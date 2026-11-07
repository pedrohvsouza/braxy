# Badges for milestones. Names, icons and descriptions live in the client
# (i18n); the server only knows the keys and how each one is earned.
#
# Checked after every XP change (Xp.after_change), which message XP already
# throttles to once per 10 s per user, and off the request fiber. Each check
# reads the user's unlocked keys and then counts only what a missing badge
# needs, with bounded queries.
module Achievements
  enum Metric
    Level
    Messages
    Friends
    ReactionsReceived
    DailyLogins
    GroupsFounded
  end

  record Def, key : String, metric : Metric, goal : Int32

  ALL = [
    Def.new("first_message", Metric::Messages, 1),
    Def.new("chatter", Metric::Messages, 100),
    Def.new("voice_of_the_lobby", Metric::Messages, 1000),
    Def.new("first_friend", Metric::Friends, 1),
    Def.new("popular", Metric::Friends, 10),
    Def.new("founder", Metric::GroupsFounded, 1),
    Def.new("loved", Metric::ReactionsReceived, 50),
    Def.new("regular", Metric::DailyLogins, 7),
    Def.new("level_10", Metric::Level, 10),
    Def.new("level_25", Metric::Level, 25),
    Def.new("level_50", Metric::Level, 50),
  ]

  KEYS = ALL.map(&.key)

  # Runs `check` in its own fiber (never fails the caller).
  def self.check_later(user_id : Int64) : Nil
    spawn(name: "achievements") do
      check(user_id)
    rescue ex
      Log.error(exception: ex) { "achievement check failed for user #{user_id}" }
    end
  end

  # Unlocks every badge `user_id` has earned and does not hold yet, with a
  # notification each. Returns the new keys.
  def self.check(user_id : Int64) : Array(String)
    have = UserAchievement.where(user_id: user_id).to_a.compact_map(&.key).to_set
    missing = ALL.reject { |d| have.includes?(d.key) }
    return [] of String if missing.empty?
    user = User.find_by(id: user_id)
    return [] of String if user.nil?

    values = {} of Metric => Int64
    unlocked = [] of String
    missing.each do |d|
      value = values[d.metric] ||= measure(user, d.metric, missing.select(&.metric.==(d.metric)).max_of(&.goal))
      next if value < d.goal
      next unless claim(user_id, d.key)
      unlocked << d.key
      Notification.deliver!(user_id, "achievement", payload: {"key" => d.key})
    end
    unlocked
  end

  # The metric's value, counted no further than `cap`.
  private def self.measure(user : User, metric : Metric, cap : Int32) : Int64
    uid = user.uid
    case metric
    in .level?              then Levels.progress(user.xp_total)[:level].to_i64
    in .friends?            then Friendship.friend_ids(uid).size.to_i64
    in .messages?           then count_capped("SELECT 1 FROM messages WHERE author_id = ?", uid, cap)
    in .reactions_received? then count_capped("SELECT 1 FROM xp_events WHERE user_id = ? AND kind = 'reaction'", uid, cap)
    in .daily_logins?       then count_capped("SELECT 1 FROM xp_events WHERE user_id = ? AND kind = 'daily_login'", uid, cap)
    in .groups_founded?     then count_capped("SELECT 1 FROM conversations WHERE owner_id = ? AND kind = 'group'", uid, cap)
    end
  end

  private def self.count_capped(inner : String, uid : Int64, cap : Int32) : Int64
    n = 0_i64
    sql = "SELECT COUNT(*) FROM (#{inner} LIMIT #{cap.to_i}) capped"
    Saci::Record.query_compat(Saci::Record.connection, sql, [uid] of Saci::Record::Value) do |rs|
      rs.each { n = rs.read(Int64) }
    end
    n
  end

  # Inserts the badge once (a concurrent check loses the race quietly).
  private def self.claim(user_id : Int64, key : String) : Bool
    now = Time.utc
    Saci::Record.exec_compat(Saci::Record.connection,
      "INSERT INTO user_achievements (user_id, key, created_at, updated_at) VALUES (?, ?, ?, ?) " \
      "ON CONFLICT (user_id, key) DO NOTHING",
      [user_id, key, now, now] of Saci::Record::Value).rows_affected > 0
  end
end
