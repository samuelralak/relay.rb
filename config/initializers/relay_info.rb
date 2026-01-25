# frozen_string_literal: true

# NIP-11: Relay Information Document
# https://github.com/nostr-protocol/nips/blob/master/11.md
Rails.application.config.relay_info = {
  name: ENV.fetch("RELAY_NAME", "relay_rb"),
  description: ENV.fetch("RELAY_DESCRIPTION", "A Nostr relay built with Ruby on Rails"),
  pubkey: ENV["RELAY_PUBKEY"],
  contact: ENV["RELAY_CONTACT"],
  supported_nips: [ 1, 9, 11, 40 ],
  software: "https://github.com/samuelralak/relay_rb",
  version: "0.1.0",
  limitation: {
    max_message_length: 16_384,
    max_subscriptions: 20,
    max_subid_length: 64,
    max_filters: 10,
    max_limit: 5_000,
    max_event_tags: 100,
    max_content_length: 65_535,
    default_limit: 500,
    auth_required: false,
    payment_required: false
  }
}

# Configure NostrRelay library with relay info and logger
NostrRelay::Config.relay_info = Rails.application.config.relay_info
NostrRelay::Config.logger = Rails.logger

# Configure adapters after models are loaded
Rails.application.config.after_initialize do
  NostrRelay::Config.configure do |config|
    # Adapters - application provides implementations matching expected API
    config.event_repository = Event                    # responds to .matching_filters(filters)
    config.event_serializer = Events::EventSerializer  # responds to .serialize(event)
    config.event_processor = Events::ProcessIncoming   # responds to .call(event_data:)
  end

  # Validate all required adapters are configured
  NostrRelay::Config.validate!
end
