<#
.SYNOPSIS
    VMware Tools Status Checker Utility
    
.DESCRIPTION
    Comprehensive utility to check VMware Tools status across multiple VMs
    with detailed state reporting and upgrade recommendations.
    
.PARAMETER vCenter
    vCenter Server FQDN or IP address
    
.PARAMETER Cluster
    Cluster name to check all VMs
    
.EXAMPLE
    .\VMware-Tools-Status-Checker.ps1 -vCenter "vcenter.example.com" -Cluster "Production"
    
.NOTES
    Author: uldyssian-sh
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$vCenter,
    
    [Parameter(Mandatory = $false)]
    [string]$Cluster
)

# Check PowerCLI availability
if (-not (Get-Command Connect-VIServer -ErrorAction SilentlyContinue)) {
    Write-Error "PowerCLI not available. Please load VMware.PowerCLI module."
    return
}

try {
    # Connect to vCenter
    $cred = Get-Credential -Message "Enter vCenter credentials"
    Connect-VIServer -Server $vCenter -Credential $cred -ErrorAction Stop | Out-Null
    
    # Get VMs
    if ($Cluster) {
        $vms = Get-Cluster -Name $Cluster | Get-VM
    } else {
        $vms = Get-VM
    }
    
    Write-Host "=== VMware Tools Status Report ===" -ForegroundColor Cyan
    Write-Host "vCenter: $vCenter" -ForegroundColor White
    Write-Host "Total VMs: $($vms.Count)" -ForegroundColor White
    Write-Host ""
    
    $results = @()
    foreach ($vm in $vms) {
        $guest = $vm.ExtensionData.Guest
        $results += [PSCustomObject]@{
            VMName = $vm.Name
            PowerState = $vm.PowerState
            ToolsVersion = $guest.ToolsVersion
            ToolsVersionStatus2 = $guest.ToolsVersionStatus2
            ToolsStatus = $guest.ToolsStatus
            ToolsRunningStatus = $guest.ToolsRunningStatus
            UpgradeRecommended = ($guest.ToolsVersionStatus2 -in @("guestToolsNeedUpgrade", "guestToolsSupportedOld") -or 
                                 $guest.ToolsStatus -in @("guestToolsNeedUpgrade", "guestToolsSupportedOld"))
        }
    }
    
    # Display results
    $results | Format-Table -AutoSize
    
    # Summary
    $upgradeNeeded = ($results | Where-Object { $_.UpgradeRecommended }).Count
    $toolsRunning = ($results | Where-Object { $_.ToolsRunningStatus -eq "guestToolsRunning" }).Count
    
    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "VMs needing upgrade: $upgradeNeeded" -ForegroundColor Yellow
    Write-Host "VMs with Tools running: $toolsRunning" -ForegroundColor Green
    Write-Host "VMs eligible for no-reboot upgrade: $(($results | Where-Object { $_.UpgradeRecommended -and $_.ToolsRunningStatus -eq 'guestToolsRunning' -and $_.PowerState -eq 'PoweredOn' }).Count)" -ForegroundColor Cyan
    
    Disconnect-VIServer -Confirm:$false
} catch {
    Write-Error "Error: $($_.Exception.Message)"
}