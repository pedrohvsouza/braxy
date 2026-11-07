class CreateBlocksAndSanctions < Saci::Record::Migration
  def change
    create_table :blocks do |t|
      t.bigint :blocker_id, null: false
      t.bigint :blocked_id, null: false
      t.timestamps
    end
    add_index :blocks, [:blocker_id, :blocked_id], unique: true
    add_index :blocks, :blocked_id

    # Per-conversation mutes and bans. One row per (conversation, user, kind);
    # expires_at null means until lifted.
    create_table :sanctions do |t|
      t.bigint :conversation_id, null: false
      t.bigint :user_id, null: false
      t.string :kind, null: false
      t.datetime :expires_at
      t.bigint :moderator_id, null: false
      t.timestamps
    end
    add_index :sanctions, [:conversation_id, :user_id, :kind], unique: true
  end
end
