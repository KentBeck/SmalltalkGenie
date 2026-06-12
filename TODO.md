# Genie — plan

Planned work, roughly in priority order. Each item is done TDD-first (write/adjust
a `GenieProtocolTest` or `GenieActionTest` before the change) and persisted with a
test-gated `save_image`, same as the rest of the project.

## Improve security — ✅ done

Shipped: the server is no longer an open network endpoint, and there are opt-in
gates for tighter lockdown. See the **Security** section in [README.md](README.md).

- [x] **Bind to loopback by default.** `start` now binds the listening socket to
      `127.0.0.1` (via the `bindingInterface` setting, default `'127.0.0.1'`; `''`
      means all interfaces). Verified both `127.0.0.1` and `localhost` reach a
      loopback-bound server, so it doesn't lock out local clients. Applies on the
      next image start.
- [x] **Add authentication.** `headersAuthorized:` checks an `Authorization: Bearer
      <token>` header against the `authToken` setting in `handleMcpHttp:` (401 on
      mismatch). **Opt-in** (default empty = no auth) rather than required-by-default:
      required-by-default would lock out every already-connected client until each is
      reconfigured with the token. Loopback binding already removes the network
      threat; the token closes off *other local processes*.
- [x] **Stop leaning on the `Origin` check as access control.** Extracted to
      `originAllowed:`, kept as DNS-rebinding defense-in-depth, and documented as
      not-a-gate (non-browser clients send no `Origin`). The token is the real gate.
- [x] **Gate the most dangerous tools.** `allowDangerousTools` setting (default
      `true`); set `false` to refuse `eval`, `save_image`, `remove_class`,
      `remove_method` (`mcpToolsCall:id:` returns a JSON-RPC error). `get_settings`
      now redacts `authToken` so it can't be read back.
- [x] **Tests.** 5 new `GenieProtocolTest` cases (origin allow/reject, auth opt-in
      enforcement, loopback default, dangerous-tool gate, token redaction). Suite
      green at 27/27.
