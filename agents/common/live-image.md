# Live Pharo Image Rules

Genie projects use a live Pharo image as the source of truth.

## Server

- Preferred MCP endpoint: `http://localhost:8087/mcp`
- Server package: `Genie`
- Server class: `GenieServer`

## Code Access

Use MCP tools as the filesystem for Smalltalk code:

- `list_packages`, `list_classes`, `list_methods`
- `get_class_source`, `get_method_source`, `get_class_comment`
- `search_classes_like`, `search_methods_like`
- `search_implementors`, `search_references`, `search_references_to_class`

## Changes

Only change image code through MCP:

- New or changed class: `define_class`
- New or changed method: `define_method`
- Other image operations: `eval`
- Class rename: `rename_class`
- Tests: `run_test`
- Persistence: `save_image`

After every change, read the method or class back to confirm it installed.

## Project Ownership

In user projects, read `.genie/project.ston` before changing code. Only modify
packages listed in `#ownedPackages` unless the user explicitly asks to change
Genie itself.

## Save Rule

Save the image only through `save_image` gated by the relevant test package or
test class. Do not save a red image.
