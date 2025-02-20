# frozen_string_literal: true

module Jobs
  class GenerateDailyDigest < ::Jobs::Scheduled
    daily at: 11.hours

    def execute(args)
      unless SiteSetting.daily_digest_enabled
        Rails.logger.warn("Daily digest is disabled, skipping")
        return
      end

      begin
        generator = DiscourseDigest::DigestGenerator.new
        generator.generate_and_post
      rescue StandardError => e
        Rails.logger.error("Error generating daily digest: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end
  end
end
