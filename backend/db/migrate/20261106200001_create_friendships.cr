class CreateFriendships < Saci::Record::Migration
  def change
    create_table :friendships do |t|
      t.bigint :requester_id, null: false
      t.bigint :addressee_id, null: false
      # "<min_id>:<max_id>" — one row per pair regardless of direction.
      t.string :pair_key, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :accepted_at
      t.timestamps
    end
    add_index :friendships, :pair_key, unique: true
    add_index :friendships, :requester_id
    add_index :friendships, :addressee_id
  end
end
