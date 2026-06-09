---
name: pharo-refactor
description: Refactor messy Pharo code safely through the smalltalk-interop MCP endpoints, working from the live image (no files). Use for renames, method extraction, moving behavior, or general cleanup of existing code.
---

# Pharo refactor loop (live image, via MCP)

Refactoring = change structure without changing behavior. The proof that
behavior is unchanged is a green test suite before AND after. All reads and
writes go through the `smalltalk-interop` MCP / `localhost:8086`; there are no
files. Change code only via `define-method` / `define-class` / `eval`, and
read every change back to confirm it.

## Loop

1. **Green baseline.** Run `run-package-test` (and the relevant
   `run-class-test`). If the code you're about to touch has NO test coverage,
   STOP and write characterization tests first (use the `pharo-tdd` skill) —
   you cannot refactor safely without a safety net.

2. **Map impact.** Before any rename/move/extract, find every caller and
   implementor:
   - `search-references` / `search-references-to-class` — who uses it
   - `search-implementors` — who else defines this selector
   - `search-methods-like` — similar code that may need the same change
   Make a list. Every item gets updated in this same session.

3. **One small change.** Make a single structured edit via `define-method` /
   `define-class`. Update all callers found in step 2 in the same pass so the
   image is never left half-migrated. Read changed methods back with
   `get-method-source`.

4. **Re-test.** Run `run-class-test` then `run-package-test`. Green → keep
   going. Red → the trace shows what broke; fix or revert this one step before
   moving on. Never batch unverified edits.

5. **Repeat** steps 3–4 in small increments until the cleanup is complete.

6. **Done.** Summarize the before/after shape and remind the user to **save
   the image**.

## Common moves
- **Rename method:** install the new selector via `define-method`, repoint all
  senders (from `search-references`), then remove the old one. (No
  `/remove-method` endpoint yet — use `eval`: `Class removeSelector: #old`.)
- **Extract method:** add the new helper, call it from the original, re-test.
- **Move/rename class:** `define-class` the new one, migrate refs found via
  `search-references-to-class`, then retire the old.

## Rules
- Behavior-preserving only. If a test changes meaning, that's a feature change
  — do it under `pharo-tdd`, not here.
- Small steps, tests between each. A long unverified refactor is a bug factory.
- Modern class API only (`ShiftClassInstaller` / `define-class`).
