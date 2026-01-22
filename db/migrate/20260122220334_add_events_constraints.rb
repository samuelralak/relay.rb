class AddEventsConstraints < ActiveRecord::Migration[8.1]
  def up
    # Validate hex format for event_id (64 lowercase hex chars)
    execute <<-SQL
      ALTER TABLE events
      ADD CONSTRAINT check_event_id_hex
      CHECK (event_id ~ '^[a-f0-9]{64}$');
    SQL

    # Validate hex format for pubkey
    execute <<-SQL
      ALTER TABLE events
      ADD CONSTRAINT check_pubkey_hex
      CHECK (pubkey ~ '^[a-f0-9]{64}$');
    SQL

    # Validate hex format for sig
    execute <<-SQL
      ALTER TABLE events
      ADD CONSTRAINT check_sig_hex
      CHECK (sig ~ '^[a-f0-9]{128}$');
    SQL

    # Validate kind range (0-65535)
    execute <<-SQL
      ALTER TABLE events
      ADD CONSTRAINT check_kind_range
      CHECK (kind >= 0 AND kind <= 65535);
    SQL
  end

  def down
    execute "ALTER TABLE events DROP CONSTRAINT IF EXISTS check_event_id_hex;"
    execute "ALTER TABLE events DROP CONSTRAINT IF EXISTS check_pubkey_hex;"
    execute "ALTER TABLE events DROP CONSTRAINT IF EXISTS check_sig_hex;"
    execute "ALTER TABLE events DROP CONSTRAINT IF EXISTS check_kind_range;"
  end
end
