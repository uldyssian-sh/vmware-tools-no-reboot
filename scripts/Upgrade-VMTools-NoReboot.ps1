<#
.SYNOPSIS
    VMware Tools Conditional Upgrade (No Reboot) PowerCLI Script

.DESCRIPTION
    Upgrade VMware Tools on a single VM only if:
    - VMware Tools are running
    - Upgrade is needed (NeedUpgrade or SupportedOld)
    - Tools are installed
    Upgrade runs silently and does NOT trigger a guest OS reboot.

.PARAMETER vCenter
    vCenter Server FQDN or IP address (optional - will prompt if not provided)

.PARAMETER VMName
    VM name to upgrade (optional - will prompt if not provided)

.PARAMETER Credential
    vCenter credentials (optional - will prompt if not provided)

.EXAMPLE
    .\Upgrade-VMTools-NoReboot.ps1

.EXAMPLE
    .\Upgrade-VMTools-NoReboot.ps1 -vCenter "vcenter.example.com" -VMName "VM-001"

.NOTES
    Author: uldyssian-sh
    Version: 1.0.0
    Requires: PowerCLI, vCenter administrative privileges
    Based on: Medium article methodology for no-reboot VMware Tools upgrades

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
    [PSCredential]$Credential
)

Clear-Host
Write-Information "=== VMware Tools Conditional Upgrade (No Reboot) ===" -InformationAction Continue
Write-Information "" -InformationAction Continue

# --- Check if PowerCLI is available (no slow module loading here) ---
if (-not (Get-Command Connect-VIServer -ErrorAction SilentlyContinue)) {
    Write-Error "Connect-VIServer not found. Please run this script in a VMware PowerCLI console or load the PowerCLI module first (Import-Module VMware.PowerCLI)."
    return
}

# --- (Optional) PowerCLI settings: CEIP off, ignore TLS warnings ---
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

# --- vCenter input ---
if (-not $vCenter) {
    $vCenter = (Read-Host "Enter vCenter FQDN or IP").Trim()
}

if ([string]::IsNullOrWhiteSpace($vCenter)) {
    Write-Error "No vCenter was entered. Exiting."
    return
}

Write-Information "" -InformationAction Continue
Write-Information "Login to vCenter..." -InformationAction Continue

if (-not $Credential) {
    $Credential = Get-Credential -Message "Enter vCenter credentials"
}

try {
    Connect-VIServer -Server $vCenter -Credential $Credential -ErrorAction Stop | Out-Null
    Write-Information "Connected to $vCenter" -InformationAction Continue
}
catch {
    Write-Error "Failed to connect to vCenter: $($_.Exception.Message)"
    return
}

# --- VM selection ---
Write-Information "" -InformationAction Continue
if (-not $VMName) {
    $VMName = (Read-Host "Enter the VM NAME for VMware Tools upgrade").Trim()
}

if ([string]::IsNullOrWhiteSpace($VMName)) {
    Write-Error "No VM name was entered. Exiting."
    Disconnect-VIServer -Confirm:$false | Out-Null
    return
}

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Error "VM '$VMName' not found!"
    Disconnect-VIServer -Confirm:$false | Out-Null
    return
}

Write-Information "VM found: $($vm.Name)" -InformationAction Continue

# --- Current VMware Tools state ---
$guest = $vm.ExtensionData.Guest
$currentVersion       = $guest.ToolsVersion
$currentStatus2       = $guest.ToolsVersionStatus2    # e.g. guestToolsCurrent, guestToolsNeedUpgrade, guestToolsSupportedOld
$currentToolsStatus   = $guest.ToolsStatus            # e.g. guestToolsSupportedOld, guestToolsCurrent
$currentRunningStatus = $guest.ToolsRunningStatus     # e.g. guestToolsRunning

Write-Information "" -InformationAction Continue
Write-Information "=== Current VMware Tools State ===" -InformationAction Continue
[PSCustomObject]@{
    VMName              = $vm.Name
    ToolsVersion        = $currentVersion
    ToolsVersionStatus2 = $currentStatus2
    ToolsStatus         = $currentToolsStatus
    ToolsRunningStatus  = $currentRunningStatus
} | Format-Table -AutoSize

# --- Validate conditions ---
Write-Information "" -InformationAction Continue
Write-Information "Checking upgrade conditions..." -InformationAction Continue
$canRun = $true

# Condition 1: Tools must be running
if ($currentRunningStatus -ne "guestToolsRunning") {
    Write-Warning "❌ VMware Tools are not running (ToolsRunningStatus = $currentRunningStatus)."
    $canRun = $false
}

# Condition 2: Upgrade must be needed (NeedUpgrade or SupportedOld)
$upgradeNeeded = $false
$upgradeStates = @("guestToolsNeedUpgrade", "guestToolsSupportedOld")
if ($currentStatus2 -in $upgradeStates -or $currentToolsStatus -in $upgradeStates) {
    $upgradeNeeded = $true
}

if (-not $upgradeNeeded) {
    Write-Warning "❌ VMware Tools are not in an upgradable state (ToolsVersionStatus2 = $currentStatus2, ToolsStatus = $currentToolsStatus)."
    $canRun = $false
}

# Condition 3: Tools must be installed
if ($currentStatus2 -eq "guestToolsNotInstalled" -or $currentToolsStatus -eq "toolsNotInstalled") {
    Write-Warning "❌ VMware Tools are not installed on this VM."
    $canRun = $false
}

if (-not $canRun) {
    Write-Information "" -InformationAction Continue
    Write-Information "Upgrade conditions NOT met. No action taken." -InformationAction Continue
    Disconnect-VIServer -Confirm:$false | Out-Null
    return
}

Write-Information "" -InformationAction Continue
Write-Information "✔ All conditions OK. Proceeding with VMware Tools upgrade (No Reboot)..." -InformationAction Continue

# --- Upgrade VMware Tools (No Reboot) ---
Write-Information "" -InformationAction Continue
Write-Information "Starting VMware Tools upgrade..." -InformationAction Continue

try {
    Update-Tools -VM $vm -NoReboot -ErrorAction Stop | Out-Null
    Write-Information "Update-Tools command executed." -InformationAction Continue
}
catch {
    Write-Error "Update-Tools failed: $($_.Exception.Message)"
    Disconnect-VIServer -Confirm:$false | Out-Null
    return
}

Write-Information "" -InformationAction Continue
Write-Information "Waiting 10 seconds for VMware Tools status to refresh..." -InformationAction Continue
Start-Sleep -Seconds 10   # adjust if needed

# --- Refresh state after upgrade ---
$vm    = Get-VM -Name $vm.Name
$guest = $vm.ExtensionData.Guest
$newVersion       = $guest.ToolsVersion
$newStatus2       = $guest.ToolsVersionStatus2
$newToolsStatus   = $guest.ToolsStatus
$newRunningStatus = $guest.ToolsRunningStatus

Write-Information "" -InformationAction Continue
Write-Information "=== VMware Tools State AFTER Upgrade ===" -InformationAction Continue
[PSCustomObject]@{
    VMName              = $vm.Name
    OldVersion          = $currentVersion
    NewVersion          = $newVersion
    ToolsVersionStatus2 = $newStatus2
    ToolsStatus         = $newToolsStatus
    ToolsRunningStatus  = $newRunningStatus
} | Format-Table -AutoSize

# --- Success evaluation ---
Write-Information "" -InformationAction Continue
$success = $false
if ($newVersion -and $newVersion -ne $currentVersion -and
    $newRunningStatus -eq "guestToolsRunning" -and
    $newStatus2 -ne "guestToolsNeedUpgrade" -and
    $newStatus2 -ne "guestToolsNotInstalled") {
    $success = $true
}

if ($success) {
    Write-Information "✔ VMware Tools upgrade SUCCESSFUL (no reboot triggered by script)." -InformationAction Continue
}
else {
    Write-Information "❌ VMware Tools upgrade might have FAILED or is INCOMPLETE." -InformationAction Continue
    Write-Information "   Check vSphere client and VM logs for more details." -InformationAction Continue
}

# --- Disconnect ---
Write-Information "" -InformationAction Continue
Write-Information "Disconnecting from vCenter..." -InformationAction Continue
Disconnect-VIServer -Confirm:$false | Out-Null
Write-Information "Disconnected." -InformationAction Continue