# API Reference

## Main Script: Upgrade-VMTools-NoReboot.ps1

### Synopsis
Performs conditional VMware Tools upgrade without requiring VM reboot.

### Syntax
```powershell
.\Upgrade-VMTools-NoReboot.ps1 
    [-vCenter <String>] 
    [-VMName <String>] 
    [-Credential <PSCredential>]
    [-WhatIf]
    [-Verbose]
```

### Parameters

#### -vCenter
**Type:** String  
**Required:** No (prompted if not provided)  
**Description:** vCenter Server FQDN or IP address

```powershell
-vCenter "vcenter.example.com"
```

#### -VMName
**Type:** String  
**Required:** No (prompted if not provided)  
**Description:** Target virtual machine name

```powershell
-VMName "VM-001"
```

#### -Credential
**Type:** PSCredential  
**Required:** No (prompted if not provided)  
**Description:** vCenter authentication credentials

```powershell
$cred = Get-Credential
-Credential $cred
```

#### -WhatIf
**Type:** Switch  
**Required:** No  
**Description:** Shows what would happen without making changes

```powershell
-WhatIf
```

#### -Verbose
**Type:** Switch  
**Required:** No  
**Description:** Provides detailed output during execution

```powershell
-Verbose
```

### Return Values

#### Success (Exit Code 0)
- VMware Tools upgraded successfully
- No reboot required
- VM remains powered on

#### Failure (Exit Code 1)
- Upgrade conditions not met
- Connection failure
- VM not found
- Tools already current

### Examples

#### Basic Usage
```powershell
.\Upgrade-VMTools-NoReboot.ps1
```

#### With Parameters
```powershell
.\Upgrade-VMTools-NoReboot.ps1 -vCenter "vcenter.lab.local" -VMName "TestVM"
```

#### With Credentials
```powershell
$cred = Get-Credential
.\Upgrade-VMTools-NoReboot.ps1 -vCenter "vcenter.lab.local" -VMName "TestVM" -Credential $cred
```

#### Dry Run
```powershell
.\Upgrade-VMTools-NoReboot.ps1 -WhatIf -Verbose
```

## Helper Functions

### Test-NoRebootCompatibility.ps1

#### Synopsis
Tests VM compatibility for no-reboot VMware Tools upgrade.

#### Syntax
```powershell
.\Test-NoRebootCompatibility.ps1 -VMName <String> [-Detailed]
```

#### Parameters
- **-VMName**: Target VM name
- **-Detailed**: Provides comprehensive compatibility report

#### Return Values
- **True**: VM is compatible for no-reboot upgrade
- **False**: VM requires reboot for upgrade

### Get-VMToolsStatus.ps1

#### Synopsis
Retrieves detailed VMware Tools status information.

#### Syntax
```powershell
.\Get-VMToolsStatus.ps1 -VMName <String>
```

#### Output Object Properties
```powershell
[PSCustomObject]@{
    VMName = [String]
    ToolsVersion = [String]
    ToolsVersionStatus2 = [String]
    ToolsStatus = [String]
    ToolsRunningStatus = [String]
    UpgradeAvailable = [Boolean]
    NoRebootSupported = [Boolean]
}
```

## VMware Tools Status Values

### ToolsVersionStatus2
- `guestToolsCurrent`: Tools are up to date
- `guestToolsNeedUpgrade`: Upgrade available
- `guestToolsSupportedOld`: Supported but old version
- `guestToolsNotInstalled`: Tools not installed
- `guestToolsUnmanaged`: Unmanaged tools installation

### ToolsStatus
- `guestToolsCurrent`: Current version
- `guestToolsSupportedOld`: Old but supported
- `toolsNotInstalled`: Not installed
- `toolsNotRunning`: Installed but not running

### ToolsRunningStatus
- `guestToolsRunning`: Tools service running
- `guestToolsNotRunning`: Tools service not running

## Error Codes

| Code | Description | Resolution |
|------|-------------|------------|
| 0    | Success | No action needed |
| 1    | General failure | Check error message |
| 2    | VM not found | Verify VM name |
| 3    | Connection failed | Check vCenter connectivity |
| 4    | Tools not running | Start VMware Tools service |
| 5    | Upgrade not needed | Tools already current |
| 6    | Reboot required | Use standard upgrade method |

## PowerCLI Cmdlets Used

### Core Cmdlets
- `Connect-VIServer`: vCenter connection
- `Get-VM`: VM object retrieval
- `Update-Tools`: Tools upgrade execution
- `Disconnect-VIServer`: Connection cleanup

### Status Cmdlets
- `Get-VMGuest`: Guest OS information
- `Get-View`: vSphere API access

## Prerequisites

### PowerShell Modules
```powershell
# Required modules
Import-Module VMware.PowerCLI
Import-Module VMware.VimAutomation.Core
```

### Permissions Required
- Virtual machine configuration
- Virtual machine interaction
- Resource pool access (if applicable)

### Network Requirements
- HTTPS access to vCenter (port 443)
- Network connectivity to target VMs
- DNS resolution for vCenter FQDN

## Best Practices

### Error Handling
```powershell
try {
    $result = .\Upgrade-VMTools-NoReboot.ps1 -vCenter $vCenter -VMName $vmName
    Write-Host "Upgrade successful: $result"
} catch {
    Write-Error "Upgrade failed: $($_.Exception.Message)"
}
```

### Logging
```powershell
# Enable transcript logging
Start-Transcript -Path "C:\Logs\VMTools-Upgrade-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
.\Upgrade-VMTools-NoReboot.ps1 -Verbose
Stop-Transcript
```

### Batch Processing
```powershell
$vms = @("VM-001", "VM-002", "VM-003")
foreach ($vm in $vms) {
    try {
        .\Upgrade-VMTools-NoReboot.ps1 -vCenter $vCenter -VMName $vm
        Write-Host "✅ $vm upgraded successfully"
    } catch {
        Write-Warning "❌ $vm upgrade failed: $($_.Exception.Message)"
    }
}
```

## Troubleshooting

### Common Issues
1. **PowerCLI not loaded**: Import VMware.PowerCLI module
2. **Connection timeout**: Check network connectivity
3. **Permission denied**: Verify vCenter permissions
4. **VM not found**: Check VM name spelling
5. **Tools not running**: Start VMware Tools service

### Debug Mode
```powershell
$DebugPreference = "Continue"
.\Upgrade-VMTools-NoReboot.ps1 -Debug -Verbose
```