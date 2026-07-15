<#
.SYNOPSIS
Foundry Chat Baseline シナリオの完全デプロイスクリプト

.DESCRIPTION
このスクリプトは以下を自動実行します：
1. Azure リソースグループの作成
2. Bicep インフラのデプロイ（VNet, App Service, Foundry, Storage, Cosmos DB, Search等）
3. チャットアプリの npm install
4. アプリを zip 化して App Service にデプロイ

.PARAMETER ScenarioCode
リソース名のプレフィックス（デフォルト: fcb01）

.PARAMETER Location
デプロイリージョン（デフォルト: southeastasia）

.PARAMETER ResourceGroup
リソースグループ名（デフォルト: rg-foundry-chat-baseline-<scenariocode>）

.PARAMETER SubscriptionId
対象サブスクリプションID（省略時は現在のコンテキスト）

.EXAMPLE
PS> .\deploy.ps1 -ScenarioCode fcb01 -Location southeastasia
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ScenarioCode = 'fcb01',

    [Parameter(Mandatory = $false)]
    [string]$Location = 'southeastasia',

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-foundry-chat-baseline-$ScenarioCode",

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'

Write-Host "====== Foundry Chat Baseline デプロイスクリプト ======" -ForegroundColor Cyan
Write-Host "開始時刻: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

try {
    # ========== 1. Azure ログイン・サブスクリプション設定 ==========
    Write-Host "`n[1/5] Azure 認証・サブスクリプション確認" -ForegroundColor Yellow

    $context = az account show --query "id" -o tsv 2>$null
    if (-not $context) {
        Write-Host "  → Azure CLI でログインしていません。ブラウザでログインしてください。" -ForegroundColor Gray
        az login | Out-Null
    } else {
        Write-Host "  ✓ ログイン済み（ID: $context）" -ForegroundColor Green
    }

    if ($SubscriptionId) {
        Write-Host "  → サブスクリプションを切り替え: $SubscriptionId" -ForegroundColor Gray
        az account set --subscription $SubscriptionId
    }

    $currentSub = az account show --query "name" -o tsv
    Write-Host "  ✓ 現在のサブスクリプション: $currentSub" -ForegroundColor Green

    # ========== 2. リソースグループ作成 ==========
    Write-Host "`n[2/5] リソースグループ作成" -ForegroundColor Yellow

    $rgExists = az group exists --name $ResourceGroup -o tsv
    if ($rgExists -eq "true") {
        Write-Host "  ✓ リソースグループは既存: $ResourceGroup" -ForegroundColor Green
    } else {
        Write-Host "  → リソースグループを作成: $ResourceGroup in $Location" -ForegroundColor Gray
        $rgCreate = az group create -n $ResourceGroup -l $Location -o json 2>&1
        if ($LASTEXITCODE -ne 0) {
            if ($rgCreate -match 'LocationNotAvailableForResourceGroup') {
                $fallbackRgLocation = 'southeastasia'
                Write-Host "  → RG では $Location を使えないため、$fallbackRgLocation で再試行します" -ForegroundColor Yellow
                $rgCreate = az group create -n $ResourceGroup -l $fallbackRgLocation -o json 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "リソースグループ作成に失敗しました。詳細: $rgCreate"
                }
            } else {
                throw "リソースグループ作成に失敗しました。詳細: $rgCreate"
            }
        }

        Write-Host "  ✓ 作成完了" -ForegroundColor Green
    }

    # ========== 3. Bicep インフラデプロイ ==========
    Write-Host "`n[3/5] Bicep インフラをデプロイ（このステップは 10～15 分かかります）" -ForegroundColor Yellow

    $repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $bicepPath = Join-Path $repoRoot 'infra\scenarios\foundry-chat-baseline\bicep\main.bicep'

    if (-not (Test-Path $bicepPath)) {
        throw "Bicep ファイルが見つかりません: $bicepPath"
    }

    # 以前の失敗/削除で soft-delete 残存している Foundry アカウントを自動 purge する
    $softDeletedFoundry = az cognitiveservices account list-deleted `
        --query "[?starts_with(name, 'aif$ScenarioCode')].{name:name,location:location}" `
        -o json 2>$null | ConvertFrom-Json

    if ($softDeletedFoundry) {
        foreach ($deletedAccount in $softDeletedFoundry) {
            Write-Host "  → soft-delete 残存の Foundry アカウントを purge: $($deletedAccount.name)" -ForegroundColor Yellow
            az cognitiveservices account purge `
                --name $deletedAccount.name `
                --resource-group $ResourceGroup `
                --location $deletedAccount.location `
                2>&1 | Out-Null
            Write-Host "  ✓ purge 完了: $($deletedAccount.name)" -ForegroundColor Green
        }
    }

    # 以前の失敗で残った Cosmos DB アカウント(非成功状態)を削除して再試行可能にする
    $cosmosCandidates = az resource list `
        --resource-group $ResourceGroup `
        --resource-type 'Microsoft.DocumentDB/databaseAccounts' `
        --query "[?starts_with(name, 'cdb-$ScenarioCode') && ends_with(name, '-chat')].name" `
        -o tsv 2>$null

    if ($cosmosCandidates) {
        foreach ($cosmosNameCandidate in ($cosmosCandidates -split "`n" | Where-Object { $_ })) {
            $cosmosState = az cosmosdb show `
                --name $cosmosNameCandidate `
                --resource-group $ResourceGroup `
                --query "provisioningState" `
                -o tsv 2>$null

            if ($cosmosState -and $cosmosState -ne 'Succeeded') {
                Write-Host "  → 非成功状態の Cosmos DB を削除: $cosmosNameCandidate (state=$cosmosState)" -ForegroundColor Yellow
                az cosmosdb delete --name $cosmosNameCandidate --resource-group $ResourceGroup --yes 2>&1 | Out-Null
            }
        }
    }

    Write-Host "  → Bicep ファイル: $bicepPath" -ForegroundColor Gray

    $effectiveLocation = $Location
    Write-Host "  → デプロイ中... (location=$effectiveLocation)" -ForegroundColor Gray

    $deployment = az deployment group create `
        --resource-group $ResourceGroup `
        --name 'main' `
        --template-file $bicepPath `
        --parameters scenarioCode=$ScenarioCode location=$effectiveLocation `
        --only-show-errors `
        -o json 2>&1

    if ($LASTEXITCODE -ne 0) {
        if ($deployment -match 'FlagMustBeSetForRestore') {
            Write-Host "  → soft-delete 残存の Foundry アカウントを検出。purge して再試行します" -ForegroundColor Yellow

            $restoredMatch = [regex]::Match($deployment, "resourceGroups/[^/]+/providers/Microsoft.CognitiveServices/accounts/([^']+)'")
            if ($restoredMatch.Success) {
                $foundryToPurge = $restoredMatch.Groups[1].Value
                az cognitiveservices account purge `
                    --name $foundryToPurge `
                    --resource-group $ResourceGroup `
                    --location $effectiveLocation `
                    2>&1 | Out-Null
                Write-Host "  ✓ purge 完了: $foundryToPurge" -ForegroundColor Green
            }

            $deployment = az deployment group create `
                --resource-group $ResourceGroup `
                --name 'main' `
                --template-file $bicepPath `
                --parameters scenarioCode=$ScenarioCode location=$effectiveLocation `
                --only-show-errors `
                -o json 2>&1
        }

        if ($deployment -match 'DeploymentActive') {
            Write-Host "  → 既存の active デプロイ(main)を検出。キャンセルして再試行します" -ForegroundColor Yellow
            az deployment group cancel --resource-group $ResourceGroup --name 'main' 2>&1 | Out-Null
            $deployment = az deployment group create `
                --resource-group $ResourceGroup `
                --name 'main' `
                --template-file $bicepPath `
                --parameters scenarioCode=$ScenarioCode location=$effectiveLocation `
                --only-show-errors `
                -o json 2>&1
        }

        if ($deployment -match 'LocationNotAvailableForResourceType') {
            $fallbackDeploymentLocation = 'southeastasia'
            $effectiveLocation = $fallbackDeploymentLocation
            Write-Host "  → $Location は一部リソースで未対応のため、$effectiveLocation で再試行します" -ForegroundColor Yellow
            $deployment = az deployment group create `
                --resource-group $ResourceGroup `
                --name 'main' `
                --template-file $bicepPath `
                --parameters scenarioCode=$ScenarioCode location=$effectiveLocation `
                --only-show-errors `
                -o json 2>&1
        }

        if ($LASTEXITCODE -ne 0) {
            if ($deployment -match 'InternalSubscriptionIsOverQuotaForSku') {
                throw "Bicep デプロイに失敗しました。現在のサブスクリプションでは App Service Plan 用クォータが 0 のため、新規作成できません。Azure ポータルで App Service のクォータ引き上げ、または既存 App Service Plan の再利用が必要です。詳細: $deployment"
            }

            throw "Bicep デプロイに失敗しました。詳細: $deployment"
        }
    }

    $depJson = $deployment | ConvertFrom-Json
    $outputs = $depJson.properties.outputs

    $appServiceName = $outputs.appServiceName.value
    $appGatewayIp = $outputs.appGatewayPublicIp.value
    $foundryName = $outputs.foundryAccountName.value

    Write-Host "  ✓ インフラデプロイ完了" -ForegroundColor Green
    Write-Host "    - App Service: $appServiceName" -ForegroundColor Gray
    Write-Host "    - Application Gateway Public IP: $appGatewayIp" -ForegroundColor Gray
    Write-Host "    - Foundry Account: $foundryName" -ForegroundColor Gray

    # ========== 4. チャットアプリの zip 作成と App Service デプロイ ==========
    Write-Host "`n[4/5] チャットアプリの準備と App Service デプロイ" -ForegroundColor Yellow

    $appPath = Join-Path $repoRoot 'apps\foundry-chat-baseline'
    $packageJsonPath = Join-Path $appPath 'package.json'

    if (-not (Test-Path $packageJsonPath)) {
        throw "package.json が見つかりません: $packageJsonPath"
    }

    Write-Host "  → Oryx ビルドを有効化（デプロイ時に依存関係を解決）" -ForegroundColor Gray
    az webapp config appsettings set `
        --resource-group $ResourceGroup `
        --name $appServiceName `
        --settings SCM_DO_BUILD_DURING_DEPLOYMENT=true ENABLE_ORYX_BUILD=true | Out-Null

    Write-Host "  → アプリを zip 化..." -ForegroundColor Gray
    $zipPath = Join-Path $repoRoot 'chatui.zip'
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force | Out-Null
    }

    Compress-Archive -Path (Join-Path $appPath '*') -DestinationPath $zipPath -Force
    Write-Host "  ✓ zip 作成完了: $zipPath" -ForegroundColor Green

    Write-Host "  → App Service へ zip deploy（Kudu/Oryx）..." -ForegroundColor Gray
    az webapp deployment source config-zip `
        --resource-group $ResourceGroup `
        --name $appServiceName `
        --src $zipPath | Out-Null

    Write-Host "  ✓ App Service デプロイ完了" -ForegroundColor Green

    # ========== 5. 動作確認用エンドポイント表示 ==========
    Write-Host "`n[5/5] デプロイ完了 - 次のステップ" -ForegroundColor Yellow

    Write-Host "`n✅ インフラとアプリのデプロイが完了しました！`n" -ForegroundColor Green

    Write-Host "【次に実施する作業】" -ForegroundColor Cyan
    Write-Host "1. Foundry プロジェクト/エージェント作成：" -ForegroundColor White
    Write-Host "   .\infra\scenarios\foundry-chat-baseline\setup-foundry-agent.ps1" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "2. App Service の環境変数更新（ステップ1 終了後）：" -ForegroundColor White
    Write-Host "   .\infra\scenarios\foundry-chat-baseline\update-app-settings.ps1 -ResourceGroup $ResourceGroup -AppServiceName $appServiceName" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "3. ブラウザでチャットアプリにアクセス：" -ForegroundColor White
    Write-Host "   http://$appGatewayIp" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "【リソース情報】" -ForegroundColor Cyan
    Write-Host "  リソースグループ: $ResourceGroup" -ForegroundColor Gray
    Write-Host "  App Service 名: $appServiceName" -ForegroundColor Gray
    Write-Host "  Foundry アカウント: $foundryName" -ForegroundColor Gray
    Write-Host "  Application Gateway IP: $appGatewayIp" -ForegroundColor Gray

    Write-Host "`n終了時刻: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

} catch {
    Write-Host "`n❌ エラー: $_" -ForegroundColor Red
    exit 1
}
