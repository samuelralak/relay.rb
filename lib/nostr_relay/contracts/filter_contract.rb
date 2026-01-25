# frozen_string_literal: true

require "dry/validation"

module NostrRelay
  module Contracts
    # Validates a single filter object per NIP-01
    class FilterContract < Dry::Validation::Contract
      HEX64 = /\A[a-f0-9]{64}\z/i

      params do
        optional(:ids).array(:string)
        optional(:authors).array(:string)
        optional(:kinds).array(:integer)
        optional(:since).filled(:integer)
        optional(:until).filled(:integer)
        optional(:limit).filled(:integer)
        optional(:search).filled(:string)  # NIP-50: Search filter
      end

      rule(:ids).each do
        key.failure("must be 64 hex chars") unless value.match?(HEX64)
      end

      rule(:authors).each do
        key.failure("must be 64 hex chars") unless value.match?(HEX64)
      end

      rule(:limit) do
        max_limit = Config.max_limit
        key.failure("must be <= #{max_limit}") if value && value > max_limit
      end

      # NIP-50: Validate search query length
      rule(:search) do
        max_length = Config.search_query_max_length
        key.failure("must be <= #{max_length} characters") if value && value.length > max_length
      end

      # NIP-01: #e and #p tag filters must contain 64-char lowercase hex values
      rule do
        e_values = values.data[:"#e"] || values.data["#e"]
        if e_values.is_a?(Array)
          e_values.each do |v|
            unless v.is_a?(String) && v.match?(HEX64)
              key([ :"#e" ]).failure("must contain 64 hex chars")
              break
            end
          end
        end

        p_values = values.data[:"#p"] || values.data["#p"]
        if p_values.is_a?(Array)
          p_values.each do |v|
            unless v.is_a?(String) && v.match?(HEX64)
              key([ :"#p" ]).failure("must contain 64 hex chars")
              break
            end
          end
        end
      end
    end

    # Validates an array of filters from REQ message
    class FiltersContract < Dry::Validation::Contract
      params do
        required(:filters).array(:hash)
      end

      rule(:filters) do
        max_filters = Config.max_filters
        if value.empty?
          key.failure("must have at least one filter")
        elsif value.size > max_filters
          key.failure("cannot have more than #{max_filters} filters")
        else
          value.each_with_index do |filter, idx|
            result = FilterContract.new.call(filter)
            unless result.success?
              key.failure("filter[#{idx}]: #{result.errors.to_h}")
            end
          end
        end
      end
    end
  end
end
