# frozen_string_literal: true

require "digest/md5"
require "active_support/core_ext/numeric/time"

module CacheStache
  class Configuration
    attr_accessor :bucket_seconds, :retention_seconds, :sample_rate, :enabled,
      :redis_url, :redis_pool_size, :use_rack_after_reply, :max_buckets
    attr_reader :keyspaces

    def initialize
      @bucket_seconds = 5.minutes.to_i
      @retention_seconds = 7.days.to_i
      @sample_rate = 1.0
      @enabled = rails_env != "test"
      @use_rack_after_reply = false
      @redis_url = ENV.fetch("CACHE_STACHE_REDIS_URL") { ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
      @redis_pool_size = 5
      @max_buckets = 288
      @keyspaces = []
      @keyspace_cache = {}
    end

    def keyspace(name, &block)
      ks = Keyspace.new(name)
      builder = KeyspaceBuilder.new(ks)
      builder.instance_eval(&block) if block_given?
      ks.validate!

      raise Error, "Keyspace #{name} already defined" if @keyspaces.any? { |k| k.name == name }

      @keyspaces << ks
      ks
    end

    def matching_keyspaces(key)
      # Simple memoization per key to avoid repeated block execution
      cache_key = key_digest(key)
      @keyspace_cache[cache_key] ||= @keyspaces.select { |ks| ks.match?(key) }
    end

    def validate!
      raise Error, "bucket_seconds must be positive" unless bucket_seconds.to_i.positive?
      raise Error, "retention_seconds must be positive" unless retention_seconds.to_i.positive?
      raise Error, "redis_pool_size must be positive" unless redis_pool_size.to_i.positive?
      raise Error, "redis_url must be configured" if redis_url.to_s.strip.empty?
      raise Error, "sample_rate must be between 0 and 1" unless sample_rate&.between?(0, 1)
      raise Error, "max_buckets must be positive" unless max_buckets.to_i.positive?

      if retention_seconds % bucket_seconds != 0
        Rails.logger.warn(
          "CacheStache: retention_seconds (#{retention_seconds}) does not divide evenly " \
          "by bucket_seconds (#{bucket_seconds}). This may result in partial bucket retention."
        )
      end

      @keyspaces.each(&:validate!)
    end

    def rails_env
      @rails_env ||= ENV.fetch("RAILS_ENV", "development")
    end

    private

    def key_digest(key)
      # Use last 4 chars of a simple hash as cache key
      Digest::MD5.hexdigest(key.to_s)[-4..]
    end

    class KeyspaceBuilder
      def initialize(keyspace)
        @keyspace = keyspace
      end

      def label(value)
        @keyspace.label = value
      end

      def match(regex)
        raise Error, "match requires a Regexp argument, got #{regex.class}" unless regex.is_a?(Regexp)
        @keyspace.pattern = regex
      end
    end
  end
end
