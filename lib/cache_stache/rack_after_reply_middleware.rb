# frozen_string_literal: true

module CacheStache
  class RackAfterReplyMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless CacheStache.configuration.use_rack_after_reply

      Thread.current[CacheStache::Instrumentation::AFTER_REPLY_QUEUE_KEY] = []

      env["rack.after_reply"] ||= []
      env["rack.after_reply"] << lambda do
        CacheStache::Instrumentation.flush_after_reply_queue!
      end

      @app.call(env)
    end
  end
end
