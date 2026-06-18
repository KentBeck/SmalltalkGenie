# Working on Genie

Genie is a Pharo MCP server. The active Smalltalk source is the running Pharo
image, accessed through the MCP server at `http://localhost:8087/mcp`.

Before changing Genie itself, follow the same rules as `CLAUDE.md`:

- Treat the live image as the source of truth.
- Read Smalltalk code through MCP read/search tools.
- Change Smalltalk code only through MCP tools.
- Run `run_test` before declaring work done.
- Save only through `save_image` gated on green tests.
- Do not edit Tonel files in `src/` as the primary source.

For user projects backed by Genie, use:

```bash
./scripts/genie-init /path/to/project --prefix ProjectPrefix
```

Then start Gemini from that project directory and read
`.genie/agent-instructions.md` plus `.agents/skills/pharo-live-image/SKILL.md`.
