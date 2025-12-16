# frozen_string_literal: true

module CacheStache
  class ApplicationController < ActionController::Base
    layout "cache_stache/application"
    helper CacheStache::ApplicationHelper
    append_view_path CacheStache::Engine.root.join("app/views")

    protect_from_forgery with: :exception
  end
end
