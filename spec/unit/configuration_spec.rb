# frozen_string_literal: true

require_relative "../cache_stache_helper"

RSpec.describe CacheStache::Configuration do
  subject(:config) { described_class.new }

  describe "#initialize" do
    let(:default_redis_url) { "redis://cache-stache.test/0" }

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("CACHE_STACHE_REDIS_URL").and_return(default_redis_url)
      allow(ENV).to receive(:fetch).with("RAILS_ENV", "development").and_return("development")
    end

    it { expect(config.bucket_seconds).to eq(5.minutes.to_i) }
    it { expect(config.retention_seconds).to eq(7.days.to_i) }
    it { expect(config.sample_rate).to eq(1.0) }
    it { expect(config.enabled).to be(true) }
    it { expect(config.use_rack_after_reply).to be(false) }
    it { expect(config.redis).to eq(default_redis_url) }
    it { expect(config.redis_pool_size).to eq(5) }
    it { expect(config.keyspaces).to eq([]) }
  end

  describe "#build_redis" do
    it "calls the proc when redis is a Proc" do
      redis_instance = instance_double(Redis)
      config.redis = -> { redis_instance }

      expect(config.build_redis).to eq(redis_instance)
    end

    it "creates a Redis instance when redis is a String URL" do
      config.redis = "redis://localhost:6379/1"

      expect(Redis).to receive(:new).with(
        hash_including(url: "redis://localhost:6379/1")
      ).and_call_original

      result = config.build_redis
      expect(result).to be_a(Redis)
    end

    it "returns the object directly when redis is an Object" do
      redis_instance = instance_double(Redis)
      config.redis = redis_instance

      expect(config.build_redis).to eq(redis_instance)
    end
  end

  describe "#keyspace" do
    it "adds a keyspace with the given name" do
      config.keyspace(:views) do
        label "View Fragments"
        match(/^views\//)
      end

      expect(config.keyspaces.size).to eq(1)
      expect(config.keyspaces.first.name).to eq(:views)
      expect(config.keyspaces.first.label).to eq("View Fragments")
    end

    it "uses humanized name as default label" do
      config.keyspace(:search_results) do
        match(/search/)
      end

      expect(config.keyspaces.first.label).to eq("Search results")
    end

    it "validates the keyspace requires a pattern" do
      expect do
        config.keyspace(:invalid) do
          label "Invalid"
          # No match pattern
        end
      end.to raise_error(CacheStache::Error, /requires a match pattern/)
    end

    it "validates the pattern must be a Regexp" do
      expect do
        config.keyspace(:invalid) do
          match "not a regex"
        end
      end.to raise_error(CacheStache::Error, /requires a Regexp argument/)
    end

    it "raises error for duplicate keyspace names" do
      config.keyspace(:views) do
        match(/^views\//)
      end

      expect do
        config.keyspace(:views) do
          match(/view/)
        end
      end.to raise_error(CacheStache::Error, /already defined/)
    end

    it "accepts a block without a label" do
      config.keyspace(:test) do
        match(/test/)
      end

      expect(config.keyspaces.first.label).to eq("Test")
    end

    it "stores the pattern on the keyspace" do
      config.keyspace(:views) do
        match(/^views\//)
      end

      expect(config.keyspaces.first.pattern).to eq(/^views\//)
    end
  end

  describe "#matching_keyspaces" do
    before do
      config.keyspace(:views) do
        match(/^views\//)
      end

      config.keyspace(:models) do
        match(/community/)
      end

      config.keyspace(:search) do
        match(/search/)
      end
    end

    it "returns keyspaces matching the key" do
      matches = config.matching_keyspaces("views/product_123")
      expect(matches.map(&:name)).to eq([:views])
    end

    it "returns multiple keyspaces when key matches multiple patterns" do
      matches = config.matching_keyspaces("views/community_search")
      expect(matches.map(&:name)).to contain_exactly(:views, :models, :search)
    end

    it "returns empty array when no keyspaces match" do
      matches = config.matching_keyspaces("unmatched_key")
      expect(matches).to eq([])
    end

    it "caches results for the same key" do
      # First call
      config.matching_keyspaces("views/test")

      # Modify keyspace to prove caching
      config.keyspaces.first.instance_variable_set(:@pattern, /never_match/)

      # Should still return cached result
      matches = config.matching_keyspaces("views/test")
      expect(matches.map(&:name)).to eq([:views])
    end
  end

  describe "#validate!" do
    before do
      config.redis = "redis://localhost:6379/0"
    end

    it "requires redis" do
      config.redis = nil
      expect { config.validate! }.to raise_error(CacheStache::Error, /redis must be configured/)
    end

    it "rejects empty string for redis" do
      config.redis = "   "
      expect { config.validate! }.to raise_error(CacheStache::Error, /redis must be a Proc, String/)
    end

    it "accepts a Proc for redis" do
      config.redis = -> { Redis.new }
      expect { config.validate! }.not_to raise_error
    end

    it "accepts an Object for redis" do
      config.redis = instance_double(Redis)
      expect { config.validate! }.not_to raise_error
    end

    it "requires redis_pool_size to be positive" do
      config.redis_pool_size = 0
      expect { config.validate! }.to raise_error(CacheStache::Error, /redis_pool_size must be positive/)
    end

    it "validates bucket_seconds is positive" do
      config.bucket_seconds = 0
      expect { config.validate! }.to raise_error(CacheStache::Error, /bucket_seconds must be positive/)
    end

    it "validates retention_seconds is positive" do
      config.retention_seconds = -1
      expect { config.validate! }.to raise_error(CacheStache::Error, /retention_seconds must be positive/)
    end

    it "validates sample_rate is between 0 and 1" do
      config.sample_rate = 1.5
      expect { config.validate! }.to raise_error(CacheStache::Error, /sample_rate must be between 0 and 1/)
    end

    it "validates all keyspaces" do
      # Create a keyspace with a valid pattern first
      config.keyspace(:invalid) do
        match(/test/)
      end

      # Then corrupt it by setting pattern to nil
      config.instance_variable_get(:@keyspaces).last.instance_variable_set(:@pattern, nil)

      expect { config.validate! }.to raise_error(CacheStache::Error, /requires a match pattern/)
    end

    it "warns when retention doesn't divide evenly by bucket size" do
      config.bucket_seconds = 7.minutes.to_i
      config.retention_seconds = 1.hour.to_i

      expect(Rails.logger).to receive(:warn).with(/does not divide evenly/)
      config.validate!
    end

    it "passes validation with valid configuration" do
      config.keyspace(:views) do
        match(/^views\//)
      end

      expect { config.validate! }.not_to raise_error
    end
  end

  describe "#rails_env" do
    it "returns RAILS_ENV when set" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("CACHE_STACHE_REDIS_URL").and_return("redis://cache-stache.test/0")
      allow(ENV).to receive(:fetch).with("RAILS_ENV", "development").and_return("production")
      expect(config.rails_env).to eq("production")
    end

    it "defaults to development when RAILS_ENV is not set" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("CACHE_STACHE_REDIS_URL").and_return("redis://cache-stache.test/0")
      allow(ENV).to receive(:fetch).with("RAILS_ENV", "development").and_return("development")
      expect(config.rails_env).to eq("development")
    end
  end
end
