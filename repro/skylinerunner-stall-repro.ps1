# Repro: SkylineRunner (the headless "drive the installed Skyline" path) stalls after opening the
# document and never executes the rest of the command line.
#
# Observed on Skyline-daily 26.1.1.209-61fa751304, Windows 11, with an interactive Skyline-daily
# instance open at the same time.
#
#   SkylineDailyRunner.exe --new=<temp>.sky --overwrite --save
#     -> prints "File <name>.sky opened."
#     -> then nothing; the document is never saved; the process never exits
#
# The SAME command through SkylineCmd.exe completes in ~1 s and writes the file.
#
# Usage:  pwsh -File skylinerunner-stall-repro.ps1
#         pwsh -File skylinerunner-stall-repro.ps1 -TimeoutSec 300

param(
    [int]$TimeoutSec = 150,
    [string]$Runner,
    [string]$SkylineCmd
)

$ErrorActionPreference = 'Stop'
$tmp = Join-Path $env:TEMP ("skylinerunner-stall-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force $tmp | Out-Null

function Find-One([string]$name) {
    Get-ChildItem "$env:LOCALAPPDATA\Apps\2.0", "$env:USERPROFILE\.skyline-mcp" -Recurse -Filter $name `
        -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

if (-not $Runner)     { $Runner     = Find-One "SkylineDailyRunner.exe" }
# SkylineCmd.exe must be the copy that sits BESIDE Skyline-daily.exe (the ClickOnce *application*
# folder); the copies in the sibling "...exe_..." folders fail with "Unable to find Skyline.exe".
if (-not $SkylineCmd) {
    $SkylineCmd = Get-ChildItem "$env:LOCALAPPDATA\Apps\2.0" -Recurse -Filter "SkylineCmd.exe" -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.DirectoryName "Skyline-daily.exe") } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

"runner     : $Runner"
"skylinecmd : $SkylineCmd"
"scratch    : $tmp"
""

function Invoke-Case([string]$label, [string]$exe, [int]$timeoutSec) {
    if (-not $exe) { "$label : executable not found"; return }
    $doc = Join-Path $tmp ((Split-Path $exe -Leaf) + ".sky")
    $out = Join-Path $tmp ((Split-Path $exe -Leaf) + ".out.txt")
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $exe -ArgumentList "--new=$doc", "--overwrite", "--save" `
        -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    if ($p.WaitForExit($timeoutSec * 1000)) {
        "$label : exited code=$($p.ExitCode) after {0:N1}s" -f $sw.Elapsed.TotalSeconds
    } else {
        "$label : STALLED - still running after {0:N0}s" -f $sw.Elapsed.TotalSeconds
        $p.Kill(); $p.WaitForExit()
    }
    if (Test-Path $out) { Get-Content $out | ForEach-Object { "           | $_" } }
    "           document written: $(Test-Path $doc)"
    ""
}

Invoke-Case "SkylineCmd " $SkylineCmd 120
Invoke-Case "DailyRunner" $Runner     $TimeoutSec

# The runner leaves its headless Skyline behind when it stalls: no window, and not the user's.
Get-Process Skyline-daily -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -eq 0 } |
    ForEach-Object { "cleanup: killing stray headless Skyline-daily pid $($_.Id)"; $_.Kill() }
