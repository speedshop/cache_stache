# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "CacheStache rake tasks" do
  it "loads without error and registers tasks" do
    # Run `rake -P` from the dummy app to verify the railtie loads tasks correctly.
    # If the railtie's rake task path is wrong, this will fail with LoadError.
    dummy_app_path = File.expand_path("../dummy_app", __dir__)
    output = `cd #{dummy_app_path} && bundle exec rake -P 2>&1`

    expect($?.success?).to be(true), "rake -P failed:\n#{output}"
    expect(output).to include("cache_stache:config")
    expect(output).to include("cache_stache:prune")
    expect(output).to include("cache_stache:stats")
  end
end
