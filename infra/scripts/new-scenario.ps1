param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('standard', 'adhoc')]
    [string]$RequestType,

    [Parameter(Mandatory = $true)]
    [string]$ScenarioName,

    [Parameter(Mandatory = $false)]
    [string]$ScenarioCode = 'csa01'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$templateFile = Join-Path $repoRoot 'infra\scenarios\_templates\bicep\main.bicep'

if (-not (Test-Path $templateFile)) {
    throw "テンプレートが見つかりません: $templateFile"
}

if ($RequestType -eq 'standard') {
    $basePath = Join-Path $repoRoot "infra\scenarios\$ScenarioName"
} else {
    $basePath = Join-Path $repoRoot "infra\custom\$ScenarioName"
}

$bicepPath = Join-Path $basePath 'bicep'
$docsPath = Join-Path $basePath 'docs'

New-Item -ItemType Directory -Path $bicepPath -Force | Out-Null
New-Item -ItemType Directory -Path $docsPath -Force | Out-Null

$mainBicepPath = Join-Path $bicepPath 'main.bicep'
$docReadmePath = Join-Path $docsPath 'README.md'

(Get-Content -Path $templateFile -Raw) |
    ForEach-Object { $_ -replace "scenarioCode string = 'csa01'", "scenarioCode string = '$ScenarioCode'" } |
    Set-Content -Path $mainBicepPath -Encoding UTF8

$doc = @"
# $ScenarioName シナリオ

## 区分
- $RequestType

## 目的
Issue の要件に基づいて追記してください。

## 既定値
- location: southwestasia
- scenarioCode: $ScenarioCode
"@

Set-Content -Path $docReadmePath -Value $doc -Encoding UTF8

Write-Host "作成完了: $basePath"
