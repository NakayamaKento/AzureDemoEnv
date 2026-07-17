param(
    [Parameter(Mandatory = $false)]
    [string]$ScenarioCode = 'sgsli01',

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-service-group-sli-demo-$ScenarioCode"
)

$ErrorActionPreference = 'Stop'

function Invoke-AzCli {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az $($Arguments -join ' ') failed: $($output | Out-String)"
    }

    return ($output | Out-String).Trim()
}

$workspaceName = Invoke-AzCli -Arguments @(
    'deployment', 'group', 'show',
    '--resource-group', $ResourceGroup,
    '--name', "sgsli-main-$ScenarioCode",
    '--query', 'properties.outputs.azureMonitorWorkspaceName.value',
    '-o', 'tsv'
)

$queryEndpoint = Invoke-AzCli -Arguments @(
    'resource', 'show',
    '--resource-group', $ResourceGroup,
    '--resource-type', 'Microsoft.Monitor/accounts',
    '--name', $workspaceName,
    '--api-version', '2025-10-03',
    '--query', 'properties.metrics.prometheusQueryEndpoint',
    '-o', 'tsv'
)

$accessToken = Invoke-AzCli -Arguments @(
    'account', 'get-access-token',
    '--resource', 'https://prometheus.monitor.azure.com',
    '--query', 'accessToken',
    '-o', 'tsv'
)

$headers = @{ Authorization = "Bearer $accessToken" }
$metrics = @(
    'orders_submitted_total',
    'order_submit_failures_total',
    'order_sli_good_requests_1m{job="order-api",environment="service-group-sli-demo"}',
    'order_sli_failed_requests_1m{job="order-api",environment="service-group-sli-demo"}',
    'order_submit_duration_milliseconds_count',
    'order_submit_duration_milliseconds_bucket{le="750.0"}'
)
$missingMetrics = @()

Write-Host "Azure Monitor Workspace: $workspaceName" -ForegroundColor Cyan
foreach ($metric in $metrics) {
    $encodedQuery = [System.Uri]::EscapeDataString($metric)
    $uri = "$($queryEndpoint.TrimEnd('/'))/api/v1/query?query=$encodedQuery"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 30
    $seriesCount = @($response.data.result).Count
    if ($seriesCount -eq 0) {
        Write-Host "  ! ${metric}: no series" -ForegroundColor Yellow
        $missingMetrics += $metric
        continue
    }

    Write-Host "  ✓ ${metric}: $seriesCount series" -ForegroundColor Green
    foreach ($series in $response.data.result) {
        $labels = ($series.metric.PSObject.Properties |
            Sort-Object Name |
            ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', '
        Write-Host "    value=$($series.value[1]) $labels" -ForegroundColor Gray
    }
}

if ($missingMetrics.Count -gt 0) {
    throw "必要な Prometheus series が見つかりません: $($missingMetrics -join ', ')"
}