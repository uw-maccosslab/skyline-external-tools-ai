# `--new` hangs through SkylineRunner

`skylinerunner-stall-repro.ps1` runs four commands side by side and prints, for each, the exact
command line, the expected result and the actual one. It finds `SkylineDailyRunner.exe` and
`SkylineCmd.exe` itself, creates its own scratch document, and kills the headless Skyline that the
stalled runner leaves behind.

```powershell
pwsh -File skylinerunner-stall-repro.ps1
pwsh -File skylinerunner-stall-repro.ps1 -TimeoutSec 300 -ReportName MyReport
```

## Observed

Skyline-daily **26.1.1.209-61fa751304**, Windows 11, with an interactive Skyline-daily instance open
throughout (an untested variable — see below).

| # | Command | Result |
|---|---------|--------|
| 1 | `SkylineCmd --new=scratch.sky --overwrite --save` | exit 0 in **~1 s**, document written |
| 2 | `SkylineDailyRunner --new=fresh.sky --overwrite --save` | **hangs** — prints `File fresh.sky opened.` and nothing more; document never written |
| 3 | `SkylineDailyRunner --in=scratch.sky --report-name=PRISM --report-file=report.parquet` | exit 0 in **~1.7 s**, valid `PAR1…PAR1` parquet |
| 4 | `SkylineCmd --in=scratch.sky --report-name="Peptide Ratio Results" --report-file=skylinecmd.parquet` | exit 2: `Could not load file or assembly 'Parquet, Version=4.0.0.0…'` |

Cases 1 and 3 are the controls that make case 2 interesting: the runner is fine (3), and the command
is fine (1). It is `--new` **through the runner** that hangs. Case 2 was left running for up to
150 s here, and for 5 minutes in the original observation, with no further output.

Case 4 is context rather than part of the bug: it records why a tool reaches for the runner at all,
since `SkylineCmd` cannot write parquet (`SkylineCmd.exe.config` lacks the Parquet.Net binding).
Between 2 and 4, a tool that wants both a scratch document and parquet has no single entry point that
does both.

## Where it was first hit

Reading a DIA acquisition's isolation windows out of a raw file, which runs against a throwaway
document so the user's is never modified:

```
--new=<temp>.sky --overwrite --full-scan-acquisition-method=DIA
--full-scan-isolation-scheme=<data file> --save
```

Through `SkylineCmd`: 167 windows from a 4.86 GB Thermo `.raw` in **8.7 s**. Through the runner: the
`File …opened.` line and then silence, killed at 5 minutes, never reaching `Reading isolation scheme
from …`.

## Not root-caused

- An interactive Skyline-daily was running during every observation. Whether the runner contends with
  or routes into an existing ClickOnce instance is untested.
- The stalled process has **no main window**, so it is not sitting on a visible dialog — though that
  does not rule out a modal it cannot show.
- It reproduces with the **official** `SkylineDailyRunner.exe`, so it is not a defect in a
  reimplementation of the SkylineRunner protocol.

## Two side findings

- **Both entry points re-split their command line.** `--report-name=Peptide Ratio Results` arrives as
  `Peptide` unless the whole parameter is quoted. The script quotes any argument containing a space.
- **`SkylineCmd` does not see reports installed into Skyline's user settings by a tool.** The same
  `--report-name=PRISM` that case 3 exports fails there with `The report PRISM does not exist`, which
  is why case 4 uses a built-in report.
