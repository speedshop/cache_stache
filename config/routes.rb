# frozen_string_literal: true

CacheStache::Engine.routes.draw do
  root to: "dashboard#index"
  get "keyspaces/:name", to: "dashboard#keyspace", as: :keyspace
end
