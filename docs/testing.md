# Testing a Skyline external tool

How to test an external tool so it's trustworthy *and* CI runs anywhere. This is deliberately **modern
.NET** (xUnit, hermetic) — it is NOT the pwiz house test style (that's for code you upstream into pwiz).

The through-line: **you almost never need a live Skyline to test your logic.** Put the RPC behind a seam,
make unit tests build their own fixtures, and reserve the live instance for a final smoke.

## The layers

| Layer | What it proves | Needs a live Skyline? |
|---|---|---|
| **Unit (hermetic)** | Parsers, format readers, algorithms, the driver logic | No |
| **Integration (in-proc)** | Your code against a real embedded engine (e.g. Osprey) with synthetic inputs | No |
| **Live round-trip** (optional) | The actual RPC export/annotation cycle end-to-end | Yes (or the `skyline` MCP) |
| **Ship gate** | The packaged zip installs and the exe loads | No (launches the built exe) |

## 1. Put the RPC behind a seam (test the driver with no Skyline)

Define the subset of RPC you use as `ISkylineClient`, plus `ISkylineExecutor.Execute<T>()`. The concrete
`SkylineSession` implements the executor (connect-per-call, message mode) and forwards to the vendored
`SkylineJsonToolClient`. A `FakeExecutor`/`FakeClient` then drives your whole report/grid/library/write-back
flow in unit tests:

```csharp
var fake = new FakeSkylineClient()
    .WithDocumentPath(@"C:\x\doc.sky")
    .WithReport("MyReport", "col1,col2\n1,2\n");
var driver = new MyToolDriver(new FakeExecutor(fake));
var result = driver.Run();
Assert.Equal(1, result.RowCount);   // no pipe, no Skyline
```
This is the single highest-leverage test investment — it turns "needs a running Skyline" into an ordinary
unit test.

## 2. Hermetic fixtures (no data files in the repo)

Build inputs in the test so CI needs nothing on disk:

- **A `.blib`** — create the SQLite tables and insert a couple of spectra with `Microsoft.Data.Sqlite`;
  cover *both* peak-blob encodings (raw and `ZLibStream`-compressed) so your reader is exercised on both.
- **A chromatogram export** — write a small TSV string (the 10-column format, comma arrays) to a temp file
  or a `StringReader`; assert grouping, array parse, and **invariant** number parsing (`6.4E+07`).
- **A `.sky` snippet** — a minimal `<transition_settings>` / `<sample_file>` string through an
  `XmlReader`; assert the tolerances / raw paths you extract.

Keep large real data **git-ignored** and out of the unit suite. Reference it only from a manual/local
harness (a CLI subcommand), never from CI tests.

## 3. Verify formats against real data (once, deliberately)

Every format fact you rely on should be **confirmed by looking at real bytes**, not assumed:
1. Export from a live document (`--chromatogram-file`, `ExportReport`, a `.blib`) — use the `skyline` MCP
   to script it (field guide §12).
2. Inspect the real output (column count, delimiters inside cells, array lengths, RT units, endianness of
   blib blobs).
3. Encode those facts as unit-test assertions against a *synthetic* fixture shaped the same way.

Then the fast hermetic tests guard the contract, and you only re-verify when Skyline changes.

## 4. Integration against an embedded engine (§11)

If you embed a pwiz engine, write one hermetic test that drives your adapter through the *real* engine
assemblies with synthetic inputs and asserts a known-direction result (e.g. a co-eluting fragment set
scores above a scrambled one). This proves the integration wiring — the riskiest part — without any data
file, and catches engine-API drift at build time.

## 5. The launch-verify ship gate (the one that saves releases)

Automate **test → package → launch-verify** (`build/package-and-verify.ps1`). The verify step extracts the
zip to a clean directory (fresh-install simulation) and *actually launches* the exe with a dummy connection
arg. Because the WPF window (hence WPF/ScottPlot/SkiaSharp/native deps) loads at startup, a broken native
dependency surfaces as a load error. Grep the tool's log for
`Could not load file or assembly | XamlParseException | TypeInitializationException | DllNotFoundException |
BadImageFormatException` and require a "tool started" line. A failed *connection* from the dummy arg is
expected; a failed *load* is not.

## 6. CI

- `EnableWindowsTargeting=true` so the `net8.0-windows`/WPF projects **build** on Linux/macOS agents; **gate
  their tests to the Windows runner** (WPF/pipes need Windows at runtime).
- `Core`/`Cli` unit tests run on every OS — keep them free of pipes/WPF.
- Pin native-dependency package versions (SkiaSharp, DuckDB, `e_sqlite3`); on Linux CI SkiaSharp needs
  `libfontconfig1` + `libfreetype6`.

## Checklist

- [ ] RPC behind `ISkylineClient` + `ISkylineExecutor`; a `FakeExecutor` drives the driver tests.
- [ ] Unit tests build their own `.blib` / TSV / `.sky` fixtures — no data files, both blib encodings.
- [ ] Every relied-on format fact was verified against real data and pinned as an assertion.
- [ ] One integration test through any embedded engine with synthetic inputs.
- [ ] `package-and-verify.ps1` runs test → package → launch-verify and greps for load failures.
- [ ] Windows-only tests gated to the Windows runner; `Core`/`Cli` tests OS-agnostic.
