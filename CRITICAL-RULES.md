# CRITICAL RULES

The handful of things that, if you get them wrong, cost hours. Each is a hard-won gotcha from
`docs/skyline-external-tools.md` (section refs below). Bare constraints only — details in the guide.

## JSON-RPC connection (§1)
- **Transform `args[0]`** — Skyline passes the *legacy* pipe name; the JSON server listens on a derived
  name. Connect to it raw and the first read fails with `0x00 is invalid start of value`. Use
  `JsonToolConstants.GetJsonPipeName(raw)`.
- **Connect PER CALL** — Skyline closes the pipe after each request. Never hold it open; open a fresh
  `NamedPipeClientStream` every call.
- **`pipe.ReadMode = PipeTransmissionMode.Message`** — mandatory, or the response read never completes.
- Same `0x00` symptom → it's one of these three.

## Selection sync (§4)
- **There are no events — poll.** The transport is request/response only; Skyline never calls you back,
  so a plot that follows the selection must ask. Poll **only while the view is on screen**, off the UI
  thread, never overlapping the previous poll, and stop on close.
- **`GetSelectedElementLocator(type)` returns the ANCESTOR at that level** — ask for the level your plot
  shows (`MoleculeGroup` / `Molecule`) and let Skyline walk the tree, instead of parsing what the user
  clicked. Verified: with a peptide selected, `MoleculeGroup` → `MoleculeGroup:/sp|P58252|EF2_MOUSE`.
- **Resolve both directions through the same `GetLocations` map** so following a selection is a dictionary
  hit on a string Skyline produced, not a second naming scheme that drifts from the first.

## Culture & globalization (§8)
- **`CultureInfo.InvariantCulture` in every data parse/format path.** Skyline exports invariant
  (`.` decimal, `6.4E+07`); parse/write invariant.
- Reports/RPC: pass `culture = "invariant"` for machine consumption.
- **Never set `InvariantGlobalization=true`** — WPF text rendering throws `CultureNotFoundException`.

## Reports & annotation columns (§2, §3)
- **Annotation columns in a `.skyr` must be prefixed AND quoted** —
  `<column name="&quot;annotation_Batch&quot;" />`. `column/@name` is a databinding PropertyPath whose
  bare-identifier syntax rejects `_`, and `annotation_` contains one. Unquoted → *"Error parsing
  annotation_Batch at location 10: Invalid character _"* and **no report file is written** (looks like a
  missing column, not a failure).
- **Parquet is chosen by the FILE EXTENSION, never by `--report-format`** (which takes only `csv|tsv`) —
  in both `ExportReport` (RPC) and `--report-file=….parquet` headless. Always validate the `PAR1` magic
  at head+tail and keep a CSV fallback: a failed parquet write can still leave a stub.
- **Headless: drive `Skyline.exe` (SkylineRunner), not `SkylineCmd.exe`.** SkylineCmd's parquet export is
  broken — `SkylineCmd.exe.config` lacks the Parquet.Net `<assemblyBinding>` that `Skyline.exe.config`
  has (the managed assembly ships as `ParquetNet.dll` and needs a `codeBase`, because a *native*
  `parquet.dll` owns the default probe path) → *"Could not load file or assembly 'Parquet' … expected to
  contain an assembly manifest."* The SkylineRunner protocol (§2) runs the real app, so parquet works.
- **SkylineRunner has no exit code** — the launcher `cmd.exe` returns immediately. Detect failure from an
  `Error:` prefix at line start (or after a tab) in the piped output, or you will report failures as
  successes.
- **`--new` through the SkylineRunner path HANGS; use `SkylineCmd` for scratch documents** (§4).
  Observed on Skyline-daily 26.1.1.209: `SkylineDailyRunner.exe --new=x.sky --overwrite --save` prints
  `File x.sky opened.` and then nothing, forever, never writing the file. Same machine, same minute:
  `SkylineCmd.exe` runs the identical arguments in 0.9 s, and the runner runs `--in=<existing>.sky` +
  a parquet report export in 1.6 s, exit 0. So `--in` is fine and report export is unaffected — it is
  `--new` specifically. Reproduces with the OFFICIAL runner (`repro/`), so it is not a reimplementation
  bug. Root cause unknown.
- **Quote any argument containing a space yourself.** BOTH entry points re-split their command line:
  `--report-name=Peptide Ratio Results` arrives as `Peptide` unless the whole parameter is quoted.
- **`SkylineCmd` does not see reports a tool installed into Skyline's user settings.** The same
  `--report-name=PRISM` that exports through the runner fails there with "The report PRISM does not exist".
- **Put a DEADLINE on every headless call.** No exit code and output-pipe-only reporting (above) means a
  stall looks exactly like slow work — a blocking `ReadLine` on that pipe hangs forever and never sees
  cancellation. Read on a worker, wake on a timer, and kill the Skyline you started when you give up
  (it is not your child process: the ClickOnce launcher exits immediately, so find it by diffing the
  process list around launch and requiring `MainWindowHandle == 0`, or you may kill the user's).
- **Never block the user's real work on an optional probe.** If the data is an enrichment (a plot's
  metadata, say), run it alongside the main job, not in front of it.

## SkylineCmd via RunCommand (§4, §6)
- **One flag per `RunCommand` batch** — SkylineCmd aborts the *whole batch* on the first bad arg. EXCEPT
  mutually-validated fields (DIA acquisition-method + isolation-scheme; MS1 count + analyzer + ppm) which
  must go together.
- **`SkylineCmd.exe` lives next to `Skyline(-daily).exe`** in the ClickOnce *application* folder
  (`%LOCALAPPDATA%\Apps\2.0\**\skyl..tion_*\`); the copy in the sibling `…exe_…` folders fails with
  *"Unable to find Skyline.exe"*. Pick the newest, and never pass `--save` when reading a user's document.
- **Any command that writes settings runs against a `--new` scratch document**, never the user's — a
  document opened with `--in` and mutated is dirtied even without `--save`.

## DIA isolation windows (§4)
- **Not in the `.sky`** for a normal analysis document (`<isolation_scheme name="Results only" />` has no
  windows), and **not in any report column** — `ChromatogramExtractionWidth` is the *product-ion* channel.
- Get them with **`--full-scan-isolation-scheme=<data file>`** (Skyline reads the vendor file) against a
  throwaway `--new` document. ~10 s for a 5.2 GB `.raw`.
- **Never substitute a uniform bin width.** Forbidden-zone edges land at e.g. 400.4319 with widths an
  integer multiple of ~1.0005 m/z; a round grid is offset ~14% of a window.
- `GetSettingsListSelectedItems` **throws** for isolation schemes — the active one is a document property.

## `.blib` SQLite (§5)
- **`Pooling=False`** in the connection string, or you lock the user's library.
- Detect zlib peak blobs **by length** (`blob.Length == numPeaks*sizeof` → raw, else inflate) — not by
  matching `0x78 0x9C` (the 2nd header byte varies with compression level).
- Writing: BiblioSpec v8, one transaction, convert `UniMod:N` → mass deltas, write next to a **saved**
  `.sky`, register with `--add-library-path` **before** `--add-library-name`.

## Chromatograms (§9)
- `Times`/`Intensities` are **comma arrays in one tab cell**; RT in **minutes**; the grid is **per
  (precursor, replicate)** — read each row's own arrays. Stream large files.

## Reading the `.sky` (§10)
- Strip the `|`/`?` multi-sample selector from `sample_file/@file_path` before `File.Exists`.
- **Warn** when a raw file is missing (so scores that need observed spectra are visibly skipped) — never
  silently drop outputs.

## Project architecture (§8, §11)
- **RPC sources go in the `net8.0-windows` project ONLY** (`System.IO.Pipes` message-mode is Windows-only)
  — that keeps `Core`/`Cli` cross-platform. Set `Nullable disable` on that project (vendored sources
  predate nullable refs).
- `EnableWindowsTargeting=true` so the Windows/WPF projects build on Linux/macOS CI.
- Embedding a pwiz engine: project-reference the multi-target (`net472;net8.0`) projects; **alias colliding
  type names**; two related types can live in different assemblies.

## Packaging (§7)
- `Arguments=$(SkylineConnection)`; the `<ToolName>.properties` filename **must match** the `Command`/
  `AssemblyName`.
- Publish **framework-dependent** (user installs the .NET 8 Desktop Runtime once → small zip).
- **Launch-verify ship gate** — extract to a clean dir, launch the exe, grep the log for load failures.
- **Close the tool before reinstalling** — a running tool leaves a partial extraction (locked DLLs).

## NEVER
- Hold the RPC pipe open across calls, or connect to the raw `args[0]` name.
- Parse localized numbers / omit InvariantCulture.
- Set `InvariantGlobalization=true`.
- Leave `.blib` connection pooling on.
- Poll Skyline from a view that is not on screen, or on the UI thread.
- Block the user's real work on an optional enrichment.
- Ship without the launch-verify gate.
