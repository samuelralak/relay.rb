# frozen_string_literal: true

module ApiKeys
  module Constants
    HMAC_SECRET = ENV.fetch("API_KEY_HMAC_SECRET")
    PREFIX = "rlk_"
  end
end
