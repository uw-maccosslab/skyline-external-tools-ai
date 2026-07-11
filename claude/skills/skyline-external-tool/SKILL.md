---
name: skyline-external-tool
description: Load when building, scaffolding, packaging, or debugging a Skyline external tool (a program launched from Skyline's Tools menu that reads/writes the document via JSON-RPC or report macros, reads/writes .blib, exports chromatograms, or embeds a pwiz engine). Triggers on "Skyline external tool", "Skyline plugin/add-in", "SkylineConnection", "tool-inf", scaffolding a Core/Cli/Skyline/App .NET tool, or packaging a Skyline tool zip.
---

# Building a Skyline external tool

You are helping build a **Skyline external tool**. The complete reference is
**`docs/skyline-external-tools.md`** (the field guide) with **`CRITICAL-RULES.md`** for the hours-costly
gotchas and **`docs/testing.md`** for tests. Read the field-guide section for the capability at hand —
don't dump the whole thing. Work through the phases below.

## Phase 1 — Scope it (pick the shape)

Ask (or infer) two things, then commit:

1. **Classic report-macro tool or live JSON-RPC tool?** (field guide §0). Default to **classic** — it's
   far simpler — unless the tool must read the live document beyond a report, write back, or show
   interactive UI. Say which you picked and why.
2. **What capabilities?** Map the ask to field-guide sections so you read only what's needed:
   - tabular data out → §2 reports · replicate/annotation metadata → §3 grid
   - **raw chromatogram traces** → §9 · instrument tolerances / raw-file paths from the `.sky` → §10
   - change settings / import / annotations → §4, §6 · read/write `.blib` → §5
   - **embed a pwiz/Osprey engine** → §11 · interactive review UI → WPF App (a Settings tab + a Log/console
     tab + optional ScottPlot review tab)
   - packaging/install → §7

## Phase 2 — Scaffold

Use `templates/dotnet-tool/` (a `dotnet new` template). Name the tool (PascalCase, e.g. `MyTool`):

```bash
dotnet new install <path-to>/templates/dotnet-tool     # once
dotnet new skyline-external-tool -n MyTool -o MyTool
```
That yields `MyTool.sln` with `Core` (net8.0) / `Cli` (net8.0) / `Skyline` (net8.0-windows, RPC) / `App`
(WPF), the **vendored `SkylineTool` RPC client** already wired into `.Skyline` only, a `tool-inf/`
manifest, `build/package-and-verify.ps1`, and a smoke test. Confirm `dotnet build MyTool.sln` is green
before writing logic. A **classic** tool needs only `Core` + a thin launcher + a `.properties` with
`Report=…` — drop `App`/`Skyline`.

## Phase 3 — Implement

- Put algorithms/IO in **`Core`** (keep it cross-platform: no pipes, no WPF). RPC in **`.Skyline`** only.
- Connection: transform `args[0]` with `GetJsonPipeName`, **connect per call**, `ReadMode=Message`
  (§1) — these are in the template's `SkylineSession`. Keep the `ISkylineClient`/`ISkylineExecutor` seam so
  you can test with a `FakeExecutor` (§ testing).
- Anything "make Skyline do X" is usually a `SkylineCmd` flag via `RunCommand` (§4, §6) — **one flag per
  batch**.
- **Invariant culture everywhere** (§8). Parse/write with `CultureInfo.InvariantCulture`.
- Embedding an engine (§11): implement the engine's peak-data *interface* as an adapter over Skyline's
  exported XICs; alias colliding type names; replicate any harness-published byproduct the engine expects.

## Phase 4 — Test (see `docs/testing.md`)

- Unit-test the driver via the `FakeExecutor` seam — no live Skyline.
- Hermetic fixtures (build a tiny `.blib` / TSV / `.sky` snippet in-test; both blib peak encodings).
- **Verify each format fact against real data once** (use the `skyline` MCP, §12), then pin it as an
  assertion. Keep real data git-ignored and out of CI.
- One integration test through any embedded engine with synthetic inputs.

## Phase 5 — Package & verify (§7)

- `tool-inf/`: `Arguments=$(SkylineConnection)`; the `<ToolName>.properties` filename **must match** the
  `AssemblyName`/`Command`; keep `Version` in sync with the assembly `<Version>`.
- Publish **framework-dependent**; run `build/package-and-verify.ps1` (test → zip → **launch-verify**:
  extract clean, launch the exe, grep the log for load failures).
- Install: Tools ▸ Tool Store ▸ Install from file, or `--tool-add-zip`. **Close the tool before
  reinstalling.**

## Guardrails

- If you hit `0x00 is invalid start of value`, it's one of the three connection rules (§1) — check them
  before anything else.
- This tool is **modern .NET 8** (async/await fine). Only code you upstream *into pwiz* follows pwiz house
  style — keep the two rule sets separate.
- New hours-costly gotcha discovered? Add it to the field guide (with a section ref) and, if severe, to
  `CRITICAL-RULES.md`.
