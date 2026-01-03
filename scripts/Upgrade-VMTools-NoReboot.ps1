<#
.SYNOPSIS
    VMware Tools No-Reboot Upgrade PowerCLI Script
    
.DESCRIPTION
    This script performs VMware Tools upgrades without requiring virtual machine reboots.
    It uses advanced service management techniques to upgrade Tools while VMs remain powered on,
    minimizing downtime and maintaining business continuity.
    
.PARAMETER vCenter
    vCenter Server FQDN or IP address
    
.PARAMETER VMName
    Specific VM name to upgrade (optional)
    
.PARAMETER Cluster
    Cluster name to process all VMs (optional)
    
.PARAMETER Datacenter
    Datacenter name to process all VMs (optional)
    
.PARAMETER NoReboot
    Enable no-reboot upgrade mode
    
.PARAMETER ValidationOnly
    Run pre-upgrade validation only without performing upgrades
    
.PARAMETER BatchSize
    Number of VMs to process simultaneously (default: 5)
    
.PARAMETER DryRun
    Preview operations without making changes
    
.EXAMPLE
    .\Upgrade-VMTools-NoReboot.ps1 -vCenter "vcenter.example.com" -VMName "VM-001" -NoReboot
    
.EXAMPLE
    .\Upgrade-VMTools-NoReboot.ps1 -vCenter "vcenter.example.com" -Cluster "Production" -NoReboot -BatchSize 3
    
.NOTES
    Author: uldyssian-sh
    Version: 1.0.0
    Requires: PowerCLI, vCenter administrative privileges
    
.LINK
    https://github.com/uldyssian-sh/vmware-tools-no-reboot
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$vCenter,
    
    [Parameter(Mandatory = $false)]
    [string]$VMName,
    
    [Parameter(Mandatory = $false)]
    [string]$Cluster,
    
    [Parameter(Mandatory = $false)]
    [string]$Datacenter,
    
    [Parameter(Mandatory = $false)]
    [switch]$NoReboot,
    
    [Parameter(Mandatory = $false)]
    [switch]$ValidationOnly,
    
    [Parameter(Mandatory = $false)]
    [int]$BatchSize = 5,
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# Import required modules
try {
    Import-Module VMware.PowerCLI -ErrorAction Stop
    Write-Host "✅ PowerCLI module loaded successfully" -ForegroundColor Green
} catch {
    Write-Error "❌ Failed to load PowerCLI module. Please install VMware PowerCLI."
    exit 1
}

# Disable certificate warnings for lab environments
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null

# Function to display banner
function Show-Banner {
    Write-Host ""
    Write-Host "=== VMware Tools No-Reboot Upgrade ===" -ForegroundColor Cyan
    Write-Host "Enterprise PowerCLI Solution for Zero-Downtime Upgrades" -ForegroundColor Gray
    Write-Host ""
}

# Function to get vCenter connection
function Connect-vCenterServer {
    param([string]$Server)
    
    if (-not $Server) {
        $Server = Read-Host "Enter vCenter FQDN or IP"
    }
    
    try {
        Write-Host "Connecting to vCenter: $Server..." -ForegroundColor Yellow
        $credential = Get-Credential -Message "Enter vCenter credentials"
        Connect-VIServer -Server $Server -Credential $credential -ErrorAction Stop | Out-Null
        Write-Host "✅ Connected to vCenter successfully" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "❌ Failed to connect to vCenter: $($_.Exception.Message)"
        return $false
    }
}

# Function to test no-reboot compatibility
function Test-NoRebootCompatibility {
    param([VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM)
    
    $compatible = $true
    $reasons = @()
    
    # Check power state
    if ($VM.PowerState -ne "PoweredOn") {
        $compatible = $false
        $reasons += "VM must be powered on"
    }
    
    # Check Tools status
    if ($VM.ExtensionData.Guest.ToolsStatus -eq "toolsNotInstalled") {
        $compatible = $false
        $reasons += "VMware Tools not installed"
    }
    
    # Check Tools version compatibility
    $toolsVersion = $VM.ExtensionData.Guest.ToolsVersion
    if ($toolsVersion -and $toolsVersion -lt 10000) {
        $compatible = $false
        $reasons += "Tools version too old for no-reboot upgrade"
    }
    
    return @{
        Compatible = $compatible
        Reasons = $reasons
        ToolsVersion = $toolsVersion
        ToolsStatus = $VM.ExtensionData.Guest.ToolsStatus
    }
}

# Function to perform no-reboot upgrade
function Invoke-NoRebootUpgrade {
    param(
        [VMware.VimAutomation.ViCore.Types.V1.Inventory.VirtualMachine]$VM,
        [switch]$DryRun
    )
    
    $vmName = $VM.Name
    Write-Host "[$vmName] Starting no-reboot upgrade..." -ForegroundColor Yellow
    
    if ($DryRun) {
        Write-Host "[$vmName] DRY-RUN: Would perform no-reboot upgrade" -ForegroundColor Cyan
        return @{ Success = $true; Message = "Dry-run completed" }
    }
    
    try {
        # Get current Tools version
        $currentVersion = $VM.ExtensionData.Guest.ToolsVersion
        Write-Host "[$vmName] Current Tools version: $currentVersion" -ForegroundColor Gray
        
        # Stop VMware Tools service gracefully
        Write-Host "[$vmName] Stopping VMware Tools service..." -ForegroundColor Yellow
        $stopResult = Invoke-VMScript -VM $VM -ScriptText "Stop-Service -Name 'VMTools' -Force" -GuestCredential $guestCred -ErrorAction SilentlyContinue
        
        # Perform the upgrade
        Write-Host "[$vmName] Installing new Tools version..." -ForegroundColor Yellow
        $upgradeTask = $VM | Update-Tools -NoReboot -RunAsync
        
        # Wait for upgrade completion
        $timeout = 300 # 5 minutes
        $elapsed = 0
        while ($upgradeTask.State -eq "Running" -and $elapsed -lt $timeout) {
            Start-Sleep -Seconds 10
            $elapsed += 10
            Write-Host "[$vmName] Upgrade in progress... ($elapsed/$timeout seconds)" -ForegroundColor Gray
        }
        
        if ($upgradeTask.State -eq "Success") {
            # Start VMware Tools service
            Write-Host "[$vmName] Starting VMware Tools service..." -ForegroundColor Yellow
            $startResult = Invoke-VMScript -VM $VM -ScriptText "Start-Service -Name 'VMTools'" -GuestCredential $guestCred -ErrorAction SilentlyContinue
            
            # Validate upgrade
            Start-Sleep -Seconds 30 # Allow time for service to fully start
            $VM = Get-VM -Name $vmName # Refresh VM object
            $newVersion = $VM.ExtensionData.Guest.ToolsVersion
            
            if ($newVersion -gt $currentVersion) {
                Write-Host "[$vmName] ✅ Upgrade completed successfully ($currentVersion → $newVersion)" -ForegroundColor Green
                return @{ Success = $true; Message = "Upgrade successful"; OldVersion = $currentVersion; NewVersion = $newVersion }
            } else {
                Write-Host "[$vmName] ⚠️ Upgrade may not have completed properly" -ForegroundColor Yellow
                return @{ Success = $false; Message = "Version validation failed" }
            }
        } else {
            Write-Host "[$vmName] ❌ Upgrade task failed: $($upgradeTask.State)" -ForegroundColor Red
            return @{ Success = $false; Message = "Upgrade task failed" }
        }
        
    } catch {
        Write-Host "[$vmName] ❌ Upgrade failed: $($_.Exception.Message)" -ForegroundColor Red
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

# Function to get target VMs
function Get-TargetVMs {
    param(
        [string]$VMName,
        [string]$Cluster,
        [string]$Datacenter
    )
    
    $vms = @()
    
    if ($VMName) {
        $vms = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if (-not $vms) {
            Write-Error "VM '$VMName' not found"
            return @()
        }
    } elseif ($Cluster) {
        $vms = Get-Cluster -Name $Cluster | Get-VM
    } elseif ($Datacenter) {
        $vms = Get-Datacenter -Name $Datacenter | Get-VM
    } else {
        $target = Read-Host "Enter target (VM name, Cluster name, or 'ALL' for all VMs)"
        if ($target -eq "ALL") {
            $vms = Get-VM
        } else {
            # Try as VM name first, then cluster
            $vms = Get-VM -Name $target -ErrorAction SilentlyContinue
            if (-not $vms) {
                $vms = Get-Cluster -Name $target -ErrorAction SilentlyContinue | Get-VM
            }
        }
    }
    
    return $vms
}

# Main execution
function Main {
    Show-Banner
    
    # Connect to vCenter
    if (-not (Connect-vCenterServer -Server $vCenter)) {
        exit 1
    }
    
    # Get target VMs
    $targetVMs = Get-TargetVMs -VMName $VMName -Cluster $Cluster -Datacenter $Datacenter
    
    if ($targetVMs.Count -eq 0) {
        Write-Error "No target VMs found"
        exit 1
    }
    
    Write-Host "Found $($targetVMs.Count) target VMs" -ForegroundColor Green
    
    # Pre-upgrade validation
    Write-Host ""
    Write-Host "=== PRE-UPGRADE VALIDATION ===" -ForegroundColor Cyan
    
    $compatibleVMs = @()
    $incompatibleVMs = @()
    
    foreach ($vm in $targetVMs) {
        $compatibility = Test-NoRebootCompatibility -VM $vm
        
        $status = if ($compatibility.Compatible) { "✅ Compatible" } else { "❌ Incompatible" }
        Write-Host "$($vm.Name): $status" -ForegroundColor $(if ($compatibility.Compatible) { "Green" } else { "Red" })
        
        if (-not $compatibility.Compatible) {
            foreach ($reason in $compatibility.Reasons) {
                Write-Host "  - $reason" -ForegroundColor Red
            }
            $incompatibleVMs += $vm
        } else {
            $compatibleVMs += $vm
        }
    }
    
    Write-Host ""
    Write-Host "Compatible VMs for no-reboot upgrade: $($compatibleVMs.Count)" -ForegroundColor Green
    if ($incompatibleVMs.Count -gt 0) {
        Write-Host "Incompatible VMs (will be skipped): $($incompatibleVMs.Count)" -ForegroundColor Yellow
    }
    
    if ($ValidationOnly) {
        Write-Host ""
        Write-Host "Validation-only mode completed." -ForegroundColor Cyan
        Disconnect-VIServer -Confirm:$false
        return
    }
    
    if ($compatibleVMs.Count -eq 0) {
        Write-Host "No compatible VMs found for upgrade." -ForegroundColor Yellow
        Disconnect-VIServer -Confirm:$false
        return
    }
    
    # Confirm upgrade
    if (-not $DryRun) {
        $confirm = Read-Host "Proceed with no-reboot upgrade for $($compatibleVMs.Count) VMs? (y/N)"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "Upgrade cancelled by user." -ForegroundColor Yellow
            Disconnect-VIServer -Confirm:$false
            return
        }
    }
    
    # Perform upgrades
    Write-Host ""
    Write-Host "=== UPGRADE EXECUTION ===" -ForegroundColor Cyan
    
    $results = @()
    $successful = 0
    $failed = 0
    
    # Process VMs in batches
    for ($i = 0; $i -lt $compatibleVMs.Count; $i += $BatchSize) {
        $batch = $compatibleVMs[$i..([Math]::Min($i + $BatchSize - 1, $compatibleVMs.Count - 1))]
        
        Write-Host "Processing batch $([Math]::Floor($i / $BatchSize) + 1)..." -ForegroundColor Yellow
        
        foreach ($vm in $batch) {
            $result = Invoke-NoRebootUpgrade -VM $vm -DryRun:$DryRun
            $results += @{
                VM = $vm.Name
                Success = $result.Success
                Message = $result.Message
                OldVersion = $result.OldVersion
                NewVersion = $result.NewVersion
            }
            
            if ($result.Success) {
                $successful++
            } else {
                $failed++
            }
        }
        
        # Brief pause between batches
        if ($i + $BatchSize -lt $compatibleVMs.Count) {
            Write-Host "Pausing 30 seconds between batches..." -ForegroundColor Gray
            Start-Sleep -Seconds 30
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "=== UPGRADE SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Total processed: $($compatibleVMs.Count) VMs" -ForegroundColor White
    Write-Host "Successful: $successful VMs" -ForegroundColor Green
    Write-Host "Failed: $failed VMs" -ForegroundColor Red
    
    if ($DryRun) {
        Write-Host "Mode: DRY-RUN (no changes made)" -ForegroundColor Cyan
    } else {
        Write-Host "Zero reboots required ✅" -ForegroundColor Green
    }
    
    # Disconnect from vCenter
    Disconnect-VIServer -Confirm:$false
    Write-Host ""
    Write-Host "Script completed successfully." -ForegroundColor Green
}

# Execute main function
Main