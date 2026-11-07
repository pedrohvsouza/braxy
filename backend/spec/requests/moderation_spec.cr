require "../spec_helper"

private def in_lobby(*users : User) : Conversation
  lobby = Conversation.lobby
  users.each { |u| Membership.ensure!(lobby.cid, u.uid) }
  lobby
end

describe "moderation API" do
  it "blocks: ends the friendship, hides from search, refuses requests and silences mentions" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      Fixtures.friends(bob, ana)
      lobby = in_lobby(bob, ana)
      ab = Fixtures.browser(app, ana)
      bb = Fixtures.browser(app, bob)

      ab.post("/api/blocks", {user_id: ana.uid}).status_code.should eq(403) # self
      ab.post("/api/blocks", {user_id: bob.uid}).status_code.should eq(200)
      Friendship.friends?(ana.uid, bob.uid).should be_false
      ab.json("/api/blocks")["users"].as_a.map(&.["username"].as_s).should eq(["bob"])
      ab.json("/api/users/bob")["user"]["blocked"].as_bool.should be_true

      # Neither side finds or befriends the other.
      ab.json("/api/users?q=bob")["users"].as_a.should be_empty
      bb.json("/api/users?q=ana")["users"].as_a.should be_empty
      bb.post("/api/friendships", {user_id: ana.uid}).status_code.should eq(403)

      # Mentions from a blocked user notify nobody.
      bb.post("/api/conversations/#{lobby.cid}/messages", {body: "oi @ana"}).status_code.should eq(201)
      Notification.where(user_id: ana.uid, kind: "mention").count.should eq(0)

      ab.delete("/api/blocks/#{bob.uid}").status_code.should eq(200)
      bb.json("/api/users?q=ana")["users"].as_a.size.should eq(1)
    end
  end

  it "mutes and bans, only by moderators and never staff or the owner" do
    with_app do |app|
      mod = Fixtures.user("rafa", "moderator")
      admin = Fixtures.user("marina", "admin")
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      lobby = in_lobby(mod, admin, bob, ana)
      mb = Fixtures.browser(app, mod)
      bb = Fixtures.browser(app, bob)
      path = "/api/conversations/#{lobby.cid}/sanctions"

      bb.post(path, {user_id: ana.uid, kind: "mute"}).status_code.should eq(403)   # not staff
      mb.post(path, {user_id: admin.uid, kind: "mute"}).status_code.should eq(403) # staff
      mb.post(path, {user_id: bob.uid, kind: "mute", minutes: 7}).status_code.should eq(422)

      mb.post(path, {user_id: bob.uid, kind: "mute", minutes: 10}).status_code.should eq(201)
      res = bb.post("/api/conversations/#{lobby.cid}/messages", {body: "posso falar?"})
      res.status_code.should eq(403)
      JSON.parse(res.body)["error"].as_s.should contain("silenciado")
      bb.json("/api/conversations/#{lobby.cid}")["conversation"]["muted_until"].as_s.should_not be_empty
      mb.json(path)["sanctions"].as_a.map(&.["kind"].as_s).should eq(["mute"])

      mb.delete("#{path}/#{bob.uid}?kind=mute").status_code.should eq(200)
      bb.post("/api/conversations/#{lobby.cid}/messages", {body: "voltei"}).status_code.should eq(201)

      # A ban removes the member; lifting it in the lobby lets them back.
      mb.post(path, {user_id: ana.uid, kind: "ban"}).status_code.should eq(201)
      Fixtures.browser(app, ana).get("/api/conversations/#{lobby.cid}").status_code.should eq(404)
      mb.delete("#{path}/#{ana.uid}?kind=ban").status_code.should eq(200)
      Fixtures.browser(app, ana).get("/api/conversations/#{lobby.cid}").status_code.should eq(200)
    end
  end

  it "lets a group owner ban, and banned friends cannot be added back" do
    with_app do |app|
      own = Fixtures.user("own")
      ana = Fixtures.user("ana")
      Fixtures.friends(own, ana)
      g = Fixtures.group(own, "Clube", [ana])
      ob = Fixtures.browser(app, own)
      Fixtures.browser(app, ana).post("/api/conversations/#{g.cid}/sanctions", {user_id: own.uid, kind: "ban"}).status_code.should eq(403)
      ob.post("/api/conversations/#{g.cid}/sanctions", {user_id: ana.uid, kind: "ban"}).status_code.should eq(201)
      g.member?(ana.uid).should be_false
      ob.post("/api/conversations/#{g.cid}/members", {user_ids: [ana.uid]})
      g.member?(ana.uid).should be_false
    end
  end
end
