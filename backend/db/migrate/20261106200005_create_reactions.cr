class CreateReactions < Saci::Record::Migration
  def change
    create_table :reactions do |t|
      t.bigint :message_id, null: false
      t.bigint :user_id, null: false
      t.string :emoji, null: false
      t.timestamps
    end
    add_index :reactions, [:message_id, :user_id, :emoji], unique: true
  end
end
