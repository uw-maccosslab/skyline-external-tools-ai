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

## Culture & globalization (§8)
- **`CultureInfo.InvariantCulture` in every data parse/format path.** Skyline exports invariant
  (`.` decimal, `6.4E+07`); parse/write invariant.
- Reports/RPC: pass `culture = "invariant"` for machine consumption.
- **Never set `InvariantGlobalization=true`** — WPF text rendering throws `CultureNotFoundException`.

## SkylineCmd via RunCommand (§4, §6)
- **One flag per `RunCommand` batch** — SkylineCmd aborts the *whole batch* on the first bad arg. EXCEPT
  mutually-validated fields (DIA acquisition-method + isolation-scheme; MS1 count + analyzer + ppm) which
  must go together.

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
- Ship without the launch-verify gate.
