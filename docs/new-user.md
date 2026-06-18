# New User Guide

This guide is for someone starting their first Genie-backed Smalltalk project.

## Mental Model

Keep three things separate:

- Genie tooling repo: the MCP server, Pharo image, and shared agent pack.
- Your project repo: project instructions, project ownership metadata, and any
  project docs.
- Live Pharo image: the source of truth for Smalltalk code.

You start the model from your project repo. The project repo points at Genie and
declares which Smalltalk packages belong to the project.

## Prerequisites

- This Genie repository is available locally.
- The Genie Pharo image can be started and listens on `localhost:8087`.
- Claude, Codex, or Gemini can be launched from a project directory.

Smoke test the MCP server:

```bash
curl -s -m 5 -X POST http://localhost:8087/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

You should see a JSON-RPC response listing tools.

## Create a Project

From the Genie repository:

```bash
./scripts/genie-init ~/work/counter-app --prefix CounterApp
```

This creates:

```text
counter-app/
├── AGENTS.md
├── CLAUDE.md
├── GEMINI.md
├── .agents/
│   └── skills/
│       └── pharo-live-image
└── .genie/
    ├── agent-instructions.md
    └── project.ston
```

By default, `.agents/skills/pharo-live-image` is a symlink to the shared skill
in the Genie repo. Use `--copy` if you want the project to vendor the skill.

## Existing Agent Instructions

If the target project already has `AGENTS.md`, `CLAUDE.md`, or `GEMINI.md`,
`genie-init` preserves those files by default and writes the Genie-specific
bootloader to `.genie/agent-instructions.md`.

You can then add a short pointer to your existing file:

```md
## Genie MCP

Before changing Smalltalk code, read `.genie/agent-instructions.md`.
```

Or let the scaffold append a marked pointer block:

```bash
./scripts/genie-init ~/work/counter-app --prefix CounterApp --append-agent-files
```

Use `--force` only for throwaway scaffolds or when you intentionally want to
regenerate the root adapter files.

## Start Work

```bash
cd ~/work/counter-app
codex .
```

Or start Claude/Gemini from the same directory.

Example first prompt:

```text
Create a Counter class in package CounterApp with tests in CounterApp-Tests.
Use the live Pharo image through Genie MCP.
```

The agent should:

1. Read `.genie/agent-instructions.md`.
2. Read `.genie/project.ston`.
3. Read `.agents/skills/pharo-live-image/SKILL.md`.
4. Use MCP read/search tools to inspect the image.
5. Create tests first in `CounterApp-Tests`.
6. Implement code in `CounterApp`.
7. Run tests.
8. Save the image only with `save_image` gated by `CounterApp-Tests`.

## Ownership Rules

The scaffold writes `.genie/project.ston`:

```smalltalk
{
  #projectName : 'counter-app',
  #packagePrefix : 'CounterApp',
  #testPackage : 'CounterApp-Tests',
  #mcpPort : 8087,
  #mcpUrl : 'http://localhost:8087/mcp',
  #serverPackage : 'Genie',
  #ownedPackages : [ 'CounterApp', 'CounterApp-Tests' ]
}
```

Agents should only modify packages listed in `#ownedPackages` unless you
explicitly ask them to change Genie itself.

## Updating Shared Instructions

If your project uses symlinks, updates to this repository's
`agents/skills/pharo-live-image` are visible immediately in new agent sessions.

If your project used `--copy`, rerun:

```bash
./scripts/genie-init ~/work/counter-app --prefix CounterApp --copy --force
```

Review changes before committing because `--force` overwrites the generated
adapter files, `.genie/agent-instructions.md`, and skill copy.

## Troubleshooting

- If the agent edits `.st` files, stop it and point it back to
  `.agents/skills/pharo-live-image/SKILL.md`.
- If MCP calls fail, verify the Pharo image is running and port `8087` is
  reachable.
- If the agent tries to change `Genie`, ask it to reread `.genie/project.ston`
  and stay within `#ownedPackages`.
- If tests are red, do not save the image. Fix the test or implementation first.
