class CreateConversations < Saci::Record::Migration
  def change
    create_table :conversations do |t|
      # lobby (global, everyone) | group | dm
      t.string :kind, null: false
      t.string :name
      t.string :avatar_key
      t.bigint :owner_id
      # "<min_user_id>:<max_user_id>" for DMs, NULL otherwise.
      t.string :dm_key
      t.bigint :last_message_id
      t.datetime :last_message_at
      t.timestamps
    end
    add_index :conversations, :dm_key, unique: true
    add_index :conversations, :kind
  end
end
