param(
	[Parameter(Mandatory = $true, Position = 0)][string]$Query,
	[int]$Max = 5
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$docDir = Join-Path $root 'wiki-lua\blizzard_api_doc'
$index = Join-Path $root 'wiki-lua\INDEX-api.md'

function Get-BlockInfo([string[]]$lines, [int]$nameIdx) {
	# nameIdx = index (0-based) of the `Name = "..."` line of an entry; entry opens on the previous `\t\t{` line
	$open = $nameIdx - 1
	$close = -1
	for ($j = $nameIdx + 1; $j -lt $lines.Count; $j++) {
		if ($lines[$j] -match '^\t\t\},?\s*$') { $close = $j; break }
	}
	if ($close -lt 0) { $close = [Math]::Min($nameIdx + 80, $lines.Count - 1) }
	$block = $lines[$open..$close]
	$info = [pscustomobject]@{
		Method     = [bool](($block | Where-Object { $_ -match 'Method = true' } | Select-Object -First 1))
		Doc        = ''
		Args       = @()
		Returns    = @()
		Type       = ''
	}
	foreach ($l in $block) {
		if ($l -match 'Type = "(Function|Event|Constant|Field|Mixin|Callback)"') { $info.Type = $Matches[1] }
		if (-not $info.Doc -and $l -match 'Documentation = \{ "([^"]+)"') { $info.Doc = $Matches[1] }
	}
	$section = ''
	foreach ($l in $block) {
		if ($l -match '^\t\t\t(Arguments|Returns|Payload) =\s*$') { $section = $Matches[1]; continue }
		if ($l -match '^\t\t\t\},?\s*$') { $section = ''; continue }
		if ($section -and $l -match '\{ Name = "([^"]+)", Type = "([^"]+)"(.*)$') {
			$t = $Matches[2]
			if ($Matches[3] -match 'InnerType = "([^"]+)"') { $t = "$t<$($Matches[1])>" }
			$nil = if ($Matches[3] -match 'Nilable = true') { '?' } else { '' }
			$entry = "$($Matches[1]):$nil $t"
			if ($section -eq 'Arguments') { $info.Args += $entry } else { $info.Returns += $entry }
		}
	}
	return $info
}

# --- 1. exact/substring lookup in the generated index ---
$idxHits = @()
if (Test-Path -LiteralPath $index) {
	$idxHits = @(Select-String -LiteralPath $index -Pattern ("(?i)^\s*" + [regex]::Escape($Query) + "\b") | Select-Object -First $Max)
	if (-not $idxHits.Count) {
		$idxHits = @(Select-String -LiteralPath $index -Pattern ("(?i)\b" + [regex]::Escape($Query)) | Select-Object -First $Max)
	}
}

$shown = 0
foreach ($h in $idxHits) {
	if ($h.Line -notmatch '^(.*?)\s+`([^`:]+):(\d+)`') { continue }
	$apiName = $Matches[1].Trim()
	$luaFile = $Matches[2]
	$lineNo = [int]$Matches[3]
	$file = Join-Path $docDir ($luaFile -replace '/', '\')
	if (-not (Test-Path -LiteralPath $file)) { "$apiName  -> $file (index stale, run tools/build-index.ps1)"; continue }
	$lines = Get-Content -LiteralPath $file
	$hit = $null
	for ($i = $lineNo - 3; $i -lt $lineNo + 3; $i++) {
		if ($i -ge 0 -and $i -lt $lines.Count -and $lines[$i] -match 'Name = "([^"]+)"') {
			if ($apiName -like ('*' + $Matches[1])) { $hit = $i; break }
		}
	}
	if ($null -eq $hit) { $hit = $lineNo - 1 }
	$info = Get-BlockInfo $lines $hit
	"### $apiName  [$($info.Type)]"
	"file: wiki-lua/blizzard_api_doc\$luaFile`:$lineNo"
	if ($info.Doc) { "desc: $($info.Doc)" }
	if ($info.Args.Count) { "args: " + ($info.Args -join ', ') }
	if ($info.Returns.Count) { "returns: " + ($info.Returns -join ', ') }
	''
	$shown++
}
if ($shown) { exit 0 }

# --- 2. raw grep over blizzard_api_doc ---
$hits = @(Select-String -Path (Join-Path $docDir '*.lua') -Pattern ('Name = ".*' + [regex]::Escape($Query) + '.*"') |
	Select-Object -First ($Max * 6))
$seen = @{}
foreach ($h in $hits) {
	if ($h.Line -notmatch 'Name = "([^"]+)"') { continue }
	$name = $Matches[1]
	$key = "$($h.Path):$name"
	if ($seen.ContainsKey($name)) { continue }
	$seen[$name] = 1
	$lines = Get-Content -LiteralPath $h.Path
	# verify next non-blank line declares Function/Event type
	$type = ''
	for ($i = $h.LineNumber; $i -lt [Math]::Min($h.LineNumber + 4, $lines.Count); $i++) {
		if ($lines[$i] -match 'Type = "(Function|Event|Constant|Field|Mixin|Callback)"') { $type = $Matches[1]; break }
	}
	if (-not $type) { continue }
	$ns = ''; $sysName = ''
	foreach ($l in ($lines | Select-Object -First 12)) {
		if ($l -match 'Namespace = "([^"]+)"') { $ns = $Matches[1] + '.' }
		elseif ($l -match '^\tName = "([^"]+)"') { $sysName = $Matches[1] }
	}
	$info = Get-BlockInfo $lines ($h.LineNumber - 1)
	if ($info.Method -and -not $ns) { $full = "$($sysName):$name" }
	elseif ($ns) { $full = "$ns$name" }
	else { $full = $name }
	"### $full  [$($info.Type)]"
	"file: wiki-lua/blizzard_api_doc\$(Split-Path -Leaf $h.Path):$($h.LineNumber)"
	if ($info.Doc) { "desc: $($info.Doc)" }
	if ($info.Args.Count) { "args: " + ($info.Args -join ', ') }
	if ($info.Returns.Count) { "returns: " + ($info.Returns -join ', ') }
	''
	$shown++
	if ($shown -ge $Max) { break }
}
if (-not $shown) {
	"no match for '$Query' in blizzard_api_doc"
	$sim = @()
	if (Test-Path -LiteralPath $index) {
		$sim = @(Select-String -LiteralPath $index -Pattern ('(?i)' + [regex]::Escape($Query)) | Select-Object -First $Max)
	}
	if ($sim.Count) {
		"similar names from index:"
		$sim | ForEach-Object { "  " + ($_.Line -replace '\s+`.*$', '') }
	}
	# deprecated / global-only functions live outside blizzard_api_doc:
	$pageHit = Get-ChildItem -LiteralPath (Join-Path $root 'wiki-lua\pages\api') -Filter ("API_*$Query*.md") -ErrorAction SilentlyContinue | Select-Object -First $Max
	if ($pageHit) {
		"wiki page(s):"
		$pageHit | ForEach-Object { "  wiki-lua/pages/api/$($_.Name)" }
	}
	if (-not $sim.Count -and -not $pageHit) {
		"try full legacy list: grep 'wiki-lua/14_world_of_warcraft_api.md' or docs/wow_addons for '$Query'"
	}
}
