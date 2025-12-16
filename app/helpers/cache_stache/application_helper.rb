# frozen_string_literal: true

module CacheStache
  module ApplicationHelper
    def window_options
      WindowOptions.for_select
    end

    def current_window_label
      WindowOptions.label_for(params[:window])
    end

    def sparkline_data(buckets, keyspace_name = nil)
      return [] if buckets.empty?

      buckets.map do |bucket|
        stats = bucket[:stats]
        if keyspace_name
          hits = stats["#{keyspace_name}:hits"].to_f
          misses = stats["#{keyspace_name}:misses"].to_f
        else
          hits = stats["overall:hits"].to_f
          misses = stats["overall:misses"].to_f
        end

        total = hits + misses
        hit_rate = total.positive? ? (hits / total * 100).round(2) : 0.0

        {
          time: Time.at(bucket[:timestamp]).utc.iso8601,
          hit_rate: hit_rate,
          operations: total.round
        }
      end
    end
  end
end
