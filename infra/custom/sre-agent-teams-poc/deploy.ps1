<#
.SYNOPSIS
    Azure SRE Agent + Teams 双方向会話 POC デプロイスクリプト

.DESCRIPTION
    以下のステップを自動実行します:
      1. Azure リソースグループ作成
      2. Bicep デプロイ（UAMI, Storage, Functions, Bot Service, Teams チャンネル）
      3. SRE Agent デプロイ（az rest — プレビュー API 直呼び）
      4. SRE Agent が Running になるまで待機
      5. RBAC ロール割り当て（SRE Agent User を UAMI に付与）
      6. Functions アプリ設定を SRE Agent 情報で更新
      7. Bot App コードをビルド・デプロイ
      8. Teams アプリマニフェスト生成

.NOTES
    前提条件:
      - az login 済み（対象サブスクリプションが選択済み）
      - Azure Functions Core Tools (func) がインストール済み
      - Node.js 20+ がインストール済み
      - npm がインストール済み
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# 設定値（デプロイ対象の情報）
# ─────────────────────────────────────────────────────────────────────────────
$SubscriptionId = '41071e92-3ceb-44a2-a41e-5c5255c5e5b9'
$TenantId       = 'e1b7b5a9-aacf-4cd3-bc37-5ef335686a3c'
$ResourceGroup  = 'rg-sre-agent-poc'
$Location       = 'koreacentral'
$ScenarioCode   = 'poc'
$AgentName      = 'sre-agent-poc'
$ScriptDir      = $PSScriptRoot

# ─────────────────────────────────────────────────────────────────────────────
# ヘルパー関数
# ─────────────────────────────────────────────────────────────────────────────
function Write-Step { param([string]$Msg) Write-Host "`n=== $Msg ===" -ForegroundColor Cyan }
function Write-OK   { param([string]$Msg) Write-Host "  ✔ $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  ⚠ $Msg" -ForegroundColor Yellow }

# ─────────────────────────────────────────────────────────────────────────────
# Step 0: サブスクリプション設定
# ─────────────────────────────────────────────────────────────────────────────
Write-Step 'Step 0: サブスクリプション選択'
az account set --subscription $SubscriptionId
Write-OK "Subscription: $SubscriptionId"

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: リソースプロバイダー登録
# ─────────────────────────────────────────────────────────────────────────────
Write-Step 'Step 1: リソースプロバイダー登録'
az provider register --namespace Microsoft.App        --wait
az provider register --namespace Microsoft.BotService --wait
Write-OK 'Microsoft.App, Microsoft.BotService 登録完了'

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: リソースグループ作成
# ─────────────────────────────────────────────────────────────────────────────
Write-Step 'Step 2: リソースグループ作成'
az group create --name $ResourceGroup --location $Location | Out-Null
Write-OK "Resource Group: $ResourceGroup ($Location)"

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Bicep デプロイ（UAMI / Storage / Functions / Bot Service）
# ─────────────────────────────────────────────────────────────────────────────
Write-Step 'Step 3: Bicep デプロイ（約 5 分）'
$bicepFile = Join-Path $ScriptDir 'bicep\main.bicep'

$deployResult = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file  $bicepFile `
    --parameters     scenarioCode=$ScenarioCode location=$Location tenantId=$TenantId `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) { throw 'Bicep デプロイ失敗' }

$out            = $deployResult.properties.outputs
$FuncAppName    = $out.funcAppName.value
$UamiId         = $out.uamiId.value
$UamiClientId   = $out.uamiClientId.value
$UamiPrincipalId= $out.uamiPrincipalId.value
$AppInsightsId  = $out.appInsightsId.value
$RgId           = $out.resourceGroupId.value
$BotMsaAppId    = $out.botMsaAppId.value

Write-OK "Functions App : $FuncAppName"
Write-OK "Bot MSA App ID: $BotMsaAppId"
Write-OK "UAMI Principal: $UamiPrincipalId"

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: SRE Agent デプロイ（az rest — プレビュー API 直呼び）
# ─────────────────────────────────────────────────────────────────────────────
Write-Step 'Step 4: SRE Agent デプロイ (az rest)'

$AgentResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.App/agents/$AgentName"
$AgentApiUrl     = "https://management.azure.com${AgentResourceId}?api-version=2025-05-01-preview"

$agentBody = @{
    location = $Location
    identity = @{
        type = 'UserAssigned'
        userAssignedIdentities = @{
            $UamiId = @{}
        }
    }
    properties = @{
        actionConfiguration = @{
            mode        = 'Review'
            accessLevel = 'Low'
        }
        defaultModel = @{
            provider = 'Anthropic'
            name     = 'Automatic'
        }
        logConfiguration = @{
            appInsightsId = $AppInsightsId
        }
        knowledgeGraphConfiguration = @{
            identity         = $UamiId
            managedResources = @($RgId)
        }
    }
} | ConvertTo-Json -Depth 10

az rest --method PUT --url $AgentApiUrl --body $agentBody --headers 'Content-Type=application/json' | Out-Null
Write-OK "SRE Agent PUT 送信完了 — プロビジョニング待機中..."

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: SRE Agent が Running になるまで待機（最大 10 分）
# ─────────────────────────────────────────────────────────────────────────────
Write-Step 'Step 5: SRE Agent 起動待機'

$maxWaitSec = 600
$elapsed    = 0
$agentData  = $null

while ($elapsed -lt $maxWaitSec) {
    Start-Sleep -Seconds 15
    $elapsed += 15

    $agentData = az rest --method GET --url $AgentApiUrl --output json | ConvertFrom-Json
    $state     = $agentData.properties.powerState
    $prov      = $agentData.properties.provisioningState

    Write-Host "  ($($elapsed)s) powerState=$state  provisioningState=$prov"

    if ($state -eq 'Running') { break }
    if ($prov  -eq 'Failed')  { throw 'SRE Agent デプロイ失敗' }
}

if ($agentData.properties.powerState -ne 'Running') {
    throw "SRE Agent が $maxWaitSec 秒以内に Running になりませんでした"
}

$AgentEndpoint = $agentData.properties.agentEndpoint
Write-OK "SRE Agent Running: $AgentEndpoint"

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: SRE Agent User RBAC を UAMI に割り当て
# ─────────────────────────────────────────────────────────────────────────────
Write-Step 'Step 6: RBAC — SRE Agent User ロール割り当て'

$sreAgentUserRole = az role definition list --name 'SRE Agent User' --output json |
    ConvertFrom-Json |
    Select-Object -First 1 -ExpandProperty id

if (-not $sreAgentUserRole) {
    Write-Warn '"SRE Agent User" ロールが見つかりません。Reader ロールで代替します。'
    $sreAgentUserRole = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'  # Reader
}

az role assignment create `
    --assignee-object-id  $UamiPrincipalId `
    --assignee-principal-type ServicePrincipal `
    --role                $sreAgentUserRole `
    --scope               $AgentResourceId | Out-Null

Write-OK "RBAC 割り当て完了: $sreAgentUserRole → $UamiPrincipalId"

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: Functions アプリ設定を SRE Agent 情報で更新
# ─────────────────────────────────────────────────────────────────────────────
Write-Step 'Step 7: Functions アプリ設定更新'

az functionapp config appsettings set `
    --name           $FuncAppName `
    --resource-group $ResourceGroup `
    --settings       "SRE_AGENT_RESOURCE_ID=$AgentResourceId" "SRE_AGENT_ENDPOINT=$AgentEndpoint" |
    Out-Null

Write-OK "SRE_AGENT_ENDPOINT 設定完了"

# ─────────────────────────────────────────────────────────────────────────────
# Step 8: Bot App ビルド・デプロイ
# ─────────────────────────────────────────────────────────────────────────────
Write-Step 'Step 8: Bot App デプロイ'

$botAppDir = Join-Path $ScriptDir 'bot-app'
Push-Location $botAppDir

Write-Host '  npm install...'
npm install --silent
if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'npm install 失敗' }

Write-Host "  func azure functionapp publish $FuncAppName ..."
func azure functionapp publish $FuncAppName --node
if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'func publish 失敗' }

Pop-Location
Write-OK "Bot App デプロイ完了"

# ─────────────────────────────────────────────────────────────────────────────
# Step 9: Teams アプリマニフェスト生成
# ─────────────────────────────────────────────────────────────────────────────
Write-Step 'Step 9: Teams アプリマニフェスト生成'

$manifestDir = Join-Path $ScriptDir 'teams-manifest'
New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null

$manifest = @{
    "`$schema"       = 'https://developer.microsoft.com/en-us/json-schemas/teams/v1.16/MicrosoftTeams.schema.json'
    manifestVersion  = '1.16'
    version          = '1.0.0'
    id               = $BotMsaAppId
    packageName      = 'com.sreagent.teams.poc'
    developer        = @{
        name          = 'Azure Demo'
        websiteUrl    = 'https://azure.microsoft.com'
        privacyUrl    = 'https://privacy.microsoft.com/privacystatement'
        termsOfUseUrl = 'https://www.microsoft.com/en-us/legal/intellectualproperty/copyright'
    }
    name = @{
        short = 'SRE Agent Bot'
        full  = 'Azure SRE Agent Teams Bot (POC)'
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
        botId           = $BotMsaAppId
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
    validDomains = @("$FuncAppName.azurewebsites.net")
} | ConvertTo-Json -Depth 10

$manifest | Set-Content -Path (Join-Path $manifestDir 'manifest.json') -Encoding UTF8

# プレースホルダーアイコン（1×1 px PNG base64）を生成
$pngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
[System.Convert]::FromBase64String($pngBase64) |
    Set-Content -Path (Join-Path $manifestDir 'color.png')   -AsByteStream
[System.Convert]::FromBase64String($pngBase64) |
    Set-Content -Path (Join-Path $manifestDir 'outline.png') -AsByteStream

# ZIP 化
$zipPath = Join-Path $ScriptDir 'TeamsAppPackage.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath }
Compress-Archive -Path (Join-Path $manifestDir '*') -DestinationPath $zipPath

Write-OK "Teams マニフェスト: $zipPath"

# ─────────────────────────────────────────────────────────────────────────────
# 完了サマリー
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n" + ('─' * 60) -ForegroundColor Green
Write-Host '✅  デプロイ完了！' -ForegroundColor Green
Write-Host ('─' * 60) -ForegroundColor Green

Write-Host @"

📌 重要情報（メモしてください）
  Bot MSA App ID    : $BotMsaAppId
  Functions App URL : https://$FuncAppName.azurewebsites.net
  SRE Agent Endpoint: $AgentEndpoint
  SRE Agent Portal  : https://sre.azure.com

📱 Teams アプリのインストール手順（ユーザーが実施）
  1. Teams を開く
  2. 対象チーム / チャンネル → Apps → Upload a custom app
  3. [$zipPath] をアップロード
  4. SRE Agent Bot をチームまたは個人チャットに追加

💬 動作確認コマンド（英語で入力）
  > What Azure resources are in resource group $ResourceGroup?
  > List all Azure subscriptions I have access to.

⚠️  注意事項
  - SRE Agent のチャット UI は英語のみ対応
  - 応答には最大 2 分かかる場合があります（AI 調査のため）
"@
