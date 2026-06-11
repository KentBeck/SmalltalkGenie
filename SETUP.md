# Setting up and working with Genie

A complete walk-through: load the server into a Pharo image, connect an MCP
client, install the agent's working agreement (`CLAUDE.md` + skills), and run the
day-to-day loop.

Genie has **two halves** that meet over HTTP on `localhost:8087`:

- the **Pharo image** runs `GenieServer` — the MCP server (the genie in the lamp);
- an **MCP client** (e.g. Claude Code) connects to it, together with the
  `CLAUDE.md` + skills that tell the agent how to drive the image safely.

You set up each half once. Then you make wishes.

---

## 1 — Load and start the server (Pharo side)

**Prerequisites.** A Pharo image + VM. Pharo 13 is recommended (the code also
runs on 9/12). [PharoLauncher](https://pharo.org/download) is the easiest way to
get one.

**Load Genie via Metacello:**

```smalltalk
Metacello new
    baseline: 'Genie';
    repository: 'github://KentBeck/SmalltalkGenie:main/src';
    load.
```

Pin a specific commit for reproducibility by replacing `:main` with a SHA, e.g.
`github://KentBeck/SmalltalkGenie:c2db995/src`. The baseline pulls its only
dependencies — **Teapot** (HTTP) and **NeoJSON**.

> On **Pharo ≤ 12**, set the author once so the first headless compile doesn't
> block on the modal "author initials" dialog: `Author fullName: 'YourName'`.
> **Pharo 13 removed the `Author` class** (and that dialog), so the step doesn't
> apply there — evaluating `Author fullName: …` on 13 raises an *undeclared
> variable* error. Just skip it.

**Start it (first time only):**

```smalltalk
GenieServer current.   "serves MCP at http://localhost:8087/mcp"
```

Loading Genie already **registered it for image startup** (its class-side
`initialize` runs on load), so you only need `current` the very first time —
after you save, every future launch of the image starts the server
automatically. If it ever isn't auto-starting, re-arm it with
`GenieServer initialize`.

**Save the image** so the loaded code and the running server persist (menu →
*Save*, or `Smalltalk snapshot: true andQuit: false`). From then on the lamp is
self-contained: open the image, the genie is awake.

**Lifecycle commands:**

```smalltalk
GenieServer current.          "start (idempotent — returns the running server)"
GenieServer current stop.     "stop"
GenieServer restart.          "stop + start (use after changing transport/port code)"
```

---

## 2 — Connect the MCP client (Claude Code side)

Register the running server:

```
claude mcp add --transport http genie http://localhost:8087/mcp
```

Restart Claude Code. The genie's tools appear under the **`mcp__genie__*`**
prefix — `eval`, `define_class`, `define_method`, `run_test`, `save_image`, the
`search_*` reads, and the rest. Confirm with `/mcp` (genie → *connected*).

> The name you give it (`genie` above) becomes the tool prefix `mcp__genie__*`.
> Keep it `genie`: the `CLAUDE.md` and skills refer to the tools by that prefix,
> so a different name means those references won't line up.

**Skip the per-call permission prompts** by allowing the whole server in
`.claude/settings.local.json`:

```json
{ "permissions": { "allow": ["mcp__genie__*"] } }
```

---

## 3 — Install the working agreement (`CLAUDE.md` + skills)

Genie hands the agent a **live image with no source files**. The `CLAUDE.md` and
skills encode the discipline that makes that safe: the image is the single source
of truth, change code *only* through the tools, never edit files, run tests
constantly, save only through the test-gated `save_image`, stay headless. Without
them an agent will reach for files that aren't there and drift from the image.

The repo ships three pieces:

- **`CLAUDE.md`** — the working agreement (orient → change-via-tools → test →
  gated save).
- **`.claude/skills/pharo-tdd/SKILL.md`** — the red → green → refactor loop.
- **`.claude/skills/pharo-refactor/SKILL.md`** — safe, behavior-preserving
  restructuring.

Where they go depends on what you're doing:

### A) Working on Genie itself

Clone this repo and run Claude Code in it. It picks up the root `CLAUDE.md` and
`.claude/skills/` automatically — nothing to copy.

### B) Using Genie to drive your *own* Pharo project

Copy the files into that project:

```
your-project/
  CLAUDE.md                          ← copy of Genie's, edited (see below)
  .claude/
    settings.local.json              ← { "permissions": { "allow": ["mcp__genie__*"] } }
    skills/
      pharo-tdd/SKILL.md
      pharo-refactor/SKILL.md
```

Then edit the copied `CLAUDE.md`:

- change the gated-save example `save_image {test_package: 'Genie'}` to **your**
  package name;
- replace the "Working on Genie" framing with your project's;
- keep everything else — the tool-only / TDD / headless rules apply to any image.

The two skills are project-agnostic; copy them as-is.

---

## 4 — The daily loop

Once both halves are up, every change follows the same loop (this is exactly what
`CLAUDE.md` enforces):

1. **Orient.** `list_packages` / `list_classes` / `list_methods`,
   `get_class_source` / `get_method_source`, `search_*`. These reads **are** your
   filesystem — never guess a class or selector exists, look it up.
2. **Change.** `define_class`, `define_method` (source is auto-formatted on
   compile), `rename_class`, `remove_method`. Read every change back to confirm
   it took.
3. **Test.** `run_test` by `class_name`, then by `package_name`. Errors come back
   as full Smalltalk stack traces — read them; they point at the fix.
4. **Persist.** `save_image` gated on tests:
   `save_image {test_package: 'YourPackage'}` saves only if green; a red suite
   leaves the on-disk image untouched.

The **image is the source of truth**. `export_package` writes a Tonel snapshot
under `src/` when you want a git/disk backup (that's how this repo is produced) —
it is not part of the loop.

---

That's the whole picture: load + start the genie, point your client at it, drop
in the working files, and run the loop. For the tool list and design notes, see
[README.md](README.md).
