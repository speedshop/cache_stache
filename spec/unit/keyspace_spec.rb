# frozen_string_literal: true

require_relative "../cache_stache_helper"

RSpec.describe CacheStache::Keyspace do
  subject(:keyspace) { described_class.new(:views) }

  describe "#initialize" do
    it { expect(keyspace.name).to eq(:views) }
    it { expect(keyspace.label).to eq("Views") }
    it { expect(keyspace.pattern).to be_nil }
  end

  describe "#match?" do
    context "with a valid pattern" do
      before do
        keyspace.pattern = /^views\//
      end

      it "returns true when key matches" do
        expect(keyspace.match?("views/product_123")).to be(true)
      end

      it "returns false when key doesn't match" do
        expect(keyspace.match?("community/456")).to be(false)
      end
    end

    context "without a pattern" do
      it "returns false" do
        expect(keyspace.match?("any_key")).to be(false)
      end
    end

    context "with various regex patterns" do
      it "handles start anchor" do
        keyspace.pattern = /^views\/\w+_\d+$/
        expect(keyspace.match?("views/product_123")).to be(true)
        expect(keyspace.match?("views/invalid")).to be(false)
      end

      it "handles partial matching" do
        keyspace.pattern = /search/
        expect(keyspace.match?("pages/search/results")).to be(true)
        expect(keyspace.match?("pages/home")).to be(false)
      end

      it "handles alternation" do
        keyspace.pattern = %r{/(community|unit|lease)/}
        expect(keyspace.match?("models/community/123")).to be(true)
        expect(keyspace.match?("models/unit/456")).to be(true)
        expect(keyspace.match?("models/account/789")).to be(false)
      end
    end
  end

  describe "#validate!" do
    it "raises error when pattern is not set" do
      expect do
        keyspace.validate!
      end.to raise_error(CacheStache::Error, /Keyspace views requires a match pattern/)
    end

    it "raises error when pattern is not a Regexp" do
      keyspace.pattern = "not a regex"
      expect do
        keyspace.validate!
      end.to raise_error(CacheStache::Error, /match pattern must be a Regexp/)
    end

    it "passes validation when pattern is a valid Regexp" do
      keyspace.pattern = /test/
      expect { keyspace.validate! }.not_to raise_error
    end
  end

  describe "label humanization" do
    it "humanizes snake_case names" do
      ks = described_class.new(:search_results)
      expect(ks.label).to eq("Search results")
    end

    it "humanizes single word names" do
      ks = described_class.new(:profiles)
      expect(ks.label).to eq("Profiles")
    end

    it "can be overridden" do
      keyspace.label = "Custom Label"
      expect(keyspace.label).to eq("Custom Label")
    end
  end
end
