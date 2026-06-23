<#
.SYNOPSIS
    新規 SRE Agent + Teams Bot 統合環境デプロイスクリプト
    
.DESCRIPTION
    1 つのリソースグループに全リソースを集約し、Container Apps ベースでデプロイします
    - Bicep テンプレートを使用して UAMI, Storage, Log Analytics, App Insights, ACR, 
      Container Apps Environment, Container App, Bot Service をプロビジョニング
    - SRE Agent は別 RG (eastus2) にデプロイ
    - Teams マニフェスト生成

.NOTES
    前提条件:
      - az login 済み（対象サブスクリプションが選択済み）
      - Docker がローカルで稼働中
      - Container App イメージが ACR に存在するか、ローカルでビルド可能
#>
[CmdletBinding()]
param(
    [string]$ScenarioCode = 'poc-test',
    [string]$Location      = 'koreacentral',
    [string]$AgentLocation = 'eastus2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# 設定値
# ─────────────────────────────────────────────────────────────────────────────
$SubscriptionId = '41071e92-3ceb-44a2-a41e-5c5255c5e5b9'
$TenantId       = 'e1b7b5a9-aacf-4cd3-bc37-5ef335686a3c'
$ResourceGroup  = "rg-sre-test-$(Get-Random -Maximum 10000)"
$ScriptDir      = $PSScriptRoot
$ContainerImageRepository = 'sre-teams-bot'
$ContainerImageTag = 'aca-v7'

function Ensure-ContainerImageTag {
    param(
        [Parameter(Mandatory = $true)][string]$ResourceGroupName,
        [Parameter(Mandatory = $true)][string]$ImageRepository,
        [Parameter(Mandatory = $true)][string]$ImageTag,
        [Parameter(Mandatory = $true)][string]$BaseDir
    )

    $acrName = az acr list -g $ResourceGroupName --query "[0].name" -o tsv
    if (-not $acrName) {
        throw "ACR が見つかりません (RG: $ResourceGroupName)"
    }

    $tagExists = az acr repository show-tags -n $acrName --repository $ImageRepository --query "contains(@, '$ImageTag')" -o tsv 2>$null
    if ($tagExists -eq 'true') {
        Write-Host "  ✔ ACR イメージタグ確認: $acrName/${ImageRepository}:$ImageTag" -ForegroundColor Green
        return
    }

    $dockerfilePath = Join-Path $BaseDir 'bot-app\Dockerfile'
    $buildContext = Join-Path $BaseDir 'bot-app'
    if (-not (Test-Path $dockerfilePath)) {
        throw "Dockerfile が見つかりません: $dockerfilePath"
    }

    Write-Host "  ⚠ ACR イメージ不足を検知。ビルドを実行します: $acrName/${ImageRepository}:$ImageTag" -ForegroundColor Yellow

    $maxBuildAttempts = 5
    $buildAttempt = 1
    while ($buildAttempt -le $maxBuildAttempts) {
        Write-Host "  [ACR build $buildAttempt/$maxBuildAttempts] 実行中..." -ForegroundColor Yellow
        $buildRaw = az acr build --registry $acrName --image "${ImageRepository}:$ImageTag" --file $dockerfilePath $buildContext 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host '  ✔ ACR ビルド成功' -ForegroundColor Green
            break
        }

        $buildText = ($buildRaw | Out-String)
        if ($buildText -match 'no such host|failed to login|lookup .*azurecr\.io') {
            if ($buildAttempt -lt $maxBuildAttempts) {
                Write-Host '  ⚠ ACR DNS 伝播待機中（30秒後に再試行）' -ForegroundColor Yellow
                Start-Sleep -Seconds 30
                $buildAttempt++
                continue
            }
        }

        Write-Host $buildText -ForegroundColor Red
        throw "ACR ビルド失敗: $acrName/${ImageRepository}:$ImageTag"
    }

    if ($buildAttempt -gt $maxBuildAttempts) {
        throw "ACR ビルド失敗（再試行上限）: $acrName/${ImageRepository}:$ImageTag"
    }
}

function ConvertFrom-AzJsonOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawText,

        [Parameter(Mandatory = $true)]
        [string]$ContextLabel
    )

    $normalized = $RawText.Trim()
    $jsonStart = $normalized.IndexOf('{')
    if ($jsonStart -lt 0) {
        throw "$ContextLabel のJSON出力が見つかりません。出力: $normalized"
    }

    $jsonText = $normalized.Substring($jsonStart)
    return ($jsonText | ConvertFrom-Json)
}

function Get-DeploymentOutputValue {
    param(
        [Parameter(Mandatory = $true)]$Outputs,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Outputs) {
        return $null
    }

    $prop = $Outputs.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return $null
    }

    $valueObj = $prop.Value
    if ($null -eq $valueObj) {
        return $null
    }

    $valueProp = $valueObj.PSObject.Properties['value']
    if ($null -eq $valueProp) {
        return $null
    }

    return $valueProp.Value
}

Write-Host "┌─────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│  新規 SRE Agent + Teams Bot 統合環境デプロイ          │" -ForegroundColor Cyan
Write-Host "├─────────────────────────────────────────────────────────┤" -ForegroundColor Cyan
Write-Host "│  リソースグループ: $ResourceGroup" -ForegroundColor Green
Write-Host "│  ロケーション:     $Location" -ForegroundColor Green
Write-Host "│  Agent ロケーション: $AgentLocation" -ForegroundColor Green
Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: サブスクリプション確認
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 1: サブスクリプション確認" -ForegroundColor Cyan
$currentRaw = az account show -o json 2>&1
$current = ConvertFrom-AzJsonOutput -RawText ($currentRaw | Out-String) -ContextLabel 'サブスクリプション確認'
Write-Host "  現在のサブスクリプション: $($current.name)" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: リソースプロバイダー登録
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 2: リソースプロバイダー登録" -ForegroundColor Cyan
az provider register --namespace Microsoft.App --wait 2>&1 | Out-Null
az provider register --namespace Microsoft.BotService --wait 2>&1 | Out-Null
Write-Host "  ✔ Microsoft.App, Microsoft.BotService" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: リソースグループ作成
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 3: リソースグループ作成" -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location | Out-Null
Write-Host "  ✔ $ResourceGroup ($Location)" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Bicep デプロイ（What-If）
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 4: デプロイ前検証（What-If）" -ForegroundColor Cyan
$bicepFile = Join-Path $ScriptDir 'bicep\main.bicep'

$whatIfResult = az deployment group what-if `
    --resource-group $ResourceGroup `
    --template-file $bicepFile `
    --parameters scenarioCode=$ScenarioCode location=$Location agentLocation=$AgentLocation tenantId=$TenantId containerImageRepository=$ContainerImageRepository containerImageTag=$ContainerImageTag `
    2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ What-If 検証失敗" -ForegroundColor Red
    Write-Host $whatIfResult -ForegroundColor Red
    throw 'What-If 検証失敗'
}
Write-Host "  ✔ What-If 検証成功" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Bicep デプロイ実行
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 5: Bicep デプロイ実行（約 5-10 分）" -ForegroundColor Cyan
$maxDeployAttempts = 2
$deployResult = $null

for ($attempt = 1; $attempt -le $maxDeployAttempts; $attempt++) {
    $deployRaw = az deployment group create `
        --resource-group $ResourceGroup `
        --template-file $bicepFile `
        --parameters scenarioCode=$ScenarioCode location=$Location agentLocation=$AgentLocation tenantId=$TenantId containerImageRepository=$ContainerImageRepository containerImageTag=$ContainerImageTag `
        --output json 2>&1

    if ($LASTEXITCODE -eq 0) {
        $deployResult = ConvertFrom-AzJsonOutput -RawText ($deployRaw | Out-String) -ContextLabel 'Bicepデプロイ'
        break
    }

    $deployText = ($deployRaw | Out-String)
    if ($attempt -lt $maxDeployAttempts -and $deployText -match 'MANIFEST_UNKNOWN|no such host|ContainerAppOperationError') {
        Write-Host "  ⚠ コンテナーイメージ未登録エラーを検知。自動復旧を実行します。" -ForegroundColor Yellow
        Ensure-ContainerImageTag -ResourceGroupName $ResourceGroup -ImageRepository $ContainerImageRepository -ImageTag $ContainerImageTag -BaseDir $ScriptDir
        Write-Host "  ↻ デプロイを再実行します。" -ForegroundColor Yellow
        continue
    }

    Write-Host $deployText -ForegroundColor Red
    throw 'Bicep デプロイ失敗'
}

if ($null -eq $deployResult) {
    throw 'Bicep デプロイ失敗'
}

$out = $deployResult.properties.outputs
Write-Host "  ✔ デプロイ完了" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: 出力値抽出
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 6: リソース情報抽出" -ForegroundColor Cyan
$containerAppName = Get-DeploymentOutputValue -Outputs $out -Name 'containerAppName'
$botMsaAppId = Get-DeploymentOutputValue -Outputs $out -Name 'botMsaAppId'
$containerAppFqdn = Get-DeploymentOutputValue -Outputs $out -Name 'containerAppFqdn'
$containerRegistryName = Get-DeploymentOutputValue -Outputs $out -Name 'containerRegistryName'

if (-not $containerAppName) {
    throw '出力値 containerAppName が取得できませんでした。'
}

if (-not $containerAppFqdn) {
    $caRaw = az containerapp show -g $ResourceGroup -n $containerAppName -o json 2>&1
    $caObj = ConvertFrom-AzJsonOutput -RawText ($caRaw | Out-String) -ContextLabel 'Container App 情報取得'
    $containerAppFqdn = $caObj.properties.configuration.ingress.fqdn
}

if (-not $botMsaAppId) {
    $botMsaAppId = Get-DeploymentOutputValue -Outputs $out -Name 'uamiClientId'
}

if ($containerRegistryName) {
    $acrLoginServer = "$containerRegistryName.azurecr.io"
} else {
    $acrNameFallback = az acr list -g $ResourceGroup --query "[0].name" -o tsv
    if ($acrNameFallback) {
        $acrLoginServer = "$acrNameFallback.azurecr.io"
    } else {
        $acrLoginServer = 'N/A'
    }
}

Write-Host "  ✔ Container App: $containerAppName" -ForegroundColor Green
Write-Host "  ✔ Bot MSA App ID: $botMsaAppId" -ForegroundColor Green
Write-Host "  ✔ FQDN: $containerAppFqdn" -ForegroundColor Green
Write-Host "  ✔ ACR: $acrLoginServer" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: Container App ヘルスチェック
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 7: Container App ヘルスチェック" -ForegroundColor Cyan
$maxAttempts = 30
$attempt = 0
$appHealthy = $false

while ($attempt -lt $maxAttempts) {
    $caStatusRaw = az containerapp show -g $ResourceGroup -n $containerAppName -o json 2>&1
    $caStatus = ConvertFrom-AzJsonOutput -RawText ($caStatusRaw | Out-String) -ContextLabel 'Container App ヘルス状態取得'
    $runningStatus = $caStatus.properties.runningStatus
    
    Write-Host "  [$($attempt + 1)/$maxAttempts] runningStatus=$runningStatus" -ForegroundColor Yellow
    
    if ($runningStatus -eq 'Running') {
        $appHealthy = $true
        break
    }
    
    Start-Sleep -Seconds 10
    $attempt++
}

if ($appHealthy) {
    Write-Host "  ✔ Container App は Running" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Container App がタイムアウト。手動確認が必要です" -ForegroundColor Yellow
}
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# Step 8: HTTP ヘルスチェック
# ─────────────────────────────────────────────────────────────────────────────
if ($appHealthy) {
    Write-Host "Step 8: HTTP ヘルスチェック" -ForegroundColor Cyan
    $healthUrl = "https://$containerAppFqdn/healthz"
    
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -TimeoutSec 10 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            Write-Host "  ✔ ヘルスチェック成功 ($($response.StatusCode))" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ ステータスコード: $($response.StatusCode)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ⚠ HTTP リクエスト失敗。URL: $healthUrl" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 9: Teams マニフェスト生成
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "Step 9: Teams マニフェスト生成" -ForegroundColor Cyan
$manifestDir = Join-Path $ScriptDir "teams-manifest-$($ResourceGroup)"
New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null

$manifest = @{
    "`$schema"       = 'https://developer.microsoft.com/en-us/json-schemas/teams/v1.16/MicrosoftTeams.schema.json'
    manifestVersion  = '1.16'
    version          = '1.0.0'
    id               = $botMsaAppId
    packageName      = "com.sreagent.teams.$ScenarioCode"
    developer        = @{
        name          = 'Azure Demo'
        websiteUrl    = 'https://azure.microsoft.com'
        privacyUrl    = 'https://privacy.microsoft.com/privacystatement'
        termsOfUseUrl = 'https://www.microsoft.com/en-us/legal/intellectualproperty/copyright'
    }
    name = @{
        short = 'SRE Agent Bot'
        full  = "Azure SRE Agent Teams Bot ($ScenarioCode)"
    }
    description = @{
        short = 'Chat with Azure SRE Agent from Teams'
        full  = 'Bidirectional real-time conversation with Azure SRE Agent via Microsoft Teams.'
    }
    icons = @{
        color   = 'color.png'
        outline = 'outline.png'
    }
    accentColor = '#0078D4'
    bots = @(@{
        botId           = $botMsaAppId
        scopes          = @('personal', 'team', 'groupchat')
        supportsFiles   = $false
        isNotificationOnly = $false
        commandLists    = @(@{
            scopes   = @('personal', 'team', 'groupchat')
            commands = @(
                @{ title = 'help';   description = 'Show usage' }
                @{ title = 'status'; description = 'Check SRE Agent status' }
            )
        })
    })
    permissions = @('identity', 'messageTeamMembers')
    validDomains = @($containerAppFqdn)
} | ConvertTo-Json -Depth 10

$manifest | Set-Content -Path (Join-Path $manifestDir 'manifest.json') -Encoding UTF8

# プレースホルダーアイコン
$pngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
[System.Convert]::FromBase64String($pngBase64) | Set-Content -Path (Join-Path $manifestDir 'color.png') -AsByteStream
[System.Convert]::FromBase64String($pngBase64) | Set-Content -Path (Join-Path $manifestDir 'outline.png') -AsByteStream

$zipPath = Join-Path $ScriptDir "TeamsAppPackage-$($ResourceGroup).zip"
if (Test-Path $zipPath) { Remove-Item $zipPath }
Compress-Archive -Path (Join-Path $manifestDir '*') -DestinationPath $zipPath -Force

Write-Host "  ✔ Teams マニフェスト: $zipPath" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# 完了サマリー
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "┌─────────────────────────────────────────────────────────┐" -ForegroundColor Green
Write-Host "│  ✅  デプロイ完了！                                   │" -ForegroundColor Green
Write-Host "├─────────────────────────────────────────────────────────┤" -ForegroundColor Green
Write-Host "│  📌 重要情報                                           │" -ForegroundColor Green
Write-Host "├─────────────────────────────────────────────────────────┤" -ForegroundColor Green
Write-Host "│  リソースグループ : $ResourceGroup" -ForegroundColor White
Write-Host "│  Bot App URL     : https://$containerAppFqdn/api/messages" -ForegroundColor White
Write-Host "│  Bot MSA App ID  : $botMsaAppId" -ForegroundColor White
Write-Host "│  Teams Package   : $zipPath" -ForegroundColor White
Write-Host "│  " -ForegroundColor Green
Write-Host "│  📱 Teams アプリのインストール手順" -ForegroundColor Cyan
Write-Host "│    1. Teams を開く" -ForegroundColor White
Write-Host "│    2. 対象チーム → Apps → Upload a custom app" -ForegroundColor White
Write-Host "│    3. $zipPath をアップロード" -ForegroundColor White
Write-Host "│  " -ForegroundColor Green
Write-Host "│  💬 テストコマンド（英語）" -ForegroundColor Cyan
Write-Host "│    > What Azure resources are in resource group ${ResourceGroup}?" -ForegroundColor White
Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Green
