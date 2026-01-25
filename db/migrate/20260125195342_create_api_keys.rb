class CreateApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_keys, id: :uuid do |t|
      t.string :name, null: false
      t.string :key_digest, null: false
      t.string :key_prefix, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :api_keys, :key_digest, unique: true
    add_index :api_keys, :key_prefix
    add_index :api_keys, :revoked_at
    add_index :api_keys, :deleted_at
  end
end
