require "random/secure"
require "file_utils"

# Image storage (avatars, group avatars, message images).
#
# Objects live in a private S3 bucket (LocalStack in dev) and are proxied by
# GET /api/files/:key for logged-in users; keys are 128-bit random. Specs and
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

  # Validates and stores an image, returning its key.
  def self.store_image(bytes : Bytes) : String
    raise Invalid.new("arquivo vazio") if bytes.empty?
    raise Invalid.new("imagem maior que 10 MB") if bytes.size > MAX_BYTES
    kind = sniff(bytes)
    raise Invalid.new("formato não suportado (use PNG, JPG, GIF ou WebP)") if kind.nil?
    ext, mime = kind
    key = "#{Random::Secure.hex(16)}.#{ext}"
    if s3 = S3
      s3.upload(bytes, filename: key, content_type: mime, key: key)
    else
      FileUtils.mkdir_p(LOCAL_ROOT)
      File.write(File.join(LOCAL_ROOT, key), bytes)
    end
    key
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
