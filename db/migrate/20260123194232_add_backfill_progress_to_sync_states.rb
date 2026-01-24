class AddBackfillProgressToSyncStates < ActiveRecord::Migration[8.1]
  def change
    add_column :sync_states, :backfill_until, :datetime
    add_column :sync_states, :backfill_target, :datetime
  end
end
