# Relay Sync System

A comprehensive system for synchronizing Nostr events between relays. Supports real-time polling, efficient backfill using the Negentropy protocol (NIP-77), and bidirectional sync. Built on Solid Queue for reliable background job processing.

## Table of Contents

- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [CLI Commands](#cli-commands)
- [Architecture](#architecture)
- [Data Flow](#data-flow)
- [Components](#components)
- [Negentropy Protocol](#negentropy-protocol)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

### 1. Install Dependencies

```bash
bundle install
```

### 2. Run Migrations

```bash
bin/rails db:migrate
```

### 3. Seed Relays

Run the database seeds to populate upstream relays:

```bash
bin/rails db:seed
```

Or manage relays via the API (see [API Configuration](#api-configuration) below).

### 4. Start the Application

```bash
# Start web server and background jobs
bin/dev
```

Sync orchestration runs automatically via Solid Queue recurring jobs.

### 5. Check Status

```bash
bin/rails sync:status
```

---

## Configuration

### Relay Configuration (Database)

Relays are stored in the `upstream_relays` table and managed via API or seeds.

**UpstreamRelay fields:**

| Field | Type | Description |
|-------|------|-------------|
| `url` | string | WebSocket URL (wss://...) |
| `enabled` | boolean | Enable/disable this relay |
| `backfill` | boolean | Include in backfill operations |
| `negentropy` | boolean | Use Negentropy protocol (NIP-77) |
| `direction` | string | `down`, `up`, or `both` |
| `notes` | text | Optional notes about the relay |
| `config` | jsonb | Per-relay config overrides |

**Example seed data (`db/seeds.rb`):**

```ruby
UpstreamRelay.find_or_create_by!(url: "wss://relay.damus.io") do |r|
  r.enabled = true
  r.backfill = true
  r.negentropy = false
  r.direction = UpstreamRelays::Directions::DOWN
end
```

### API Configuration

Manage relays via REST API with bearer token authentication:

```bash
# Create API key
bin/rails relay_config:create_api_key[MyKey]

# List relays
curl -H "Authorization: Bearer rlk_..." http://localhost:3000/api/v1/relays

# Create relay
curl -X POST -H "Authorization: Bearer rlk_..." \
  -H "Content-Type: application/json" \
  -d '{"upstream_relay":{"url":"wss://new.relay.com","direction":"down"}}' \
  http://localhost:3000/api/v1/relays

# Update relay
curl -X PATCH -H "Authorization: Bearer rlk_..." \
  -H "Content-Type: application/json" \
  -d '{"upstream_relay":{"enabled":false}}' \
  http://localhost:3000/api/v1/relays/:id

# Delete relay
curl -X DELETE -H "Authorization: Bearer rlk_..." \
  http://localhost:3000/api/v1/relays/:id
```

### Sync Settings (Defaults)

Sync settings are defined with sensible defaults in `UpstreamRelays::Config`:

| Setting | Default | Description |
|---------|---------|-------------|
| `batch_size` | 100 | Events per batch |
| `max_concurrent_connections` | 10 | Max simultaneous connections |
| `reconnect_delay_seconds` | 5 | Wait before reconnecting |
| `max_reconnect_attempts` | 10 | Max reconnection tries |
| `backfill_since_hours` | 43800 | Default backfill window (5 years) |
| `negentropy_frame_size` | 60000 | Max message size (60KB) |
| `negentropy_chunk_hours` | 2 | Chunk size for negentropy sync |
| `polling_chunk_hours` | 6 | Chunk size for polling backfill |
| `upload_batch_size` | 50 | Events per upload batch |
| `upload_delay_ms` | 100 | Delay between uploads |
| `polling_window_minutes` | 15 | Realtime polling window |
| `polling_timeout_seconds` | 30 | Timeout per poll operation |
| `stale_threshold_minutes` | 10 | When to consider sync stale |
| `error_retry_after_minutes` | 30 | How long before retrying errors |

Per-relay overrides can be set in the `config` JSON field.

### Sync Directions

| Direction | Download | Upload | Use Case |
|-----------|----------|--------|----------|
| `down` | Yes | No | Aggregate from public relays |
| `up` | No | Yes | Backup to personal relay |
| `both` | Yes | Yes | Full bidirectional mirror |

### Recurring Job Schedule (`config/recurring.yml`)

Sync orchestration runs automatically via Solid Queue:

| Job | Schedule | Description |
|-----|----------|-------------|
| `realtime_sync` | Every 5 min | Poll for recent events |
| `backfill_sync` | Hourly | Negentropy/deep sync |
| `upload_sync` | Every 15 min | Upload to upload-enabled relays |
| `stale_sync_recovery` | Every 10 min | Recover stuck syncs |
| `full_sync` | Daily at 3am | Comprehensive sync |

---

## CLI Commands

### Check Status

View connection status and sync progress:

```bash
bin/rails sync:status
```

### Manually Trigger Sync

```bash
# Realtime sync (recent events)
bin/rails sync:trigger[realtime]

# Backfill sync (historical events)
bin/rails sync:trigger[backfill]

# Upload sync
bin/rails sync:trigger[upload]

# Full sync
bin/rails sync:trigger[full]

# Specific relay only
bin/rails sync:trigger[backfill,wss://relay.damus.io]
```

### Recover Stale Syncs

```bash
bin/rails sync:recover
```

### Reset Sync State

Clear sync progress for a relay (will re-sync from beginning):

```bash
bin/rails sync:reset[wss://relay.damus.io]  # Specific relay
bin/rails sync:reset                         # All relays (prompts for confirmation)
```

### List Configured Relays

```bash
bin/rails sync:relays
```

### Show Configuration

```bash
bin/rails sync:config
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Solid Queue Recurring Jobs                   │
│                     (config/recurring.yml)                       │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                      SyncOrchestratorJob                         │
│  - Dispatches sync jobs based on mode and relay config          │
│  - Modes: realtime, backfill, upload, full                      │
└─────────────────────────────────────────────────────────────────┘
                                 │
        ┌────────────────────────┼────────────────────────┐
        │                        │                        │
        ▼                        ▼                        ▼
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│ NegentropySyn │      │ PollingSyncJob│      │ UploadSyncJob │
│ Job           │      │               │      │               │
│               │      │ - REQ/EOSE    │      │ - EVENT/OK    │
│ - NEG-OPEN    │      │ - Short-lived │      │ - Batch upload│
│ - NEG-MSG     │      │ - Resumable   │      │               │
│ - Progressive │      │               │      │               │
└───────────────┘      └───────────────┘      └───────────────┘
        │                        │                        │
        └────────────────────────┼────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                      RelaySync::Manager                          │
│  - Singleton managing all relay connections                      │
│  - Routes messages to handlers                                   │
└─────────────────────────────────────────────────────────────────┘
                                 │
        ┌────────────────────────┼────────────────────────┐
        │                        │                        │
        ▼                        ▼                        ▼
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│  Connection   │      │  Connection   │      │  Connection   │
│  (Relay A)    │      │  (Relay B)    │      │  (Relay C)    │
│               │      │               │      │               │
│ - WebSocket   │      │ - WebSocket   │      │ - WebSocket   │
│ - Reconnect   │      │ - Reconnect   │      │ - Reconnect   │
└───────────────┘      └───────────────┘      └───────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ProcessEventJob                             │
│  - Validates and saves incoming events                          │
│  - Handles duplicates gracefully                                │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Database                                 │
│  ┌─────────────┐            ┌─────────────┐                     │
│  │   Events    │            │ SyncStates  │                     │
│  │             │            │             │                     │
│  │ - event_id  │            │ - relay_url │                     │
│  │ - pubkey    │            │ - status    │                     │
│  │ - kind      │            │ - progress  │                     │
│  │ - content   │            │ - backfill  │                     │
│  └─────────────┘            └─────────────┘                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### Download Flow (Polling)

```
SyncOrchestratorJob              PollingSyncJob                    Remote Relay
      │                               │                                  │
      │  dispatch                     │                                  │
      │──────────────────────────────►│                                  │
      │                               │                                  │
      │                               │  1. WebSocket Connect            │
      │                               │─────────────────────────────────►│
      │                               │                                  │
      │                               │  2. REQ (with resume filter)     │
      │                               │─────────────────────────────────►│
      │                               │                                  │
      │                               │  3. EVENT (nostr events)         │
      │                               │◄─────────────────────────────────│
      │                               │                                  │
      │                               │  4. ProcessEventJob (async)      │
      │                               │──────────┐                       │
      │                               │          ▼                       │
      │                               │    ┌──────────┐                  │
      │                               │    │ Database │                  │
      │                               │    └──────────┘                  │
      │                               │                                  │
      │                               │  5. EOSE                         │
      │                               │◄─────────────────────────────────│
      │                               │                                  │
      │                               │  6. Update SyncState cursor      │
      │                               │                                  │
```

### Negentropy Sync Flow (NIP-77)

```
NegentropySyncJob               SyncWithNegentropy             Remote Relay
      │                               │                              │
      │  call service                 │                              │
      │──────────────────────────────►│                              │
      │                               │                              │
      │                               │  1. Build local storage      │
      │                               │     (event IDs + timestamps) │
      │                               │                              │
      │                               │  2. NEG-OPEN (filter + msg)  │
      │                               │─────────────────────────────►│
      │                               │                              │
      │                               │  3. NEG-MSG (fingerprints)   │
      │                               │◄─────────────────────────────│
      │                               │                              │
      │                               │  4. Compare & subdivide      │
      │                               │                              │
      │                               │  5. NEG-MSG (response)       │
      │                               │─────────────────────────────►│
      │                               │                              │
      │                               │  ... repeat until converged  │
      │                               │                              │
      │                               │  6. have_ids / need_ids      │
      │                               │                              │
      │                               │  7. FetchEvents              │
      │                               │  8. REQ for needed events    │
      │                               │─────────────────────────────►│
      │                               │                              │
      │                               │  9. EVENT responses          │
      │                               │◄─────────────────────────────│
      │                               │                              │
      │                               │  10. NEG-CLOSE               │
      │                               │─────────────────────────────►│
      │                               │                              │
      │  schedule next chunk          │                              │
      │◄──────────────────────────────│                              │
```

---

## Components

### Core Libraries (`lib/`)

| Component | File | Description |
|-----------|------|-------------|
| **Manager** | `lib/relay_sync/manager.rb` | Singleton coordinating all connections |
| **Connection** | `lib/relay_sync/connection.rb` | WebSocket wrapper with reconnection |
| **MessageHandler** | `lib/relay_sync/message_handler.rb` | Nostr protocol message parsing |
| **Configuration** | `lib/relay_sync/configuration.rb` | Loads relay configuration |
| **EventPublisher** | `lib/relay_sync/event_publisher.rb` | Event publishing with rate limiting |

### Negentropy Protocol (`lib/negentropy/`)

| Component | File | Description |
|-----------|------|-------------|
| **Varint** | `lib/negentropy/varint.rb` | Variable-length integer encoding |
| **Bound** | `lib/negentropy/bound.rb` | Timestamp/ID boundary for ranges |
| **Fingerprint** | `lib/negentropy/fingerprint.rb` | SHA-256 based set fingerprints |
| **Storage** | `lib/negentropy/storage.rb` | Event storage adapter |
| **Message** | `lib/negentropy/message.rb` | Binary message encoding/decoding |
| **Reconciler** | `lib/negentropy/reconciler.rb` | Set reconciliation algorithm |

### Sync Services (`app/services/sync/`)

| Service | Description |
|---------|-------------|
| **DispatchSyncJobs** | Dispatches sync jobs based on mode and relay config |
| **SyncWithNegentropy** | Performs NIP-77 reconciliation |
| **FetchEvents** | Fetches events by ID (in actions/) |
| **UploadEvents** | Uploads local events to relays |
| **ProcessEvent** | Validates and saves incoming events |
| **RecoverStale** | Recovers stuck/errored sync states |

### Background Jobs (`app/jobs/`)

| Job | Queue | Description |
|-----|-------|-------------|
| **SyncOrchestratorJob** | sync | Entry point for scheduled sync |
| **NegentropySyncJob** | sync | Progressive negentropy backfill |
| **PollingSyncJob** | sync | REQ/EOSE based polling |
| **UploadSyncJob** | uploads | Batch upload to relays |
| **StaleSyncRecoveryJob** | sync | Recover stuck syncs |
| **ProcessEventJob** | events | Validate and save events |
| **UploadEventsJob** | uploads | Upload specific events |

### Models

| Model | Description |
|-------|-------------|
| **Event** | Nostr events with soft deletion |
| **SyncState** | Tracks sync progress per relay |

---

## Negentropy Protocol

Negentropy (NIP-77) is an efficient set reconciliation protocol. Instead of transferring all event IDs, it uses fingerprints to identify differences.

### How It Works

1. **Fingerprint Computation**: Compute a 16-byte fingerprint for a set of event IDs
   - Sum all 32-byte IDs (mod 2^256)
   - Append count as varint
   - SHA-256 hash, take first 16 bytes

2. **Range Subdivision**: If fingerprints don't match, split the range and compare sub-ranges

3. **Convergence**: Continue until ranges are small enough to send full ID lists

### Benefits

- **Bandwidth Efficient**: Only transfers fingerprints until differences are found
- **Works at Scale**: Handles millions of events efficiently
- **Bidirectional**: Identifies what each side is missing

### Progressive Backfill

Large backfills are chunked into manageable time windows:
- Default chunk size: 168 hours (1 week)
- Each chunk synced completely before moving to next
- Progress tracked in SyncState (backfill_target, backfill_until)
- Automatic continuation via job self-scheduling

### Message Types

| Message | Direction | Description |
|---------|-----------|-------------|
| `NEG-OPEN` | Client → Relay | Start reconciliation with filter |
| `NEG-MSG` | Bidirectional | Exchange fingerprints/ID lists |
| `NEG-CLOSE` | Client → Relay | End reconciliation |
| `NEG-ERR` | Relay → Client | Error response |

---

## Testing

### Run All Tests

```bash
bin/rails test
```

### Run Specific Test Suites

```bash
# Negentropy protocol tests
bin/rails test test/services/negentropy/

# RelaySync service tests
bin/rails test test/services/relay_sync/

# Sync service tests
bin/rails test test/services/sync/

# Job tests
bin/rails test test/jobs/

# Integration tests
bin/rails test test/integration/

# SyncState model tests
bin/rails test test/models/sync_state_test.rb
```

---

## Troubleshooting

### Sync Not Running

**Problem**: No sync activity visible

```bash
# Check job queue
bin/rails runner "puts SolidQueue::Job.where(finished_at: nil).group(:class_name).count"

# Check recurring jobs are scheduled
bin/rails runner "puts SolidQueue::RecurringTask.pluck(:key, :schedule)"
```

**Solution**: Ensure Solid Queue worker is running (`bin/rails solid_queue:start`)

### Stale Syncing State

**Problem**: Relay stuck in "syncing" status

```bash
# Check for stale states
bin/rails runner "SyncState.syncing.where('updated_at < ?', 10.minutes.ago).pluck(:relay_url)"

# Manually recover
bin/rails sync:recover
```

### Connection Issues

**Problem**: Relay shows as "disconnected"

```bash
# Check relay status
bin/rails sync:status

# Verify relay URL is correct and accessible
curl -I https://relay.example.com
```

**Solution**: Check firewall settings, verify WSS URL is correct

### No Events Received

**Problem**: Connected but no events arriving

1. Check relay configuration in database (`UpstreamRelay.all`)
2. Verify relay is enabled and has correct direction
3. Check `backfill_since_hours` in config covers the time range you need

```bash
# Check current event count
bin/rails runner "puts Event.count"

# Check relay configuration
bin/rails runner "UpstreamRelay.enabled.each { |r| puts \"#{r.url}: #{r.direction}\" }"
```

### Reset and Start Fresh

```bash
# Reset all sync states
bin/rails sync:reset

# Clear all events (DESTRUCTIVE)
bin/rails runner "Event.unscoped.delete_all"

# Trigger fresh backfill
bin/rails sync:trigger[backfill]
```

### Debug Mode

```ruby
# In Rails console
RelaySync.manager.status
```

---

## SyncState Status Lifecycle

```
                    ┌─────────┐
                    │  idle   │◄────────────────────┐
                    └────┬────┘                     │
                         │                          │
                    mark_syncing!                   │
                         │                          │
                         ▼                          │
                    ┌─────────┐                     │
              ┌─────│ syncing │─────┐               │
              │     └─────────┘     │               │
              │                     │               │
         error occurs          success              │
              │                     │               │
              ▼                     ▼               │
        ┌─────────┐          ┌───────────┐         │
        │  error  │          │           │         │
        └────┬────┘          │  Polling? │         │
             │               │           │         │
        retry after          ▼           ▼         │
        30 minutes     reset_to_idle!  backfill    │
             │               │         complete?   │
             │               │           │         │
             │               │      Yes  │  No     │
             │               │           │         │
             │               │           ▼         │
             │               │    mark_completed!  │
             │               │           │         │
             │               │           ▼         │
             │               │     ┌───────────┐   │
             │               │     │ completed │   │
             │               │     └───────────┘   │
             │               │                     │
             └───────────────┴─────────────────────┘
```

**Key Rules:**
- `idle`: Ready for sync (initial state, after polling, after recovery)
- `syncing`: Actively running (only one sync per relay at a time)
- `completed`: Backfill fully complete (only when `backfill_complete?` is true)
- `error`: Sync failed (auto-retried after 30 minutes)

---

## References

- [NIP-01: Basic Protocol](https://github.com/nostr-protocol/nips/blob/master/01.md)
- [NIP-77: Negentropy Syncing](https://github.com/nostr-protocol/nips/blob/master/77.md)
- [Solid Queue](https://github.com/rails/solid_queue)
- [Nostr Protocol](https://nostr.com)
