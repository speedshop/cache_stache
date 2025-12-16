# frozen_string_literal: true

require "pathname"
require "rails/engine"

module CacheStache
  class Engine < ::Rails::Engine
    isolate_namespace CacheStache

    # Engine root is lib/cache_stache/
    config.root = Pathname.new(File.expand_path("../..", __dir__))

    initializer "cache_stache.assets.precompile" do |app|
      app.config.assets.precompile += %w[cache_stache/pico.css cache_stache/application.css]
    end
  end
end
