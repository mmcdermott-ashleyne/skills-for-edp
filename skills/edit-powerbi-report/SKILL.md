---
name: edit-powerbi-report
description: >-
  Edit a Power BI report in a local PBIP project by editing its PBIR JSON files
  on disk. Use for: add/edit pages, visuals, slicers, filters, bookmarks,
  drillthrough, themes, layout, and formatting. Pure file editing — no CLI, no
  MCP, no Fabric service. Triggers: "edit report", "add a visual", "add a page",
  "format visual", "change theme", "add slicer", "edit PBIR".
---

# Edit Power BI Report (local PBIR)

Edit the report's PBIR JSON files directly. The report lives on disk inside a
PBIP project. You do not connect to the service, run `az`/`npm`/`powerbi-desktop`,
or use an MCP server — just read and edit the JSON files.

**Does:** pages, visuals, slicers, filters, bookmarks, drillthrough, tooltips,
themes, layout, formatting. **Does not:** model logic, DAX, measures,
descriptions (use `edit-semantic-model`); publish/deploy/rebind to the service
(out of scope).

## 1. Locate the file

```text
<Report>.pbip                              # Project manifest
└── <Report>.Report/
    ├── definition.pbir                    # Report → SemanticModel binding
    └── definition/
        ├── version.json                   # PBIR format version
        ├── report.json                    # Report-level: themes, settings, resources
        └── pages/
            ├── pages.json                 # Page order + active page
            └── <pageId>/
                ├── page.json              # Page: displayName, size, type, filters
                └── visuals/
                    └── <visualId>/
                        └── visual.json    # Visual: type, position, query, formatting
```

| File | Purpose |
|---|---|
| `definition.pbir` | Report → model binding (`byPath`/`byConnection`) — don't change unless rebinding |
| `report.json` | Report-level settings, registered themes, resources |
| `pages.json` | Page order (`pageOrder`) and active page — add every new page here |
| `page.json` | Page metadata, size, page-level filters |
| `visual.json` | Visual type, position, query bindings, formatting (`objects`) |

To find a visual: read `pages.json` for page order/ids, then the target page's
`visuals/*/visual.json`.

## 2. Make the edit

- **Edit JSON safely:** read → `JSON.parse` (or exact-string `edit`) → modify →
  write. **Never** use regex/string replacement on whole JSON values or
  `ConvertTo-Json` (corrupts nesting / reorders keys). Exact old/new string edits
  on a unique snippet are fine.
- **Preserve `$schema` and `version`** values — copy from an existing file of the
  same type; never invent or bump them.
- Add each new page id to `pages.json` `pageOrder`. Generate unique ids for new
  pages/visuals.
- Use modern visual types: `cardVisual` (not `card`), `tableEx` (not `table`),
  `pivotTable` (not `matrix`), `azureMap` (not `map`/`filledMap`).
- Bind columns with type `Column`, measures with type `Measure` — don't mix.
- Don't guess role names, formatting object keys, or enum values — check the
  relevant reference file below.

## 3. Validate (no CLI)

- Every edited JSON file must stay well-formed and keep its `$schema`/`version`.
- Cross-file refs resolve: new pages in `pageOrder`; visual queries reference
  fields/measures that exist in the bound model.
- Tell the user to open the PBIP in Power BI Desktop to confirm rendering. You
  cannot reload or screenshot from files alone.

## 4. Confirm before

Overwriting existing report files in bulk; changing `definition.pbir` binding;
deleting pages/visuals that bookmarks or drillthrough may reference.

## On-demand references

Load only the file matching the task — the steps above cover simple edits.

| Reference | Load when |
|---|---|
| `references/authoring.md` | Adding/modifying pages, visuals, drillthrough, interactions (full JSON examples) |
| `references/expressions.md` | Building field refs (Column/Measure/Aggregation/Hierarchy) and sort defs |
| `references/filters.md` / `references/filter-pane.md` | Adding filters / styling the filter pane |
| `references/slicers.md` | Adding or configuring slicers and selections |
| `references/cartesian.md` | Bar/column/line charts |
| `references/card.md` | KPI/card visuals (`cardVisual`) |
| `references/table.md` | Tables/matrices (`tableEx`/`pivotTable`) |
| `references/image.md` / `references/shape.md` / `references/textbox.md` / `references/map.md` | Those visual types |
| `references/formatting-overview.md` | **Read first for appearance changes** — cascade, selectors, routing |
| `references/formatting.md` | `visual.json` appearance — selectors, VCOs, encoding |
| `references/color-strategy.md` / `references/conditional-formatting.md` | Data-point colors / data-driven formatting |
| `references/page-formatting.md` | `page.json` appearance — canvas/background |
| `references/theming.md` / `references/re-theming.md` | Creating/editing `theme.json` / switching themes on existing visuals |
| `references/chart-selection.md` / `references/layout.md` / `references/accessibility.md` | Choosing a chart / layout / a11y |
| `references/anti-patterns.md` | Before nontrivial visual/formatting edits — common traps |
| `references/version-control.md` | Git branch/commit/revert for safe rollback |
