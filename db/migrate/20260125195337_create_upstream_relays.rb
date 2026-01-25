class CreateUpstreamRelays < ActiveRecord::Migration[8.1]
  def change
    create_table :upstream_relays, id: :uuid do |t|
      t.string :url, null: false
      t.boolean :enabled, default: true
      t.boolean :backfill, default: true
      t.boolean :negentropy, default: false
      t.string :direction, default: "down"
      t.text :notes
      t.jsonb :config, default: {}

      t.timestamps
    end

    add_index :upstream_relays, :url, unique: true
    add_index :upstream_relays, :enabled
  end
end
