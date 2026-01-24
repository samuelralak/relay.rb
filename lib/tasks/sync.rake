# frozen_string_literal: true

# Utility rake tasks for sync management
# Note: Sync orchestration is now handled by Solid Queue recurring jobs
# These tasks are for manual operations and debugging

namespace :sync do
  desc "Boot-time sync initialization (runs backfill immediately)"
  task boot: :environment do
    puts "[sync:boot] Triggering initial backfill sync..."

    result = Sync::DispatchSyncJobs.call(mode: "backfill")

    puts "[sync:boot] Dispatched #{result[:dispatched]} backfill job(s)"
  end
  desc "Show sync status for all relays"
  task status: :environment do
    puts ""
    puts "=" * 60
    puts "Sync Status"
    puts "=" * 60
    puts ""

    # Show sync states from database
    puts "Sync States:"
    sync_states = SyncState.order(updated_at: :desc)
    if sync_states.empty?
      puts "  (none)"
    else
      sync_states.each do |state|
        status_icon = case state.status
        when "completed" then "[OK]"
        when "syncing" then "[..]"
        when "error" then "[!!]"
        else "[--]"
        end
        stale_marker = state.stale? ? " (STALE)" : ""

        puts "  #{status_icon} #{state.relay_url}#{stale_marker}"
        puts "       Filter: #{state.filter_hash || 'default'}"
        puts "       Status: #{state.status} | Direction: #{state.direction}"
        puts "       Downloaded: #{state.events_downloaded} | Uploaded: #{state.events_uploaded}"
        puts "       Last sync: #{state.last_synced_at&.strftime('%Y-%m-%d %H:%M:%S') || 'never'}"
        puts "       Error: #{state.error_message}" if state.error_message.present?
        puts ""
      end
    end

    # Show event counts
    puts "Event Counts:"
    puts "  Total events: #{Event.count}"
    puts "  Active events: #{Event.active.count}"
    puts ""

    # Show pending jobs
    puts "Pending Jobs:"
    pending = SolidQueue::Job.where(finished_at: nil).count
    puts "  #{pending} job(s) in queue"

    # Show job breakdown
    if pending > 0
      job_counts = SolidQueue::Job.where(finished_at: nil)
                                  .group(:class_name)
                                  .count
      job_counts.each do |class_name, count|
        puts "    - #{class_name}: #{count}"
      end
    end
    puts ""

    # Show configured relays
    puts "Configured Relays:"
    RelaySync.configuration.upstream_relays.each do |relay|
      flags = []
      flags << "backfill" if relay.backfill?
      flags << "negentropy" if relay.negentropy?
      flags << relay.direction
      puts "  #{relay.enabled? ? '[ON]' : '[--]'} #{relay.url} (#{flags.join(', ')})"
    end
    puts ""
  end

  desc "Manually trigger sync (modes: realtime, backfill, full, upload)"
  task :trigger, [ :mode, :relay_url ] => :environment do |_t, args|
    mode = args[:mode] || "realtime"
    relay_url = args[:relay_url]

    unless %w[realtime backfill full upload].include?(mode)
      puts "Invalid mode: #{mode}"
      puts "Valid modes: realtime, backfill, full, upload"
      exit 1
    end

    puts "Triggering #{mode} sync#{relay_url ? " for #{relay_url}" : " for all relays"}..."

    if relay_url
      result = Sync::DispatchSyncJobs.call(mode:, relay_url:)
    else
      result = Sync::DispatchSyncJobs.call(mode:)
    end

    puts "Dispatched #{result[:dispatched]} job(s)"
    puts ""
    puts "Monitor progress with: bin/rails sync:status"
  end

  desc "Recover stale syncs manually"
  task recover: :environment do
    puts "Recovering stale syncs..."

    result = Sync::RecoverStale.call

    puts "Recovered: #{result[:recovered_stale]} stale, #{result[:retried_errors]} errors"
  end

  desc "Reset sync state for a relay (or all relays if no URL given)"
  task :reset, [ :relay_url ] => :environment do |_t, args|
    relay_url = args[:relay_url]

    if relay_url
      states = SyncState.where(relay_url:)
      count = states.count
      states.destroy_all
      puts "Reset #{count} sync state(s) for #{relay_url}"
    else
      print "This will reset ALL sync states. Are you sure? [y/N] "
      confirm = $stdin.gets.chomp.downcase
      if confirm == "y"
        count = SyncState.count
        SyncState.destroy_all
        puts "Reset all #{count} sync states"
      else
        puts "Cancelled"
      end
    end
  end

  desc "List configured relays"
  task relays: :environment do
    puts ""
    puts "=" * 60
    puts "Configured Relays"
    puts "=" * 60
    puts ""

    RelaySync.configuration.upstream_relays.each do |relay|
      puts "#{relay.url}:"
      puts "  Enabled: #{relay.enabled?}"
      puts "  Backfill: #{relay.backfill?}"
      puts "  Negentropy: #{relay.negentropy?}"
      puts "  Direction: #{relay.direction}"
      puts ""
    end

    puts "Summary:"
    puts "  Total: #{RelaySync.configuration.upstream_relays.size}"
    puts "  Enabled: #{RelaySync.configuration.enabled_relays.size}"
    puts "  Backfill: #{RelaySync.configuration.backfill_relays.size}"
    puts "  Negentropy: #{RelaySync.configuration.negentropy_relays.size}"
    puts "  Download: #{RelaySync.configuration.download_relays.size}"
    puts "  Upload: #{RelaySync.configuration.upload_relays.size}"
  end

  desc "Show sync configuration settings"
  task config: :environment do
    settings = RelaySync.configuration.sync_settings

    puts ""
    puts "=" * 60
    puts "Sync Configuration"
    puts "=" * 60
    puts ""

    puts "General:"
    puts "  Batch size: #{settings.batch_size}"
    puts "  Max concurrent connections: #{settings.max_concurrent_connections}"
    puts "  Reconnect delay: #{settings.reconnect_delay_seconds}s"
    puts "  Max reconnect attempts: #{settings.max_reconnect_attempts}"
    puts ""

    puts "Backfill:"
    puts "  Since: #{settings.backfill_since_hours} hours (#{(settings.backfill_since_hours / 8760.0).round(2)} years)"
    puts "  Event kinds: #{settings.event_kinds.join(', ')}"
    puts ""

    puts "Polling:"
    puts "  Window: #{settings.polling_window_minutes} minutes"
    puts "  Timeout: #{settings.polling_timeout_seconds} seconds"
    puts ""

    puts "Robustness:"
    puts "  Resume overlap: #{settings.resume_overlap_seconds} seconds"
    puts "  Checkpoint interval: #{settings.checkpoint_interval} events"
    puts "  Stale threshold: #{settings.stale_threshold_minutes} minutes"
    puts "  Error retry after: #{settings.error_retry_after_minutes} minutes"
    puts ""

    puts "Upload:"
    puts "  Batch size: #{settings.upload_batch_size}"
    puts "  Delay: #{settings.upload_delay_ms}ms"
    puts ""

    puts "Negentropy:"
    puts "  Frame size: #{settings.negentropy_frame_size} bytes"
  end
end
