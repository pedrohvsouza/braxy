require "../spec_helper"

describe "auth API" do
  it "signs up, joins the lobby, reads the session and logs out" do
    with_app do |app|
      b = Browser.new(app)
      res = b.post("/api/signup", {name: "Ada Lovelace", username: "@Ada", email: "ADA@x.io", password: "password123"})
      res.status_code.should eq(201)
      user = JSON.parse(res.body)["user"]
      user["username"].as_s.should eq("ada")
      user["email"].as_s.should eq("ada@x.io")
      user["level"].as_i.should eq(2) # 50 XP daily-login bonus
      Conversation.lobby.member?(user["id"].as_i64).should be_true

      b.json("/api/session")["user"]["username"].as_s.should eq("ada")
      b.delete("/api/session").status_code.should eq(200)
      b.json("/api/session")["user"].raw.should be_nil
    end
  end

  it "validates signup fields" do
    with_app do |app|
      Fixtures.user("taken")
      b = Browser.new(app)
      b.post("/api/signup", {name: "X", username: "taken", email: "t@x.io", password: "password123"}).status_code.should eq(422)
      b.post("/api/signup", {name: "Xavier", username: "bad name", email: "t@x.io", password: "password123"}).status_code.should eq(422)
      b.post("/api/signup", {name: "Xavier", username: "xavier", email: "nope", password: "password123"}).status_code.should eq(422)
      b.post("/api/signup", {name: "Xavier", username: "xavier", email: "x@x.io", password: "short"}).status_code.should eq(422)
    end
  end

  it "logs in by username or email and rejects bad passwords" do
    with_app do |app|
      Fixtures.user("bob")
      Browser.new(app).login("bob").status_code.should eq(200)
      Browser.new(app).login("bob@test.local").status_code.should eq(200)
      Browser.new(app).login("bob", "wrong-password").status_code.should eq(401)
    end
  end

  it "requires CSRF on mutations and auth on private endpoints" do
    with_app do |app|
      Fixtures.user("bob")
      b = Fixtures.browser(app, User.find_by(username: "bob").not_nil!)
      raw = HTTP::Client.new(app.host, app.port)
      res = raw.patch("/api/me", headers: HTTP::Headers{"Cookie" => b.cookie_header, "Content-Type" => "application/json"}, body: {name: "Hacker"}.to_json)
      raw.close
      res.status_code.should eq(403)
      Browser.new(app).get("/api/sidebar").status_code.should eq(401)
    end
  end

  it "pays the daily login XP once per day" do
    with_app do |app|
      bob = Fixtures.user("bob")
      b = Fixtures.browser(app, bob)
      b.get("/api/session")
      b.get("/api/session")
      User.find_by(id: bob.uid).not_nil!.xp_total.should eq(Xp::DAILY_LOGIN)
    end
  end
end
