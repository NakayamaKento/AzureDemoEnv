<#
.SYNOPSIS
OrderAvailability SLI の確認用に正常・失敗トラフィックを定期送信します。
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Endpoint,

    [Parameter(Mandatory = $false)]
    [string]$ScenarioCode = 'sgsli01',

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-service-group-sli-demo-$ScenarioCode",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3600)]
    [int]$IntervalSeconds = 30,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$NormalRequestsPerCycle = 5,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10000)]
    [int]$FailureEveryCycles = 10,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$FailureRequests = 2,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 1000000)]
    [int]$MaxCycles = 0
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
    throw 'API endpoint が見つかりません。-Endpoint を指定してください。'
}

$Endpoint = $Endpoint.TrimEnd('/')
$trafficScript = Join-Path $PSScriptRoot 'run-demo-traffic.ps1'
$cycle = 0

Write-Host "SLI test traffic: $Endpoint" -ForegroundColor Cyan
Write-Host "normal=$NormalRequestsPerCycle every=${IntervalSeconds}s, failure=$FailureRequests every $FailureEveryCycles cycles" -ForegroundColor Cyan
Write-Host '停止するには Ctrl+C を押してください。' -ForegroundColor Gray

try {
    while ($MaxCycles -eq 0 -or $cycle -lt $MaxCycles) {
        $cycle += 1
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "`n[$timestamp] cycle=$cycle normal" -ForegroundColor Cyan
        & $trafficScript `
            -Endpoint $Endpoint `
            -Count $NormalRequestsPerCycle `
            -DelaySeconds 0 `
            -FaultMode none `
            -Simulate

        if ($cycle % $FailureEveryCycles -eq 0) {
            Write-Host "[$timestamp] cycle=$cycle failure burst" -ForegroundColor Magenta
            & $trafficScript `
                -Endpoint $Endpoint `
                -Count $FailureRequests `
                -DelaySeconds 0 `
                -FaultMode api `
                -Simulate
        }

        if ($MaxCycles -eq 0 -or $cycle -lt $MaxCycles) {
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
} finally {
    Write-Host "`nSLI test traffic を停止しました。" -ForegroundColor Yellow
}

Write-Host "SLI test traffic completed: cycles=$cycle" -ForegroundColor Green