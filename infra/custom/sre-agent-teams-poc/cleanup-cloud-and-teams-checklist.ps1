[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [string]$SubscriptionId = '41071e92-3ceb-44a2-a41e-5c5255c5e5b9',

    [switch]$DeleteResourceGroup,

    [switch]$NoWait
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '=== Cleanup: Local artifacts ===' -ForegroundColor Cyan
$localCleanup = Join-Path $PSScriptRoot 'cleanup-artifacts.ps1'
if (Test-Path $localCleanup) {
    & $localCleanup
} else {
    Write-Host 'cleanup-artifacts.ps1 not found. Skip local cleanup.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '=== Cleanup: Azure context ===' -ForegroundColor Cyan
az account set --subscription $SubscriptionId | Out-Null
Write-Host "Subscription set: $SubscriptionId" -ForegroundColor Green

$exists = (az group exists --name $ResourceGroup | Out-String).Trim()
if ($exists -ne 'true') {
    Write-Host "Resource group not found: $ResourceGroup" -ForegroundColor Yellow
} else {
    Write-Host "Resource group exists: $ResourceGroup" -ForegroundColor Yellow

    if ($DeleteResourceGroup) {
        Write-Host "Deleting resource group: $ResourceGroup" -ForegroundColor Yellow
        if ($NoWait) {
            az group delete --name $ResourceGroup --yes --no-wait | Out-Null
            Write-Host 'Delete requested with --no-wait.' -ForegroundColor Green
        } else {
            az group delete --name $ResourceGroup --yes | Out-Null
            Write-Host 'Delete completed.' -ForegroundColor Green
        }
    } else {
        Write-Host 'Dry-run mode: resource group was NOT deleted.' -ForegroundColor Yellow
        Write-Host 'Add -DeleteResourceGroup to actually delete it.' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host '=== Cleanup: Teams manual checklist ===' -ForegroundColor Cyan
Write-Host '1) Teams client: uninstall the bot app from chat/team.' -ForegroundColor White
Write-Host '2) Teams admin center: remove the uploaded custom app package.' -ForegroundColor White
Write-Host '3) Developer Portal (if used): remove the app definition.' -ForegroundColor White
Write-Host '4) Verify the app no longer appears in Teams search/app list.' -ForegroundColor White

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
