# frozen_string_literal: true

# NIP-11: Relay Information Document
# https://github.com/nostr-protocol/nips/blob/master/11.md
Rails.application.config.relay_info = {
  name: ENV.fetch("RELAY_NAME", "relay_rb"),
  description: ENV.fetch("RELAY_DESCRIPTION", "A Nostr relay built with Ruby on Rails"),
  pubkey: ENV["RELAY_PUBKEY"],
  contact: ENV["RELAY_CONTACT"],
  supported_nips: [ 1, 9, 11, 40, 42, 50, 70 ],
  software: ENV.fetch("RELAY_SOFTWARE", "https://github.com/samuelralak/relay.rb"),
  version: ENV.fetch("RELAY_VERSION", "0.1.0"),
  relay_url: ENV["RELAY_URL"],  # NIP-42: Required for AUTH challenge validation
  limitation: {
    max_message_length: 16_384,
    max_subscriptions: 20,
    max_subid_length: 64,
    max_filters: 10,
    max_limit: 5_000,
    max_event_tags: 100,
    max_content_length: 65_535,
    default_limit: 500,
    auth_required: ENV.fetch("AUTH_REQUIRED", "false") == "true",  # NIP-42: require auth for ALL events
    payment_required: false,
    restrict_dm_access: ENV.fetch("RESTRICT_DM_ACCESS", "false") == "true",  # NIP-42: require auth for DM kinds
    auth_timeout_seconds: 600,  # NIP-42: ±10 minutes tolerance for AUTH event timestamps
    search_query_max_length: 256,  # NIP-50
    search_max_limit: 500,         # NIP-50
    ping_interval: 20              # WebSocket keepalive (Heroku idle timeout is 55s)
  }
}

# Configure NostrRelay library after Rails loads
Rails.application.config.after_initialize do
  NostrRelay::Config.relay_info = Rails.application.config.relay_info

  NostrRelay::Config.configure do |config|
    # Adapters - application provides implementations matching expected API
    config.event_repository = Event                    # responds to .matching_filters(filters)
    config.event_serializer = Events::EventSerializer  # responds to .serialize(event)
    config.event_processor = Events::ProcessIncoming   # responds to .call(event_data:)
  end

  # Validate all required adapters are configured
  NostrRelay::Config.validate!

  # Log Redis pub/sub status
  if defined?(NostrRelay::RedisPubsub) && NostrRelay::RedisPubsub.enabled?
    AppLogger[:NostrRelay].info "Redis pub/sub enabled for cross-worker broadcasts"
  else
    AppLogger[:NostrRelay].info "Redis pub/sub disabled (REDIS_URL not set)"
  end
end
