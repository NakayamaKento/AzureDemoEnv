<#
.SYNOPSIS
Service Group SLI Demo の API にデモトラフィックを送信します。
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Endpoint,

    [Parameter(Mandatory = $false)]
    [string]$ScenarioCode = 'sgsli01',

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-service-group-sli-demo-$ScenarioCode",

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10000)]
    [int]$Count = 20,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 3600)]
    [int]$DelaySeconds = 1
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

$Endpoint = $Endpoint.TrimEnd('/')
Write-Host "Endpoint: $Endpoint" -ForegroundColor Cyan

$accepted = 0
$failed = 0

foreach ($index in 1..$Count) {
    $body = @{ customerId = "traffic-$index" } | ConvertTo-Json
    try {
        $response = Invoke-RestMethod `
            -Uri "$Endpoint/api/orders" `
            -Method POST `
            -ContentType 'application/json' `
            -Body $body `
            -TimeoutSec 30
        $accepted += 1
        Write-Host "[$index/$Count] accepted order=$($response.order.id) queued=$($response.queue.queued) mode=$($response.faultMode)" -ForegroundColor Green
    } catch {
        $failed += 1
        Write-Host "[$index/$Count] failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    if ($DelaySeconds -gt 0 -and $index -lt $Count) {
        Start-Sleep -Seconds $DelaySeconds
    }
}

Write-Host "`naccepted=$accepted failed=$failed" -ForegroundColor Cyan
