# frozen_string_literal: true

DiscourseDigest::Engine.routes.draw do
  # define routes here
end

Discourse::Application.routes.draw { mount ::DiscourseDigest::Engine, at: "/discourse-daily-digest" }
