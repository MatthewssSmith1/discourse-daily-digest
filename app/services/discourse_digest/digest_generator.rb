# frozen_string_literal: true

module DiscourseDigest
  class DigestGenerator
    AUDIENCE_DESCRIPTION = "Your audience consists of AI professionals - engineers and entrepreneurs - with deep technical expertise in the field. They follow major developments in AI and are fluent in technical terminology. Focus on significant technical and industry developments rather than introductory content or niche applications."
    
    def generate_and_post
      articles = fetch_news_articles
      if articles.empty?
        Rails.logger.error('No articles fetched from NewsAPI.')
        return
      end

      Rails.logger.info("Fetched #{articles.size} articles.")

      stories = articles_to_stories(articles)
      if stories.empty?
        Rails.logger.error('No stories passed filtering.')
        return
      end

      Rails.logger.info("Created #{stories.size} stories from articles.")

      stories.each do |story|
        post_story(story)
      end
    end

    private

    def fetch_news_articles
      api_key = SiteSetting.news_api_key
      if api_key.blank?
        Rails.logger.error('News API key not configured')
        return []
      end

      # Load from static JSON file
      # path = File.join(Rails.root, 'plugins', 'discourse-daily-digest', 'docs', 'news_api_response.json')
      # return JSON.parse(File.read(path))['articles'] || []

      from_date = (Time.now - 24*60*60).iso8601
      response = Faraday.get("https://newsapi.org/v2/everything?q=Artificial%20Intelligence&from=#{from_date}&sortBy=relevancy&language=en&apiKey=#{api_key}")

      unless response.success?
        Rails.logger.error("NewsAPI error: #{response.status} - #{response.body}")
        return []
      end

      JSON.parse(response.body)['articles'] || []
    end

    # TODO: include recent daily-digest stories to avoid repeats
    def articles_to_stories(articles)
      system_prompt = <<~PROMPT
        You are an expert news curator with a focus on Artificial Intelligence. #{AUDIENCE_DESCRIPTION} 

        Your task is to analyze the provided JSON array of news articles and identify the two most significant AI-related stories. For each story:
        - Provide a brief explanation of its relevance
        - Create a clear, informative title
        - List 1-3 of the provided article URLs from the most authoritative sources

        Selection criteria:
        - Stories must represent new developments in frontier AI technology or its business applications
        - Impact should be broad and significant to the AI field and world at large, avoiding niche topics
        - Content should be factual and objective, avoiding speculation and personal opinions

        If multiple articles cover the same story, synthesize their information into a single comprehensive entry while citing all relevant sources.
      PROMPT

      json_articles = articles.map do |article|
        {
          title: article['title'],
          description: article['description'],
          url: article['url']
        }
      end.to_json

      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: "Pick the two most significant stories based on these articles: #{json_articles}" }
      ]

      story_schema = {
        "type" => "object",
        "properties" => {
          "explanation" => { "type" => "string" },
          "title" => { "type" => "string" },
          "urls" => {
            "type" => "array",
            "items" => { "type" => "string" }
          }
        },
        "required" => ["explanation", "title", "urls"],
        "additionalProperties" => false
      }

      schema = {
        "stories" => {
          "type" => "array",
          "items" => story_schema
        }
      }

      begin
        response = DiscourseDigest::OpenaiService.chat_completion(messages, schema, "story_evaluations")

        response["stories"].map do |story|
          {
            title: story['title'],
            articles: articles.select { |a| story['urls'].include?(a['url']) }
          }
        end
      rescue => e
        Rails.logger.error("Error during story filtering: #{e.message}")
        []
      end
    end

    def post_story(story)
      system_prompt = <<~PROMPT
        You are an expert in summarizing news stories related to Artificial Intelligence. #{AUDIENCE_DESCRIPTION} 

        You will receive JSON containing one or more related articles. Analyze these articles and return a JSON response with the following fields:
        - title: A clear, concise title in plain text (no markdown)
        - summary: A focused summary in markdown format, containing 2-3 bullet points highlighting key technical details and implications
        - sources: A markdown bullet point list of the source URLs from the provided articles

        Your summaries should emphasize technical substance and business impact while avoiding surface-level explanations. Keep the bullet points short and to the point.
      PROMPT

      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: "Analyze and summarize the following articles: #{story.to_json}" }
      ]

      schema = {
        "title" => { "type" => "string" },
        "summary" => { "type" => "string" },
        "sources" => { "type" => "string" }
      }

      begin
        response = DiscourseDigest::OpenaiService.chat_completion(messages, schema, 'story_summary')
      rescue => e
        Rails.logger.error("Error during story summary generation: #{e.message}")
        return
      end

      category = Category.find_by(id: SiteSetting.daily_digest_category_id)
      unless category
        Rails.logger.error("Could not find category with ID: #{SiteSetting.daily_digest_category_id}")
        return
      end

      creator = PostCreator.new(
        Discourse.system_user,
        category: category.id,
        title: response["title"],
        raw: "## Summary\n#{response["summary"]}\n\n## Sources\n#{response["sources"]}",
        tags: [SiteSetting.daily_digest_tag],
        skip_validations: true
      )

      post = creator.create
      if post.present? && post.persisted?
        Rails.logger.warn("Successfully created daily digest post: #{post.url}")
      else
        Rails.logger.error("Failed to create daily digest post. Errors: #{creator.errors.full_messages.join(", ")}")
      end
    end
  end
end
