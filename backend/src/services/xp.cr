# XP awards. Every award is idempotent on (user, kind, source_key) through
# the xp_events unique index, so retries and re-toggles never double-pay.
module Xp
  GROUP_MESSAGE    = 10
  DM_MESSAGE       =  2
  DAILY_LOGIN      = 50
  FRIENDSHIP       = 20
  REACTION         =  2
  MESSAGE_COOLDOWN = 10.seconds

  # Brazil has no DST since 2019: a fixed UTC-3 "day" is enough.
  BRT = Time::Location.fixed("BRT", -3 * 3600)

  # Pays `amount` once per (user, kind, source_key). `notify: false` only
  # writes (safe inside a transaction); the caller runs `after_change`
  # after commit.
  def self.award(user_id : Int64, kind : String, amount : Int32, source_key : String, notify : Bool = true) : Bool
    db = Saci::Record.connection
    now = Time.utc
    # ON CONFLICT instead of rescuing a unique violation: an error would
    # abort the surrounding transaction.
    inserted = Saci::Record.exec_compat(db,
      "INSERT INTO xp_events (user_id, kind, amount, source_key, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?) " \
      "ON CONFLICT (user_id, kind, source_key) DO NOTHING",
      [user_id, kind, amount.to_i64, source_key, now, now] of Saci::Record::Value).rows_affected
    return false if inserted == 0
    Saci::Record.exec_compat(db, "UPDATE users SET xp = xp + ? WHERE id = ?", [amount.to_i64, user_id] of Saci::Record::Value)
    after_change(user_id) if notify
    true
  end

  # Message XP cooldown, claimed atomically in Redis (SET NX with a TTL) so
  # parallel sends — on any process — cannot both pay, and no database
  # write happens for the posts in between. Returns the XP to award (0
  # while cooling down); the batch writer persists it.
  def self.claim_message_xp(user : User, conversation : Conversation) : Int32
    return 0 unless KV.backend.set("braxy:msgxp:#{user.uid}", "1", ttl: MESSAGE_COOLDOWN, nx: true)
    conversation.dm? ? DM_MESSAGE : GROUP_MESSAGE
  end

  # The Redis guard makes every request after the first of the day free
  # (no UPDATE at all).
  # In-process memo of guards already settled today, so repeat requests
  # skip even the Redis round trip.
  @@daily_seen = Set(String).new
  @@daily_mutex = Mutex.new

  def self.daily_login(user : User) : Bool
    today = Time.utc.in(BRT).at_beginning_of_day
    guard = "braxy:daily:#{user.uid}:#{today.to_s("%Y-%m-%d")}"
    return false if @@daily_mutex.synchronize { @@daily_seen.includes?(guard) }
    remember = ->{
      @@daily_mutex.synchronize do
        @@daily_seen.clear if @@daily_seen.size > 500_000
        @@daily_seen << guard
      end
    }
    unless KV.backend.set(guard, "1", ttl: 26.hours, nx: true)
      remember.call
      return false
    end
    remember.call
    day = Time.utc(today.year, today.month, today.day)
    db = Saci::Record.connection
    claimed = Saci::Record.exec_compat(db,
      "UPDATE users SET last_daily_xp_on = ? WHERE id = ? AND (last_daily_xp_on IS NULL OR last_daily_xp_on < ?)",
      [day, user.uid, day] of Saci::Record::Value).rows_affected
    return false if claimed == 0
    Invalidation.user(user.uid)
    award(user.uid, "daily_login", DAILY_LOGIN, "day:#{today.to_s("%Y-%m-%d")}")
  end

  def self.reset_memo! : Nil
    @@daily_mutex.synchronize { @@daily_seen.clear }
  end

  # Recomputes the stored level, notifies on level-up and pushes the new
  # progress to the user's own sockets.
  def self.after_change(user_id : Int64) : Nil
    Invalidation.user(user_id)
    user = User.find_by(id: user_id)
    return if user.nil?
    progress = Levels.progress(user.xp_total)
    old_level = user.level || 1
    if progress[:level] != old_level
      user.update_columns(level: progress[:level])
      if progress[:level] > old_level
        Notification.deliver!(user_id, "level_up", payload: {"level" => progress[:level]})
      end
    end
    Realtime.to_user(user_id, {
      type:       "xp.updated",
      xp:         user.xp_total,
      level:      progress[:level],
      level_xp:   progress[:into],
      level_need: progress[:need],
    })
  end
end
