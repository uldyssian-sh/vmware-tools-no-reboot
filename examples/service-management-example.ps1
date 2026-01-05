# VMware Tools Service Management Example
# This script demonstrates how to manage VMware Tools services during upgrades

param(
    [Parameter(Mandatory=$true)]
    [string]$vCenter,
    
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$false)]
    [PSCredential]$Credential,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Check", "Start", "Stop", "Restart", "Upgrade")]
    [string]$Action = "Check"
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
    # Get target VM
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    Write-Host "Target VM: $($vm.Name)" -ForegroundColor Yellow
    
    # Check VM power state
    if ($vm.PowerState -ne "PoweredOn") {
        throw "VM must be powered on for service management"
    }
    
    # Get VM guest information
    $vmGuest = Get-VMGuest -VM $vm
    
    switch ($Action) {
        "Check" {
            Write-Host "`nVMware Tools Service Status:" -ForegroundColor Cyan
            Write-Host "=============================" -ForegroundColor Cyan
            
            # Get detailed tools information
            $toolsInfo = $vm.ExtensionData.Guest
            
            Write-Host "Tools Version: $($toolsInfo.ToolsVersion)" -ForegroundColor White
            Write-Host "Tools Status: $($toolsInfo.ToolsStatus)" -ForegroundColor White
            Write-Host "Tools Version Status: $($toolsInfo.ToolsVersionStatus2)" -ForegroundColor White
            Write-Host "Tools Running Status: $($toolsInfo.ToolsRunningStatus)" -ForegroundColor White
            Write-Host "Guest OS: $($vmGuest.OSFullName)" -ForegroundColor White
            Write-Host "Guest State: $($vmGuest.State)" -ForegroundColor White
            
            # Check if upgrade is available
            if ($toolsInfo.ToolsVersionStatus2 -eq "guestToolsNeedUpgrade") {
                Write-Host "🔄 VMware Tools upgrade available" -ForegroundColor Yellow
            } elseif ($toolsInfo.ToolsVersionStatus2 -eq "guestToolsCurrent") {
                Write-Host "✅ VMware Tools are current" -ForegroundColor Green
            }
            
            # Check service status
            if ($toolsInfo.ToolsRunningStatus -eq "guestToolsRunning") {
                Write-Host "🟢 VMware Tools service is running" -ForegroundColor Green
            } else {
                Write-Host "🔴 VMware Tools service is not running" -ForegroundColor Red
            }
        }
        
        "Start" {
            Write-Host "Starting VMware Tools service..." -ForegroundColor Yellow
            
            # For Windows VMs, we can try to start the service via PowerShell
            if ($vmGuest.OSFullName -like "*Windows*") {
                $script = @"
Start-Service -Name "VMTools" -ErrorAction SilentlyContinue
Get-Service -Name "VMTools" | Select-Object Name, Status
"@
                try {
                    $result = Invoke-VMScript -VM $vm -ScriptText $script -ScriptType PowerShell -GuestCredential (Get-Credential -Message "Enter guest OS credentials")
                    Write-Host "Service start result:" -ForegroundColor Green
                    Write-Host $result.ScriptOutput -ForegroundColor White
                } catch {
                    Write-Host "Failed to start service: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "Service management for Linux VMs requires manual intervention" -ForegroundColor Yellow
            }
        }
        
        "Stop" {
            Write-Host "Stopping VMware Tools service..." -ForegroundColor Yellow
            Write-Host "⚠️  Warning: This will disconnect VM management until service is restarted" -ForegroundColor Red
            
            $confirm = Read-Host "Are you sure you want to stop VMware Tools service? (y/N)"
            if ($confirm -eq "y" -or $confirm -eq "Y") {
                if ($vmGuest.OSFullName -like "*Windows*") {
                    $script = @"
Stop-Service -Name "VMTools" -Force -ErrorAction SilentlyContinue
Get-Service -Name "VMTools" | Select-Object Name, Status
"@
                    try {
                        $result = Invoke-VMScript -VM $vm -ScriptText $script -ScriptType PowerShell -GuestCredential (Get-Credential -Message "Enter guest OS credentials")
                        Write-Host "Service stop result:" -ForegroundColor Green
                        Write-Host $result.ScriptOutput -ForegroundColor White
                    } catch {
                        Write-Host "Failed to stop service: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "Operation cancelled" -ForegroundColor Yellow
            }
        }
        
        "Restart" {
            Write-Host "Restarting VMware Tools service..." -ForegroundColor Yellow
            
            if ($vmGuest.OSFullName -like "*Windows*") {
                $script = @"
Restart-Service -Name "VMTools" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Get-Service -Name "VMTools" | Select-Object Name, Status
"@
                try {
                    $result = Invoke-VMScript -VM $vm -ScriptText $script -ScriptType PowerShell -GuestCredential (Get-Credential -Message "Enter guest OS credentials")
                    Write-Host "Service restart result:" -ForegroundColor Green
                    Write-Host $result.ScriptOutput -ForegroundColor White
                } catch {
                    Write-Host "Failed to restart service: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        
        "Upgrade" {
            Write-Host "Performing VMware Tools upgrade with service management..." -ForegroundColor Yellow
            
            # Check current status
            $toolsInfo = $vm.ExtensionData.Guest
            
            if ($toolsInfo.ToolsRunningStatus -ne "guestToolsRunning") {
                Write-Host "❌ VMware Tools service is not running. Cannot perform upgrade." -ForegroundColor Red
                return
            }
            
            if ($toolsInfo.ToolsVersionStatus2 -eq "guestToolsCurrent") {
                Write-Host "ℹ️  VMware Tools are already current" -ForegroundColor Blue
                return
            }
            
            if ($toolsInfo.ToolsVersionStatus2 -eq "guestToolsNeedUpgrade" -or 
                $toolsInfo.ToolsVersionStatus2 -eq "guestToolsSupportedOld") {
                
                Write-Host "🔄 Starting no-reboot upgrade..." -ForegroundColor Green
                
                try {
                    # Perform the upgrade
                    Update-Tools -VM $vm -NoReboot
                    
                    Write-Host "✅ Upgrade initiated successfully" -ForegroundColor Green
                    Write-Host "⏳ Waiting for upgrade to complete..." -ForegroundColor Yellow
                    
                    # Monitor upgrade progress
                    $timeout = 300 # 5 minutes
                    $elapsed = 0
                    
                    do {
                        Start-Sleep -Seconds 10
                        $elapsed += 10
                        
                        # Refresh VM information
                        $vm = Get-VM -Name $VMName
                        $currentStatus = $vm.ExtensionData.Guest.ToolsVersionStatus2
                        
                        Write-Host "  Status: $currentStatus (${elapsed}s elapsed)" -ForegroundColor Gray
                        
                        if ($currentStatus -eq "guestToolsCurrent") {
                            Write-Host "🎉 Upgrade completed successfully!" -ForegroundColor Green
                            break
                        }
                        
                    } while ($elapsed -lt $timeout)
                    
                    if ($elapsed -ge $timeout) {
                        Write-Host "⚠️  Upgrade timeout reached. Check VM manually." -ForegroundColor Yellow
                    }
                    
                } catch {
                    Write-Host "❌ Upgrade failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "⚠️  Upgrade not supported for current tools status: $($toolsInfo.ToolsVersionStatus2)" -ForegroundColor Yellow
            }
        }
    }
    
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    # Disconnect from vCenter
    Disconnect-VIServer -Server $vCenter -Confirm:$false
    Write-Host "`nDisconnected from vCenter" -ForegroundColor Green
}

# Example usage:
# .\service-management-example.ps1 -vCenter "vcenter.lab.local" -VMName "TestVM" -Action Check
# .\service-management-example.ps1 -vCenter "vcenter.lab.local" -VMName "TestVM" -Action Upgrade