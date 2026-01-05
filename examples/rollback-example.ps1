# VMware Tools Rollback Example
# This script demonstrates rollback procedures for VMware Tools upgrades

param(
    [Parameter(Mandatory=$true)]
    [string]$vCenter,
    
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$false)]
    [PSCredential]$Credential,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("CreateSnapshot", "RestoreSnapshot", "CheckRollback", "ManualRollback")]
    [string]$Action = "CheckRollback",
    
    [Parameter(Mandatory=$false)]
    [string]$SnapshotName = "Pre-VMTools-Upgrade-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
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
    
    switch ($Action) {
        "CreateSnapshot" {
            Write-Host "`nCreating pre-upgrade snapshot..." -ForegroundColor Cyan
            
            # Check if VM is powered on
            if ($vm.PowerState -ne "PoweredOn") {
                Write-Host "⚠️  VM is not powered on. Snapshot will not include memory state." -ForegroundColor Yellow
            }
            
            try {
                # Create snapshot
                $snapshot = New-Snapshot -VM $vm -Name $SnapshotName -Description "Pre-VMware Tools upgrade snapshot created on $(Get-Date)" -Memory:($vm.PowerState -eq "PoweredOn") -Quiesce:($vm.PowerState -eq "PoweredOn")
                
                Write-Host "✅ Snapshot created successfully:" -ForegroundColor Green
                Write-Host "   Name: $($snapshot.Name)" -ForegroundColor White
                Write-Host "   Description: $($snapshot.Description)" -ForegroundColor White
                Write-Host "   Created: $($snapshot.Created)" -ForegroundColor White
                Write-Host "   Size: $([Math]::Round($snapshot.SizeGB, 2)) GB" -ForegroundColor White
                
                # Store snapshot info for later use
                $snapshotInfo = @{
                    Name = $snapshot.Name
                    Created = $snapshot.Created
                    VM = $vm.Name
                }
                
                $snapshotInfo | ConvertTo-Json | Out-File -FilePath "snapshot-$($vm.Name)-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
                Write-Host "📄 Snapshot information saved to JSON file" -ForegroundColor Blue
                
            } catch {
                Write-Host "❌ Failed to create snapshot: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        "RestoreSnapshot" {
            Write-Host "`nRestoring from snapshot..." -ForegroundColor Cyan
            
            # Get available snapshots
            $snapshots = Get-Snapshot -VM $vm | Sort-Object Created -Descending
            
            if ($snapshots.Count -eq 0) {
                Write-Host "❌ No snapshots found for VM $($vm.Name)" -ForegroundColor Red
                return
            }
            
            Write-Host "Available snapshots:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $snapshots.Count; $i++) {
                Write-Host "  [$i] $($snapshots[$i].Name) - $($snapshots[$i].Created)" -ForegroundColor White
            }
            
            # Select snapshot to restore
            if ($snapshots.Count -eq 1) {
                $selectedSnapshot = $snapshots[0]
                Write-Host "Using only available snapshot: $($selectedSnapshot.Name)" -ForegroundColor Yellow
            } else {
                $selection = Read-Host "Select snapshot to restore (0-$($snapshots.Count-1)) or press Enter for most recent"
                if ([string]::IsNullOrEmpty($selection)) {
                    $selectedSnapshot = $snapshots[0]
                } else {
                    $selectedSnapshot = $snapshots[[int]$selection]
                }
            }
            
            Write-Host "⚠️  WARNING: This will revert the VM to the snapshot state!" -ForegroundColor Red
            Write-Host "   Selected snapshot: $($selectedSnapshot.Name)" -ForegroundColor Yellow
            Write-Host "   Created: $($selectedSnapshot.Created)" -ForegroundColor Yellow
            
            $confirm = Read-Host "Are you sure you want to restore this snapshot? (y/N)"
            if ($confirm -eq "y" -or $confirm -eq "Y") {
                try {
                    Write-Host "🔄 Restoring snapshot..." -ForegroundColor Yellow
                    Set-VM -VM $vm -Snapshot $selectedSnapshot -Confirm:$false
                    
                    Write-Host "✅ Snapshot restored successfully" -ForegroundColor Green
                    Write-Host "🔄 VM may need to be powered on manually" -ForegroundColor Blue
                    
                } catch {
                    Write-Host "❌ Failed to restore snapshot: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "Operation cancelled" -ForegroundColor Yellow
            }
        }
        
        "CheckRollback" {
            Write-Host "`nChecking rollback options..." -ForegroundColor Cyan
            
            # Get current VMware Tools status
            $toolsInfo = $vm.ExtensionData.Guest
            
            Write-Host "Current VMware Tools Status:" -ForegroundColor Yellow
            Write-Host "  Version: $($toolsInfo.ToolsVersion)" -ForegroundColor White
            Write-Host "  Status: $($toolsInfo.ToolsVersionStatus2)" -ForegroundColor White
            Write-Host "  Running: $($toolsInfo.ToolsRunningStatus)" -ForegroundColor White
            
            # Check for snapshots
            $snapshots = Get-Snapshot -VM $vm | Sort-Object Created -Descending
            
            if ($snapshots.Count -gt 0) {
                Write-Host "`nAvailable rollback snapshots:" -ForegroundColor Green
                foreach ($snapshot in $snapshots) {
                    Write-Host "  📸 $($snapshot.Name) - $($snapshot.Created)" -ForegroundColor White
                    Write-Host "     Size: $([Math]::Round($snapshot.SizeGB, 2)) GB" -ForegroundColor Gray
                }
                
                Write-Host "`n✅ Rollback via snapshot is available" -ForegroundColor Green
            } else {
                Write-Host "`n⚠️  No snapshots available for rollback" -ForegroundColor Yellow
            }
            
            # Check for manual rollback options
            Write-Host "`nManual rollback options:" -ForegroundColor Yellow
            Write-Host "  🔧 Reinstall previous VMware Tools version" -ForegroundColor White
            Write-Host "  🔄 Restore from VM backup" -ForegroundColor White
            Write-Host "  ⚙️  Use VMware Tools installer with /S /v/qn REINSTALL=ALL" -ForegroundColor White
        }
        
        "ManualRollback" {
            Write-Host "`nManual rollback procedure..." -ForegroundColor Cyan
            
            # Get guest OS information
            $vmGuest = Get-VMGuest -VM $vm
            
            Write-Host "Guest OS: $($vmGuest.OSFullName)" -ForegroundColor Yellow
            
            if ($vmGuest.OSFullName -like "*Windows*") {
                Write-Host "`nWindows VMware Tools Manual Rollback Steps:" -ForegroundColor Green
                Write-Host "1. Connect to VM console or RDP" -ForegroundColor White
                Write-Host "2. Download previous VMware Tools version" -ForegroundColor White
                Write-Host "3. Run: VMware-tools-windows-x.x.x-xxxxx.exe /S /v/qn REINSTALL=ALL" -ForegroundColor White
                Write-Host "4. Reboot the VM after installation" -ForegroundColor White
                
                # Try to get current tools installer path
                $script = @"
Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -like "*VMware Tools*"} | Select-Object Name, Version, InstallDate
"@
                
                try {
                    Write-Host "`nCurrent VMware Tools installation:" -ForegroundColor Yellow
                    $result = Invoke-VMScript -VM $vm -ScriptText $script -ScriptType PowerShell -GuestCredential (Get-Credential -Message "Enter guest OS credentials")
                    Write-Host $result.ScriptOutput -ForegroundColor White
                } catch {
                    Write-Host "Could not retrieve installation information: $($_.Exception.Message)" -ForegroundColor Red
                }
                
            } elseif ($vmGuest.OSFullName -like "*Linux*") {
                Write-Host "`nLinux VMware Tools Manual Rollback Steps:" -ForegroundColor Green
                Write-Host "1. Connect to VM via SSH or console" -ForegroundColor White
                Write-Host "2. Stop VMware Tools: sudo /etc/init.d/vmware-tools stop" -ForegroundColor White
                Write-Host "3. Uninstall current tools: sudo vmware-uninstall-tools.pl" -ForegroundColor White
                Write-Host "4. Install previous version: sudo ./vmware-install.pl" -ForegroundColor White
                Write-Host "5. Start VMware Tools: sudo /etc/init.d/vmware-tools start" -ForegroundColor White
            } else {
                Write-Host "⚠️  Manual rollback steps vary by operating system" -ForegroundColor Yellow
                Write-Host "Please refer to VMware documentation for your specific OS" -ForegroundColor White
            }
            
            Write-Host "`n📚 Additional Resources:" -ForegroundColor Blue
            Write-Host "  - VMware Tools Installation Guide" -ForegroundColor White
            Write-Host "  - VMware KB articles for rollback procedures" -ForegroundColor White
            Write-Host "  - Contact VMware Support if needed" -ForegroundColor White
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
# .\rollback-example.ps1 -vCenter "vcenter.lab.local" -VMName "TestVM" -Action CreateSnapshot
# .\rollback-example.ps1 -vCenter "vcenter.lab.local" -VMName "TestVM" -Action CheckRollback
# .\rollback-example.ps1 -vCenter "vcenter.lab.local" -VMName "TestVM" -Action RestoreSnapshot