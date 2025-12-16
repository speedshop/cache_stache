# frozen_string_literal: true

require_relative "../cache_stache_helper"

RSpec.describe CacheStache::Instrumentation do
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
  end

  describe ".install!" do
    it "installs instrumentation when enabled" do
      expect(Rails.logger).to receive(:info).with(/Instrumentation installed/)
      described_class.install!

      expect(described_class.instance_variable_get(:@installed)).to be(true)
    end

    it "does not install when disabled" do
      config.enabled = false
      described_class.install!

      expect(described_class.instance_variable_get(:@installed)).to be_falsey
    end

    it "does not install twice" do
      described_class.install!
      expect(Rails.logger).not_to receive(:info)
      described_class.install!
    end

    it "subscribes to cache_read.active_support" do
      described_class.install!

      listeners = ActiveSupport::Notifications.notifier.listeners_for("cache_read.active_support")
      expect(listeners).not_to be_empty
    end

    it "creates a cache client" do
      described_class.install!
      cache_client = described_class.instance_variable_get(:@cache_client)

      expect(cache_client).to be_a(CacheStache::CacheClient)
    end

    it "stores config metadata" do
      described_class.install!

      raw_metadata = cache_stache_redis.get("cache_stache:v1:test:config")
      metadata = raw_metadata ? JSON.parse(raw_metadata) : nil
      expect(metadata).not_to be_nil
      expect(metadata["bucket_seconds"]).to eq(300)
    end

    it "captures the monitored store class name" do
      described_class.install!

      expect(described_class.monitored_store_class).to eq(Rails.cache.class.name)
    end
  end

  describe ".call" do
    before do
      described_class.install!
    end

    it "records cache hits" do
      Rails.cache.write("test_key", "value")
      Rails.cache.read("test_key")

      sleep 0.1

      expect(current_bucket_stats["overall:hits"].to_f).to be >= 1
    end

    it "records cache misses" do
      Rails.cache.read("nonexistent_key")

      sleep 0.1

      expect(current_bucket_stats["overall:misses"].to_f).to be >= 1
    end

    it "records keyspace hits when key matches" do
      Rails.cache.write("views/product_123", "value")
      Rails.cache.read("views/product_123")

      sleep 0.1

      expect(current_bucket_stats["views:hits"].to_f).to be >= 1
    end

    it "records keyspace misses when key matches" do
      Rails.cache.read("views/nonexistent")

      sleep 0.1

      expect(current_bucket_stats["views:misses"].to_f).to be >= 1
    end

    it "records multiple keyspaces when key matches multiple patterns" do
      Rails.cache.write("views/community_123", "value")
      Rails.cache.read("views/community_123")

      sleep 0.1

      stats = current_bucket_stats
      expect(stats["views:hits"].to_f).to be >= 1
      expect(stats["models:hits"].to_f).to be >= 1
    end

    it "ignores cache_stache keys to prevent recursion" do
      Rails.cache.read("cache_stache:v1:test:12345")

      sleep 0.1

      stats = Rails.cache.read(current_bucket_key)

      # Should not record the cache_stache key read
      expect(stats).to be_nil
    end

    it "handles payloads with :key field" do
      payload = {key: "test_key", hit: true, store: Rails.cache.class.name}
      described_class.call(nil, nil, nil, nil, payload)

      sleep 0.1

      expect(current_bucket_stats["overall:hits"].to_f).to be >= 1
    end

    it "handles payloads with :name field" do
      payload = {name: "test_key", hit: false, store: Rails.cache.class.name}
      described_class.call(nil, nil, nil, nil, payload)

      sleep 0.1

      expect(current_bucket_stats["overall:misses"].to_f).to be >= 1
    end

    it "ignores payloads without key or name" do
      payload = {hit: true, store: Rails.cache.class.name}
      expect { described_class.call(nil, nil, nil, nil, payload) }.not_to raise_error

      stats = Rails.cache.read(current_bucket_key)

      expect(stats).to be_nil
    end

    it "ignores payloads from different store classes" do
      payload = {key: "test_key", hit: true, store: "ActiveSupport::Cache::MemoryStore"}
      # Only ignore if Rails.cache is not a MemoryStore
      if Rails.cache.class.name != "ActiveSupport::Cache::MemoryStore"
        described_class.call(nil, nil, nil, nil, payload)

        sleep 0.1

        stats = Rails.cache.read(current_bucket_key)

        expect(stats).to be_nil
      end
    end

    it "handles errors gracefully" do
      allow_any_instance_of(CacheStache::CacheClient).to receive(:increment_stats).and_raise(StandardError, "Test error")
      allow(Rails.logger).to receive(:error)

      payload = {key: "test_key", hit: true, store: Rails.cache.class.name}
      expect { described_class.call(nil, nil, nil, nil, payload) }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/instrumentation error/)
    end

    it "logs error backtraces" do
      allow_any_instance_of(CacheStache::CacheClient).to receive(:increment_stats).and_raise(StandardError, "Test error")
      allow(Rails.logger).to receive(:error)

      payload = {key: "test_key", hit: true, store: Rails.cache.class.name}
      described_class.call(nil, nil, nil, nil, payload)

      # Should log both the error message and the backtrace
      expect(Rails.logger).to have_received(:error).twice
    end
  end

  describe "bucket alignment" do
    before do
      described_class.install!
    end

    it "assigns operations to correct time buckets" do
      Rails.cache.read("test_bucket_alignment") # miss

      expect(current_bucket_stats["overall:misses"].to_f).to be >= 1
    end

    it "groups operations within the same bucket" do
      Rails.cache.read("test_bucket_1") # miss
      Rails.cache.read("test_bucket_2") # miss
      Rails.cache.read("test_bucket_3") # miss

      expect(current_bucket_stats["overall:misses"].to_f).to be >= 3
    end
  end

  describe "sample_rate" do
    it "reduces event volume when sample_rate is lower than 1.0" do
      config.sample_rate = 0.5
      described_class.install!

      200.times { |i| Rails.cache.read("sample_test_#{i}") }

      sleep 0.1

      recorded_count = (current_bucket_stats["overall:misses"] || 0).to_f

      expect(recorded_count).to be >= 80
      expect(recorded_count).to be <= 120
      expect(recorded_count).to be < 200
    end

    it "records all events when sample_rate is 1.0" do
      config.sample_rate = 1.0
      described_class.install!

      50.times { |i| Rails.cache.read("full_sample_test_#{i}") }

      sleep 0.1

      recorded_count = (current_bucket_stats["overall:misses"] || 0).to_f

      expect(recorded_count).to eq(50)
    end

    it "applies sampling consistently across keyspaces" do
      config.sample_rate = 0.5
      described_class.install!

      200.times { |i| Rails.cache.read("views/sample_test_#{i}") }

      sleep 0.1

      stats = current_bucket_stats
      overall_count = (stats["overall:misses"] || 0).to_f
      keyspace_count = (stats["views:misses"] || 0).to_f

      expect(overall_count).to be >= 80
      expect(overall_count).to be <= 120
      expect(keyspace_count).to eq(overall_count)
    end
  end
end
