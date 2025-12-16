# frozen_string_literal: true

require_relative "engine"

module CacheStache
  class Web
    class << self
      def call(env)
        ensure_routes_loaded!

        # Build app only once and cache it
        unless @app
          # Capture middlewares outside the Rack::Builder context
          mw = middlewares

          @app = Rack::Builder.new do
            mw.each { |middleware, args, block| use(middleware, *args, &block) }
            run CacheStache::Engine
          end.to_app

          Rails.logger.info "[CacheStache::Web] Rack app built successfully"
        end

        @app.call(env)
      end

      def use(middleware, *args, &block)
        middlewares << [middleware, args, block]
      end

      def middlewares
        @middlewares ||= []
      end

      def reset_middlewares!
        @middlewares = []
        @app = nil
      end

      def reset_routes!
        @routes_loaded = false
        @app = nil
      end

      private

      def ensure_routes_loaded!
        return if @routes_loaded

        routes_path = File.expand_path("../../config/routes.rb", __dir__)
        load_engine_components
        load routes_path
        @routes_loaded = true
      end

      def load_engine_components
        base_path = File.expand_path("../../app", __dir__)

        Dir["#{base_path}/helpers/**/*.rb"].sort.each do |file|
          load file
        end

        Dir["#{base_path}/controllers/**/*.rb"].sort.each do |file|
          load file
        end
      end
    end
  end
end
