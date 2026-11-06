require "../spec_helper"

describe "friendships API" do
  it "sends, lists and accepts a request (notifications + XP for both)" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      bb = Fixtures.browser(app, bob)
      ab = Fixtures.browser(app, ana)

      res = bb.post("/api/friendships", {user_id: ana.uid})
      res.status_code.should eq(201)
      JSON.parse(res.body)["friendship"]["status"].as_s.should eq("outgoing")
      bb.post("/api/friendships", {user_id: ana.uid}).status_code.should eq(200) # idempotent

      incoming = ab.json("/api/friendships")["incoming"].as_a
      incoming.size.should eq(1)
      ab.json("/api/notifications")["notifications"].as_a.map(&.["kind"].as_s).should contain("friend_request")

      fid = incoming[0]["id"].as_i64
      bb.post("/api/friendships/#{fid}/accept").status_code.should eq(403) # requester cannot accept
      ab.post("/api/friendships/#{fid}/accept").status_code.should eq(200)

      Friendship.friends?(bob.uid, ana.uid).should be_true
      bb.json("/api/notifications")["notifications"].as_a.map(&.["kind"].as_s).should contain("friend_accepted")
      User.find_by(id: bob.uid).not_nil!.xp_total.should eq(Xp::DAILY_LOGIN + Xp::FRIENDSHIP)
      User.find_by(id: ana.uid).not_nil!.xp_total.should eq(Xp::DAILY_LOGIN + Xp::FRIENDSHIP)
    end
  end

  it "auto-accepts when both sides ask, and unfriends" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      bb = Fixtures.browser(app, bob)
      ab = Fixtures.browser(app, ana)
      bb.post("/api/friendships", {user_id: ana.uid})
      res = ab.post("/api/friendships", {user_id: bob.uid})
      JSON.parse(res.body)["friendship"]["status"].as_s.should eq("friends")
      fid = JSON.parse(res.body)["friendship"]["id"].as_i64
      bb.delete("/api/friendships/#{fid}").status_code.should eq(200)
      Friendship.between(bob.uid, ana.uid).should be_nil
    end
  end

  it "cannot touch someone else's request" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      eve = Fixtures.user("eve")
      f = Friendship.create!(requester_id: bob.uid, addressee_id: ana.uid, pair_key: Friendship.pair_key(bob.uid, ana.uid))
      eb = Fixtures.browser(app, eve)
      eb.post("/api/friendships/#{f.id}/accept").status_code.should eq(404)
      eb.delete("/api/friendships/#{f.id}").status_code.should eq(404)
    end
  end
end
