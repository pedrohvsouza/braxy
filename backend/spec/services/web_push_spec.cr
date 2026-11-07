require "../spec_helper"
require "file_utils"

# A throwaway P-256 key pair made with the openssl CLI.
private def with_vapid_keys(&)
  dir = File.tempname("vapid")
  Dir.mkdir_p(dir)
  pem = File.join(dir, "k.pem")
  Process.run("openssl", ["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", pem])
  der = IO::Memory.new
  Process.run("openssl", ["ec", "-in", pem, "-pubout", "-outform", "DER"], output: der, error: Process::Redirect::Close)
  point = der.to_slice[-65, 65]
  ENV["VAPID_PRIVATE_KEY"] = File.read(pem)
  ENV["VAPID_PUBLIC_KEY"] = Base64.urlsafe_encode(point, padding: false)
  begin
    yield pem
  ensure
    ENV.delete("VAPID_PRIVATE_KEY")
    ENV.delete("VAPID_PUBLIC_KEY")
    FileUtils.rm_rf(dir)
  end
end

private def b64url_decode(s : String) : Bytes
  Base64.decode(s.tr("-_", "+/") + "=" * ((4 - s.size % 4) % 4))
end

# Raw r||s back to DER, for `openssl dgst -verify`.
private def raw_to_der(raw : Bytes) : Bytes
  body = [] of UInt8
  [raw[0, 32], raw[32, 32]].each do |part|
    int = part.to_a
    while int.size > 1 && int[0] == 0 && int[1] < 0x80
      int.shift
    end
    int.unshift(0_u8) if int[0] >= 0x80
    body << 0x02_u8 << int.size.to_u8
    body.concat(int)
  end
  der = [0x30_u8, body.size.to_u8] + body
  Bytes.new(der.size) { |i| der[i] }
end

describe WebPush do
  it "signs RFC 8292 JWTs that openssl verifies with the public key" do
    with_vapid_keys do |pem|
      WebPush.configured?.should be_true
      jwt = WebPush.vapid_jwt("https://push.example.com", Time.utc(2026, 11, 7))
      header, claims, sig = jwt.split(".")
      JSON.parse(String.new(b64url_decode(header)))["alg"].as_s.should eq("ES256")
      body = JSON.parse(String.new(b64url_decode(claims)))
      body["aud"].as_s.should eq("https://push.example.com")
      body["exp"].as_i64.should eq((Time.utc(2026, 11, 7) + 12.hours).to_unix)
      raw = b64url_decode(sig)
      raw.size.should eq(64)

      dir = File.dirname(pem)
      pub = File.join(dir, "pub.pem")
      Process.run("openssl", ["ec", "-in", pem, "-pubout", "-out", pub], error: Process::Redirect::Close)
      File.write(File.join(dir, "sig.der"), raw_to_der(raw))
      File.write(File.join(dir, "data"), "#{header}.#{claims}")
      status = Process.run("openssl", ["dgst", "-sha256", "-verify", pub, "-signature", File.join(dir, "sig.der"), File.join(dir, "data")],
        output: Process::Redirect::Close, error: Process::Redirect::Close)
      status.success?.should be_true
    end
  end

  it "stores subscriptions per user and serves parked content to the service worker" do
    with_vapid_keys do |_pem|
      with_app do |app|
        bob = Fixtures.user("bob")
        bb = Fixtures.browser(app, bob)
        JSON.parse(bb.get("/api/push/key").body)["key"].as_s.should eq(ENV["VAPID_PUBLIC_KEY"])
        bb.post("/api/push/subscriptions", {endpoint: "http://insecure.example/x"}).status_code.should eq(422)
        sub = {endpoint: "https://push.example.com/abc", keys: {p256dh: "p", auth: "a"}}
        bb.post("/api/push/subscriptions", sub).status_code.should eq(201)
        bb.post("/api/push/subscriptions", sub).status_code.should eq(201) # idempotent
        PushSubscription.where(user_id: bob.uid).count.should eq(1)

        bb.json("/api/push/latest")["content"].raw.should be_nil
        KV.backend.set("#{WebPush::CONTENT_KEY}#{bob.uid}",
          WebPush::Content.new("Ana", "oi ▒▒▒", "/c/3", "conv-3").to_json)
        latest = bb.json("/api/push/latest")["content"]
        latest["title"].as_s.should eq("Ana")
        latest["url"].as_s.should eq("/c/3")

        bb.delete("/api/push/subscriptions", {endpoint: "https://push.example.com/abc"}).status_code.should eq(200)
        PushSubscription.where(user_id: bob.uid).count.should eq(0)
      end
    end
  end
end
