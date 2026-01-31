# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Upstream Relays
RELAYS = [
  # NIP-77 relays
  {
    url: "wss://relay.snort.social",
    enabled: true,
    backfill: true,
    negentropy: true,
    direction: UpstreamRelays::Directions::DOWN
  },
  {
    url: "wss://nostr.oxtr.dev",
    enabled: true,
    backfill: true,
    negentropy: true,
    direction: UpstreamRelays::Directions::DOWN
  },
  {
    url: "wss://relay.primal.net",
    enabled: true,
    backfill: true,
    negentropy: false,
    direction: UpstreamRelays::Directions::DOWN,
    notes: "Relay returns 'negentropy disabled' - doesn't support NIP-77"
  },
  {
    url: "wss://premium.primal.net",
    enabled: true,
    backfill: true,
    negentropy: true,
    direction: UpstreamRelays::Directions::DOWN,
    notes: "strfry v1.0.3, confirmed NIP-77 support"
  },
  {
    url: "wss://purplerelay.com",
    enabled: true,
    backfill: true,
    negentropy: true,
    direction: UpstreamRelays::Directions::DOWN,
    notes: "strfry v407-7701d55"
  },
  {
    url: "wss://relay.noderunners.network",
    enabled: true,
    backfill: true,
    negentropy: true,
    direction: UpstreamRelays::Directions::DOWN,
    notes: "strfry 1.0.3"
  },
  {
    url: "wss://relay.mostr.pub",
    enabled: true,
    backfill: true,
    negentropy: true,
    direction: UpstreamRelays::Directions::DOWN,
    notes: "strfry 1.0.4"
  },
  {
    url: "wss://offchain.pub",
    enabled: true,
    backfill: true,
    negentropy: true,
    direction: UpstreamRelays::Directions::DOWN
  },
  {
    url: "wss://nostr.mom",
    enabled: true,
    backfill: true,
    negentropy: false,
    direction: UpstreamRelays::Directions::DOWN,
    notes: "strfry but negentropy disabled on this instance"
  },
  {
    url: "wss://relay.current.fyi",
    enabled: false,
    backfill: true,
    negentropy: false,
    direction: UpstreamRelays::Directions::DOWN,
    notes: "DNS resolution failed - relay may be down"
  },
  {
    url: "wss://pyramid.fiatjaf.com",
    enabled: true,
    backfill: true,
    negentropy: true,
    direction: UpstreamRelays::Directions::DOWN,
    notes: "Khatru-based, works without AUTH for reads"
  },

  # Standard relays for streaming (no negentropy)
  {
    url: "wss://relay.damus.io",
    enabled: true,
    backfill: false,
    negentropy: false,
    direction: UpstreamRelays::Directions::DOWN,
    notes: "Has query limits"
  },
  {
    url: "wss://nos.lol",
    enabled: true,
    backfill: true,
    negentropy: false,
    direction: UpstreamRelays::Directions::DOWN,
    notes: "strfry 1.0.4, but negentropy disabled on this instance"
  }
].freeze

puts "Seeding upstream relays..."

RELAYS.each do |relay_attrs|
  relay = UpstreamRelay.find_or_initialize_by(url: relay_attrs[:url])

  if relay.new_record?
    relay.assign_attributes(relay_attrs)
    relay.save!
    puts "  Created: #{relay.url}"
  else
    puts "  Exists:  #{relay.url}"
  end
end

puts "Done. #{UpstreamRelay.count} relays in database."
