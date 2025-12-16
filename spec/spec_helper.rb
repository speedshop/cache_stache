# frozen_string_literal: true

# Only run SimpleCov when running CacheStache specs in isolation
# (not when loaded as part of the main app's test suite)
if ENV["CACHE_STACHE_COVERAGE"] || !defined?(Rails)
  require "simplecov"

  SimpleCov.start do
    enable_coverage :branch
    command_name "CacheStache"

    # The project root for CacheStache is the lib/cache_stache directory
    cache_stache_root = File.expand_path("..", __dir__)
    root cache_stache_root
    coverage_dir File.join(cache_stache_root, "coverage")

    # Only track files within lib/cache_stache
    add_filter do |source_file|
      !source_file.filename.start_with?(cache_stache_root)
    end

    add_filter "/spec/"
    add_filter "/bin/"
    add_filter "/tasks/"
    add_filter "/generators/"

    add_group "Core", ["cache_stache.rb", "configuration.rb", "keyspace.rb"]
    add_group "Storage", ["cache_client.rb"]
    add_group "Instrumentation", ["instrumentation.rb"]
    add_group "Query", ["stats_query.rb"]
    add_group "Web", ["engine.rb", "railtie.rb", "web.rb", "app/"]

    # Coverage thresholds disabled for now - just tracking coverage
    # minimum_coverage line: 80, branch: 60
    # minimum_coverage_by_file line: 50, branch: 30
  end
end

require "bundler/setup"

# Set up Rails environment and load the dummy app (which loads CacheStache)
ENV["RAILS_ENV"] ||= "test"
require_relative "dummy_app/config/application"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Use consistent ordering for tests
  config.order = :random
  Kernel.srand config.seed

  # Clear configuration before each test
  config.before do
    CacheStache.instance_variable_set(:@configuration, nil)
  end
end
