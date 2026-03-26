$p = Join-Path $env:APPDATA 'CT-Hub\chasetactical.json'
$arr = Get-Content -Raw $p | ConvertFrom-Json

$map = @{
'PIG.754D-0001'='DELTA Utility Gloves, BLACK, Small'
'PIG.754D-0002'='DELTA Utility Gloves, BLACK, Medium'
'PIG.754D-0003'='DELTA Utility Gloves, BLACK, Large'
'PIG.754D-0004'='DELTA Utility Gloves, BLACK, X-Large'
'PIG.754D-0005'='DELTA Utility Gloves, BLACK, 2X-Large'
'PIG.754D-0006'='DELTA Utility Gloves, COYOTE, Small'
'PIG.754D-0007'='DELTA Utility Gloves, COYOTE, Medium'
'PIG.754D-0008'='DELTA Utility Gloves, COYOTE, Large'
'PIG.754D-0009'='DELTA Utility Gloves, COYOTE, X-Large'
'PIG.754D-0010'='DELTA Utility Gloves, COYOTE, 2X-Large'
'PIG.754D-0011'='DELTA Utility Gloves, RANGER GREEN, Small'
'PIG.754D-0012'='DELTA Utility Gloves, RANGER GREEN, Medium'
'PIG.754D-0013'='DELTA Utility Gloves, RANGER GREEN, Large'
'PIG.754D-0014'='DELTA Utility Gloves, RANGER GREEN, X-Large'
'PIG.754D-0015'='DELTA Utility Gloves, RANGER GREEN, 2X-Large'
'PIG.754D-0021'='DELTA Utility Gloves, MULTICAM, Small'
'PIG.754D-0022'='DELTA Utility Gloves, MULTICAM, Medium'
'PIG.754D-0023'='DELTA Utility Gloves, MULTICAM, Large'
'PIG.754D-0024'='DELTA Utility Gloves, MULTICAM, X-Large'
'PIG.754D-0025'='DELTA Utility Gloves, MULTICAM, 2X-Large'
'PIG.754D-0026'='DELTA Utility Gloves, MULTICAM BLACK, Small'
'PIG.754D-0027'='DELTA Utility Gloves, MULTICAM BLACK, Medium'
'PIG.754D-0028'='DELTA Utility Gloves, MULTICAM BLACK, Large'
'PIG.754D-0029'='DELTA Utility Gloves, MULTICAM BLACK, X-Large'
'PIG.754D-0030'='DELTA Utility Gloves, MULTICAM BLACK, 2X-Large'
'PIG.700D-0001'='ALPHA Gloves GEN 2, BLACK, Small'
'PIG.700D-0002'='ALPHA Gloves GEN 2, BLACK, Medium'
'PIG.700D-0003'='ALPHA Gloves GEN 2, BLACK, Large'
'PIG.700D-0004'='ALPHA Gloves GEN 2, BLACK, X-Large'
'PIG.700D-0005'='ALPHA Gloves GEN 2, BLACK, 2X-Large'
'PIG.700D-0006'='ALPHA Gloves GEN 2, COYOTE, Small'
'PIG.700D-0007'='ALPHA Gloves GEN 2, COYOTE, Medium'
'PIG.700D-0008'='ALPHA Gloves GEN 2, COYOTE, Large'
'PIG.700D-0009'='ALPHA Gloves GEN 2, COYOTE, X-Large'
'PIG.700D-0010'='ALPHA Gloves GEN 2, COYOTE, 2X-Large'
'PIG.700D-0011'='ALPHA Gloves GEN 2, RANGER GREEN, Small'
'PIG.700D-0012'='ALPHA Gloves GEN 2, RANGER GREEN, Medium'
'PIG.700D-0013'='ALPHA Gloves GEN 2, RANGER GREEN, Large'
'PIG.700D-0014'='ALPHA Gloves GEN 2, RANGER GREEN, X-Large'
'PIG.700D-0015'='ALPHA Gloves GEN 2, RANGER GREEN, 2X-Large'
'PIG.700D-0021'='ALPHA Gloves GEN 2, MULTICAM, Small'
'PIG.700D-0022'='ALPHA Gloves GEN 2, MULTICAM, Medium'
'PIG.700D-0023'='ALPHA Gloves GEN 2, MULTICAM, Large'
'PIG.700D-0024'='ALPHA Gloves GEN 2, MULTICAM, X-Large'
'PIG.700D-0025'='ALPHA Gloves GEN 2, MULTICAM, 2X-Large'
'PIG.700D-0026'='ALPHA Gloves GEN 2, MULTICAM BLACK, Small'
'PIG.700D-0027'='ALPHA Gloves GEN 2, MULTICAM BLACK, Medium'
'PIG.700D-0028'='ALPHA Gloves GEN 2, MULTICAM BLACK, Large'
'PIG.700D-0029'='ALPHA Gloves GEN 2, MULTICAM BLACK, X-Large'
'PIG.700D-0030'='ALPHA Gloves GEN 2, MULTICAM BLACK, 2X-Large'
}

$updated = 0
foreach ($e in $arr) {
    $sku = [string]$e.label
    if ($map.ContainsKey($sku)) {
        $e.label = $map[$sku]
        if ([string]::IsNullOrWhiteSpace([string]$e.notes)) {
            $e.notes = $sku
        }
        elseif (-not ([string]$e.notes).Contains($sku, [System.StringComparison]::OrdinalIgnoreCase)) {
            $e.notes = "$sku | $($e.notes)"
        }
        $updated++
    }
}

$arr | ConvertTo-Json -Depth 10 | Set-Content -Path $p -Encoding UTF8
Write-Output "Updated=$updated Path=$p"
