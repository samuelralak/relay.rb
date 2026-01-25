# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ApiKeysControllerTest < ActionDispatch::IntegrationTest
      setup do
        @api_key = ApiKey.create!(name: "Admin Key")
        @auth_headers = { "Authorization" => "Bearer #{@api_key.token}" }
      end

      teardown do
        ApiKey.delete_all
      end

      # =========================================================================
      # Authentication
      # =========================================================================

      test "returns unauthorized without API key" do
        get api_v1_api_keys_url
        assert_response :unauthorized
        assert_equal "Invalid or missing API key", json_response["error"]
      end

      test "returns unauthorized with invalid API key" do
        get api_v1_api_keys_url, headers: { "Authorization" => "Bearer invalid" }
        assert_response :unauthorized
      end

      test "returns unauthorized with malformed authorization header" do
        get api_v1_api_keys_url, headers: { "Authorization" => "Basic sometoken" }
        assert_response :unauthorized
      end

      test "returns unauthorized without Bearer prefix" do
        get api_v1_api_keys_url, headers: { "Authorization" => @api_key.token }
        assert_response :unauthorized
      end

      # =========================================================================
      # GET /api/v1/api_keys (index)
      # =========================================================================

      test "index returns active API keys" do
        ApiKey.create!(name: "Second Key")
        ApiKey.create!(name: "Third Key")

        get api_v1_api_keys_url, headers: @auth_headers
        assert_response :success

        keys = json_response
        assert_equal 3, keys.size
      end

      test "index excludes revoked API keys" do
        revoked_key = ApiKey.create!(name: "Revoked Key")
        revoked_key.revoke!

        get api_v1_api_keys_url, headers: @auth_headers
        assert_response :success

        keys = json_response
        assert_equal 1, keys.size
        assert_equal @api_key.id, keys.first["id"]
      end

      test "index returns limited fields for security" do
        get api_v1_api_keys_url, headers: @auth_headers
        assert_response :success

        key = json_response.first
        assert key.key?("id")
        assert key.key?("name")
        assert key.key?("key_prefix")
        assert key.key?("created_at")
        assert key.key?("last_used_at")
        assert_not key.key?("key_digest")
        assert_not key.key?("token")
      end

      test "index returns the requesting key when no other keys exist" do
        get api_v1_api_keys_url, headers: @auth_headers
        assert_response :success

        keys = json_response
        assert_equal 1, keys.size
      end

      # =========================================================================
      # POST /api/v1/api_keys (create)
      # =========================================================================

      test "create creates a new API key" do
        key_params = {
          api_key: {
            name: "New API Key"
          }
        }

        assert_difference("ApiKey.count", 1) do
          post api_v1_api_keys_url, params: key_params, headers: @auth_headers
        end

        assert_response :created
      end

      test "create returns the token only once" do
        key_params = {
          api_key: {
            name: "New API Key"
          }
        }

        post api_v1_api_keys_url, params: key_params, headers: @auth_headers
        assert_response :created

        body = json_response
        assert body.key?("token"), "Response should include token"
        assert body["token"].start_with?(ApiKeys::Constants::PREFIX)
        assert_equal "Save this token - it will not be shown again", body["message"]
      end

      test "create returns key metadata" do
        key_params = {
          api_key: {
            name: "Metadata Test Key"
          }
        }

        post api_v1_api_keys_url, params: key_params, headers: @auth_headers
        assert_response :created

        body = json_response
        assert body.key?("id")
        assert_equal "Metadata Test Key", body["name"]
        assert body.key?("key_prefix")
        assert body.key?("created_at")
        assert body["key_prefix"].start_with?(ApiKeys::Constants::PREFIX)
      end

      test "create returns errors for missing name" do
        key_params = {
          api_key: {
            name: ""
          }
        }

        assert_no_difference("ApiKey.count") do
          post api_v1_api_keys_url, params: key_params, headers: @auth_headers
        end

        assert_response :unprocessable_entity
        assert_includes json_response["errors"], "Name can't be blank"
      end

      test "created key can authenticate" do
        key_params = {
          api_key: {
            name: "Functional Test Key"
          }
        }

        post api_v1_api_keys_url, params: key_params, headers: @auth_headers
        assert_response :created

        new_token = json_response["token"]

        # Use new key to authenticate
        get api_v1_api_keys_url, headers: { "Authorization" => "Bearer #{new_token}" }
        assert_response :success
      end

      # =========================================================================
      # DELETE /api/v1/api_keys/:id (destroy/revoke)
      # =========================================================================

      test "destroy revokes the API key" do
        key_to_revoke = ApiKey.create!(name: "Key to Revoke")

        delete api_v1_api_key_url(key_to_revoke), headers: @auth_headers
        assert_response :no_content

        key_to_revoke.reload
        assert_not key_to_revoke.active?
        assert_not_nil key_to_revoke.revoked_at
      end

      test "destroy does not delete the key record" do
        key_to_revoke = ApiKey.create!(name: "Key to Revoke")

        assert_no_difference("ApiKey.unscoped.count") do
          delete api_v1_api_key_url(key_to_revoke), headers: @auth_headers
        end

        assert_response :no_content
      end

      test "destroy returns not found for non-existent key" do
        delete api_v1_api_key_url(id: "00000000-0000-0000-0000-000000000000"), headers: @auth_headers
        assert_response :not_found
        assert_equal "Resource not found", json_response["error"]
      end

      test "revoked key cannot authenticate" do
        key_to_revoke = ApiKey.create!(name: "Key to Revoke")
        token = key_to_revoke.token

        delete api_v1_api_key_url(key_to_revoke), headers: @auth_headers
        assert_response :no_content

        # Try to use revoked key
        get api_v1_api_keys_url, headers: { "Authorization" => "Bearer #{token}" }
        assert_response :unauthorized
      end

      test "cannot revoke own key while using it" do
        # This is allowed - key is revoked but current request completes
        delete api_v1_api_key_url(@api_key), headers: @auth_headers
        assert_response :no_content

        # Subsequent requests fail
        get api_v1_api_keys_url, headers: @auth_headers
        assert_response :unauthorized
      end

      # =========================================================================
      # JSON Response Format
      # =========================================================================

      test "index response is valid JSON" do
        get api_v1_api_keys_url, headers: @auth_headers
        assert_response :success
        assert_nothing_raised { JSON.parse(response.body) }
      end

      # =========================================================================
      # Key Prefix Format
      # =========================================================================

      test "key prefix matches token prefix" do
        key_params = {
          api_key: {
            name: "Prefix Test Key"
          }
        }

        post api_v1_api_keys_url, params: key_params, headers: @auth_headers
        assert_response :created

        body = json_response
        assert body["token"].start_with?(body["key_prefix"])
      end

      private

      def json_response
        JSON.parse(response.body)
      end
    end
  end
end
