<#
.SYNOPSIS
    VMware Tools No-Reboot Compatibility Checker
    
.DESCRIPTION
    This script tests virtual machines for compatibility with no-reboot VMware Tools upgrades.
    It validates VM state, Tools version, and system requirements.
    
.PARAMETER vCenter
    vCenter Server FQDN or IP address
    
.PARAMETER VMName
    Specific VM name to test
    
.EXAMPLE
    .\Test-NoRebootCompatibility.ps1 -vCenter "vcenter.example.com" -VMName "VM-001"
    
.NOTES
    Author: uldyssian-sh
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$vCenter,
    
    [Parameter(Mandatory = $true)]
    [string]$VMName
)

Import-Module VMware.PowerCLI -ErrorAction Stop

try {
    Connect-VIServer -Server $vCenter
    $vm = Get-VM -Name $VMName
    
    Write-Host "=== No-Reboot Compatibility Check ===" -ForegroundColor Cyan
    Write-Host "VM: $($vm.Name)" -ForegroundColor White
    Write-Host "Power State: $($vm.PowerState)" -ForegroundColor White
    Write-Host "Tools Status: $($vm.ExtensionData.Guest.ToolsStatus)" -ForegroundColor White
    Write-Host "Tools Version: $($vm.ExtensionData.Guest.ToolsVersion)" -ForegroundColor White
    
    $compatible = $vm.PowerState -eq "PoweredOn" -and 
                  $vm.ExtensionData.Guest.ToolsStatus -ne "toolsNotInstalled" -and
                  $vm.ExtensionData.Guest.ToolsVersion -ge 10000
    
    if ($compatible) {
        Write-Host "✅ VM is compatible with no-reboot upgrade" -ForegroundColor Green
    } else {
        Write-Host "❌ VM is NOT compatible with no-reboot upgrade" -ForegroundColor Red
    }
    
    Disconnect-VIServer -Confirm:$false
} catch {
    Write-Error "Error: $($_.Exception.Message)"
}