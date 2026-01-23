# Relay Sync System

A comprehensive system for synchronizing Nostr events between relays. Supports real-time streaming, efficient backfill using the Negentropy protocol (NIP-77), and bidirectional sync.

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

### 3. Configure Relays

Edit `config/relays.yml` to add your upstream relays:

```yaml
development:
  upstream_relays:
    - url: wss://relay.damus.io
      enabled: true
      backfill: true
      negentropy: true
      direction: down    # down, up, or both
```

### 4. Start Syncing

```bash
# Option A: Start the sync daemon (recommended for production)
bin/rails relay_sync:start

# Option B: Stream real-time events
bin/rails relay_sync:stream

# Option C: Run a one-time backfill
bin/rails relay_sync:backfill[24]  # Last 24 hours
```

### 5. Check Status

```bash
bin/rails relay_sync:status
```

---

## Configuration

### Relay Configuration (`config/relays.yml`)

```yaml
default: &default
  upstream_relays:
    - url: wss://relay.damus.io
      enabled: true       # Enable/disable this relay
      backfill: true      # Include in backfill operations
      negentropy: true    # Use Negentropy protocol if supported
      direction: down     # Sync direction: down, up, or both

    - url: wss://nos.lol
      enabled: true
      backfill: true
      negentropy: true
      direction: down

    - url: wss://my-backup.relay.com
      enabled: true
      backfill: false
      negentropy: false
      direction: up       # Upload only (backup relay)

  sync:
    batch_size: 100                    # Events per batch
    max_concurrent_connections: 10     # Max simultaneous connections
    reconnect_delay_seconds: 5         # Wait before reconnecting
    max_reconnect_attempts: 10         # Max reconnection tries
    backfill_since_hours: 168          # Default backfill window (1 week)
    event_kinds: [0, 1, 3, 5, 6, 7]    # Event kinds to sync
    negentropy_frame_size: 60000       # Max message size (60KB)
    upload_batch_size: 50              # Events per upload batch
    upload_delay_ms: 100               # Delay between uploads

development:
  <<: *default

production:
  <<: *default
```

### Sync Directions

| Direction | Download | Upload | Use Case |
|-----------|----------|--------|----------|
| `down` | Yes | No | Aggregate from public relays |
| `up` | No | Yes | Backup to personal relay |
| `both` | Yes | Yes | Full bidirectional mirror |

---

## CLI Commands

### Start Sync Daemon

Connects to all configured relays and maintains persistent connections:

```bash
bin/rails relay_sync:start
```

Press `Ctrl+C` to stop gracefully.

### Stream Real-time Events

Subscribe to live events from all enabled relays:

```bash
bin/rails relay_sync:stream
```

### Backfill Historical Events

Fetch events from the past N hours:

```bash
bin/rails relay_sync:backfill[24]     # Last 24 hours
bin/rails relay_sync:backfill[168]    # Last week
bin/rails relay_sync:backfill[720]    # Last month
```

### Negentropy Sync

Efficient set reconciliation with a specific relay:

```bash
# Download missing events
bin/rails relay_sync:negentropy[wss://relay.damus.io,down]

# Upload events relay doesn't have
bin/rails relay_sync:negentropy[wss://relay.damus.io,up]

# Bidirectional sync
bin/rails relay_sync:negentropy[wss://relay.damus.io,both]
```

### Upload Events

Push local events to a relay:

```bash
bin/rails relay_sync:upload[wss://my-backup.relay.com]
```

### Check Status

View connection status and sync progress:

```bash
bin/rails relay_sync:status
```

### List Configured Relays

```bash
bin/rails relay_sync:relays
```

### Reset Sync State

Clear sync progress for a relay (will re-sync from beginning):

```bash
bin/rails relay_sync:reset[wss://relay.damus.io]  # Specific relay
bin/rails relay_sync:reset                         # All relays
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLI / Rake Tasks                          │
│                     (lib/tasks/relay_sync.rake)                  │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                      RelaySync::Manager                          │
│  - Singleton managing all relay connections                      │
│  - Coordinates sync operations                                   │
│  - Routes events to appropriate handlers                         │
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
│ - Subscribe   │      │ - Subscribe   │      │ - Subscribe   │
└───────────────┘      └───────────────┘      └───────────────┘
        │                        │                        │
        └────────────────────────┼────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Background Jobs                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ProcessEvent │  │Negentropy   │  │Streaming    │              │
│  │Job          │  │SyncJob      │  │SyncJob      │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                        ┌─────────────┐                           │
│                        │UploadEvents │                           │
│                        │Job          │                           │
│                        └─────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Database                                 │
│  ┌─────────────┐            ┌─────────────┐                     │
│  │   Events    │            │ SyncStates  │                     │
│  │             │            │             │                     │
│  │ - event_id  │            │ - relay_url │                     │
│  │ - pubkey    │            │ - direction │                     │
│  │ - kind      │            │ - status    │                     │
│  │ - content   │            │ - progress  │                     │
│  └─────────────┘            └─────────────┘                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### Download Flow (Receiving Events)

```
Remote Relay                    Local System
     │                               │
     │  1. WebSocket Connect         │
     │◄──────────────────────────────│
     │                               │
     │  2. REQ (subscription)        │
     │◄──────────────────────────────│
     │                               │
     │  3. EVENT (nostr event)       │
     │──────────────────────────────►│
     │                               │
     │                               ▼
     │                    ┌──────────────────┐
     │                    │ MessageHandler   │
     │                    │ (parse & route)  │
     │                    └──────────────────┘
     │                               │
     │                               ▼
     │                    ┌──────────────────┐
     │                    │ ProcessEventJob  │
     │                    │ (validate/save)  │
     │                    └──────────────────┘
     │                               │
     │                               ▼
     │                    ┌──────────────────┐
     │                    │    Database      │
     │                    │    (Events)      │
     │                    └──────────────────┘
     │                               │
     │  4. EOSE (end of stored)      │
     │──────────────────────────────►│
     │                               │
     │  5. Live events continue...   │
     │──────────────────────────────►│
```

### Upload Flow (Publishing Events)

```
Local System                    Remote Relay
     │                               │
     │  1. Load events to upload     │
     │                               │
     ▼                               │
┌──────────────────┐                 │
│ UploadEventsJob  │                 │
└──────────────────┘                 │
     │                               │
     │  2. EVENT (nostr event)       │
     │──────────────────────────────►│
     │                               │
     │  3. OK (success/failure)      │
     │◄──────────────────────────────│
     │                               │
     ▼                               │
┌──────────────────┐                 │
│ Update SyncState │                 │
│ (track progress) │                 │
└──────────────────┘                 │
```

### Negentropy Sync Flow (NIP-77)

```
Client (Us)                     Server (Remote Relay)
     │                               │
     │  1. Build local storage       │
     │     (event IDs + timestamps)  │
     │                               │
     │  2. NEG-OPEN (filter + msg)   │
     │──────────────────────────────►│
     │                               │
     │  3. NEG-MSG (fingerprints)    │
     │◄──────────────────────────────│
     │                               │
     │  4. Compare fingerprints      │
     │     - Match: skip range       │
     │     - Mismatch: subdivide     │
     │                               │
     │  5. NEG-MSG (subdivisions)    │
     │──────────────────────────────►│
     │                               │
     │  ... repeat until converged   │
     │                               │
     │  6. Final ID lists exchanged  │
     │◄─────────────────────────────►│
     │                               │
     │  7. have_ids: we have, they   │
     │     need (upload these)       │
     │                               │
     │  8. need_ids: they have, we   │
     │     need (request these)      │
     │                               │
     │  9. REQ for needed events     │
     │──────────────────────────────►│
     │                               │
     │  10. EVENT responses          │
     │◄──────────────────────────────│
     │                               │
     │  11. NEG-CLOSE                │
     │──────────────────────────────►│
```

---

## Components

### Core Services

| Component | File | Description |
|-----------|------|-------------|
| **Manager** | `app/services/relay_sync/manager.rb` | Singleton coordinating all connections and sync operations |
| **Connection** | `app/services/relay_sync/connection.rb` | WebSocket wrapper with reconnection logic |
| **MessageHandler** | `app/services/relay_sync/message_handler.rb` | Parses and builds Nostr protocol messages |
| **Configuration** | `app/services/relay_sync/configuration.rb` | Loads and validates relay configuration |
| **EventPublisher** | `app/services/relay_sync/event_publisher.rb` | Handles event publishing with rate limiting |

### Negentropy Protocol (NIP-77)

| Component | File | Description |
|-----------|------|-------------|
| **Varint** | `app/services/negentropy/varint.rb` | Variable-length integer encoding |
| **Bound** | `app/services/negentropy/bound.rb` | Timestamp/ID boundary for ranges |
| **Fingerprint** | `app/services/negentropy/fingerprint.rb` | SHA-256 based set fingerprints |
| **Storage** | `app/services/negentropy/storage.rb` | Event storage adapter for reconciliation |
| **Message** | `app/services/negentropy/message.rb` | Binary message encoding/decoding |
| **Reconciler** | `app/services/negentropy/reconciler.rb` | Base reconciliation algorithm |
| **ClientReconciler** | `app/services/negentropy/client_reconciler.rb` | Client-side sync initiator |
| **ServerReconciler** | `app/services/negentropy/server_reconciler.rb` | Server-side sync responder |

### Background Jobs

| Job | File | Description |
|-----|------|-------------|
| **ProcessEventJob** | `app/jobs/process_event_job.rb` | Validates and saves incoming events |
| **NegentropySyncJob** | `app/jobs/negentropy_sync_job.rb` | Orchestrates Negentropy reconciliation |
| **StreamingSyncJob** | `app/jobs/streaming_sync_job.rb` | Manages streaming subscriptions |
| **UploadEventsJob** | `app/jobs/upload_events_job.rb` | Uploads events to remote relays |

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

# SyncState model tests
bin/rails test test/models/sync_state_test.rb
```

### Test Coverage

- **73 tests** for Negentropy components
- **45 tests** for RelaySync services
- **30 tests** for SyncState model

---

## Troubleshooting

### Connection Issues

**Problem**: Relay shows as "disconnected"

```bash
# Check relay status
bin/rails relay_sync:status

# Verify relay URL is correct and accessible
curl -I https://relay.example.com
```

**Solution**: Check firewall settings, verify WSS URL is correct

### No Events Received

**Problem**: Connected but no events arriving

1. Check your filter configuration in `config/relays.yml`
2. Verify `event_kinds` includes the kinds you want
3. Check `backfill_since_hours` isn't too restrictive

```bash
# Check current event count
bin/rails runner "puts Event.count"
```

### Duplicate Sync States

**Problem**: Multiple SyncState records for same relay

```bash
# Clean up duplicates
bin/rails runner "
  SyncState.group(:relay_url, :filter_hash)
    .having('count(*) > 1').count
    .each do |(url, hash), count|
      SyncState.where(relay_url: url, filter_hash: hash)
        .offset(1).destroy_all
    end
"
```

### Reset and Start Fresh

```bash
# Reset all sync states
bin/rails relay_sync:reset

# Clear all events (DESTRUCTIVE)
bin/rails runner "Event.unscoped.delete_all"

# Restart sync
bin/rails relay_sync:stream
```

### Debug Mode

```ruby
# In Rails console
RelaySync.start
sleep 5
puts RelaySync.status.inspect
RelaySync.stop
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RAILS_ENV` | development | Environment for config loading |

---

## References

- [NIP-01: Basic Protocol](https://github.com/nostr-protocol/nips/blob/master/01.md)
- [NIP-77: Negentropy Syncing](https://github.com/nostr-protocol/nips/blob/master/77.md)
- [Nostr Protocol](https://nostr.com)
