# Skyline external tool template (`dotnet new`)

A working skeleton for a **live JSON-RPC** Skyline external tool. Four projects, the vendored `SkylineTool`
RPC client already wired into the Windows project only, a `tool-inf/` manifest, a smoke test, and a
package + launch-verify script.

## Use it

```bash
# once: install the template from this folder
dotnet new install ./templates/dotnet-tool

# scaffold a new tool (renames SkylineToolTemplate -> MyTool everywhere)
dotnet new skyline-external-tool -n MyTool -o MyTool
cd MyTool
dotnet build MyTool.sln          # should be green immediately
dotnet test  MyTool.sln
```

Then implement (the `skyline-external-tool` skill walks you through it, keyed to the field guide
`docs/skyline-external-tools.md`).

## Layout

| Project | TFM | Role |
|---|---|---|
| `*.Core` | `net8.0` | algorithms / IO — **cross-platform, no pipes, no WPF** |
| `*.Cli` | `net8.0` | cross-platform headless entry (references Core only) |
| `*.Skyline` | `net8.0-windows` | JSON-RPC client + the `ISkylineClient`/`ISkylineExecutor` seam; the **only** project that link-compiles the vendored `SkylineTool` sources (keeps Core cross-platform) |
| `*.App` | `net8.0-windows` WPF | the `.exe` Skyline launches — Settings + Log tabs; `AssemblyName` matches `tool-inf/<Tool>.properties` |
| `tests/*.Tests` | `net8.0` | hermetic xUnit (a smoke test; add fixtures per `docs/testing.md`) |

The `SkylineSession` already encodes the three connection rules (transform `args[0]`, connect per call,
`ReadMode=Message`). The `App` receives `$(SkylineConnection)` as `args[0]` and talks to Skyline on Run.

## Building a *classic* (report-macro) tool instead?

You don't need `App`/`Skyline`. Keep `Core` + a thin launcher, and write a `tool-inf/<Tool>.properties`
with `Command=…`, `Report=<name>`, `Arguments="…$(ReportTempPath)…"` (no `$(SkylineConnection)`). See field
guide §0.

## Package + install

```powershell
pwsh -File build/package-and-verify.ps1        # test -> publish (framework-dependent) -> zip -> launch-verify
```
Install the resulting `publish/<Tool>.zip` via Skyline ▸ Tools ▸ Tool Store ▸ *Install from file*, or
`SkylineCmd --tool-add-zip=<zip>`. **Close the tool before reinstalling.** Users install the **.NET 8
Desktop Runtime** once (the zip is framework-dependent).

## Vendored RPC client

`external/SkylineTool/*.cs` are copied verbatim from pwiz `pwiz_tools/Skyline/SkylineTool/` (Apache-2.0).
Re-sync by diffing against a fresh pwiz checkout — see `external/SkylineTool/README.md`.
