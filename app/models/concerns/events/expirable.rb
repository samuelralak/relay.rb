# frozen_string_literal: true

module Events
  module Expirable
    extend ActiveSupport::Concern

    included do
      scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

      before_validation :set_first_seen_at, on: :create
      before_validation :extract_and_set_expiration
    end

    def created_at_unix
      nostr_created_at&.to_i
    end

    def created_at_unix=(unix_timestamp)
      self.nostr_created_at = unix_timestamp ? Time.at(unix_timestamp).utc : nil
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    private

    def set_first_seen_at
      self.first_seen_at ||= Time.current
    end

    def extract_and_set_expiration
      expiration_tag = tags&.find { |tag| tag.is_a?(Array) && tag[0] == "expiration" }
      unix_ts = expiration_tag&.dig(1)&.to_i
      self.expires_at = unix_ts && unix_ts > 0 ? Time.at(unix_ts).utc : nil
    end
  end
end
