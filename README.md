# skyline-external-tools-ai

**Everything an AI agent needs to help you build a [Skyline](https://skyline.ms) external tool** — the
hard-won field knowledge, a scaffolding skill, and a ready-to-clone .NET project template. Clone this
next to your work, point Claude Code at it, and go from "I want a tool that does X" to a packaged,
installable Skyline tool without relearning the platform.

Modeled on [`ProteoWizard/pwiz-ai`](https://github.com/ProteoWizard/pwiz-ai), but **scoped to Skyline
external tools generally** — not just ProteoWizard. The knowledge here was distilled building
[skyline-prism](https://github.com/maccoss/skyline-prism),
[skyline-cadenza](https://github.com/maccoss/skyline-cadenza), and
[skyline-osprey-tool](https://github.com/maccoss/skyline-osprey-tool).

## What's inside

| Path | What it is |
|---|---|
| **`docs/skyline-external-tools.md`** | **The field guide** — the canonical, comprehensive reference: RPC connection, reports, document grid, settings, `.blib`, chromatogram export, reading the `.sky` XML, embedding a pwiz engine, packaging, and every gotcha that cost real time. |
| **`docs/installing-a-skyline-tool.md`** | **End-user install guide** — a friendly, non-developer walkthrough for analysts who received a packaged tool `.zip`: prerequisites (.NET 8 Desktop Runtime), installing from the Tools menu, running, updating, and troubleshooting. |
| **`docs/testing.md`** | Testing practices for external tools (the `FakeExecutor` seam, hermetic xUnit, the launch-verify ship gate, verify-against-real-data). |
| **`claude/skills/skyline-external-tool/`** | The **`skyline-external-tool` skill** — drives the workflow: read the guide → scaffold from the template → implement → build → package → verify. |
| **`claude/commands/`** | Slash commands for the tool lifecycle. |
| **`templates/dotnet-tool/`** | A **working .NET skeleton** (`Core`/`Cli`/`Skyline`/`App`) with the vendored `SkylineTool` RPC client, `tool-inf/` manifest, and packaging — a `dotnet new` template. |

## Use it two ways

**1. Clone as a sibling (full dev environment — recommended)**

```bash
mkdir dev && cd dev
git clone https://github.com/uw-maccosslab/skyline-external-tools-ai.git ai
# Windows: expose the skill/commands to Claude Code
mklink /J .claude ai\claude          # (macOS/Linux: ln -s ai/claude .claude)
git clone <your-new-tool-repo>       # or scaffold one from the template
claude                               # start Claude Code from `dev/`
```
Claude Code, running from `dev/`, sees the `ai/` context (field guide, skill, template) *and* your tool
checkout, and can build across both.

**2. Install the plugin (lightweight — no clone)**

Once published, `claude plugin install skyline-external-tool` gives you the skill + commands + the
`skyline` MCP config in any session. Good when you just want AI help in an existing tool repo.
*(The repo is primary; the plugin is a thin distribution of `claude/`.)*

## Start here (for the agent)

1. **`CLAUDE.md`** — orientation + the classic-vs-RPC decision.
2. **`CRITICAL-RULES.md`** — the handful of rules that, if broken, waste hours.
3. **`docs/skyline-external-tools.md`** — the deep reference; read the section you need.
4. Run the **`skyline-external-tool` skill** to scaffold and build.

Reference Skyline version for the CLI/RPC surface: **26.1** (confirm at runtime with `--version` / RPC
`GetVersion`).
