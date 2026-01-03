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

    Write-Information "=== No-Reboot Compatibility Check ===" -InformationAction Continue
    Write-Information "VM: $($vm.Name)" -InformationAction Continue
    Write-Information "Power State: $($vm.PowerState)" -InformationAction Continue
    Write-Information "Tools Status: $($vm.ExtensionData.Guest.ToolsStatus)" -InformationAction Continue
    Write-Information "Tools Version: $($vm.ExtensionData.Guest.ToolsVersion)" -InformationAction Continue

    $compatible = $vm.PowerState -eq "PoweredOn" -and
                  $vm.ExtensionData.Guest.ToolsStatus -ne "toolsNotInstalled" -and
                  $vm.ExtensionData.Guest.ToolsVersion -ge 10000

    if ($compatible) {
        Write-Information "✅ VM is compatible with no-reboot upgrade" -InformationAction Continue
    } else {
        Write-Information "❌ VM is NOT compatible with no-reboot upgrade" -InformationAction Continue
    }

    Disconnect-VIServer -Confirm:$false
} catch {
    Write-Error "Error: $($_.Exception.Message)"
}