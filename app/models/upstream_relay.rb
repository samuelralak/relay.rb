# frozen_string_literal: true

class UpstreamRelay < ApplicationRecord
  URL_FORMAT = /\Awss?:\/\/.+\z/

  validates :url, presence: true, uniqueness: true, format: { with: URL_FORMAT, message: "must be a valid WebSocket URL (ws:// or wss://)" }
  validates :direction, inclusion: { in: UpstreamRelays::Directions::ALL }

  scope :enabled, -> { where(enabled: true) }
  scope :backfill_capable, -> { enabled.where(backfill: true) }
  scope :negentropy_capable, -> { enabled.where(negentropy: true) }
  scope :download_capable, -> { enabled.where(direction: UpstreamRelays::Directions::DOWNLOAD_CAPABLE) }
  scope :upload_capable, -> { enabled.where(direction: UpstreamRelays::Directions::UPLOAD_CAPABLE) }

  def self.find_by_url(url) = find_by(url:)

  def enabled? = enabled
  def backfill? = backfill
  def negentropy? = negentropy
  def download_enabled? = UpstreamRelays::Directions::DOWNLOAD_CAPABLE.include?(direction)
  def upload_enabled? = UpstreamRelays::Directions::UPLOAD_CAPABLE.include?(direction)

  def config
    UpstreamRelays::Config.new(attributes["config"] || {})
  end
end
