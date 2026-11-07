require "../spec_helper"

describe Presence do
  it "stays online while any tab is open and goes offline with the last one" do
    with_app do |_app|
      bob = Fixtures.user("bob")
      Presence.online?(bob.uid).should be_false
      Presence.connected(bob)
      Presence.connected(bob) # second tab
      Presence.online_count.should eq(1)
      Presence.disconnected(bob)
      Presence.online?(bob.uid).should be_true
      Presence.disconnected(bob)
      Presence.online?(bob.uid).should be_false
      Presence.online_count.should eq(0)
    end
  end

  it "looks many users up at once and expires stale signals" do
    with_app do |_app|
      a = Fixtures.user("ana")
      b = Fixtures.user("bia")
      Presence.connected(a)
      KV.backend.zadd(Presence::ONLINE_KEY, Time.utc.to_unix - 600, b.uid.to_s) # crashed process
      Presence.online_ids([a.uid, b.uid]).should eq(Set{a.uid})
      Presence.prune
      KV.backend.zscores(Presence::ONLINE_KEY, [b.uid.to_s]).should eq([nil])
    end
  end
end

describe Stats do
  it "seeds counters from the database and then moves them with events" do
    with_app do |_app|
      bob = Fixtures.user("bob")
      lobby = Conversation.lobby
      Membership.ensure!(lobby.cid, bob.uid)
      Messaging.post(bob, lobby, "um", nil, nil, nil)
      Stats.snapshot[:messages].should eq(1)
      m, _ = Messaging.post(bob, lobby, "dois", nil, nil, nil)
      Stats.snapshot[:messages].should eq(2)
      Messaging.delete(bob, m, lobby)
      Stats.snapshot[:messages].should eq(1)
      Stats.counter("users").should eq(1)
    end
  end

  it "lets only one node lead the broadcaster" do
    with_app do |_app|
      Stats.leader?.should be_true
      Stats.leader?.should be_true # renews its own lease
      KV.backend.set(Stats::LEADER_KEY, "someone-else", ttl: 10.seconds)
      Stats.leader?.should be_false
    end
  end
end

describe Messaging do
  it "writes the message, cursors and XP in one transaction" do
    with_app do |_app|
      bob = Fixtures.user("bob")
      lobby = Conversation.lobby
      Membership.ensure!(lobby.cid, bob.uid)
      m, created = Messaging.post(bob, lobby, "oi", nil, nil, nil)
      created.should be_true
      Conversation.find_by(id: lobby.cid).not_nil!.last_message_id.should eq(m.mid)
      lobby.membership_for(bob.uid).not_nil!.last_read_message_id.should eq(m.mid)
      User.find_by(id: bob.uid).not_nil!.xp_total.should eq(Xp::GROUP_MESSAGE)
      XpEvent.where(user_id: bob.uid, kind: "message").count.should eq(1)
    end
  end

  it "rolls nothing back into a half state on invalid input" do
    with_app do |_app|
      bob = Fixtures.user("bob")
      lobby = Conversation.lobby
      Membership.ensure!(lobby.cid, bob.uid)
      expect_raises(Messaging::Invalid) { Messaging.post(bob, lobby, "", nil, nil, nil) }
      Message.count.should eq(0)
      Conversation.find_by(id: lobby.cid).not_nil!.last_message_id.should be_nil
    end
  end
end
