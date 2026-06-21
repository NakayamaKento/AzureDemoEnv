[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot

$targets = @(
    'TeamsAppPackage-*.zip',
    'teams-manifest-*',
    'bot-app-package*.zip',
    'bot-app-deploy.zip',
    'logs\\unzipped',
    'logs\\*.zip'
)

foreach ($pattern in $targets) {
    Get-ChildItem -Path $root -Filter $pattern -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.PSIsContainer) {
            Remove-Item $_.FullName -Recurse -Force
            Write-Host "Removed directory: $($_.FullName)" -ForegroundColor Yellow
        } else {
            Remove-Item $_.FullName -Force
            Write-Host "Removed file: $($_.FullName)" -ForegroundColor Yellow
        }
    }
}

Write-Host 'Cleanup completed.' -ForegroundColor Green
