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

> ⚠️ **Security: `eval` runs arbitrary code.** A client that can reach the server has
> the full power of the Pharo process. By default the server binds to **loopback only**
> (no network access) and checks the `Origin` header; optional **token auth** and
> **dangerous-tool gating** harden it further. Run it only on a machine and image you
> trust. See **[Security](#security)**.

## Install

```smalltalk
Metacello new
    baseline: 'Genie';
    repository: 'github://KentBeck/SmalltalkGenie:main/src';
    load.
```

Tested with Pharo 12+ (the code also runs on Pharo 9). The baseline pulls in its
only non-base dependencies, **Teapot** (HTTP) and **NeoJSON**.

On **Pharo ≤ 12**, set the author once on a freshly loaded image so headless
compiles don't block on the modal "author initials" dialog:

```smalltalk
Author fullName: 'YourName'.
```

**Pharo 13 removed the `Author` class** (and that dialog), so this step does not
apply there — evaluating `Author fullName: …` on Pharo 13 raises an *undeclared
variable* error. On 13 there is nothing to set; just skip it.

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

Genie exists to let a client program a live image, so **a client that can reach the
server has the full power of the Pharo process.** `eval` compiles and runs arbitrary
Smalltalk (`handleEval:` is literally `compiler evaluate: code`): read, write, or
delete any file the user can, open sockets, spawn processes, modify or wipe the
image. The "go only through the tools" rule in `CLAUDE.md` is guidance to a
cooperating agent, **not a sandbox**. So the real job is containing *who can reach
the server*.

**Safe by default:**

- **Loopback-only binding.** The listening socket binds to `127.0.0.1`, so the
  server is not reachable over the network — only from processes on the same
  machine. (Takes effect when the image next starts.)
- **Origin check.** Requests whose HTTP `Origin` header isn't local are rejected
  (403), blocking browser DNS-rebinding. This is defense-in-depth, *not* access
  control — non-browser clients (`curl`, scripts, MCP clients) send no `Origin` and
  aren't gated by it; the token below is the real gate.

**Opt-in hardening** — settings, applied via `apply_settings` or
`GenieServer current settings at: #key put: value` (save the image to persist):

- **`authToken`** — set a non-empty token to require `Authorization: Bearer <token>`
  on every request (401 otherwise); off by default. Use it to stop *other local
  processes* from driving the image. **Enable it in this order so you don't lock
  yourself out** (it takes effect on the very next request): add the header to your
  client and restart the client *first* — it's ignored while no token is set —
  `claude mcp add --transport http genie http://localhost:8087/mcp --header
  "Authorization: Bearer <token>"`, *then* set `authToken`, *then* save the image.
  (`get_settings` redacts the token.)
- **`allowDangerousTools`** — `true` by default; set `false` to refuse the most
  dangerous tools (`eval`, `save_image`, `remove_class`, `remove_method`) for a
  read-mostly deployment. Note that this also blocks `save_image` itself, so persist
  the change by saving the image directly (Pharo menu / `Smalltalk snapshot:`) rather
  than through the tool.
- **`bindingInterface`** — `'127.0.0.1'` by default; set `''` to bind all interfaces
  (only if you knowingly want remote access), or another address. Applies on restart.

**Still your responsibility:**

- Run Genie only on a machine you trust, in an image you can afford to lose; don't
  load it into an image holding secrets, credentials, or production data.
- Never expose the port to an untrusted network or the public internet.
- Only connect clients/agents you trust, and review what they run.
- For untrusted or experimental use, run the whole image inside a throwaway VM or
  container.

## Design notes

- **Direct, no bridge.** The image is the MCP endpoint. Plain `application/json`
  request/response over a single `POST /mcp` (no SSE required); protocol version
  `2025-11-25`. Binds to loopback by default and validates the `Origin` header;
  optional token auth and dangerous-tool gating — see [Security](#security).
- **Headless, code-only.** No Morphic / Spec / Roassal, no screen inspection.
- **Self-contained.** Depends only on Teapot, NeoJSON, and base Pharo.

## License

MIT — see [LICENSE](LICENSE).
