---
name: pharo-tdd
description: Drive a Pharo change test-first through the smalltalk-interop MCP endpoints, working entirely from the live image (no files). Use when adding behavior or fixing a bug in the image — anything where a test should lead.
---

# Pharo TDD loop (live image, via MCP)

All work goes through the `smalltalk-interop` MCP / `localhost:8086`. There are
no source files — read with the MCP endpoints, change only via
`define-class` / `define-method` / `eval`. Confirm every change by reading it
back. Never assume a class/selector exists — look it up first.

## Loop

1. **Locate.** Find the class and its test class:
   `list-classes` (package) → `list-methods` → `get-method-source`.
   Find the matching `...Test` (TestCase subclass). If none exists, create it
   via `define-class` (superclass `TestCase`).

2. **Red.** Write or adjust ONE failing test with `define-method` (protocol
   `tests`). Run it: `run-class-test` on the test class. **Expect failure.**
   If it passes immediately, the test isn't exercising the new behavior — fix
   the test before writing code.

3. **Green.** Implement the smallest method that could pass, via
   `define-method`. Run `run-class-test` again → expect green. Read the
   method back with `get-method-source` to confirm what's installed.

4. **Regression check.** Run `run-package-test` for the whole package. A green
   class test with a red package is not done.

5. **Refactor.** Clean up while green, re-running `run-class-test` after each
   step. (For larger cleanups, switch to the `pharo-refactor` skill.)

6. **Done.** Summarize what changed (class >> selector list) and remind the
   user to **save the image** — changes are in-memory only.

## Debugging a red test
The server returns full stack traces: failing block source, receiver, and its
variables. Read them. Reproduce the failure with a minimal `eval` first, fix
the smallest thing the trace implicates, then re-run the test. Don't guess.

## Rules
- One test, one reason to fail, at a time.
- Modern class API only (`ShiftClassInstaller` / `define-class`), never the
  deprecated `subclass:instanceVariableNames:classVariableNames:package:`.
- Tests are methods too — install them with `define-method`, protocol `tests`.
