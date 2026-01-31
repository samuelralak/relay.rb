class AddFirstSeenAtIndexToEvents < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :events, :first_seen_at,
              algorithm: :concurrently,
              name: "idx_events_first_seen_at"
  end
end
