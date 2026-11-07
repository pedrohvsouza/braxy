require "random/secure"

# Group commit for new messages.
#
# Requests hand their validated message to this per-process writer and wait.
# One fiber drains whatever has queued up (up to MAX_BATCH) and writes it in
# a single transaction:
#
#   * one multi-row INSERT ... ON CONFLICT (author_id, client_id) DO NOTHING
#     RETURNING id, author_id, client_id, created_at
#   * XP: one INSERT xp_events + one UPDATE users FROM (VALUES ...) (rare: the
#     per-user cooldown keeps a user out of concurrent batches)
#
# so N concurrent posts cost one commit (one fsync) instead of N. Under light
# load a batch is a single message and nothing waits for company.
module MessageWriter
  MAX_BATCH = 256

  class Job
    getter message : Message
    getter xp : Int32
    getter done = ::Channel(Exception?).new(1)
    property created = true
    property xp_paid = false

    def initialize(@message : Message, @xp : Int32)
    end
  end

  @@queue = ::Channel(Job).new(8192)
  @@started = Atomic(Bool).new(false)

  # Writes `message` (validated, with client_id set) and fills in its id and
  # timestamps. Returns false when a message with the same (author, client_id)
  # already existed (`message` then holds that row's id).
  def self.write(message : Message, xp : Int32 = 0) : Job
    start
    job = Job.new(message, xp)
    @@queue.send(job)
    if failure = job.done.receive
      raise failure
    end
    job
  end

  def self.start : Nil
    return if @@started.swap(true)
    spawn(name: "braxy-message-writer") do
      loop do
        batch = [@@queue.receive]
        while batch.size < MAX_BATCH
          select
          when job = @@queue.receive
            batch << job
          else
            break
          end
        end
        failure = nil.as(Exception?)
        begin
          write_batch(batch)
        rescue ex
          failure = ex
        end
        Bookkeeping.flush if Saci.env == "test" # specs see it immediately
        batch.each { |job| job.done.send(failure) }
      end
    end
  end

  private def self.placeholders(rows : Int32, cols : Int32) : String
    row = "(" + (["?"] * cols).join(", ") + ")"
    ([row] * rows).join(", ")
  end

  private def self.write_batch(batch : Array(Job)) : Nil
    now = Time.utc
    db = Saci::Record.connection.as(DB::Database)
    db.transaction do |tx|
      conn = tx.connection

      # 1. Insert (duplicates by client_id are skipped and resolved below).
      args = [] of Saci::Record::Value
      batch.each do |job|
        m = job.message
        args.push(m.conversation_id, m.author_id, m.body, m.image_key, m.reply_to_id, m.client_id, now, now)
      end
      inserted = {} of {Int64, String} => {Int64, Time}
      sql = "INSERT INTO messages (conversation_id, author_id, body, image_key, reply_to_id, client_id, created_at, updated_at) " \
            "VALUES #{placeholders(batch.size, 8)} " \
            "ON CONFLICT (author_id, client_id) DO NOTHING RETURNING id, author_id, client_id, created_at"
      Saci::Record.query_compat(conn, sql, args) do |rs|
        rs.each do
          id = rs.read(Int64)
          author = rs.read(Int64)
          client = rs.read(String)
          at = rs.read(Time)
          inserted[{author, client}] = {id, at}
        end
      end

      fresh = [] of Job
      batch.each do |job|
        m = job.message
        if row = inserted[{m.author_id.not_nil!, m.client_id.not_nil!}]?
          m.id = row[0]
          m.created_at = row[1]
          m.updated_at = row[1]
          m.__saci_mark_persisted! # as if loaded: later update_columns work
          fresh << job
        else
          job.created = false
          if existing = Message.find_by(author_id: m.author_id, client_id: m.client_id)
            m.id = existing.id
            m.created_at = existing.created_at
            m.body = existing.body
            m.image_key = existing.image_key
            m.reply_to_id = existing.reply_to_id
            m.__saci_mark_persisted!
          end
        end
      end
      next if fresh.empty?

      # Conversation "last message" bookkeeping is not written here: it is a
      # hot row per conversation, and updating it from concurrent batches on
      # several processes deadlocked. `Bookkeeping` coalesces it instead.
      # The author's own read cursor needs no update at all (unread counts
      # ignore one's own messages).
      fresh.each { |job| Bookkeeping.note(job.message) }

      # 4. Message XP (cooldown already claimed in Redis by the caller).
      paying = fresh.select { |job| job.xp > 0 }
      unless paying.empty?
        xargs = [] of Saci::Record::Value
        paying.each { |job| xargs.push(job.message.author_id, "message", job.xp.to_i64, "message:#{job.message.mid}", now, now) }
        Saci::Record.exec_compat(conn,
          "INSERT INTO xp_events (user_id, kind, amount, source_key, created_at, updated_at) VALUES #{placeholders(paying.size, 6)} " \
          "ON CONFLICT (user_id, kind, source_key) DO NOTHING",
          xargs)
        totals = {} of Int64 => Int64
        paying.each do |job|
          uid = job.message.author_id.not_nil!
          totals[uid] = (totals[uid]? || 0_i64) + job.xp
          job.xp_paid = true
        end
        uargs = [] of Saci::Record::Value
        totals.each { |uid, amt| uargs.push(uid, amt) }
        Saci::Record.exec_compat(conn,
          "UPDATE users AS u SET xp = u.xp + v.amt::bigint FROM (VALUES #{placeholders(totals.size, 2)}) AS v(uid, amt) " \
          "WHERE u.id = v.uid::bigint",
          uargs)
      end
    end
  end

  def self.new_client_id : String
    "srv-" + Random::Secure.hex(12)
  end
end

# Coalesced "last message" bookkeeping for conversations.
#
# Posts only `note` the newest message per conversation in memory; one fiber
# per process writes them every INTERVAL in a single transaction that touches
# rows in ascending id order (every process locks in the same order, so no
# deadlock cycle can form) with synchronous_commit off (the value can always
# be recomputed from the messages themselves).
module Bookkeeping
  INTERVAL = 200.milliseconds

  @@mutex = Mutex.new
  @@latest = {} of Int64 => {Int64, Time}
  @@started = Atomic(Bool).new(false)

  def self.note(message : Message) : Nil
    cid = message.conversation_id.not_nil!
    mid = message.mid
    at = message.created_at || Time.utc
    @@mutex.synchronize do
      if (prev = @@latest[cid]?).nil? || prev[0] < mid
        @@latest[cid] = {mid, at}
      end
    end
    start
  end

  def self.start : Nil
    return if Saci.env == "test" || @@started.swap(true)
    spawn(name: "braxy-bookkeeping") do
      loop do
        sleep INTERVAL
        begin
          flush
        rescue ex
          Saci::Cable.report_error(ex, "bookkeeping")
        end
      end
    end
  end

  def self.flush : Nil
    pending = @@mutex.synchronize do
      p = @@latest
      @@latest = {} of Int64 => {Int64, Time}
      p
    end
    return if pending.empty?
    db = Saci::Record.connection.as(DB::Database)
    db.transaction do |tx|
      conn = tx.connection
      conn.exec("SET LOCAL synchronous_commit TO OFF")
      pending.keys.sort.each do |cid|
        mid, at = pending[cid]
        Saci::Record.exec_compat(conn,
          "UPDATE conversations SET last_message_id = ?, last_message_at = ? " \
          "WHERE id = ? AND (last_message_id IS NULL OR last_message_id < ?)",
          [mid, at, cid, mid] of Saci::Record::Value)
      end
    end
  end
end
