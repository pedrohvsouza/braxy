require "../spec_helper"

describe "uploads API" do
  it "serves message images only to members of the conversation" do
    with_app do |app|
      bob = Fixtures.user("bob")
      carl = Fixtures.user("carl")
      ana = Fixtures.user("ana")
      g = Fixtures.group(bob, "Turma", [carl])
      other = Fixtures.group(bob, "Outra", [ana])
      bb = Fixtures.browser(app, bob)
      cb = Fixtures.browser(app, carl)
      ab = Fixtures.browser(app, ana)

      key = JSON.parse(bb.upload("/api/uploads", Fixtures::PNG).body)["key"].as_s
      # Not posted yet: only the uploader.
      bb.get("/api/files/#{key}").status_code.should eq(200)
      cb.get("/api/files/#{key}").status_code.should eq(404)

      bb.post("/api/conversations/#{g.cid}/messages", {image_key: key}).status_code.should eq(201)
      cb.get("/api/files/#{key}").status_code.should eq(200)
      ab.get("/api/files/#{key}").status_code.should eq(404)

      # The key cannot be relayed into a conversation the outsider can read.
      bb.post("/api/conversations/#{other.cid}/messages", {image_key: key}).status_code.should eq(422)
      ab.post("/api/conversations/#{other.cid}/messages", {image_key: key}).status_code.should eq(422)
      ab.get("/api/files/#{key}").status_code.should eq(404)

      Membership.find_by(conversation_id: g.cid, user_id: carl.uid).not_nil!.destroy
      cb.get("/api/files/#{key}").status_code.should eq(404)
    end
  end

  it "serves avatars to any logged-in user and nothing for unknown keys" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      bb = Fixtures.browser(app, bob)
      ab = Fixtures.browser(app, ana)
      url = JSON.parse(bb.upload("/api/me/avatar", Fixtures::PNG).body)["user"]["avatar_url"].as_s
      ab.get(url).status_code.should eq(200)
      Browser.new(app).get(url).status_code.should eq(401)
      ab.get("/api/files/#{"0" * 32}.png").status_code.should eq(404)
    end
  end
end
