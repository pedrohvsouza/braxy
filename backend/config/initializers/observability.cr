# Logs, errors and metrics for production (see docs/deploy.md).
#
#   SACI_LOG_FORMAT=json  one JSON object per line, app and request logs alike
#   LOG_LEVEL=info        overrides the environment's level (production: warn;
#                         info adds one line per request)
#   METRICS_TOKEN=...     enables GET /metrics (Prometheus text), Bearer auth
module Observability
  LEVELS = {
    "debug" => :debug, "info" => :info, "notice" => :notice,
    "warn" => :warn, "error" => :error, "fatal" => :fatal,
  }

  # Saci's JSON formatter, except that a message which already is a JSON
  # object (Saci's request lines under SACI_LOG_FORMAT=json) is written as
  # is instead of being escaped into a string, and exceptions keep their
  # backtrace.
  def self.format_json(entry : ::Log::Entry, io : IO) : Nil
    message = entry.message
    if entry.exception.nil? && message.starts_with?('{') && message.ends_with?('}')
      io << message
      return
    end
    JSON.build(io) do |json|
      json.object do
        json.field "time", entry.timestamp.to_rfc3339
        json.field "level", entry.severity.label
        json.field "source", entry.source
        json.field "pid", Process.pid
        json.field "message", message
        entry.data.each { |key, value| json.field key.to_s, value.to_s }
        if ex = entry.exception
          json.field "exception", ex.class.name
          json.field "exception_message", ex.message
          json.field "backtrace", (ex.backtrace? || [] of String).first(20)
        end
      end
    end
  end

  @@request_metrics = false

  def self.metrics_token : String?
    ENV["METRICS_TOKEN"]?.presence
  end

  # Feeds Saci::Metrics from the router's `process_action.saci` event. The
  # event carries no status, but `Saci::Current.request` is still set when
  # it is published.
  def self.enable_request_metrics! : Nil
    return if @@request_metrics
    @@request_metrics = true
    Saci::Notifications.subscribe("process_action.saci") do |event|
      status = Saci::Current.request.try(&.response.status_code) || 0
      status = 500 if event["exception"]
      Saci::Metrics.track_request("#{event["controller"]}##{event["action"]}", status, event.duration)
    end
  end
end

if level = ENV["LOG_LEVEL"]?.try { |name| Observability::LEVELS[name.downcase]? }
  Saci.log_level = level
end

if Saci.log_json?
  severity = Saci.logger.level
  ::Log.setup(severity, ::Log::IOBackend.new(STDOUT, formatter: ::Log::Formatter.new { |entry, io| Observability.format_json(entry, io) }, dispatcher: :sync))
  Saci.logger.level = severity
end

# Unhandled controller errors: Saci renders a 500 but does not log it.
Saci.error_reporter = ->(ex : Exception) do
  Saci.logger.error(exception: ex) { "unhandled #{ex.class}: #{ex.message}" }
end

Observability.enable_request_metrics! if Observability.metrics_token && Saci.env != "test"
