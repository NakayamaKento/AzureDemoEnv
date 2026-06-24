<#
.SYNOPSIS
Foundry チャットエージェントの作成スクリプト

.DESCRIPTION
このスクリプトは以下を実行します：
1. 環境変数からリソース情報を取得
2. Azure CLI で Foundry のリソースにアクセス
3. Foundry に「baseline-chatbot-agent」エージェントを作成
4. エージェントの ID とバージョンを表示

前提：
- deploy.ps1 でインフラが正常にデプロイされていること
- ジャンプボックス VM または VPN で Foundry にアクセス可能なネットワーク内にいること

.PARAMETER ResourceGroup
リソースグループ名

.PARAMETER ScenarioCode
シナリオコード（デフォルト: fcb01）

.PARAMETER FoundryProjectName
Foundry プロジェクト名（デフォルト: projchat）

.EXAMPLE
PS> .\setup-foundry-agent.ps1 -ResourceGroup rg-foundry-chat-baseline-fcb01 -ScenarioCode fcb01
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$ScenarioCode = 'fcb01',

    [Parameter(Mandatory = $false)]
    [string]$FoundryProjectName = 'projchat'
)

$ErrorActionPreference = 'Stop'

Write-Host "====== Foundry チャットエージェント作成スクリプト ======" -ForegroundColor Cyan
Write-Host "開始時刻: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

try {
    # ========== 1. Foundry リソース情報取得 ==========
    Write-Host "`n[1/3] Foundry リソース情報取得" -ForegroundColor Yellow

    $suffix = (az group show --name $ResourceGroup --query 'tags.resourceGroupSuffix' -o tsv 2>$null) || "unknown"
    if ($suffix -eq "unknown") {
        # 別の方法で Foundry 名を構築
        $foundryName = "aif$(([System.Text.RegularExpressions.Regex]::Replace($ScenarioCode, '[^a-z0-9]', '')))$(Get-Random -Minimum 1000 -Maximum 9999)"
        Write-Host "  → 警告: Foundry 名を自動推定: $foundryName" -ForegroundColor Yellow
    } else {
        $foundryName = "aif${suffix}"
    }

    # az rest で Foundry アカウント一覧を取得して正確な名前を確認
    Write-Host "  → Foundry リソースを検索..." -ForegroundColor Gray
    $foundryResources = az resource list `
        --resource-group $ResourceGroup `
        --resource-type 'Microsoft.CognitiveServices/accounts' `
        --query '[0].name' -o tsv 2>$null

    if ($foundryResources) {
        $foundryName = $foundryResources
        Write-Host "  ✓ 見つかった Foundry アカウント: $foundryName" -ForegroundColor Green
    } else {
        throw "リソースグループ内に Foundry（Azure AI Services）が見つかりません: $ResourceGroup"
    }

    # ========== 2. 接続情報設定 ==========
    Write-Host "`n[2/3] Foundry 接続設定" -ForegroundColor Yellow

    $BING_CONNECTION_NAME = "bingaiagent${ScenarioCode}"
    $MODEL_CONNECTION_NAME = "agent-model"
    $FOUNDRY_AGENT_URL = "https://${foundryName}.services.ai.azure.com/api/projects/${FoundryProjectName}/agents?api-version=2025-11-15-preview"
    $BING_CONNECTION_ID = "$(az cognitiveservices account show -n $foundryName -g $ResourceGroup --query 'id' --out tsv)/projects/${FoundryProjectName}/connections/${BING_CONNECTION_NAME}"

    Write-Host "  - Foundry エンドポイント: $FOUNDRY_AGENT_URL" -ForegroundColor Gray
    Write-Host "  - Bing 接続: $BING_CONNECTION_NAME" -ForegroundColor Gray
    Write-Host "  - モデル接続: $MODEL_CONNECTION_NAME" -ForegroundColor Gray

    # ========== 3. エージェント作成 ==========
    Write-Host "`n[3/3] Foundry にエージェントを作成" -ForegroundColor Yellow

    Write-Host "  → エージェント定義テンプレートをダウンロード..." -ForegroundColor Gray
    
    # GitHub から agent JSON テンプレートを取得
    # 参照: https://github.com/Azure-Samples/microsoft-foundry-baseline/blob/main/agents/chat-with-bing.json
    $agentTemplate = @{
        definition = @{
            name = "baseline-chatbot-agent"
            model = $MODEL_CONNECTION_NAME
            description = "Chat agent with Bing search grounding"
            instructions = "You are a helpful AI assistant. Use the provided tools and knowledge bases to help answer user questions."
            tools = @(
                @{
                    type = "bing_grounding"
                    bing_grounding = @{
                        search_configurations = @(
                            @{
                                project_connection_id = $BING_CONNECTION_ID
                            }
                        )
                    }
                }
            )
        }
    } | ConvertTo-Json -Depth 10

    # 一時ファイルに保存
    $tempJsonPath = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
    Set-Content -Path $tempJsonPath -Value $agentTemplate -Encoding UTF8

    Write-Host "  → Foundry に POST リクエストを送信..." -ForegroundColor Gray

    $response = az rest `
        -u $FOUNDRY_AGENT_URL `
        -m "POST" `
        --resource "https://ai.azure.com" `
        -b "@${tempJsonPath}" `
        2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Foundry エージェント作成に失敗しました。エラー: $response`n詳細は Foundry ポータルを確認してください。"
    }

    Remove-Item $tempJsonPath -Force

    $responseJson = $response | ConvertFrom-Json
    $agentId = $responseJson.last_id
    $agentVersion = $responseJson.data[0].versions.latest.version

    if (-not $agentId -or -not $agentVersion) {
        throw "エージェント作成レスポンスから ID/バージョンが取得できませんでした。"
    }

    Write-Host "  ✓ エージェント作成完了" -ForegroundColor Green
    Write-Host "    - Agent ID: $agentId" -ForegroundColor Gray
    Write-Host "    - Version: $agentVersion" -ForegroundColor Gray

    # ========== 4. 次のステップ表示 ==========
    Write-Host "`n✅ Foundry エージェント作成完了！`n" -ForegroundColor Green

    Write-Host "【次に実施する作業】" -ForegroundColor Cyan
    Write-Host "App Service の環境変数を更新してください：" -ForegroundColor White
    Write-Host "  .\infra\scenarios\foundry-chat-baseline\update-app-settings.ps1 -ResourceGroup $ResourceGroup -AgentId $agentId -AgentVersion $agentVersion" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "【環境変数の値】" -ForegroundColor Cyan
    Write-Host "  FOUNDRY_PROJECT_ENDPOINT: https://${foundryName}.services.ai.azure.com/api/projects/${FoundryProjectName}" -ForegroundColor Gray
    Write-Host "  FOUNDRY_AGENT_ID: $agentId" -ForegroundColor Gray
    Write-Host "  FOUNDRY_AGENT_VERSION: $agentVersion" -ForegroundColor Gray

    Write-Host "`n終了時刻: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

} catch {
    Write-Host "`n❌ エラー: $_" -ForegroundColor Red
    exit 1
}
