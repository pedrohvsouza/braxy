# Coalesced read cursors for groups and the lobby.
#
# The client marks a conversation as read for every message that arrives
# while it is open, so a message in a busy room turns into one read request
# per viewer. Each request only `note`s the cursor in memory (no I/O); one
# fiber per process writes the pending cursors every INTERVAL in a single
# statement that
#
#   * locks the membership rows in ascending id order (every process locks
#     in the same order, so no deadlock cycle can form),
#   * never moves a cursor back, and never past the conversation's newest
#     message (the clamp is the messages table itself: a message a client
#     has seen is always already inserted),
#
# and then invalidates the sidebars of the users whose cursor moved, in one
# announcement. The client clears its badge itself, so nothing waits for
# the write. DMs do not come here: the other side shows "Visto" from them.
module ReadCursors
  INTERVAL = 200.milliseconds

  @@mutex = Mutex.new
  @@pending = {} of {Int64, Int64} => Int64
  @@started = Atomic(Bool).new(false)

  SQL = "WITH v AS (SELECT * FROM unnest($1::bigint[], $2::bigint[], $3::bigint[]) AS t(cid, uid, upto)), " \
        "locked AS (SELECT mb.id, LEAST(v.upto, (SELECT max(m.id) FROM messages m WHERE m.conversation_id = v.cid)) AS upto " \
        "FROM memberships mb JOIN v ON mb.conversation_id = v.cid AND mb.user_id = v.uid " \
        "ORDER BY mb.id FOR UPDATE OF mb) " \
        "UPDATE memberships mb SET last_read_message_id = locked.upto FROM locked " \
        "WHERE mb.id = locked.id AND locked.upto IS NOT NULL " \
        "AND COALESCE(mb.last_read_message_id, 0) < locked.upto RETURNING mb.user_id"

  # Records that `user_id` has read `conversation_id` up to `upto`
  # (Int64::MAX: up to its newest message).
  def self.note(conversation_id : Int64, user_id : Int64, upto : Int64) : Nil
    key = {conversation_id, user_id}
    @@mutex.synchronize do
      prev = @@pending[key]?
      @@pending[key] = upto if prev.nil? || prev < upto
    end
    if Saci.env == "test"
      flush # specs see it immediately
    else
      start
    end
  end

  def self.start : Nil
    return if @@started.swap(true)
    spawn(name: "braxy-read-cursors") do
      loop do
        sleep INTERVAL
        begin
          flush
        rescue ex
          Saci::Cable.report_error(ex, "read cursors")
        end
      end
    end
  end

  def self.flush : Nil
    pending = @@mutex.synchronize do
      p = @@pending
      @@pending = {} of {Int64, Int64} => Int64
      p
    end
    return if pending.empty?
    cids = [] of Int64
    uids = [] of Int64
    uptos = [] of Int64
    pending.each do |(cid, uid), upto|
      cids << cid
      uids << uid
      uptos << upto
    end
    moved = [] of Int64
    db = Saci::Record.connection.as(DB::Database)
    db.using_connection do |conn|
      conn.query(SQL, args: [cids, uids, uptos]) do |rs|
        rs.each { moved << rs.read(Int64) }
      end
    end
    Invalidation.sidebars(moved.uniq) unless moved.empty?
  rescue ex
    # Put the cursors back (keeping any newer ones) for the next round.
    @@mutex.synchronize do
      pending.try &.each do |key, upto|
        prev = @@pending[key]?
        @@pending[key] = upto if prev.nil? || prev < upto
      end
    end
    raise ex
  end
end
