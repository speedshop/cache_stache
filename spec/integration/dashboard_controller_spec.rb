# frozen_string_literal: true

require_relative "../cache_stache_helper"

RSpec.describe CacheStache::DashboardController, type: :controller do
  routes { CacheStache::Engine.routes }

  let(:config) do
    CacheStache::Configuration.new.tap do |c|
      c.bucket_seconds = 300
      c.retention_seconds = 3600

      c.keyspace(:views) do
        label "View Fragments"
        match(/^views\//)
      end

      c.keyspace(:models) do
        label "Model Cache"
        match(/community/)
      end
    end
  end

  before do
    allow(CacheStache).to receive(:configuration).and_return(config)
    Rails.cache.clear
  end

  describe "GET #index" do
    it "renders successfully" do
      get :index
      expect(response).to be_successful
    end

    context "with custom window parameter" do
      it "accepts 5 minutes window" do
        get :index, params: {window: "5m"}
        expect(response).to be_successful
      end

      it "accepts 15 minutes window" do
        get :index, params: {window: "15m"}
        expect(response).to be_successful
      end

      it "accepts 1 hour window" do
        get :index, params: {window: "1h"}
        expect(response).to be_successful
      end

      it "accepts 6 hours window" do
        get :index, params: {window: "6h"}
        expect(response).to be_successful
      end

      it "accepts 1 day window" do
        get :index, params: {window: "1d"}
        expect(response).to be_successful
      end

      it "accepts 1 week window" do
        get :index, params: {window: "1w"}
        expect(response).to be_successful
      end

      it "defaults to 1 hour for invalid window" do
        get :index, params: {window: "invalid"}
        expect(response).to be_successful
      end
    end
  end

  describe "GET #keyspace" do
    it "renders successfully for valid keyspace" do
      get :keyspace, params: {name: "views"}
      expect(response).to be_successful
    end

    context "with custom window parameter" do
      it "respects window parameter" do
        get :keyspace, params: {name: "views", window: "6h"}
        expect(response).to be_successful
      end
    end

    context "with invalid keyspace" do
      it "returns 404" do
        get :keyspace, params: {name: "nonexistent"}
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
