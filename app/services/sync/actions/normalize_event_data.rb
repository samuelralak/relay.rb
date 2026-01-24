# frozen_string_literal: true

module Sync
  module Actions
    # Normalizes event data hash keys to symbols.
    # Handles nested hashes and arrays of hashes.
    class NormalizeEventData < BaseService
      option :event_data, type: Types::Hash

      def call
        Success(deep_symbolize(event_data))
      end

      private

      def deep_symbolize(hash)
        return hash unless hash.is_a?(Hash)

        hash.transform_keys(&:to_sym).transform_values do |v|
          case v
          when Hash then deep_symbolize(v)
          when Array then v.map { |i| i.is_a?(Hash) ? deep_symbolize(i) : i }
          else v
          end
        end
      end
    end
  end
end
