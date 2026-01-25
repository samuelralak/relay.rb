# frozen_string_literal: true

module NostrRelay
  module Handlers
    # Handles CLOSE messages (unsubscribe).
    module Close
      module_function

      def call(connection:, sub_id:)
        Subscriptions.unsubscribe(connection.id, sub_id)
      end
    end
  end
end
