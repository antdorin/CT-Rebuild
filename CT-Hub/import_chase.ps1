$dataPath = Join-Path $env:APPDATA 'CT-Hub\chasetactical.json'
$importPath = Join-Path $PSScriptRoot 'chase_import.txt'

if (-not (Test-Path $dataPath)) {
  '[]' | Set-Content -Path $dataPath -Encoding UTF8
}

$existingRaw = Get-Content -Raw -Path $dataPath
$existing = @()
if ($existingRaw.Trim()) {
  $existing = $existingRaw | ConvertFrom-Json
}
if ($existing -isnot [System.Collections.IEnumerable]) {
  $existing = @($existing)
}

$seen = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($e in $existing) {
  if ($null -ne $e.bin -and $null -ne $e.label) {
    [void]$seen.Add("$($e.bin)|$($e.label)")
  }
}

$newItems = New-Object System.Collections.ArrayList
$bad = 0
$skipped = 0

Get-Content $importPath | ForEach-Object {
  $line = $_.Trim()
  if (-not $line) { return }

  $m = [regex]::Match($line, '^(.*?)\s+(\d+)?\s*([1-3]-[AB]-[1-6][A-F])$')
  if (-not $m.Success) { $bad++; return }

  $label = $m.Groups[1].Value.Trim()
  $qty = 0
  if ($m.Groups[2].Success -and $m.Groups[2].Value) {
    $qty = [int]$m.Groups[2].Value
  }
  $bin = $m.Groups[3].Value.Trim()

  if ([string]::IsNullOrWhiteSpace($label)) { $bad++; return }

  $key = "$bin|$label"
  if ($seen.Contains($key)) { $skipped++; return }

  $obj = [ordered]@{
    id = [guid]::NewGuid().ToString()
    bin = $bin
    label = $label
    qty = $qty
    notes = ''
  }

  [void]$newItems.Add([pscustomobject]$obj)
  [void]$seen.Add($key)
}

$merged = @($existing) + @($newItems)
$merged | ConvertTo-Json -Depth 5 | Set-Content -Path $dataPath -Encoding UTF8

Write-Output "Added=$($newItems.Count) Skipped=$skipped BadLines=$bad Total=$($merged.Count)"
Write-Output "DataFile=$dataPath"
