require "../spec_helper"

describe "metrics endpoint" do
  it "is hidden without METRICS_TOKEN and needs the bearer token" do
    with_app do |app|
      ENV.delete("METRICS_TOKEN")
      app.get("/metrics").status_code.should eq(404)

      ENV["METRICS_TOKEN"] = "s3cret"
      begin
        Observability.enable_request_metrics!
        app.get("/api/session")
        app.get("/metrics").status_code.should eq(401)
        app.get("/metrics", headers: HTTP::Headers{"Authorization" => "Bearer nope"}).status_code.should eq(401)
        res = app.get("/metrics", headers: HTTP::Headers{"Authorization" => "Bearer s3cret"})
        res.status_code.should eq(200)
        res.body.should contain(%(saci_route_requests_total{route="Api::SessionsController#show"}))
        res.body.should contain(%(saci_requests_by_status_total{status="401"} 2))
        res.body.should contain("braxy_cable_connections{pid=")
        res.body.should contain("braxy_gc_heap_bytes{pid=")
      ensure
        ENV.delete("METRICS_TOKEN")
      end
    end
  end
end

describe "JSON log lines" do
  it "keeps JSON request lines as they are and adds exception details" do
    io = IO::Memory.new
    request_line = %({"level":"INFO","path":"/api/session"})
    Observability.format_json(::Log::Entry.new("saci", :info, request_line, ::Log::Metadata.empty, nil), io)
    io.to_s.should eq(request_line)

    io = IO::Memory.new
    ex = begin
      raise "boom"
    rescue e
      e
    end
    Observability.format_json(::Log::Entry.new("saci", :error, "unhandled", ::Log::Metadata.empty, ex), io)
    line = JSON.parse(io.to_s)
    line["level"].as_s.should eq("ERROR")
    line["exception_message"].as_s.should eq("boom")
    line["backtrace"].as_a.should_not be_empty
  end
end
