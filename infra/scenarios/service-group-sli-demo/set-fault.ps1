<#
.SYNOPSIS
Service Group SLI Demo の障害モードを切り替えます。
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('none', 'api', 'queue', 'worker', 'cosmos', 'storage', 'latency')]
    [string]$Mode,

    [Parameter(Mandatory = $false)]
    [string]$ScenarioCode = 'sgsli01',

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-service-group-sli-demo-$ScenarioCode",

    [Parameter(Mandatory = $false)]
    [string]$Endpoint
)

$ErrorActionPreference = 'Stop'

if (-not $Endpoint) {
    $mainDeployment = az deployment group show `
        --resource-group $ResourceGroup `
        --name "sgsli-main-$ScenarioCode" `
        -o json | ConvertFrom-Json

    $Endpoint = $mainDeployment.properties.outputs.webAppUrl.value
}

if (-not $Endpoint) {
    throw "API endpoint が見つかりません。-Endpoint を指定してください。"
}

$body = @{ mode = $Mode } | ConvertTo-Json -Compress
Write-Host "fault:mode = $Mode -> $Endpoint" -ForegroundColor Cyan
Invoke-RestMethod `
    -Uri "$Endpoint/api/faults" `
    -Method POST `
    -ContentType 'application/json' `
    -Body $body `
    -TimeoutSec 30 | Out-Null

$deadline = (Get-Date).AddSeconds(90)
do {
    $current = Invoke-RestMethod -Uri "$Endpoint/api/faults" -Method GET -TimeoutSec 30
    if ($current.mode -eq $Mode) {
        Write-Host "✓ 更新完了（反映済み: $Mode）" -ForegroundColor Green
        return
    }

    Write-Host "  -> 反映待ち: current=$($current.mode), expected=$Mode" -ForegroundColor Gray
    Start-Sleep -Seconds 5
} while ((Get-Date) -lt $deadline)

throw "障害モード $Mode が 90 秒以内に反映されませんでした。"
