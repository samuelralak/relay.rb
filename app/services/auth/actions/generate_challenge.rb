# frozen_string_literal: true

module Auth
  module Actions
    # Generates a random challenge string for NIP-42 authentication.
    # Returns a 64-character hex string (32 bytes).
    class GenerateChallenge < BaseService
      CHALLENGE_BYTES = 32

      def call
        challenge = SecureRandom.hex(CHALLENGE_BYTES)
        Success(challenge:)
      end
    end
  end
end
