# frozen_string_literal: true

module Jobs
  class GenerateDailyDigest < ::Jobs::Scheduled
    every 1.day

    def execute(args)
      unless SiteSetting.daily_digest_enabled
        Rails.logger.info("Daily digest is disabled, skipping")
        return
      end

      # Check if it's time to post
      # current_time = Time.now
      # target_time = Time.parse(SiteSetting.daily_digest_post_time)
      # return unless current_time.hour == target_time.hour && current_time.min < 15

      begin
        generator = DiscourseDigest::DigestGenerator.new
        generator.generate_and_post
      rescue StandardError => e
        Rails.logger.error("Error generating daily digest: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        raise e  
      end
    end
  end
end
