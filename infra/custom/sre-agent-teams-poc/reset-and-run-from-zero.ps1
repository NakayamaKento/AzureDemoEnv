[CmdletBinding()]
param(
    [string]$SubscriptionId = '41071e92-3ceb-44a2-a41e-5c5255c5e5b9',
    [string]$ScenarioCode = 'poc-v3',
    [string]$Location = 'koreacentral',
    [string]$AgentLocation = 'eastus2',
    [string]$DeleteRgNamePattern = 'rg-sre-*',
    [switch]$IncludeProd,
    [switch]$SkipDelete,
    [switch]$NoWaitDelete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$deployScript = Join-Path $scriptDir 'deploy-new-env.ps1'
$cleanupScript = Join-Path $scriptDir 'cleanup-artifacts.ps1'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) が見つかりません。インストール後に再実行してください。'
}

if (-not (Test-Path $deployScript)) {
    throw "deploy-new-env.ps1 が見つかりません: $deployScript"
}

Write-Host '=== Step 1: ローカル生成物の片付け ===' -ForegroundColor Cyan
if (Test-Path $cleanupScript) {
    & $cleanupScript
} else {
    Write-Host 'cleanup-artifacts.ps1 が見つからないためスキップします。' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '=== Step 2: Azure サブスクリプション設定 ===' -ForegroundColor Cyan
az account show -o none
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI にログインされていません。az login を実行してください。'
}
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "サブスクリプション切り替えに失敗しました: $SubscriptionId"
}
Write-Host "Subscription set: $SubscriptionId" -ForegroundColor Green

Write-Host ''
Write-Host '=== Step 3: 既存 SRE リソースグループ削除 ===' -ForegroundColor Cyan
if ($SkipDelete) {
    Write-Host 'SkipDelete が指定されたため、RG 削除をスキップします。' -ForegroundColor Yellow
} else {
    $rgNames = @(az group list --query "[?starts_with(name, 'rg-sre-')].name" -o tsv)
    if ($DeleteRgNamePattern -ne 'rg-sre-*') {
        $prefix = $DeleteRgNamePattern.TrimEnd('*')
        $rgNames = @($rgNames | Where-Object { $_ -like "$prefix*" })
    }

    if (-not $IncludeProd) {
        $rgNames = @($rgNames | Where-Object { $_ -notlike 'rg-sre-prod-*' })
    }

    if ($rgNames.Count -eq 0) {
        Write-Host '削除対象の RG はありません。' -ForegroundColor Green
    } else {
        Write-Host "削除対象 RG: $($rgNames -join ', ')" -ForegroundColor Yellow
        foreach ($rg in $rgNames) {
            if ($NoWaitDelete) {
                az group delete --name $rg --yes --no-wait
            } else {
                az group delete --name $rg --yes
            }
            if ($LASTEXITCODE -ne 0) {
                throw "RG 削除に失敗しました: $rg"
            }
            Write-Host "Deleted (requested): $rg" -ForegroundColor Green
        }

        if (-not $NoWaitDelete) {
            $timeoutSec = 1200
            $sleepSec = 10
            $elapsed = 0
            do {
                $remaining = @()
                foreach ($rg in $rgNames) {
                    $exists = (az group exists --name $rg | Out-String).Trim()
                    if ($exists -eq 'true') {
                        $remaining += $rg
                    }
                }

                if ($remaining.Count -eq 0) {
                    break
                }

                Write-Host "削除待機中: $($remaining -join ', ')" -ForegroundColor Yellow
                Start-Sleep -Seconds $sleepSec
                $elapsed += $sleepSec
            } while ($elapsed -lt $timeoutSec)

            if ($remaining.Count -gt 0) {
                throw "RG 削除待機タイムアウト: $($remaining -join ', ')"
            }
            Write-Host 'RG 削除完了を確認しました。' -ForegroundColor Green
        } else {
            Write-Host 'NoWaitDelete のため削除完了待機をスキップしました。' -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host '=== Step 4: 新規デプロイ ===' -ForegroundColor Cyan
& $deployScript -ScenarioCode $ScenarioCode -Location $Location -AgentLocation $AgentLocation
if ($LASTEXITCODE -ne 0) {
    throw '新規デプロイに失敗しました。'
}

Write-Host ''
Write-Host '=== 完了 ===' -ForegroundColor Green
Write-Host 'Teams 側は手動でアプリ登録・テストを実施してください。' -ForegroundColor White
