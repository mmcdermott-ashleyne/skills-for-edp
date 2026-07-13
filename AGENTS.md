# AGENTS.md — Ashley / FDE Power BI (local PBIP)

You edit **local PBIP project files** for an enterprise Power BI semantic model
and its reports. Work happens entirely on disk: read and edit TMDL / PBIR files.

**Never** touch the Fabric / Power BI service and never require a CLI or MCP
server: no `az`, no `npm`, no `powerbi-desktop`, no REST, no deploy / refresh /
publish / bind. Validation = the user opening the PBIP in Power BI Desktop.

## Two actions

Every request resolves to exactly one of two skills:

| Skill | Use when the request changes… |
|---|---|
| `skills/edit-semantic-model/SKILL.md` | business logic, DAX, measures, columns, tables, relationships, calculation groups, hierarchies, display folders, format strings, descriptions, synonyms — i.e. `<Name>.SemanticModel/definition/*.tmdl` |
| `skills/edit-powerbi-report/SKILL.md` | report pages, visuals, slicers, filters, bookmarks, drillthrough, themes, layout, formatting — i.e. `<Report>.Report/definition/**/*.json` |

**Needs both** (e.g. "add YoY Sales to the report" when `[YoY Sales]` doesn't
exist): do the semantic-model change first, then the report change.

Out of scope: other Fabric workloads (Spark, Lakehouse, Warehouse, Dataflow,
KQL, Pipelines, etc.) and any service operation. Don't suggest them unless the
user explicitly asks.

## Inspecting the model (do this BEFORE reading TMDL)

A semantic model is tens of thousands of lines of `.tmdl`. **Do not** read whole
table files to find or understand an object — that burns context. Use the
read-only PowerShell tool `bin/model.ps1`; it parses the model and returns only
the slice you asked for. Open a `.tmdl` file only once you know the exact object
to edit.

PowerShell only — no Node.js. Runs anywhere on Windows. `-Model` defaults to the
current dir; pass it when running from elsewhere.

```powershell
pwsh bin/model.ps1 show "Net Sales" -Model <pbip-dir>  # one block: DAX, format, folder, description
pwsh bin/model.ps1 list -Measures -Folder Sales        # filtered inventory (also -Columns / -Tables, -Table, -Hidden)
pwsh bin/model.ps1 deps "Net Sales"                    # what references it — run BEFORE any rename/delete
pwsh bin/model.ps1 audit                               # visible objects missing a description
pwsh bin/model.ps1 lint                                # dangling refs, duplicate measure names
```

Add `-Json` for structured output. Full help: `Get-Help bin/model.ps1 -Full` (or
run with no command). If the tool is unavailable, fall back to grepping
`tables/*.tmdl` for the name.
