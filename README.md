# SmalltalkGenie

Program a live **Pharo Smalltalk** image from an AI agent — over the **Model
Context Protocol (MCP)**, with no bridge process in between.

SmalltalkGenie is an MCP server that lives *inside* a Pharo image and speaks MCP
directly over HTTP. Point an MCP client (e.g. Claude Code) at it and the agent
can define classes and methods, run tests, search the system, rename classes,
and save the image — all by remote control.

The metaphor: the image is the **lamp**, `GenieServer` is the **genie** inside
it, and each MCP tool call is a **wish** (`Wish` is the class that carries an
incoming call's arguments). You never enter the lamp; you make wishes and the
genie carries them out in its own world.

> ⚠️ **Security: a running Genie server is an unauthenticated remote-code-execution
> endpoint.** The `eval` tool runs arbitrary Smalltalk — i.e. arbitrary code — with
> the full privileges of the process, and there is no authentication. Run it only on
> a machine and image you trust, and never expose the port to an untrusted network.
> Read **[Security](#security)** before you run it.

## Install

```smalltalk
Metacello new
    baseline: 'Genie';
    repository: 'github://KentBeck/SmalltalkGenie:main/src';
    load.
```

Tested with Pharo 12+ (the code also runs on Pharo 9). The baseline pulls in its
only non-base dependencies, **Teapot** (HTTP) and **NeoJSON**.

On a freshly loaded image, set the author once so headless compiles don't block
on the "author initials" dialog:

```smalltalk
Author fullName: 'YourName'.
```

## Run

```smalltalk
GenieServer current.   "starts the server on http://localhost:8087/mcp"
```

Then register it with your MCP client. For Claude Code:

```
claude mcp add --transport http genie http://localhost:8087/mcp
```

For a full walk-through — auto-start, lifecycle commands, connecting the client,
and installing the agent's working files (`CLAUDE.md` + skills) so it drives the
image safely — see **[SETUP.md](SETUP.md)**.

## Tools

The genie grants 26 wishes over MCP:

- **Code:** `eval`, `define_class`, `define_method`, `rename_class`,
  `remove_class`, `remove_method`
- **Tests:** `run_test` (structured pass/fail/error counts)
- **Read / search:** `list_packages`, `list_classes`, `list_methods`,
  `list_extended_classes`, `get_class_source`, `get_method_source`,
  `get_class_comment`, `search_classes_like`, `search_methods_like`,
  `search_implementors`, `search_references`, `search_references_to_class`,
  `search_traits_like`
- **Packages / settings:** `export_package`, `import_package`,
  `install_project`, `get_settings`, `apply_settings`
- **Persistence:** `save_image` — snapshots the image, optionally **gated on
  tests**: pass `test_package` / `test_class` and it saves *only* if they pass.

## Security

**Treat a running Genie server as an open, unauthenticated remote shell on the
host.** That is what it is, by design — the whole point is to let a client program
a live image — so the responsibility for containing it is yours.

- **`eval` is arbitrary code execution.** It compiles and runs any Smalltalk you
  send (`handleEval:` is literally `compiler evaluate: code`). Through it a caller
  can read, write, or delete any file the user can, open network connections, spawn
  OS processes, exfiltrate data, and modify or wipe the image. The narrower tools
  (`define_method`, `remove_class`, `save_image`, …) still let a caller rewrite the
  running system.
- **The "go only through the tools" rule in `CLAUDE.md` is not a sandbox.** It is
  guidance to a cooperating agent. A confused, jailbroken, or prompt-injected agent —
  or anything else that reaches the port — can call `eval` and do anything. There is
  no allow-list and no capability restriction.
- **No authentication.** Any client that can open a TCP connection to the port and
  send a JSON body is fully trusted. There is no token, password, or handshake.
- **The `Origin` check is narrow.** The server rejects (403) requests whose HTTP
  `Origin` header isn't `localhost`/`127.0.0.1`, which blocks malicious *web pages*
  (cross-origin / DNS-rebinding via a browser). But a non-browser client — `curl`, a
  script, another MCP client — sends no `Origin` header, so the check is skipped and
  the request is served.
- **Not bound to loopback.** The listening socket sets no binding interface, so the
  port may be reachable from your network, not just your machine.

Practical rules:

- Run Genie only on a machine you trust, in an image you can afford to lose.
- Don't load it into an image holding secrets, credentials, or production data.
- Keep the port (`8087`) off untrusted networks — firewall it or bind it to
  loopback. **Never expose it to the public internet.**
- Only connect clients/agents you trust, and review what they run.
- For untrusted or experimental use, run the whole image inside a throwaway VM or
  container.

## Design notes

- **Direct, no bridge.** The image is the MCP endpoint. Plain `application/json`
  request/response over a single `POST /mcp` (no SSE required); protocol version
  `2025-11-25`. Validates the `Origin` header to block browser cross-origin
  requests — but there is **no authentication** and the socket is not restricted to
  loopback; see [Security](#security).
- **Headless, code-only.** No Morphic / Spec / Roassal, no screen inspection.
- **Self-contained.** Depends only on Teapot, NeoJSON, and base Pharo.

## License

MIT — see [LICENSE](LICENSE).
