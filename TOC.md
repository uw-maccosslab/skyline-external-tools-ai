# Table of Contents

Index of everything in `skyline-external-tools-ai`. Update when you add a document.

## Core files (read each session)
- **[README.md](README.md)** — what this repo is; the two ways to use it (clone / plugin).
- **[CLAUDE.md](CLAUDE.md)** — agent orientation; the classic-vs-RPC tool decision; capability map.
- **[CRITICAL-RULES.md](CRITICAL-RULES.md)** — the hard rules (connect-per-call, message mode, invariant
  culture, blib pooling, packaging gate, …).
- **[MEMORY.md](MEMORY.md)** — ecosystem, mental model, working discipline.

## Documentation (`docs/`)
- **[docs/skyline-external-tools.md](docs/skyline-external-tools.md)** — **the field guide** (canonical).
  §0 tool shapes · §1 RPC connection · §2 reports · §3 document grid · §4 settings · §5 `.blib` ·
  §6 import (SkylineCmd) · §7 packaging · §8 project setup · §9 chromatograms · §10 reading the `.sky` XML ·
  §11 embedding a pwiz engine · §12 dev via the `skyline` MCP · §13 checklist · §14 source map.
- **[docs/installing-a-skyline-tool.md](docs/installing-a-skyline-tool.md)** — **end-user install guide**
  (non-developer): prerequisites, installing the `.zip` from the Tools menu, running, updating, removing,
  troubleshooting.
- **[docs/testing.md](docs/testing.md)** — testing practices (fake RPC seam, hermetic xUnit, ship gate,
  verify-against-real-data, optional live integration).

## Claude assets (`claude/`)
- **[claude/skills/skyline-external-tool/SKILL.md](claude/skills/skyline-external-tool/SKILL.md)** — the
  scaffold-to-package workflow skill.
- **claude/commands/** — lifecycle slash commands.
- **claude/plugins/** — (future) `marketplace.json` to install the skill/commands without cloning.

## Template (`templates/dotnet-tool/`)
- A `dotnet new` template: `Core`/`Cli`/`Skyline`/`App` + vendored `SkylineTool` RPC client + `tool-inf/`
  manifest + `build/` packaging + a smoke test. See its `README.md`.
