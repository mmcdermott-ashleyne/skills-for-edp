<#
.SYNOPSIS
pbip-model — read-only query tool over a local PBIP semantic model (TMDL).

.DESCRIPTION
Parses the *.SemanticModel/definition files on disk and returns just the slice
you ask for, so you don't have to open every .tmdl file. No service, no auth,
no network — reads files only. Pure PowerShell; no Node.js required.

-Model resolves a *.SemanticModel dir, its definition/ dir, or any folder
containing exactly one *.SemanticModel. Defaults to the current directory.

.PARAMETER Command
One of: show | list | deps | audit | lint

  show <Name>   Show a measure / column / table block + props
  list          List objects (filter with -Measures/-Columns/-Tables, -Folder, -Table, -Hidden)
  deps <Name>   What references this object (rename/delete impact)
  audit         AI-readiness gaps (visible objects missing a description)
  lint          Offline checks: dangling refs, duplicate measure names

.PARAMETER Name
Object name for 'show' and 'deps' (case-insensitive).

.PARAMETER Model
Path to the PBIP project / *.SemanticModel / definition dir. Defaults to CWD.

.PARAMETER Json
Emit machine-readable JSON instead of text.

.EXAMPLE
pwsh bin/model.ps1 show "Net Sales" -Model "C:\path\to\pbip-project"

.EXAMPLE
pwsh bin/model.ps1 list -Measures -Folder Headcount

.EXAMPLE
pwsh bin/model.ps1 deps "Terminations"

.EXAMPLE
pwsh bin/model.ps1 audit
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command,
    [Parameter(Position = 1)][string]$Name,
    [string]$Model,
    [switch]$Measures,
    [switch]$Columns,
    [switch]$Tables,
    [string]$Folder,
    [string]$Table,
    [switch]$Hidden,
    [switch]$MissingDescriptions,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

function Die([string]$msg) { Write-Error ("error: " + $msg); exit 1 }

# ---------- TMDL parsing primitives ----------

function Get-Indent([string]$line) {
    if ($null -eq $line) { return 0 }
    return [regex]::Match($line, '^\t*').Value.Length
}
function Remove-Tabs([string]$line) { return ($line -replace '^\t+', '') }
function Remove-Quotes([string]$s) {
    $t = $s.Trim()
    if ($t -match '^''(.*)''$') { return $Matches[1].Trim() }
    return $t
}

$PROP_RE = [regex]'^([A-Za-z_][\w]*)\s*:\s*(.*)$'
# Table-qualifier and "[" must be on the same line ([ \t]*, never a newline).
$REF_RE  = [regex]'(?:(''[^'']+'')|(\b[A-Za-z_]\w*))?[ \t]*\[([^\]]+)\]'

function Parse-TableFile([string]$text) {
    $lines = $text -split "`r?`n"
    $table = [ordered]@{ name = $null; description = ''; measures = @(); columns = @(); partitions = 0 }
    $pending = @()
    $i = 0
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        if ($line.Trim() -eq '') { $i++; continue }
        $indent = Get-Indent $line
        $content = Remove-Tabs $line

        if ($content.StartsWith('///')) { $pending += $content.Substring(3).Trim(); $i++; continue }

        if ($content.StartsWith('table ')) {
            $table.name = Remove-Quotes $content.Substring(6)
            $table.description = ($pending -join ' ').Trim(); $pending = @()
            $i++; continue
        }

        if ($content.StartsWith('measure ') -or $content.StartsWith('column ')) {
            $isMeasure = $content.StartsWith('measure ')
            $objIndent = $indent
            $head = $content.Substring($(if ($isMeasure) { 8 } else { 7 }))
            $eq = $head.IndexOf('=')
            $namePart = if ($eq -ge 0) { $head.Substring(0, $eq) } else { $head }
            $oname = Remove-Quotes $namePart.Trim()
            $inlineExpr = if ($eq -ge 0) { $head.Substring($eq + 1).Trim() } else { '' }
            $description = ($pending -join ' ').Trim(); $pending = @()

            # gather the block (everything indented deeper than the object keyword)
            $block = @()
            $i++
            while ($i -lt $lines.Count) {
                $l = $lines[$i]
                if ($l.Trim() -ne '' -and (Get-Indent $l) -le $objIndent) { break }
                $block += $l
                $i++
            }
            # properties at objIndent+1 matching key:value; rest = expression
            $props = @{}
            $exprLines = @()
            foreach ($l in $block) {
                if ($l.Trim() -eq '') { continue }
                $ind = Get-Indent $l
                $c = Remove-Tabs $l
                $m = $null
                if ($ind -eq $objIndent + 1) { $mm = $PROP_RE.Match($c); if ($mm.Success) { $m = $mm } }
                if ($m) { $props[$m.Groups[1].Value] = $m.Groups[2].Value.Trim() }
                else { $exprLines += $c }
            }
            $expr = if ($inlineExpr) { $inlineExpr } else { $exprLines -join "`n" }
            $obj = [ordered]@{
                name          = $oname
                table         = $null
                description   = $description
                expr          = $expr
                formatString  = $(if ($props.ContainsKey('formatString')) { $props['formatString'] } else { '' })
                displayFolder = $(if ($props.ContainsKey('displayFolder')) { $props['displayFolder'] } else { '' })
                dataType      = $(if ($props.ContainsKey('dataType')) { $props['dataType'] } else { '' })
                hidden        = ($props['isHidden'] -eq 'true')
            }
            if ($isMeasure) { $table.measures += , $obj } else { $table.columns += , $obj }
            continue
        }

        if ($content.StartsWith('partition ')) { $table.partitions++; $pending = @(); $i++; continue }

        # any other line at table level — drop pending desc so it doesn't leak
        $pending = @()
        $i++
    }
    return $table
}

function Parse-Relationships([string]$text) {
    $rels = @()
    $lines = $text -split "`r?`n"
    $cur = $null
    foreach ($line in $lines) {
        $c = Remove-Tabs $line
        if ($c.StartsWith('relationship ')) { $cur = [ordered]@{ from = $null; to = $null }; $rels += , $cur }
        elseif ($cur) {
            $f = [regex]::Match($c, '^fromColumn:\s*(.+?)\.(.+)$')
            $t = [regex]::Match($c, '^toColumn:\s*(.+?)\.(.+)$')
            if ($f.Success) { $cur.from = @{ table = $f.Groups[1].Value.Trim(); col = $f.Groups[2].Value.Trim() } }
            if ($t.Success) { $cur.to = @{ table = $t.Groups[1].Value.Trim(); col = $t.Groups[2].Value.Trim() } }
        }
    }
    return @($rels | Where-Object { $_.from -and $_.to })
}

# ---------- reference extraction ----------

function Remove-DaxComments([string]$s) {
    $s = [regex]::Replace($s, '/\*[\s\S]*?\*/', ' ')      # block comments
    $s = [regex]::Replace($s, '(?m)(--|//).*$', ' ')      # line comments
    return $s
}
function Get-Refs([string]$exprRaw) {
    $expr = Remove-DaxComments $exprRaw
    $measures = New-Object 'System.Collections.Generic.HashSet[string]'
    $columns = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in $REF_RE.Matches($expr)) {
        $g1 = $m.Groups[1].Value
        $g2 = $m.Groups[2].Value
        $inner = $m.Groups[3].Value
        $tbl = if ($g1) { Remove-Quotes $g1 } else { $g2 }
        if ($tbl) { [void]$columns.Add("$tbl.$inner") } else { [void]$measures.Add($inner) }
    }
    return @{ measures = $measures; columns = $columns }
}

# ---------- model location & load ----------

$script:hits = @()
function Walk-ForModels([string]$dir, [int]$depth) {
    if ($depth -gt 4) { return }
    try { $entries = Get-ChildItem -LiteralPath $dir -Directory -ErrorAction Stop } catch { return }
    foreach ($e in $entries) {
        if ($e.Name.EndsWith('.SemanticModel')) {
            $d = Join-Path $e.FullName 'definition'
            if (Test-Path $d) { $script:hits += $d }
        }
        elseif (-not $e.Name.StartsWith('.') -and $e.Name -ne 'node_modules') {
            Walk-ForModels $e.FullName ($depth + 1)
        }
    }
}

function Find-DefinitionDir([string]$start) {
    $leaf = Split-Path $start -Leaf
    if ($leaf.EndsWith('.SemanticModel')) {
        $d = Join-Path $start 'definition'
        if (Test-Path $d) { return $d }
    }
    if ($leaf -eq 'definition' -and (Test-Path (Join-Path $start 'tables'))) { return $start }
    $script:hits = @()
    Walk-ForModels $start 0
    if ($script:hits.Count -eq 1) { return $script:hits[0] }
    if ($script:hits.Count -gt 1) {
        Die("Multiple semantic models found; pass -Model:`n" + (($script:hits | ForEach-Object { '  ' + $_ }) -join "`n"))
    }
    return $null
}

function Load-Model([string]$defDir) {
    $tables = @()
    $tablesDir = Join-Path $defDir 'tables'
    if (Test-Path $tablesDir) {
        foreach ($f in Get-ChildItem -LiteralPath $tablesDir -Filter *.tmdl -File) {
            $t = Parse-TableFile (Get-Content -LiteralPath $f.FullName -Raw)
            foreach ($m in $t.measures) { $m.table = $t.name }
            foreach ($c in $t.columns) { $c.table = $t.name }
            $tables += , $t
        }
    }
    $rels = @()
    $relFile = Join-Path $defDir 'relationships.tmdl'
    if (Test-Path $relFile) { $rels = Parse-Relationships (Get-Content -LiteralPath $relFile -Raw) }
    return [ordered]@{ defDir = $defDir; tables = $tables; relationships = $rels }
}

# ---------- helpers ----------

function Get-AllMeasures($model) { @($model.tables | ForEach-Object { $_.measures }) }
function Get-AllColumns($model) { @($model.tables | ForEach-Object { $_.columns }) }
function Write-Json($obj) { $obj | ConvertTo-Json -Depth 12 }

# ---------- commands ----------

function Cmd-Show($model) {
    $q = $Name
    if (-not $q) { Die 'show <Name>' }
    $ql = $q.ToLower()
    $found = @()
    foreach ($m in Get-AllMeasures $model | Where-Object { $_.name.ToLower() -eq $ql }) {
        $found += , ([ordered]@{ kind = 'measure'; table = $m.table; name = $m.name; description = $m.description; expr = $m.expr; formatString = $m.formatString; displayFolder = $m.displayFolder; dataType = $m.dataType; hidden = $m.hidden })
    }
    foreach ($c in Get-AllColumns $model | Where-Object { $_.name.ToLower() -eq $ql }) {
        $found += , ([ordered]@{ kind = 'column'; table = $c.table; name = $c.name; description = $c.description; expr = $c.expr; formatString = $c.formatString; displayFolder = $c.displayFolder; dataType = $c.dataType; hidden = $c.hidden })
    }
    foreach ($t in $model.tables | Where-Object { $_.name.ToLower() -eq $ql }) {
        $found += , ([ordered]@{ kind = 'table'; table = $t.name; name = $t.name; description = $t.description; measures = $t.measures.Count; columns = $t.columns.Count })
    }
    if (-not $found.Count) { Die "not found: $q" }
    if ($Json) { Write-Json $(if ($found.Count -eq 1) { $found[0] } else { $found }); return }
    foreach ($o in $found) {
        Write-Output ("{0}  {1}{2}" -f $o.kind.ToUpper(), $(if ($o.table -and $o.kind -ne 'table') { $o.table + ' / ' } else { '' }), $o.name)
        if ($o.kind -eq 'table') { Write-Output ("  measures: {0}   columns: {1}" -f $o.measures, $o.columns) }
        if ($o.formatString) { Write-Output "  formatString: $($o.formatString)" }
        if ($o.displayFolder) { Write-Output "  displayFolder: $($o.displayFolder)" }
        if ($o.dataType) { Write-Output "  dataType: $($o.dataType)" }
        if ($o.hidden) { Write-Output "  hidden: true" }
        Write-Output ("  description: {0}" -f $(if ($o.description) { $o.description } else { '(none)' }))
        if ($o.expr) {
            Write-Output "  expression:"
            foreach ($l in ($o.expr -split "`n")) { Write-Output ("    " + $l) }
        }
        Write-Output ""
    }
}

function Cmd-List($model) {
    $wantM = $Measures -or (-not $Columns -and -not $Tables)
    $wantC = $Columns -or (-not $Measures -and -not $Tables)
    $rows = @()
    if ($Tables) {
        $rows = @($model.tables | ForEach-Object { [ordered]@{ kind = 'table'; table = $_.name; name = $_.name; displayFolder = ''; hidden = $false } })
    }
    else {
        if ($wantM) { $rows += @(Get-AllMeasures $model | ForEach-Object { [ordered]@{ kind = 'measure'; table = $_.table; name = $_.name; displayFolder = $_.displayFolder; hidden = $_.hidden } }) }
        if ($wantC) { $rows += @(Get-AllColumns $model | ForEach-Object { [ordered]@{ kind = 'column'; table = $_.table; name = $_.name; displayFolder = $_.displayFolder; hidden = $_.hidden } }) }
    }
    if ($Table) { $rows = @($rows | Where-Object { $_.table.ToLower() -eq $Table.ToLower() }) }
    if ($Folder) { $rows = @($rows | Where-Object { ($_.displayFolder).ToLower().Contains($Folder.ToLower()) }) }
    if (-not $Hidden) { $rows = @($rows | Where-Object { -not $_.hidden }) }
    if ($Json) {
        Write-Json @($rows | ForEach-Object { [ordered]@{ kind = $_.kind; table = $_.table; name = $_.name; displayFolder = $(if ($_.displayFolder) { $_.displayFolder } else { '' }) } })
        return
    }
    foreach ($r in $rows) {
        Write-Output ("{0} {1} / {2}{3}" -f $r.kind.PadRight(7), $r.table, $r.name, $(if ($r.displayFolder) { '   [' + $r.displayFolder + ']' } else { '' }))
    }
    Write-Output ("`n{0} object(s)" -f $rows.Count)
}

function Cmd-Deps($model) {
    $q = $Name
    if (-not $q) { Die 'deps <Name>' }
    $ql = $q.ToLower()
    $colMatch = @(Get-AllColumns $model | Where-Object { $_.name.ToLower() -eq $ql }) | Select-Object -First 1
    $refsMeasure = @()
    foreach ($m in Get-AllMeasures $model) {
        $r = Get-Refs $m.expr
        $hitM = $false; foreach ($x in $r.measures) { if ($x.ToLower() -eq $ql) { $hitM = $true; break } }
        $hitC = $false; foreach ($x in $r.columns) { $p = $x.Split('.'); if ($p.Length -ge 2 -and $p[1].ToLower() -eq $ql) { $hitC = $true; break } }
        if ($hitM -or $hitC) { $refsMeasure += , ([ordered]@{ table = $m.table; name = $m.name }) }
    }
    $relHits = @($model.relationships |
        Where-Object { $_.from.col.ToLower() -eq $ql -or $_.to.col.ToLower() -eq $ql } |
        ForEach-Object { "$($_.from.table).$($_.from.col) -> $($_.to.table).$($_.to.col)" })
    $kind = if ($colMatch) { 'column' } else { 'measure' }
    if ($Json) {
        Write-Json ([ordered]@{ object = $q; kind = $kind; referencedBy = $refsMeasure; relationships = $relHits })
        return
    }
    Write-Output "${kind}: $q"
    Write-Output ("referenced by {0} measure(s):" -f $refsMeasure.Count)
    foreach ($m in $refsMeasure) { Write-Output ("  {0} / {1}" -f $m.table, $m.name) }
    if ($relHits.Count) { Write-Output ("used in {0} relationship(s):" -f $relHits.Count); $relHits | ForEach-Object { Write-Output ('  ' + $_) } }
    if (-not $refsMeasure.Count -and -not $relHits.Count) { Write-Output '  (no references found — safe to change)' }
}

function Cmd-Audit($model) {
    $missing = @()
    foreach ($t in $model.tables) {
        if (-not $t.description) { $missing += , ([ordered]@{ kind = 'table'; table = $t.name; name = $t.name }) }
        foreach ($m in $t.measures) { if (-not $m.hidden -and -not $m.description) { $missing += , ([ordered]@{ kind = 'measure'; table = $t.name; name = $m.name }) } }
        foreach ($c in $t.columns) { if (-not $c.hidden -and -not $c.description) { $missing += , ([ordered]@{ kind = 'column'; table = $t.name; name = $c.name }) } }
    }
    if ($Json) { Write-Json ([ordered]@{ missingDescriptions = $missing }); return }
    Write-Output ("AI-readiness audit — {0} visible object(s) missing a description:" -f $missing.Count)
    foreach ($o in $missing) { Write-Output ("  {0} {1} / {2}" -f $o.kind.PadRight(7), $o.table, $o.name) }
    if (-not $missing.Count) { Write-Output '  all visible tables, columns, and measures are described.' }
}

function Cmd-Lint($model) {
    $measureNames = @{}; foreach ($m in Get-AllMeasures $model) { $measureNames[$m.name.ToLower()] = $true }
    $colIndex = @{}; $colNames = @{}
    foreach ($c in Get-AllColumns $model) { $colIndex["$($c.table).$($c.name)".ToLower()] = $true; $colNames[$c.name.ToLower()] = $true }
    $issues = @()
    # duplicate measure names
    $seen = @{}
    foreach ($m in Get-AllMeasures $model) {
        $k = $m.name.ToLower()
        if ($seen.ContainsKey($k)) { $issues += , ([ordered]@{ type = 'duplicate-measure'; name = $m.name; tables = @($seen[$k], $m.table) }) }
        else { $seen[$k] = $m.table }
    }
    # dangling refs
    foreach ($m in Get-AllMeasures $model) {
        $r = Get-Refs $m.expr
        foreach ($mr in $r.measures) {
            if (-not $measureNames.ContainsKey($mr.ToLower()) -and -not $colNames.ContainsKey($mr.ToLower())) {
                $issues += , ([ordered]@{ type = 'unknown-measure-ref'; in = "$($m.table)/$($m.name)"; ref = "[$mr]" })
            }
        }
        foreach ($cr in $r.columns) {
            $parts = $cr.Split('.'); $tbl = $parts[0]; $col = $parts[1]
            if (-not $colIndex.ContainsKey("$tbl.$col".ToLower()) -and -not $colNames.ContainsKey($col.ToLower())) {
                $issues += , ([ordered]@{ type = 'unknown-column-ref'; in = "$($m.table)/$($m.name)"; ref = $cr })
            }
        }
    }
    if ($Json) { Write-Json ([ordered]@{ issues = $issues }); return }
    Write-Output ("lint — {0} issue(s):" -f $issues.Count)
    foreach ($x in $issues) {
        if ($x.type -eq 'duplicate-measure') { Write-Output ("  DUP   measure '{0}' in {1}" -f $x.name, ($x.tables -join ' and ')) }
        else { Write-Output ("  {0}  {1}: {2}" -f $(if ($x.type -eq 'unknown-measure-ref') { 'MREF' } else { 'CREF' }), $x.in, $x.ref) }
    }
    if (-not $issues.Count) { Write-Output '  no issues found.' }
}

# ---------- main ----------

if (-not $Command -or $Command -eq 'help') {
    Get-Help $PSCommandPath -Detailed
    exit 0
}

$start = if ($Model) { $Model } else { (Get-Location).Path }
$defDir = Find-DefinitionDir $start
if (-not $defDir) { Die "no *.SemanticModel found under $start (pass -Model <path>)" }
# NB: do not name this $model — it would collide (case-insensitively) with the
# [string]$Model parameter and coerce the model object to a string.
$loaded = Load-Model $defDir

switch ($Command) {
    'show'  { Cmd-Show $loaded }
    'list'  { Cmd-List $loaded }
    'deps'  { Cmd-Deps $loaded }
    'audit' { Cmd-Audit $loaded }
    'lint'  { Cmd-Lint $loaded }
    default { Die "unknown command: $Command" }
}
