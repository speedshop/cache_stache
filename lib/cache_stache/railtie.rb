# frozen_string_literal: true

module CacheStache
  class Railtie < Rails::Railtie
    initializer "cache_stache.middleware", after: :load_config_initializers do |app|
      if CacheStache.configuration.use_rack_after_reply
        app.config.middleware.use(CacheStache::RackAfterReplyMiddleware)
      end
    end

    initializer "cache_stache.instrumentation", after: :load_config_initializers do
      # Install instrumentation after initializers run so user configuration is loaded
      if CacheStache.configuration.enabled
        CacheStache::Instrumentation.install!
      else
        Rails.logger.info("CacheStache: Instrumentation disabled via configuration")
      end
    end

    rake_tasks do
      load File.expand_path("../../tasks/cache_stache.rake", __dir__)
    end

    initializer "cache_stache.web_reloader" do
      ActiveSupport::Reloader.to_prepare do
        CacheStache::Web.reset_routes!
      end
    end
  end
end
