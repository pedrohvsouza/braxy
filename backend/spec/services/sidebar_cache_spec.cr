require "../spec_helper"

describe SidebarCache do
  it "stays correct across messages, reads, friendships and memberships" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      zed = Fixtures.user("zed")
      lobby = Conversation.lobby
      [bob, ana, zed].each { |u| Membership.ensure!(lobby.cid, u.uid) }
      Fixtures.friends(bob, ana)
      dm, _ = Conversation.find_or_create_dm(bob.uid, ana.uid)
      b = Fixtures.browser(app, bob)

      side = b.json("/api/sidebar")
      side["friends"][0]["unread"].as_i.should eq(0)

      # A new message in one of bob's conversations shows up immediately.
      m, _ = Messaging.post(ana, dm, "oi bob", nil, nil, nil)
      side = b.json("/api/sidebar")
      side["friends"][0]["unread"].as_i.should eq(1)
      side["friends"][0]["last_message"]["preview"].as_s.should eq("oi bob")

      # Reading clears the badge.
      b.post("/api/conversations/#{dm.cid}/read", {message_id: m.mid})
      b.json("/api/sidebar")["friends"][0]["unread"].as_i.should eq(0)

      # A new friendship and a new group appear without waiting.
      Fixtures.friends(bob, zed)
      b.json("/api/sidebar")["friends"].as_a.map(&.["user"]["username"].as_s).sort.should eq(["ana", "zed"])
      group = Fixtures.group(zed, "Clube", [bob])
      b.json("/api/sidebar")["groups"].as_a.map(&.["conversation_id"].as_i64).should contain(group.cid)
    end
  end
end
