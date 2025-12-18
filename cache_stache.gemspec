# frozen_string_literal: true

require_relative "lib/cache_stache/version"

Gem::Specification.new do |spec|
  spec.name = "cache_stache"
  spec.version = CacheStache::VERSION
  spec.summary = "CacheStache tracks cache hit rates for Rails apps."
  spec.description = "CacheStache tracks cache hit/miss rates and exposes a small Rails engine UI."
  spec.license = "MIT"
  spec.authors = ["CacheStache contributors"]
  spec.homepage = "https://github.com/speedshop/cache_stache"

  spec.metadata = {
    "source_code_uri" => "https://github.com/speedshop/cache_stache",
    "changelog_uri" => "https://github.com/speedshop/cache_stache/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/speedshop/cache_stache/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir.chdir(__dir__) do
    Dir[
      "{app,bin,config,lib,spec,tasks}/**/*",
      "*.rb",
      "README.md"
    ].select { |path| File.file?(path) }
  end

  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "connection_pool"
  spec.add_dependency "redis"

  spec.add_development_dependency "sprockets-rails"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "rails-controller-testing"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "standard"
end
