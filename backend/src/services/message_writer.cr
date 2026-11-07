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
  # Fuller batches mean fewer commits per message. After draining what is
  # queued, keep collecting only while posts keep arriving (each wait is at
  # most IDLE_GAP, the whole batch at most LINGER): a burst that has fully
  # arrived is written at once.
  MIN_FILL = 64
  IDLE_GAP = 200.microseconds
  LINGER   = 1.millisecond
  # Writer fibers draining the queue: while one batch waits on Postgres the
  # next one is already collecting (batches of different processes run
  # concurrently anyway, so this adds no new ordering case).
  WRITERS = (ENV["MESSAGE_WRITERS"]? || "1").to_i

  class Job
    getter message : Message
    getter xp : Int32
    getter author_name : String
    getter done = ::Channel(Exception?).new(1)
    property created = true
    property xp_paid = false

    def initialize(@message : Message, @xp : Int32, @author_name : String = "?")
    end
  end

  @@queue = ::Channel(Job).new(8192)
  @@started = Atomic(Bool).new(false)

  # Writes `message` (validated, with client_id set) and fills in its id and
  # timestamps. Returns false when a message with the same (author, client_id)
  # already existed (`message` then holds that row's id).
  def self.write(message : Message, xp : Int32 = 0, author_name : String = "?") : Job
    start
    job = Job.new(message, xp, author_name)
    @@queue.send(job)
    if failure = job.done.receive
      raise failure
    end
    job
  end

  def self.start : Nil
    return if @@started.swap(true)
    (Saci.env == "test" ? 1 : WRITERS).times { |i| spawn(name: "braxy-message-writer-#{i}") { run_writer } }
  end

  private def self.run_writer : Nil
    last_size = 1
    loop do
      batch = [@@queue.receive]
      deadline = Time.instant + LINGER
      while batch.size < MAX_BATCH
        select
        when job = @@queue.receive
          batch << job
        else
          # A lone post, after a batch that was also alone, goes out at
          # once: posts are not arriving together, so waiting for company
          # would only add latency. As soon as they do, the writer lingers
          # again (fewer, fuller commits).
          break if (batch.size == 1 && last_size == 1) || batch.size >= MIN_FILL || Saci.env == "test"
          remaining = deadline - Time.instant
          break if remaining <= Time::Span.zero
          select
          when job = @@queue.receive
            batch << job
          when timeout({remaining, IDLE_GAP}.min)
            break
          end
        end
      end
      last_size = batch.size
      failure = nil.as(Exception?)
      begin
        write_batch(batch)
        # Per conversation in this batch: refresh the sidebar preview with
        # its newest message, then bump the cache version (in that order,
        # so a reader that sees the new version also sees the preview).
        newest = {} of Int64 => Job
        batch.each do |job|
          next unless job.created
          cid = job.message.conversation_id.not_nil!
          newest[cid] = job if (prev = newest[cid]?).nil? || prev.message.mid < job.message.mid
        end
        entries = newest.map do |cid, job|
          {ConversationPreview.id_key(cid), ConversationPreview.key(cid), job.message.mid,
           ConversationPreview.json_for(job.message, job.author_name)}
        end
        cids = newest.keys
        bumped = KV.backend.set_if_newer_and_bump(entries, cids.map { |cid| {MessagePageCache.version_key(cid), cid} }, Invalidation::CHANNEL)
        cids.each_with_index { |cid, i| bumped[i]?.try { |v| MessagePageCache.observe(cid, v) } }
      rescue ex
        failure = ex
      end
      Bookkeeping.flush if Saci.env == "test" # specs see it immediately
      batch.each { |job| job.done.send(failure) }
    end
  end

  alias BatchArg = Array(Int64) | Array(Int64?) | Array(String) | Array(String?) | Time | Int64 | String | Nil

  # The whole batch is ONE statement in autocommit: the message INSERT and,
  # through data-modifying CTEs, the XP events and user totals for the rows
  # that were really inserted. One round trip instead of BEGIN / INSERT /
  # INSERT / UPDATE / COMMIT, so the connection never sits "idle in
  # transaction" while this fiber waits for its turn on the scheduler.
  #
  # Rows travel as one array parameter per column (unnest), so the SQL text
  # is the same for every batch size: two prepared statements in all,
  # instead of one per size, each with 8 parameters to bind rather than 8
  # per row.
  #
  # The batch first goes in as a plain INSERT: ON CONFLICT's speculative
  # insertion costs Postgres about 3x more per row, and duplicates (a
  # client retrying a post) are rare. A batch that hits one fails as a
  # whole, with nothing written, and is retried with ON CONFLICT DO NOTHING.
  INSERT_SQL = "WITH v AS (SELECT * FROM unnest($1::bigint[], $2::bigint[], $3::text[], $4::text[], $5::bigint[], $6::text[]) " \
               "WITH ORDINALITY AS t(conversation_id, author_id, body, image_key, reply_to_id, client_id, ord)), " \
               "ins AS (INSERT INTO messages (conversation_id, author_id, body, image_key, reply_to_id, client_id, created_at, updated_at) " \
               "SELECT conversation_id, author_id, body, image_key, reply_to_id, client_id, $7::timestamp, $7::timestamp FROM v ORDER BY ord " \
               "RETURNING id, author_id, client_id, created_at)"
  XP_SQL = ", xp AS (SELECT * FROM unnest($8::bigint[], $9::text[], $10::bigint[]) AS x(uid, cid, amt)), " \
           "xpe AS (INSERT INTO xp_events (user_id, kind, amount, source_key, created_at, updated_at) " \
           "SELECT ins.author_id, 'message', xp.amt, 'message:' || ins.id, ins.created_at, ins.created_at " \
           "FROM xp JOIN ins ON ins.author_id = xp.uid AND ins.client_id = xp.cid " \
           "ON CONFLICT (user_id, kind, source_key) DO NOTHING RETURNING user_id, amount), " \
           "upd AS (UPDATE users AS u SET xp = u.xp + t.amt FROM " \
           "(SELECT user_id, sum(amount)::bigint AS amt FROM xpe GROUP BY user_id) AS t WHERE u.id = t.user_id)"
  # A batch of one (the common case at low load) binds plain values: the
  # driver's array encoding and unnest cost ~0.3 ms more per statement.
  INSERT_ONE_SQL = "WITH ins AS (INSERT INTO messages (conversation_id, author_id, body, image_key, reply_to_id, client_id, created_at, updated_at) " \
                   "VALUES ($1, $2, $3, $4, $5, $6, $7, $7) RETURNING id, author_id, client_id, created_at)"
  SELECT_SQL  = " SELECT id, author_id, client_id, created_at FROM ins"
  ON_CONFLICT = "ON CONFLICT (author_id, client_id) DO NOTHING RETURNING id, author_id"
  # {single row, with ON CONFLICT, with XP} => statement
  BATCH_SQL = begin
    sql = {} of {Bool, Bool, Bool} => String
    {true, false}.each do |single|
      insert = single ? INSERT_ONE_SQL : INSERT_SQL
      {true, false}.each do |conflict|
        head = conflict ? insert.sub("RETURNING id, author_id", ON_CONFLICT) : insert
        sql[{single, conflict, false}] = head + SELECT_SQL
        sql[{single, conflict, true}] = head + XP_SQL + SELECT_SQL
      end
    end
    sql
  end
  UNIQUE_VIOLATION = "23505"

  # :nodoc:
  # Writes `batch` as one statement right now (specs: batches written by the
  # writer fiber are always single in the test environment).
  def self.__write_batch(batch : Array(Job)) : Nil
    write_batch(batch)
  end

  private def self.write_batch(batch : Array(Job)) : Nil
    now = Time.utc
    msgs = batch.map(&.message)
    single = batch.size == 1
    args = if single
             m = msgs[0]
             [m.conversation_id.not_nil!, m.author_id.not_nil!, m.body, m.image_key, m.reply_to_id,
              m.client_id.not_nil!, now] of BatchArg
           else
             [
               msgs.map(&.conversation_id.not_nil!), msgs.map(&.author_id.not_nil!),
               msgs.map(&.body), msgs.map(&.image_key), msgs.map(&.reply_to_id),
               msgs.map(&.client_id.not_nil!), now,
             ] of BatchArg
           end
    paying = batch.select { |job| job.xp > 0 }
    unless paying.empty?
      args << paying.map(&.message.author_id.not_nil!)
      args << paying.map(&.message.client_id.not_nil!)
      args << paying.map(&.xp.to_i64)
    end

    inserted = {} of {Int64, String} => {Int64, Time}
    db = Saci::Record.connection.as(DB::Database)
    db.using_connection do |conn|
      begin
        insert_rows(conn, BATCH_SQL[{single, false, !paying.empty?}], args, inserted)
      rescue ex : PQ::PQError
        raise ex unless ex.field_message(:code) == UNIQUE_VIOLATION
        inserted.clear
        insert_rows(conn, BATCH_SQL[{single, true, !paying.empty?}], args, inserted)
      end
    end

    batch.each do |job|
      m = job.message
      if row = inserted[{m.author_id.not_nil!, m.client_id.not_nil!}]?
        m.id = row[0]
        m.created_at = row[1]
        m.updated_at = row[1]
        m.__saci_mark_persisted! # as if loaded: later update_columns work
        job.xp_paid = job.xp > 0
        # Conversation "last message" bookkeeping is not written here: it is
        # a hot row per conversation, and updating it from concurrent batches
        # on several processes deadlocked. `Bookkeeping` coalesces it. The
        # author's own read cursor needs no update (unread counts ignore
        # one's own messages).
        Bookkeeping.note(m)
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
  end

  private def self.insert_rows(conn : DB::Connection, sql : String, args : Array(BatchArg), into : Hash({Int64, String}, {Int64, Time})) : Nil
    conn.query(sql, args: args) do |rs|
      rs.each do
        id = rs.read(Int64)
        author = rs.read(Int64)
        client = rs.read(String)
        at = rs.read(Time)
        into[{author, client}] = {id, at}
      end
    end
  end

  # Only has to be unique per author within the unique index, not secret:
  # the fast PRNG avoids a getrandom syscall per post.
  def self.new_client_id : String
    "srv-#{Random.rand(UInt64::MAX).to_s(36)}#{Random.rand(UInt32::MAX).to_s(36)}"
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
    # One statement: the CTE locks the rows in ascending id order (every
    # process locks in the same order, so no deadlock cycle can form) and
    # the UPDATE only moves last_message_id forward.
    args = [] of Saci::Record::Value
    cids = pending.keys.sort
    cids.each do |cid|
      mid, at = pending[cid]
      args.push(cid, mid, at)
    end
    rows = (["(?::bigint, ?::bigint, ?::timestamp)"] * cids.size).join(", ")
    Saci::Record.exec_compat(Saci::Record.connection.as(DB::Database),
      "WITH v(cid, mid, at) AS (VALUES #{rows}), " \
      "locked AS (SELECT c.id FROM conversations c JOIN v ON v.cid = c.id ORDER BY c.id FOR UPDATE) " \
      "UPDATE conversations c SET last_message_id = v.mid, last_message_at = v.at " \
      "FROM v, locked WHERE c.id = v.cid AND locked.id = c.id " \
      "AND (c.last_message_id IS NULL OR c.last_message_id < v.mid)",
      args)
  end
end
