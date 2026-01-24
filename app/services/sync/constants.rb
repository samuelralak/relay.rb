# frozen_string_literal: true

module Sync
  module Constants
    module Timeouts
      FETCH_BATCH = 10        # Timeout per batch for event fetching
      NEGENTROPY_SYNC = 300   # Timeout for full Negentropy reconciliation (5 minutes)
      CONDITION_WAIT = 30     # Wait time for condition variable
    end

    module Batches
      DEFAULT_FETCH = 100     # Default batch size for fetching events
      MAX_UPLOAD = 1000       # Maximum events to upload in one operation
    end

    module SubscriptionPrefixes
      FETCH = "fetch_"        # Prefix for fetch operation subscription IDs
      NEGENTROPY = "neg_"     # Prefix for Negentropy subscription IDs
    end

    module IdLengths
      FETCH_ID = 4            # SecureRandom.hex length for fetch subscription IDs
      NEGENTROPY_ID = 8       # SecureRandom.hex length for Negentropy subscription IDs
    end
  end
end
