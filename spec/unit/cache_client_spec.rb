# frozen_string_literal: true

require_relative "../cache_stache_helper"
require "json"

RSpec.describe CacheStache::CacheClient do
  subject(:client) { described_class.new(config) }

  let(:config) { build_test_config }

  describe "#initialize" do
    it "uses the provided configuration" do
      expect(client.instance_variable_get(:@config)).to eq(config)
    end

    it "uses the default configuration when none provided" do
      allow(CacheStache).to receive(:configuration).and_return(config)
      default_client = described_class.new
      expect(default_client.instance_variable_get(:@config)).to eq(config)
    end

    it "creates a Redis connection pool" do
      expect(client.instance_variable_get(:@pool)).to be_a(ConnectionPool)
    end
  end

  describe "#increment_stats" do
    # Use aligned timestamp (1_700_000_000 / 300 * 300 = 1_699_999_800)
    let(:bucket_ts) { (1_700_000_000 / 300) * 300 }
    let(:increments) do
      {
        "overall:hits" => 1,
        "overall:misses" => 0,
        "views:hits" => 1,
        "views:misses" => 0
      }
    end

    it "increments stats for a bucket" do
      client.increment_stats(bucket_ts, increments)

      buckets = client.fetch_buckets(bucket_ts - 100, bucket_ts + 100)
      expect(buckets.size).to eq(1)
      expect(buckets.first[:stats]["overall:hits"]).to eq(1.0)
      expect(buckets.first[:stats]["overall:misses"]).to eq(0.0)
      expect(buckets.first[:stats]["views:hits"]).to eq(1.0)
      expect(buckets.first[:stats]["views:misses"]).to eq(0.0)
    end

    it "accumulates stats across multiple calls" do
      client.increment_stats(bucket_ts, increments)
      client.increment_stats(bucket_ts, increments)

      buckets = client.fetch_buckets(bucket_ts - 100, bucket_ts + 100)
      expect(buckets.first[:stats]["overall:hits"]).to eq(2.0)
      expect(buckets.first[:stats]["views:hits"]).to eq(2.0)
    end

    it "handles mixed hit and miss increments" do
      client.increment_stats(bucket_ts, {"overall:hits" => 1, "overall:misses" => 0})
      client.increment_stats(bucket_ts, {"overall:hits" => 0, "overall:misses" => 1})

      buckets = client.fetch_buckets(bucket_ts - 100, bucket_ts + 100)
      expect(buckets.first[:stats]["overall:hits"]).to eq(1.0)
      expect(buckets.first[:stats]["overall:misses"]).to eq(1.0)
    end

    it "sets expiry on the bucket" do
      client.increment_stats(bucket_ts, increments)

      key = "cache_stache:v1:test:#{bucket_ts}"
      ttl = cache_stache_redis.ttl(key)

      expect(ttl).to be > 0
      expect(ttl).to be <= config.retention_seconds
    end

    it "handles errors gracefully" do
      # Create client, then make the pool raise errors
      test_client = described_class.new(config)
      pool = test_client.instance_variable_get(:@pool)
      allow(pool).to receive(:with).and_raise(StandardError, "Redis error")
      allow(Rails.logger).to receive(:error)

      expect { test_client.increment_stats(bucket_ts, increments) }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/Failed to increment stats/)
    end
  end

  describe "#fetch_buckets" do
    # Use a timestamp that aligns to 300-second bucket boundaries
    let(:base_ts) { (1_700_000_000 / 300) * 300 } # 1_699_999_800

    before do
      # Create some test buckets
      client.increment_stats(base_ts, {"overall:hits" => 5, "overall:misses" => 2})
      client.increment_stats(base_ts + 300, {"overall:hits" => 3, "overall:misses" => 1})
      client.increment_stats(base_ts + 600, {"overall:hits" => 8, "overall:misses" => 4})
    end

    it "fetches buckets in time range" do
      from_ts = base_ts
      to_ts = base_ts + 700

      buckets = client.fetch_buckets(from_ts, to_ts)

      expect(buckets.size).to eq(3)
      expect(buckets[0][:timestamp]).to eq(base_ts)
      expect(buckets[1][:timestamp]).to eq(base_ts + 300)
      expect(buckets[2][:timestamp]).to eq(base_ts + 600)
    end

    it "returns bucket stats as floats" do
      buckets = client.fetch_buckets(base_ts, base_ts + 100)

      expect(buckets[0][:stats]["overall:hits"]).to eq(5.0)
      expect(buckets[0][:stats]["overall:misses"]).to eq(2.0)
    end

    it "excludes empty buckets" do
      buckets = client.fetch_buckets(base_ts + 900, base_ts + 1200)
      expect(buckets).to be_empty
    end

    it "aligns timestamps to bucket boundaries" do
      buckets = client.fetch_buckets(base_ts + 50, base_ts + 550)

      expect(buckets.map { |b| b[:timestamp] }).to eq([base_ts, base_ts + 300])
    end

    it "handles errors gracefully" do
      # Create client, then make the pool raise errors
      test_client = described_class.new(config)
      pool = test_client.instance_variable_get(:@pool)
      allow(pool).to receive(:with).and_raise(StandardError, "Redis error")
      allow(Rails.logger).to receive(:error)

      buckets = test_client.fetch_buckets(base_ts, base_ts + 300)
      expect(buckets).to eq([])
      expect(Rails.logger).to have_received(:error).with(/Failed to fetch buckets/)
    end

    it "reflects single-field increments" do
      # Use a timestamp aligned to bucket boundary
      ts = base_ts + 900

      # Increment a single field
      client.increment_stats(ts, {"overall:hits" => 1})

      # Fetch the bucket containing this increment
      buckets = client.fetch_buckets(ts, ts + 100)

      # Verify the increment is visible
      expect(buckets.size).to eq(1)
      expect(buckets[0][:timestamp]).to eq(ts)
      expect(buckets[0][:stats]["overall:hits"]).to eq(1.0)
    end
  end

  describe "#store_config_metadata" do
    it "stores configuration metadata in Redis" do
      client.store_config_metadata

      metadata = client.fetch_config_metadata

      expect(metadata["bucket_seconds"]).to eq(300)
      expect(metadata["retention_seconds"]).to eq(3600)
      expect(metadata["updated_at"]).to be_a(Integer)
    end

    it "handles errors gracefully" do
      # Create client, then make the pool raise errors
      test_client = described_class.new(config)
      pool = test_client.instance_variable_get(:@pool)
      allow(pool).to receive(:with).and_raise(StandardError, "Redis error")
      allow(Rails.logger).to receive(:error)

      expect { test_client.store_config_metadata }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/Failed to store config metadata/)
    end
  end

  describe "#fetch_config_metadata" do
    it "retrieves stored metadata" do
      client.store_config_metadata
      metadata = client.fetch_config_metadata

      expect(metadata["bucket_seconds"]).to eq(300)
      expect(metadata["retention_seconds"]).to eq(3600)
    end

    it "returns nil when metadata doesn't exist" do
      metadata = client.fetch_config_metadata
      expect(metadata).to be_nil
    end

    it "handles errors gracefully" do
      # Create client, then make the pool raise errors
      test_client = described_class.new(config)
      pool = test_client.instance_variable_get(:@pool)
      allow(pool).to receive(:with).and_raise(StandardError, "Redis error")
      allow(Rails.logger).to receive(:error)

      metadata = test_client.fetch_config_metadata
      expect(metadata).to be_nil
      expect(Rails.logger).to have_received(:error).with(/Failed to fetch config metadata/)
    end
  end

  describe "#estimate_storage_size" do
    before do
      config.keyspace(:views) { match(/^views\//) }
      config.keyspace(:models) { match(/model/) }
    end

    it "calculates estimated storage size" do
      estimate = client.estimate_storage_size

      expect(estimate[:max_buckets]).to be > 0
      expect(estimate[:fields_per_bucket]).to eq(6) # 2 overall + 2*2 keyspaces
      expect(estimate[:bytes_per_bucket]).to be > 0
      expect(estimate[:total_bytes]).to be > 0
      expect(estimate[:human_size]).to be_a(String)
    end

    it "formats bytes correctly" do
      expect(client.send(:format_bytes, 500)).to eq("500 B")
      expect(client.send(:format_bytes, 2048)).to eq("2.0 KB")
      expect(client.send(:format_bytes, 2_097_152)).to eq("2.0 MB")
      expect(client.send(:format_bytes, 2_147_483_648)).to eq("2.0 GB")
    end

    it "handles errors gracefully" do
      allow(config).to receive(:retention_seconds).and_raise(StandardError, "Config error")
      expect(Rails.logger).to receive(:error).with(/Failed to estimate storage size/)

      estimate = client.estimate_storage_size
      expect(estimate[:total_bytes]).to eq(0)
      expect(estimate[:human_size]).to eq("Unknown")
    end
  end

  describe "private methods" do
    describe "#bucket_key" do
      it "generates correct bucket key format" do
        key = client.send(:bucket_key, 1_700_000_000)
        expect(key).to eq("cache_stache:v1:test:1700000000")
      end
    end

    describe "#align_to_bucket" do
      it "aligns timestamp to bucket boundary" do
        aligned = client.send(:align_to_bucket, 1_700_000_123)
        expect(aligned).to eq(1_700_000_100) # 123 aligned to 300s bucket
      end
    end

    describe "#extract_timestamp_from_key" do
      it "extracts timestamp from key" do
        ts = client.send(:extract_timestamp_from_key, "cache_stache:v1:test:1700000000")
        expect(ts).to eq(1_700_000_000)
      end
    end

    describe "#bucket_keys_in_range" do
      it "generates all bucket keys in range" do
        # Use aligned timestamps (1_699_999_800 is divisible by 300)
        aligned_base = (1_700_000_000 / 300) * 300
        keys = client.send(:bucket_keys_in_range, aligned_base, aligned_base + 700)
        expect(keys).to eq([
          "cache_stache:v1:test:#{aligned_base}",
          "cache_stache:v1:test:#{aligned_base + 300}",
          "cache_stache:v1:test:#{aligned_base + 600}"
        ])
      end
    end
  end
end
