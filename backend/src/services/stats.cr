# Lobby counters for the empty state. Mutations call `touch!`; a single
# background fiber (started at boot) recomputes and broadcasts at most once
# every INTERVAL, so a message storm costs one query batch per tick.
module Stats
  INTERVAL = 3.seconds

  @@dirty = Atomic(Int32).new(0)

  def self.snapshot
    {
      users:    User.count,
      messages: Message.where("deleted_at IS NULL").count,
      online:   Presence.online_count,
      groups:   Conversation.where("kind IN ('lobby','group')").count,
    }
  end

  def self.touch! : Nil
    @@dirty.set(1)
  end

  def self.start_broadcaster : Nil
    spawn(name: "braxy-stats") do
      loop do
        sleep INTERVAL
        next unless @@dirty.swap(0) == 1
        begin
          Saci::Cable.broadcast(Realtime::STATS_STREAM, {type: "stats", stats: snapshot})
        rescue ex
          Saci::Cable.report_error(ex, "stats broadcaster")
        end
      end
    end
  end
end
