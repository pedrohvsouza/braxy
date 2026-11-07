require "base64"
require "http/client"
require "json"
require "uri"

# EVP signing comes from Saci's DKIM bindings; only BIO_free is missing.
lib LibCrypto
  fun bio_free = BIO_free(bio : Bio*) : Int32
end

# Web Push to people with no Braxy tab open.
#
# Pushes carry no payload (no RFC 8291 encryption needed): the content is
# parked in Redis for the user, and the service worker fetches it from
# GET /api/push/latest with the session cookie, then shows it.
#
# Configure with a P-256 key pair (see `VAPID_*` in the README):
#   VAPID_PUBLIC_KEY   uncompressed point, base64url
#   VAPID_PRIVATE_KEY  PEM ("\n" escapes allowed)
#   VAPID_SUBJECT      mailto: or https: contact (optional)
module WebPush
  TTL         = 1.day
  JWT_TTL     = 12.hours
  CONTENT_KEY = "braxy:push:latest:"

  record Content, title : String, body : String, url : String, tag : String do
    include JSON::Serializable
  end

  def self.public_key : String?
    ENV["VAPID_PUBLIC_KEY"]?.presence
  end

  def self.configured? : Bool
    !public_key.nil? && !private_pem.nil?
  end

  private def self.private_pem : String?
    ENV["VAPID_PRIVATE_KEY"]?.presence.try(&.gsub("\\n", "\n"))
  end

  # Parks `content` for each of `user_ids` with no socket open (an open tab
  # notifies by itself) and pings their devices. One fiber, never raises.
  def self.notify_later(user_ids : Array(Int64), content : Content) : Nil
    return if !configured? || user_ids.empty?
    spawn(name: "web-push") do
      online = Presence.online_ids(user_ids)
      offline = user_ids.reject { |id| online.includes?(id) }
      next if offline.empty?
      subs = PushSubscription.where("user_id IN (#{offline.map(&.to_i64).join(",")})").to_a
      subs.map(&.user_id.not_nil!).uniq.each do |uid|
        KV.backend.set("#{CONTENT_KEY}#{uid}", content.to_json, ttl: TTL)
      end
      subs.each do |sub|
        deliver(sub)
      rescue ex
        Log.warn(exception: ex) { "web push delivery failed (subscription #{sub.id})" }
      end
    rescue ex
      Log.error(exception: ex) { "web push failed" }
    end
  end

  # What the service worker shows (the newest parked content).
  def self.latest(user_id : Int64) : Content?
    KV.backend.get("#{CONTENT_KEY}#{user_id}").try { |json| Content.from_json(json) }
  rescue JSON::ParseException
    nil
  end

  # New message in a DM or private group: every offline member but the author.
  def self.message_later(convo : Conversation, message : Message, author : User) : Nil
    return if !configured? || convo.lobby?
    title = convo.dm? ? author.name.to_s : "#{author.name} em #{convo.name}"
    body = message.preview.gsub(/\|\|.+?\|\|/, "▒▒▒")
    content = Content.new(title, body, "/c/#{convo.cid}", "conv-#{convo.cid}")
    notify_later(convo.member_ids.reject(&.==(author.uid)), content)
  end

  # Mentions, replies and friend events (not XP noise).
  PUSHED_KINDS = {"mention", "reply", "friend_request", "friend_accepted", "group_added"}

  def self.notification_later(n : Notification, text : String) : Nil
    return unless configured? && PUSHED_KINDS.includes?(n.kind)
    url = n.conversation_id.try { |c| "/c/#{c}" } || "/"
    tag = n.conversation_id.try { |c| "conv-#{c}" } || "notif-#{n.id}"
    notify_later([n.user_id.not_nil!], Content.new("Braxy", text, url, tag))
  end

  # -- delivery ----------------------------------------------------------

  def self.deliver(sub : PushSubscription) : Nil
    endpoint = URI.parse(sub.endpoint.not_nil!)
    return unless endpoint.scheme == "https" && endpoint.host
    audience = "https://#{endpoint.host}#{endpoint.port ? ":#{endpoint.port}" : ""}"
    headers = HTTP::Headers{
      "Authorization"  => "vapid t=#{vapid_jwt(audience)}, k=#{public_key}",
      "TTL"            => TTL.total_seconds.to_i.to_s,
      "Urgency"        => "normal",
      "Content-Length" => "0",
    }
    res = HTTP::Client.post(endpoint, headers: headers)
    # Gone or unknown: the browser dropped this subscription.
    sub.destroy if res.status_code == 404 || res.status_code == 410
  end

  # RFC 8292 JWT, ES256 over the VAPID private key.
  def self.vapid_jwt(audience : String, now : Time = Time.utc) : String
    subject = ENV["VAPID_SUBJECT"]?.presence || "mailto:no-reply@braxy.local"
    header = b64url(%({"typ":"JWT","alg":"ES256"}))
    claims = b64url({aud: audience, exp: (now + JWT_TTL).to_unix, sub: subject}.to_json)
    input = "#{header}.#{claims}"
    "#{input}.#{b64url(es256(input.to_slice))}"
  end

  def self.b64url(data : String | Bytes) : String
    Base64.urlsafe_encode(data, padding: false)
  end

  # ECDSA P-256 / SHA-256, as the raw 64-byte r||s JWS wants.
  def self.es256(data : Bytes) : Bytes
    pem = private_pem || raise "VAPID_PRIVATE_KEY is not set"
    bio = LibCrypto.bio_new_mem_buf(pem.to_unsafe.as(Void*), pem.bytesize)
    pkey = LibCrypto.pem_read_bio_private_key(bio, nil, nil, nil)
    raise "invalid VAPID_PRIVATE_KEY" if pkey.null?
    ctx = LibCrypto.evp_md_ctx_new
    begin
      md = LibCrypto.evp_get_digestbyname("SHA256")
      raise "ES256 sign init failed" unless LibCrypto.evp_digest_sign_init(ctx, nil, md, nil, pkey) == 1
      raise "ES256 sign failed" unless LibCrypto.evp_digest_sign_update(ctx, data.to_unsafe, data.size) == 1
      len = LibC::SizeT.new(0)
      raise "ES256 sign failed" unless LibCrypto.evp_digest_sign_final(ctx, nil, pointerof(len)) == 1
      der = Bytes.new(len)
      raise "ES256 sign failed" unless LibCrypto.evp_digest_sign_final(ctx, der.to_unsafe, pointerof(len)) == 1
      der_to_raw(der[0, len])
    ensure
      LibCrypto.evp_md_ctx_free(ctx)
      LibCrypto.evp_pkey_free(pkey)
      LibCrypto.bio_free(bio)
    end
  end

  # DER SEQUENCE { INTEGER r, INTEGER s } -> 32-byte r || 32-byte s.
  def self.der_to_raw(der : Bytes) : Bytes
    raise "bad ECDSA signature" unless der[0] == 0x30
    i = der[1] & 0x80 != 0 ? 2 + (der[1] & 0x7f) : 2
    raw = Bytes.new(64)
    2.times do |n|
      raise "bad ECDSA signature" unless der[i] == 0x02
      len = der[i + 1].to_i
      int = der[i + 2, len]
      while int.size > 32 && int[0] == 0
        int = int[1..]
      end
      int.copy_to(raw[(n * 32) + (32 - int.size), int.size])
      i += 2 + len
    end
    raw
  end
end
