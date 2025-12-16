# frozen_string_literal: true

module CacheStache
  module Instrumentation
    # Thread-local key to track when CacheStache is performing internal operations
    INTERNAL_OPERATION_KEY = :cache_stache_internal_operation
    AFTER_REPLY_QUEUE_KEY = :cache_stache_after_reply_queue
    MAX_AFTER_REPLY_EVENTS = 1000

    class << self
      attr_reader :monitored_store_class

      def reset!
        @installed = false
        @monitored_store_class = nil
        @cache_client = nil
      end

      def install!
        return unless CacheStache.configuration.enabled
        return if @installed

        # Store cache_client as a class instance variable
        @cache_client = CacheClient.new
        @cache_client.store_config_metadata

        # Capture the Rails.cache store class name to filter events.
        # Note: This filters by class name, not instance. If multiple stores
        # use the same class (e.g., two RedisCacheStore instances), events
        # from all of them will be tracked.
        @monitored_store_class = Rails.cache.class.name

        # Subscribe to cache read events only (hits and misses)
        ActiveSupport::Notifications.subscribe("cache_read.active_support", self)

        @installed = true
        Rails.logger.info("CacheStache: Instrumentation installed for #{@monitored_store_class}")
      end

      # Execute a block while marking it as an internal CacheStache operation.
      # Cache operations inside this block will be ignored by instrumentation.
      def without_instrumentation
        previous_value = Thread.current[INTERNAL_OPERATION_KEY]
        Thread.current[INTERNAL_OPERATION_KEY] = true
        yield
      ensure
        Thread.current[INTERNAL_OPERATION_KEY] = previous_value
      end

      # Returns true if we're currently inside an internal CacheStache operation
      def internal_operation?
        Thread.current[INTERNAL_OPERATION_KEY] == true
      end

      def call(_name, _start, _finish, _id, payload)
        # Skip if this is an internal CacheStache operation
        return if internal_operation?

        # Only track events from Rails.cache, not other ActiveSupport::Cache instances
        return unless payload[:store] == @monitored_store_class

        key = payload[:key] || payload[:name]
        return unless key
        # Belt-and-suspenders: also skip by key prefix in case thread-local wasn't set
        return if key.to_s.start_with?("cache_stache:")

        # Skip event based on sample_rate (e.g., 0.5 means record 50% of events)
        sample_rate = CacheStache.configuration.sample_rate
        return if sample_rate < 1.0 && rand >= sample_rate

        # Record hit or miss
        bucket_ts = (Time.current.to_i / CacheStache.configuration.bucket_seconds) * CacheStache.configuration.bucket_seconds
        hit = payload[:hit]

        increments = {
          "overall:hits" => hit ? 1 : 0,
          "overall:misses" => hit ? 0 : 1
        }

        # Add keyspace increments
        matching_keyspaces = CacheStache.configuration.matching_keyspaces(key)
        matching_keyspaces.each do |keyspace|
          increments["#{keyspace.name}:hits"] = hit ? 1 : 0
          increments["#{keyspace.name}:misses"] = hit ? 0 : 1
        end

        # Filter out zero-valued fields to reduce write amplification
        increments.reject! { |_k, v| v == 0 }

        if should_defer_instrumentation?
          enqueue_after_reply_event(bucket_ts, increments)
        else
          @cache_client.increment_stats(bucket_ts, increments)
        end
      rescue => e
        Rails.logger.error("CacheStache instrumentation error: #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
      end

      def flush_after_reply_queue!
        return unless @cache_client
        queue = Thread.current[AFTER_REPLY_QUEUE_KEY]
        return unless queue.is_a?(Array) && !queue.empty?

        max = MAX_AFTER_REPLY_EVENTS
        dropped = [queue.size - max, 0].max
        events = queue.shift([queue.size, max].min)
        queue.clear

        Rails.logger.warn("CacheStache: Dropped #{dropped} after-reply events") if dropped.positive?

        combined = {}
        events.each do |(bucket_ts, increments)|
          combined[bucket_ts] ||= Hash.new(0)
          increments.each do |field, value|
            combined[bucket_ts][field] += value
          end
        end

        combined.each do |bucket_ts, increments|
          # Filter out zero-valued fields to reduce write amplification
          increments.reject! { |_k, v| v == 0 }
          @cache_client.increment_stats(bucket_ts, increments)
        end
      rescue => e
        Rails.logger.error("CacheStache after-reply flush error: #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n"))
      end

      private

      def should_defer_instrumentation?
        CacheStache.configuration.use_rack_after_reply
      end

      def enqueue_after_reply_event(bucket_ts, increments)
        Thread.current[AFTER_REPLY_QUEUE_KEY] ||= []
        Thread.current[AFTER_REPLY_QUEUE_KEY] << [bucket_ts, increments]
      end
    end
  end
end
