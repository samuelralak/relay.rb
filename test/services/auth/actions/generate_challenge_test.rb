# frozen_string_literal: true

require "test_helper"

module Auth
  module Actions
    class GenerateChallengeTest < ActiveSupport::TestCase
      test "generates a 64-character hex challenge" do
        result = GenerateChallenge.call

        assert result.success?
        assert_equal 64, result.value![:challenge].length
        assert_match(/\A[a-f0-9]+\z/, result.value![:challenge])
      end

      test "generates unique challenges" do
        challenges = 10.times.map { GenerateChallenge.call.value![:challenge] }

        assert_equal challenges.uniq.length, challenges.length
      end
    end
  end
end
