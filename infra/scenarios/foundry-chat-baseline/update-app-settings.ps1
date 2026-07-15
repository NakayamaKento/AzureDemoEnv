<#
.SYNOPSIS
App Service の環境変数（アプリ設定）を更新するスクリプト

.DESCRIPTION
このスクリプトは以下を実行します：
1. setup-foundry-agent.ps1 で取得したエージェント ID とバージョンを設定
2. Foundry の接続情報を App Service 環境変数に反映
3. アプリを再起動

.PARAMETER ResourceGroup
リソースグループ名

.PARAMETER AppServiceName
App Service 名（省略時は自動取得）

.PARAMETER AgentId
Foundry エージェント ID

.PARAMETER AgentVersion
Foundry エージェントバージョン

.EXAMPLE
PS> .\update-app-settings.ps1 -ResourceGroup rg-foundry-chat-baseline-fcb01 -AgentId baseline-chatbot-agent -AgentVersion 1
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$AppServiceName,

    [Parameter(Mandatory = $true)]
    [string]$AgentId,

    [Parameter(Mandatory = $true)]
    [string]$AgentVersion
)

$ErrorActionPreference = 'Stop'

Write-Host "====== App Service 環境変数更新スクリプト ======" -ForegroundColor Cyan
Write-Host "開始時刻: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

try {
    # ========== 1. App Service 名の自動取得 ==========
    if (-not $AppServiceName) {
        Write-Host "`n[1/3] App Service 検索" -ForegroundColor Yellow
        Write-Host "  → App Service を検索..." -ForegroundColor Gray

        $appServices = az webapp list `
            --resource-group $ResourceGroup `
            --query '[0].name' -o tsv 2>$null

        if (-not $appServices) {
            throw "リソースグループ内に App Service が見つかりません: $ResourceGroup"
        }

        $AppServiceName = $appServices
        Write-Host "  ✓ 見つかった App Service: $AppServiceName" -ForegroundColor Green
    } else {
        Write-Host "`n[1/3] App Service 確認" -ForegroundColor Yellow
        Write-Host "  ✓ 指定された App Service: $AppServiceName" -ForegroundColor Green
    }

    # ========== 2. Foundry リソース情報取得 ==========
    Write-Host "`n[2/3] Foundry リソース情報取得" -ForegroundColor Yellow

    $foundryResources = az resource list `
        --resource-group $ResourceGroup `
        --resource-type 'Microsoft.CognitiveServices/accounts' `
        --query '[0].name' -o tsv 2>$null

    if (-not $foundryResources) {
        throw "Foundry（Azure AI Services）が見つかりません"
    }

    $foundryName = $foundryResources
    $foundryEndpoint = "https://${foundryName}.services.ai.azure.com/api/projects/projchat"

    Write-Host "  ✓ Foundry エンドポイント: $foundryEndpoint" -ForegroundColor Green

    # ========== 3. 環境変数を更新 ==========
    Write-Host "`n[3/3] App Service 設定更新" -ForegroundColor Yellow

    Write-Host "  → 環境変数を設定..." -ForegroundColor Gray
    Write-Host "    - FOUNDRY_PROJECT_ENDPOINT=$foundryEndpoint" -ForegroundColor Gray
    Write-Host "    - FOUNDRY_AGENT_ID=$AgentId" -ForegroundColor Gray
    Write-Host "    - FOUNDRY_AGENT_VERSION=$AgentVersion" -ForegroundColor Gray

    az webapp config appsettings set `
        --name $AppServiceName `
        --resource-group $ResourceGroup `
        --settings `
            FOUNDRY_PROJECT_ENDPOINT=$foundryEndpoint `
            FOUNDRY_AGENT_ID=$AgentId `
            FOUNDRY_AGENT_VERSION=$AgentVersion `
        | Out-Null

    Write-Host "  ✓ 設定完了" -ForegroundColor Green

    Write-Host "  → App Service を再起動..." -ForegroundColor Gray
    az webapp restart `
        --name $AppServiceName `
        --resource-group $ResourceGroup `
        | Out-Null

    Write-Host "  ✓ 再起動完了" -ForegroundColor Green

    # ========== 4. 完了メッセージ ==========
    Write-Host "`n✅ 設定更新完了！`n" -ForegroundColor Green

    Write-Host "【ブラウザでアクセス】" -ForegroundColor Cyan
    $appGatewayIp = az deployment group show `
        --name "main" `
        --resource-group $ResourceGroup `
        --query 'properties.outputs.appGatewayPublicIp.value' -o tsv 2>$null

    if ($appGatewayIp) {
        Write-Host "  http://$appGatewayIp" -ForegroundColor Yellow
    } else {
        Write-Host "  https://${AppServiceName}.azurewebsites.net" -ForegroundColor Yellow
    }

    Write-Host "`n終了時刻: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

} catch {
    Write-Host "`n❌ エラー: $_" -ForegroundColor Red
    exit 1
}
