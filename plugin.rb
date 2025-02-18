# frozen_string_literal: true

# name: discourse-daily-digest
# about: Generate scheduled posts summarizing multiple news sources
# meta_topic_id: TODO
# version: 0.0.1
# authors: Matt Smith
# url: https://github.com/MatthewssSmith1/discourse-daily-digest
# required_version: 2.7.0

enabled_site_setting :plugin_name_enabled

module ::MyPluginModule
  PLUGIN_NAME = "discourse-daily-digest"
end

require_relative "lib/my_plugin_module/engine"

after_initialize do
  # Code which should run after Rails has finished booting
end
