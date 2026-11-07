# Small Redis facade for the commands Braxy needs beyond Saci::Cache
# (sorted sets, counters, locks), over Saci's vendored RESP client.
#
# A tiny connection pool keeps it safe under concurrent fibers (and several
# processes share state through Redis itself). Without REDIS_URL — specs,
# bare-metal runs — an in-process implementation with the same semantics
# is used instead.
module KV
  abstract class Backend
    abstract def incr(key : String, by : Int64 = 1) : Int64
    abstract def get(key : String) : String?
    abstract def set(key : String, value : String, ttl : Time::Span? = nil, nx : Bool = false) : Bool
    abstract def del(key : String) : Nil
    abstract def getdel(key : String) : String?
    abstract def zadd(key : String, score : Int64, member : String) : Nil
    abstract def zrem(key : String, member : String) : Nil
    abstract def zscores(key : String, members : Array(String)) : Array(Int64?)
    abstract def zcount(key : String, min : Int64) : Int64
    abstract def zremrangebyscore(key : String, max : Int64) : Nil
  end

  class RedisBackend < Backend
    POOL_SIZE = 8

    @pool : ::Channel(Saci::Cable::RedisWire::Conn)

    def initialize(url : String)
      info = Saci::Cable::RedisWire.parse_url(url)
      @pool = ::Channel(Saci::Cable::RedisWire::Conn).new(POOL_SIZE)
      POOL_SIZE.times { @pool.send(Saci::Cable::RedisWire::Conn.new(info)) }
    end

    def call(args : Array(String)) : Saci::Cable::RedisWire::RedisValue
      conn = @pool.receive
      begin
        conn.call(args)
      ensure
        @pool.send(conn)
      end
    end

    def incr(key : String, by : Int64 = 1) : Int64
      call(["INCRBY", key, by.to_s]).as(Int64)
    end

    def get(key : String) : String?
      call(["GET", key]).as?(String)
    end

    def set(key : String, value : String, ttl : Time::Span? = nil, nx : Bool = false) : Bool
      args = ["SET", key, value]
      args += ["PX", ttl.total_milliseconds.to_i64.to_s] if ttl
      args << "NX" if nx
      call(args) == "OK"
    end

    def del(key : String) : Nil
      call(["DEL", key])
    end

    def getdel(key : String) : String?
      call(["GETDEL", key]).as?(String)
    end

    def zadd(key : String, score : Int64, member : String) : Nil
      call(["ZADD", key, score.to_s, member])
    end

    def zrem(key : String, member : String) : Nil
      call(["ZREM", key, member])
    end

    def zscores(key : String, members : Array(String)) : Array(Int64?)
      return [] of Int64? if members.empty?
      reply = call(["ZMSCORE", key] + members).as(Array)
      reply.map { |v| v.as?(String).try(&.to_f64?).try(&.to_i64) }
    end

    def zcount(key : String, min : Int64) : Int64
      call(["ZCOUNT", key, min.to_s, "+inf"]).as(Int64)
    end

    def zremrangebyscore(key : String, max : Int64) : Nil
      call(["ZREMRANGEBYSCORE", key, "-inf", "(#{max}"])
    end
  end

  class MemoryBackend < Backend
    @mutex = Mutex.new
    @strings = {} of String => {String, Time?}
    @zsets = {} of String => Hash(String, Int64)

    private def live(key : String) : String?
      entry = @strings[key]?
      return nil if entry.nil?
      if (exp = entry[1]) && exp <= Time.utc
        @strings.delete(key)
        return nil
      end
      entry[0]
    end

    def incr(key : String, by : Int64 = 1) : Int64
      @mutex.synchronize do
        value = (live(key).try(&.to_i64?) || 0_i64) + by
        @strings[key] = {value.to_s, @strings[key]?.try(&.[1])}
        value
      end
    end

    def get(key : String) : String?
      @mutex.synchronize { live(key) }
    end

    def set(key : String, value : String, ttl : Time::Span? = nil, nx : Bool = false) : Bool
      @mutex.synchronize do
        return false if nx && live(key)
        @strings[key] = {value, ttl.try { |t| Time.utc + t }}
        true
      end
    end

    def del(key : String) : Nil
      @mutex.synchronize { @strings.delete(key) }
    end

    def getdel(key : String) : String?
      @mutex.synchronize do
        v = live(key)
        @strings.delete(key)
        v
      end
    end

    def zadd(key : String, score : Int64, member : String) : Nil
      @mutex.synchronize { (@zsets[key] ||= {} of String => Int64)[member] = score }
    end

    def zrem(key : String, member : String) : Nil
      @mutex.synchronize { @zsets[key]?.try(&.delete(member)) }
    end

    def zscores(key : String, members : Array(String)) : Array(Int64?)
      @mutex.synchronize { members.map { |m| @zsets[key]?.try(&.[m]?) } }
    end

    def zcount(key : String, min : Int64) : Int64
      @mutex.synchronize { (@zsets[key]?.try(&.count { |_, s| s >= min }) || 0).to_i64 }
    end

    def zremrangebyscore(key : String, max : Int64) : Nil
      @mutex.synchronize { @zsets[key]?.try(&.reject! { |_, s| s < max }) }
    end

    def clear : Nil
      @mutex.synchronize do
        @strings.clear
        @zsets.clear
      end
    end
  end

  @@backend : Backend? = nil

  def self.backend : Backend
    @@backend ||= begin
      url = ENV["REDIS_URL"]?
      if url && !url.empty? && Saci.env != "test"
        RedisBackend.new(url).as(Backend)
      else
        MemoryBackend.new.as(Backend)
      end
    end
  end

  def self.backend=(backend : Backend) : Nil
    @@backend = backend
  end

  # Specs: forget in-memory state between examples.
  def self.reset! : Nil
    if (b = @@backend).is_a?(MemoryBackend)
      b.clear
    end
  end
end
