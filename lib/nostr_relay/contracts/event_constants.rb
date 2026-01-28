# frozen_string_literal: true

module NostrRelay
  module Contracts
    # Shared constants for Nostr event validation.
    # Used by EventContract and AuthEventContract.
    module EventConstants
      HEX64 = /\A[a-f0-9]{64}\z/i
      HEX128 = /\A[a-f0-9]{128}\z/i
    end
  end
end
