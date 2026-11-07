require "../spec_helper"

describe ReadCursors do
  it "moves group read cursors forward only, never past the newest message" do
    with_app do |app|
      ana = Fixtures.user("ana")
      bia = Fixtures.user("bia")
      lobby = Conversation.lobby
      Membership.ensure!(lobby.cid, ana.uid)
      Membership.ensure!(lobby.cid, bia.uid)
      first, _ = Messaging.post(ana, lobby, "um", nil, nil, "rc-1")
      second, _ = Messaging.post(ana, lobby, "dois", nil, nil, "rc-2")
      b = Fixtures.browser(app, bia)
      cursor = -> { Membership.find_by(conversation_id: lobby.cid, user_id: bia.uid).not_nil!.last_read_message_id }

      b.json("/api/sidebar")["groups"].as_a.find! { |g| g["conversation_id"].as_i64 == lobby.cid }["unread"].as_i.should eq(2)

      b.post("/api/conversations/#{lobby.cid}/read", {message_id: first.mid}).status_code.should eq(200)
      cursor.call.should eq(first.mid)
      # The sidebar was invalidated: one unread left.
      b.json("/api/sidebar")["groups"].as_a.find! { |g| g["conversation_id"].as_i64 == lobby.cid }["unread"].as_i.should eq(1)

      # Past the newest message: clamped to it.
      b.post("/api/conversations/#{lobby.cid}/read", {message_id: second.mid + 1000})
      cursor.call.should eq(second.mid)

      # Never backwards.
      b.post("/api/conversations/#{lobby.cid}/read", {message_id: first.mid})
      cursor.call.should eq(second.mid)
      b.json("/api/sidebar")["groups"].as_a.find! { |g| g["conversation_id"].as_i64 == lobby.cid }["unread"].as_i.should eq(0)
    end
  end

  it "keeps the strongest cursor when one is noted twice before a flush" do
    with_app do |_app|
      ana = Fixtures.user("ana")
      lobby = Conversation.lobby
      Membership.ensure!(lobby.cid, ana.uid)
      m, _ = Messaging.post(Fixtures.user("caio"), lobby, "oi", nil, nil, "rc-3")
      ReadCursors.note(lobby.cid, ana.uid, Int64::MAX)
      Membership.find_by(conversation_id: lobby.cid, user_id: ana.uid).not_nil!.last_read_message_id.should eq(m.mid)
    end
  end
end
