# frozen_string_literal: true

require_relative "../cache_stache_helper"

RSpec.describe "Full Cache Flow" do
  include ActiveSupport::Testing::TimeHelpers

  include_context "with instrumentation and search"

  after do
    travel_back if respond_to?(:travel_back)
  end

  describe "complete workflow" do
    it "tracks cache operations end-to-end" do
      # Generate cache misses (first fetch)
      10.times { |i| Rails.cache.fetch("views/product_#{i}") { "Product #{i}" } }

      # Generate cache hits (repeat fetch)
      5.times { Rails.cache.fetch("views/product_1") { "Product 1" } }

      # Generate model cache operations
      3.times { |i| Rails.cache.fetch("community/#{i}") { "Community #{i}" } }

      # Generate operations matching multiple keyspaces
      Rails.cache.fetch("views/community_search") { "Search results" }

      sleep 0.2 # Allow instrumentation to process

      # Query statistics
      query = CacheStache::StatsQuery.new(window: 5.minutes)
      results = query.execute

      # Verify overall stats
      expect(results[:overall][:total_operations]).to be >= 18 # 10 + 5 + 3
      expect(results[:overall][:hits]).to be >= 5
      expect(results[:overall][:misses]).to be >= 13

      # Verify view keyspace stats
      expect(results[:keyspaces][:views][:total_operations]).to be >= 16 # 10 + 5 + 1
      expect(results[:keyspaces][:views][:hits]).to be >= 5

      # Verify model keyspace stats
      expect(results[:keyspaces][:models][:total_operations]).to be >= 4 # 3 + 1

      # Verify search keyspace stats
      expect(results[:keyspaces][:search][:total_operations]).to be >= 1
    end

    it "calculates accurate hit rates" do
      # Generate known pattern: 10 misses, 5 hits
      10.times { |i| Rails.cache.fetch("views/item_#{i}") { "Item #{i}" } }
      5.times { Rails.cache.fetch("views/item_1") { "Item 1" } }

      sleep 0.2

      query = CacheStache::StatsQuery.new(window: 5.minutes)
      results = query.execute

      # Total operations = 15, hits = 5, misses = 10
      # Hit rate should be ~33%
      expect(results[:overall][:total_operations]).to eq(15)
      expect(results[:overall][:hits]).to eq(5)
      expect(results[:overall][:misses]).to eq(10)
      expect(results[:overall][:hit_rate_percent]).to be_within(0.1).of(33.33)
    end

    it "handles mixed cache operations" do
      # Mix of reads, writes, and fetches
      Rails.cache.write("test_1", "value")
      Rails.cache.read("test_1") # hit
      Rails.cache.read("nonexistent") # miss
      Rails.cache.fetch("test_2") { "value" } # miss (write + read)
      Rails.cache.fetch("test_2") { "value" } # hit

      sleep 0.2

      query = CacheStache::StatsQuery.new(window: 5.minutes)
      results = query.execute

      # Only reads are tracked
      expect(results[:overall][:total_operations]).to be >= 4
    end

    it "handles keyspaces with overlapping patterns" do
      # Key matches both views and search keyspaces
      Rails.cache.fetch("views/search_page") { "content" }

      sleep 0.2

      query = CacheStache::StatsQuery.new(window: 5.minutes)
      results = query.execute

      # Both keyspaces should record the operation
      expect(results[:keyspaces][:views][:total_operations]).to eq(1)
      expect(results[:keyspaces][:search][:total_operations]).to eq(1)

      # Overall should still count it once
      expect(results[:overall][:total_operations]).to eq(1)
    end
  end

  describe "edge cases" do
    it "handles cache keys with special characters" do
      special_keys = [
        "views/product:123",
        "views/category/sub-category",
        "views/item.json",
        "views/search?query=test"
      ]

      special_keys.each { |key| Rails.cache.fetch(key) { "value" } }
      sleep 0.2

      query = CacheStache::StatsQuery.new(window: 5.minutes)
      results = query.execute

      expect(results[:keyspaces][:views][:total_operations]).to eq(special_keys.size)
    end

    it "handles very high operation volumes" do
      100.times { |i| Rails.cache.fetch("views/item_#{i}") { "value" } }
      sleep 0.3

      query = CacheStache::StatsQuery.new(window: 5.minutes)
      results = query.execute

      expect(results[:overall][:total_operations]).to eq(100)
    end

    it "handles cache operations with nil values" do
      Rails.cache.write("nil_value", nil)
      Rails.cache.read("nil_value") # This is a hit

      sleep 0.2

      query = CacheStache::StatsQuery.new(window: 5.minutes)
      results = query.execute

      expect(results[:overall][:hits]).to be >= 1
    end
  end

  describe "realistic usage scenarios" do
    it "simulates a typical request pattern" do
      # Simulate multiple requests hitting various cache keys

      # Request 1: Homepage (all hits after first)
      Rails.cache.fetch("views/homepage") { "content" }
      3.times { Rails.cache.fetch("views/homepage") { "content" } }

      # Request 2: Product listings (some hits, some misses)
      Rails.cache.fetch("views/products/list") { "list" }
      Rails.cache.fetch("views/products/list") { "list" }

      # Request 3: Community data (misses)
      5.times { |i| Rails.cache.fetch("community/#{i}/stats") { "stats" } }

      # Request 4: Search results (misses)
      Rails.cache.fetch("search/results?q=test") { "results" }

      sleep 0.2

      query = CacheStache::StatsQuery.new(window: 5.minutes)
      results = query.execute

      # Verify realistic metrics
      expect(results[:overall][:total_operations]).to be >= 12
      expect(results[:overall][:hit_rate_percent]).to be > 0
      expect(results[:overall][:hit_rate_percent]).to be < 100

      # Verify keyspace breakdown
      expect(results[:keyspaces][:views][:total_operations]).to be >= 6
      expect(results[:keyspaces][:models][:total_operations]).to be >= 5
      expect(results[:keyspaces][:search][:total_operations]).to be >= 1
    end

    it "simulates gradual cache warming" do
      # First pass: all misses (cold cache)
      10.times { |i| Rails.cache.fetch("warming_item_#{i}") { "value" } }
      sleep 0.2

      query = CacheStache::StatsQuery.new(window: 5.minutes)
      results_after_cold = query.execute
      cold_misses = results_after_cold[:overall][:misses]
      expect(cold_misses).to eq(10)

      # Second pass: all hits (warm cache)
      10.times { |i| Rails.cache.fetch("warming_item_#{i}") { "value" } }
      sleep 0.2

      query = CacheStache::StatsQuery.new(window: 5.minutes)
      results_after_warm = query.execute

      # Should now have 10 misses + 10 hits = 20 total, 50% hit rate
      expect(results_after_warm[:overall][:total_operations]).to eq(20)
      expect(results_after_warm[:overall][:hits]).to eq(10)
      expect(results_after_warm[:overall][:misses]).to eq(10)
      expect(results_after_warm[:overall][:hit_rate_percent]).to eq(50.0)
    end
  end
end
