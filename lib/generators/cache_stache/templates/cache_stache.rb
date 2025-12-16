# frozen_string_literal: true

# CacheStache Configuration
# This file configures the CacheStache cache hit rate monitoring system.

CacheStache.configure do |config|
  # Redis connection for storing cache metrics
  # Falls back to ENV["REDIS_URL"] if not set
  config.redis_url = ENV.fetch("CACHE_STACHE_REDIS_URL", ENV["REDIS_URL"])

  # Size of time buckets for aggregation (default: 5 minutes)
  config.bucket_seconds = 5.minutes

  # How long to retain data (default: 7 days)
  config.retention_seconds = 7.days

  # Sample rate (0.0 to 1.0). Use < 1.0 for high-traffic apps (default: 1.0)
  config.sample_rate = 1.0

  # Enable/disable instrumentation (default: true)
  # Set to false in test environment if desired
  config.enabled = !Rails.env.test?

  # Defer stats increments until after the response is sent, via Rack's
  # `env["rack.after_reply"]` (supported by Puma and others).
  # Default: false
  config.use_rack_after_reply = false

  # Define keyspaces to track specific cache key patterns
  # Each keyspace uses a regex to match cache keys
  #
  # Example:
  #
  # config.keyspace :profiles do
  #   label "Profile Fragments"
  #   match /^profile:/
  # end
  #
  # config.keyspace :search do
  #   label "Search Results"
  #   match %r{/search/}
  # end
end
