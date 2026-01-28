# frozen_string_literal: true

module Auth
  module Actions
    # Normalizes relay URLs for comparison in NIP-42 authentication.
    # Handles case differences, trailing slashes, and protocol variations.
    class NormalizeRelayUrl < BaseService
      option :url, type: Types::String

      def call
        return Failure[:invalid, "URL cannot be blank"] if url.blank?

        normalized = url
          .to_s
          .strip
          .downcase
          .gsub(%r{/+$}, "") # Remove trailing slashes

        Success(normalized_url: normalized)
      end
    end
  end
end
