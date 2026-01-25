# frozen_string_literal: true

class ApiKey < ApplicationRecord
  extend ApiKeys::Authentication

  include SoftDeletable
  include ApiKeys::Tokenable

  validates :name, presence: true
  validates :key_digest, presence: true, uniqueness: true
  validates :key_prefix, presence: true

  scope :active, -> { where(revoked_at: nil) }
end
