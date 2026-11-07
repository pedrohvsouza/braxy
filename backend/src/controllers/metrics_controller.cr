require "crypto/subtle"

# GET /metrics: Prometheus text for the process that answers (each process
# of bin/multi keeps its own counters; see docs/deploy.md). 404 unless
# METRICS_TOKEN is set; requires `Authorization: Bearer <METRICS_TOKEN>`.
class MetricsController < Saci::Controller
  STARTED_AT = Time.instant

  def show
    token = Observability.metrics_token
    unless token
      render text: "Not Found", status: 404
      return
    end
    given = request.headers["Authorization"]?.try(&.lchop("Bearer ")) || ""
    unless Crypto::Subtle.constant_time_compare(given, token)
      render text: "Unauthorized", status: 401
      return
    end
    render text: Saci::Metrics.to_prometheus + process_metrics, content_type: "text/plain; version=0.0.4; charset=utf-8"
  end

  private def process_metrics : String
    gc = GC.stats
    pid = Process.pid
    String.build do |io|
      gauge(io, "braxy_process_info", "Process answering this scrape.", 1, pid)
      gauge(io, "braxy_uptime_seconds", "Seconds since this process booted.", (Time.instant - STARTED_AT).total_seconds.round(1), pid)
      gauge(io, "braxy_cable_connections", "Open WebSocket connections on this process.", Saci::Cable.server.open_connections_count, pid)
      gauge(io, "braxy_gc_heap_bytes", "GC heap size.", gc.heap_size, pid)
      gauge(io, "braxy_gc_free_bytes", "Free bytes in the GC heap.", gc.free_bytes, pid)
      gauge(io, "braxy_gc_allocated_bytes_total", "Bytes allocated since boot.", gc.total_bytes, pid)
      if rss = rss_bytes
        gauge(io, "braxy_process_rss_bytes", "Resident set size.", rss, pid)
      end
    end
  end

  private def gauge(io : IO, name : String, help : String, value, pid : Int64) : Nil
    io << "# HELP " << name << ' ' << help << '\n'
    io << "# TYPE " << name << " gauge\n"
    io << name << "{pid=\"" << pid << "\"} " << value << '\n'
  end

  private def rss_bytes : Int64?
    File.each_line("/proc/self/status") do |line|
      if line.starts_with?("VmRSS:")
        return line.split[1].to_i64 * 1024
      end
    end
    nil
  rescue
    nil
  end
end
