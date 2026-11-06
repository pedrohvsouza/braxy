require "../spec_helper"

describe "conversations API" do
  it "opens DMs only between friends (idempotent)" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      eve = Fixtures.user("eve")
      Fixtures.friends(bob, ana)
      bb = Fixtures.browser(app, bob)
      first = bb.post("/api/conversations/dm", {user_id: ana.uid})
      first.status_code.should eq(201)
      again = bb.post("/api/conversations/dm", {user_id: ana.uid})
      again.status_code.should eq(200)
      JSON.parse(first.body)["conversation"]["id"].should eq(JSON.parse(again.body)["conversation"]["id"])
      bb.post("/api/conversations/dm", {user_id: eve.uid}).status_code.should eq(403)
    end
  end

  it "creates groups with friends, manages members and hides groups from outsiders" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      cid = Fixtures.user("cid")
      eve = Fixtures.user("eve")
      Fixtures.friends(bob, ana)
      Fixtures.friends(bob, cid)
      bb = Fixtures.browser(app, bob)

      bb.post("/api/conversations", {name: "Trio", member_ids: [ana.uid, eve.uid]}).status_code.should eq(422)
      res = bb.post("/api/conversations", {name: "Trio", member_ids: [ana.uid]})
      res.status_code.should eq(201)
      group = JSON.parse(res.body)["conversation"]
      gid = group["id"].as_i64
      group["can_manage"].as_bool.should be_true
      group["members"].as_a.size.should eq(2)

      ab = Fixtures.browser(app, ana)
      ab.json("/api/notifications")["notifications"].as_a.map(&.["kind"].as_s).should contain("group_added")
      ab.patch("/api/conversations/#{gid}", {name: "Hijack"}).status_code.should eq(403)

      bb.post("/api/conversations/#{gid}/members", {user_ids: [cid.uid, eve.uid]}).status_code.should eq(200)
      convo = Conversation.find_by(id: gid).not_nil!
      convo.member?(cid.uid).should be_true
      convo.member?(eve.uid).should be_false # not bob's friend

      bb.patch("/api/conversations/#{gid}", {name: "Quarteto"}).status_code.should eq(200)
      bb.delete("/api/conversations/#{gid}/members/#{cid.uid}").status_code.should eq(200)
      ab.delete("/api/conversations/#{gid}/members/#{ana.uid}").status_code.should eq(200) # leave
      bb.delete("/api/conversations/#{gid}/members/#{bob.uid}").status_code.should eq(403) # owner can't leave

      Fixtures.browser(app, eve).get("/api/conversations/#{gid}").status_code.should eq(404)
    end
  end

  it "builds the sidebar: lobby/groups first, then friends with DM previews and unread counts" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      zed = Fixtures.user("zed")
      lobby = Conversation.lobby
      [bob, ana, zed].each { |u| Membership.ensure!(lobby.cid, u.uid) }
      Fixtures.friends(bob, ana)
      Fixtures.friends(bob, zed)
      dm, _ = Conversation.find_or_create_dm(bob.uid, ana.uid)
      Messaging.post(ana, dm, "oi bob", nil, nil, nil)
      Messaging.post(ana, dm, "tá aí?", nil, nil, nil)
      Messaging.post(zed, lobby, "salve", nil, nil, nil)

      side = Fixtures.browser(app, bob).json("/api/sidebar")
      side["groups"][0]["kind"].as_s.should eq("lobby")
      side["groups"][0]["unread"].as_i.should eq(1)
      side["groups"][0]["last_message"]["preview"].as_s.should eq("salve")
      friends = side["friends"].as_a
      friends.map { |f| f["user"]["username"].as_s }.should eq(["ana", "zed"])
      friends[0]["unread"].as_i.should eq(2)
      friends[0]["last_message"]["preview"].as_s.should eq("tá aí?")
      friends[1]["conversation_id"].raw.should be_nil
    end
  end

  it "moves the read cursor" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      Fixtures.friends(bob, ana)
      dm, _ = Conversation.find_or_create_dm(bob.uid, ana.uid)
      m, _ = Messaging.post(ana, dm, "oi", nil, nil, nil)
      bb = Fixtures.browser(app, bob)
      bb.post("/api/conversations/#{dm.cid}/read", {message_id: m.mid}).status_code.should eq(200)
      bb.json("/api/sidebar")["friends"][0]["unread"].as_i.should eq(0)
    end
  end
end
