# frozen_string_literal: true

require_relative "../cache_stache_helper"

RSpec.describe CacheStache::StatsQuery do
  include ActiveSupport::Testing::TimeHelpers

  subject(:query) { described_class.new(window: window) }

  let(:window) { 1.hour }
  let(:config) do
    build_test_config(
      keyspaces: {
        views: {label: "View Fragments", match: /^views\//},
        models: {label: "Model Cache", match: /model/}
      }
    )
  end
  let(:cache_client) { CacheStache::CacheClient.new(config) }

  before do
    allow(CacheStache).to receive(:configuration).and_return(config)
  end

  describe "#initialize" do
    it { expect(query.window).to eq(3600) }

    it "accepts resolution parameter" do
      q = described_class.new(window: 1.hour, resolution: 12)
      expect(q.resolution).to eq(12)
    end
  end

  describe "#execute" do
    let(:base_time) { Time.current }

    before do
      # Freeze time and create test data
      travel_to base_time

      # Create buckets with stats
      bucket_ts = (base_time.to_i / 300) * 300

      # Recent bucket (within window)
      cache_client.increment_stats(bucket_ts, {
        "overall:hits" => 10,
        "overall:misses" => 5,
        "views:hits" => 8,
        "views:misses" => 2,
        "models:hits" => 2,
        "models:misses" => 3
      })

      # Another recent bucket
      cache_client.increment_stats(bucket_ts - 300, {
        "overall:hits" => 15,
        "overall:misses" => 10,
        "views:hits" => 12,
        "views:misses" => 8,
        "models:hits" => 3,
        "models:misses" => 2
      })

      # Old bucket (outside window)
      cache_client.increment_stats(bucket_ts - 7200, {
        "overall:hits" => 100,
        "overall:misses" => 50
      })
    end

    after do
      travel_back
    end

    it "returns overall statistics" do
      results = query.execute

      expect(results[:overall][:hits]).to eq(25)
      expect(results[:overall][:misses]).to eq(15)
      expect(results[:overall][:total_operations]).to eq(40)
      expect(results[:overall][:hit_rate_percent]).to eq(62.5)
    end

    it "returns keyspace statistics" do
      results = query.execute

      expect(results[:keyspaces][:views]).to include(
        label: "View Fragments",
        pattern: /^views\//,
        hits: 20,
        misses: 10,
        total_operations: 30,
        hit_rate_percent: 66.67
      )

      expect(results[:keyspaces][:models]).to include(
        label: "Model Cache",
        pattern: /model/,
        hits: 5,
        misses: 5,
        total_operations: 10,
        hit_rate_percent: 50.0
      )
    end

    it "includes bucket details" do
      results = query.execute

      expect(results[:buckets].size).to eq(2)
      expect(results[:buckets][0]).to include(:timestamp, :time, :stats)
      expect(results[:buckets][0][:stats]).to include("overall:hits", "overall:misses")
    end

    it "includes metadata" do
      results = query.execute

      expect(results[:window_seconds]).to eq(3600)
      expect(results[:bucket_count]).to eq(2)
    end

    it "excludes buckets outside the window" do
      results = query.execute

      total_hits = results[:overall][:hits]
      # Should not include the 100 hits from old bucket
      expect(total_hits).to eq(25)
    end

    context "with no data" do
      before do
        flush_cache_stache_redis
      end

      it "returns zeros for overall stats" do
        results = query.execute

        expect(results[:overall]).to eq(
          hits: 0,
          misses: 0,
          total_operations: 0,
          hit_rate_percent: 0.0
        )
      end

      it "returns zeros for keyspace stats" do
        results = query.execute

        expect(results[:keyspaces][:views][:total_operations]).to eq(0)
        expect(results[:keyspaces][:views][:hit_rate_percent]).to eq(0.0)
      end

      it "has zero buckets" do
        results = query.execute
        expect(results[:bucket_count]).to eq(0)
      end
    end

    context "with only hits" do
      before do
        flush_cache_stache_redis
        bucket_ts = (base_time.to_i / 300) * 300
        cache_client.increment_stats(bucket_ts, {
          "overall:hits" => 20,
          "overall:misses" => 0
        })
      end

      it "calculates 100% hit rate" do
        results = query.execute
        expect(results[:overall][:hit_rate_percent]).to eq(100.0)
      end
    end

    context "with only misses" do
      before do
        flush_cache_stache_redis
        bucket_ts = (base_time.to_i / 300) * 300
        cache_client.increment_stats(bucket_ts, {
          "overall:hits" => 0,
          "overall:misses" => 20
        })
      end

      it "calculates 0% hit rate" do
        results = query.execute
        expect(results[:overall][:hit_rate_percent]).to eq(0.0)
      end
    end

    context "with different window sizes" do
      it "respects custom window parameter" do
        short_query = described_class.new(window: 5.minutes)
        results = short_query.execute

        # Should only include most recent bucket
        expect(results[:bucket_count]).to be <= 2
      end

      it "works with long windows" do
        long_query = described_class.new(window: 7.days)
        results = long_query.execute

        expect(results[:window_seconds]).to eq(7.days.to_i)
      end

      it "truncates to max_buckets for very long windows" do
        # With 5-minute buckets, 7 days would be 2,016 buckets
        # but max_buckets defaults to 288, so we expect truncation
        long_query = described_class.new(window: 7.days)

        max_buckets = CacheStache.configuration.max_buckets

        # Expect a warning to be logged when truncation occurs
        expect(Rails.logger).to receive(:warn).with(
          /CacheStache: Truncating bucket range from \d+ to #{max_buckets} buckets/
        )

        results = long_query.execute

        # Should be capped at max_buckets (default: 288)
        expect(results[:bucket_count]).to be <= max_buckets
      end
    end
  end

  describe "#execute with default labels" do
    let(:config) do
      build_test_config(
        keyspaces: {
          profiles: {match: /^profile:/}
        }
      )
    end

    it "returns humanized labels when none are provided" do
      bucket_ts = (Time.current.to_i / config.bucket_seconds) * config.bucket_seconds
      cache_client.increment_stats(bucket_ts, {
        "overall:hits" => 1,
        "overall:misses" => 0,
        "profiles:hits" => 1,
        "profiles:misses" => 0
      })

      results = query.execute

      expect(results[:keyspaces][:profiles][:label]).to eq("Profiles")
    end
  end

  describe "zero-omission optimization" do
    let(:base_time) { Time.current }

    before do
      travel_to base_time
    end

    after do
      travel_back
    end

    it "treats missing stat fields as 0 when aggregating across buckets" do
      bucket_ts = (base_time.to_i / 300) * 300

      # Bucket 1: only has hits for overall and views
      cache_client.increment_stats(bucket_ts, {
        "overall:hits" => 5,
        "views:hits" => 8
      })

      # Bucket 2: only has misses for overall and models
      cache_client.increment_stats(bucket_ts - 300, {
        "overall:misses" => 3,
        "models:misses" => 2
      })

      results = query.execute

      # Overall should aggregate: hits=5 (0 from bucket2), misses=3 (0 from bucket1)
      expect(results[:overall][:hits]).to eq(5)
      expect(results[:overall][:misses]).to eq(3)
      expect(results[:overall][:total_operations]).to eq(8)
      expect(results[:overall][:hit_rate_percent]).to eq(62.5)

      # Views should aggregate: hits=8 (0 from bucket2), misses=0 (0 from bucket2)
      expect(results[:keyspaces][:views][:hits]).to eq(8)
      expect(results[:keyspaces][:views][:misses]).to eq(0)
      expect(results[:keyspaces][:views][:total_operations]).to eq(8)
      expect(results[:keyspaces][:views][:hit_rate_percent]).to eq(100.0)

      # Models should aggregate: hits=0 (0 from bucket1), misses=2 (0 from bucket1)
      expect(results[:keyspaces][:models][:hits]).to eq(0)
      expect(results[:keyspaces][:models][:misses]).to eq(2)
      expect(results[:keyspaces][:models][:total_operations]).to eq(2)
      expect(results[:keyspaces][:models][:hit_rate_percent]).to eq(0.0)
    end
  end

  describe "private methods" do
    describe "#calculate_overall_stats" do
      it "aggregates across buckets correctly" do
        buckets = [
          {stats: {"overall:hits" => 5.0, "overall:misses" => 3.0}},
          {stats: {"overall:hits" => 10.0, "overall:misses" => 7.0}}
        ]

        stats = query.send(:calculate_overall_stats, buckets)

        expect(stats[:hits]).to eq(15)
        expect(stats[:misses]).to eq(10)
        expect(stats[:total_operations]).to eq(25)
        expect(stats[:hit_rate_percent]).to eq(60.0)
      end

      it "rounds floats to integers for operations" do
        buckets = [
          {stats: {"overall:hits" => 5.7, "overall:misses" => 3.2}}
        ]

        stats = query.send(:calculate_overall_stats, buckets)

        expect(stats[:hits]).to eq(6)
        expect(stats[:misses]).to eq(3)
      end
    end

    describe "#calculate_keyspace_stats" do
      it "aggregates keyspace stats correctly" do
        views_keyspace = CacheStache::Keyspace.new(:views).tap do |k|
          k.label = "Views"
          k.pattern = /^views\//
        end
        allow(config).to receive(:keyspaces).and_return([views_keyspace])

        buckets = [
          {stats: {"views:hits" => 8.0, "views:misses" => 2.0}},
          {stats: {"views:hits" => 12.0, "views:misses" => 8.0}}
        ]

        stats = query.send(:calculate_keyspace_stats, buckets)

        expect(stats[:views]).to eq(
          label: "Views",
          pattern: /^views\//,
          hits: 20,
          misses: 10,
          total_operations: 30,
          hit_rate_percent: 66.67
        )
      end
    end

    describe "#format_bucket" do
      it "formats bucket with timestamp and time" do
        bucket = {
          timestamp: 1_700_000_000,
          stats: {"overall:hits" => 10.0}
        }

        formatted = query.send(:format_bucket, bucket)

        expect(formatted[:timestamp]).to eq(1_700_000_000)
        expect(formatted[:time]).to eq(Time.at(1_700_000_000).utc)
        expect(formatted[:stats]).to eq({"overall:hits" => 10.0})
      end
    end
  end
end
