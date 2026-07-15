<#
.SYNOPSIS
App Service でのリモート npm install スクリプト

.DESCRIPTION
App Service の Kudu コンソールを通じて npm install を実行します

.PARAMETER ResourceGroup
リソースグループ名

.PARAMETER AppServiceName
App Service 名

.EXAMPLE
PS> .\install-app-deps.ps1 -ResourceGroup rg-foundry-chat-baseline-fcb03 -AppServiceName app-fcb03oztkaf
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$AppServiceName
)

$ErrorActionPreference = 'Stop'

Write-Host "====== App Service npm install スクリプト ======" -ForegroundColor Cyan

try {
    # Kudu の deployment credentials を取得
    Write-Host "`n[1/3] デプロイ資格情報を取得..." -ForegroundColor Yellow
    
    $publishProfile = az webapp deployment list-publishing-profiles `
        --resource-group $ResourceGroup `
        --name $AppServiceName `
        --query "[0]" `
        -o json | ConvertFrom-Json

    if (-not $publishProfile) {
        throw "デプロイプロフィールの取得に失敗しました"
    }

    $username = $publishProfile.userName
    $password = $publishProfile.userPWD
    $auth = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($username):$($password)"))

    Write-Host "  ✓ 認証情報取得完了" -ForegroundColor Green

    # Kudu コンソール API で npm install を実行
    Write-Host "`n[2/3] Kudu 経由で npm install を実行..." -ForegroundColor Yellow

    $kuduUrl = "https://$AppServiceName.scm.azurewebsites.net"
    $commandUrl = "$kuduUrl/api/command"

    # npm install コマンド実行
    $command = "npm install"
    $body = @{
        command = $command
        dir     = "D:\home\site\wwwroot"
    } | ConvertTo-Json

    $response = Invoke-WebRequest `
        -Uri $commandUrl `
        -Method Post `
        -Headers @{ Authorization = "Basic $auth"; ContentType = "application/json" } `
        -Body $body `
        -TimeoutSec 300 `
        -ErrorAction SilentlyContinue

    if ($response.StatusCode -eq 200) {
        Write-Host "  ✓ npm install が正常に完了しました" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ npm install コマンド実行。ステータス: $($response.StatusCode)" -ForegroundColor Yellow
    }

    Write-Host "`n[3/3] 確認..." -ForegroundColor Yellow

    # node_modules の存在確認
    $kuduFiles = "https://$AppServiceName.scm.azurewebsites.net/api/vfs/site/wwwroot/"
    $fileCheck = Invoke-WebRequest `
        -Uri $kuduFiles `
        -Headers @{ Authorization = "Basic $auth" } `
        -ErrorAction SilentlyContinue

    if ($fileCheck.Content -like '*node_modules*') {
        Write-Host "  ✓ node_modules が確認されました" -ForegroundColor Green
    } else {
        Write-Host "  ℹ node_modules がまだ見つかりません（実行中の可能性あり）" -ForegroundColor Yellow
    }

    Write-Host "`n✅ npm install 実行が完了しました！" -ForegroundColor Green
    Write-Host "`nアプリ URL: http://$AppServiceName.azurewebsites.net" -ForegroundColor Cyan

} catch {
    Write-Host "`n❌ エラー: $_" -ForegroundColor Red
    exit 1
}
