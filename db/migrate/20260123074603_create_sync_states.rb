# frozen_string_literal: true

class CreateSyncStates < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_states, id: :uuid do |t|
      t.string :relay_url, limit: 255, null: false
      t.string :direction, limit: 10, null: false, default: "down"
      t.datetime :last_synced_at
      t.string :last_download_event_id, limit: 64
      t.datetime :last_download_timestamp
      t.string :last_upload_event_id, limit: 64
      t.datetime :last_upload_timestamp
      t.string :filter_hash, limit: 64
      t.string :status, limit: 20, null: false, default: "idle"
      t.integer :events_downloaded, null: false, default: 0
      t.integer :events_uploaded, null: false, default: 0
      t.text :error_message

      t.timestamps
    end

    add_index :sync_states, [:relay_url, :filter_hash], unique: true, name: "idx_sync_states_relay_filter"
    add_index :sync_states, :status, name: "idx_sync_states_status"
  end
end
