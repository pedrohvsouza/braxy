class CreateUserAchievements < Saci::Record::Migration
  def change
    create_table :user_achievements do |t|
      t.bigint :user_id, null: false
      t.string :key, null: false
      t.timestamps
    end
    add_index :user_achievements, [:user_id, :key], unique: true
    # "Fundador" looks up groups by owner.
    add_index :conversations, :owner_id
  end
end
