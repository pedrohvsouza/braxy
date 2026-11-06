class CreateUsers < Saci::Record::Migration
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :username, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "member"
      t.string :avatar_key
      t.string :bio
      t.date :birthday
      t.bigint :xp, null: false, default: 0
      t.integer :level, null: false, default: 1
      t.datetime :last_seen_at
      t.date :last_daily_xp_on
      t.datetime :last_message_xp_at
      t.timestamps
    end
    add_index :users, :username, unique: true
    add_index :users, :email, unique: true
  end
end
