# frozen_string_literal: true

module ApiKeys
  module Tokenable
    extend ActiveSupport::Concern

    included do
      attr_accessor :token # Virtual, only set on creation

      before_validation :generate_token, on: :create
    end

    def revoke!
      update!(revoked_at: Time.current)
    end

    def active?
      revoked_at.nil?
    end

    def touch_last_used!
      update_column(:last_used_at, Time.current)
    end

    private

    def generate_token
      raw = SecureRandom.urlsafe_base64(32)
      self.token = "#{ApiKeys::Constants::PREFIX}#{raw}"
      self.key_prefix = token[0, 8]
      self.key_digest = OpenSSL::HMAC.hexdigest("SHA256", ApiKeys::Constants::HMAC_SECRET, token)
    end
  end
end
