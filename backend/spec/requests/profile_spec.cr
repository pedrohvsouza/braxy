require "../spec_helper"

describe "profile API" do
  it "updates name, bio and birthday" do
    with_app do |app|
      bob = Fixtures.user("bob")
      b = Fixtures.browser(app, bob)
      res = b.patch("/api/me", {name: "Bob Esponja", bio: "Fenda do Biquíni", birthday: "1999-05-01"})
      res.status_code.should eq(200)
      me = JSON.parse(res.body)["user"]
      me["name"].as_s.should eq("Bob Esponja")
      me["bio"].as_s.should eq("Fenda do Biquíni")
      me["birthday"].as_s.should eq("1999-05-01")
      b.patch("/api/me", {birthday: "2999-01-01"}).status_code.should eq(422)
      b.patch("/api/me", {birthday: "ontem"}).status_code.should eq(422)
      JSON.parse(b.patch("/api/me", {birthday: ""}).body)["user"]["birthday"].raw.should be_nil
    end
  end

  it "changes the password with the current one" do
    with_app do |app|
      bob = Fixtures.user("bob")
      b = Fixtures.browser(app, bob)
      b.patch("/api/me/password", {current_password: "wrong", password: "newpassword1"}).status_code.should eq(422)
      b.patch("/api/me/password", {current_password: "password123", password: "newpassword1"}).status_code.should eq(200)
      b.json("/api/session")["user"]["username"].as_s.should eq("bob")
      Browser.new(app).login("bob", "newpassword1").status_code.should eq(200)
    end
  end

  it "uploads an avatar image and serves it to logged-in users only" do
    with_app do |app|
      bob = Fixtures.user("bob")
      b = Fixtures.browser(app, bob)
      res = b.upload("/api/me/avatar", Fixtures::PNG)
      res.status_code.should eq(200)
      url = JSON.parse(res.body)["user"]["avatar_url"].as_s
      img = b.get(url)
      img.status_code.should eq(200)
      img.headers["Content-Type"].should eq("image/png")
      Browser.new(app).get(url).status_code.should eq(401)
    end
  end

  it "rejects non-images by content, not by declared type" do
    with_app do |app|
      b = Fixtures.browser(app, Fixtures.user("bob"))
      b.upload("/api/uploads", "<svg onload=alert(1)>".to_slice + Bytes.new(20), "x.png", "image/png").status_code.should eq(422)
      ok = b.upload("/api/uploads", Fixtures::PNG)
      ok.status_code.should eq(201)
      JSON.parse(ok.body)["key"].as_s.should match(/\A[0-9a-f]{32}\.png\z/)
    end
  end

  it "shows profile cards with the friendship status" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana", "admin", Levels.total_for(10))
      b = Fixtures.browser(app, bob)
      card = b.json("/api/users/ana")["user"]
      card["role"].as_s.should eq("admin")
      card["level"].as_i.should eq(10)
      card["friendship"]["status"].as_s.should eq("none")
      b.get("/api/users/nobody").status_code.should eq(404)
      found = b.json("/api/users?q=an")["users"].as_a
      found.map { |u| u["user"]["username"].as_s }.should eq(["ana"])
    end
  end
end
