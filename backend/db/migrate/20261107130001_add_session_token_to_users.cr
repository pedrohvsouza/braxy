class AddSessionTokenToUsers < Saci::Record::Migration
  def change
    # Rotated on password changes to end every other session (null: never
    # rotated, so sessions made before this column stay valid).
    add_column :users, :session_token, :string
  end
end
