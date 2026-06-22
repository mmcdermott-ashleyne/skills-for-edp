# skills-for-edp Setup Guide

This guide creates a focused fork of Microsoft `skills-for-fabric` for Ashley / FDE Power BI semantic model and PBIR report work.

Your custom version can be named:

```text
skills-for-edp
```

Yes, this is a good name. It clearly separates your enterprise data platform / Power BI agent setup from Microsoft's upstream repo while still allowing you to pull selected updates from Microsoft later.

## Goal

Create a lean agent repository for two focused workstreams:

1. **Data team** manages the large shared semantic model.
2. **BI team** builds PBIR / PBIP Power BI reports from that shared semantic model.

This setup intentionally excludes unrelated Fabric workloads such as Spark, Lakehouse, Warehouse, Eventhouse, KQL, Dataflows, Eventstream, Activator, Notebooks, and Pipelines.

## Final Repository Shape

```text
skills-for-edp/
├── AGENTS.md
├── CLAUDE.md
├── README.md
├── CHANGELOG.md
├── package.json
├── agents/
│   ├── SemanticModelAgent.agent.md
│   └── PowerBIReportAgent.agent.md
├── common/
│   ├── COMMON-CORE.md
│   └── COMMON-CLI.md
└── skills/
    ├── semantic-model-authoring/
    ├── semantic-model-consumption/
    ├── powerbi-report-authoring/
    ├── powerbi-report-design/
    ├── powerbi-report-management/
    ├── powerbi-report-planning/
    └── check-updates/
```

## Keep or Remove `package.json`?

Keep it.

`package.json` is not required for Codex or Claude Code to read the Markdown agent instructions, but it is useful for version awareness and update checks.

Recommended root metadata files to keep:

```text
README.md
CHANGELOG.md
package.json
```

Recommended agent instruction files:

```text
AGENTS.md
CLAUDE.md
```

## Does Copilot Syntax Matter for Codex or Claude Code?

Mostly no.

The custom agent files are plain Markdown. Codex and Claude Code can read them as normal project instructions.

The YAML-style header at the top of each agent file is harmless:

```yaml
---
name: SemanticModelAgent
description: ...
delegates_to:
  - semantic-model-authoring
---
```

It gives structure for tools that understand metadata, but Codex and Claude Code can still use the files even if they ignore the header.

For Codex, `AGENTS.md` is the important root instruction file.

For Claude Code, `CLAUDE.md` is strongly recommended as a short bridge that points Claude to `AGENTS.md`.

## Step 1: Fork the Microsoft Repository

Open:

```text
https://github.com/microsoft/skills-for-fabric
```

Click **Fork**.

Name your fork:

```text
skills-for-edp
```

Fork it into your GitHub account or Ashley / FDE organization.

Example final fork URL:

```text
https://github.com/YOUR_ORG/skills-for-edp
```

## Step 2: Clone Your Fork

Replace `YOUR_ORG` with your GitHub user or organization.

```bash
git clone --filter=blob:none --no-checkout https://github.com/YOUR_ORG/skills-for-edp.git
cd skills-for-edp
```

## Step 3: Add Microsoft as Upstream

```bash
git remote add upstream https://github.com/microsoft/skills-for-fabric.git
git remote -v
```

Expected remotes:

```text
origin    https://github.com/YOUR_ORG/skills-for-edp.git
upstream  https://github.com/microsoft/skills-for-fabric.git
```

## Step 4: Enable Sparse Checkout

```bash
git sparse-checkout init --cone
```

## Step 5: Pull Only the Needed Files and Folders

```bash
git sparse-checkout set \
  AGENTS.md \
  CLAUDE.md \
  README.md \
  CHANGELOG.md \
  package.json \
  agents \
  common/COMMON-CORE.md \
  common/COMMON-CLI.md \
  skills/semantic-model-authoring \
  skills/semantic-model-consumption \
  skills/powerbi-report-authoring \
  skills/powerbi-report-design \
  skills/powerbi-report-management \
  skills/powerbi-report-planning \
  skills/check-updates
```

Then check out the branch:

```bash
git checkout main
```

## Step 6: Replace the Root `AGENTS.md`

Replace the Microsoft root `AGENTS.md` with your custom Ashley / FDE router file.

The custom `AGENTS.md` should route work between:

```text
agents/SemanticModelAgent.agent.md
agents/PowerBIReportAgent.agent.md
```

Routing rule:

```text
Semantic model, DAX, TMDL, XMLA, Copilot readiness, AI instructions, AI schema, descriptions, synonyms, Verified Answers, RLS, OLS, refresh, partitions
→ SemanticModelAgent

PBIR/PBIP reports, pages, visuals, slicers, filters, bookmarks, themes, report deployment, report rebinds
→ PowerBIReportAgent

Both domains required
→ SemanticModelAgent first, then PowerBIReportAgent
```

## Step 7: Replace the `agents` Folder

Delete the unrelated Microsoft agent files:

```bash
rm -rf agents/*
```

Add only these two files:

```text
agents/SemanticModelAgent.agent.md
agents/PowerBIReportAgent.agent.md
```

## Step 8: Create or Replace `CLAUDE.md`

Recommended `CLAUDE.md`:

```md
# Claude Code Instructions

Read `AGENTS.md` first.

This repository is intentionally limited to:

- enterprise Power BI semantic model work
- Copilot / AI readiness for semantic models
- PBIR / PBIP report development from the shared semantic model

Use:

- `agents/SemanticModelAgent.agent.md` for semantic model, DAX, TMDL, XMLA, AI instructions, AI schema, descriptions, synonyms, Verified Answers, and Copilot readiness.
- `agents/PowerBIReportAgent.agent.md` for PBIR/PBIP reports, pages, visuals, slicers, filters, themes, bookmarks, report deployment, and report rebinds.

Do not use unrelated Fabric workload guidance unless explicitly requested.
```

## Step 9: Commit Your Custom Agent Setup

```bash
git add AGENTS.md CLAUDE.md agents
git commit -m "Customize agents for semantic model and Power BI report workflows"
git push origin main
```

## Step 10: Keep Upstream Available for Updates

Fetch upstream changes:

```bash
git fetch upstream
```

Review only relevant upstream changes:

```bash
git log --oneline main..upstream/main -- \
  skills/semantic-model-authoring \
  skills/semantic-model-consumption \
  skills/powerbi-report-authoring \
  skills/powerbi-report-design \
  skills/powerbi-report-management \
  skills/powerbi-report-planning \
  skills/check-updates \
  common/COMMON-CORE.md \
  common/COMMON-CLI.md \
  CHANGELOG.md \
  package.json
```

Pull selected upstream files when you want to update your local skills:

```bash
git checkout upstream/main -- \
  skills/semantic-model-authoring \
  skills/semantic-model-consumption \
  skills/powerbi-report-authoring \
  skills/powerbi-report-design \
  skills/powerbi-report-management \
  skills/powerbi-report-planning \
  skills/check-updates \
  common/COMMON-CORE.md \
  common/COMMON-CLI.md \
  CHANGELOG.md \
  package.json
```

Commit the update:

```bash
git add .
git commit -m "Update selected Microsoft Fabric Power BI skills"
git push origin main
```

## Step 11: Optional Rename Cleanup

Because your fork is named `skills-for-edp`, update your local README title if desired:

```text
# skills-for-edp

Focused Ashley / FDE agent skills for Power BI semantic models and PBIR report development.
```

This is optional, but it helps avoid confusion with Microsoft's full upstream repo.

## Step 12: Recommended AI Readiness Rule

Your semantic model agent should enforce this rule:

```text
Every visible table, column, and measure must have a clear business-friendly description.
```

Descriptions should explain:

- what the object means
- how business users should interpret it
- when to use it
- when not to use it
- any grain, filter, time, or security assumptions

This supports Copilot, Q&A, Data Agents, and natural-language BI use cases.

## Step 13: Recommended Sparse Checkout Refresh Command

If your sparse checkout gets out of sync, re-run:

```bash
git sparse-checkout set \
  AGENTS.md \
  CLAUDE.md \
  README.md \
  CHANGELOG.md \
  package.json \
  agents \
  common/COMMON-CORE.md \
  common/COMMON-CLI.md \
  skills/semantic-model-authoring \
  skills/semantic-model-consumption \
  skills/powerbi-report-authoring \
  skills/powerbi-report-design \
  skills/powerbi-report-management \
  skills/powerbi-report-planning \
  skills/check-updates
```

## Final Recommendation

Use the name:

```text
skills-for-edp
```

Keep:

```text
AGENTS.md
CLAUDE.md
README.md
CHANGELOG.md
package.json
agents/SemanticModelAgent.agent.md
agents/PowerBIReportAgent.agent.md
common/COMMON-CORE.md
common/COMMON-CLI.md
skills/semantic-model-authoring
skills/semantic-model-consumption
skills/powerbi-report-authoring
skills/powerbi-report-design
skills/powerbi-report-management
skills/powerbi-report-planning
skills/check-updates
```

Remove or ignore everything else.

This gives you a clean, narrow, updateable agent repo for Data team semantic model ownership and BI team PBIR report development.
