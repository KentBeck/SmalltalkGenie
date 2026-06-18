# Project Agent Instructions

This project uses Genie MCP for live Pharo development.

Before changing Smalltalk code, read:

- `.agents/skills/pharo-live-image/SKILL.md`
- `.genie/project.ston`

Genie server:

- MCP URL: `http://localhost:8087/mcp`
- Project package prefix: `__PACKAGE_PREFIX__`
- Test package: `__TEST_PACKAGE__`

Do not edit `.st` files as the source of truth unless the user explicitly asks
for export/import work. Modify only packages listed in `.genie/project.ston`
unless the user explicitly asks to work on Genie itself.
