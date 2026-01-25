# frozen_string_literal: true

# NIP-50: OpenSearch client wrapper for search functionality
# Note: Uses RelaySearch namespace to avoid conflict with opensearch-ruby gem's OpenSearch::Client
module RelaySearch
  module Client
    class << self
      def client
        @client ||= build_client
      end

      def available?
        return false unless enabled?

        client.ping
      rescue StandardError
        false
      end

      def enabled?
        ENV["OPENSEARCH_URL"].present?
      end

      private

      def build_client
        OpenSearch::Client.new(
          url: ENV.fetch("OPENSEARCH_URL", "http://localhost:9200"),
          user: ENV["OPENSEARCH_USER"],
          password: ENV["OPENSEARCH_PASSWORD"],
          log: Rails.env.development?,
          transport_options: {
            ssl: { verify: ENV.fetch("OPENSEARCH_SSL_VERIFY", "false") != "false" },
            request: { timeout: 30 }
          }
        )
      end
    end
  end
end
