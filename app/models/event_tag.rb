# frozen_string_literal: true

class EventTag < ApplicationRecord
  include SoftDeletable
  include EventTags::Queryable
  include EventTags::Identifiable

  # Associations
  belongs_to :event, inverse_of: :event_tags

  # Validations
  validates :tag_name, presence: true, length: { is: 1 }
  validates :tag_value, presence: true, length: { maximum: 255 }
  validates :tag_index, presence: true,
                        numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :nostr_created_at, presence: true
  validates :kind, presence: true, numericality: { only_integer: true }
end
