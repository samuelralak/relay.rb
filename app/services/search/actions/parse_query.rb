# frozen_string_literal: true

module Search
  module Actions
    class ParseQuery < BaseService
      option :query, type: Types::String

      def call
        extensions = extract_extensions

        Success(
          terms: extract_terms,
          phrases: extract_phrases,
          exclusions: extract_exclusions,
          excluded_phrases: extract_excluded_phrases,
          extensions: extensions,
          from_authors: extract_from_authors(extensions)
        )
      end

      private

      def extract_phrases
        # Extract quoted phrases (not preceded by -)
        query.scan(/(?<!-)"([^"]+)"/).flatten.map(&:downcase)
      end

      def extract_excluded_phrases
        # Extract -"excluded phrases"
        query.scan(/-"([^"]+)"/).flatten.map(&:downcase)
      end

      def extract_exclusions
        # Extract -term patterns (not followed by quote)
        query.scan(/(?:^|\s)-(\w+)(?!")/).flatten.map(&:downcase)
      end

      def extract_extensions
        # Extract key:value patterns
        query.scan(/(\w+):(\S+)/).to_h
      end

      def extract_terms
        # Remove phrases, exclusions, and extensions, then split remaining
        cleaned = query.dup
        cleaned.gsub!(/-?"[^"]+"/, "")          # Remove all quoted phrases (including excluded)
        cleaned.gsub!(/-\w+/, "")               # Remove exclusions
        cleaned.gsub!(/\w+:\S+/, "")            # Remove extensions
        cleaned.split.map(&:downcase).reject(&:blank?)
      end

      # Extract and convert from: extension to hex pubkeys.
      # Supports multiple from: values (comma-separated or repeated).
      # @param extensions [Hash] parsed extensions
      # @return [Array<String>] hex pubkeys (invalid ones are silently ignored)
      def extract_from_authors(extensions)
        from_value = extensions["from"]
        return [] if from_value.blank?

        # Support comma-separated values: from:npub1,npub2
        identifiers = from_value.split(",").map(&:strip).reject(&:blank?)

        identifiers.filter_map do |identifier|
          result = ConvertNpub.call(identifier: identifier)
          result.success? ? result.value![:pubkey] : nil
        end
      end
    end
  end
end
