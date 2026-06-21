param(
    [switch]$Apply,
    [string]$TargetRoot = 'infra',
    [string]$ReportPath = 'docs/operations/avm-version-review.md'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$targetPath = Join-Path $repoRoot $TargetRoot
$reportFullPath = Join-Path $repoRoot $ReportPath

if (-not (Test-Path $targetPath)) {
    throw "Target path does not exist: $targetPath"
}

$pattern = "br/public:(avm/res/[a-zA-Z0-9\-/]+):([0-9]+\.[0-9]+\.[0-9]+)"
$bicepFiles = Get-ChildItem -Path $targetPath -Recurse -File -Filter '*.bicep'

$tagCache = @{}
$results = New-Object System.Collections.Generic.List[object]

foreach ($file in $bicepFiles) {
    $content = Get-Content -Path $file.FullName -Raw
    $regex = [regex]::new($pattern)
    $firstRef = $regex.Match($content)
    if (-not $firstRef.Success) {
        $results.Add([pscustomobject]@{
            File = $file.FullName.Replace($repoRoot + [System.IO.Path]::DirectorySeparatorChar, '')
            Module = '-'
            Current = '-'
            Latest = '-'
            Status = 'No AVM references'
        })
        continue
    }

    $moduleRefs = New-Object System.Collections.Generic.List[object]
    $cursor = $firstRef
    while ($cursor.Success) {
        $moduleRefs.Add($cursor)
        $cursor = $cursor.NextMatch()
    }

    $updatedContent = $content

    foreach ($m in $moduleRefs) {
        $modulePath = $m.Groups[1].Value
        $currentVersion = $m.Groups[2].Value
        $cacheKey = $modulePath

        if (-not $tagCache.ContainsKey($cacheKey)) {
            $url = "https://mcr.microsoft.com/v2/bicep/$modulePath/tags/list"
            try {
                $resp = Invoke-RestMethod -Uri $url -Method Get
                $versions = @($resp.tags | Where-Object { $_ -match '^[0-9]+\.[0-9]+\.[0-9]+$' })
                if ($versions.Count -eq 0) {
                    $tagCache[$cacheKey] = $null
                } else {
                    $latest = $versions | Sort-Object { [version]$_ } -Descending | Select-Object -First 1
                    $tagCache[$cacheKey] = $latest
                }
            }
            catch {
                $tagCache[$cacheKey] = $null
            }
        }

        $latestVersion = $tagCache[$cacheKey]
        if ([string]::IsNullOrWhiteSpace($latestVersion)) {
            $results.Add([pscustomobject]@{
                File = $file.FullName.Replace($repoRoot + [System.IO.Path]::DirectorySeparatorChar, '')
                Module = $modulePath
                Current = $currentVersion
                Latest = 'Failed'
                Status = 'Failed'
            })
            continue
        }

        $isOutdated = ([version]$currentVersion -lt [version]$latestVersion)
        if ($isOutdated -and $Apply) {
            $oldRef = ('br/public:{0}:{1}' -f $modulePath, $currentVersion)
            $newRef = ('br/public:{0}:{1}' -f $modulePath, $latestVersion)
            $updatedContent = $updatedContent.Replace($oldRef, $newRef)
        }

        $results.Add([pscustomobject]@{
            File = $file.FullName.Replace($repoRoot + [System.IO.Path]::DirectorySeparatorChar, '')
            Module = $modulePath
            Current = $currentVersion
            Latest = $latestVersion
            Status = $(if ($isOutdated) { 'Needs Update' } else { 'Latest' })
        })
    }

    if ($Apply -and $updatedContent -ne $content) {
        Set-Content -Path $file.FullName -Value $updatedContent -Encoding UTF8
    }
}

$reportDir = Split-Path -Parent $reportFullPath
if (-not (Test-Path $reportDir)) {
    New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
}

$lines = @()
$lines += '# AVM Version Review Report'
$lines += ''
$lines += "- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
$lines += "- Auto-Update: $(if ($Apply) { 'Enabled' } else { 'Disabled' })"
$lines += ''
$lines += '| File | Module | Current | Latest | Status |'
$lines += '|---|---|---|---|---|'

if ($results.Count -eq 0) {
    $lines += '| (No matches) | - | - | - | - |'
} else {
    foreach ($r in $results) {
        $lines += "| $($r.File) | $($r.Module) | $($r.Current) | $($r.Latest) | $($r.Status) |"
    }
}

Set-Content -Path $reportFullPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
Write-Host "Report generated: $reportFullPath"

$outdatedCount = @($results | Where-Object { $_.Status -eq 'Needs Update' }).Count
$failedCount = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
$noAvmCount = @($results | Where-Object { $_.Status -eq 'No AVM references' }).Count

if ($failedCount -gt 0) {
    Write-Warning "Failed to fetch tags for $failedCount modules"
}

if ($outdatedCount -gt 0 -and -not $Apply) {
    Write-Warning "Found $outdatedCount outdated AVM references"
}

if ($noAvmCount -gt 0) {
    Write-Warning "Found $noAvmCount Bicep files without AVM references"
}
