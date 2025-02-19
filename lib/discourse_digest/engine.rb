# frozen_string_literal: true

module ::DiscourseDigest
  class Engine < ::Rails::Engine
    engine_name "discourse_daily_digest"
    isolate_namespace DiscourseDigest
    config.autoload_paths << File.join(config.root, "lib")
    scheduled_job_dir = "#{config.root}/app/jobs/scheduled"
    config.to_prepare do
      Rails.autoloaders.main.eager_load_dir(scheduled_job_dir) if Dir.exist?(scheduled_job_dir)
    end
  end
end
