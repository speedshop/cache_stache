# frozen_string_literal: true

require_relative "spec_helper"
require "json"

# Initialize the Rails app (spec_helper loads it but doesn't initialize)
CacheStacheDummy::Application.initialize! unless CacheStacheDummy::Application.initialized?

# Load RSpec Rails integration (controller specs, etc.)
require "rspec/rails"

# Ensure the engine is loaded after Rails is initialized
require "cache_stache/engine"
load CacheStache::Engine.root.join("config/routes.rb")

# Test Redis configuration - uses database 15 to isolate from other Redis usage
CACHE_STACHE_TEST_REDIS_URL = ENV.fetch("CACHE_STACHE_TEST_REDIS_URL", "redis://localhost:6379/15")

module CacheStacheTestHelpers
  # Helper to get the test Redis connection directly
  def cache_stache_redis
    @_cache_stache_redis ||= Redis.new(url: CACHE_STACHE_TEST_REDIS_URL)
  end

  # Helper to get the current bucket key
  def current_bucket_key(bucket_seconds: 300)
    bucket_ts = (Time.current.to_i / bucket_seconds) * bucket_seconds
    "cache_stache:v1:test:#{bucket_ts}"
  end

  # Helper to get stats from current bucket
  def current_bucket_stats(bucket_seconds: 300)
    cache_stache_redis.hgetall(current_bucket_key(bucket_seconds: bucket_seconds))
  end

  # Helper to clear all CacheStache notification listeners
  def clear_cache_stache_listeners
    ActiveSupport::Notifications.notifier.listeners_for("cache_read.active_support").each do |listener|
      ActiveSupport::Notifications.unsubscribe(listener)
    end
  end

  # Helper to flush CacheStache keys from Redis
  def flush_cache_stache_redis
    redis = Redis.new(url: CACHE_STACHE_TEST_REDIS_URL)
    redis.scan_each(match: "cache_stache:*") { |key| redis.del(key) }
    redis.close
  end

  # Build a test configuration with common defaults
  def build_test_config(keyspaces: {}, **options)
    CacheStache::Configuration.new.tap do |c|
      c.redis = CACHE_STACHE_TEST_REDIS_URL
      c.bucket_seconds = options.fetch(:bucket_seconds, 300)
      c.retention_seconds = options.fetch(:retention_seconds, 3600)
      c.sample_rate = options.fetch(:sample_rate, 1.0)
      c.use_rack_after_reply = options.fetch(:use_rack_after_reply, false)
      c.enabled = options.fetch(:enabled, true)

      keyspaces.each do |name, keyspace_config|
        c.keyspace(name) do
          label keyspace_config[:label] if keyspace_config[:label]
          match keyspace_config[:match]
        end
      end
    end
  end
end

RSpec.configure do |config|
  config.include CacheStacheTestHelpers

  config.before(:suite) do
    # Verify Redis is available before running tests
    redis = Redis.new(url: CACHE_STACHE_TEST_REDIS_URL)
    begin
      redis.ping
    rescue Redis::CannotConnectError => e
      abort "CacheStache tests require a running Redis server. " \
            "Please start Redis and try again.\n" \
            "Connection error: #{e.message}"
    ensure
      redis.close
    end
  end

  config.before do
    # Configure CacheStache to use test Redis
    CacheStache.configure do |c|
      c.redis = CACHE_STACHE_TEST_REDIS_URL
      c.redis_pool_size = 1
      c.enabled = true
    end

    # Create a fresh cache client for each test
    cache_client = CacheStache::CacheClient.new(CacheStache.configuration)
    Thread.current[:cache_stache_test_client] = cache_client

    flush_cache_stache_redis
    Rails.cache.clear
    clear_cache_stache_listeners
    CacheStache::Instrumentation.reset!
  end

  config.after do
    Thread.current[:cache_stache_test_client] = nil
    Rails.cache.clear

    if defined?(@_cache_stache_redis) && @_cache_stache_redis
      @_cache_stache_redis.close
      @_cache_stache_redis = nil
    end
  end
end

# Shared context for tests that need instrumentation installed
RSpec.shared_context "with instrumentation" do
  let(:config) do
    build_test_config(
      keyspaces: {
        views: {label: "View Fragments", match: /^views\//},
        models: {label: "Model Cache", match: /community/}
      }
    )
  end

  before do
    allow(CacheStache).to receive(:configuration).and_return(config)
    CacheStache::Instrumentation.install!
  end
end

# Shared context for tests that need instrumentation with search keyspace
RSpec.shared_context "with instrumentation and search" do
  let(:config) do
    build_test_config(
      keyspaces: {
        views: {label: "View Fragments", match: /^views\//},
        models: {label: "Model Cache", match: /community/},
        search: {label: "Search Results", match: /search/}
      }
    )
  end

  before do
    allow(CacheStache).to receive(:configuration).and_return(config)
    CacheStache::Instrumentation.install!
  end
end
