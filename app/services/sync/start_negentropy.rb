# frozen_string_literal: true

module Sync
  # DEPRECATED: Use Sync::SyncWithNegentropy instead.
  # This alias will be removed in the next major version.
  #
  # Performs Negentropy (NIP-77) set reconciliation with a remote relay.
  # Downloads events we need and schedules uploads for events we have.
  StartNegentropy = SyncWithNegentropy
end
