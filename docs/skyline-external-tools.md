# Building a Skyline external tool — a field guide

Everything we've learned building Skyline external tools in C#/.NET across
[skyline-prism](https://github.com/maccoss/skyline-prism),
[skyline-cadenza](https://github.com/maccoss/skyline-cadenza), and
[skyline-osprey-tool](https://github.com/maccoss/skyline-osprey-tool) — how a tool connects to a running
Skyline, exports reports **and raw chromatograms**, reads the document grid **and the `.sky` XML**,
changes settings, reads and *writes* `.blib` libraries, imports results, **embeds a pwiz/ProteoWizard
engine in-process**, and is packaged/installed. It is deliberately broader than what any one tool uses.
**Written for the next AI agent** who has to do this again: the gotchas below each cost real time to
discover.

Reference Skyline version for the CLI surface here: **26.1.1** (get it at runtime with
`--version` / RPC `GetVersion`).

---

## Contents

- [0. Two ways to write a tool — pick one](#0-two-ways-to-write-a-tool--pick-one)
- [1. Connecting to a running Skyline (JSON-RPC)](#1-connecting-to-a-running-skyline-json-rpc)
- [2. Reports](#2-reports)
- [3. Reading the document grid (Replicates, annotations)](#3-reading-the-document-grid-replicates-annotations)
- [4. Changing document settings & annotations](#4-changing-document-settings--annotations)
- [5. BLIB spectral libraries (SQLite)](#5-blib-spectral-libraries-sqlite)
- [6. Importing results, FASTA, libraries, building a blib (SkylineCmd surface)](#6-importing-results-fasta-libraries-building-a-blib-skylinecmd-surface)
- [7. Packaging & installing the tool](#7-packaging--installing-the-tool)
- [8. Project setup / NuGet / architecture](#8-project-setup--nuget--architecture)
- [9. Chromatograms — getting extracted XICs out of Skyline](#9-chromatograms--getting-extracted-xics-out-of-skyline)
- [10. Reading the raw `.sky` XML directly](#10-reading-the-raw-sky-xml-directly)
- [11. Embedding a pwiz / ProteoWizard engine in-process (project references)](#11-embedding-a-pwiz--proteowizard-engine-in-process-project-references)
- [12. Developing against a live Skyline (the `skyline` MCP server)](#12-developing-against-a-live-skyline-the-skyline-mcp-server)
- [13. Checklist for the next agent](#13-checklist-for-the-next-agent)
- [14. Source map (where each capability lives)](#14-source-map-where-each-capability-lives)

**Related:** [Installing a Skyline tool (end-user guide)](installing-a-skyline-tool.md) — a friendly,
non-developer walkthrough for analysts installing a packaged tool `.zip`.

---

## 0. Two ways to write a tool — pick one

| | **Live JSON-RPC tool** (PRISM `SkylinePrism.App`, cadenza) | **Classic report-macro tool** (`skyline-prism/skyline-external-tool`, Python) |
|---|---|---|
| Mechanism | Connects back to the *running* Skyline over a named pipe (JSON-RPC 2.0) | Skyline exports named reports to temp files and launches your program with path macros |
| Interactivity | Bidirectional — read grid, change settings, write libraries, re-import, live | One-shot — read the exported report(s), do work, write output |
| Manifest key | `Arguments=$(SkylineConnection)` | `Report=…`, `Arguments="…$(ReportTempPath)…"` |
| When to use | You need to read/write the live document or show interactive UI | You just need the report data and to emit files |

The classic tool is far simpler and needs no RPC. Reach for the live RPC tool only when you need to
*read the live document beyond a report* or *write back to it*.

Classic manifest (`skyline-external-tool/tool-inf/PRISM.properties`):
```properties
Command=$(ProgramPath(Python,3.12.8))
Arguments="$(ToolDir)/Scripts/run_prism.py" --report "$(ReportTempPath)" --metadata "$(ReportTempPath:Replicates)" --output "$(DocumentDir)/prism-output"
Report=Skyline-PRISM
AuxiliaryReport1=Replicates
InitialDirectory=$(DocumentDir)
```
Macros: `$(ProgramPath(title,version))`, `$(ToolDir)`, `$(DocumentDir)`, `$(ReportTempPath)` /
`$(ReportTempPath:<AuxReportName>)`, and `$(SkylineConnection)` (RPC tools). `info.properties` may add
`PythonVersion=3.12.8` so Skyline provisions the interpreter.

Everything from Section 1 on is about the **live JSON-RPC tool**.

---

## 1. Connecting to a running Skyline (JSON-RPC)

### The vendored RPC client
Copy four files **verbatim** from pwiz `pwiz_tools/Skyline/SkylineTool/` (Apache-2.0):
`SkylineJsonToolClient.cs`, `IJsonToolService.cs`, `JsonToolConstants.cs`, `JsonToolModels.cs`. Keep them
under `external/SkylineTool/` with a README noting the sync procedure (diff against a fresh pwiz checkout
before committing). Consume them two ways:
- **.NET Framework 4.7.2** tool → reference the prebuilt `SkylineTool.dll`.
- **.NET 8+** tool → **link-compile the four `.cs` files** (System.Text.Json is in-box).

### Transport
JSON-RPC 2.0 over a `NamedPipeClientStream`, **message mode**, snake_case JSON:
```csharp
var pipe = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut);
pipe.Connect(5000);
pipe.ReadMode = PipeTransmissionMode.Message;      // MANDATORY — else the response read never completes
using var client = new SkylineJsonToolClient(pipe);
var path = client.GetDocumentPath();
```
The client serializes `{ jsonrpc:"2.0", method, params, id:1 }`, `Flush()`+`WaitForPipeDrain()`, then reads
until `IsMessageComplete`. Errors surface as a typed `JsonRpcException(Code, Message)`.

### ⚠️ The single biggest gotcha: `$(SkylineConnection)` is the *legacy* pipe name
Skyline passes your tool the **legacy ToolService pipe name** as `args[0]`. The JSON-RPC server listens on
a *derived* name. **Connect to `args[0]` directly and the first read fails with
`JsonReaderException: 0x00 is invalid start of value`** (you hit the old binary server). Transform it:
```csharp
// JsonToolConstants: JSON_PIPE_PREFIX = "SkylineMcpJson-"; GetJsonPipeName(name) = prefix + name.Replace("-","")
var jsonName = raw.StartsWith("SkylineMcpJson-") ? raw : JsonToolConstants.GetJsonPipeName(raw);
```
(`SkylineSession.FromArguments`.)

### ⚠️ Connect **per call** — never hold the pipe open
Skyline closes the pipe after each request/response. Reusing a pipe works for the first call and then fails
after idle with the same `0x00` error. Open a fresh pipe every call:
```csharp
public T Execute<T>(Func<ISkylineClient,T> action) {
    using var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.InOut);
    pipe.Connect(timeout); pipe.ReadMode = PipeTransmissionMode.Message;
    return action(new JsonClientAdapter(new SkylineJsonToolClient(pipe)));
}
```

### Standalone discovery (dev without `args[0]`)
Skyline writes `~/.skyline-mcp/connection-<pid>.json` (`pipe_name`, `process_id`, `connected_at`,
`skyline_version`). Walk them and pick the newest to attach a locally-launched `.exe` to a running Skyline.

### Recommended seam (testability)
Define `ISkylineClient` (the subset of RPC calls you use) + `ISkylineExecutor` (`Execute<T>`), have the
concrete `SkylineSession` implement the executor and forward through a private adapter to
`SkylineJsonToolClient`. Then a `FakeExecutor`/`FakeClient` drives your whole driver in unit tests **with no
live Skyline** — this is how PRISM tests the report/grid/library logic. (Cadenza skips the seam and hands
out the concrete client; add the seam if you want tests.)

---

## 2. Reports

### RPC surface (`IJsonToolService`)
- `ExportReport(name, filePath, culture)` → writes a saved report; **format is chosen by file extension**.
- `ExportReportFromDefinition(ReportDefinition, filePath, culture)` — export an *ad-hoc* report.
- `GetReportRows(name, offset, count, columns, filter, includeMaxLength, culture)` — inline windowed rows.
- `GetReportFromDefinitionRows(ReportDefinition, offset, count, includeMaxLength, culture)`.
- `AddReportFromDefinition(ReportDefinition)` — persist a report into user settings.
- `GetReportDocTopics()` / `GetReportDocTopic(name, dataSource)` — column documentation (see §3).

`culture` = `"invariant"` or `"localized"`. **Always use `"invariant"`** for machine consumption (English
headers without spaces, `.` decimal). `count = 0` returns **shape only** (TotalRows + columns, no rows) — use
it to size a pull, then fetch all rows in a second call.

### `ReportDefinition` shape
```csharp
class ReportDefinition {
  string[] Select;           // column IDs (dotted navigation, see .skyr below)
  string Name;
  ReportFilter[] Filter;     // { Column, Op, Value }
  ReportSort[] Sort;         // { Column, Direction }
  bool? PivotReplicate;      // fold per-replicate result columns into columns (vs. row explosion)
  bool? PivotIsotopeLabel;
  string Uimode;             // "proteomic" | "small_molecules" | "mixed"
  string DataSource;         // "document_grid" | "audit_log" | ...
}
```

### `.skyr` report definitions (ship them, install on demand)
A `.skyr` is a Skyline "view" XML. Ship it next to the tool and install with
`RunCommand(["--report-add=<file>.skyr", "--report-conflict-resolution=overwrite"])`. Column names use dotted
entity navigation; `Results!*` is the per-replicate sublist:
```xml
<view name="PRISM" rowsource="pwiz.Skyline.Model.Databinding.Entities.Transition" sublist="Results!*" uimode="proteomic">
  <column name="Precursor.Peptide.Protein" />
  <column name="Precursor.Peptide.ModifiedSequence.UnimodIds" />
  <column name="Results!*.Value.Area" />
  <column name="Results!*.Value.PrecursorResult.PeptideResult.ResultFile.Replicate.Name" />
</view>
```
A replicate-level view uses `rowsource=...Entities.Replicate`; the first `<column name="" />` is the row's own
identity.

### Export-to-file vs paginate (perf)
`GetReportRows`/`GetReportFromDefinitionRows` **recompute the report from scratch on every page** — paginating a
big report is O(pages × full-report). Prefer `ExportReport*` to write the whole report to disk in one
round-trip (~20× faster on a SEA-AD-class document); use a tiny `GetReportFromDefinitionRows(def,0,200,…)` only
to probe columns.

### PRISM's driver pattern
1. `EnsureReportsInstalled` → install the `.skyr` files (idempotent, overwrite).
2. **Parquet-first**: `ExportReport("PRISM","PRISM.parquet","invariant")`, then validate by checking the `PAR1`
   magic at head+tail; **CSV fallback** (`.csv`) whenever that does not yield real parquet — an older
   Skyline, or the host you are driving (see the next two subsections: `SkylineCmd` cannot).
3. Invariant everywhere.

### Format is chosen by the FILE EXTENSION — not by a format argument

Both `ExportReport` (RPC) and `SkylineCmd --report-file=…` dispatch on the output extension.
**There is no `--report-format=parquet`** — that flag validates against `csv|tsv` and rejects anything
else (`The value 'parquet' is not valid for the argument --report-format. Use one of csv, tsv`). To get
parquet on the command line, pass `--report-file=out.parquet` and **omit `--report-format` entirely**.
Always verify the `PAR1` magic and keep a CSV fallback rather than trusting the exit code.

#### Driving Skyline headlessly: `SkylineRunner` beats `SkylineCmd`

There are two ways to run Skyline command-line arguments against a document that is **not open**, and they
are not equivalent:

| | `SkylineCmd.exe` | **SkylineRunner** (recommended) |
|---|---|---|
| What runs | a small stand-alone host | the **installed `Skyline.exe`**, UI-less |
| Config file | `SkylineCmd.exe.config` | `Skyline.exe.config` |
| Parquet report export | ✗ broken (see below) | ✓ works |
| Startup | fast (~2 s) | slower (~6 s; full app + update check) |
| Exit code | real process exit code | none — parse the output |

**SkylineRunner is a tiny shim, and its protocol is ~40 lines you can reimplement** (pwiz:
`pwiz_tools/Skyline/Executables/SkylineRunner/Program.cs`). Worth doing, because the official shim is a
separate download **built per channel** — one binary looks only for `Skyline`, another
(`SkylineDailyRunner.exe`) only for `Skyline-daily` — so shipping it means shipping the right one, or two.
Reimplementing lets you probe both:

1. Find the ClickOnce shortcut, trying `Skyline-daily` then `Skyline`, in either layout:
   `%APPDATA%\Microsoft\Windows\Start Menu\Programs\MacCoss Lab, UW\<App>.appref-ms`, or
   `…\Programs\<App>\<App>.appref-ms`.
2. `guid = "-" + Guid.NewGuid()`; launch `cmd.exe /c "<shortcut>" CMD<guid>`
   (`.appref-ms` is not directly executable; escape `^` and `&` — and then spaces — in the path).
3. Serve `NamedPipeServerStream("SkylineInputPipe" + guid)`, wait for Skyline to connect, then write
   `--sw=<width>`, `--dir=<cwd>`, and **one argument per line**. Close the writer.
4. Connect `NamedPipeClientStream("SkylineOutputPipe" + guid)` and read lines until EOF.

⚠️ **There is no exit code.** The launching `cmd.exe` returns immediately, so the *only* failure signal is
an `Error:` prefix at the start of an output line (or straight after a tab, when timestamps are on) — plus
the localized `エラー：` / `错误：`. Get this wrong and a failed export reports success. Reading the output
pipe to EOF is also how you know the batch finished.

Allow a generous startup timeout: a cold ClickOnce launch plus Skyline's update check can exceed the
official runner's 15 s.

#### ⚠️ Headless parquet is broken in `SkylineCmd` (use SkylineRunner instead)
`SkylineCmd --report-file=out.parquet` fails (Skyline-daily 25.1) with:

```text
Error: Failure attempting to save <Report> report to out.parquet.
Could not load file or assembly 'Parquet, Version=4.0.0.0, Culture=neutral,
PublicKeyToken=d380b3dee6d01926' or one of its dependencies. The module was expected to contain an
assembly manifest.
```

The parquet code path **is** reached — this is a deployment bug, not a missing feature. In the Skyline
application folder the managed Parquet.Net assembly ships as **`ParquetNet.dll`** (identity `Parquet,
Version=4.0.0.0`) while a **native** `parquet.dll` sits beside it and owns the default probe path (the
filesystem is case-insensitive), so the CLR loads the native DLL and finds no assembly manifest.
`Skyline.exe.config` resolves this with an explicit binding; `SkylineCmd.exe.config` has **no
`<assemblyBinding>` section at all**, so the GUI/RPC path works and the CLI does not.

Verified fix — copy these eight `dependentAssembly` entries from `Skyline.exe.config` into
`SkylineCmd.exe.config` (the `Parquet` `codeBase` alone is *not* enough; the dependency redirects are
required too, or it fails with a bare `One or more errors occurred.`):

```xml
<dependentAssembly>
  <assemblyIdentity name="Parquet" publicKeyToken="d380b3dee6d01926" culture="neutral" />
  <codeBase version="4.0.0.0" href="ParquetNet.dll" />
</dependentAssembly>
<!-- plus bindingRedirects for: IronCompress, Microsoft.IO.RecyclableMemoryStream, System.Buffers,
     System.Memory, System.Numerics.Vectors, System.Runtime.CompilerServices.Unsafe,
     System.Threading.Tasks.Extensions -->
```

With that in place the same report exported **61 KB of parquet vs 946 KB of CSV**. Until Skyline ships
the fix, a tool should just try `.parquet` and fall back to CSV — no version check needed.

> Reports give tabular **aggregates** (areas, RTs, scores). For the raw **chromatogram point-arrays**
> (XIC traces) that a peak-picking / detection / re-scoring tool needs, see **§9**.

---

## 3. Reading the document grid (Replicates, annotations)

### ⚠️ The built-in "Replicates" view is **not a named report**
`GetReportRows("Replicates", …)` fails with **"Report not found"** and it isn't in the exportable saved-report
list. Read it as a **document grid** instead:
```csharp
// Columns available on the Replicate entity (built-ins + user annotations):
var detail = client.GetReportDocTopic("Replicate", "document_grid");   // -> ColumnDefinition[] { Name, Description, Type }
var columns = detail.Columns.Select(c => c.Name);

// Rows, one per replicate:
var def = new ReportDefinition { Select = columns.ToArray(), PivotReplicate = false, DataSource = "document_grid" };
var shape = client.GetReportFromDefinitionRows(def, 0, 0, false, "invariant");   // count=0 -> TotalRows
var rows  = client.GetReportFromDefinitionRows(def, 0, shape.TotalRows, false, "invariant");
```

### Queryable document-grid topics (from `GetReportDocTopics`)
`Protein, ProteinResults, Peptides, PeptideResults, Precursors, PrecursorResults, PrecursorResultsSummary,
Transitions, TransitionResults, TransitionResultsSummary, Replicate, AuditLog` — each reports its column count.
`Replicate` carries the built-in replicate columns **plus every user-defined document annotation**.

### Built-in vs annotation columns
Maintain a hard-coded set of built-in Replicate columns (`Replicate, ReplicateName, FileName, FilePath,
SampleName, ModifiedTime, AcquiredTime, SampleType, AnalyteConcentration, BatchName, ReplicateLocator, …`).
**Any column not in that set is a user annotation** — carry those through verbatim (they're the experiment
design: Condition, Subject, Batch, …). PRISM curates the useful built-ins and always keeps the annotations.

### Annotation column naming — ⚠️ prefix it **and quote it**

When requesting an annotation column in an ad-hoc `.skyr` you must prefix it (`annotation_<Name>`) **and
wrap it in quotes**:

```xml
<column name="&quot;annotation_Condition&quot;" />   <!-- correct -->
<column name="annotation_Condition" />               <!-- REJECTED -->
```

Skyline parses `column/@name` as a databinding **PropertyPath**, whose bare-identifier syntax does not
allow `_` — and the `annotation_` prefix itself contains one, so *every* annotation column needs the
quotes. Unquoted, the export dies with:

```text
Error: Failure attempting to save <View> report to <path>.
Error parsing annotation_Condition at location 10: Invalid character _
```

and **no file is written** — so an annotation silently never reaches your metadata (the failure looks
like "the report came back without that column"). Quoted, the exported column is headed with the plain
annotation name (`Condition`). This is the same quoting Skyline itself uses for property names with
special characters in saved views, e.g.
`<column name="Results!*.Value.PeptideResult.&quot;rdotp_Light:Heavy&quot;" />`.

Verified against `SkylineCmd --report-add … --report-name … --report-file …` on a real document
(quoted → OK; bare → the error above; `Annotations.<Name>` → also rejected;
`Replicate."annotation_<Name>"` → exports a `#COLUMN … NOT FOUND#` placeholder).

Because the built-in Replicates view isn't RPC-exportable, PRISM synthesizes a Replicate `.skyr` on the
fly (`ReplicatesReportBuilder`), installs it with `--report-add`, then exports it — the same builder
feeds both the live-RPC path and the headless `SkylineCmd` path.

---

## 4. Changing document settings & annotations

**Golden rule (per Nick Shulman): anything `SkylineCmd` can do is reachable via JSON-RPC `RunCommand` against
the live document.** So most "change settings" operations are just `RunCommand([...SkylineCmd flags...])`
(§7 lists the flags). Examples: `--pep-min-length`, `--tran-precursor-ion-charges`,
`--tran-product-ion-types`, `--full-scan-acquisition-method`, `--full-scan-isolation-scheme`,
`--annotation-name/-targets/-type/-values`, `--integrate-all`.

RPC-native settings calls also exist: `GetDocumentSettings(file)` / `GetDefaultSettings(file)` (write settings
XML), and the settings-list family `GetSettingsListTypes` / `GetSettingsListNames(type, group)` /
`GetSettingsListItem` / `AddSettingsListItem(type, xml, overwrite)` / `GetSettingsListSelectedItems` /
`SelectSettingsListItems`. `ImportProperties(csvText)` imports annotation values (first column = ElementLocator
paths).

### ⚠️ SkylineCmd aborts the **whole batch** on the first unknown/invalid arg
Send flags **one per `RunCommand` batch** so one bad flag doesn't roll back the rest — **except** fields that
Skyline **mutually validates**, which must be sent **together** or each rejects the other (e.g. DIA
acquisition-method + isolation-scheme; MS1 isotope count + analyzer + ppm). Test empirically.

---

## 5. BLIB spectral libraries (SQLite)

A `.blib` is a BiblioSpec SQLite database. Use `Microsoft.Data.Sqlite`.

### ⚠️ Always `Pooling=False`
`Data Source=<path>;Mode=ReadOnly;Pooling=False` — otherwise the connection lingers in the pool and **locks the
user's `.blib`**. Same for writes.

### Reading fragment spectra
```sql
SELECT s.peptideSeq, s.precursorMZ, s.precursorCharge, s.peptideModSeq, p.peakMZ, p.peakIntensity
FROM RefSpectra s JOIN RefSpectraPeaks p ON p.RefSpectraID = s.id
```
- `peakMZ` = little-endian **doubles** (8 bytes each); `peakIntensity` = little-endian **floats** (4 bytes).
- **Blobs may be zlib-compressed** — detect by **length**, not the magic bytes: if
  `blob.Length == numPeaks * sizeof` it's raw, otherwise inflate with `ZLibStream`. ⚠️ The zlib header's
  second byte varies with compression level (`0x78 0x01 / 0x5E / 0x9C / 0xDA`), so matching `0x78 0x9C`
  exclusively **misses** blibs written at a non-default level (Carafe/Cadenza-predicted `.blib`s are
  compressed but not always `0x9C`); the length check is level-agnostic. (Old/small BLIBs store peaks raw.)
- Normalize intensities to base peak = 1.0 if you need relative intensities.
- ⚠️ **Match fragments to the chromatogram export by m/z, not by order.** When you pair library fragment
  intensities (`RefSpectraPeaks`) with Skyline's extracted fragment XICs (§9) for a spectral-match score,
  align on **m/z** — the export's fragment row order does **not** follow the library's stored peak order.
- RT / peak boundaries live in the `RetentionTimes` table (per-peptide `MIN(startTime)/MAX(endTime)` for the
  union firing window); `PRAGMA table_info(RetentionTimes)` first — older BLIBs lack start/end columns.
  `ScoreTypes.probabilityType` tells you filter direction (q-value lower-is-better vs. score higher-is-better).

### Discovering the active library
`GetSettingsListSelectedItems("Libraries")` → `GetSettingsListItem("Libraries", name)` → parse the library
XML; a BLIB is any root element whose local name starts with `bibliospec`; resolve its path against the
document directory. (Simpler: scan `*.blib` next to the `.sky`, document-named first.)

### ⚠️ Writing a `.blib` (BiblioSpec v8) + registering it
Create schema **majorVersion 1, minorVersion 8** (the version that added `RefSpectra.startTime/endTime`).
Tables: `LibInfo, IonMobilityTypes, ScoreTypes, SpectrumSourceFiles, Proteins, RefSpectraProteins, RefSpectra,
RefSpectraPeaks, Modifications, RetentionTimes`. Write everything in one transaction. Peaks = top-N by
intensity, re-sorted by m/z ascending, m/z as LE doubles + intensity as LE floats, each zlib(RFC-1950)
compressed.

- **UniMod IDs break BiblioSpec's matcher.** `LibKeyModificationMatcher` int-parses bracket contents and
  throws `FormatException: The number 'UniMod:4' is not in the correct format`. Translate `C[UniMod:4]` →
  `C[+57.021464]` (keep a UniMod→mass-delta table) before writing.
- **Write next to a *saved* `.sky`.** Writing to `%TEMP%` reports success but the registration silently drops
  on the next document save.
- **`AddSettingsListItem` can't register a Spectral Library** (the list's `T` is the abstract `LibrarySpec`
  with no static `Deserialize`). Use the CLI path, **path before name**:
  ```csharp
  client.RunCommand(new[] { "--add-library-path=" + blibPath, "--add-library-name=" + assayName });
  ```

### ⚠️ Note on modification formats generally
Skyline exports and BLIB use *different* modification notations: Skyline uses `(unimod:4)` / `[+57.02146]`
depending on the column, BLIB uses `[+57.02146]`. And **I and L are indistinguishable by MS** — decide
explicitly whether to collapse `I↔L` when matching peptides to a library (PRISM keeps them distinct for
library-assist because a detected peptide has its own exact predicted spectrum; FASTA parsimony collapses
them). Getting this wrong silently changes match rates.

---

## 6. Importing results, FASTA, libraries, building a blib (SkylineCmd surface)

These run via `RunCommand([...])` against the live document (or via `SkylineCmd`/`SkylineRunner` headless).
Verified against Skyline 26.1.1 (`--help=sections` lists the categories; `--help` a section for details).

**Import results (chromatograms):**
`--import-file=<raw>` + `--import-replicate-name=<name>`; `--import-all=<folder>` /
`--import-all-files=<folder>` with `--import-naming-pattern` / `--import-filename-pattern` /
`--import-samplename-pattern`; `--import-append`, `--import-before/-on-or-after=<date>`,
`--import-peak-boundaries=<file>`, `--import-warn-on-failure`. Performance: `--import-threads=<n>`
(parallel files, like the UI's "files to import simultaneously"), `--import-process-count=<n>` (sub-processes,
up to ~10× on NUMA servers), `--import-no-join` (write per-file `.skyd` without joining — for HPC).

**Build a document `.blib` from a peptide search** (the real "write blib" path when you have search results):
`--import-search-file=<search results>` (repeatable) builds a document-specific spectral library;
`--import-search-cutoff-score=<0..1>` (default 0.95), `--import-search-add-mods`,
`--import-search-irts=<name>`, `--import-search-include-ambiguous`, `--import-search-prefer-embedded-spectra`.
Add `--import-fasta` to also add the matched peptides as targets.

**Add an existing library:** `--add-library-path=<file>` + `--add-library-name=<name>`.

**Import FASTA / targets:** `--import-fasta=<file>` (`--keep-empty-proteins`);
`--import-transition-list=<csv>` (slow, ~10 rows/s — show a heartbeat); annotations via `--annotation-*`
(§4) or `ImportProperties` CSV.

**Decoys for FDR in scheduled PRM (reversed sequences work).** Scheduled/timed PRM is often assumed to
have "no decoy data" — untrue. A **reversed-sequence** decoy shares its target's amino-acid composition and
therefore its **precursor m/z**, so it falls in the **same scheduled isolation window**, and the instrument
physically recorded its (different) fragment m/z in those MS2 scans. Skyline can therefore extract **real**
decoy chromatograms, and a decoy that is noise can legitimately out-score a target — giving a usable
target/decoy FDR. Recipe: add the reversed peptides under a `decoy_`-prefixed protein (`--import-fasta` /
`--import-transition-list`), extract chromatograms alongside the targets, score, then drop the decoy
protein before write-back.

**Document I/O (headless):** `--in`/`--open`, `--save`/`--out`/`--save-as`, `--new[=path]` (`--overwrite`,
`--discard-changes`), `--share-zip[=…]` (`--share-type=minimal|complete`), `--batch-commands=<file>` (run a
command file against one open document), `--log-file`, `--timestamp`, `--memstamp`.

**Reports (headless):** `--report-name` + `--report-file` + `--report-format=csv|tsv` + `--report-invariant`;
`--report-add=<file>.skyr` + `--report-conflict-resolution=overwrite|skip`. For **parquet**, omit
`--report-format` and give `--report-file` a `.parquet` extension — but see §2 ("Format is chosen by the
FILE EXTENSION"): headless parquet is currently broken by a missing binding in `SkylineCmd.exe.config`.
`--report-name` takes ONE report, so exporting two reports means loading the document twice.

---

## 7. Packaging & installing the tool

### `tool-inf/` manifest (RPC/exe tool)
- `info.properties`: `Name`, `Version` (keep in sync with the assembly version — verify at release),
  `Identifier = URN:LSID:<org>:<Tool>`, `Author`, `Description`.
- `<ToolName>.properties`: `Command=<Tool>.exe`, **`Arguments=$(SkylineConnection)`**, `Title`,
  `InitialDirectory=`, `OutputToImmediateWindow=False`. The properties filename **must match** the
  `Command`/`AssemblyName`.
- Copy both into the build output (`<None Include="tool-inf\..." CopyToOutputDirectory="PreserveNewest" />`).

### Zip
`dotnet msbuild build/package.proj` → `dotnet publish` the WPF app **framework-dependent**
(`--self-contained false /p:UseAppHost=true`, so the user installs the .NET 8 **Desktop** Runtime separately →
small zip) → `ZipDirectory` to `publish/<Tool>.zip`. Stage `tool-inf/` and the `Reports/*.skyr` into the zip.

### Ship gate (learned the hard way)
Automate **test → package → launch-verify** (`package-and-verify.ps1`). The verify step extracts the zip to a
clean dir (fresh-install simulation) and *actually launches* the exe with a dummy connection arg. Because the
WPF window (hence ScottPlot/SkiaSharp/XAML) loads at startup, a broken native dependency shows up as a load
error — grep the tool's log for `Could not load file or assembly | XamlParseException |
TypeInitializationException | DllNotFoundException | BadImageFormatException` and require a
"tool started" line. A failed *connection* from the dummy arg is expected; a failed *load* is not.

### Install
> For an **end-user** (analyst) walkthrough of installing the packaged `.zip` — prerequisites, the
> Tools-menu steps, updating, and troubleshooting — see [installing-a-skyline-tool.md](installing-a-skyline-tool.md).

- **UI:** Tools ▸ Tool Store ▸ *Install from file* (pick the zip).
- **Headless:** `SkylineCmd --tool-add-zip=<zip> --tool-zip-conflict-resolution=overwrite|parallel`
  (`--tool-zip-overwrite-annotations`, `--tool-ignore-required-packages`). Add-by-settings without a zip:
  `--tool-add`, `--tool-command`, `--tool-arguments`, `--tool-report`.
- ⚠️ **Reinstalling over a *running* tool** can leave a **partial extraction** (locked files) that drops
  `deps.json` / DLLs → the tool then fails to load (we hit exactly this as a SkiaSharp
  `FileNotFoundException`). **Close the tool before reinstalling.**

### runtimeconfig / natives
The published `deps.json` must list the native assets that have to survive extraction
(`runtimes/win-x64/native/duckdb.dll`, SkiaSharp/HarfBuzz, `e_sqlite3`). On Linux CI, SkiaSharp needs
`libfontconfig1` + `libfreetype6`.

---

## 8. Project setup / NuGet / architecture

### Layout (cross-platform CLI + Windows tool)
| Project | TFM | Role |
|---|---|---|
| `Core` | `net8.0` | algorithms / IO / QC — **cross-platform, no pipes, no WPF** |
| `Cli` | `net8.0` | the cross-platform command-line entry point (references Core only) |
| `Skyline` | `net8.0-windows` | JSON-RPC client + report/grid/library driver |
| `App` | `net8.0-windows`, WPF | the `.exe` Skyline launches |

### ⚠️ Keep the RPC out of a cross-platform Core
The SkylineTool sources use `System.IO.Pipes` message-mode (Windows-only at runtime). **Link-compile the four
RPC files into the `net8.0-windows` project ONLY** — that's what keeps `Core` (and the CLI) cross-platform.
Set `Nullable disable` on that project (the vendored sources predate nullable refs).
*Cadenza folds the RPC into its Core, making Core Windows-only — fine if you have no cross-platform CLI, but
split it (PRISM-style) if you do.*

### `Directory.Build.props`
- `EnableWindowsTargeting=true` — so the `net8.0-windows`/WPF projects **build on Linux/macOS CI** (their
  tests are gated to the Windows runner).
- Single-source `<Version>`; verify it matches `tool-inf/info.properties` at release.
- ⚠️ **Do NOT set `InvariantGlobalization=true`** — WPF text/font rendering throws `CultureNotFoundException`
  under invariant globalization. Get numeric reproducibility by passing `CultureInfo.InvariantCulture`
  explicitly in every data-output path instead.

### Packages
`Microsoft.Data.Sqlite` (read/write `.blib`), `Parquet.Net` (typed columnar report I/O — pin a version that
decodes Skyline/DuckDB dictionary pages), `DuckDB.NET.Data.Full` (merge/sort large reports; ships the native
engine — pin the version, sort tie-breaks can shift across engine versions), `ScottPlot` (+ `ScottPlot.WPF`
for interactive; SkiaSharp under the hood), `YamlDotNet`, `MathNet.Numerics`.

---

## 9. Chromatograms — getting extracted XICs out of Skyline

Reports (§2) give tabular *aggregates* (areas, RTs). A peak-picking / detection / re-scoring tool needs
the **chromatogram point-arrays** themselves. That's a first-class `SkylineCmd` export — so it works over
`RunCommand` against the live document, **no `.skyd` parsing and no re-import**:
```
--chromatogram-file=<out.tsv> --chromatogram-precursors --chromatogram-products
```
(also `--chromatogram-base-peaks`, `--chromatogram-tics`; each sub-flag **requires** `--chromatogram-file`;
default with none is precursors+products). From a live tool:
`RunCommand(["--chromatogram-file=…","--chromatogram-precursors","--chromatogram-products"])`.

**Format (verified, Skyline-daily 26.1):** tab-delimited, **10 columns**, one row per **(transition,
replicate)**:
`FileName, PeptideModifiedSequence, PrecursorCharge, ProductMz, FragmentIon, ProductCharge,
IsotopeLabelType, TotalArea, Times, Intensities`.
- Row count = transitions × replicates. Precursor and product transitions export together; the precursor
  row has `FragmentIon = precursor` and `ProductMz` = the precursor m/z.
- ⚠️ **`Times` and `Intensities` are comma-separated numeric arrays inside a single tab cell**, equal
  length within a row, invariant-formatted (e.g. `6.400576E+07`). Parse with `CultureInfo.InvariantCulture`;
  split the two cells on `,`.
- **`Times` are in minutes**, on a regular/interpolated grid. ⚠️ **The grid is per (precursor, replicate)**
  — point counts vary across peptides (different scheduled windows), so read each row's own arrays; do NOT
  assume one shared length or axis across peptides or replicates.
- **All fragments of one (FileName, precursor) share one identical `Times` grid** → the precursor is
  already co-aligned, ideal for consensus peak detection / co-elution.
- ⚠️ The point-arrays make this **big**: a 314-precursor × 18-replicate PRM doc → ~50 MB, ~32k rows.
  Stream it with a line reader; don't `File.ReadAllText`.

**Join key.** `PeptideModifiedSequence` + `PrecursorCharge` in the export match the `.blib`
`peptideModSeq`/`precursorCharge` **and** the document **verbatim** (same `C[+57]…` bracket format) — join
on `(PeptideModifiedSequence, PrecursorCharge)` with no normalization. (If your library came from
elsewhere, mind §5's modification-format and I/L caveats.)

### ⚠️ Scheduled PRM: the XIC extent already *is* the RT window
On a scheduled/timed acquisition the instrument only records MS2 for a precursor **inside its scheduled RT
window**, so the extracted chromatogram contains **no data outside that window** — the XIC extent *is* the
hard RT limit. Layering a second `±` RT gate on top (around a predicted RT) is redundant and actively
harmful when the predicted RT is off: it can exclude the true peak the instrument actually recorded. Treat
the scheduling window (the XIC extent) as the only hard RT bound, and use any expected RT as a **soft
prior** within it, not a cutoff.
- **Prefer the document's `ExplicitRetentionTime` (the RT the run was *scheduled* on) over the spectral
  library's predicted RT** as that expected RT. The acquisition was scheduled on the document RT, so the
  data — and the true peak — sit there; even a fine-tuned library RT prediction can be off by >0.5 min for
  a minority of peptides (a ~7% tail in one real dataset), which a tight RT gate then mis-reads. Export it
  with a report selecting `ModifiedSequence` + `PrecursorCharge` + `ExplicitRetentionTime` (§2).

**Write-back** the peaks you pick with `--import-peak-boundaries=<csv>` (§6, but mind the two gotchas
below); write per-precursor scores (q-value/PEP/detection flags) as document annotations via
`--annotation-*` + `ImportProperties` (§4).

### ⚠️ Writing peak boundaries back (`--import-peak-boundaries`)
Two gotchas here each cost real time to discover:
- **Rows match by the raw *file* name, not the replicate name.** Replicates are frequently renamed (file
  `2026-06-22-…-PRM-002.raw` → replicate `PRM-002`), but the boundaries file's `FileName` column must carry
  the **file** name; the import **silently skips** any row it can't match. Confirm the write-back actually
  moved a boundary rather than trusting a clean exit.
- **Turn off Skyline's own peak algorithms first, or they quietly overrule you.** Peptide Settings ▸
  Prediction peak-boundary **imputation** (`impute_missing="true"`, `max_rt_shift`, `max_peak_width_var`)
  will **re-impute** any boundary you move more than `max_rt_shift` (e.g. 0.1 min) from the consensus, and
  an active mProphet peak-scoring model can re-pick — so your imported boundaries look like they never
  applied (peaks display at the predicted RT, not your pick). These are GUI-only settings today (no
  `SkylineCmd` flag exposed under Peptide Settings), so a production tool should write them into the
  document settings itself.

### A "Candidate Peaks" diagnostic view earns its keep
When a tool re-scores or re-picks peaks, expose a per-candidate score breakdown — every detector candidate
with its **combined** score *and* the individual term contributions, which candidate was chosen, and any
post-processing / reconciliation action taken — mirroring Skyline's own **View ▸ Live Reports ▸ Candidate
Peaks**. It turns "why did it pick *that* peak?" from a debugging session into a glance, for you and the
analyst alike.

---

## 10. Reading the raw `.sky` XML directly

Some inputs are easier to read straight from the `.sky` (it's XML) than through the RPC. Use a streaming
`XmlReader` and **stop early** — the peptide/results tree that follows the settings can be huge. Two we
needed:

**Instrument tolerances — so an embedded engine matches how Skyline extracted.** The chromatograms were
extracted with the document's transition settings; an in-process scorer must match with the *same*
tolerances, not a guess.
```xml
<transition_settings>
  <transition_instrument mz_match_tolerance="0.055" .../>
  <transition_full_scan acquisition_method="PRM"
      product_mass_analyzer="qit" product_res="0.5"
      precursor_mass_analyzer="qit" precursor_res="0.7" .../>
</transition_settings>
```
`product_mass_analyzer = qit` (or `ion_trap`) → **unit resolution**, and `product_res` / `precursor_res`
are the m/z extraction widths in Th; high-res analyzers (`orbitrap` / `tof` / `ft`) report resolving power
instead. Fall back to `transition_instrument/@mz_match_tolerance` when full-scan res is absent.
(`GetDocumentSettings` (§4) also writes this XML if you'd rather not open the `.sky`.)

**Raw file paths + availability.** Each imported run is a `sample_file`:
```xml
<measured_results><replicate name="PRM-001">
  <sample_file id="…" file_path="D:\data\PRM-001.raw" .../>
</replicate>…</measured_results>
```
Read `sample_file/@file_path`. ⚠️ Skyline appends a multi-sample selector after `|` or `?` for
wiff/multi-injection files — strip to the first segment before `File.Exists` / `Directory.Exists` (a raw
source can be a file **or** a `.d` directory). **If a raw file is missing, tell the user which outputs are
therefore unavailable** rather than silently producing a smaller result — e.g. features that need the
observed MS2 spectra can't be computed when the raw has moved. Graceful degradation + a clear warning
beats a silently truncated answer.

---

## 11. Embedding a pwiz / ProteoWizard engine in-process (project references)

An advanced tool can reuse a pwiz engine (Osprey's scoring/FDR, a spectrum reader, …) **in-process**
instead of shelling out. The Osprey projects are SDK-style, multi-target **`net472;net8.0`**, `AnyCPU;x64`,
and build standalone (`dotnet build`), so a `net8.0` tool project references them directly:
```xml
<PropertyGroup>
  <!-- point at the pwiz checkout; override with -p:OspreyDir=… or the OSPREY_DIR env var -->
  <OspreyDir Condition="'$(OspreyDir)'==''">$(OSPREY_DIR)</OspreyDir>
  <OspreyDir Condition="'$(OspreyDir)'==''">D:\Dev\pwiz\pwiz_tools\Osprey</OspreyDir>
</PropertyGroup>
<ItemGroup>
  <ProjectReference Include="$(OspreyDir)\Osprey.Scoring\Osprey.Scoring.csproj" />
  <ProjectReference Include="$(OspreyDir)\Osprey.FDR\Osprey.FDR.csproj" />
  <!-- Osprey.Core / Osprey.Chromatography come transitively -->
</ItemGroup>
```
- A `net8.0` project referencing a multi-target project resolves the **net8.0** target automatically; it
  won't try to build net472.
- The referenced project keeps **its own** `Directory.Build.props` (Osprey is `Nullable disable`), so it
  won't inherit yours; your nullable-enabled adapter consumes the engine's oblivious types fine — annotate
  null-returning members `T?` to silence CS8603.
- ⚠️ **Type-name collisions.** Both your `Core` and the engine may define e.g. `LibraryEntry` / `XicData`.
  Alias in the consuming file: `using LibraryEntry = pwiz.Osprey.Core.LibraryEntry;`.
- ⚠️ Two related types can live in **different assemblies** (Osprey's `XicData` is in
  `Osprey.Chromatography`, `XICPeakBounds` in `Osprey.Core`) — reference both.
- **The bridge is an adapter**: implement the engine's peak-data *interface* over Skyline's exported XICs
  and pass it to the engine's public calculator registry — no engine edits for the XIC-only path. Where a
  score depends on a byproduct the engine's own harness publishes (e.g. Osprey's median-polish fit),
  replicate that publish step exactly, or the feature silently returns its default.
- Prototype the references in your own repo; if the facade is meant to be **upstreamed into pwiz**, port it
  there once the science is proven — it must then follow pwiz house style (CRLF, **no `async`/`await`**,
  resource strings, `quickbuild`, helpers after callers).

---

## 12. Developing against a live Skyline (the `skyline` MCP server)

Skyline-daily exposes an **MCP server** over the same JSON pipe as §1, so an AI agent can drive a running
Skyline directly while developing — script the export/annotation round-trip without hand-clicking or
writing a throwaway RPC harness. The tools mirror the RPC/CLI surface: `skyline_run_command` (**any**
`SkylineCmd` flag — `--chromatogram-file`, `--import-peak-boundaries`, `--annotation-*`),
`skyline_get_document_status` (fast doc overview — type, target/replicate counts, path),
`skyline_get_document_settings` (settings XML), `skyline_get_report_from_definition` (ad-hoc reports via a
JSON `select`/`filter`/`sort`), `skyline_get_document_path`, `skyline_get_graph_data` (spot-check an
exported trace against Skyline's chromatogram graph).
- ⚠️ **Multiple Skyline windows** → calls go to the *most-recently-connected* instance. List with
  `skyline_get_instances` (PID, version, document) and **pin** the one you mean via
  `skyline_set_instance(pid)` before anything mutating — otherwise you may drive the wrong document.
- Report-definition column names are the **databinding** names (`IsDecoy`, not `PrecursorIsDecoy`); on a
  bad name the error suggests the right one — read it.
- This is a **development aid**, not part of the shipped tool; the tool itself uses the vendored RPC
  client (§1).

### Running a headless `SkylineCmd` alongside the live GUI
For extraction / re-import experiments you can run `SkylineCmd.exe` against a **copy** of the document
without disturbing the user's open session. ⚠️ Use the `SkylineCmd.exe` that sits in the **ClickOnce
application folder next to `Skyline(-daily).exe`** — the `SkylineCmd.exe` in the sibling `…exe_…` folders
fails with *"Unable to find Skyline.exe"*. Always work on a copy so a mistaken `--save` can't touch the
live document.

---

## 13. Checklist for the next agent

1. **Connection:** transform `args[0]` with `GetJsonPipeName`; connect **per call**; `ReadMode=Message`. If you
   see `0x00 is invalid start of value`, it's one of these three.
2. **Reports:** invariant culture; export-to-file (validate `PAR1`) beats paginating; ship `.skyr` and install
   with `--report-add … --report-conflict-resolution=overwrite`.
3. **Replicates/grid:** it's **not** a report — `GetReportDocTopic("Replicate","document_grid")` +
   `GetReportFromDefinitionRows(DataSource="document_grid")`; `count=0` → shape only; anything not a built-in
   column is a user annotation (`annotation_<Name>`), keep it.
4. **Settings / import / build-blib:** almost everything is a `SkylineCmd` flag via `RunCommand`
   (§6) — one flag per batch except mutually-validated fields; `RunCommand` aborts the batch on the first bad
   arg.
5. **BLIB:** `Pooling=False`; guard the zlib `0x78 0x9C` magic; write BiblioSpec v8 in one transaction; convert
   UniMod IDs to mass deltas; register with `--add-library-path` (path before name), next to a **saved** `.sky`.
6. **Packaging:** `Arguments=$(SkylineConnection)`; framework-dependent publish; a launch-verify ship gate;
   close the tool before reinstalling.
7. **Architecture:** RPC only in the `net8.0-windows` project; `EnableWindowsTargeting`; no
   `InvariantGlobalization`.
8. **Chromatograms (§9):** `--chromatogram-file` (+ `--chromatogram-precursors`/`-products`) → 10-col TSV;
   `Times`/`Intensities` are comma arrays in one cell, minutes, **per-precursor grid** (read each row's
   own arrays); join on `(PeptideModifiedSequence, PrecursorCharge)`; stream it. **Write-back:**
   `--import-peak-boundaries` matches by the raw **file** name, and Skyline's own boundary imputation /
   mProphet model will overrule your picks unless disabled; on scheduled PRM treat the XIC extent as the
   hard RT bound and use `ExplicitRetentionTime` as a soft prior, not a second RT gate.
9. **Raw `.sky` (§10):** parse `transition_full_scan` for analyzer/res tolerances and
   `sample_file/@file_path` for raw availability (strip the `|`/`?` selector); **warn**, don't silently
   drop, when a raw file is missing.
10. **Embedding pwiz (§11):** project-reference the multi-target (`net472;net8.0`) engine projects behind
    an overridable `$(EngineDir)`; alias colliding type names; bridge with an adapter over the engine's
    peak-data interface; replicate any harness-published byproduct.

## 14. Source map (where each capability lives)
- RPC client/models: `dotnet/external/SkylineTool/{SkylineJsonToolClient,IJsonToolService,JsonToolConstants,JsonToolModels}.cs`
- Connection + seam: `SkylinePrism.Skyline/{SkylineSession,ISkylineClient}.cs`
- Reports / grid / annotations driver: `SkylinePrism.Skyline/SkylineReportDriver.cs` + `Reports/*.skyr`
- BLIB read: `SkylinePrism.Core/Library/SpectralLibrary.cs`
- BLIB **write** + RT read + discovery + settings write-back: **cadenza** —
  `SkylineCadenza.Core/{Output/BlibAssayWriter.cs, Ingest/BlibRetentionTimeReader.cs, Ingest/SkylineBlibDiscovery.cs,
  SkylineRpc/SkylineSettingsConfigurator.cs}`, `App/ViewModels/MainViewModel.cs`, `docs/skyline-integration.md`
- Packaging: `dotnet/build/{package.proj,package-and-verify.ps1,verify-tool.ps1}`, `App/tool-inf/*`,
  `Directory.Build.props`
- Classic report-macro tool (contrast): `skyline-prism/skyline-external-tool/tool-inf/{PRISM,info}.properties`
- Chromatogram (XIC) export + parse (§9): **skyline-osprey-tool** —
  `dotnet/src/OspreyTool.Core/ChromatogramTsvReader.cs`, `docs/data-formats.md`
- Raw `.sky` XML parsing (§10): **skyline-osprey-tool** —
  `dotnet/src/OspreyTool.Core/{SkylineTransitionSettings,RawFileAvailability}.cs`
- Embedding a pwiz engine + adapter (§11): **skyline-osprey-tool** —
  `dotnet/src/OspreyTool.Scoring/{OspreyTool.Scoring.csproj, OspreyFeatureScorer.cs, XicPeakData.cs}`,
  `docs/osprey-api.md`
