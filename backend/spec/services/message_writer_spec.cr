require "../spec_helper"

describe MessageWriter do
  it "commits concurrent posts together and keeps conversation bookkeeping right" do
    with_app do |_app|
      users = (1..8).map { |i| Fixtures.user("user#{i}") }
      lobby = Conversation.lobby
      users.each { |u| Membership.ensure!(lobby.cid, u.uid) }
      done = Channel(Message).new(40)
      40.times do |i|
        spawn do
          m, created = Messaging.post(users[i % 8], lobby, "msg #{i}", nil, nil, "c-#{i}")
          created.should be_true
          done.send(m)
        end
      end
      posted = Array.new(40) { done.receive }
      ids = posted.map(&.mid)
      ids.uniq.size.should eq(40)
      Message.where(conversation_id: lobby.cid).count.should eq(40)
      Conversation.find_by(id: lobby.cid).not_nil!.last_message_id.should eq(ids.max)
      # Own messages never count as unread (no read-cursor write needed).
      unread = Sidebar.unread_counts(users[0].uid)[lobby.cid]
      unread.should eq(posted.count { |m| m.author_id != users[0].uid })

      # Same client_id again: the original comes back, nothing is inserted.
      again, created = Messaging.post(users[0], lobby, "msg 0", nil, nil, "c-0")
      created.should be_false
      again.mid.should eq(posted.find! { |m| m.client_id == "c-0" }.mid)
      Message.where(conversation_id: lobby.cid).count.should eq(40)
    end
  end
end

describe MessagePageCache do
  it "serves the latest page from cache and invalidates on any change" do
    with_app do |app|
      bob = Fixtures.user("bob")
      lobby = Conversation.lobby
      Membership.ensure!(lobby.cid, bob.uid)
      b = Fixtures.browser(app, bob)
      b.post("/api/conversations/#{lobby.cid}/messages", {body: "primeira"})
      first = b.json("/api/conversations/#{lobby.cid}/messages")["messages"].as_a
      first.map(&.["body"].as_s).should eq(["primeira"])

      res = b.post("/api/conversations/#{lobby.cid}/messages", {body: "segunda"})
      mid = JSON.parse(res.body)["message"]["id"].as_i64
      b.json("/api/conversations/#{lobby.cid}/messages")["messages"].as_a.map(&.["body"].as_s).should eq(["primeira", "segunda"])

      b.patch("/api/messages/#{mid}", {body: "segunda (editada)"})
      b.json("/api/conversations/#{lobby.cid}/messages")["messages"][1]["body"].as_s.should eq("segunda (editada)")

      b.post("/api/messages/#{mid}/reactions", {emoji: "🔥"})
      b.json("/api/conversations/#{lobby.cid}/messages")["messages"][1]["reactions"][0]["count"].as_i.should eq(1)
    end
  end
end
