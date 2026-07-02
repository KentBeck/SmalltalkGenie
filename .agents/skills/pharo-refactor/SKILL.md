---
name: pharo-refactor
description: Refactor messy Pharo code safely through the genie MCP tools, working from the live image (no files). Use for renames, method extraction, moving behavior, or general cleanup of existing code.
---

# Pharo refactor loop (live image, via the genie MCP tools)

Refactoring = change structure without changing behavior. The proof that
behavior is unchanged is a green test suite before AND after. All reads and
writes go through the `genie` MCP tools; there are no files. Change code only
via `define_method` / `define_class` / `rename_class` / `remove_method` /
`eval`, and read every change back to confirm it.

## Loop

1. **Green baseline.** Run `run_test` on the relevant class/package. If the code
   you're about to touch has NO test coverage, STOP and write characterization
   tests first (use the `pharo-tdd` skill) — you cannot refactor safely without
   a safety net.

2. **Map impact.** Before any rename/move/extract, find every caller and
   implementor:
   - `search_references` / `search_references_to_class` — who uses it
   - `search_implementors` — who else defines this selector
   - `search_methods_like` — similar code that may need the same change
   Make a list. Every item gets updated in this same session.

3. **One small change.** Make a single structured edit. Read changed methods
   back with `get_method_source`.

4. **Re-test.** Run `run_test` (class, then package). Green → keep going.
   Red → the trace shows what broke; fix or revert this one step before moving
   on. Never batch unverified edits.

5. **Repeat** steps 3–4 in small increments until the cleanup is complete.

6. **Done.** Persist with `save_image` gated on the test package. Summarize the
   before/after shape.

## Common moves
- **Rename class:** use `rename_class` — it updates every code reference and
  symbol literal via the refactoring engine. It does NOT touch string literals,
  so fix stringly-typed names by hand; and in a test that renames a class, refer
  to the old name as `'Foo' asSymbol`, never `#Foo`, or the test rewrites its
  own assertion and self-mangles.
- **Remove method:** `remove_method`. **Remove class:** `remove_class`.
- **Rename method:** install the new selector via `define_method`, repoint every
  sender (from `search_references`), then `remove_method` the old one.
- **Extract method:** add the new helper, call it from the original, re-test.

## Rules
- Behavior-preserving only. If a test changes meaning, that's a feature change
  — do it under `pharo-tdd`, not here.
- Small steps, tests between each. A long unverified refactor is a bug factory.
- Modern class API only (`ShiftClassInstaller` / `define_class`).
