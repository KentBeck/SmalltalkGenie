---
name: pharo-tdd
description: Drive a Genie change test-first through the genie MCP tools, working entirely from the live image (no files). Use when adding behavior or fixing a bug in the image — anything where a test should lead.
---

# Pharo TDD loop (live image, via the genie MCP tools)

All work goes through the `genie` MCP tools — there are no files. Read with the
read tools, change only via `define_class` / `define_method` / `eval`. Confirm
every change by reading it back. Never assume a class/selector exists — look it
up first.

## Loop

1. **Locate.** Find the class and its test class:
   `list_classes` (package) → `list_methods` → `get_method_source`.
   Find the matching `...Test` (TestCase subclass). If none exists, create it
   via `define_class` (superclass `TestCase`).

2. **Red.** Write or adjust ONE failing test with `define_method` (protocol
   `tests`). Run it: `run_test` with `class_name`. **Expect failure.** If it
   passes immediately, the test isn't exercising the new behavior — fix the
   test before writing code.

3. **Green.** Implement the smallest method that could pass, via
   `define_method`. Run `run_test` again → expect green. Read the method back
   with `get_method_source` to confirm what's installed.

4. **Regression check.** Run `run_test` for the whole `package_name`. A green
   class test with a red package is not done.

5. **Refactor.** Clean up while green, re-running `run_test` after each step.
   (For larger cleanups, switch to the `pharo-refactor` skill.)

6. **Done.** Persist with `save_image` gated on tests — pass `test_package` so
   it runs them and saves the image only if green. Summarize what changed
   (class >> selector list).

## Debugging a red test
Genie returns full stack traces: failing block source, receiver, and its
variables. Read them. Reproduce the failure with a minimal `eval` first, fix
the smallest thing the trace implicates, then re-run the test. Don't guess.

## Rules
- One test, one reason to fail, at a time.
- Modern class API only (`ShiftClassInstaller` / `define_class`), never the
  deprecated `subclass:instanceVariableNames:classVariableNames:package:`.
- Tests are methods too — install them with `define_method`, protocol `tests`.
