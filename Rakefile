# frozen_string_literal: true

require "bundler/gem_tasks"
require "bundler/setup"
require "rspec/core/rake_task"
require "standard/rake"

RSpec::Core::RakeTask.new(:spec)

namespace :gem do
  desc "Ensure packaged files are world-readable before building the gem"
  task :normalize_file_permissions do
    spec = Gem::Specification.load("cache_stache.gemspec")

    spec.files.each do |path|
      next unless File.file?(path)

      mode = File.stat(path).mode & 0o777
      new_mode = mode | 0o444
      next if new_mode == mode

      File.chmod(new_mode, path)
    end
  end
end

task build: "gem:normalize_file_permissions"

task default: %i[standard spec]
