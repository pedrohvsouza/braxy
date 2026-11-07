require "../spec_helper"

describe ChatChannel do
  it "authenticates with the session cookie and rejects anonymous or foreign-origin sockets" do
    with_app do |app|
      bob = Fixtures.user("bob")
      client = Fixtures.browser(app, bob).cable
      client.subscribe("ChatChannel").should contain("ChatChannel")
      client.close

      expect_raises(Exception) do
        Browser.new(app).cable.subscribe("ChatChannel", timeout: 300.milliseconds)
      end
      expect_raises(Exception) do
        Fixtures.browser(app, bob).cable(HTTP::Headers{"Origin" => "http://evil.test"}).subscribe("ChatChannel", timeout: 300.milliseconds)
      end
    end
  end

  it "accepts the page's own address as origin (another device on the network)" do
    with_app do |app|
      bob = Fixtures.user("bob")
      browser = Fixtures.browser(app, bob)
      same = browser.cable(HTTP::Headers{"Origin" => "http://#{browser.host}:#{browser.port}"})
      same.subscribe("ChatChannel").should contain("ChatChannel")
      same.close
    end
  end

  it "matches origins against the Host header" do
    braxy_origin_allowed?("http://192.168.0.10:5173", "192.168.0.10:5173").should be_true
    braxy_origin_allowed?("http://Notebook.Local:5173", "notebook.local:5173").should be_true
    braxy_origin_allowed?("http://192.168.0.10", "192.168.0.10").should be_true
    braxy_origin_allowed?("http://localhost:5173", nil).should be_true # APP_ORIGINS
    braxy_origin_allowed?("http://evil.test", "192.168.0.10:5173").should be_false
    braxy_origin_allowed?("http://192.168.0.10:6666", "192.168.0.10:5173").should be_false
    braxy_origin_allowed?("file://192.168.0.10:5173", "192.168.0.10:5173").should be_false
    braxy_origin_allowed?("null", "192.168.0.10:5173").should be_false
  end

  it "streams new messages, reactions and typing to members" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      group = Fixtures.group(bob, "Dupla", [ana])
      listener = Fixtures.browser(app, ana).cable
      ident = listener.subscribe("ChatChannel")
      begin
        bb = Fixtures.browser(app, bob)
        bb.post("/api/conversations/#{group.cid}/messages", {body: "ao vivo"})
        created = wait_for(listener, "message.created")
        created["message"]["body"].as_s.should eq("ao vivo")
        mid = created["message"]["id"].as_i64

        bb.post("/api/messages/#{mid}/reactions", {emoji: "👍"})
        wait_for(listener, "reaction.updated")["reactions"][0]["count"].as_i.should eq(1)

        typer = bb.cable
        tid = typer.subscribe("ChatChannel")
        typer.send_message(tid, {action: "typing", conversation_id: group.cid})
        wait_for(listener, "typing")["user"]["name"].as_s.should eq("Bob")
        typer.close

        listener.send_message(ident, {action: "ping", ts: 42})
        wait_for(listener, "pong")["ts"].as_i.should eq(42)
      ensure
        listener.close
      end
    end
  end

  it "follows conversations created after connecting and delivers personal events" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      Fixtures.friends(bob, ana)
      listener = Fixtures.browser(app, ana).cable
      ident = listener.subscribe("ChatChannel")
      begin
        bb = Fixtures.browser(app, bob)
        res = bb.post("/api/conversations", {name: "Nova", member_ids: [ana.uid]})
        gid = JSON.parse(res.body)["conversation"]["id"].as_i64
        # (Logging in pays daily XP, which may unlock a badge first.)
        note = wait_for(listener, "notification.created")
        while note["notification"]["kind"].as_s == "achievement"
          note = wait_for(listener, "notification.created")
        end
        note["notification"]["kind"].as_s.should eq("group_added")
        wait_for(listener, "conversation.added")["conversation_id"].as_i64.should eq(gid)

        # Not following yet: a foreign conversation id is ignored.
        listener.send_message(ident, {action: "follow", conversation_id: gid})
        sleep 100.milliseconds
        bb.post("/api/conversations/#{gid}/messages", {body: "bem-vinda"})
        wait_for(listener, "message.created")["message"]["body"].as_s.should eq("bem-vinda")
      ensure
        listener.close
      end
    end
  end

  it "shows DM read receipts and friend presence" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      Fixtures.friends(bob, ana)
      dm, _ = Conversation.find_or_create_dm(bob.uid, ana.uid)
      bob_socket = Fixtures.browser(app, bob).cable
      bob_socket.subscribe("ChatChannel")
      begin
        ab = Fixtures.browser(app, ana)
        ana_socket = ab.cable
        ana_socket.subscribe("ChatChannel")
        wait_for(bob_socket, "presence")["online"].as_bool.should be_true

        m, _ = Messaging.post(bob, dm, "viu?", nil, nil, nil)
        ab.post("/api/conversations/#{dm.cid}/read", {message_id: m.mid})
        read = wait_for(bob_socket, "read")
        read["user_id"].as_i64.should eq(ana.uid)
        read["message_id"].as_i64.should eq(m.mid)

        ana_socket.close
        wait_for(bob_socket, "presence")["online"].as_bool.should be_false
      ensure
        bob_socket.close
      end
    end
  end
end
