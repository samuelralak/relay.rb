# frozen_string_literal: true

class Event < ApplicationRecord
  include Events::Classifiable
  include Events::Expirable
  include Events::Taggable
  include Events::Filterable

  acts_as_paranoid

  # Associations
  has_many :event_tags, dependent: :delete_all, inverse_of: :event

  # Validations
  validates :event_id, presence: true,
                       uniqueness: true,
                       length: { is: 64 },
                       format: { with: Events::Kinds::HEX_PATTERN, message: "must be lowercase hex" }

  validates :pubkey, presence: true,
                     length: { is: 64 },
                     format: { with: Events::Kinds::HEX_PATTERN, message: "must be lowercase hex" }

  validates :nostr_created_at, presence: true

  validates :kind, presence: true,
                   numericality: { only_integer: true,
                                   greater_than_or_equal_to: 0,
                                   less_than_or_equal_to: 65_535 }

  validate :tags_is_array  # Empty tags [] is valid in Nostr, but must be an array
  validates :content, presence: true, allow_blank: true

  validates :sig, presence: true,
                  length: { is: 128 },
                  format: { with: Events::Kinds::HEX_PATTERN, message: "must be lowercase hex" }

  validates :raw_event, presence: true
  validates :first_seen_at, presence: true

  private

  def tags_is_array
    errors.add(:tags, "must be an array") unless tags.is_a?(Array)
  end
end
