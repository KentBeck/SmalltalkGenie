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

## Install

```smalltalk
Metacello new
    baseline: 'Genie';
    repository: 'github://KentBeck/SmalltalkGenie:main/src';
    load.
```

Tested with Pharo 12+ (the code also runs on Pharo 9). The baseline pulls in its
only non-base dependencies, **Teapot** (HTTP) and **NeoJSON**.

On a freshly loaded image, set the author once so headless compiles don't block
on the "author initials" dialog:

```smalltalk
Author fullName: 'YourName'.
```

## Run

```smalltalk
GenieServer current.   "starts the server on http://localhost:8087/mcp"
```

Then register it with your MCP client. For Claude Code:

```
claude mcp add --transport http genie http://localhost:8087/mcp
```

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

## Design notes

- **Direct, no bridge.** The image is the MCP endpoint. Plain `application/json`
  request/response over a single `POST /mcp` (no SSE required); protocol version
  `2025-11-25`. Binds to localhost; validates the `Origin` header.
- **Headless, code-only.** No Morphic / Spec / Roassal, no screen inspection.
- **Self-contained.** Depends only on Teapot, NeoJSON, and base Pharo.

## License

MIT — see [LICENSE](LICENSE).
