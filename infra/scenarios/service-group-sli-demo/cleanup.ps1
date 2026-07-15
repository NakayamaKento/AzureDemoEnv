<#
.SYNOPSIS
Service Group SLI Demo の Azure リソースを削除します。

.DESCRIPTION
Resource Group と tenant-scope Service Group を削除します。誤削除防止のため、-Force が必須です。
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ScenarioCode = 'sgsli01',

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-service-group-sli-demo-$ScenarioCode",

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [ValidateRange(60, 3600)]
    [int]$TimeoutSeconds = 1800
)

$ErrorActionPreference = 'Stop'

if (-not $Force) {
    throw "削除するには -Force を指定してください。対象: $ResourceGroup / Service Groups for $ScenarioCode"
}

function Invoke-AzCli {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & az @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()
    if ($exitCode -ne 0) {
        throw "az $($Arguments -join ' ') failed: $text"
    }

    return $text
}

function Test-ServiceGroupExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $url = "https://management.azure.com/providers/Microsoft.Management/serviceGroups/${Name}?api-version=2024-02-01-preview"
    $output = & az rest --method get --url $url --only-show-errors -o none 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        return $true
    }

    $text = ($output | Out-String).Trim()
    if ($text -match '(?i)ResourceNotFound|NotFound|could not be found|status code 404|\b404\b') {
        return $false
    }

    throw "Service Group $Name の存在確認に失敗しました: $text"
}

function Wait-ServiceGroupDeleted {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (-not (Test-ServiceGroupExists -Name $Name)) {
            Write-Host "  ✓ Deleted Service Group: $Name" -ForegroundColor Green
            return
        }

        Write-Host "  -> waiting Service Group deletion: $Name" -ForegroundColor Gray
        Start-Sleep -Seconds 15
    } while ((Get-Date) -lt $deadline)

    throw "Service Group $Name が $TimeoutSeconds 秒以内に削除されませんでした。"
}

Write-Host "====== Service Group SLI Demo cleanup ======" -ForegroundColor Yellow

$managedResourceGroups = @()
$rgExists = (Invoke-AzCli -Arguments @('group', 'exists', '--name', $ResourceGroup, '-o', 'tsv')).Trim()
if ($rgExists -eq 'true') {
    $monitorAccountIds = Invoke-AzCli -Arguments @(
        'resource', 'list',
        '--resource-group', $ResourceGroup,
        '--resource-type', 'Microsoft.Monitor/accounts',
        '--query', '[].id',
        '-o', 'tsv'
    )
    foreach ($monitorAccountId in @($monitorAccountIds -split "`r?`n" | Where-Object { $_ })) {
        $managedNames = Invoke-AzCli -Arguments @(
            'group', 'list',
            '--query', "[?managedBy=='$monitorAccountId'].name",
            '-o', 'tsv'
        )
        $managedResourceGroups += @($managedNames -split "`r?`n" | Where-Object { $_ })
    }

    Write-Host "Deleting Resource Group: $ResourceGroup" -ForegroundColor Gray
    Invoke-AzCli -Arguments @('group', 'delete', '--name', $ResourceGroup, '--yes', '--no-wait', '-o', 'none') | Out-Null
    Invoke-AzCli -Arguments @(
        'group', 'wait',
        '--name', $ResourceGroup,
        '--deleted',
        '--interval', '15',
        '--timeout', "$TimeoutSeconds"
    ) | Out-Null
    Write-Host "  ✓ Deleted Resource Group: $ResourceGroup" -ForegroundColor Green
} else {
    Write-Host "Resource Group already absent: $ResourceGroup" -ForegroundColor Gray
}

foreach ($managedResourceGroup in $managedResourceGroups | Select-Object -Unique) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $managedExists = (Invoke-AzCli -Arguments @('group', 'exists', '--name', $managedResourceGroup, '-o', 'tsv')).Trim()
        if ($managedExists -ne 'true') {
            Write-Host "  ✓ Azure Monitor managed Resource Group absent: $managedResourceGroup" -ForegroundColor Green
            break
        }

        Write-Host "  -> waiting Azure Monitor managed Resource Group deletion: $managedResourceGroup" -ForegroundColor Gray
        Start-Sleep -Seconds 15
    } while ((Get-Date) -lt $deadline)

    if ($managedExists -eq 'true') {
        throw "Azure Monitor managed Resource Group $managedResourceGroup が $TimeoutSeconds 秒以内に削除されませんでした。"
    }
}

$normalizedScenarioCode = $ScenarioCode.ToLowerInvariant().Replace('-', '')
$serviceGroupNames = @(
    "sg-$normalizedScenarioCode-api",
    "sg-$normalizedScenarioCode-processing",
    "sg-$normalizedScenarioCode-data",
    "sg-$normalizedScenarioCode-observability",
    "sg-$normalizedScenarioCode-order-service"
)

foreach ($serviceGroupName in $serviceGroupNames) {
    $serviceGroupId = "/providers/Microsoft.Management/serviceGroups/$serviceGroupName"
    $serviceGroupUrl = "https://management.azure.com/providers/Microsoft.Management/serviceGroups/${serviceGroupName}?api-version=2024-02-01-preview"
    if (-not (Test-ServiceGroupExists -Name $serviceGroupName)) {
        Write-Host "Service Group already absent: $serviceGroupId" -ForegroundColor Gray
        continue
    }

    Write-Host "Deleting Service Group: $serviceGroupId" -ForegroundColor Gray
    Invoke-AzCli -Arguments @(
        'rest',
        '--method', 'delete',
        '--url', $serviceGroupUrl,
        '--only-show-errors',
        '-o', 'none'
    ) | Out-Null
    Wait-ServiceGroupDeleted -Name $serviceGroupName
}

Write-Host "✓ cleanup complete" -ForegroundColor Green
