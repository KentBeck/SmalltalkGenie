---
name: pharo-live-image
description: Use when modifying a Genie-backed Pharo project through the live MCP server on localhost:8087; includes project ownership, image read/change/test/save workflow, and first steps for new user projects.
---

# Pharo Live Image Workflow

Use this skill for any task that reads, changes, tests, or saves Smalltalk code
in a Genie-backed project.

## Before Changing Code

1. Read `.genie/project.ston` if it exists.
2. Identify the project package prefix and `#ownedPackages`.
3. Use MCP read/search tools to inspect the live image before assuming a class,
   selector, or package exists.
4. If the requested change touches packages outside `#ownedPackages`, stop and
   ask unless the user explicitly asked to work on Genie itself.

## MCP Server

Preferred endpoint:

```text
http://localhost:8087/mcp
```

The server is JSON-RPC MCP. Do not assume REST paths like `/list-packages`
exist.

Use tools by name:

- `list_packages`, `list_classes`, `list_methods`
- `get_class_source`, `get_method_source`, `get_class_comment`
- `search_classes_like`, `search_methods_like`
- `search_implementors`, `search_references`, `search_references_to_class`
- `define_class`, `define_method`, `rename_class`, `remove_class`,
  `remove_method`
- `run_test`
- `save_image`

## TDD Loop

1. Locate current code with MCP read/search tools.
2. Add or update a test in the project test package.
3. Run the test and confirm it fails for the expected reason.
4. Implement the smallest image change through MCP.
5. Read changed methods/classes back.
6. Run the relevant class/package tests.
7. Save with `save_image` gated on the relevant test package when green.

## Exported Files

The live image is the source of truth. Do not edit `.st`, Tonel, or generated
export files as the primary way to change behavior unless the user explicitly
asks for export/import maintenance.

## References

Read `references/mcp-8087.md` when you need the exact JSON-RPC request shape or
a curl smoke test.
