# Working on Genie

Genie is a Pharo MCP server: it lives inside a running **Pharo image** and
exposes that image to an AI agent over MCP. When you work on Genie itself, the
code lives in the **live image**, reached through the **`genie`** MCP server
(HTTP at `localhost:8087`). The image is the single source of truth.

**Operate entirely from the live image via the `genie` MCP tools. Do not
create, expect, or rely on a file mirror of the code.** The `src/` Tonel tree is
an export for git and loading, not something to edit by hand — when you need to
see code, fetch it live with the read tools (see "How to orient" below).

## The `genie` server — call its tools directly
`genie` is native MCP over HTTP on port **8087**, implemented by the
`GenieServer` class (package `Genie`). Call its tools directly — no curl, no
bridge: `mcp__genie__eval`, `…__define_class`, `…__define_method`,
`…__rename_class`, `…__remove_class`, `…__remove_method`, `…__run_test`
(structured pass/fail), `…__save_image` (test-gated), and reads/searches
`…__list_classes`, `…__get_method_source`, `…__search_*`, etc.

**Genie is fully headless — no UI, ever.** The server is code-only. Do NOT add
UI-inspection tools (`read_screen`) or any Morphic / Spec / Roassal code. If a
task seems to need the screen, it's the wrong approach here.

## How to change code — tools ONLY
- New class         → `define_class` (params: `name`, `superclass`, `fields`, `package`)
- New / edit method → `define_method` (params: `class`, `source`, `protocol`)
- Rename a class    → `rename_class` (updates every reference via the refactoring engine)
- Anything else     → `eval` with an explicit `compile:classified:` or a
  `ShiftClassInstaller` builder.
- **Never** use the Edit/Write tools to change image code. If you feel the urge
  to edit a `.class.st` file, stop — you are about to drift from the image.
- After every mutation, **confirm it took**: read it back with
  `get_method_source` / `get_class_source`. Never assume success.
- Use the modern class API (`ShiftClassInstaller`), not the deprecated
  `subclass:instanceVariableNames:classVariableNames:package:`.
- On a freshly-loaded image, set the author ONCE up front — otherwise the
  first compile blocks forever on a modal "author initials" dialog that a
  headless `eval` can't answer: `Author fullName: 'YourName'`.

## How to orient (no files = the read tools ARE the filesystem)
Treat these as `ls` / `cat` / `grep` and use them BEFORE changing anything.
Never guess that a class or selector exists — look it up.
- `list_packages`, `list_classes`, `list_methods`        → directory listing
- `get_class_source`, `get_method_source`                → cat
- `search_methods_like`, `search_implementors`,
  `search_references`, `search_references_to_class`      → grep / call graph

## Tests: run them constantly
- After each change, run `run_test` (by `class_name` or `package_name`) before
  declaring anything done.
- Red → green → refactor. When fixing a bug, write or adjust the failing test
  FIRST, then make it pass.

## Debugging: the stack traces are the payload, not noise
- Genie returns full Smalltalk stack traces on error — they include the failing
  block's source, the receiver, and its variables. Read them closely.
- Reproduce with a minimal `eval` before touching code. Let the trace point you
  at the method, fix the smallest thing, re-run the test.

## Refactoring
- Establish a green baseline first. If there are no tests for the code you're
  about to change, write characterization tests via `define_method` first.
- Before any rename/move: use `search_references` / `search_implementors` /
  `search_references_to_class` to find every caller. For class renames, prefer
  `rename_class` — it updates every code reference AND symbol literal (`#Foo`)
  via the refactoring engine, but NOT string literals (`'Foo'`). Two
  consequences: fix stringly-typed names by hand; and a test that renames a
  class must refer to the old name as `'Foo' asSymbol`, never `#Foo` — else the
  refactor rewrites the test's own assertion and it self-mangles (passes once,
  fails after).
- One small structured change at a time; run tests between each step.

## Persistence — image changes are in-memory until saved
- The image is the source of truth and the only place code lives; nothing else
  persists the live state.
- After a GREEN unit of work, persist with the **`save_image` tool gated on
  tests**: pass `test_package` (or `test_class`) so it runs them and saves the
  image ONLY if all pass — `mcp__genie__save_image {test_package: 'Genie'}`.
- A red suite is refused (`saved: false`, image untouched). Never save ungated
  right after changes — let the gate protect the on-disk image.
- `export_package` writes a Tonel snapshot to `src/` (that's how this repo is
  produced); it is NOT the working loop — the live image is.
