require "../spec_helper"

def lobby_with(*users : User) : Conversation
  lobby = Conversation.lobby
  users.each { |u| Membership.ensure!(lobby.cid, u.uid) }
  lobby
end

describe "messages API" do
  it "posts, dedupes by client_id and paginates history" do
    with_app do |app|
      bob = Fixtures.user("bob")
      lobby = lobby_with(bob)
      bb = Fixtures.browser(app, bob)
      first = bb.post("/api/conversations/#{lobby.cid}/messages", {body: "oi", client_id: "c-1"})
      first.status_code.should eq(201)
      dup = bb.post("/api/conversations/#{lobby.cid}/messages", {body: "oi", client_id: "c-1"})
      dup.status_code.should eq(200)
      JSON.parse(first.body)["message"]["id"].should eq(JSON.parse(dup.body)["message"]["id"])
      bb.post("/api/conversations/#{lobby.cid}/messages", {body: "   "}).status_code.should eq(422)

      60.times { |i| Messaging.post(bob, lobby, "msg #{i}", nil, nil, nil) }
      page = bb.json("/api/conversations/#{lobby.cid}/messages")
      msgs = page["messages"].as_a
      msgs.size.should eq(50)
      page["has_more"].as_bool.should be_true
      msgs.last["body"].as_s.should eq("msg 59")
      older = bb.json("/api/conversations/#{lobby.cid}/messages?before=#{msgs.first["id"]}")
      older["messages"].as_a.size.should eq(11)
      older["has_more"].as_bool.should be_false
      newer = bb.json("/api/conversations/#{lobby.cid}/messages?after=#{msgs[-3]["id"]}")
      newer["messages"].as_a.map(&.["body"].as_s).should eq(["msg 58", "msg 59"])
    end
  end

  it "blocks non-members and ex-friends" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      eve = Fixtures.user("eve")
      f = Fixtures.friends(bob, ana)
      dm, _ = Conversation.find_or_create_dm(bob.uid, ana.uid)
      eb = Fixtures.browser(app, eve)
      eb.get("/api/conversations/#{dm.cid}/messages").status_code.should eq(404)
      eb.post("/api/conversations/#{dm.cid}/messages", {body: "intrusa"}).status_code.should eq(404)
      f.destroy
      Fixtures.browser(app, bob).post("/api/conversations/#{dm.cid}/messages", {body: "oi"}).status_code.should eq(403)
    end
  end

  it "replies, mentions and notifies once per person" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      cid = Fixtures.user("cid")
      lobby = lobby_with(bob, ana, cid)
      parent, _ = Messaging.post(ana, lobby, "pergunta", nil, nil, nil)
      bb = Fixtures.browser(app, bob)
      res = bb.post("/api/conversations/#{lobby.cid}/messages", {body: "@ana @cid @bob @ghost resposta", reply_to_id: parent.mid})
      res.status_code.should eq(201)
      msg = JSON.parse(res.body)["message"]
      msg["reply_to"]["author_name"].as_s.should eq("Ana")
      Notification.where(user_id: ana.uid).where("kind NOT IN ('level_up', 'achievement')").to_a.map(&.kind).should eq(["reply"])
      Notification.where(user_id: cid.uid).where("kind NOT IN ('level_up', 'achievement')").to_a.map(&.kind).should eq(["mention"])
      Notification.where(user_id: bob.uid).where("kind NOT IN ('level_up', 'achievement')").count.should eq(0)
    end
  end

  it "edits own messages, deletes with moderation rules" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      mod = Fixtures.user("rafa", "moderator")
      lobby = lobby_with(bob, ana, mod)
      m, _ = Messaging.post(bob, lobby, "original", nil, nil, nil)

      ab = Fixtures.browser(app, ana)
      ab.patch("/api/messages/#{m.mid}", {body: "hack"}).status_code.should eq(403)
      ab.delete("/api/messages/#{m.mid}").status_code.should eq(403)

      bb = Fixtures.browser(app, bob)
      edited = JSON.parse(bb.patch("/api/messages/#{m.mid}", {body: "editada"}).body)["message"]
      edited["body"].as_s.should eq("editada")
      edited["edited"].as_bool.should be_true

      deleted = JSON.parse(Fixtures.browser(app, mod).delete("/api/messages/#{m.mid}").body)["message"]
      deleted["deleted"].as_bool.should be_true
      deleted["body"].as_s.should eq("")
    end
  end

  it "lets group owners moderate their group but nobody else's DMs" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      admin = Fixtures.user("root", "admin")
      group = Fixtures.group(bob, "Clube", [ana])
      m, _ = Messaging.post(ana, group, "spam", nil, nil, nil)
      Fixtures.browser(app, bob).delete("/api/messages/#{m.mid}").status_code.should eq(200)

      Fixtures.friends(ana, admin)
      dm, _ = Conversation.find_or_create_dm(ana.uid, admin.uid)
      d, _ = Messaging.post(ana, dm, "privado", nil, nil, nil)
      Conversation.find_by(id: dm.cid).not_nil!.can_moderate?(admin).should be_false
      Fixtures.browser(app, admin).delete("/api/messages/#{d.mid}").status_code.should eq(403)
    end
  end

  it "toggles fixed reactions and pays the author once" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      lobby = lobby_with(bob, ana)
      m, _ = Messaging.post(bob, lobby, "curte aí", nil, nil, nil)
      before = User.find_by(id: bob.uid).not_nil!.xp_total
      ab = Fixtures.browser(app, ana)
      r = JSON.parse(ab.post("/api/messages/#{m.mid}/reactions", {emoji: "🔥"}).body)["reactions"].as_a
      r[0]["emoji"].as_s.should eq("🔥")
      r[0]["count"].as_i.should eq(1)
      ab.post("/api/messages/#{m.mid}/reactions", {emoji: "🔥"})
      ab.post("/api/messages/#{m.mid}/reactions", {emoji: "🔥"})
      User.find_by(id: bob.uid).not_nil!.xp_total.should eq(before + Xp::REACTION)
      ab.post("/api/messages/#{m.mid}/reactions", {emoji: "🍕"}).status_code.should eq(422)
    end
  end

  it "attaches images by key" do
    with_app do |app|
      bob = Fixtures.user("bob")
      lobby = lobby_with(bob)
      bb = Fixtures.browser(app, bob)
      key = JSON.parse(bb.upload("/api/uploads", Fixtures::PNG).body)["key"].as_s
      res = bb.post("/api/conversations/#{lobby.cid}/messages", {image_key: key})
      res.status_code.should eq(201)
      JSON.parse(res.body)["message"]["image_url"].as_s.should eq("/api/files/#{key}")
      bb.post("/api/conversations/#{lobby.cid}/messages", {image_key: "../../etc/passwd"}).status_code.should eq(422)
    end
  end

  it "pays message XP with a cooldown (more in groups than in DMs)" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      lobby = lobby_with(bob)
      Messaging.post(bob, lobby, "um", nil, nil, nil)
      Messaging.post(bob, lobby, "dois", nil, nil, nil) # inside cooldown
      User.find_by(id: bob.uid).not_nil!.xp_total.should eq(Xp::GROUP_MESSAGE)

      Fixtures.friends(ana, bob)
      dm, _ = Conversation.find_or_create_dm(ana.uid, bob.uid)
      Messaging.post(ana, dm, "oi", nil, nil, nil)
      User.find_by(id: ana.uid).not_nil!.xp_total.should eq(Xp::DM_MESSAGE)
    end
  end

  it "notifies on level up" do
    with_app do |app|
      bob = Fixtures.user("bob", xp: 45_i64)
      lobby = lobby_with(bob)
      Messaging.post(bob, lobby, "subindo", nil, nil, nil)
      n = Notification.where(user_id: bob.uid, kind: "level_up").to_a
      n.size.should eq(1)
      n[0].payload_json.not_nil!["level"].as_i.should eq(2)
      User.find_by(id: bob.uid).not_nil!.level.should eq(2)
    end
  end
end
