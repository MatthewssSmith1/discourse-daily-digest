# frozen_string_literal: true

module DiscourseDigest
  class OpenaiService
    CHAT_API_ENDPOINT = 'https://api.openai.com/v1/chat/completions'

    def self.chat_completion(messages, schema, schema_name)
      api_key = SiteSetting.openai_api_key
      if api_key.blank?
        raise StandardError.new('OpenAI API key not configured')
      end

      payload = {
        "model" => SiteSetting.openai_model,
        "temperature" => SiteSetting.openai_temperature,
        "messages" => messages,
        "response_format" => {
          "type" => "json_schema",
          "json_schema" => {
            "name" => schema_name,
            "schema" => {
              "type" => "object",
              "properties" => schema,
              "required" => schema.keys,
              "additionalProperties" => false
            }
          }
        }
      }

      response = Faraday.post(
        CHAT_API_ENDPOINT,
        payload.to_json,
        {
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{api_key}"
        }
      )

      if response.status != 200
        raise StandardError.new("OpenAI API request failed: #{response.body}")
      end

      body = JSON.parse(response.body)
      JSON.parse(body['choices'].first['message']['content'])
    end
  end
end
