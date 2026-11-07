// Content-Security-Policy of the SPA document, injected as a <meta> tag by
// the production build (the dev server needs inline scripts for HMR).
// `frame-ancestors` is ignored in <meta>: whatever serves index.html must
// also send `X-Frame-Options: DENY` (or `frame-ancestors 'none'`).
//
// - style-src 'unsafe-inline': Font Awesome injects its stylesheet at runtime.
// - img-src blob: data:: image previews before upload, small inlined assets.
// - connect-src 'self': the API and the same-origin WebSocket (/cable).
export const documentCsp = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' blob: data:",
  "font-src 'self' data:",
  "connect-src 'self'",
  "media-src 'self' blob:",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
].join("; ");
