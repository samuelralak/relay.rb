# frozen_string_literal: true

module Search
  module Actions
    class ParseQuery < BaseService
      option :query, type: Types::String

      def call
        extensions = extract_extensions
        phrases = extract_phrases
        exclusions = extract_exclusions
        excluded_phrases = extract_excluded_phrases
        from_authors = extract_from_authors(extensions)

        raw_terms = extract_terms
        remaining_terms, pubkey_terms = partition_pubkey_terms(raw_terms)

        query_type = classify_query(phrases:, exclusions:, excluded_phrases:)
        hint = identity_hint?(remaining_terms, pubkey_terms)

        Success(
          terms: remaining_terms,
          phrases:,
          exclusions:,
          excluded_phrases:,
          extensions:,
          from_authors:,
          pubkey_terms:,
          query_type:,
          identity_hint: hint
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

      # Detect and extract pubkey-like terms (npub or 64-char hex).
      # These are useless for content search but valuable for author filtering.
      def partition_pubkey_terms(terms)
        pubkeys = []
        remaining = []

        terms.each do |term|
          result = ConvertNpub.call(identifier: term)
          if result.success?
            pubkeys << result.value![:pubkey]
          else
            remaining << term
          end
        end

        [ remaining, pubkeys ]
      end

      # Only phrases and exclusions affect query structure (must/must_not clauses).
      # Extensions like from:, include: are handled separately and don't change
      # whether we use single-match vs per-term query optimization.
      def classify_query(phrases:, exclusions:, excluded_phrases:)
        phrases.empty? && exclusions.empty? && excluded_phrases.empty? ? :plain : :advanced
      end

      # Heuristic: single short alphanumeric term is likely a username search,
      # or pubkey terms are present (explicit identity lookup).
      def identity_hint?(terms, pubkey_terms)
        return true if pubkey_terms.any?

        terms.size == 1 && terms.first.length <= 30 && terms.first.match?(/\A[a-z0-9_.-]+\z/)
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
          result = ConvertNpub.call(identifier:)
          result.success? ? result.value![:pubkey] : nil
        end
      end
    end
  end
end
