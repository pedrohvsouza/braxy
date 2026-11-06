class CreateMemberships < Saci::Record::Migration
  def change
    create_table :memberships do |t|
      t.bigint :conversation_id, null: false
      t.bigint :user_id, null: false
      t.string :role, null: false, default: "member"
      t.bigint :last_read_message_id, null: false, default: 0
      t.timestamps
    end
    add_index :memberships, [:conversation_id, :user_id], unique: true
    add_index :memberships, :user_id
  end
end
