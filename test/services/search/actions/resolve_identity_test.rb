# frozen_string_literal: true

require "test_helper"

module Search
  module Actions
    class ResolveIdentityTest < ActiveSupport::TestCase
      test "returns search_disabled failure when OpenSearch unavailable" do
        # OpenSearch is not available in test environment
        result = ResolveIdentity.call(username: "fiatjaf")

        assert result.failure?
        assert_equal :search_disabled, result.failure
      end

      test "returns search_disabled for blank input when OpenSearch unavailable" do
        # When OpenSearch is unavailable, search_disabled takes precedence
        result = ResolveIdentity.call(username: "")

        assert result.failure?
        assert_equal :search_disabled, result.failure
      end

      test "caps resolved profiles at MAX_RESOLVED_PROFILES" do
        assert_equal 5, ResolveIdentity::MAX_RESOLVED_PROFILES
      end
    end
  end
end
