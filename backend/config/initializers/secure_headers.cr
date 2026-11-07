# Security headers on every backend response (JSON API, /api/files, the
# cable handshake). None of them is a document, so the CSP denies
# everything. The SPA document gets its own policy at build time
# (frontend/csp.ts), wherever its static files are served from.
Saci::SecureHeaders.configure do |headers|
  headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
  headers["X-Frame-Options"] = "DENY"
  headers["Cross-Origin-Resource-Policy"] = "same-origin"
end

# The app uses none of these; audio recording (backlog E) would add microphone=(self).
Saci::SecureHeaders.permissions_policy(
  camera: [] of String, microphone: [] of String, geolocation: [] of String,
  payment: [] of String, usb: [] of String, "interest-cohort": [] of String)

# Production runs behind TLS only (see Saci::Session.secure in session.cr).
Saci::SecureHeaders.hsts = true if Saci.env == "production"
