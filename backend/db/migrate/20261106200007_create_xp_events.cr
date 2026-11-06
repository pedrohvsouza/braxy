class CreateXpEvents < Saci::Record::Migration
  def change
    create_table :xp_events do |t|
      t.bigint :user_id, null: false
      t.string :kind, null: false
      t.integer :amount, null: false
      # Idempotency key: the same (user, kind, source) never pays twice.
      t.string :source_key, null: false
      t.timestamps
    end
    add_index :xp_events, [:user_id, :kind, :source_key], unique: true
  end
end
