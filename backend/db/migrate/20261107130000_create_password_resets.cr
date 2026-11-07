class CreatePasswordResets < Saci::Record::Migration
  def change
    create_table :password_resets do |t|
      t.bigint :user_id, null: false
      # SHA-256 of the emailed token: a database leak alone resets nothing.
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end
    add_index :password_resets, :token_digest, unique: true
    add_index :password_resets, :user_id
  end
end
