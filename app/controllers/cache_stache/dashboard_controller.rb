# frozen_string_literal: true

module CacheStache
  class DashboardController < ApplicationController
    def index
      window = parse_window(params[:window])
      @results = StatsQuery.new(window: window).execute
      @config = CacheStache.configuration
      @storage_estimate = CacheClient.new(@config).estimate_storage_size
    end

    def keyspace
      @config = CacheStache.configuration
      @keyspace = @config.keyspaces.find { |ks| ks.name == params[:name].to_sym }

      unless @keyspace
        render plain: "Keyspace not found", status: :not_found
        return
      end

      window = parse_window(params[:window])
      @results = StatsQuery.new(window: window).execute
      @keyspace_stats = @results[:keyspaces][@keyspace.name]
    end

    private

    def parse_window(window_param)
      WindowOptions.duration_for(window_param)
    end
  end
end
