# frozen_string_literal: true

# name: discourse-daily-digest
# about: Generate scheduled posts summarizing multiple news sources
# meta_topic_id: TODO
# version: 0.0.1
# authors: Matt Smith
# url: https://github.com/MatthewssSmith1/discourse-daily-digest
# required_version: 2.7.0
# depends_on: discourse-ai

enabled_site_setting :daily_digest_enabled

gem 'feedjira', '3.2.4'
gem 'faraday', '2.12.2'

module ::DiscourseDigest
  PLUGIN_NAME = "discourse-daily-digest"
end

require_relative "lib/discourse_digest/engine"

after_initialize do
  # Load our dependencies
  require_dependency File.expand_path('../app/jobs/scheduled/generate_daily_digest', __FILE__)
  require_dependency File.expand_path('../app/services/discourse_digest/digest_generator', __FILE__)
end
