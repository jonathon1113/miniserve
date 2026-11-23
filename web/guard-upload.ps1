param(
    [Parameter(Mandatory=$true)][string]$UploadDir,
    [Parameter(Mandatory=$true)][string]$ExePath,
    [string]$LogFile = "",
    [int]$IntervalMs = 1000,
    [int]$StartTimeoutSec = 120
)

# Guards the upload folder.
#
# miniserve's rm handler allows deleting the allowed-rm dir ITSELF, because
#   rm_path.starts_with(allowed_rm_dir)
# is true for "upload".starts_with("upload").
# If that folder disappears the server stops accepting uploads.
# This watchdog recreates it automatically.

$ErrorActionPreference = "SilentlyContinue"
$seen = $false
$deadline = (Get-Date).AddSeconds($StartTimeoutSec)
$ExeName = [System.IO.Path]::GetFileNameWithoutExtension($ExePath)

function Write-GuardLog([string]$Message) {
    if (-not $LogFile) { return }
    try {
        $dir = Split-Path -Parent $LogFile
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $LogFile -Encoding UTF8 -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
    } catch { }
}

while ($true) {
    $proc = Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -like "$ExeName*" } |
            Select-Object -First 1

    if (-not $proc) {
        if ($seen) {
            Write-GuardLog "miniserve stopped - watchdog exiting."
            exit 0
        }
        if ((Get-Date) -gt $deadline) {
            Write-GuardLog "miniserve never appeared - watchdog exiting."
            exit 0
        }
        Start-Sleep -Milliseconds $IntervalMs
        continue
    }

    $seen = $true

    if (-not (Test-Path -LiteralPath $UploadDir)) {
        try {
            New-Item -ItemType Directory -Path $UploadDir -Force | Out-Null
            Write-GuardLog ("Recreated upload dir: {0}" -f $UploadDir)
        } catch {
            Write-GuardLog ("Failed to recreate upload dir: {0}" -f $UploadDir)
        }
    }

    Start-Sleep -Milliseconds $IntervalMs
}
