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
