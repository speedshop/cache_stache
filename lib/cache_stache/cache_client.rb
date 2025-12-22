# frozen_string_literal: true

require "redis"
require "connection_pool"

module CacheStache
  class CacheClient
    # Lua script for atomic increment with expiry
    INCR_AND_EXPIRE_SCRIPT = <<~LUA
      local key = KEYS[1]
      local expire_seconds = tonumber(ARGV[1])
      local increments = cjson.decode(ARGV[2])

      for field, value in pairs(increments) do
        redis.call('HINCRBYFLOAT', key, field, value)
      end

      local ttl = redis.call('TTL', key)
      if ttl == -1 or ttl < expire_seconds then
        redis.call('EXPIRE', key, expire_seconds)
      end

      return redis.status_reply('OK')
    LUA

    def initialize(config = CacheStache.configuration)
      @config = config
      @pool = ConnectionPool.new(size: @config.redis_pool_size) do
        @config.build_redis
      end
    end

    def increment_stats(bucket_ts, increments)
      key = bucket_key(bucket_ts)

      without_instrumentation do
        @pool.with do |redis|
          Rails.logger.debug { "CacheStache: Redis EVAL increment on #{key} with #{increments.size} fields" }
          redis.eval(
            INCR_AND_EXPIRE_SCRIPT,
            keys: [key],
            argv: [@config.retention_seconds, increments.to_json]
          )
        end
      end
    rescue => e
      Rails.logger.error("CacheStache: Failed to increment stats: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end

    def fetch_buckets(from_ts, to_ts)
      keys = bucket_keys_in_range(from_ts, to_ts)
      return [] if keys.empty?

      Rails.logger.debug { "CacheStache: Redis fetching #{keys.size} buckets from #{from_ts} to #{to_ts}" }

      without_instrumentation do
        @pool.with do |redis|
          Rails.logger.debug { "CacheStache: Redis PIPELINE hgetall for #{keys.size} keys" }
          pipeline_results = redis.pipelined do |pipe|
            keys.each { |key| pipe.hgetall(key) }
          end

          keys.zip(pipeline_results).map do |key, data|
            next unless data && !data.empty?

            {
              timestamp: extract_timestamp_from_key(key),
              stats: data.transform_values(&:to_f)
            }
          end.compact
        end
      end
    rescue => e
      Rails.logger.error("CacheStache: Failed to fetch buckets: #{e.message}")
      []
    end

    def store_config_metadata
      key = "cache_stache:v1:#{@config.rails_env}:config"
      metadata = {
        bucket_seconds: @config.bucket_seconds,
        retention_seconds: @config.retention_seconds,
        updated_at: Time.current.to_i
      }

      without_instrumentation do
        @pool.with do |redis|
          # Use SETEX for atomic set-with-expiry (single command)
          Rails.logger.debug { "CacheStache: Redis SETEX #{key} #{@config.retention_seconds}" }
          redis.setex(key, @config.retention_seconds, metadata.to_json)
        end
      end
    rescue => e
      Rails.logger.error("CacheStache: Failed to store config metadata: #{e.message}")
    end

    def fetch_config_metadata
      key = "cache_stache:v1:#{@config.rails_env}:config"

      without_instrumentation do
        @pool.with do |redis|
          Rails.logger.debug { "CacheStache: Redis GET #{key}" }
          data = redis.get(key)
          data ? JSON.parse(data) : nil
        end
      end
    rescue => e
      Rails.logger.error("CacheStache: Failed to fetch config metadata: #{e.message}")
      nil
    end

    def estimate_storage_size
      # Calculate theoretical number of buckets
      max_buckets = (@config.retention_seconds.to_f / @config.bucket_seconds).ceil

      # Each bucket has:
      # - overall:hits and overall:misses (2 fields)
      # - keyspace_name:hits and keyspace_name:misses per keyspace (2 * num_keyspaces)
      fields_per_bucket = 2 + (@config.keyspaces.size * 2)

      # Estimate bytes per field:
      # - Field name: ~20 bytes average (e.g., "search:hits", "profiles:misses")
      # - Field value: ~8 bytes (float stored as string, e.g., "12345.0")
      # - Redis hash overhead: ~24 bytes per field
      bytes_per_field = 52

      # Key overhead: "cache_stache:v1:environment:timestamp" ~45 bytes
      # Plus Redis key overhead: ~96 bytes
      key_overhead = 141

      # Calculate total size per bucket
      bytes_per_bucket = (fields_per_bucket * bytes_per_field) + key_overhead

      # Total estimated size
      total_bytes = max_buckets * bytes_per_bucket

      # Add config metadata key size (~200 bytes)
      total_bytes += 200

      {
        max_buckets: max_buckets,
        fields_per_bucket: fields_per_bucket,
        bytes_per_bucket: bytes_per_bucket,
        total_bytes: total_bytes,
        human_size: format_bytes(total_bytes)
      }
    rescue => e
      Rails.logger.error("CacheStache: Failed to estimate storage size: #{e.message}")
      {total_bytes: 0, human_size: "Unknown"}
    end

    private

    def format_bytes(bytes)
      if bytes < 1024
        "#{bytes} B"
      elsif bytes < 1024 * 1024
        "#{(bytes / 1024.0).round(1)} KB"
      elsif bytes < 1024 * 1024 * 1024
        "#{(bytes / (1024.0 * 1024)).round(2)} MB"
      else
        "#{(bytes / (1024.0 * 1024 * 1024)).round(2)} GB"
      end
    end

    def bucket_key(timestamp)
      "cache_stache:v1:#{@config.rails_env}:#{timestamp}"
    end

    def bucket_keys_in_range(from_ts, to_ts)
      timestamps = []
      current = align_to_bucket(from_ts)
      to_aligned = align_to_bucket(to_ts)

      while current <= to_aligned
        timestamps << current
        current += @config.bucket_seconds
      end

      # Limit to most recent max_buckets
      if timestamps.size > @config.max_buckets
        Rails.logger.warn("CacheStache: Truncating bucket range from #{timestamps.size} to #{@config.max_buckets} buckets (requested #{from_ts} to #{to_ts})")
        timestamps = timestamps.last(@config.max_buckets)
      end

      timestamps.map { |ts| bucket_key(ts) }
    end

    def align_to_bucket(timestamp)
      (timestamp.to_i / @config.bucket_seconds) * @config.bucket_seconds
    end

    def extract_timestamp_from_key(key)
      key.split(":").last.to_i
    end

    def without_instrumentation(&block)
      CacheStache::Instrumentation.without_instrumentation(&block)
    end
  end
end
