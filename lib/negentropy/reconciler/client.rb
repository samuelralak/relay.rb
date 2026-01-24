# frozen_string_literal: true

module Negentropy
  class Reconciler
    # Client-side reconciler for initiating sync
    class Client < Reconciler
      # Process response from server
      # Same as reconcile but semantically for client use
      alias process_response reconcile
    end
  end
end
