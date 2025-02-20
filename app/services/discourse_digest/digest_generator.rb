# frozen_string_literal: true

module DiscourseDigest
  class DigestGenerator
    def generate_and_post
      articles = fetch_news_articles
      if articles.empty?
        ::Rails.logger.error('No articles fetched from NewsAPI.')
        return
      end

      ::Rails.logger.info("Fetched #{articles.size} articles.")

      stories = filter_stories(articles)
      if stories.empty?
        ::Rails.logger.error('No stories passed filtering.')
        return
      end

      ::Rails.logger.info("Created #{stories.size} stories from articles.")

      stories.each do |story|
        post_story(story)
      end
    end

    private

    def fetch_news_articles
      api_key = SiteSetting.newsapi_api_key
      if api_key.blank?
        ::Rails.logger.error('NewsAPI API key not configured')
        return []
      end

      # Load from static JSON file
      # file_path = File.join(Rails.root, 'plugins', 'discourse-daily-digest', 'app', 'services', 'discourse_digest', 'newsapi_example_response.json')
      # json_data = File.read(file_path)
      # body = JSON.parse(json_data)

      from_date = (Time.now - 24*60*60).iso8601
      query = CGI.escape('Artificial Intelligence')
      response = Faraday.get("https://newsapi.org/v2/everything?q=#{query}&from=#{from_date}&sortBy=relevancy&language=en&apiKey=#{api_key}")

      unless response.success?
        ::Rails.logger.error("NewsAPI error: #{response.status} - #{response.body}")
        return []
      end

      JSON.parse(response.body)['articles'] || []
    end

    def filter_stories(articles)
      return [] if articles.empty?

      mapped_articles = articles.map do |article|
        {
          title: article['title'],
          description: article['description'],
          url: article['url']
        }
      end

      system_prompt = <<~PROMPT
        You are an expert news curator with a focus on Artificial Intelligence. 
        Your audience is a group of expert AI engineers and entrepreneurs who are interested in the biggest developments in AI; they don't care about articles written for laypeople.

        # Goal
        You will be provided with a JSON array of news articles; your task is to pick the three best stories that meet the following criteria:
        - objective, avoiding speculation and personal opinions
        - have a large impact on the world as a whole, not just a niche story
        - either a new development that advances AI technology or its business application

        Multiple articles may be about the same story, in which case you should combine their information and return the most relevant urls.
      PROMPT

      user_prompt = <<~PROMPT
        # ARTICLE LIST
        #{mapped_articles.to_json}

        # INSTRUCTIONS
        Pick the three best stories for an audience of expert AI engineers and entrepreneurs. For each one, return a brief explanation of why the story is relevant, followed by a title for the story and an array of source urls.
      PROMPT

      begin
        response = Faraday.post(
          'https://api.openai.com/v1/chat/completions',
          {
            model: "gpt-4o",
            temperature: 0.7,
            messages: [
              { role: "system", content: system_prompt },
              { role: "user", content: user_prompt }
            ],
            response_format: {
              "type": "json_schema",
              "json_schema": {
                "name": "story_evaluations",
                "schema": {
                  "type": "object",
                  "properties": {
                    "stories": {
                      "type": "array",
                      "items": {
                        "type": "object",
                        "properties": {
                          "explanation": { "type": "string" },
                          "title": { "type": "string" },
                          "urls": {
                            "type": "array",
                            "items": { "type": "string" }
                          }
                        },
                        "required": ["explanation", "title", "urls"],
                        "additionalProperties": false
                      }
                    }
                  },
                  "required": ["stories"],
                  "additionalProperties": false
                }
              }
            }
          }.to_json,
          {
            'Authorization' => "Bearer #{SiteSetting.ai_openai_api_key}",
            'Content-Type' => 'application/json'
          }
        )

        response_body = JSON.parse(response.body)

        if !response.success?
          error_message = response_body["error"]&.[]("message") || "Unknown error"
          ::Rails.logger.error("OpenAI error: #{error_message}")
          return []
        end

        JSON.parse(response_body["choices"][0]["message"]["content"])["stories"].map do |story|
          {
            title: story['title'],
            articles: articles.select { |a| story['urls'].include?(a['url']) }
          }
        end
      rescue => e
        ::Rails.logger.error("Error during story filtering: #{e.message}")
        []
      end
    end

    def post_story(story)
      response = Faraday.post(
        'https://api.openai.com/v1/chat/completions',
        {
          model: "gpt-4o",
          temperature: 0.7,
          messages: [
            { 
              role: "system", 
              content: "You are a helpful assistant that generates engaging article summaries. When provided a story containing multiple related articles, generate a comprehensive summary that combines their information into a cohesive narrative. Include links to all source articles at the end." 
            },
            { 
              role: "user", 
              content: "# Story JSON\n#{story.to_json}\n\n# Instructions\nCreate a comprehensive summary combining information from all articles in this story. The content should be in markdown format with links to all source articles at the end." 
            }
          ],
          response_format: {
            "type": "json_schema",
            "json_schema": {
              "name": "story_summary",
              "schema": {
                "type": "object",
                "properties": {
                  "title": { "type": "string" },
                  "content": { "type": "string" }
                },
                "required": ["title", "content"],
                "additionalProperties": false
              }
            }
          }
        }.to_json,
        {
          'Authorization' => "Bearer #{SiteSetting.ai_openai_api_key}",
          'Content-Type' => 'application/json'
        }
      )

      response_body = JSON.parse(response.body)

      if !response.success?
        error_message = response_body["error"]&.[]("message") || "Unknown error"
        ::Rails.logger.error("OpenAI error: #{error_message}")
        return
      end

      summary = JSON.parse(response_body["choices"][0]["message"]["content"])

      category = Category.find_by(id: SiteSetting.daily_digest_category_id)
      unless category
        ::Rails.logger.error("Could not find category with ID: #{SiteSetting.daily_digest_category_id}")
        return
      end

      creator = PostCreator.new(
        Discourse.system_user,
        category: category.id,
        raw: summary["content"],
        title: summary["title"],
        tags: [SiteSetting.daily_digest_tag],
        skip_validations: true
      )

      post = creator.create
      if post.present? && post.persisted?
        ::Rails.logger.warn("Successfully created daily digest post: #{post.url}")
      else
        ::Rails.logger.error("Failed to create daily digest post. Errors: #{creator.errors.full_messages.join(", ")}")
      end
    end
  end
end
