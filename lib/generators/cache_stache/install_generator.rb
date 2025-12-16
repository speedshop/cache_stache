# frozen_string_literal: true

require "rails/generators"

module CacheStache
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates a CacheStache initializer and mounts the dashboard"

      def copy_initializer
        template "cache_stache.rb", "config/initializers/cache_stache.rb"
      end

      def show_readme
        readme "README" if behavior == :invoke
      end
    end
  end
end
