# frozen_string_literal: true

module Negentropy
  # Client-side reconciler for initiating sync
  class ClientReconciler < Reconciler
    # Process response from server
    # Same as reconcile but semantically for client use
    alias process_response reconcile
  end
end
