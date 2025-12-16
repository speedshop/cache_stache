# frozen_string_literal: true

require "active_support/core_ext/string/inflections"

module CacheStache
  class Keyspace
    attr_accessor :name, :label, :pattern

    def initialize(name)
      @name = name
      @label = name.to_s.humanize
      @pattern = nil
    end

    def match?(key)
      return false unless pattern
      pattern.match?(key.to_s)
    rescue => e
      Rails.logger.error("CacheStache: Keyspace #{name} matcher error: #{e.message}")
      false
    end

    def validate!
      raise Error, "Keyspace #{name} requires a match pattern (regex)" unless pattern
      raise Error, "Keyspace #{name} match pattern must be a Regexp" unless pattern.is_a?(Regexp)
    end
  end
end
