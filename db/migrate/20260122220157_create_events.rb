class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events, id: :uuid do |t|
      # Nostr event ID - SHA256 hash as 64-char lowercase hex
      t.string :event_id, limit: 64, null: false

      # Author's public key - 32 bytes as 64-char lowercase hex
      t.string :pubkey, limit: 64, null: false

      # Nostr timestamp (stored as datetime, converted to/from unix timestamp)
      t.datetime :nostr_created_at, null: false

      # Event kind (0-65535)
      t.integer :kind, null: false

      # Tags as JSONB array
      t.jsonb :tags, null: false, default: []

      # Event content (can be empty string)
      t.text :content, null: false, default: ""

      # Schnorr signature - 64 bytes as 128-char lowercase hex
      t.string :sig, limit: 128, null: false

      # Full original event for serving to clients
      t.jsonb :raw_event, null: false

      # Extracted d-tag for addressable events (kind 30000-39999)
      t.string :d_tag, limit: 255

      # NIP-40 expiration timestamp
      t.datetime :expires_at

      # Soft delete timestamp (NULL = active, timestamp = deleted)
      t.datetime :deleted_at

      # When relay first received this event
      t.datetime :first_seen_at, null: false

      t.timestamps
    end

    # Primary lookup - must be unique
    add_index :events, :event_id, unique: true, name: "idx_events_event_id"

    # Author + time queries: "user's recent posts"
    add_index :events, [ :pubkey, :nostr_created_at ],
              order: { nostr_created_at: :desc },
              name: "idx_events_pubkey_created_at"

    # Kind + time queries: "latest text notes"
    add_index :events, [ :kind, :nostr_created_at ],
              order: { nostr_created_at: :desc },
              name: "idx_events_kind_created_at"

    # Replaceable events: author + kind (kind 0, 3, 10000-19999)
    add_index :events, [ :pubkey, :kind ],
              name: "idx_events_pubkey_kind"

    # Addressable events: author + kind + d_tag (kind 30000-39999)
    add_index :events, [ :pubkey, :kind, :d_tag ],
              where: "d_tag IS NOT NULL",
              name: "idx_events_addressable"

    # Expiration cleanup (partial index)
    add_index :events, :expires_at,
              where: "expires_at IS NOT NULL",
              name: "idx_events_expires_at"

    # Soft delete queries
    add_index :events, :deleted_at,
              name: "idx_events_deleted_at"

    # GIN index on tags for direct JSONB queries
    add_index :events, :tags, using: :gin, name: "idx_events_tags_gin"
  end
end
