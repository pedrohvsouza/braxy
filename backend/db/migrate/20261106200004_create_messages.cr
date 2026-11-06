class CreateMessages < Saci::Record::Migration
  def change
    create_table :messages do |t|
      t.bigint :conversation_id, null: false
      t.bigint :author_id, null: false
      t.text :body
      t.string :image_key
      t.bigint :reply_to_id
      t.string :client_id
      t.datetime :edited_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :messages, [:conversation_id, :id]
    add_index :messages, [:author_id, :client_id], unique: true
  end
end
