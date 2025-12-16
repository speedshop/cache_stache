# frozen_string_literal: true

require "active_support/core_ext/numeric/time"

module CacheStache
  class StatsQuery
    attr_reader :window, :resolution

    def initialize(window: 1.hour, resolution: nil)
      @window = window.to_i
      @resolution = resolution
      @config = CacheStache.configuration
      @cache_client = CacheClient.new(@config)
    end

    def execute
      to_ts = Time.current.to_i
      from_ts = to_ts - window

      buckets = @cache_client.fetch_buckets(from_ts, to_ts)

      {
        overall: calculate_overall_stats(buckets),
        keyspaces: calculate_keyspace_stats(buckets),
        buckets: buckets.map { |b| format_bucket(b) },
        window_seconds: window,
        bucket_count: buckets.size
      }
    end

    private

    def calculate_overall_stats(buckets)
      total_hits = 0.0
      total_misses = 0.0

      buckets.each do |bucket|
        total_hits += bucket[:stats]["overall:hits"].to_f
        total_misses += bucket[:stats]["overall:misses"].to_f
      end

      total_ops = total_hits + total_misses
      hit_rate = total_ops.positive? ? (total_hits / total_ops * 100).round(2) : 0.0

      {
        hits: total_hits.round,
        misses: total_misses.round,
        total_operations: total_ops.round,
        hit_rate_percent: hit_rate
      }
    end

    def calculate_keyspace_stats(buckets)
      keyspace_data = {}

      @config.keyspaces.each do |keyspace|
        total_hits = 0.0
        total_misses = 0.0

        buckets.each do |bucket|
          total_hits += bucket[:stats]["#{keyspace.name}:hits"].to_f
          total_misses += bucket[:stats]["#{keyspace.name}:misses"].to_f
        end

        total_ops = total_hits + total_misses
        hit_rate = total_ops.positive? ? (total_hits / total_ops * 100).round(2) : 0.0

        keyspace_data[keyspace.name] = {
          label: keyspace.label,
          pattern: keyspace.pattern,
          hits: total_hits.round,
          misses: total_misses.round,
          total_operations: total_ops.round,
          hit_rate_percent: hit_rate
        }
      end

      keyspace_data
    end

    def format_bucket(bucket)
      {
        timestamp: bucket[:timestamp],
        time: Time.at(bucket[:timestamp]).utc,
        stats: bucket[:stats]
      }
    end
  end
end
