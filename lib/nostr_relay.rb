# frozen_string_literal: true

require_relative "nostr_relay/config"
require_relative "nostr_relay/lifecycle"
require_relative "nostr_relay/filter_matcher"
require_relative "nostr_relay/connection_registry"
require_relative "nostr_relay/redis_pubsub"
require_relative "nostr_relay/messages"
require_relative "nostr_relay/connection"
require_relative "nostr_relay/router"
require_relative "nostr_relay/subscription"
require_relative "nostr_relay/subscriptions"

# Handlers
require_relative "nostr_relay/handlers/event"
require_relative "nostr_relay/handlers/req"
require_relative "nostr_relay/handlers/close"

# Contracts
require_relative "nostr_relay/contracts/event_contract"
require_relative "nostr_relay/contracts/filter_contract"

# Websocket
require_relative "nostr_relay/websocket/middleware"

module NostrRelay
  class Error < StandardError; end
end
