require "http/client"

# A cookie-keeping API client that behaves like the React app: it keeps the
# session cookie, mirrors `saci_csrf` into X-CSRF-Token and sends JSON.
class Browser
  getter host : String
  getter port : Int32
  getter cookies = {} of String => String

  def initialize(app : Saci::TestSession)
    @host = app.host
    @port = app.port
    get("/api/session")
  end

  def cookie_header : String
    cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
  end

  def csrf : String
    URI.decode_www_form(cookies["saci_csrf"]? || "")
  end

  def get(path : String) : HTTP::Client::Response
    request("GET", path)
  end

  def post(path : String, body = nil) : HTTP::Client::Response
    request("POST", path, body)
  end

  def patch(path : String, body = nil) : HTTP::Client::Response
    request("PATCH", path, body)
  end

  def delete(path : String) : HTTP::Client::Response
    request("DELETE", path)
  end

  def upload(path : String, bytes : Bytes, filename : String = "img.png", mime : String = "image/png") : HTTP::Client::Response
    io = IO::Memory.new
    boundary = "braxy-#{Random::Secure.hex(6)}"
    HTTP::FormData.build(io, boundary) do |form|
      form.file("file", IO::Memory.new(bytes), HTTP::FormData::FileMetadata.new(filename: filename), HTTP::Headers{"Content-Type" => mime})
    end
    headers = base_headers
    headers["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    send("POST", path, headers, io.to_s)
  end

  def json(path : String) : JSON::Any
    res = get(path)
    raise "GET #{path} -> #{res.status_code}: #{res.body}" unless res.success?
    JSON.parse(res.body)
  end

  def login(login : String, password : String = "password123") : HTTP::Client::Response
    post("/api/session", {login: login, password: password})
  end

  def cable(headers : HTTP::Headers = HTTP::Headers.new) : Saci::Cable::TestClient
    h = HTTP::Headers{"Cookie" => cookie_header, "Origin" => "http://localhost:5173"}
    headers.each { |k, v| h[k] = v }
    Saci::Cable::TestClient.new(host, port, "/cable", h)
  end

  private def base_headers : HTTP::Headers
    h = HTTP::Headers{"Accept" => "application/json"}
    h["Cookie"] = cookie_header unless cookies.empty?
    h["X-CSRF-Token"] = csrf unless csrf.empty?
    h
  end

  private def request(method : String, path : String, body = nil) : HTTP::Client::Response
    headers = base_headers
    payload = nil
    if body
      headers["Content-Type"] = "application/json"
      payload = body.to_json
    end
    send(method, path, headers, payload)
  end

  private def send(method : String, path : String, headers : HTTP::Headers, payload : String?) : HTTP::Client::Response
    client = HTTP::Client.new(host, port)
    res = client.exec(method, path, headers: headers, body: payload)
    client.close
    res.cookies.each do |c|
      if c.value.empty? || (c.expires.try { |e| e < Time.utc } || false)
        cookies.delete(c.name)
      else
        cookies[c.name] = c.value
      end
    end
    res
  end
end

module Fixtures
  PNG = Bytes[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 0x1F, 0x15, 0xC4, 0x89]

  def self.user(username : String, role : String = "member", xp : Int64 = 0_i64) : User
    User.create!(name: username.capitalize, username: username, email: "#{username}@test.local",
      password: "password123", role: role, xp: xp, level: Levels.level_for(xp))
  end

  def self.friends(a : User, b : User) : Friendship
    Friendship.create!(requester_id: a.uid, addressee_id: b.uid, pair_key: Friendship.pair_key(a.uid, b.uid),
      status: "accepted", accepted_at: Time.utc)
  end

  def self.group(owner : User, name : String, members : Array(User) = [] of User) : Conversation
    g = Conversation.create!(kind: "group", name: name, owner_id: owner.uid)
    Membership.ensure!(g.cid, owner.uid, "owner")
    members.each { |m| Membership.ensure!(g.cid, m.uid) }
    g
  end

  # Logs `user` in and returns the browser.
  def self.browser(app : Saci::TestSession, user : User) : Browser
    b = Browser.new(app)
    res = b.login(user.username.not_nil!)
    raise "login failed: #{res.body}" unless res.success?
    b
  end
end

def with_app(&)
  Saci::Record.clean_database!
  Saci::Cache.clear rescue nil
  KV.reset!
  UserCache.clear!
  Access.clear!
  MessagePageCache.clear!
  SidebarCache.clear!
  Xp.reset_memo!
  Saci::TestSession.serve(BraxyRoutes.build) { |app| yield app }
end

def wait_for(client : Saci::Cable::TestClient, type : String, timeout : Time::Span = 3.seconds) : JSON::Any
  deadline = Time.instant + timeout
  loop do
    remaining = deadline - Time.instant
    raise "timed out waiting for #{type}" if remaining <= Time::Span.zero
    frame = client.next_message(remaining)
    if msg = frame["message"]?
      return msg if msg.as_h? && msg["type"]?.try(&.as_s?) == type
    end
  end
end
