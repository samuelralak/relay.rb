# frozen_string_literal: true

module EventTags
  module Identifiable
    extend ActiveSupport::Concern

    # Tag type checks
    def event_reference?
      tag_name == TagNames::EVENT
    end

    def pubkey_reference?
      tag_name == TagNames::PUBKEY
    end

    def addressable_reference?
      tag_name == TagNames::ADDRESSABLE
    end

    def identifier_tag?
      tag_name == TagNames::IDENTIFIER
    end

    def hashtag?
      tag_name == TagNames::HASHTAG
    end

    def kind_reference?
      tag_name == TagNames::KIND
    end

    def relay_reference?
      tag_name == TagNames::REFERENCE
    end

    # Check if tag name is indexable (single letter a-z, A-Z)
    def indexable?
      TagNames.indexable?(tag_name)
    end

    # Check if this is a reference tag (e, p, or a)
    def reference_tag?
      event_reference? || pubkey_reference? || addressable_reference?
    end
  end
end
