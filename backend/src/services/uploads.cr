require "random/secure"
require "file_utils"

# Image storage (avatars, group avatars, message images).
#
# Objects live in a private S3 bucket (LocalStack in dev) and are proxied by
# GET /api/files/:key; keys are 128-bit random. Each key has a row in
# `uploads` saying who may download it (see `visible_to?`). Specs and
# bare-metal runs without S3_BUCKET fall back to a local directory.
module Uploads
  MAX_BYTES = 10 * 1024 * 1024
  KEY_RE    = /\A[0-9a-f]{32}\.(png|jpg|gif|webp)\z/

  class Invalid < Exception
  end

  S3 = begin
    bucket = ENV["S3_BUCKET"]?
    if bucket && !bucket.empty?
      Saci::Storage::S3Service.new(
        bucket: bucket,
        region: ENV.fetch("S3_REGION", "us-east-1"),
        access_key_id: ENV["S3_ACCESS_KEY_ID"]?,
        secret_access_key: ENV["S3_SECRET_ACCESS_KEY"]?,
        endpoint: ENV["S3_ENDPOINT"]?,
        name: "braxy",
      )
    end
  end

  LOCAL_ROOT = ENV.fetch("UPLOAD_DIR", "tmp/uploads")

  def self.valid_key?(key : String) : Bool
    KEY_RE.matches?(key)
  end

  # Identifies the image from its magic bytes (the declared MIME type is
  # never trusted). Returns {extension, mime} or nil.
  def self.sniff(bytes : Bytes) : {String, String}?
    return nil if bytes.size < 12
    if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47
      {"png", "image/png"}
    elsif bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
      {"jpg", "image/jpeg"}
    elsif String.new(bytes[0, 4]) == "GIF8"
      {"gif", "image/gif"}
    elsif String.new(bytes[0, 4]) == "RIFF" && String.new(bytes[8, 4]) == "WEBP"
      {"webp", "image/webp"}
    end
  end

  def self.mime_for(key : String) : String
    case File.extname(key)
    when ".png"  then "image/png"
    when ".jpg"  then "image/jpeg"
    when ".gif"  then "image/gif"
    when ".webp" then "image/webp"
    else              "application/octet-stream"
    end
  end

  AVATAR  = "avatar"  # any logged-in user
  MESSAGE = "message" # members of the conversation it was posted to

  record Grant, kind : String, user_id : Int64, conversation_id : Int64?

  @@grants = {} of String => Grant
  @@mutex = Mutex.new
  GRANT_CACHE_MAX = 100_000

  # Validates and stores an image uploaded by `user_id`, returning its key.
  def self.store_image(bytes : Bytes, user_id : Int64, kind : String) : String
    raise Invalid.new("arquivo vazio") if bytes.empty?
    raise Invalid.new("imagem maior que 10 MB") if bytes.size > MAX_BYTES
    sniffed = sniff(bytes)
    raise Invalid.new("formato não suportado (use PNG, JPG, GIF ou WebP)") if sniffed.nil?
    ext, mime = sniffed
    key = "#{Random::Secure.hex(16)}.#{ext}"
    if s3 = S3
      s3.upload(bytes, filename: key, content_type: mime, key: key)
    else
      FileUtils.mkdir_p(LOCAL_ROOT)
      File.write(File.join(LOCAL_ROOT, key), bytes)
    end
    db.exec("INSERT INTO uploads (key, kind, user_id, created_at, updated_at) VALUES ($1, $2, $3, now(), now())",
      key, kind, user_id)
    key
  end

  # Binds a message image to the conversation it is posted to. Only the
  # uploader can attach it, and only to one conversation (reposting to the
  # same one, as idempotent retries do, is fine).
  def self.attach(key : String, user_id : Int64, conversation_id : Int64) : Bool
    return false unless valid_key?(key)
    res = db.exec("UPDATE uploads SET conversation_id = $3, updated_at = now() " \
                  "WHERE key = $1 AND user_id = $2 AND kind = 'message' " \
                  "AND (conversation_id IS NULL OR conversation_id = $3)", key, user_id, conversation_id)
    res.rows_affected > 0
  end

  # Avatars: any logged-in user. Message images: members of the
  # conversation (removed members lose access); not yet posted: the uploader.
  # Unknown keys: nobody.
  def self.visible_to?(key : String, user_id : Int64) : Bool
    grant = grant_for(key)
    return false if grant.nil?
    return true if grant.kind == AVATAR
    if cid = grant.conversation_id
      Access.member?(cid, user_id)
    else
      grant.user_id == user_id
    end
  end

  # Grants never change once bound, so those are cached per process.
  private def self.grant_for(key : String) : Grant?
    return nil unless valid_key?(key)
    if hit = @@mutex.synchronize { @@grants[key]? }
      return hit
    end
    grant = db.query_one?("SELECT kind, user_id, conversation_id FROM uploads WHERE key = $1", key,
      as: {String, Int64, Int64?}).try { |(kind, uid, cid)| Grant.new(kind, uid, cid) }
    if grant && (grant.kind == AVATAR || grant.conversation_id)
      @@mutex.synchronize do
        @@grants.clear if @@grants.size >= GRANT_CACHE_MAX
        @@grants[key] = grant
      end
    end
    grant
  end

  def self.clear_cache! : Nil
    @@mutex.synchronize { @@grants.clear }
  end

  private def self.db : DB::Database
    Saci::Record.connection.as(DB::Database)
  end

  def self.fetch(key : String) : Bytes?
    return nil unless valid_key?(key)
    if s3 = S3
      begin
        s3.download(key)
      rescue Saci::Storage::FileNotFound
        nil
      end
    else
      path = File.join(LOCAL_ROOT, key)
      File.file?(path) ? File.read(path).to_slice : nil
    end
  end
end
