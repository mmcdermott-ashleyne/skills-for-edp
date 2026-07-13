# skills-for-edp

Ashley / FDE tooling for working with a **local PBIP Power BI project** — the
shared enterprise semantic model and the reports built on it. Everything here
operates on the PBIP files **on disk**. Nothing connects to the Power BI / Fabric
service, and nothing needs a login.

It has two parts:

1. **Agent skills** (`skills/`) — instructions an AI agent (Claude Code, Copilot,
   etc.) follows to edit the model or a report.
2. **`pbip-model`** (`bin/model.ps1`) — a small read-only PowerShell command you
   (or an agent) run to query the semantic model without opening every TMDL file.

## What problem this solves

A PBIP semantic model is a folder of `.tmdl` text files — one per table, often
tens of thousands of lines total. To answer "what does this measure do?" or
"what breaks if I rename this column?" you'd otherwise open and scan many files.
`pbip-model` parses the model once and hands back just the slice you asked for.

---

## For humans: using `pbip-model`

### Prerequisite

PowerShell. Already on every Windows machine — no install, no Node.js. Use
either Windows PowerShell (`powershell`) or PowerShell 7+ (`pwsh`).

### Run it

From this repo, point it at your PBIP project folder (the folder that contains
`<Name>.SemanticModel`):

```powershell
pwsh bin/model.ps1 <command> -Model "C:\path\to\your\pbip-project"
```

If you run it from *inside* your PBIP project, you can drop `-Model` — it finds
the `.SemanticModel` automatically. For full help: `Get-Help bin/model.ps1 -Full`
(or run it with no command).

### The five commands

```powershell
# 1. Show one measure / column / table: its DAX, format, folder, description
pwsh bin/model.ps1 show "Annualized Attrition Rate (As Of Date)" -Model "<path>"

# 2. List objects, optionally filtered
pwsh bin/model.ps1 list -Measures                  # all measures
pwsh bin/model.ps1 list -Measures -Folder Headcount
pwsh bin/model.ps1 list -Columns -Table dim_employee
pwsh bin/model.ps1 list -Tables

# 3. Impact analysis — what references this object?
#    Use BEFORE renaming or deleting anything.
pwsh bin/model.ps1 deps "Terminations"             # → measures + relationships that use it

# 4. AI-readiness audit — visible objects missing a description
pwsh bin/model.ps1 audit

# 5. Sanity check — broken references, duplicate measure names
pwsh bin/model.ps1 lint
```

Add `-Json` to any command for machine-readable output.

### Worked example

```powershell
pwsh bin/model.ps1 show "Net Employee Change" -Model "C:\...\enterprise_data_platform"
```

```text
MEASURE  _Measures – HR Employee / Net Employee Change
  formatString: +#,##0;-#,##0;0
  displayFolder: Hiring
  description: PERIOD NET | Net workforce change over the selected date range...
  expression:
    [New Hires] - [Terminations]
```

### What it does **not** do

- It does not change anything — it's read-only. To edit, change the `.tmdl`
  files directly (or let an agent do it via the skill below).
- It does not connect to Power BI / Fabric. It only reads files on disk.
- To see a change take effect, open the PBIP in Power BI Desktop.

---

## For agents: the two skills

An agent resolves every request to one of two skills (see `AGENTS.md`):

| Skill | Use for |
|---|---|
| `skills/edit-semantic-model/SKILL.md` | measures, DAX, columns, tables, relationships, descriptions — edits to `*.SemanticModel/definition/*.tmdl` |
| `skills/edit-powerbi-report/SKILL.md` | report pages, visuals, slicers, filters, themes — edits to `*.Report/definition/**/*.json` |

The semantic-model skill tells the agent to **inspect with `pbip-model`** (cheap,
structured) and then edit the one target `.tmdl` file. Each skill keeps deep
material in `references/` that loads only when a task needs it, so a simple edit
stays small.

---

## Repository layout

```text
AGENTS.md                         Router: picks one of the two skills
CLAUDE.md / GEMINI.md             Tool-specific entry points → AGENTS.md
bin/model.ps1                     pbip-model query tool (PowerShell, read-only)
skills/edit-semantic-model/       Semantic model editing skill + references
skills/edit-powerbi-report/       Report editing skill + references
skills-for-edp-setup.md           How this repo was carved from upstream
```

## Roadmap

`pbip-model` is currently **read-only (Phase 1)**. Planned Phase 2 adds safe write
commands (`set-description`, `add-measure`, `rename --apply`) and a `report`
subcommand for the PBIR side.
