---
name: edit-semantic-model
description: >-
  Edit a Power BI semantic model in a local PBIP project by editing its TMDL
  files on disk. Use for: add/edit/remove measures, columns, tables,
  relationships, calculation groups, hierarchies, display folders, format
  strings, descriptions, and synonyms. Pure file editing — no CLI, no MCP, no
  Fabric service. Triggers: "edit semantic model", "add a measure", "change DAX",
  "rename column", "add description", "edit TMDL".
---

# Edit Semantic Model (local TMDL)

Edit the model's TMDL source files directly. The model lives on disk inside a
PBIP project. You do not connect to the service, run `az`/`npm`, or use an MCP
server — just read and edit `.tmdl` files.

**Does:** measures, DAX, columns, tables, relationships, calculation groups,
hierarchies, display folders, format strings, descriptions, synonyms.
**Does not:** report visuals/pages (use `edit-powerbi-report`); refresh, deploy,
publish, bind connections, RLS/OLS membership (all service operations — out of
scope).

## 1. Locate the file

TMDL lives under `<Name>.SemanticModel/definition/`:

```text
<Name>.SemanticModel/definition/
├── model.tmdl              # model-level props, culture, annotations
├── database.tmdl           # compatibility level
├── relationships.tmdl      # all relationships
├── tables/
│   └── <Table>.tmdl        # one file per table: columns, measures, partitions, hierarchies
├── cultures/               # translations / synonyms (if present)
└── expressions.tmdl        # shared M expressions / parameters (if present)
```

To find or inspect an object, **prefer the read-only model tool** (parses the
TMDL and returns just the slice you need — far cheaper than reading whole table
files):

```bash
node bin/model.mjs show "Net Sales" --model <pbip-dir>   # one block + props + description
node bin/model.mjs list --measures --folder Sales         # filtered inventory
node bin/model.mjs deps "Net Sales"                       # what references it (rename/delete impact)
node bin/model.mjs audit --missing-descriptions           # AI-readiness gaps
node bin/model.mjs lint                                    # dangling refs, duplicate names
```

Add `--json` for compact structured output. If the tool is unavailable, fall
back to grepping `tables/*.tmdl` for the name. Either way, then open the one
target `.tmdl` file to edit.

## 2. Make the edit

Edit the `.tmdl` file directly with exact string edits.

- A measure block looks like (the `///` line above it IS the description):
  ```tmdl
  /// Recognized sales after returns and discounts.
  measure 'Net Sales' = CALCULATE(SUM(Sales[Amount]), ...)
      formatString: #,0
      displayFolder: Sales
  ```
- Keep changes small. Preserve the file's existing indentation (tabs), property
  order, and formatting. Do not reorder or reflow unrelated lines.
- When adding a measure, put it in the right table file; set `formatString` and
  `displayFolder` to match sibling measures.
- DAX: prefer measures over calculated columns; use `VAR` for readability;
  `DIVIDE()` for safe division; be explicit with `CALCULATE`. Load
  `references/dax-guidelines.md` for non-trivial DAX.

## 3. AI-readiness checklist (required for visible objects)

When you **add or change** a visible table, column, or measure, add or update its
`///` description comment (the line directly above the object) in the same edit.
Run `node bin/model.mjs audit --missing-descriptions` to find gaps. A description
states:

- what it means in business terms, and (for tables) the grain
- aggregation / filter / time-intelligence behavior (measures)
- caveats, exclusions, current-vs-historical notes
- no secrets, credentials, or internal-only data

Keep synonyms current if the model uses cultures/synonyms. Skip descriptions only
for hidden technical objects that aren't business-facing.

## 4. Validate (no CLI)

- TMDL stays syntactically valid: correct keyword (`measure`/`column`/`table`),
  indentation, and balanced expressions; referenced columns/tables exist
  (case-sensitive).
- After edits, tell the user to open the PBIP in Power BI Desktop to confirm the
  model loads and measures compile. You cannot execute DAX from files alone.

## 5. Confirm before

Renaming or deleting any object that other measures, relationships, hierarchies,
or reports may reference; changing descriptions on existing production objects in
a way that alters meaning. Inspect the `.tmdl` files for references first and
call out impact.

## On-demand references

Load only when the task needs the depth — the steps above cover simple edits.

| Reference | Load when |
|---|---|
| `references/tmdl-guidelines.md` | Editing/creating non-trivial TMDL structure |
| `references/dax-guidelines.md` | Writing or refactoring DAX beyond a one-liner |
| `references/modeling-guidelines.md` | Adding tables/relationships; star-schema decisions |
| `references/naming-conventions.md` | Naming new tables, columns, or measures |
| `references/pbip.md` | Need PBIP folder structure details or scaffolding |
