# frozen_string_literal: true

namespace :relay_sync do
  desc "Start the relay sync daemon (connects to all configured relays)"
  task start: :environment do
    puts "Starting RelaySync daemon..."

    RelaySync.start

    # Keep the process running
    trap("INT") do
      puts "\nStopping..."
      RelaySync.stop
      exit
    end

    trap("TERM") do
      puts "\nStopping..."
      RelaySync.stop
      exit
    end

    puts "Connected. Press Ctrl+C to stop."
    loop { sleep 1 }
  end

  desc "Run backfill from upstream relays"
  task :backfill, [:hours] => :environment do |_t, args|
    hours = (args[:hours] || 24).to_i
    since = hours.hours.ago.to_i

    puts "Starting backfill since #{Time.at(since)} (#{hours} hours ago)..."

    RelaySync.start
    sleep 2 # Wait for connections

    RelaySync.manager.start_backfill(since: since)

    puts "Backfill jobs queued. Run Solid Queue workers to process."
  end

  desc "Start streaming sync (real-time events)"
  task stream: :environment do
    puts "Starting streaming sync..."

    RelaySync.start
    sleep 2 # Wait for connections

    RelaySync.manager.start_streaming

    # Keep the process running
    trap("INT") do
      puts "\nStopping..."
      RelaySync.stop
      exit
    end

    trap("TERM") do
      puts "\nStopping..."
      RelaySync.stop
      exit
    end

    puts "Streaming. Press Ctrl+C to stop."
    loop { sleep 1 }
  end

  desc "Upload local events to a relay"
  task :upload, [:relay_url] => :environment do |_t, args|
    relay_url = args[:relay_url]

    unless relay_url
      puts "Usage: rake relay_sync:upload[wss://relay.example.com]"
      exit 1
    end

    puts "Uploading events to #{relay_url}..."

    RelaySync.start
    sleep 2 # Wait for connection

    RelaySync.manager.upload_events(relay_url)

    puts "Upload job queued. Run Solid Queue workers to process."
  end

  desc "Run Negentropy sync with a specific relay"
  task :negentropy, [:relay_url, :direction] => :environment do |_t, args|
    relay_url = args[:relay_url]
    direction = args[:direction] || "down"

    unless relay_url
      puts "Usage: rake relay_sync:negentropy[wss://relay.example.com,down|up|both]"
      exit 1
    end

    puts "Starting Negentropy sync with #{relay_url} (direction: #{direction})..."

    RelaySync.start
    sleep 2 # Wait for connection

    filter = {
      kinds: RelaySync.configuration.sync_settings.event_kinds,
      since: RelaySync.configuration.sync_settings.backfill_since.ago.to_i
    }

    RelaySync.manager.start_negentropy_sync(relay_url, filter: filter, direction: direction)

    puts "Negentropy sync job queued. Run Solid Queue workers to process."
  end

  desc "Show sync status"
  task status: :environment do
    status = RelaySync.status

    puts "\n=== RelaySync Status ==="
    puts ""

    puts "Connections:"
    if status[:connections].empty?
      puts "  (none)"
    else
      status[:connections].each do |url, info|
        puts "  #{url}:"
        puts "    State: #{info[:state]}"
        puts "    Subscriptions: #{info[:subscriptions].join(', ').presence || 'none'}"
        puts "    Reconnect attempts: #{info[:reconnect_attempts]}"
      end
    end

    puts ""
    puts "Sync States:"
    if status[:sync_states].empty?
      puts "  (none)"
    else
      status[:sync_states].each do |state|
        puts "  #{state[:relay_url]}:"
        puts "    Direction: #{state[:direction]}"
        puts "    Status: #{state[:status]}"
        puts "    Downloaded: #{state[:events_downloaded]}"
        puts "    Uploaded: #{state[:events_uploaded]}"
        puts "    Last sync: #{state[:last_synced_at] || 'never'}"
      end
    end

    puts ""
    puts "Event counts:"
    puts "  Total events: #{Event.count}"
    puts "  Active events: #{Event.active.count}"
    puts "  Sync states: #{SyncState.count}"
  end

  desc "Reset sync state for a relay"
  task :reset, [:relay_url] => :environment do |_t, args|
    relay_url = args[:relay_url]

    if relay_url
      states = SyncState.where(relay_url: relay_url)
      count = states.count
      states.destroy_all
      puts "Reset #{count} sync state(s) for #{relay_url}"
    else
      count = SyncState.count
      SyncState.destroy_all
      puts "Reset all #{count} sync states"
    end
  end

  desc "List configured relays"
  task relays: :environment do
    puts "\n=== Configured Relays ==="
    puts ""

    RelaySync.configuration.upstream_relays.each do |relay|
      puts "#{relay.url}:"
      puts "  Enabled: #{relay.enabled?}"
      puts "  Backfill: #{relay.backfill?}"
      puts "  Negentropy: #{relay.negentropy?}"
      puts "  Direction: #{relay.direction}"
      puts ""
    end
  end
end
