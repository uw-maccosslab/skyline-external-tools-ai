# MEMORY

Cross-cutting context for building Skyline external tools. Gotchas live in `CRITICAL-RULES.md`; deep
detail in `docs/skyline-external-tools.md`. This file is the "what you should know" summary.

## The ecosystem (real examples to learn from)
- **skyline-prism** — RPC tool + cross-platform CLI; robust reports/grid/`.blib`-read; the packaging ship
  gate. The field guide's home before it moved here.
- **skyline-cadenza** — `.blib` *write* + RT read + settings write-back; folds RPC into Core (Windows-only
  Core — fine when there's no cross-platform CLI).
- **skyline-osprey-tool** — chromatogram (XIC) export + parse; reading the `.sky` XML (tolerances, raw
  paths); **embedding the Osprey engine in-process** (project references + adapter over the engine's
  peak-data interface); Percolator FDR. The source of §9–§11.

When in doubt about how a capability is really done, read the corresponding file in one of these (the
field guide's §14 source map points at exact paths).

## Reference platform
- Skyline **26.1** (get the exact version at runtime: `--version` / RPC `GetVersion`).
- .NET **8** for the tool (SDK pinned in `global.json`, `rollForward: latestFeature`). The WPF App needs
  the **.NET 8 Desktop** Runtime; the CLI needs the base runtime.

## The mental model
- **Skyline is the platform; your tool is a client.** Most "make Skyline do X" is a `SkylineCmd` flag sent
  via RPC `RunCommand` (Nick Shulman's golden rule: anything `SkylineCmd` can do, RPC can do live).
- **Getting data out** has three lanes: reports (aggregates), the document grid (replicate/annotations),
  and chromatograms (raw XIC traces). Pick the lane by what you need; don't paginate big reports —
  export to a file.
- **Writing back**: peak boundaries (`--import-peak-boundaries`), annotations (`--annotation-*` +
  `ImportProperties`), libraries (`--add-library-path`).

## Working discipline
- **Verify formats against real data.** Every format fact in the field guide was confirmed by exporting
  from a live document and inspecting the bytes — do the same before trusting a parser. Use the `skyline`
  MCP server to script the round-trip during development (§12).
- **Test without a live Skyline** via the `ISkylineClient`/`FakeExecutor` seam; keep unit tests hermetic
  (build synthetic fixtures, no data files). See `docs/testing.md`.
- **Two rule sets:** a fresh tool uses modern .NET conventions; code you upstream *into pwiz* uses pwiz
  house style. Never cross them.

## Keeping this repo healthy
- The field guide is **canonical here** — other tool repos point to it, they don't fork it.
- Core files (this one, `CLAUDE.md`, `CRITICAL-RULES.md`) are **append-hostile** reference cards
  (<~200 lines); put depth in `docs/`. Update `TOC.md` when you add a doc.
- New verified gotcha → add it to the field guide (with a section ref) and, if it's hours-costly, to
  `CRITICAL-RULES.md`.
