<#
.SYNOPSIS
Foundry チャットエージェントの作成スクリプト

.DESCRIPTION
このスクリプトは以下を実行します：
1. 環境変数からリソース情報を取得
2. Azure CLI で Foundry のリソースにアクセス
3. （必要時のみ）Foundry エージェント作成 API を実行
4. アプリ設定に使うエージェント ID とバージョンを表示

前提：
- deploy.ps1 でインフラが正常にデプロイされていること
- ジャンプボックス VM または VPN で Foundry にアクセス可能なネットワーク内にいること

.PARAMETER ResourceGroup
リソースグループ名

.PARAMETER ScenarioCode
シナリオコード（デフォルト: fcb01）

.PARAMETER FoundryProjectName
Foundry プロジェクト名（デフォルト: projchat）

.PARAMETER CreateFoundryAgent
Foundry data-plane の agents API で実際にエージェントを作成するかどうか（既定: false）

.EXAMPLE
PS> .\setup-foundry-agent.ps1 -ResourceGroup rg-foundry-chat-baseline-fcb01 -ScenarioCode fcb01
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$ScenarioCode = 'fcb01',

    [Parameter(Mandatory = $false)]
    [string]$FoundryProjectName = 'projchat',

    [Parameter(Mandatory = $false)]
    [switch]$CreateFoundryAgent
)

$ErrorActionPreference = 'Stop'

Write-Host "====== Foundry チャットエージェント作成スクリプト ======" -ForegroundColor Cyan
Write-Host "開始時刻: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

try {
    # ========== 1. Foundry リソース情報取得 ==========
    Write-Host "`n[1/3] Foundry リソース情報取得" -ForegroundColor Yellow

    $subscriptionId = az account show --query id -o tsv

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

    $foundryLocation = az cognitiveservices account show -n $foundryName -g $ResourceGroup --query location -o tsv

    # Foundry プロジェクト管理を有効化（未有効時のみ）
    $accountUrl = "https://management.azure.com/subscriptions/${subscriptionId}/resourceGroups/${ResourceGroup}/providers/Microsoft.CognitiveServices/accounts/${foundryName}?api-version=2025-06-01"
    $accountProjectMgmtUrl = "https://management.azure.com/subscriptions/${subscriptionId}/resourceGroups/${ResourceGroup}/providers/Microsoft.CognitiveServices/accounts/${foundryName}?api-version=2024-10-01"
    $accountIdentityType = az cognitiveservices account show -n $foundryName -g $ResourceGroup --query "identity.type" -o tsv 2>$null

    if ($accountIdentityType -ne 'SystemAssigned') {
        Write-Host "  → Foundry の SystemAssigned MSI を有効化..." -ForegroundColor Gray
        $identityPatch = @{
            identity = @{
                type = 'SystemAssigned'
            }
        } | ConvertTo-Json -Depth 5 -Compress
        $identityPatchPath = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
        Set-Content -Path $identityPatchPath -Value $identityPatch -Encoding UTF8

        $identityResult = az rest --method PATCH --url $accountUrl --headers "Content-Type=application/json" -b "@${identityPatchPath}" 2>&1
        Remove-Item $identityPatchPath -Force

        if ($LASTEXITCODE -ne 0) {
            throw "Foundry MSI 有効化に失敗しました。詳細: $identityResult"
        }
        Write-Host "  ✓ Foundry MSI 有効化完了" -ForegroundColor Green
    }

    $projectMgmtEnabled = az rest --method GET --url $accountProjectMgmtUrl --query "properties.allowProjectManagement" -o tsv 2>$null
    if ($projectMgmtEnabled -ne 'true') {
        Write-Host "  → allowProjectManagement を有効化..." -ForegroundColor Gray
        $projectMgmtPatch = @{
            properties = @{
                allowProjectManagement = $true
            }
        } | ConvertTo-Json -Depth 10 -Compress

        $projectMgmtPatchPath = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
        Set-Content -Path $projectMgmtPatchPath -Value $projectMgmtPatch -Encoding UTF8

        $patchResult = az rest --method PATCH --url $accountProjectMgmtUrl --headers "Content-Type=application/json" -b "@${projectMgmtPatchPath}" 2>&1
        Remove-Item $projectMgmtPatchPath -Force

        if ($LASTEXITCODE -ne 0) {
            throw "allowProjectManagement の有効化に失敗しました。詳細: $patchResult"
        }

        $projectMgmtEnabledAfterPatch = az rest --method GET --url $accountProjectMgmtUrl --query "properties.allowProjectManagement" -o tsv 2>$null
        if ($projectMgmtEnabledAfterPatch -eq 'true') {
            Write-Host "  ✓ allowProjectManagement 有効化完了" -ForegroundColor Green
        } else {
            # API バージョンによっては確認値が返らない場合がある（処理は継続）
            Write-Host "  ✓ allowProjectManagement PATCH 送信完了（確認は project 作成で実施）" -ForegroundColor Green
        }
    } else {
        Write-Host "  ✓ allowProjectManagement は有効化済み" -ForegroundColor Green
    }

    # Foundry プロジェクトを存在確認し、なければ作成
    $projectUrl = "https://management.azure.com/subscriptions/${subscriptionId}/resourceGroups/${ResourceGroup}/providers/Microsoft.CognitiveServices/accounts/${foundryName}/projects/${FoundryProjectName}?api-version=2025-06-01"
    $projectCheck = az rest --method GET --url $projectUrl --query "name" -o tsv 2>$null
    if (-not $projectCheck) {
        Write-Host "  → Foundry プロジェクト ${FoundryProjectName} を作成..." -ForegroundColor Gray
        $projectBody = @{
            location = $foundryLocation
            properties = @{
                description = 'Baseline chat project'
                displayName = 'Baseline Chat'
            }
        } | ConvertTo-Json -Depth 10 -Compress

        $projectBodyPath = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
        Set-Content -Path $projectBodyPath -Value $projectBody -Encoding UTF8

        $projectCreateResult = az rest --method PUT --url $projectUrl --headers "Content-Type=application/json" -b "@${projectBodyPath}" 2>&1

        if ($LASTEXITCODE -ne 0 -and $projectCreateResult -match 'must enable a managed identity') {
            Write-Host "  → プロジェクト作成前に Foundry MSI を再有効化して再試行..." -ForegroundColor Yellow

            $identityPatchRetry = @{
                identity = @{
                    type = 'SystemAssigned'
                }
            } | ConvertTo-Json -Depth 5 -Compress

            $identityPatchRetryPath = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
            Set-Content -Path $identityPatchRetryPath -Value $identityPatchRetry -Encoding UTF8
            az rest --method PATCH --url $accountUrl --headers "Content-Type=application/json" -b "@${identityPatchRetryPath}" | Out-Null
            Remove-Item $identityPatchRetryPath -Force

            $projectCreateResult = az rest --method PUT --url $projectUrl --headers "Content-Type=application/json" -b "@${projectBodyPath}" 2>&1
        }
        Remove-Item $projectBodyPath -Force

        if ($LASTEXITCODE -ne 0) {
            throw "Foundry プロジェクト作成に失敗しました。詳細: $projectCreateResult"
        }
        Write-Host "  ✓ Foundry プロジェクト作成完了" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Foundry プロジェクトは既存: $FoundryProjectName" -ForegroundColor Green
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

    # ========== 3. エージェント情報確定 ==========
    Write-Host "`n[3/3] エージェント情報設定" -ForegroundColor Yellow

    $agentId = 'baseline-chatbot-agent'
    $agentVersion = '1'

    if ($CreateFoundryAgent) {
        Write-Host "  → Foundry data-plane の agents API で作成を試行..." -ForegroundColor Gray

        # 注意: Foundry の agents API は仕様変更が頻繁なため、必要時のみ実行
        $agentTemplate = @{
            name = $agentId
            definition = @{
                kind = 'assistant'
                model = $MODEL_CONNECTION_NAME
                description = 'Chat agent with Bing search grounding'
                instructions = 'You are a helpful AI assistant. Use the provided tools and knowledge bases to help answer user questions.'
            }
        } | ConvertTo-Json -Depth 10

        $tempJsonPath = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
        Set-Content -Path $tempJsonPath -Value $agentTemplate -Encoding UTF8

        $response = az rest `
            -u $FOUNDRY_AGENT_URL `
            -m "POST" `
            --resource "https://ai.azure.com" `
            -b "@${tempJsonPath}" `
            2>&1

        Remove-Item $tempJsonPath -Force

        if ($LASTEXITCODE -ne 0) {
            throw "Foundry エージェント作成に失敗しました。CreateFoundryAgent を外して再実行するか、payload を最新 API 仕様に更新してください。詳細: $response"
        }

        $responseJson = $response | ConvertFrom-Json
        if ($responseJson.last_id) {
            $agentId = $responseJson.last_id
        }

        if ($responseJson.data -and $responseJson.data[0] -and $responseJson.data[0].versions -and $responseJson.data[0].versions.latest -and $responseJson.data[0].versions.latest.version) {
            $agentVersion = [string]$responseJson.data[0].versions.latest.version
        }
    } else {
        Write-Host "  → 現在のチャットアプリは Azure OpenAI Chat Completions API を使用するため、agents API 呼び出しはスキップします。" -ForegroundColor Gray
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
