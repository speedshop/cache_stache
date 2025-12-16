# frozen_string_literal: true

require "active_support/all"

require_relative "cache_stache/version"
require_relative "cache_stache/window_options"
require_relative "cache_stache/configuration"
require_relative "cache_stache/keyspace"
require_relative "cache_stache/cache_client"
require_relative "cache_stache/instrumentation"
require_relative "cache_stache/stats_query"
require_relative "cache_stache/rack_after_reply_middleware"

module CacheStache
  class Error < StandardError; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
      configuration.validate!
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

require_relative "cache_stache/railtie"
require_relative "cache_stache/engine"
require_relative "cache_stache/web"
