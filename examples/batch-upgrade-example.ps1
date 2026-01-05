# Batch VMware Tools No-Reboot Upgrade Example
# This script demonstrates how to upgrade VMware Tools on multiple VMs without reboots

param(
    [Parameter(Mandatory=$true)]
    [string]$vCenter,
    
    [Parameter(Mandatory=$false)]
    [string[]]$VMNames,
    
    [Parameter(Mandatory=$false)]
    [string]$VMPattern = "*",
    
    [Parameter(Mandatory=$false)]
    [PSCredential]$Credential,
    
    [Parameter(Mandatory=$false)]
    [int]$BatchSize = 5,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Import required modules
Import-Module VMware.PowerCLI -ErrorAction Stop

# Connect to vCenter
Write-Host "Connecting to vCenter: $vCenter" -ForegroundColor Green
if ($Credential) {
    Connect-VIServer -Server $vCenter -Credential $Credential | Out-Null
} else {
    Connect-VIServer -Server $vCenter | Out-Null
}

try {
    # Get target VMs
    if ($VMNames) {
        $targetVMs = $VMNames | ForEach-Object { Get-VM -Name $_ -ErrorAction SilentlyContinue }
    } else {
        $targetVMs = Get-VM -Name $VMPattern | Where-Object { $_.PowerState -eq "PoweredOn" }
    }
    
    Write-Host "Found $($targetVMs.Count) target VMs" -ForegroundColor Yellow
    
    # Process VMs in batches
    $processed = 0
    $successful = 0
    $failed = 0
    
    for ($i = 0; $i -lt $targetVMs.Count; $i += $BatchSize) {
        $batch = $targetVMs[$i..([Math]::Min($i + $BatchSize - 1, $targetVMs.Count - 1))]
        
        Write-Host "`nProcessing batch $([Math]::Floor($i / $BatchSize) + 1)..." -ForegroundColor Cyan
        
        foreach ($vm in $batch) {
            $processed++
            Write-Host "[$processed/$($targetVMs.Count)] Processing: $($vm.Name)" -ForegroundColor White
            
            try {
                # Check current VMware Tools status
                $toolsStatus = $vm.ExtensionData.Guest.ToolsVersionStatus2
                $toolsRunning = $vm.ExtensionData.Guest.ToolsRunningStatus
                
                Write-Host "  Current status: $toolsStatus, Running: $toolsRunning" -ForegroundColor Gray
                
                # Check if upgrade is needed and possible
                if ($toolsRunning -eq "guestToolsRunning" -and 
                    ($toolsStatus -eq "guestToolsNeedUpgrade" -or $toolsStatus -eq "guestToolsSupportedOld")) {
                    
                    if ($WhatIf) {
                        Write-Host "  [WHATIF] Would upgrade VMware Tools on $($vm.Name)" -ForegroundColor Yellow
                    } else {
                        Write-Host "  Upgrading VMware Tools..." -ForegroundColor Green
                        Update-Tools -VM $vm -NoReboot -RunAsync | Out-Null
                        
                        # Wait a moment for the upgrade to start
                        Start-Sleep -Seconds 2
                        
                        Write-Host "  ✅ Upgrade initiated successfully" -ForegroundColor Green
                    }
                    $successful++
                } elseif ($toolsStatus -eq "guestToolsCurrent") {
                    Write-Host "  ℹ️  VMware Tools already current" -ForegroundColor Blue
                    $successful++
                } elseif ($toolsRunning -ne "guestToolsRunning") {
                    Write-Host "  ⚠️  VMware Tools not running - skipping" -ForegroundColor Yellow
                    $failed++
                } else {
                    Write-Host "  ⚠️  No upgrade needed or not supported" -ForegroundColor Yellow
                    $successful++
                }
                
            } catch {
                Write-Host "  ❌ Error processing $($vm.Name): $($_.Exception.Message)" -ForegroundColor Red
                $failed++
            }
        }
        
        # Pause between batches
        if ($i + $BatchSize -lt $targetVMs.Count) {
            Write-Host "Waiting 10 seconds before next batch..." -ForegroundColor Gray
            Start-Sleep -Seconds 10
        }
    }
    
    # Summary
    Write-Host "`n" + "="*50 -ForegroundColor Cyan
    Write-Host "BATCH UPGRADE SUMMARY" -ForegroundColor Cyan
    Write-Host "="*50 -ForegroundColor Cyan
    Write-Host "Total VMs processed: $processed" -ForegroundColor White
    Write-Host "Successful: $successful" -ForegroundColor Green
    Write-Host "Failed: $failed" -ForegroundColor Red
    Write-Host "Success rate: $([Math]::Round(($successful / $processed) * 100, 2))%" -ForegroundColor Yellow
    
} finally {
    # Disconnect from vCenter
    Disconnect-VIServer -Server $vCenter -Confirm:$false
    Write-Host "`nDisconnected from vCenter" -ForegroundColor Green
}

# Example usage:
# .\batch-upgrade-example.ps1 -vCenter "vcenter.lab.local" -VMPattern "Web*" -BatchSize 3
# .\batch-upgrade-example.ps1 -vCenter "vcenter.lab.local" -VMNames @("VM-001", "VM-002", "VM-003") -WhatIf