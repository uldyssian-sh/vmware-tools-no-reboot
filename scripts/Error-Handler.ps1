# Enhanced Error Handling Module
function Handle-UpgradeError {
    param([string]$ErrorMessage, [string]$VMName)
    Write-Host "Error in $VMName : $ErrorMessage" -ForegroundColor Red
}