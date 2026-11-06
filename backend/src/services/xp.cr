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

  def self.award(user_id : Int64, kind : String, amount : Int32, source_key : String) : Bool
    begin
      XpEvent.create!(user_id: user_id, kind: kind, amount: amount, source_key: source_key)
    rescue Saci::Record::RecordInvalid | DB::Error
      return false # already paid
    end
    db = Saci::Record.connection
    Saci::Record.exec_compat(db, "UPDATE users SET xp = xp + ? WHERE id = ?", [amount.to_i64, user_id] of Saci::Record::Value)
    after_change(user_id)
    true
  end

  # Message XP with a per-user cooldown (claimed atomically so parallel
  # sends cannot both pay).
  def self.for_message(user : User, message : Message, conversation : Conversation) : Bool
    now = Time.utc
    db = Saci::Record.connection
    claimed = Saci::Record.exec_compat(db,
      "UPDATE users SET last_message_xp_at = ? WHERE id = ? AND (last_message_xp_at IS NULL OR last_message_xp_at < ?)",
      [now, user.uid, now - MESSAGE_COOLDOWN] of Saci::Record::Value).rows_affected
    return false if claimed == 0
    amount = conversation.dm? ? DM_MESSAGE : GROUP_MESSAGE
    award(user.uid, "message", amount, "message:#{message.mid}")
  end

  def self.daily_login(user : User) : Bool
    today = Time.utc.in(BRT).at_beginning_of_day
    day = Time.utc(today.year, today.month, today.day)
    db = Saci::Record.connection
    claimed = Saci::Record.exec_compat(db,
      "UPDATE users SET last_daily_xp_on = ? WHERE id = ? AND (last_daily_xp_on IS NULL OR last_daily_xp_on < ?)",
      [day, user.uid, day] of Saci::Record::Value).rows_affected
    return false if claimed == 0
    award(user.uid, "daily_login", DAILY_LOGIN, "day:#{today.to_s("%Y-%m-%d")}")
  end

  # Recomputes the stored level, notifies on level-up and pushes the new
  # progress to the user's own sockets.
  def self.after_change(user_id : Int64) : Nil
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
