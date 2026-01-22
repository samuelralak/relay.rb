class CreateEventTags < ActiveRecord::Migration[8.1]
  def change
    create_table :event_tags, id: :uuid do |t|
      # Foreign key to events table (UUID)
      t.references :event, null: false, foreign_key: { on_delete: :cascade }, type: :uuid

      # Single-character tag name (e, p, t, a, d, etc.)
      t.string :tag_name, limit: 1, null: false

      # First value of the tag (indexed value)
      t.string :tag_value, limit: 255, null: false

      # Position in tags array (for ordering)
      t.integer :tag_index, null: false

      # Denormalized for covering indexes (avoids join to events)
      t.datetime :nostr_created_at, null: false
      t.integer :kind, null: false

      # Soft delete timestamp
      t.datetime :deleted_at

      t.timestamps
    end

    # Primary tag lookup
    add_index :event_tags, [ :tag_name, :tag_value ],
              name: "idx_event_tags_lookup"

    # Covering index - satisfies most tag queries without joining events
    add_index :event_tags,
              [ :tag_name, :tag_value, :nostr_created_at, :event_id ],
              order: { nostr_created_at: :desc },
              name: "idx_event_tags_covering"

    # Covering index with kind (for "reactions to event X")
    add_index :event_tags,
              [ :tag_name, :kind, :tag_value, :nostr_created_at, :event_id ],
              order: { nostr_created_at: :desc },
              name: "idx_event_tags_kind_covering"

    # Soft delete queries
    add_index :event_tags, :deleted_at,
              name: "idx_event_tags_deleted_at"
  end
end
