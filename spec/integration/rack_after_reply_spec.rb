# frozen_string_literal: true

require "rack/mock"
require "active_support/testing/time_helpers"
require_relative "../cache_stache_helper"

RSpec.describe "CacheStache rack.after_reply" do
  include ActiveSupport::Testing::TimeHelpers

  let(:config) { build_test_config(use_rack_after_reply: true) }

  before do
    allow(CacheStache).to receive(:configuration).and_return(config)
    CacheStache::Instrumentation.install!
  end

  after do
    travel_back if respond_to?(:travel_back)
  end

  it "records cache stats via a single after_reply proc" do
    travel_to Time.utc(2020, 1, 1, 0, 0, 0) do
      inner = lambda do |_env|
        Rails.cache.write("test_key", "value")
        Rails.cache.read("test_key") # hit
        Rails.cache.read("missing_key") # miss
        [200, {"Content-Type" => "text/plain"}, ["ok"]]
      end

      app = CacheStache::RackAfterReplyMiddleware.new(inner)

      env = Rack::MockRequest.env_for("/", "rack.after_reply" => [])
      status, = app.call(env)
      expect(status).to eq(200)

      expect(env["rack.after_reply"].size).to eq(1)

      expect(cache_stache_redis.hgetall(current_bucket_key)).to be_empty

      env["rack.after_reply"].each(&:call)

      stats = current_bucket_stats
      expect(stats["overall:hits"].to_f).to be >= 1
      expect(stats["overall:misses"].to_f).to be >= 1
    end
  end
end
