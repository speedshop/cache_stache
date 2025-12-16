# frozen_string_literal: true

require_relative "boot"

require "pathname"
require "logger"
require "rails"
require "rails/engine"
require "active_support/all"
require "action_dispatch/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "sprockets/railtie"

require "cache_stache"
require "cache_stache/web"
require "cache_stache/engine"
require "cache_stache/railtie"

module CacheStacheDummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.root = Pathname.new(File.expand_path("..", __dir__))

    config.eager_load = false
    config.cache_store = :memory_store
    config.logger = Logger.new(nil)
    config.active_support.deprecation = :log
    config.secret_key_base = "cache-stache-test"
  end
end
