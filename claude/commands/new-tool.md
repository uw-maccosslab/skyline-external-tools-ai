---
description: Scaffold a new Skyline external tool from the template and confirm it builds.
---

Scaffold a new Skyline external tool. Load the **`skyline-external-tool`** skill first, then:

1. Ask the user (or infer from their request) the **tool name** (PascalCase, e.g. `MyTool`) and whether it
   needs a **live JSON-RPC** connection / interactive UI or is a **classic report-macro** tool (field
   guide §0). Recommend classic unless it must read the live document beyond a report or write back.
2. Install and run the template:
   ```bash
   dotnet new install <repo>/templates/dotnet-tool
   dotnet new skyline-external-tool -n <ToolName> -o <ToolName>
   ```
3. `cd <ToolName>` and run `dotnet build <ToolName>.sln` — confirm it's green before writing any logic.
4. For a **classic** tool, remove the `App` and `Skyline` projects and write a `tool-inf/<Tool>.properties`
   with `Report=…` instead of `Arguments=$(SkylineConnection)`.
5. Summarize the layout and the next step (implement the capability the user asked for, keyed to the field
   guide section).

Arguments: `$ARGUMENTS` (treat as the tool name and/or a one-line description of what the tool should do).
