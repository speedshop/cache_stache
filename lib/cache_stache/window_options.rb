# frozen_string_literal: true

module CacheStache
  module WindowOptions
    WINDOWS = [
      {param: "5m", aliases: ["5_minutes"], label: "5 minutes", duration: 5.minutes},
      {param: "15m", aliases: ["15_minutes"], label: "15 minutes", duration: 15.minutes},
      {param: "1h", aliases: ["1_hour"], label: "1 hour", duration: 1.hour, default: true},
      {param: "6h", aliases: ["6_hours"], label: "6 hours", duration: 6.hours},
      {param: "1d", aliases: ["1_day", "24h"], label: "1 day", duration: 1.day},
      {param: "1w", aliases: ["1_week", "7d"], label: "1 week", duration: 1.week}
    ].freeze

    DEFAULT_WINDOW = WINDOWS.find { |w| w[:default] }

    module_function

    def for_select
      WINDOWS.map { |w| [w[:label], w[:param]] }
    end

    def find(param)
      WINDOWS.find { |w| w[:param] == param || w[:aliases].include?(param) } || DEFAULT_WINDOW
    end

    def label_for(param)
      find(param)[:label]
    end

    def duration_for(param)
      find(param)[:duration]
    end
  end
end
