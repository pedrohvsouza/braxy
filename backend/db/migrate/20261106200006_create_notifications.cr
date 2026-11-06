class CreateNotifications < Saci::Record::Migration
  def change
    create_table :notifications do |t|
      t.bigint :user_id, null: false
      # friend_request | friend_accepted | mention | reply | level_up | group_added
      t.string :kind, null: false
      t.bigint :actor_id
      t.bigint :conversation_id
      t.bigint :message_id
      t.json :payload
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, [:user_id, :id]
  end
end
