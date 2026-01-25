# frozen_string_literal: true

module ApiKeys
  module Authentication
    def authenticate(token)
      return nil if token.blank?

      digest = OpenSSL::HMAC.hexdigest("SHA256", ApiKeys::Constants::HMAC_SECRET, token)
      active.find_by(key_digest: digest)
    end
  end
end
