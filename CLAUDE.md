# CLAUDE.md

Orientation for an AI agent helping build a **Skyline external tool**. This repo is the shared knowledge
base; the tool you're building lives in its own checkout (a sibling of this `ai/`).

## First moves

1. Read **`CRITICAL-RULES.md`** (the handful of rules that waste hours if broken).
2. Skim **`docs/skyline-external-tools.md`** §0 to pick the tool *shape* (below), then read the sections
   for the capabilities your tool needs — don't read it all up front.
3. To scaffold + build, invoke the **`skyline-external-tool` skill**.

## Pick the tool shape first (docs §0)

| | **Live JSON-RPC tool** | **Classic report-macro tool** |
|---|---|---|
| Mechanism | Connects back to the running Skyline over a named pipe (JSON-RPC) | Skyline exports named reports and launches your program with path macros |
| Interactivity | Bidirectional — read grid, change settings, write libraries, live UI | One-shot — read the report(s), emit files |
| Manifest | `Arguments=$(SkylineConnection)` | `Report=…`, `Arguments="…$(ReportTempPath)…"` |
| Reach for it when | You must read the live document beyond a report, or write back to it | You just need the report data |

**The classic tool is far simpler.** Only build the RPC tool when you need live read/write or interactive UI.

## What Skyline can do for your tool (map to the field guide)

- **Get data out** — reports (tabular: areas/RTs/scores, docs §2), the document grid / annotations (§3),
  and **raw chromatogram XIC traces** (`--chromatogram-file`, §9). Read the `.sky` XML directly for
  instrument tolerances + raw-file paths (§10).
- **Change the document** — almost anything `SkylineCmd` can do is reachable via RPC `RunCommand`
  (§4, §6): settings, import results/FASTA/libraries, annotations, peak boundaries.
- **Libraries** — read and *write* `.blib` (§5).
- **Write back** — `--import-peak-boundaries`, `--annotation-*` + `ImportProperties`, custom annotations.
- **Advanced** — embed a pwiz/ProteoWizard engine (Osprey scoring, readers) in-process (§11); drive a
  live Skyline during development via the `skyline` MCP server (§12).

## Conventions for the tool you build

- **Modern .NET 8** (this is a fresh tool, not the pwiz codebase — no pwiz house-style rules apply here).
  `async`/`await` is fine. Use the `templates/dotnet-tool/` layout: `Core` (net8.0, cross-platform) /
  `Cli` (net8.0) / `Skyline` (net8.0-windows, RPC) / `App` (WPF).
- **Exception:** if you contribute a facade *upstream into pwiz* (e.g. an `Osprey.Api`), that code follows
  **pwiz** house style (CRLF, no `async`/`await`, resource strings, `quickbuild`) — see the target repo's
  own `ai/`. Keep the two rule sets separate.
- Verify formats against a **live Skyline / real data**, not assumptions — see `docs/testing.md`.

## This repo

Don't confuse *this* knowledge repo with the *tool* you're building. Edits here improve the shared guide,
skill, or template; edits in the tool checkout build the tool. Keep the field guide canonical here — other
tool repos should point to it, not fork it.
