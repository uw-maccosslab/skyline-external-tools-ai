# Repro: SkylineRunner hangs on --new, but only on --new.
#
# Observed on Skyline-daily 26.1.1.209-61fa751304, Windows 11, with an interactive Skyline-daily
# instance open at the same time.
#
#   SkylineDailyRunner.exe --new=x.sky --overwrite --save
#     -> prints "File x.sky opened."
#     -> then nothing: the file is never written and the process never exits
#
# Two controls show how narrow this is:
#   * SkylineCmd.exe runs the IDENTICAL --new command in ~1 s and writes the file.
#   * SkylineDailyRunner.exe runs --in=<existing>.sky + a report export in ~1.5 s, exit 0.
#
# So it is not the runner in general, and not the SkylineRunner protocol - it is --new through the
# runner specifically.
#
# A fourth case records a separate, already-known limitation for completeness: SkylineCmd cannot
# write parquet at all (its .exe.config lacks the Parquet.Net assembly binding), which is why tools
# use the runner for report export in the first place.
#
# Usage:  pwsh -File skylinerunner-stall-repro.ps1
#         pwsh -File skylinerunner-stall-repro.ps1 -TimeoutSec 300 -ReportName MyReport
#
# -ReportName must NOT contain spaces: SkylineRunner re-splits its command line, so a spaced report
# name arrives truncated ("The report Peptide does not exist"). Any space-free report in your Skyline
# settings works; PRISM installs one called "PRISM".
#
# Noted in passing: BOTH entry points re-split their command line, so any argument containing a space
# must be quoted by the caller. And SkylineCmd does not see reports installed into Skyline's user
# settings by a tool.
# The same "--report-name=PRISM" that case 3 exports through the runner fails through SkylineCmd with
# "The report PRISM does not exist", which is why case 4 uses a built-in report instead.

param(
    [int]$TimeoutSec = 120,
    [string]$ReportName = "PRISM",
    # Case 4 goes through SkylineCmd, which does NOT see reports a tool installed into Skyline's user
    # settings - "--report-name=PRISM" succeeds through the runner and fails here on the same machine.
    # So case 4 uses a built-in report. Its spaces are handled by the quoting in Invoke-Case.
    [string]$BuiltInReportName = "Peptide Ratio Results",
    [string]$Runner,
    [string]$SkylineCmd
)

$ErrorActionPreference = 'Stop'
# No spaces in the scratch path, for the same re-splitting reason.
$tmp = Join-Path $env:TEMP ("skylinerunner-repro-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force $tmp | Out-Null

if (-not $Runner) {
    $Runner = Get-ChildItem "$env:LOCALAPPDATA\Apps\2.0", "$env:USERPROFILE\.skyline-mcp" -Recurse `
        -Filter "SkylineDailyRunner.exe" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
# SkylineCmd.exe must be the copy BESIDE Skyline-daily.exe (the ClickOnce *application* folder);
# the copies in the sibling "...exe_..." folders fail with "Unable to find Skyline.exe".
if (-not $SkylineCmd) {
    $SkylineCmd = Get-ChildItem "$env:LOCALAPPDATA\Apps\2.0" -Recurse -Filter "SkylineCmd.exe" -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.DirectoryName "Skyline-daily.exe") } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

"runner     : $Runner"
"skylinecmd : $SkylineCmd"
"scratch    : $tmp"
""

function Invoke-Case {
    param([string]$Label, [string]$Exe, [string[]]$Arguments, [int]$Timeout, [string]$Expect)
    if (-not $Exe) { Write-Host "$Label : executable not found`n"; return }
    $log = Join-Path $tmp ([guid]::NewGuid().ToString("N").Substring(0, 6) + ".log")
    $sw = [Diagnostics.Stopwatch]::StartNew()
    # Both Skyline entry points re-split their command line, and Start-Process joins the array
    # without quoting - so an argument containing a space has to carry its own quotes, exactly as
    # Skyline's own error advises ("use \"double quotes\" around the entire list of command parameters").
    $quoted = $Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
    $p = Start-Process -FilePath $Exe -ArgumentList $quoted -NoNewWindow -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    $exited = $p.WaitForExit($Timeout * 1000)
    if (-not $exited) { $p.Kill(); $p.WaitForExit() }
    $sw.Stop()

    Write-Host $Label
    # Echo the command verbatim. A repro that only prints a label asks the reader to take the
    # description on trust - and the arguments are the thing under test here.
    Write-Host ("  command : " + (Split-Path $Exe -Leaf) + " " + ($quoted -join " "))
    Write-Host "  expected: $Expect"
    Write-Host ("  actual  : " + $(if ($exited) { "exited code=$($p.ExitCode) after {0:N1}s" -f $sw.Elapsed.TotalSeconds }
                                   else { "STALLED - still running after {0:N0}s" -f $sw.Elapsed.TotalSeconds }))
    Get-Content $log -ErrorAction SilentlyContinue | Select-Object -First 8 | ForEach-Object { Write-Host "          | $_" }
    Get-Content "$log.err" -ErrorAction SilentlyContinue | Select-Object -First 4 | ForEach-Object { Write-Host "          ! $_" }
    Write-Host ""
}

function Show-Parquet([string]$Path) {
    if (-not (Test-Path $Path)) { Write-Host "          -> no output file`n"; return }
    $b = [IO.File]::ReadAllBytes($Path)
    $h = [Text.Encoding]::ASCII.GetString($b[0..3])
    $t = [Text.Encoding]::ASCII.GetString($b[($b.Length - 4)..($b.Length - 1)])
    Write-Host ("          -> {0:N0} bytes, head='{1}' tail='{2}' : {3}" -f $b.Length, $h, $t,
        $(if ($h -eq 'PAR1' -and $t -eq 'PAR1') { 'VALID PARQUET' } else { 'NOT parquet' }))
    Write-Host ""
}

$scratchDoc = Join-Path $tmp "scratch.sky"

"=== 1. CONTROL: --new through SkylineCmd (also creates the document case 3 opens) ==="
Invoke-Case "SkylineCmd --new" $SkylineCmd @("--new=$scratchDoc", "--overwrite", "--save") 120 `
    "exit 0 in ~1 s, document written"
"          document written: $(Test-Path $scratchDoc)"
""

"=== 2. THE BUG: the same --new through SkylineRunner ==="
$newDoc = Join-Path $tmp "fresh.sky"
Invoke-Case "Runner --new" $Runner @("--new=$newDoc", "--overwrite", "--save") $TimeoutSec `
    "STALL after 'File fresh.sky opened.'"
"          document written: $(Test-Path $newDoc)"
""

"=== 3. CONTROL: --in through the SAME runner (report export to parquet) ==="
$parquet = Join-Path $tmp "report.parquet"
if (Test-Path $scratchDoc) {
    Invoke-Case "Runner --in" $Runner @("--in=$scratchDoc", "--report-name=$ReportName", "--report-file=$parquet") 180 `
        "exit 0 in ~1.5 s, valid parquet"
    Show-Parquet $parquet
} else {
    "  skipped: case 1 produced no document to open"; ""
}

"=== 4. CONTEXT: parquet through SkylineCmd (known to be unsupported) ==="
$cmdParquet = Join-Path $tmp "skylinecmd.parquet"
if (Test-Path $scratchDoc) {
    Invoke-Case "SkylineCmd parquet" $SkylineCmd @("--in=$scratchDoc", "--report-name=$BuiltInReportName", "--report-file=$cmdParquet") 120 `
        "exit 2: Could not load file or assembly 'Parquet'"
    Show-Parquet $cmdParquet
} else {
    "  skipped: case 1 produced no document to open"; ""
}

# A stalled runner leaves its headless Skyline behind: no main window, and not the user's instance.
Get-Process Skyline-daily -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -eq 0 } |
    ForEach-Object { "cleanup: killing stray headless Skyline-daily pid $($_.Id)"; $_.Kill() }
