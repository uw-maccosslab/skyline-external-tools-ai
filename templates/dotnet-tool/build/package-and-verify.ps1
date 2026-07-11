#requires -Version 7
<#
.SYNOPSIS
  Ship gate: test -> publish (framework-dependent) -> zip -> launch-verify.
.DESCRIPTION
  The launch-verify step extracts the zip to a clean directory (fresh-install simulation) and launches the
  exe with a dummy connection arg. A broken native/WPF dependency makes the process exit early with a
  non-zero code; a healthy tool shows its window and keeps running (we then close it). A failed *connection*
  from the dummy arg is expected and fine; a failed *load* is not.
  Run:  pwsh -File build/package-and-verify.ps1
#>
param([string]$Configuration = "Release")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tool = "SkylineToolTemplate"
$sln  = Join-Path $root "$tool.sln"
$publishDir = Join-Path $root "publish/app"
$zipDir = Join-Path $root "publish"
$zipPath = Join-Path $zipDir "$tool.zip"

Write-Host "== Test =="
dotnet test $sln -c $Configuration --nologo
if ($LASTEXITCODE -ne 0) { throw "Tests failed" }

Write-Host "== Publish (framework-dependent) =="
if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
dotnet publish (Join-Path $root "src/$tool.App/$tool.App.csproj") -c $Configuration `
    --self-contained false -p:UseAppHost=true -o $publishDir
if ($LASTEXITCODE -ne 0) { throw "Publish failed" }

Write-Host "== Zip =="
if (-not (Test-Path $zipDir)) { New-Item -ItemType Directory $zipDir | Out-Null }
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $publishDir "*") -DestinationPath $zipPath

Write-Host "== Launch-verify (clean extract) =="
$verifyDir = Join-Path ([System.IO.Path]::GetTempPath()) "$tool-verify-$([System.IO.Path]::GetRandomFileName())"
Expand-Archive -Path $zipPath -DestinationPath $verifyDir
$exe = Join-Path $verifyDir "$tool.exe"
if (-not (Test-Path $exe)) { throw "exe missing from package: $exe" }

$proc = Start-Process -FilePath $exe -ArgumentList "DUMMY-CONNECTION" -PassThru
Start-Sleep -Seconds 4
if ($proc.HasExited -and $proc.ExitCode -ne 0) {
    throw "Launch-verify FAILED: exe exited early with code $($proc.ExitCode) (likely a load / native-dependency error)."
}
if (-not $proc.HasExited) { $proc.CloseMainWindow() | Out-Null; Start-Sleep 1; if (-not $proc.HasExited) { $proc.Kill() } }
Remove-Item $verifyDir -Recurse -Force

Write-Host "OK: package built and launch-verified -> $zipPath"
