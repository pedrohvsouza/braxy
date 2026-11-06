require "../spec_helper"

describe "notifications API" do
  it "lists, marks one and marks all as read" do
    with_app do |app|
      bob = Fixtures.user("bob")
      ana = Fixtures.user("ana")
      bb = Fixtures.browser(app, bob)
      bb.post("/api/notifications/read_all") # first-login level-up
      n1 = Notification.deliver!(bob.uid, "friend_request", actor_id: ana.uid)
      Notification.deliver!(bob.uid, "level_up", payload: {"level" => 3})
      data = bb.json("/api/notifications")
      data["unread_count"].as_i.should eq(2)
      data["notifications"][0]["payload"]["level"].as_i.should eq(3)
      data["notifications"][1]["actor"]["username"].as_s.should eq("ana")
      JSON.parse(bb.post("/api/notifications/#{n1.id}/read").body)["unread_count"].as_i.should eq(1)
      Fixtures.browser(app, ana).post("/api/notifications/#{n1.id}/read").status_code.should eq(404)
      bb.post("/api/notifications/read_all")
      bb.json("/api/notifications")["unread_count"].as_i.should eq(0)
    end
  end

  it "reports lobby stats" do
    with_app do |app|
      bob = Fixtures.user("bob")
      lobby = Conversation.lobby
      Membership.ensure!(lobby.cid, bob.uid)
      Messaging.post(bob, lobby, "oi", nil, nil, nil)
      stats = Fixtures.browser(app, bob).json("/api/stats")["stats"]
      stats["users"].as_i.should eq(1)
      stats["messages"].as_i.should eq(1)
      stats["groups"].as_i.should eq(1)
    end
  end
end
