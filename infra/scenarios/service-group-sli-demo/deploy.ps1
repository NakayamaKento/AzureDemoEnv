<#
.SYNOPSIS
Service Group SLI Demo シナリオを Azure にデプロイします。

.DESCRIPTION
1. Azure provider registration
2. tenant scope Service Groups
3. resource group scope workload
4. Service Group membership
5. Health Model
6. SLI preview
7. App Service Oryx ZIP deploy / optional Function App deploy
8. smoke check
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ScenarioCode = 'sgsli01',

    [Parameter(Mandatory = $false)]
    [string]$Location = 'southeastasia',

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-service-group-sli-demo-$ScenarioCode",

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ParentServiceGroupResourceId = '',

    [Parameter(Mandatory = $false)]
    [switch]$SkipHealthModel,

    [Parameter(Mandatory = $false)]
    [switch]$SkipSli,

    [Parameter(Mandatory = $false)]
    [switch]$StrictPreview,

    [Parameter(Mandatory = $false)]
    [switch]$CleanupOnFailure,

    [Parameter(Mandatory = $false)]
    [switch]$SkipAppDeploy,

    [Parameter(Mandatory = $false)]
    [switch]$DeployFunctionWorker,

    [Parameter(Mandatory = $false)]
    [switch]$DeployPrometheusCollector,

    [Parameter(Mandatory = $false)]
    [string]$CollectorSshPublicKeyPath = (Join-Path $HOME '.ssh\id_ed25519_azure_demo_env.pub')
)

$ErrorActionPreference = 'Stop'
$providerRegistrationTimeoutSeconds = 600
$providerRegistrationPollSeconds = 15
$serviceGroupReadyTimeoutSeconds = 1800
$serviceGroupReadyPollSeconds = 15
$previewDeploymentTimeoutSeconds = 240
$previewDeploymentPollSeconds = 15
$apiHealthTimeoutSeconds = 600
$apiHealthPollSeconds = 15
$appDeploymentTimeoutSeconds = 900
$appDeploymentPollSeconds = 15

if ($DeployPrometheusCollector -and $CleanupOnFailure) {
    throw '-DeployPrometheusCollector と -CleanupOnFailure は併用できません。既存環境を保護するため、collector の増分デプロイでは -CleanupOnFailure を外してください。'
}

function Invoke-AzCli {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $false)]
        [switch]$AsJson
    )

    $standardOutputPath = [System.IO.Path]::GetTempFileName()
    $standardErrorPath = [System.IO.Path]::GetTempFileName()
    try {
        $azCommand = (Get-Command az -ErrorAction Stop).Source
        $process = Start-Process `
            -FilePath $azCommand `
            -ArgumentList $Arguments `
            -RedirectStandardOutput $standardOutputPath `
            -RedirectStandardError $standardErrorPath `
            -PassThru `
            -Wait `
            -NoNewWindow
        $exitCode = $process.ExitCode
        $standardOutput = Get-Content -Path $standardOutputPath -Raw
        $standardError = Get-Content -Path $standardErrorPath -Raw
        if ($exitCode -ne 0) {
            throw "az $($Arguments -join ' ') failed: $standardOutput $standardError"
        }

        if ($AsJson) {
            return $standardOutput | ConvertFrom-Json
        }

        return $standardOutput
    } finally {
        Remove-Item -Path $standardOutputPath, $standardErrorPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-AzCliWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $false)]
        [int]$MaxAttempts = 3,

        [Parameter(Mandatory = $false)]
        [int]$DelaySeconds = 45,

        [Parameter(Mandatory = $false)]
        [string[]]$RetryWhenMessageContains = @()
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return Invoke-AzCli -Arguments $Arguments
        } catch {
            $message = $_.Exception.Message
            $isRetryable = $false
            foreach ($marker in $RetryWhenMessageContains) {
                if ($message.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $isRetryable = $true
                    break
                }
            }

            if (-not $isRetryable -or $attempt -eq $MaxAttempts) {
                throw
            }

            Write-Host "  ! Azure CLI transient failure; retrying in $DelaySeconds seconds ($attempt/$MaxAttempts)" -ForegroundColor Yellow
            Write-Host "    $message" -ForegroundColor Gray
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function New-ParameterFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    $parameterBody = [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = @{}
    }

    foreach ($key in $Parameters.Keys) {
        $parameterBody.parameters[$key] = @{ value = $Parameters[$key] }
    }

    $parameterBody | ConvertTo-Json -Depth 30 | Set-Content -Path $Path -Encoding UTF8
    return $Path
}

function Get-OrCreateSshPublicKey {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PublicKeyPath
    )

    if (-not (Test-Path $PublicKeyPath)) {
        $sshKeygen = (Get-Command ssh-keygen -ErrorAction Stop).Source
        $privateKeyPath = $PublicKeyPath -replace '\.pub$', ''
        New-Item -ItemType Directory -Path (Split-Path $PublicKeyPath -Parent) -Force | Out-Null
        & $sshKeygen -q -t ed25519 -f $privateKeyPath -N '""' -C 'azure-demo-env-prometheus-collector'
        if ($LASTEXITCODE -ne 0) {
            throw "collector VM 用 SSH key の生成に失敗しました: $PublicKeyPath"
        }
    }

    $publicKey = (Get-Content -Path $PublicKeyPath -Raw).Trim()
    if ($publicKey -notmatch '^ssh-(ed25519|rsa)\s+') {
        throw "有効な SSH public key ではありません: $PublicKeyPath"
    }

    return $publicKey
}

function Compress-App {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeNodeModules
    )

    if (Test-Path $DestinationPath) {
        Remove-Item $DestinationPath -Force
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $sourceFullPath = (Resolve-Path $SourcePath).Path.TrimEnd('\', '/')
    $excludedDirectories = @('.git', '.vscode', 'coverage', 'logs', '.nyc_output')
    if (-not $IncludeNodeModules) {
        $excludedDirectories += 'node_modules'
    }

    $destinationDirectory = Split-Path -Parent $DestinationPath
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null

    if ($IncludeNodeModules) {
        # Web package は依存関係を含むためファイル数が多い。ZipFile の一括処理で作成時間を短縮する。
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $sourceFullPath,
            $DestinationPath,
            [System.IO.Compression.CompressionLevel]::Fastest,
            $false
        )
        return
    }

    $zipStream = [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::CreateNew)
    $archive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $files = Get-ChildItem -Path $sourceFullPath -Recurse -File -Force | Where-Object {
            $relativePath = $_.FullName.Substring($sourceFullPath.Length).TrimStart('\', '/')
            $pathParts = $relativePath -split '[\\/]'
            -not ($pathParts | Where-Object { $_ -in $excludedDirectories })
        }

        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($sourceFullPath.Length).TrimStart('\', '/') -replace '\\', '/'
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive,
                $file.FullName,
                $relativePath,
                [System.IO.Compression.CompressionLevel]::Fastest
            ) | Out-Null
        }
    } finally {
        $archive.Dispose()
        $zipStream.Dispose()
    }

    $zipItem = Get-Item $DestinationPath
    if ($zipItem.Length -le 0) {
        throw "zip package creation produced an empty file: $DestinationPath"
    }
}

function Invoke-NpmInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeDev
    )

    $npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npmCommand) {
        $npmCommand = Get-Command npm -ErrorAction SilentlyContinue
    }
    if (-not $npmCommand) {
        throw "npm が見つかりません。Node.js 22 以降をインストールしてから再実行してください。"
    }

    Write-Host "  -> npm dependencies: $DisplayName" -ForegroundColor Gray
    Push-Location $SourcePath
    try {
        $installArguments = if (Test-Path 'package-lock.json') {
            @('ci', '--no-audit', '--no-fund', '--progress=false')
        } else {
            @('install', '--no-audit', '--no-fund', '--progress=false')
        }
        if (-not $IncludeDev) {
            $installArguments += '--omit=dev'
        }

        & $npmCommand.Source @installArguments
        if ($LASTEXITCODE -ne 0) {
            throw "npm dependency restore failed for $DisplayName"
        }
    } finally {
        Pop-Location
    }
}

function Invoke-NpmScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    $npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npmCommand) {
        $npmCommand = Get-Command npm -ErrorAction SilentlyContinue
    }
    if (-not $npmCommand) {
        throw "npm が見つかりません。Node.js 22 以降をインストールしてから再実行してください。"
    }

    Write-Host "  -> npm run ${ScriptName}: $DisplayName" -ForegroundColor Gray
    Push-Location $SourcePath
    try {
        & $npmCommand.Source run $ScriptName
        if ($LASTEXITCODE -ne 0) {
            throw "npm script '$ScriptName' failed for $DisplayName"
        }
    } finally {
        Pop-Location
    }
}

function Wait-ApiHealth {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WebUrl
    )

    $healthUrl = "$WebUrl/healthz"
    $deadline = (Get-Date).AddSeconds($apiHealthTimeoutSeconds)
    $lastFailure = ''
    do {
        try {
            $response = Invoke-RestMethod -Uri $healthUrl -Method GET -TimeoutSec 30
            if ($response.status -eq 'ok') {
                Write-Host "  ✓ API health endpoint is ready" -ForegroundColor Green
                return $response
            }

            $lastFailure = "Unexpected health status: $($response.status)"
        } catch {
            $lastFailure = $_.Exception.Message
        }

        Write-Host "  -> waiting API startup: $healthUrl" -ForegroundColor Gray
        Start-Sleep -Seconds $apiHealthPollSeconds
    } while ((Get-Date) -lt $deadline)

    throw "API did not become healthy within $apiHealthTimeoutSeconds seconds. Last response: $lastFailure"
}

function Wait-AppServiceDeployment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,

        [Parameter(Mandatory = $true)]
        [datetime]$StartedAfter
    )

    $deadline = (Get-Date).AddSeconds($appDeploymentTimeoutSeconds)
    do {
        $deployments = Invoke-AzCli -Arguments @(
            'webapp', 'log', 'deployment', 'list',
            '--resource-group', $ResourceGroup,
            '--name', $AppName,
            '--only-show-errors',
            '-o', 'json'
        ) -AsJson

        $deployment = $deployments | Where-Object {
            $_.start_time -and ([datetime]$_.start_time).ToUniversalTime() -ge $StartedAfter.ToUniversalTime()
        } | Sort-Object { [datetime]$_.start_time } -Descending | Select-Object -First 1

        if ($deployment) {
            if ($deployment.complete -and $deployment.status -eq 4) {
                Write-Host "  ✓ App Service Oryx deployment completed" -ForegroundColor Green
                return
            }
            if ($deployment.complete -and $deployment.status -ne 4) {
                $details = Invoke-AzCli -Arguments @(
                    'webapp', 'log', 'deployment', 'show',
                    '--resource-group', $ResourceGroup,
                    '--name', $AppName,
                    '--only-show-errors',
                    '-o', 'json'
                )
                throw "App Service Oryx deployment failed (status=$($deployment.status)): $details"
            }

            Write-Host "  -> waiting App Service Oryx deployment: status=$($deployment.status)" -ForegroundColor Gray
        } else {
            Write-Host "  -> waiting App Service deployment record" -ForegroundColor Gray
        }

        Start-Sleep -Seconds $appDeploymentPollSeconds
    } while ((Get-Date) -lt $deadline)

    throw "App Service Oryx deployment did not complete within $appDeploymentTimeoutSeconds seconds."
}

function Register-AzProviderWithTimeout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Namespace
    )

    $state = (Invoke-AzCli -Arguments @('provider', 'show', '--namespace', $Namespace, '--query', 'registrationState', '-o', 'tsv')).Trim()
    if ($state -eq 'Registered') {
        Write-Host "  ✓ $Namespace already registered" -ForegroundColor Green
        return
    }

    Write-Host "  -> register $Namespace (current: $state)" -ForegroundColor Gray
    Invoke-AzCli -Arguments @('provider', 'register', '--namespace', $Namespace, '--only-show-errors', '-o', 'none') | Out-Null

    $deadline = (Get-Date).AddSeconds($providerRegistrationTimeoutSeconds)
    do {
        $state = (Invoke-AzCli -Arguments @('provider', 'show', '--namespace', $Namespace, '--query', 'registrationState', '-o', 'tsv')).Trim()
        if ($state -eq 'Registered') {
            Write-Host "  ✓ $Namespace registered" -ForegroundColor Green
            return
        }

        Start-Sleep -Seconds $providerRegistrationPollSeconds
    } while ((Get-Date) -lt $deadline)

    throw "$Namespace provider registration did not complete within $providerRegistrationTimeoutSeconds seconds. Current state: $state"
}

function Invoke-PreviewGroupDeploymentWithTimeout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeploymentName,

        [Parameter(Mandatory = $true)]
        [string]$TemplateFile,

        [Parameter(Mandatory = $true)]
        [string]$ParameterFile
    )

    Invoke-AzCli -Arguments @(
        'deployment', 'group', 'create',
        '--resource-group', $ResourceGroup,
        '--name', $DeploymentName,
        '--template-file', $TemplateFile,
        '--parameters', "@$ParameterFile",
        '--only-show-errors',
        '--no-wait',
        '-o', 'none'
    ) | Out-Null

    $deadline = (Get-Date).AddSeconds($previewDeploymentTimeoutSeconds)
    $lastLoggedState = ''
    do {
        $raw = az deployment group show --resource-group $ResourceGroup --name $DeploymentName --only-show-errors -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) {
            $deployment = $raw | ConvertFrom-Json
            $state = $deployment.properties.provisioningState
            if ($state -eq 'Succeeded') {
                return
            }

            if ($state -in @('Failed', 'Canceled', 'Cancelled')) {
                $failedMessages = az deployment operation group list --resource-group $ResourceGroup --name $DeploymentName --query "[?properties.provisioningState=='Failed'].properties.statusMessage.error.message" -o tsv --only-show-errors 2>$null
                if ($failedMessages) {
                    throw "Preview deployment $DeploymentName failed: $failedMessages"
                }

                throw "Preview deployment $DeploymentName ended with state: $state"
            }

            if ($state -and $state -ne $lastLoggedState) {
                Write-Host "  -> waiting preview deployment: $DeploymentName ($state)" -ForegroundColor Gray
                $lastLoggedState = $state
            }
        }

        Start-Sleep -Seconds $previewDeploymentPollSeconds
    } while ((Get-Date) -lt $deadline)

    az deployment group cancel --resource-group $ResourceGroup --name $DeploymentName --only-show-errors -o none 2>$null | Out-Null
    throw "Preview deployment $DeploymentName did not complete within $previewDeploymentTimeoutSeconds seconds and was cancelled."
}

function New-ServiceGroupRest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter(Mandatory = $true)]
        [string]$ParentResourceId,

        [Parameter(Mandatory = $true)]
        [string]$BodyPath
    )

    $body = @{
        tags = @{
            scenario = 'service-group-sli-demo'
            scenarioCode = $ScenarioCode
            workload = 'order-processing'
        }
        properties = @{
            displayName = $DisplayName
            parent = @{
                resourceId = $ParentResourceId
            }
        }
    } | ConvertTo-Json -Depth 20 -Compress

    [System.IO.File]::WriteAllText($BodyPath, $body, [System.Text.UTF8Encoding]::new($false))
    $url = "https://management.azure.com/providers/Microsoft.Management/serviceGroups/${Name}?api-version=2024-02-01-preview"
    Invoke-AzCli -Arguments @(
        'rest',
        '--method', 'put',
        '--url', $url,
        '--headers', 'Content-Type=application/json; charset=utf-8',
        '--body', "@$BodyPath",
        '--only-show-errors',
        '-o', 'none'
    ) | Out-Null
}

function Wait-ServiceGroupRest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $deadline = (Get-Date).AddSeconds($serviceGroupReadyTimeoutSeconds)
    $lastLoggedState = ''
    $url = "https://management.azure.com/providers/Microsoft.Management/serviceGroups/${Name}?api-version=2024-02-01-preview"
    do {
        $raw = az rest --method get --url $url --only-show-errors -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) {
            $serviceGroup = $raw | ConvertFrom-Json
            $state = $serviceGroup.properties.provisioningState
            if ($state -in @('Succeeded', 'Created')) {
                Write-Host "  ✓ Service Group ready: $Name ($state)" -ForegroundColor Green
                return
            }

            if ($state -and $state -ne $lastLoggedState) {
                Write-Host "  -> waiting Service Group: $Name ($state)" -ForegroundColor Gray
                $lastLoggedState = $state
            }
        }

        Start-Sleep -Seconds $serviceGroupReadyPollSeconds
    } while ((Get-Date) -lt $deadline)

    throw "Service Group $Name was not ready within $serviceGroupReadyTimeoutSeconds seconds."
}

function New-ServiceGroupsRest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )

    $normalizedScenarioCode = $ScenarioCode.ToLowerInvariant().Replace('-', '')
    $names = [ordered]@{
        root = "sg-$normalizedScenarioCode-order-service"
    }
    $ids = [ordered]@{}
    foreach ($key in $names.Keys) {
        $ids[$key] = "/providers/Microsoft.Management/serviceGroups/$($names[$key])"
    }

    $rootParentId = if ([string]::IsNullOrWhiteSpace($ParentServiceGroupResourceId)) {
        "/providers/Microsoft.Management/serviceGroups/$TenantId"
    } else {
        $ParentServiceGroupResourceId
    }

    New-ServiceGroupRest -Name $names.root -DisplayName '注文処理サービス' -ParentResourceId $rootParentId -BodyPath (Join-Path $tempRoot 'sg-root.json')
    Wait-ServiceGroupRest -Name $names.root

    return [pscustomobject]@{
        properties = [pscustomobject]@{
            outputs = [pscustomobject]@{
                serviceGroupNames = [pscustomobject]@{ value = $names }
                serviceGroupIds = [pscustomobject]@{ value = $ids }
            }
        }
    }
}

Write-Host "====== Service Group SLI Demo デプロイ ======" -ForegroundColor Cyan
Write-Host "開始時刻: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$bicepRoot = Join-Path $PSScriptRoot 'bicep'
$appRoot = Join-Path $repoRoot 'apps\service-group-sli-demo'
$functionRoot = Join-Path $repoRoot 'apps\service-group-sli-demo-function'
$tempRoot = Join-Path $env:TEMP "sgsli-$ScenarioCode"
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$previewWarnings = [System.Collections.Generic.List[string]]::new()

try {
    Write-Host "`n[1/8] Azure 認証と subscription 確認" -ForegroundColor Yellow
    $accountId = az account show --query id -o tsv 2>$null
    if (-not $accountId) {
        Write-Host "  -> Azure CLI にログインします" -ForegroundColor Gray
        az login | Out-Null
    }

    if ($SubscriptionId -and $accountId -ne $SubscriptionId) {
        Invoke-AzCli -Arguments @('account', 'set', '--subscription', $SubscriptionId) | Out-Null
    }

    $account = Invoke-AzCli -Arguments @('account', 'show', '-o', 'json') -AsJson
    Write-Host "  ✓ Subscription: $($account.name) ($($account.id))" -ForegroundColor Green

    Write-Host "`n[2/8] Provider registration" -ForegroundColor Yellow
    $providers = @(
        'Microsoft.AppConfiguration',
        'Microsoft.Compute',
        'Microsoft.DocumentDB',
        'Microsoft.Insights',
        'Microsoft.ManagedIdentity',
        'Microsoft.Management',
        'Microsoft.Monitor',
        'Microsoft.Network',
        'Microsoft.OperationalInsights',
        'Microsoft.Relationships',
        'Microsoft.ServiceBus',
        'Microsoft.Storage',
        'Microsoft.Web'
    )

    foreach ($provider in $providers) {
        Register-AzProviderWithTimeout -Namespace $provider
    }

    Write-Host "`n[3/8] Resource group" -ForegroundColor Yellow
    $rgExists = az group exists --name $ResourceGroup -o tsv
    if ($rgExists -ne 'true') {
        Invoke-AzCli -Arguments @('group', 'create', '--name', $ResourceGroup, '--location', $Location, '-o', 'none') | Out-Null
        Write-Host "  ✓ Created: $ResourceGroup" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Existing: $ResourceGroup" -ForegroundColor Green
    }

    Write-Host "`n[4/8] Service Groups (tenant scope)" -ForegroundColor Yellow
    $serviceGroupDeployment = New-ServiceGroupsRest -TenantId $account.tenantId
    $serviceGroupOutputs = $serviceGroupDeployment.properties.outputs
    Write-Host "  ✓ Root Service Group: $($serviceGroupOutputs.serviceGroupNames.value.root)" -ForegroundColor Green

    Write-Host "`n[5/8] Workload resources (resource group scope)" -ForegroundColor Yellow
    $mainParams = New-ParameterFile -Path (Join-Path $tempRoot 'main.parameters.json') -Parameters @{
        scenarioCode = $ScenarioCode
        location = $Location
    }
    $mainDeployment = Invoke-AzCli -Arguments @(
        'deployment', 'group', 'create',
        '--resource-group', $ResourceGroup,
        '--name', "sgsli-main-$ScenarioCode",
        '--template-file', (Join-Path $bicepRoot 'main.bicep'),
        '--parameters', "@$mainParams",
        '--only-show-errors',
        '-o', 'json'
    ) -AsJson
    $mainOutputs = $mainDeployment.properties.outputs
    Write-Host "  ✓ API App Service: $($mainOutputs.webAppName.value)" -ForegroundColor Green
    Write-Host "  ✓ Function App: $($mainOutputs.functionAppName.value)" -ForegroundColor Green

    Write-Host "`n[6/8] Service Group membership / Health Model / SLI" -ForegroundColor Yellow
    $collectorOutputs = $null
    if ($DeployPrometheusCollector) {
        $collectorPublicKey = Get-OrCreateSshPublicKey -PublicKeyPath $CollectorSshPublicKeyPath
        $collectorParams = New-ParameterFile -Path (Join-Path $tempRoot 'prometheus-collector.parameters.json') -Parameters @{
            scenarioCode = $ScenarioCode
            location = $Location
            apiHostName = ([System.Uri]$mainOutputs.webAppUrl.value).Host
            metricsIngestionEndpoint = $mainOutputs.azureMonitorMetricsIngestionEndpoint.value
            adminSshPublicKey = $collectorPublicKey
        }
        Write-Host "  -> validate Prometheus collector deployment with what-if" -ForegroundColor Gray
        Invoke-AzCli -Arguments @(
            'deployment', 'group', 'what-if',
            '--resource-group', $ResourceGroup,
            '--template-file', (Join-Path $bicepRoot 'prometheus-collector.bicep'),
            '--parameters', "@$collectorParams",
            '--only-show-errors',
            '-o', 'none'
        ) | Out-Null
        $collectorDeployment = Invoke-AzCli -Arguments @(
            'deployment', 'group', 'create',
            '--resource-group', $ResourceGroup,
            '--name', "sgsli-prometheus-$ScenarioCode",
            '--template-file', (Join-Path $bicepRoot 'prometheus-collector.bicep'),
            '--parameters', "@$collectorParams",
            '--only-show-errors',
            '-o', 'json'
        ) -AsJson
        $collectorOutputs = $collectorDeployment.properties.outputs
        Write-Host "  ✓ Prometheus collector VM: $($collectorOutputs.collectorVmName.value)" -ForegroundColor Green

        $collectorRbacParams = New-ParameterFile -Path (Join-Path $tempRoot 'prometheus-rbac.parameters.json') -Parameters @{
            collectorIdentityPrincipalId = $collectorOutputs.collectorIdentityPrincipalId.value
            defaultDataCollectionRuleResourceId = $mainOutputs.azureMonitorDefaultDcrResourceId.value
        }
        Invoke-AzCli -Arguments @(
            'deployment', 'sub', 'create',
            '--location', $Location,
            '--name', "sgsli-prometheus-rbac-$ScenarioCode",
            '--template-file', (Join-Path $bicepRoot 'prometheus-rbac.bicep'),
            '--parameters', "@$collectorRbacParams",
            '--only-show-errors',
            '-o', 'none'
        ) | Out-Null
        Write-Host "  ✓ Prometheus collector DCR RBAC deployed" -ForegroundColor Green
    } else {
        Write-Host "  - Prometheus collector deployment skipped (use -DeployPrometheusCollector to opt in)." -ForegroundColor Yellow
        $existingCollectorDeployment = az deployment group show `
            --resource-group $ResourceGroup `
            --name "sgsli-prometheus-$ScenarioCode" `
            -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and $existingCollectorDeployment) {
            $collectorOutputs = ($existingCollectorDeployment | ConvertFrom-Json).properties.outputs
            Write-Host "  ✓ Existing Prometheus collector detected for Service Group membership" -ForegroundColor Green
        }
    }

    $memberParams = New-ParameterFile -Path (Join-Path $tempRoot 'members.parameters.json') -Parameters @{
        serviceGroupIds = $serviceGroupOutputs.serviceGroupIds.value
        workloadNames = $mainOutputs.workloadNames.value
    }
    Invoke-AzCli -Arguments @(
        'deployment', 'group', 'create',
        '--resource-group', $ResourceGroup,
        '--name', "sgsli-members-$ScenarioCode",
        '--template-file', (Join-Path $bicepRoot 'service-group-members.bicep'),
        '--parameters', "@$memberParams",
        '--only-show-errors',
        '-o', 'none'
    ) | Out-Null
    Write-Host "  ✓ Service Group membership deployed" -ForegroundColor Green

    if ($collectorOutputs) {
        $collectorMemberParams = New-ParameterFile -Path (Join-Path $tempRoot 'prometheus-members.parameters.json') -Parameters @{
            rootServiceGroupId = $serviceGroupOutputs.serviceGroupIds.value.root
            collectorVmName = $collectorOutputs.collectorVmName.value
            collectorIdentityName = $collectorOutputs.collectorIdentityName.value
        }
        Invoke-AzCli -Arguments @(
            'deployment', 'group', 'create',
            '--resource-group', $ResourceGroup,
            '--name', "sgsli-prometheus-members-$ScenarioCode",
            '--template-file', (Join-Path $bicepRoot 'prometheus-members.bicep'),
            '--parameters', "@$collectorMemberParams",
            '--only-show-errors',
            '-o', 'none'
        ) | Out-Null
        Write-Host "  ✓ Prometheus collector Service Group membership deployed" -ForegroundColor Green
    }

    if (-not $SkipHealthModel) {
        $healthParams = New-ParameterFile -Path (Join-Path $tempRoot 'health.parameters.json') -Parameters @{
            azureMonitorWorkspaceName = $mainOutputs.azureMonitorWorkspaceName.value
            logAnalyticsName = $mainOutputs.logAnalyticsName.value
            rootServiceGroupId = $serviceGroupOutputs.serviceGroupIds.value.root
            workloadResourceIds = $mainOutputs.workloadResourceIds.value
            serviceBusQueueName = $mainOutputs.serviceBusQueueName.value
            location = $Location
        }
        try {
            Invoke-PreviewGroupDeploymentWithTimeout -DeploymentName "sgsli-health-$ScenarioCode" -TemplateFile (Join-Path $bicepRoot 'health-model.bicep') -ParameterFile $healthParams
            Write-Host "  ✓ Health Model deployed" -ForegroundColor Green
        } catch {
            if ($StrictPreview) {
                throw
            }

            $warning = "Health Model preview deployment was skipped after RP failure: $($_.Exception.Message)"
            $previewWarnings.Add($warning) | Out-Null
            Write-Host "  ! Health Model preview deployment failed; continuing without Health Model." -ForegroundColor Yellow
            Write-Host "    Use -StrictPreview to treat this as a deployment failure." -ForegroundColor Gray
        }
    } else {
        Write-Host "  - Health Model deployment skipped" -ForegroundColor Yellow
    }

    if (-not $SkipSli) {
        try {
            $sliRbacParams = New-ParameterFile -Path (Join-Path $tempRoot 'sli-rbac.parameters.json') -Parameters @{
                sliManagedIdentityPrincipalId = $mainOutputs.sliIdentityPrincipalId.value
                azureMonitorWorkspaceResourceId = $mainOutputs.azureMonitorWorkspaceResourceId.value
                defaultDataCollectionRuleResourceId = $mainOutputs.azureMonitorDefaultDcrResourceId.value
            }
            Invoke-AzCli -Arguments @(
                'deployment', 'sub', 'create',
                '--location', $Location,
                '--name', "sgsli-sli-rbac-$ScenarioCode",
                '--template-file', (Join-Path $bicepRoot 'sli-rbac.bicep'),
                '--parameters', "@$sliRbacParams",
                '--only-show-errors',
                '-o', 'none'
            ) | Out-Null
            Write-Host "  ✓ SLI managed identity RBAC deployed" -ForegroundColor Green

            $sliParams = New-ParameterFile -Path (Join-Path $tempRoot 'sli.parameters.json') -Parameters @{
                rootServiceGroupName = $serviceGroupOutputs.serviceGroupNames.value.root
                azureMonitorWorkspaceName = $mainOutputs.azureMonitorWorkspaceName.value
                sliManagedIdentityResourceId = $mainOutputs.sliIdentityResourceId.value
            }
            Invoke-PreviewGroupDeploymentWithTimeout -DeploymentName "sgsli-sli-$ScenarioCode" -TemplateFile (Join-Path $bicepRoot 'sli-preview.bicep') -ParameterFile $sliParams
            Write-Host "  ✓ SLI preview resources deployed" -ForegroundColor Green
        } catch {
            if ($StrictPreview) {
                throw
            }

            $warning = "SLI preview deployment was skipped after RP failure: $($_.Exception.Message)"
            $previewWarnings.Add($warning) | Out-Null
            Write-Host "  ! SLI preview deployment failed; continuing without SLI preview resources." -ForegroundColor Yellow
            Write-Host "    Use -StrictPreview to treat this as a deployment failure." -ForegroundColor Gray
        }
    } else {
        Write-Host "  - SLI preview deployment skipped" -ForegroundColor Yellow
    }

    Write-Host "`n[7/8] Application startup" -ForegroundColor Yellow
    if (-not $SkipAppDeploy) {
        $webZip = Join-Path $tempRoot 'service-group-sli-demo-web.zip'
        Write-Host "  -> package source: API App Service" -ForegroundColor Gray
        Compress-App -SourcePath $appRoot -DestinationPath $webZip

        # Foundry Chat Baseline と同じく、依存関係を ZIP に含めず App Service の Oryx で復元する。
        Write-Host "  -> enable App Service Oryx build" -ForegroundColor Gray
        Invoke-AzCli -Arguments @(
            'webapp', 'config', 'appsettings', 'set',
            '--resource-group', $ResourceGroup,
            '--name', $mainOutputs.webAppName.value,
            '--settings', 'SCM_DO_BUILD_DURING_DEPLOYMENT=true', 'ENABLE_ORYX_BUILD=true',
            '--only-show-errors',
            '-o', 'none'
        ) | Out-Null

        Write-Host "  -> deploy source ZIP to App Service (Kudu/Oryx)" -ForegroundColor Gray
        $webDeploymentStartedAt = (Get-Date).ToUniversalTime().AddSeconds(-5)
        Invoke-AzCli -Arguments @(
            'webapp', 'deploy',
            '--resource-group', $ResourceGroup,
            '--name', $mainOutputs.webAppName.value,
            '--src-path', $webZip,
            '--type', 'zip',
            '--clean', 'true',
            '--restart', 'true',
            '--async', 'true',
            '--timeout', '600000',
            '--only-show-errors',
            '-o', 'none'
        ) | Out-Null
        Wait-AppServiceDeployment -AppName $mainOutputs.webAppName.value -StartedAfter $webDeploymentStartedAt
        Write-Host "  ✓ API App Service source deployed" -ForegroundColor Green

        if ($DeployFunctionWorker) {
            Invoke-NpmInstall -SourcePath $functionRoot -DisplayName 'Function App' -IncludeDev
            Invoke-NpmScript -SourcePath $functionRoot -ScriptName 'build' -DisplayName 'Function App'
        }

        if ($DeployFunctionWorker) {
            $functionZip = Join-Path $tempRoot 'service-group-sli-demo-function.zip'
            Write-Host "  -> package: Function App" -ForegroundColor Gray
            Compress-App -SourcePath $functionRoot -DestinationPath $functionZip
        }

        Wait-ApiHealth -WebUrl $mainOutputs.webAppUrl.value | Out-Null

        if ($DeployFunctionWorker) {
            Invoke-AzCliWithRetry -Arguments @(
                'functionapp', 'deployment', 'source', 'config-zip',
                '--resource-group', $ResourceGroup,
                '--name', $mainOutputs.functionAppName.value,
                '--src', $functionZip,
                '--build-remote', 'true',
                '-o', 'none'
            ) -RetryWhenMessageContains @(
                'InaccessibleStorageException',
                'BlobUploadFailedException',
                'This request is not authorized',
                '403'
            ) | Out-Null
            Write-Host "  ✓ Function App deployed" -ForegroundColor Green
        } else {
            Write-Host "  - Function App worker package is not deployed by default (use -DeployFunctionWorker to opt in)." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  - App deployment skipped" -ForegroundColor Yellow
    }

    Write-Host "`n[8/8] Smoke check" -ForegroundColor Yellow
    $webUrl = $mainOutputs.webAppUrl.value
    Write-Host "  -> $webUrl/healthz" -ForegroundColor Gray
    try {
        $health = Invoke-RestMethod -Uri "$webUrl/healthz" -Method GET -TimeoutSec 30
        Write-Host "  ✓ Health: $($health.status), faultMode=$($health.faultMode)" -ForegroundColor Green
    } catch {
        Write-Host "  ! Health endpoint check failed. App may still be starting: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    if ($previewWarnings.Count -gt 0) {
        Write-Host "`nPreview warnings:" -ForegroundColor Yellow
        foreach ($warning in $previewWarnings) {
            Write-Host "  - $warning" -ForegroundColor Yellow
        }
    }

    Write-Host "`n✅ デプロイ処理が完了しました" -ForegroundColor Green
    Write-Host "Web UI: $webUrl" -ForegroundColor Cyan
    Write-Host "次: .\run-demo-traffic.ps1 -Endpoint $webUrl" -ForegroundColor Cyan
} catch {
    Write-Host "`n❌ デプロイに失敗しました: $($_.Exception.Message)" -ForegroundColor Red
    if ($CleanupOnFailure) {
        Write-Host "  -> CleanupOnFailure が指定されているため、今回の作成物を削除します" -ForegroundColor Yellow
        try {
            & (Join-Path $PSScriptRoot 'cleanup.ps1') -ScenarioCode $ScenarioCode -ResourceGroup $ResourceGroup -Force
        } catch {
            Write-Host "  ! cleanup に失敗しました: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    throw
} finally {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
