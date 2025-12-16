# frozen_string_literal: true

require "cache_stache/web"

Rails.application.routes.draw do
  mount CacheStache::Web => "/cache-stache"
end
