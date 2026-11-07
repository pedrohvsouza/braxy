-- wrk script: every request picks the next of N logged-in users, so caches
-- keyed by user see realistic hit rates.
--   wrk -s wrk-users.lua <url> -- <cookies.tsv> <path template> [GET|POST] [body]
-- The path template may contain {room}; POST sends a small chat message
-- unless another JSON body is given.
local users = {}
local path_tmpl, method, body

local function load(file)
  for line in io.lines(file) do
    local cookie, csrf, room = line:match("([^\t]+)\t([^\t]*)\t([^\t]+)")
    if cookie then users[#users + 1] = { cookie = cookie, csrf = csrf, room = room } end
  end
end

function init(args)
  load(args[1])
  path_tmpl = args[2] or "/api/session"
  method = args[3] or "GET"
  body = args[4] or '{"body":"carga"}'
  -- Spread threads across the user list.
  idx = math.random(#users)
end

function request()
  idx = idx % #users + 1
  local u = users[idx]
  local path = path_tmpl:gsub("{room}", u.room)
  local headers = { ["Cookie"] = u.cookie, ["X-CSRF-Token"] = u.csrf, ["Origin"] = "http://bench.local" }
  if method == "POST" then
    headers["Content-Type"] = "application/json"
    return wrk.format("POST", path, headers, body)
  end
  return wrk.format("GET", path, headers)
end

local errors = 0
function response(status)
  if status >= 400 then errors = errors + 1 end
end

function done(summary, latency, requests)
  local s = summary
  io.write(string.format(
    "RESULT rps=%.0f p50=%.2f p90=%.2f p95=%.2f p99=%.2f max=%.2f total=%d errors=%d sockerr=%d timeouts=%d\n",
    s.requests / (s.duration / 1e6),
    latency:percentile(50) / 1000, latency:percentile(90) / 1000, latency:percentile(95) / 1000, latency:percentile(99) / 1000,
    latency.max / 1000, s.requests,
    s.errors.status, s.errors.connect + s.errors.read + s.errors.write, s.errors.timeout))
end
