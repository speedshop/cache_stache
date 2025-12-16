# frozen_string_literal: true

namespace :cache_stache do
  desc "Prune old CacheStache data from Redis"
  task prune: :environment do
    require "redis"

    config = CacheStache.configuration
    redis = Redis.new(url: config.redis_url)

    pattern = "cache_stache:v1:#{config.rails_env}:*"
    cutoff_time = Time.current.to_i - config.retention_seconds

    pruned_count = 0
    redis.scan_each(match: pattern) do |key|
      # Extract timestamp from key
      timestamp = key.split(":").last.to_i

      if timestamp < cutoff_time
        redis.del(key)
        pruned_count += 1
      end
    end

    puts "CacheStache: Pruned #{pruned_count} old bucket(s)"
  ensure
    redis&.close
  end

  desc "Display CacheStache configuration"
  task config: :environment do
    config = CacheStache.configuration

    puts "CacheStache Configuration:"
    puts "  Redis URL: #{config.redis_url}"
    puts "  Bucket Size: #{config.bucket_seconds} seconds (#{config.bucket_seconds / 60} minutes)"
    puts "  Retention: #{config.retention_seconds} seconds (#{config.retention_seconds / 86400} days)"
    puts "  Sample Rate: #{(config.sample_rate * 100).round}%"
    puts "  Enabled: #{config.enabled}"
    puts "  Environment: #{config.rails_env}"
    puts "\nKeyspaces:"
    if config.keyspaces.any?
      config.keyspaces.each do |ks|
        puts "  - #{ks.name}: #{ks.label}"
      end
    else
      puts "  (none configured)"
    end
  end

  desc "Show current CacheStache stats"
  task stats: :environment do
    query = CacheStache::StatsQuery.new(window: 1.hour)
    results = query.execute

    puts "CacheStache Stats (last hour):"
    puts "\nOverall:"
    puts "  Total Operations: #{results[:overall][:total_operations]}"
    puts "  Hits: #{results[:overall][:hits]}"
    puts "  Misses: #{results[:overall][:misses]}"
    puts "  Hit Rate: #{results[:overall][:hit_rate_percent]}%"

    if results[:keyspaces].any?
      puts "\nKeyspaces:"
      results[:keyspaces].each do |name, stats|
        puts "  #{stats[:label]}:"
        puts "    Operations: #{stats[:total_operations]}"
        puts "    Hit Rate: #{stats[:hit_rate_percent]}%"
      end
    end

    puts "\nBuckets: #{results[:bucket_count]}"
  end
end
