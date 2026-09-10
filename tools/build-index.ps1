param(
	[string]$Out
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$docDir = Join-Path $root 'wiki-lua\blizzard_api_doc'
if (-not $Out) { $Out = Join-Path $root 'wiki-lua\INDEX-api.md' }

$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine('# INDEX-api.md — сгенерировано tools/build-index.ps1. GREP-индекс, НЕ читать целиком.')
[void]$sb.AppendLine(('# Источник: wiki-lua/blizzard_api_doc, дата: {0}' -f (Get-Date -Format 'yyyy-MM-dd')))
[void]$sb.AppendLine('# Формат: NAME<tab>`файл:строка`')
[void]$sb.AppendLine('')

$count = 0
foreach ($f in (Get-ChildItem -LiteralPath $docDir -Filter *.lua | Sort-Object Name)) {
	$lines = Get-Content -LiteralPath $f.FullName
	$ns = ''; $sysName = ''
	foreach ($l in ($lines | Select-Object -First 12)) {
		if ($l -match 'Namespace = "([^"]+)"') { $ns = $Matches[1] }
		elseif ($l -match '^\tName = "([^"]+)"') { $sysName = $Matches[1] }
	}
	$section = ''
	$isWidget = ($lines | Select-Object -First 5 | Where-Object { $_ -match 'Type = "ScriptObject"' }).Count -gt 0
	for ($i = 0; $i -lt $lines.Count; $i++) {
		$l = $lines[$i]
		if ($l -match '^\t(Functions|Events|Constants) =\s*$') { $section = $Matches[1]; continue }
		if ($l -match '^\t\},?\s*$') { $section = ''; continue }
		if (-not $section) { continue }
		if ($l -match '^\t\t\{\s*$' -and ($i + 1) -lt $lines.Count -and $lines[$i + 1] -match '^\t\t\tName = "([^"]+)"') {
			$name = $Matches[1]
			switch -Regex ($lines[$i + 2]) {
				'Type = "Function"' {
					if ($ns) { $full = "$ns.$name" }
					elseif ($isWidget) { $full = "$sysName.$name" }
					else { $full = $name }
				}
				'Type = "Event"'    { $full = "EVENT $name" }
				'Type = "Constant"' { $full = "CONST $name" }
				default             { $full = $null }
			}
			if (-not $full) { continue }
			[void]$sb.AppendLine(("{0}`t``{1}:{2}``" -f $full, $f.Name, ($i + 2)))
			$count++
			if ($lines[$i + 2] -match 'Type = "Event"' -and ($i + 3) -lt $lines.Count -and $lines[$i + 3] -match 'LiteralName = "([^"]+)"') {
				[void]$sb.AppendLine(("EVENT {0}`t``{1}:{2}``" -f $Matches[1], $f.Name, ($i + 2)))
				$count++
			}
		}
	}
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine(("# всего записей: $count"))
Set-Content -LiteralPath $Out -Value $sb.ToString() -Encoding UTF8
"index written: $Out ($count entries)"
