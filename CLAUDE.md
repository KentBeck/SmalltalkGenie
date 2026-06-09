# Working on this codebase

The code lives in a running **Pharo image**, reachable only through MCP
servers — prefer the native **`arlo-smalltalk`** server (HTTP at
`localhost:8087`); the `smalltalk-interop` bridge (`localhost:8086`) is a
fallback. **There are no application source files on disk.** The image is the
single source of truth.

**Operate entirely from the live image via the MCP read endpoints. Do not
create, expect, or rely on a file mirror of the code.** There are no
`.st` / Tonel source files to read or edit — when you need to see code,
fetch it live (see "How to orient" below).

## Two servers — prefer the native `arlo-smalltalk` tools
The image runs two MCP-reachable servers (save the image to keep both alive):
- **`arlo-smalltalk`** — native MCP over HTTP on port **8087**, implemented by
  the `GenieServer` class (package `Genie`) in the image. Call its tools
  DIRECTLY (no curl, no Python bridge): `mcp__arlo-smalltalk__eval`,
  `…__define_class`, `…__define_method`, `…__rename_class`, `…__remove_class`,
  `…__remove_method`, `…__run_test` (structured pass/fail), `…__save_image`
  (test-gated), and reads/searches `…__list_classes`, `…__get_method_source`,
  `…__search_*`, etc. **Prefer these.**
- **`smalltalk-interop`** — the original `uvx` Python bridge to `SisServer`
  (port 8086). Still works; use only if `arlo-smalltalk` is unavailable.
The HTTP endpoint names below (`/define-class`, …) map 1:1 to the native tool
names (`define_class`, …) — same params, same `{success,result}` shape.

**Arlo is fully headless — no UI, ever.** The server is code-only. Do NOT add
UI-inspection tools (`read_screen`) or any Morphic / Spec / Roassal code. If a
task seems to need the screen, it's the wrong approach here.

## How to change code — endpoints ONLY
- New class        → `POST /define-class` (params: `name`, `superclass`, `fields`, `package`)
- New / edit method → `POST /define-method` (params: `class`, `source`, `protocol`)
- Anything else     → `eval` with an explicit `compile:classified:` or a
  `ShiftClassInstaller` builder.
- **Never** use the Edit/Write tools to change application code. If you feel
  the urge to edit a file, stop — you are about to drift from the image.
- After every mutation, **confirm it took**: read it back with
  `get-method-source` / `get-class-source`. Never assume success.
- Use the modern class API (`ShiftClassInstaller`), not the deprecated
  `subclass:instanceVariableNames:classVariableNames:package:`.
- On a freshly-loaded image, set the author ONCE up front — otherwise the
  first compile blocks forever on a modal "author initials" dialog that a
  headless `eval` can't answer: `Author fullName: 'KentBeck'`.

## How to orient (no files = the read endpoints ARE the filesystem)
Treat these as `ls` / `cat` / `grep` and use them BEFORE changing anything.
Never guess that a class or selector exists — look it up.
- `list-packages`, `list-classes`, `list-methods`        → directory listing
- `get-class-source`, `get-method-source`                → cat
- `search-methods-like`, `search-implementors`,
  `search-references`, `search-references-to-class`      → grep / call graph

## Tests: run them constantly
- After each method change, run `run-class-test` (fast), then
  `run-package-test` before declaring anything done.
- Red → green → refactor. When fixing a bug, write or adjust the failing
  test FIRST, then make it pass.

## Debugging: the stack traces are the payload, not noise
- This server returns full Smalltalk stack traces on error — they include the
  failing block's source, the receiver, and its variables. Read them closely.
- Reproduce with a minimal `eval` before touching code. Let the trace point
  you at the method, fix the smallest thing, re-run the test.

## Refactoring messy code
- Establish a green baseline first. If there are no tests for the code you're
  about to change, write characterization tests via `define-method` first.
- Before any rename/move: use `search-references` / `search-implementors` /
  `search-references-to-class` to find every caller, and update them in the
  same session. For class renames, prefer the `rename_class` tool — it updates
  every code reference AND symbol literal (`#Foo`) via the refactoring engine,
  but NOT string literals (`'Foo'`). Two consequences: fix stringly-typed names
  by hand; and a test that renames a class must refer to the old name as
  `'Foo' asSymbol`, never `#Foo` — else the refactor rewrites the test's own
  assertion and it self-mangles (passes once, fails after).
- One small structured change at a time; run tests between each step.

## Persistence — image changes are in-memory until saved
- The image is the source of truth and the only place code lives; nothing else
  persists the live state.
- After a GREEN unit of work, persist with the **`save_image` tool gated on
  tests**: pass `test_package` (or `test_class`) so it runs them and saves the
  image ONLY if all pass —
  `mcp__arlo-smalltalk__save_image {test_package: 'Genie'}`. This is the
  working loop's save step; don't ask the user to save by hand.
- A red suite is refused (`saved: false`, image untouched). Never save ungated
  right after changes — let the gate protect the on-disk image.
- `export-package` exists for a disk/git backup, but it is NOT part of the
  working loop and there is no on-disk mirror to keep in sync.
