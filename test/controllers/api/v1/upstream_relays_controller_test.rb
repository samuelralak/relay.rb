# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class UpstreamRelaysControllerTest < ActionDispatch::IntegrationTest
      setup do
        @api_key = ApiKey.create!(name: "Test Key")
        @auth_headers = { "Authorization" => "Bearer #{@api_key.token}" }

        @relay = UpstreamRelay.create!(
          url: "wss://test.relay.com",
          enabled: true,
          backfill: true,
          negentropy: true,
          direction: UpstreamRelays::Directions::DOWN
        )
      end

      teardown do
        UpstreamRelay.delete_all
        ApiKey.delete_all
      end

      # =========================================================================
      # Authentication
      # =========================================================================

      test "returns unauthorized without API key" do
        get api_v1_upstream_relays_url
        assert_response :unauthorized
        assert_equal "Invalid or missing API key", json_response["error"]
      end

      test "returns unauthorized with invalid API key" do
        get api_v1_upstream_relays_url, headers: { "Authorization" => "Bearer invalid_token" }
        assert_response :unauthorized
      end

      test "returns unauthorized with revoked API key" do
        @api_key.revoke!
        get api_v1_upstream_relays_url, headers: @auth_headers
        assert_response :unauthorized
      end

      test "updates last_used_at on successful authentication" do
        assert_nil @api_key.last_used_at
        get api_v1_upstream_relays_url, headers: @auth_headers
        assert_response :success
        @api_key.reload
        assert_not_nil @api_key.last_used_at
      end

      # =========================================================================
      # GET /api/v1/relays (index)
      # =========================================================================

      test "index returns all relays" do
        UpstreamRelay.create!(
          url: "wss://another.relay.com",
          direction: UpstreamRelays::Directions::UP
        )

        get api_v1_upstream_relays_url, headers: @auth_headers
        assert_response :success

        relays = json_response
        assert_equal 2, relays.size
      end

      test "index returns empty array when no relays exist" do
        UpstreamRelay.delete_all

        get api_v1_upstream_relays_url, headers: @auth_headers
        assert_response :success
        assert_equal [], json_response
      end

      # =========================================================================
      # GET /api/v1/relays/:id (show)
      # =========================================================================

      test "show returns relay details" do
        get api_v1_upstream_relay_url(@relay), headers: @auth_headers
        assert_response :success

        relay = json_response
        assert_equal @relay.url, relay["url"]
        assert_equal @relay.enabled, relay["enabled"]
        assert_equal @relay.direction, relay["direction"]
      end

      test "show returns not found for non-existent relay" do
        get api_v1_upstream_relay_url(id: "00000000-0000-0000-0000-000000000000"), headers: @auth_headers
        assert_response :not_found
        assert_equal "Resource not found", json_response["error"]
      end

      # =========================================================================
      # POST /api/v1/relays (create)
      # =========================================================================

      test "create creates a new relay with valid params" do
        relay_params = {
          upstream_relay: {
            url: "wss://new.relay.com",
            enabled: true,
            backfill: false,
            negentropy: true,
            direction: UpstreamRelays::Directions::BOTH,
            notes: "A new relay"
          }
        }

        assert_difference("UpstreamRelay.count", 1) do
          post api_v1_upstream_relays_url, params: relay_params, headers: @auth_headers
        end

        assert_response :created

        relay = json_response
        assert_equal "wss://new.relay.com", relay["url"]
        assert_equal true, relay["enabled"]
        assert_equal false, relay["backfill"]
        assert_equal true, relay["negentropy"]
        assert_equal "both", relay["direction"]
        assert_equal "A new relay", relay["notes"]
      end

      test "create with minimal params uses defaults" do
        relay_params = {
          upstream_relay: {
            url: "wss://minimal.relay.com"
          }
        }

        post api_v1_upstream_relays_url, params: relay_params, headers: @auth_headers
        assert_response :created

        relay = json_response
        assert_equal true, relay["enabled"]
        assert_equal true, relay["backfill"]
        assert_equal false, relay["negentropy"]
        assert_equal "down", relay["direction"]
      end

      test "create returns errors for invalid params" do
        relay_params = {
          upstream_relay: {
            url: "",
            direction: "invalid"
          }
        }

        assert_no_difference("UpstreamRelay.count") do
          post api_v1_upstream_relays_url, params: relay_params, headers: @auth_headers
        end

        assert_response :unprocessable_entity
        errors = json_response["errors"]
        assert_includes errors, "Url can't be blank"
        assert_includes errors, "Direction is not included in the list"
      end

      test "create returns error for duplicate URL" do
        relay_params = {
          upstream_relay: {
            url: @relay.url
          }
        }

        post api_v1_upstream_relays_url, params: relay_params, headers: @auth_headers
        assert_response :unprocessable_entity
        assert_includes json_response["errors"], "Url has already been taken"
      end

      test "create returns error for invalid URL format" do
        relay_params = {
          upstream_relay: {
            url: "http://invalid.relay.com"
          }
        }

        post api_v1_upstream_relays_url, params: relay_params, headers: @auth_headers
        assert_response :unprocessable_entity
        assert json_response["errors"].any? { |e| e.include?("WebSocket URL") }
      end

      test "create with config overrides" do
        relay_params = {
          upstream_relay: {
            url: "wss://configured.relay.com",
            config: {
              batch_size: 50,
              max_concurrent_connections: 5
            }
          }
        }

        post api_v1_upstream_relays_url, params: relay_params, headers: @auth_headers
        assert_response :created

        relay = UpstreamRelay.find_by(url: "wss://configured.relay.com")
        assert_equal 50, relay.config.batch_size
        assert_equal 5, relay.config.max_concurrent_connections
      end

      # =========================================================================
      # PATCH /api/v1/relays/:id (update)
      # =========================================================================

      test "update modifies relay attributes" do
        relay_params = {
          upstream_relay: {
            enabled: false,
            notes: "Updated notes"
          }
        }

        patch api_v1_upstream_relay_url(@relay), params: relay_params, headers: @auth_headers
        assert_response :success

        @relay.reload
        assert_equal false, @relay.enabled
        assert_equal "Updated notes", @relay.notes
      end

      test "update can change direction" do
        relay_params = {
          upstream_relay: {
            direction: UpstreamRelays::Directions::BOTH
          }
        }

        patch api_v1_upstream_relay_url(@relay), params: relay_params, headers: @auth_headers
        assert_response :success

        @relay.reload
        assert_equal "both", @relay.direction
      end

      test "update returns errors for invalid params" do
        relay_params = {
          upstream_relay: {
            url: "invalid-url"
          }
        }

        patch api_v1_upstream_relay_url(@relay), params: relay_params, headers: @auth_headers
        assert_response :unprocessable_entity
        assert json_response["errors"].any? { |e| e.include?("WebSocket URL") }
      end

      test "update returns not found for non-existent relay" do
        relay_params = {
          upstream_relay: {
            enabled: false
          }
        }

        patch api_v1_upstream_relay_url(id: "00000000-0000-0000-0000-000000000000"), params: relay_params, headers: @auth_headers
        assert_response :not_found
      end

      test "update can modify config" do
        relay_params = {
          upstream_relay: {
            config: { batch_size: 200 }
          }
        }

        patch api_v1_upstream_relay_url(@relay), params: relay_params, headers: @auth_headers
        assert_response :success

        @relay.reload
        assert_equal 200, @relay.config.batch_size
      end

      # =========================================================================
      # DELETE /api/v1/relays/:id (destroy)
      # =========================================================================

      test "destroy deletes the relay" do
        assert_difference("UpstreamRelay.count", -1) do
          delete api_v1_upstream_relay_url(@relay), headers: @auth_headers
        end

        assert_response :no_content
      end

      test "destroy returns not found for non-existent relay" do
        delete api_v1_upstream_relay_url(id: "00000000-0000-0000-0000-000000000000"), headers: @auth_headers
        assert_response :not_found
      end

      # =========================================================================
      # JSON Response Format
      # =========================================================================

      test "index response is valid JSON" do
        get api_v1_upstream_relays_url, headers: @auth_headers
        assert_response :success
        assert_nothing_raised { JSON.parse(response.body) }
      end

      private

      def json_response
        JSON.parse(response.body)
      end
    end
  end
end
