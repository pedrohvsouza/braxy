class CreatePushSubscriptions < Saci::Record::Migration
  def change
    create_table :push_subscriptions do |t|
      t.bigint :user_id, null: false
      t.string :endpoint, null: false
      # Kept for payload encryption later; pushes are payload-free today.
      t.string :p256dh
      t.string :auth
      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true
    add_index :push_subscriptions, :user_id
  end
end
