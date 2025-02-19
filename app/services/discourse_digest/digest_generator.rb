# frozen_string_literal: true

module DiscourseDigest
  class DigestGenerator
    def generate_and_post
      content = generate_content
      if content.present?
        create_post(content)
      end
    end

    private

    def generate_content
      sources = parse_sources
      return if sources.empty?

      content = []
      sources.each do |source|
        items = fetch_source_content(source)
        next if items.empty?
        content << process_items(source, items)
      end

      return if content.empty?
      summarize_with_ai(content.join("\n\n"))
    end

    def parse_sources
      sources_setting = SiteSetting.daily_digest_sources
      sources_setting.split("|").each_slice(2).map do |name, url|
        { name: name, url: url }
      end
    end

    def fetch_source_content(source)
      response = Faraday.get(source[:url])
      unless response.success?
        Rails.logger.error("Failed to fetch from #{source[:name]}, status: #{response.status}")
        return []
      end

      feed = Feedjira.parse(response.body)
      max_items = SiteSetting.daily_digest_max_items_per_source
      feed.entries.first(max_items)
    rescue => e
      Rails.logger.error("Error fetching content from #{source[:name]}: #{e.message}")
      []
    end

    def process_items(source, items)
      content = "## #{source[:name].titleize}\n\n"
      items.each do |item|
        content << "* [#{item.title}](#{item.url})\n"
      end
      content
    end

    def summarize_with_ai(content)
      api_key = SiteSetting.ai_openai_api_key
      
      if api_key.blank?
        Rails.logger.error("OpenAI API key not configured")
        return content
      end

      prompt = <<~PROMPT
        Here is a list of news items from various sources. Please create a concise and engaging summary
        that highlights the most interesting and important items. Focus on providing value to readers
        while maintaining a neutral tone. Format the response in Markdown.

        News items:
        #{content}
      PROMPT

      begin
        response = Faraday.post(
          'https://api.openai.com/v1/chat/completions',
          {
            model: "gpt-4o",
            messages: [{ role: "user", content: prompt }],
            temperature: 0.7
          }.to_json,
          {
            'Authorization' => "Bearer #{api_key}",
            'Content-Type' => 'application/json'
          }
        )
        
        if response.success?
          data = JSON.parse(response.body)
          summarized_content = data.dig("choices", 0, "message", "content")
          return summarized_content if summarized_content.present?
        else
          Rails.logger.error("OpenAI API error: #{response.status} - #{response.body}")
        end
      rescue StandardError => e
        Rails.logger.error("Error during OpenAI request: #{e.message}")
      end

      content
    end

    def create_post(content)
      category = Category.find_by(id: SiteSetting.daily_digest_category_id)
      unless category
        Rails.logger.error("Could not find category with ID: #{SiteSetting.daily_digest_category_id}")
        return
      end

      title = I18n.t(
        SiteSetting.daily_digest_post_title_template,
        date: I18n.l(Time.now.to_date, format: '%B %-d, %Y')
      )

      creator = PostCreator.new(
        Discourse.system_user,
        raw: content,
        title: title,
        category: category.id,
        tags: [SiteSetting.daily_digest_tag],
        skip_validations: true
      )

      post = creator.create
      
      if post.present? && post.persisted?
        Rails.logger.info("Successfully created daily digest post: #{post.url}")
      else
        Rails.logger.error("Failed to create daily digest post. Errors: #{creator.errors.full_messages.join(", ")}")
      end
    end
  end
end
