require "../spec_helper"

private def badges(user : User) : Array(String)
  UserAchievement.where(user_id: user.uid).to_a.compact_map(&.key).sort
end

private def wait_for_badge(user : User, key : String) : Nil
  deadline = Time.instant + 3.seconds
  until badges(user).includes?(key) || Time.instant > deadline
    sleep 20.milliseconds
  end
end

describe Achievements do
  it "unlocks what was earned, once, with a notification each" do
    with_app do |_app|
      ana = Fixtures.user("ana", xp: Levels.total_for(12)) # level 12
      bob = Fixtures.user("bob")
      Fixtures.friends(ana, bob)

      Achievements.check(ana.uid).sort.should eq(["first_friend", "level_10"])
      Achievements.check(ana.uid).should be_empty
      Notification.where(user_id: ana.uid, kind: "achievement").count.should eq(2)

      Fixtures.group(ana, "Clube")
      Achievements.check(ana.uid).should eq(["founder"])
    end
  end

  it "counts messages and shows badges on the profile" do
    with_app do |app|
      bob = Fixtures.user("bob")
      lobby = Conversation.lobby
      Membership.ensure!(lobby.cid, bob.uid)
      bb = Fixtures.browser(app, bob)
      # The first message pays XP, and every XP change runs a check.
      bb.post("/api/conversations/#{lobby.cid}/messages", {body: "oi"}).status_code.should eq(201)
      wait_for_badge(bob, "first_message")
      badges(bob).should contain("first_message")
      badges(bob).should_not contain("chatter")

      profile = bb.json("/api/users/bob")["user"]
      keys = profile["achievements"].as_a.map(&.["key"].as_s)
      keys.should contain("first_message")
      profile["achievements"][0]["unlocked_at"].as_s.should_not be_empty
    end
  end
end
