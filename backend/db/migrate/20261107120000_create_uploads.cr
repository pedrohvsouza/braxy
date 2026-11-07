# Who may download each stored image (GET /api/files/:key):
# - kind "avatar": any logged-in user (profile and group pictures);
# - kind "message": members of `conversation_id`, set when the image is
#   attached to a message; until then only the uploader.
class CreateUploads < Saci::Record::Migration
  def up : Nil
    create_table :uploads do |t|
      t.string :key, null: false
      t.string :kind, null: false
      t.bigint :user_id, null: false
      t.bigint :conversation_id
      t.timestamps
    end
    add_index :uploads, :key, unique: true

    # Images stored before this table existed.
    execute <<-SQL
      INSERT INTO uploads (key, kind, user_id, conversation_id, created_at, updated_at)
      SELECT DISTINCT ON (image_key) image_key, 'message', author_id, conversation_id, created_at, created_at
      FROM messages WHERE image_key IS NOT NULL
      ORDER BY image_key, id
      ON CONFLICT (key) DO NOTHING
    SQL
    execute <<-SQL
      INSERT INTO uploads (key, kind, user_id, conversation_id, created_at, updated_at)
      SELECT avatar_key, 'avatar', id, NULL::bigint, now(), now() FROM users WHERE avatar_key IS NOT NULL
      UNION ALL
      SELECT avatar_key, 'avatar', COALESCE(owner_id, 0), NULL::bigint, now(), now() FROM conversations WHERE avatar_key IS NOT NULL
      ON CONFLICT (key) DO NOTHING
    SQL
  end

  def down : Nil
    drop_table :uploads
  end
end
