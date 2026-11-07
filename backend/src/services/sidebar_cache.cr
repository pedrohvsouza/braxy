# Per-user sidebar responses, kept per process as ready JSON.
#
# An entry is valid while (a) the versions of every conversation the user
# belongs to are unchanged (MessagePageCache versions: bumped by any post,
# edit, delete or reaction) — checked with one Redis MGET — and (b) nothing
# structural changed for the user: membership, friendship, read cursor or a
# conversation rename, all of which arrive through Invalidation. MAX_AGE
# bounds how stale the presence dots can be (clients also get them live):
# an entry past it whose versions still match is served once more while a
# background fiber rebuilds it (stale-while-revalidate), so expiry never
# turns into a burst of synchronous rebuilds.
module SidebarCache
  MAX_AGE     = 10.seconds
  MAX_ENTRIES = 100_000

  REFRESHERS    =    2
  REFRESH_QUEUE = 4096

  alias Build = -> String

  @@mutex = Mutex.new
  @@entries = {} of Int64 => {Array(String?), String, Time::Instant}
  # Users with a background refresh queued or running.
  @@refreshing = Set(Int64).new
  # Single flight: concurrent misses for one user wait for the first build.
  @@inflight = {} of Int64 => Array(::Channel(String?))
  # Bumped by invalidations (per user, and globally by clear!): a build
  # that started before one must not store its possibly outdated result.
  @@generation = 0_i64
  @@user_generation = {} of Int64 => Int64
  @@refresh_queue = ::Channel({Int64, Array(String?), {Int64, Int64}, Build}).new(REFRESH_QUEUE)
  @@refreshers_started = Atomic(Bool).new(false)

  def self.fetch(user_id : Int64, &build : -> String) : String
    convs = Access.conversation_ids(user_id)
    versions = KV.backend.mget(convs.map { |cid| MessagePageCache.version_key(cid) })
    now = Time.instant
    gen = generation(user_id)
    if (hit = @@mutex.synchronize { @@entries[user_id]? }) && hit[0] == versions
      return hit[1] if now - hit[2] < MAX_AGE
      # Past MAX_AGE but nothing it depends on changed: serve it once more
      # and let a refresher rebuild it, at a bounded rate.
      return hit[1] if Saci.env != "test" && schedule_refresh(user_id, versions, gen, build)
    end
    build_once(user_id, versions, gen, build)
  end

  private def self.build_once(user_id : Int64, versions : Array(String?), gen : {Int64, Int64}, build : Build) : String
    waiter = nil.as(::Channel(String?)?)
    @@mutex.synchronize do
      if waiters = @@inflight[user_id]?
        waiter = ::Channel(String?).new(1)
        waiters << waiter
      else
        @@inflight[user_id] = [] of ::Channel(String?)
      end
    end
    if w = waiter
      # Another fiber is building this user's sidebar; nil means it failed.
      return w.receive || build.call
    end
    json = nil.as(String?)
    begin
      json = build.call
      store(user_id, versions, json, gen)
      json
    ensure
      waiters = @@mutex.synchronize { @@inflight.delete(user_id) }
      waiters.try &.each(&.send(json))
    end
  end

  private def self.schedule_refresh(user_id : Int64, versions : Array(String?), gen : {Int64, Int64}, build : Build) : Bool
    start_refreshers
    return true unless @@mutex.synchronize { @@refreshing.add?(user_id) } # already queued
    select
    when @@refresh_queue.send({user_id, versions, gen, build})
      true
    else
      @@mutex.synchronize { @@refreshing.delete(user_id) }
      false # queue full: rebuild in the request instead
    end
  end

  private def self.start_refreshers : Nil
    return if @@refreshers_started.swap(true)
    REFRESHERS.times do
      spawn(name: "sidebar-refresh") do
        loop do
          user_id, versions, gen, build = @@refresh_queue.receive
          begin
            build_once(user_id, versions, gen, build)
          rescue ex
            Saci::Cable.report_error(ex, "sidebar refresh")
          ensure
            @@mutex.synchronize { @@refreshing.delete(user_id) }
          end
        end
      end
    end
  end

  private def self.generation(user_id : Int64) : {Int64, Int64}
    @@mutex.synchronize { current_generation(user_id) }
  end

  # Caller holds @@mutex.
  private def self.current_generation(user_id : Int64) : {Int64, Int64}
    {@@generation, @@user_generation[user_id]? || 0_i64}
  end

  private def self.store(user_id : Int64, versions : Array(String?), json : String, gen : {Int64, Int64}) : Nil
    @@mutex.synchronize do
      return if current_generation(user_id) != gen
      @@entries.clear if @@entries.size >= MAX_ENTRIES
      @@entries[user_id] = {versions, json, Time.instant}
    end
  end

  def self.invalidate(user_id : Int64) : Nil
    @@mutex.synchronize do
      @@user_generation[user_id] = (@@user_generation[user_id]? || 0_i64) + 1
      @@entries.delete(user_id)
    end
  end

  def self.clear! : Nil
    @@mutex.synchronize do
      @@generation += 1
      @@user_generation.clear
      @@entries.clear
    end
  end
end
