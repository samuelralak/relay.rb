# frozen_string_literal: true

module Events
  module Taggable
    extend ActiveSupport::Concern

    included do
      before_validation :extract_and_set_d_tag
      after_create :create_event_tags
    end

    private

    def extract_and_set_d_tag
      return unless addressable?

      d_tag_array = tags&.find { |tag| tag.is_a?(Array) && tag[0] == "d" }
      self.d_tag = d_tag_array&.dig(1) || ""
    end

    def create_event_tags
      indexable_tags = tags.each_with_index.filter_map do |tag, index|
        next unless valid_indexable_tag?(tag)

        {
          event_id: id,
          tag_name: tag[0],
          tag_value: tag[1],
          tag_index: index,
          nostr_created_at: nostr_created_at,
          kind: kind,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      EventTag.insert_all(indexable_tags) if indexable_tags.present?
    end

    def valid_indexable_tag?(tag)
      tag.is_a?(Array) &&
        tag.length >= 2 &&
        tag[0].is_a?(String) &&
        tag[0].length == 1 &&
        tag[1].is_a?(String) &&
        tag[1].length <= 255
    end
  end
end
