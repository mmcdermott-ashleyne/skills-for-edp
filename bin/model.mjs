#!/usr/bin/env node
// pbip-model — read-only query tool over a local PBIP semantic model (TMDL).
// No service, no auth. Operates only on *.SemanticModel/definition files on disk.
//
// Usage:
//   node bin/model.mjs <command> [args] [--model <path>] [--json]
//
// Commands:
//   show <name>                       Show a measure / column / table block + props
//   list [--measures|--columns|--tables] [--folder F] [--hidden] [--table T]
//   deps <name>                       What references this object (rename/delete impact)
//   audit [--missing-descriptions]    AI-readiness / quality gaps
//   lint                              Offline checks: dangling refs, duplicate names
//
// --model resolves a *.SemanticModel dir, its definition/ dir, or any folder
// containing exactly one *.SemanticModel. Defaults to the current directory.

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, basename } from 'node:path';

// ---------- model location ----------

function findDefinitionDir(start) {
  let p = start;
  // direct hits
  if (basename(p).endsWith('.SemanticModel')) {
    const d = join(p, 'definition');
    if (existsSync(d)) return d;
  }
  if (basename(p) === 'definition' && existsSync(join(p, 'tables'))) return p;
  // search downward (shallow) for a *.SemanticModel
  const hits = [];
  const walk = (dir, depth) => {
    if (depth > 4) return;
    let entries;
    try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      if (!e.isDirectory()) continue;
      const full = join(dir, e.name);
      if (e.name.endsWith('.SemanticModel')) {
        const d = join(full, 'definition');
        if (existsSync(d)) hits.push(d);
      } else if (!e.name.startsWith('.') && e.name !== 'node_modules') {
        walk(full, depth + 1);
      }
    }
  };
  walk(p, 0);
  if (hits.length === 1) return hits[0];
  if (hits.length > 1) {
    die(`Multiple semantic models found; pass --model:\n${hits.map(h => '  ' + h).join('\n')}`);
  }
  return null;
}

// ---------- TMDL parsing ----------

const indentOf = (line) => (line.match(/^\t*/)[0] || '').length;
const stripTabs = (line) => line.replace(/^\t+/, '');
const unquote = (s) => s.replace(/^'(.*)'$/, '$1').trim();
const PROP_RE = /^([A-Za-z_][\w]*)\s*:\s*(.*)$/;

function parseTableFile(text) {
  const lines = text.split(/\r?\n/);
  const table = { name: null, description: '', measures: [], columns: [], partitions: 0 };
  let pending = []; // /// description buffer
  let i = 0;

  const flushDesc = () => { const d = pending.join(' ').trim(); pending = []; return d; };

  while (i < lines.length) {
    const line = lines[i];
    if (line.trim() === '') { i++; continue; }
    const indent = indentOf(line);
    const content = stripTabs(line);

    if (content.startsWith('///')) { pending.push(content.slice(3).trim()); i++; continue; }

    if (content.startsWith('table ')) {
      table.name = unquote(content.slice(6));
      table.description = flushDesc();
      i++; continue;
    }

    if (content.startsWith('measure ') || content.startsWith('column ')) {
      const isMeasure = content.startsWith('measure ');
      const objIndent = indent;
      const head = content.slice(isMeasure ? 8 : 7);
      const eq = head.indexOf('=');
      const name = unquote((eq >= 0 ? head.slice(0, eq) : head).trim());
      const inlineExpr = eq >= 0 ? head.slice(eq + 1).trim() : '';
      const description = flushDesc();

      // gather the block (everything indented deeper than the object keyword)
      const block = [];
      i++;
      while (i < lines.length) {
        const l = lines[i];
        if (l.trim() !== '' && indentOf(l) <= objIndent) break;
        block.push(l);
        i++;
      }
      // classify block lines: properties at objIndent+1 matching key:value; rest = expression
      const props = {};
      const exprLines = [];
      for (const l of block) {
        if (l.trim() === '') continue;
        const ind = indentOf(l);
        const c = stripTabs(l);
        const m = ind === objIndent + 1 ? c.match(PROP_RE) : null;
        if (m) props[m[1]] = m[2].trim();
        else exprLines.push(c);
      }
      const expr = inlineExpr || exprLines.join('\n');
      const obj = {
        name, description, expr,
        formatString: props.formatString || '',
        displayFolder: props.displayFolder || '',
        dataType: props.dataType || '',
        hidden: props.isHidden === 'true',
      };
      if (isMeasure) table.measures.push(obj); else table.columns.push(obj);
      continue;
    }

    if (content.startsWith('partition ')) { table.partitions++; pending = []; i++; continue; }

    // any other line at table level — drop pending desc so it doesn't leak
    pending = [];
    i++;
  }
  return table;
}

function parseRelationships(text) {
  const rels = [];
  const lines = text.split(/\r?\n/);
  let cur = null;
  for (const line of lines) {
    const c = stripTabs(line);
    if (c.startsWith('relationship ')) { cur = { from: null, to: null }; rels.push(cur); }
    else if (cur) {
      const f = c.match(/^fromColumn:\s*(.+?)\.(.+)$/);
      const t = c.match(/^toColumn:\s*(.+?)\.(.+)$/);
      if (f) cur.from = { table: f[1].trim(), col: f[2].trim() };
      if (t) cur.to = { table: t[1].trim(), col: t[2].trim() };
    }
  }
  return rels.filter(r => r.from && r.to);
}

function loadModel(defDir) {
  const tablesDir = join(defDir, 'tables');
  const tables = [];
  if (existsSync(tablesDir)) {
    for (const f of readdirSync(tablesDir)) {
      if (!f.endsWith('.tmdl')) continue;
      tables.push(parseTableFile(readFileSync(join(tablesDir, f), 'utf8')));
    }
  }
  let rels = [];
  const relFile = join(defDir, 'relationships.tmdl');
  if (existsSync(relFile)) rels = parseRelationships(readFileSync(relFile, 'utf8'));
  return { defDir, tables, relationships: rels };
}

// ---------- reference extraction ----------

// Returns { measures:Set<string>, columns:Set<"Table.col"|".col"> }
// Table-qualifier and "[" must be on the same line ([ \t]*, never a newline),
// otherwise a word ending one line bleeds into a [ref] on the next.
const REF_RE = /(?:('[^']+')|(\b[A-Za-z_]\w*))?[ \t]*\[([^\]]+)\]/g;
// Strip DAX comments so refs inside them don't count.
const stripComments = (s) => s
  .replace(/\/\*[\s\S]*?\*\//g, ' ')   // block comments
  .replace(/(--|\/\/).*$/gm, ' ');      // line comments
function extractRefs(exprRaw) {
  const expr = stripComments(exprRaw);
  const measures = new Set(), columns = new Set();
  let m;
  while ((m = REF_RE.exec(expr)) !== null) {
    const tbl = m[1] ? unquote(m[1]) : (m[2] || '');
    const inner = m[3];
    if (tbl) columns.add(`${tbl}.${inner}`);
    else measures.add(inner);
  }
  return { measures, columns };
}

// ---------- helpers ----------

function allMeasures(model) {
  return model.tables.flatMap(t => t.measures.map(x => ({ ...x, table: t.name })));
}
function allColumns(model) {
  return model.tables.flatMap(t => t.columns.map(x => ({ ...x, table: t.name })));
}
function die(msg) { console.error('error: ' + msg); process.exit(1); }

function parseArgs(argv) {
  const out = { _: [], flags: {} };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next !== undefined && !next.startsWith('--')) { out.flags[key] = next; i++; }
      else out.flags[key] = true;
    } else out._.push(a);
  }
  return out;
}

// ---------- commands ----------

function cmdShow(model, args) {
  const q = args._[1];
  if (!q) die('show <name>');
  const ql = q.toLowerCase();
  const meas = allMeasures(model).filter(m => m.name.toLowerCase() === ql);
  const cols = allColumns(model).filter(c => c.name.toLowerCase() === ql);
  const tbls = model.tables.filter(t => t.name.toLowerCase() === ql);
  const found = [
    ...meas.map(m => ({ kind: 'measure', ...m })),
    ...cols.map(c => ({ kind: 'column', ...c })),
    ...tbls.map(t => ({ kind: 'table', name: t.name, description: t.description, table: t.name,
      measures: t.measures.length, columns: t.columns.length })),
  ];
  if (!found.length) die(`not found: ${q}`);
  if (args.flags.json) return print(found.length === 1 ? found[0] : found);
  for (const o of found) {
    console.log(`${o.kind.toUpperCase()}  ${o.table ? o.table + ' / ' : ''}${o.name}`);
    if (o.kind === 'table') console.log(`  measures: ${o.measures}   columns: ${o.columns}`);
    if (o.formatString) console.log(`  formatString: ${o.formatString}`);
    if (o.displayFolder) console.log(`  displayFolder: ${o.displayFolder}`);
    if (o.dataType) console.log(`  dataType: ${o.dataType}`);
    if (o.hidden) console.log(`  hidden: true`);
    console.log(`  description: ${o.description || '(none)'}`);
    if (o.expr) console.log('  expression:\n' + o.expr.split('\n').map(l => '    ' + l).join('\n'));
    console.log('');
  }
}

function cmdList(model, args) {
  const f = args.flags;
  const wantM = f.measures || (!f.columns && !f.tables);
  const wantC = f.columns || (!f.measures && !f.tables);
  const wantT = f.tables;
  let rows = [];
  if (wantT) rows = model.tables.map(t => ({ kind: 'table', table: t.name, name: t.name, displayFolder: '', hidden: false }));
  else {
    if (wantM) rows.push(...allMeasures(model).map(m => ({ kind: 'measure', ...m })));
    if (wantC) rows.push(...allColumns(model).map(c => ({ kind: 'column', ...c })));
  }
  if (f.table) rows = rows.filter(r => r.table.toLowerCase() === String(f.table).toLowerCase());
  if (f.folder) rows = rows.filter(r => (r.displayFolder || '').toLowerCase().includes(String(f.folder).toLowerCase()));
  if (!f.hidden) rows = rows.filter(r => !r.hidden);
  if (f.json) return print(rows.map(r => ({ kind: r.kind, table: r.table, name: r.name, displayFolder: r.displayFolder || '' })));
  for (const r of rows) console.log(`${r.kind.padEnd(7)} ${r.table} / ${r.name}${r.displayFolder ? '   [' + r.displayFolder + ']' : ''}`);
  console.log(`\n${rows.length} object(s)`);
}

function cmdDeps(model, args) {
  const q = args._[1];
  if (!q) die('deps <name>');
  const ql = q.toLowerCase();
  // is it a measure or a column?
  const colMatch = allColumns(model).find(c => c.name.toLowerCase() === ql);
  const refsMeasure = [];
  for (const m of allMeasures(model)) {
    const r = extractRefs(m.expr);
    const hitMeasure = [...r.measures].some(x => x.toLowerCase() === ql);
    const hitColumn = [...r.columns].some(x => x.split('.')[1].toLowerCase() === ql);
    if (hitMeasure || hitColumn) refsMeasure.push({ table: m.table, name: m.name });
  }
  const relHits = model.relationships.filter(r =>
    r.from.col.toLowerCase() === ql || r.to.col.toLowerCase() === ql)
    .map(r => `${r.from.table}.${r.from.col} -> ${r.to.table}.${r.to.col}`);
  const result = { object: q, kind: colMatch ? 'column' : 'measure', referencedBy: refsMeasure, relationships: relHits };
  if (args.flags.json) return print(result);
  console.log(`${result.kind}: ${q}`);
  console.log(`referenced by ${refsMeasure.length} measure(s):`);
  for (const m of refsMeasure) console.log(`  ${m.table} / ${m.name}`);
  if (relHits.length) { console.log(`used in ${relHits.length} relationship(s):`); relHits.forEach(r => console.log('  ' + r)); }
  if (!refsMeasure.length && !relHits.length) console.log('  (no references found — safe to change)');
}

function cmdAudit(model, args) {
  const missing = [];
  for (const t of model.tables) {
    if (!t.description) missing.push({ kind: 'table', table: t.name, name: t.name });
    for (const m of t.measures) if (!m.hidden && !m.description) missing.push({ kind: 'measure', table: t.name, name: m.name });
    for (const c of t.columns) if (!c.hidden && !c.description) missing.push({ kind: 'column', table: t.name, name: c.name });
  }
  if (args.flags.json) return print({ missingDescriptions: missing });
  console.log(`AI-readiness audit — ${missing.length} visible object(s) missing a description:`);
  for (const o of missing) console.log(`  ${o.kind.padEnd(7)} ${o.table} / ${o.name}`);
  if (!missing.length) console.log('  all visible tables, columns, and measures are described.');
}

function cmdLint(model, args) {
  const measureNames = new Set(allMeasures(model).map(m => m.name.toLowerCase()));
  const colIndex = new Set(allColumns(model).map(c => `${c.table}.${c.name}`.toLowerCase()));
  const colNames = new Set(allColumns(model).map(c => c.name.toLowerCase()));
  const issues = [];
  // duplicate measure names
  const seen = new Map();
  for (const m of allMeasures(model)) {
    const k = m.name.toLowerCase();
    if (seen.has(k)) issues.push({ type: 'duplicate-measure', name: m.name, tables: [seen.get(k), m.table] });
    else seen.set(k, m.table);
  }
  // dangling refs
  for (const m of allMeasures(model)) {
    const r = extractRefs(m.expr);
    for (const mr of r.measures) {
      if (!measureNames.has(mr.toLowerCase()) && !colNames.has(mr.toLowerCase()))
        issues.push({ type: 'unknown-measure-ref', in: `${m.table}/${m.name}`, ref: `[${mr}]` });
    }
    for (const cr of r.columns) {
      const [tbl, col] = cr.split('.');
      if (!colIndex.has(`${tbl}.${col}`.toLowerCase()) && !colNames.has(col.toLowerCase()))
        issues.push({ type: 'unknown-column-ref', in: `${m.table}/${m.name}`, ref: cr });
    }
  }
  if (args.flags.json) return print({ issues });
  console.log(`lint — ${issues.length} issue(s):`);
  for (const x of issues) {
    if (x.type === 'duplicate-measure') console.log(`  DUP   measure '${x.name}' in ${x.tables.join(' and ')}`);
    else console.log(`  ${x.type === 'unknown-measure-ref' ? 'MREF' : 'CREF'}  ${x.in}: ${x.ref}`);
  }
  if (!issues.length) console.log('  no issues found.');
}

function print(obj) { console.log(JSON.stringify(obj, null, 2)); }

// ---------- main ----------

const argv = process.argv.slice(2);
const args = parseArgs(argv);
const cmd = args._[0];
if (!cmd || cmd === 'help' || args.flags.help) {
  console.log('pbip-model <show|list|deps|audit|lint> [args] [--model <path>] [--json]');
  process.exit(0);
}

const start = args.flags.model ? String(args.flags.model) : process.cwd();
const defDir = findDefinitionDir(start);
if (!defDir) die(`no *.SemanticModel found under ${start} (pass --model <path>)`);
const model = loadModel(defDir);

switch (cmd) {
  case 'show': cmdShow(model, args); break;
  case 'list': cmdList(model, args); break;
  case 'deps': cmdDeps(model, args); break;
  case 'audit': cmdAudit(model, args); break;
  case 'lint': cmdLint(model, args); break;
  default: die(`unknown command: ${cmd}`);
}
