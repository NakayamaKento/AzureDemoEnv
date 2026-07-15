<#
.SYNOPSIS
Service Group SLI Demo の主要リソースとエンドポイントを検証します。
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ScenarioCode = 'sgsli01',

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-service-group-sli-demo-$ScenarioCode",

    [Parameter(Mandatory = $false)]
    [switch]$RequireHealthModel
)

$ErrorActionPreference = 'Stop'

function Invoke-AzCli {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $false)]
        [switch]$AsJson
    )

    $output = & az @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($exitCode -ne 0) {
        throw "az $($Arguments -join ' ') failed: $text"
    }

    if ($AsJson) {
        return $text | ConvertFrom-Json
    }

    return $text
}

function Assert-Value {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    if (-not $Value) {
        throw "$Name が空です。"
    }

    Write-Host "✓ $Name" -ForegroundColor Green
}

Write-Host "====== Service Group SLI Demo 検証 ======" -ForegroundColor Cyan

$mainDeployment = Invoke-AzCli -Arguments @(
    'deployment', 'group', 'show',
    '--resource-group', $ResourceGroup,
    '--name', "sgsli-main-$ScenarioCode",
    '-o', 'json'
) -AsJson

$mainOutputs = $mainDeployment.properties.outputs
$normalizedScenarioCode = $ScenarioCode.ToLowerInvariant().Replace('-', '')
$serviceGroupNames = @(
    "sg-$normalizedScenarioCode-order-service",
    "sg-$normalizedScenarioCode-api",
    "sg-$normalizedScenarioCode-processing",
    "sg-$normalizedScenarioCode-data",
    "sg-$normalizedScenarioCode-observability"
)

Assert-Value -Name 'API App Service name' -Value $mainOutputs.webAppName.value
Assert-Value -Name 'Function App name' -Value $mainOutputs.functionAppName.value
Assert-Value -Name 'Service Group root id' -Value "/providers/Microsoft.Management/serviceGroups/sg-$normalizedScenarioCode-order-service"

$resourceIds = $mainOutputs.workloadResourceIds.value.PSObject.Properties.Value
foreach ($resourceId in $resourceIds) {
    Invoke-AzCli -Arguments @('resource', 'show', '--ids', $resourceId, '--only-show-errors', '-o', 'none') | Out-Null
}
Write-Host "✓ Workload resources" -ForegroundColor Green

foreach ($serviceGroupName in $serviceGroupNames) {
    Invoke-AzCli -Arguments @(
        'rest',
        '--method', 'get',
        '--url', "https://management.azure.com/providers/Microsoft.Management/serviceGroups/${serviceGroupName}?api-version=2024-02-01-preview",
        '--only-show-errors',
        '-o', 'none'
    ) | Out-Null
}
Write-Host "✓ Service Groups" -ForegroundColor Green

$healthDeploymentJson = az deployment group show `
    --resource-group $ResourceGroup `
    --name "sgsli-health-$ScenarioCode" `
    -o json 2>$null
if ($LASTEXITCODE -eq 0 -and $healthDeploymentJson) {
    $healthDeployment = $healthDeploymentJson | ConvertFrom-Json
    if ($healthDeployment.properties.provisioningState -eq 'Succeeded') {
        Assert-Value -Name 'Health Model id' -Value $healthDeployment.properties.outputs.healthModelId.value
        Invoke-AzCli -Arguments @(
            'resource', 'show',
            '--ids', $healthDeployment.properties.outputs.healthModelId.value,
            '--only-show-errors',
            '-o', 'none'
        ) | Out-Null
        Write-Host "✓ Health Model" -ForegroundColor Green
    } elseif ($RequireHealthModel) {
        throw "Health Model deployment state is $($healthDeployment.properties.provisioningState)."
    } else {
        Write-Host "! Health Model preview は未作成です: deployment state=$($healthDeployment.properties.provisioningState)" -ForegroundColor Yellow
    }
} elseif ($RequireHealthModel) {
    throw "Health Model deployment が見つかりません。"
} else {
    Write-Host "! Health Model preview はこの環境では未作成です。" -ForegroundColor Yellow
}

$webUrl = $mainOutputs.webAppUrl.value
$health = Invoke-RestMethod -Uri "$webUrl/healthz" -Method GET -TimeoutSec 30
Assert-Value -Name 'Health endpoint status' -Value $health.status
if ($health.status -ne 'ok') {
    throw "Health endpoint が正常ではありません: status=$($health.status), faultMode=$($health.faultMode)"
}
Write-Host "  status=$($health.status) faultMode=$($health.faultMode)" -ForegroundColor Gray

Write-Host "`n✅ 検証完了" -ForegroundColor Green
