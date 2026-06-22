# skills-for-edp Setup Guide

A focused fork of Microsoft `skills-for-fabric` for Ashley / FDE Power BI work.
It does exactly two things, both as **local PBIP file edits** — no CLI, no MCP,
no Fabric service:

1. Edit the shared **semantic model** (TMDL).
2. Edit **PBIR / PBIP reports** built from that model.

All other Fabric workloads (Spark, Lakehouse, Warehouse, Eventhouse, KQL,
Dataflows, Eventstream, Activator, Notebooks, Pipelines) are intentionally
excluded.

## Repository shape

```text
skills-for-edp/
├── AGENTS.md                 # router: picks one of the two skills
├── CLAUDE.md                 # Claude Code bridge → AGENTS.md
├── GEMINI.md                 # thin import of AGENTS.md
├── package.json
└── skills/
    ├── edit-semantic-model/
    │   ├── SKILL.md
    │   └── references/       # on-demand: tmdl, dax, modeling, naming, pbip
    └── edit-powerbi-report/
        ├── SKILL.md
        └── references/       # on-demand: authoring, formatting, visuals, theming, …
```

The two `SKILL.md` files are self-sufficient for ordinary edits; their
`references/` files load only when a task needs the extra depth. There are no
`agents/`, `common/`, or service/CLI skills — they were removed so a simple edit
never pulls service, REST, or CLI context.

## How it was carved from upstream

The repo is a **sparse checkout** of `microsoft/skills-for-fabric`: git tracks
the full upstream tree, but only the paths below are checked out to disk.

```bash
git clone --filter=blob:none --no-checkout https://github.com/YOUR_ORG/skills-for-edp.git
cd skills-for-edp
git remote add upstream https://github.com/microsoft/skills-for-fabric.git
```

Scope the working tree (non-cone, so we can include our custom skill folders and
exclude everything else under `skills/`):

```bash
git sparse-checkout set --no-cone \
  "/*" "!/skills/*/" \
  "/skills/edit-semantic-model/" \
  "/skills/edit-powerbi-report/"
git checkout main
```

If the sparse checkout drifts (unrelated workload folders reappear on disk),
re-run the `git sparse-checkout set` command above.

## Relationship to upstream

The two skills are **custom-authored** for the local-file, non-CLI workflow —
they are no longer a straight mirror of upstream skill files. Upstream remains
useful as a reference for new PBIR/TMDL mechanics, but pull changes manually and
re-apply them by hand rather than overwriting these SKILLs:

```bash
git fetch upstream
git log --oneline main..upstream/main -- skills/semantic-model-authoring skills/powerbi-report-authoring
```

## AI-readiness rule (semantic model)

When you add or change a visible table, column, or measure, give it a clear
business-friendly `description` covering meaning, grain, filter/time behavior,
and caveats. This supports Copilot, Q&A, and natural-language consumption. See
`skills/edit-semantic-model/SKILL.md`.
