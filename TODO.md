# Genie — plan

Planned work, roughly in priority order. Each item is done TDD-first (write/adjust
a `GenieProtocolTest` or `GenieActionTest` before the change) and persisted with a
test-gated `save_image`, same as the rest of the project.

## Improve security

Today a running Genie server is an **unauthenticated remote-code-execution
endpoint** — `eval` runs arbitrary Smalltalk with the full privileges of the OS
process, and nothing authenticates the caller (see the **Security** section in
[README.md](README.md)). Harden it:

- [ ] **Bind to loopback by default.** The socket currently sets no binding
      interface, so the port can be reachable from the network. Bind to
      `127.0.0.1` by default (via `teapotConfig`), and expose the bind interface
      as a setting for users who knowingly want remote access. This also makes the
      README's "localhost" framing true.
- [ ] **Add authentication.** Check a bearer token (or similar shared secret) in
      `handleMcpHttp:` so a local process can't drive the image just by opening the
      port. Generate a token at startup and surface it, so it's secure by default
      rather than opt-in.
- [ ] **Stop leaning on the `Origin` check as access control.** It only blocks
      browser requests that send an `Origin` header; `curl`/scripts/other MCP
      clients send none and pass straight through. Keep it as DNS-rebinding
      defense-in-depth, but the auth token above is the real gate.
- [ ] **Consider gating the most dangerous tools** (`eval`, `save_image`,
      `remove_class`, `remove_method`) behind an explicit "allow dangerous tools"
      setting, off unless enabled, for read-mostly deployments.
- [ ] **Tests:** a request from a non-local `Origin` is rejected (already implied
      by current behavior — add coverage); an unauthenticated request is rejected
      when auth is enabled; a request with the right token is served.
