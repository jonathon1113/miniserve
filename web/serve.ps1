# =====================================================================
#  miniserve launcher (PowerShell)
#
#  Reads config.txt, builds the miniserve command line, deploys the
#  custom home page, rotates the log and runs the server.
#
#  Kept in PowerShell on purpose: batch files are notoriously fragile
#  with quotes, parentheses and delayed expansion. Arrays + proper
#  string handling remove an entire class of bugs.
# =====================================================================

# NOTE: $ErrorActionPreference must stay "Continue" while a native command
# runs - miniserve writes normal log lines to stderr, and with "Stop"
# PowerShell would treat them as terminating errors and kill the server.
$ErrorActionPreference = "Continue"
$BaseDir    = Split-Path -Parent $PSScriptRoot
$ConfigFile = Join-Path $BaseDir "config.txt"
$MessagesFile = Join-Path $BaseDir "messages.txt"
$WebDir     = $PSScriptRoot
$HomeTpl    = Join-Path $WebDir "home.html"
$DeployScript = Join-Path $WebDir "deploy.ps1"
$GuardScript  = Join-Path $WebDir "guard-upload.ps1"

# ---------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------
$cfg = @{
    PORT             = "8080"
    SERVE_DIR        = "."
    UPLOAD_DIR       = ""
    MKDIR            = "0"
    ON_DUPLICATE     = "rename"
    MEDIA_TYPE       = ""
    HIDDEN           = "0"
    VERBOSE          = "0"
    OPEN_BROWSER     = "1"
    DISABLE_INDEXING = "0"
    INDEX            = ""
    PRETTY_URLS      = "0"
    SPA              = "0"
    SORTING_METHOD   = "name"
    SORTING_ORDER    = "desc"
    AUTH             = ""
    AUTH_FILE        = ""
    ROUTE_PREFIX     = ""
    ENABLE_WEBDAV    = "0"
    INDEX_REFRESH    = "0"
    ALLOW_DELETE     = "0"
    RM_DIR           = ""
    COMPRESS         = "0"
    RECURSIVE_INDEX  = "0"
    GUARD_UPLOAD     = "1"
    COLOR_SCHEME     = "squirrel"
    COLOR_SCHEME_DARK = "archlinux"
    ENABLE_TAR       = "0"
    ENABLE_TAR_GZ    = "1"
    ENABLE_ZIP       = "1"
    LOG_TO_FILE      = "0"
    LOG_FILE         = "logs\miniserve.log"
    LOG_MAX_MB       = "10"
}

# ---------------------------------------------------------------------
# Read config.txt (UTF-8, '#' and ';' start a comment)
# ---------------------------------------------------------------------
function Read-Config([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "[WARN] config.txt not found, using defaults."
        return
    }
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        $t = $line.Trim()
        if ($t -eq "" -or $t.StartsWith("#") -or $t.StartsWith(";")) { continue }
        $i = $t.IndexOf("=")
        if ($i -lt 1) { continue }
        $key = $t.Substring(0, $i).Trim().ToUpperInvariant()
        $val = $t.Substring($i + 1).Trim()
        if ($cfg.ContainsKey($key)) { $cfg[$key] = $val }
    }
}
Read-Config $ConfigFile

function Is-True([string]$v) { return ($v -eq "1" -or $v -eq "true" -or $v -eq "yes" -or $v -eq "on") }

# ---------------------------------------------------------------------
# Locate the miniserve binary
# ---------------------------------------------------------------------
$exe = Get-ChildItem -LiteralPath $BaseDir -Filter "miniserve*.exe" -File -ErrorAction SilentlyContinue |
       Select-Object -First 1
if (-not $exe) {
    Write-Host "[ERROR] miniserve*.exe not found in $BaseDir"
    exit 1
}
$ExePath = $exe.FullName

# ---------------------------------------------------------------------
# Resolve the served directory
# ---------------------------------------------------------------------
$serveDir = $cfg["SERVE_DIR"]
if (-not (Test-Path -LiteralPath $serveDir)) {
    $serveDir = Join-Path $BaseDir $cfg["SERVE_DIR"]
}
if (-not (Test-Path -LiteralPath $serveDir)) {
    Write-Host "[ERROR] Serve directory does not exist: $serveDir"
    exit 1
}
$serveDir = (Resolve-Path -LiteralPath $serveDir).Path

# ---------------------------------------------------------------------
# Build the argument list
# ---------------------------------------------------------------------
$argsList = New-Object System.Collections.Generic.List[string]
function Add-Arg([string]$a) { $argsList.Add($a) }

Add-Arg "--port";              Add-Arg $cfg["PORT"]
Add-Arg "--default-sorting-method"; Add-Arg $cfg["SORTING_METHOD"]
Add-Arg "--default-sorting-order";  Add-Arg $cfg["SORTING_ORDER"]
Add-Arg "--on-duplicate-files";     Add-Arg $cfg["ON_DUPLICATE"]
Add-Arg "--color-scheme";           Add-Arg $cfg["COLOR_SCHEME"]
Add-Arg "--color-scheme-dark";      Add-Arg $cfg["COLOR_SCHEME_DARK"]

if ($cfg["UPLOAD_DIR"]) { Add-Arg "--upload-files"; Add-Arg $cfg["UPLOAD_DIR"] }
else                    { Add-Arg "--upload-files" }

if (Is-True $cfg["MKDIR"])             { Add-Arg "--mkdir" }
if (Is-True $cfg["ENABLE_WEBDAV"])     { Add-Arg "--enable-webdav" }
if (Is-True $cfg["COMPRESS"])          { Add-Arg "--compress-response" }
if (Is-True $cfg["ENABLE_TAR"])        { Add-Arg "--enable-tar" }
if (Is-True $cfg["ENABLE_TAR_GZ"])     { Add-Arg "--enable-tar-gz" }
if (Is-True $cfg["ENABLE_ZIP"])        { Add-Arg "--enable-zip" }
if (Is-True $cfg["HIDDEN"])            { Add-Arg "--hidden" }
if (Is-True $cfg["VERBOSE"])           { Add-Arg "--verbose" }
if (Is-True $cfg["DISABLE_INDEXING"])  { Add-Arg "--disable-indexing" }
if (Is-True $cfg["PRETTY_URLS"])       { Add-Arg "--pretty-urls" }
if (Is-True $cfg["SPA"])               { Add-Arg "--spa" }
if ($cfg["INDEX"])        { Add-Arg "--index";        Add-Arg $cfg["INDEX"] }
if ($cfg["MEDIA_TYPE"])   { Add-Arg "--media-type";  Add-Arg $cfg["MEDIA_TYPE"] }

# Route prefix: normalise to "/prefix" (leading slash, no trailing slash)
$routePrefix = ""
if ($cfg["ROUTE_PREFIX"]) {
    $routePrefix = $cfg["ROUTE_PREFIX"].Trim()
    $routePrefix = $routePrefix.TrimEnd("/")
    if (-not $routePrefix.StartsWith("/")) { $routePrefix = "/" + $routePrefix }
    if ($routePrefix -eq "/") { $routePrefix = "" }
    if ($routePrefix) { Add-Arg "--route-prefix"; Add-Arg $routePrefix }
}

# Authentication
if ($cfg["AUTH_FILE"])      { Add-Arg "--auth-file"; Add-Arg $cfg["AUTH_FILE"] }
elseif ($cfg["AUTH"])       { Add-Arg "--auth";      Add-Arg $cfg["AUTH"] }

# Deletion scope. NOTE: miniserve also allows deleting the allowed dir
# itself, so we never fall back to "delete anywhere".
$rmDir = $cfg["RM_DIR"]
if (-not $rmDir) { $rmDir = $cfg["UPLOAD_DIR"] }
$rmDir = $rmDir.Trim().TrimStart("/", "\")
if (Is-True $cfg["ALLOW_DELETE"]) {
    if ($rmDir) { Add-Arg "--rm-files"; Add-Arg $rmDir }
    else { Write-Host "[WARN] ALLOW_DELETE=1 but no RM_DIR/UPLOAD_DIR - deletion disabled to stay safe." }
}

# favicon route (miniserve serves its own icon under the route prefix)
$faviconRoute = "/__miniserve_internal/favicon.svg"
if ($routePrefix) { $faviconRoute = "$routePrefix$faviconRoute" }

# ---------------------------------------------------------------------
# Deploy the custom home page
# ---------------------------------------------------------------------
if ($cfg["INDEX"]) {
    # The custom home page lists files via read-only WebDAV -> make sure it is on
    if (-not (Is-True $cfg["ENABLE_WEBDAV"])) {
        $cfg["ENABLE_WEBDAV"] = "1"
        Add-Arg "--enable-webdav"
        Write-Host "[INFO] ENABLE_WEBDAV turned on automatically - it is needed by the custom home page."
    }
    if (Test-Path -LiteralPath $DeployScript) {
        $overwrite = if (Is-True $cfg["INDEX_REFRESH"]) { 1 } else { 0 }
        $archiveOk = if (Is-True $cfg["RECURSIVE_INDEX"]) { 0 } else { 1 }
        $dArgs = @{
            Root         = $serveDir
            Template     = $HomeTpl
            Overwrite    = $overwrite
            UploadPath   = $cfg["UPLOAD_DIR"]
            AllowDelete  = $cfg["ALLOW_DELETE"]
            RmPrefix     = $rmDir
            RoutePrefix  = $routePrefix
            ArchiveOk    = $archiveOk
            FaviconRoute = $faviconRoute
        }
        if (-not (Is-True $cfg["RECURSIVE_INDEX"])) { $dArgs["RootOnly"] = $true }
        & $DeployScript @dArgs
    } else {
        Write-Host "[WARN] web\deploy.ps1 not found, skipped index deployment."
    }
}

# ---------------------------------------------------------------------
# Create the upload folder if needed
# ---------------------------------------------------------------------
$upPath = ""
if ($cfg["UPLOAD_DIR"]) {
    $upPath = Join-Path $serveDir $cfg["UPLOAD_DIR"].TrimStart("/", "\")
    if (-not (Test-Path -LiteralPath $upPath)) {
        New-Item -ItemType Directory -Path $upPath -Force | Out-Null
        Write-Host "[INFO] Upload folder created: $upPath"
    }
}

# ---------------------------------------------------------------------
# Log file + rotation
# ---------------------------------------------------------------------
$logAbs = $null
if (Is-True $cfg["LOG_TO_FILE"]) {
    $logAbs = if ([System.IO.Path]::IsPathRooted($cfg["LOG_FILE"])) {
        $cfg["LOG_FILE"]
    } else {
        Join-Path $BaseDir $cfg["LOG_FILE"]
    }
    $logDir = Split-Path -Parent $logAbs
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    # Rotation: keep the previous file as .1 (and .2) when it gets too big
    $maxMb = 10
    if ($cfg["LOG_MAX_MB"] -match '^\d+$') { $maxMb = [int]$cfg["LOG_MAX_MB"] }
    if ($maxMb -gt 0 -and (Test-Path -LiteralPath $logAbs)) {
        $size = (Get-Item -LiteralPath $logAbs).Length
        if ($size -gt ($maxMb * 1MB)) {
            if (Test-Path -LiteralPath "$logAbs.2") { Remove-Item -LiteralPath "$logAbs.2" -Force }
            if (Test-Path -LiteralPath "$logAbs.1") { Move-Item -LiteralPath "$logAbs.1" -Destination "$logAbs.2" -Force }
            Move-Item -LiteralPath $logAbs -Destination "$logAbs.1" -Force
            Write-Host "[INFO] Log rotated (exceeded $maxMb MB): $logAbs.1"
        }
    }
}

# ---------------------------------------------------------------------
# Show the info banner (template in messages.txt)
# ---------------------------------------------------------------------
$uploadDisplay = if ($cfg["UPLOAD_DIR"]) { $cfg["UPLOAD_DIR"] } else { "(anywhere)" }
$authDisplay   = if ($cfg["AUTH_FILE"]) { $cfg["AUTH_FILE"] } elseif ($cfg["AUTH"]) { $cfg["AUTH"] } else { "(none)" }
$logDisplay    = if ($logAbs) { $cfg["LOG_FILE"] } else { "(disabled)" }
$deleteDisplay = if (Is-True $cfg["ALLOW_DELETE"]) { if ($rmDir) { $rmDir } else { "(anywhere)" } } else { "(disabled)" }

$vars = @{
    "{SERVE_DIR}"   = $serveDir
    "{UPLOAD_DIR}"  = $uploadDisplay
    "{PORT}"        = $cfg["PORT"]
    "{ROUTE_PREFIX}" = $routePrefix
    "{AUTH}"        = $authDisplay
    "{LOG}"         = $logDisplay
    "{DELETE}"      = $deleteDisplay
}

Write-Host ""
if (Test-Path -LiteralPath $MessagesFile) {
    foreach ($line in [System.IO.File]::ReadAllLines($MessagesFile, [System.Text.Encoding]::UTF8)) {
        $out = $line
        foreach ($k in $vars.Keys) { $out = $out.Replace($k, $vars[$k]) }
        Write-Host $out
    }
} else {
    Write-Host "============================================"
    Write-Host " miniserve is starting"
    Write-Host " Serve dir  : $serveDir"
    Write-Host " Upload dir : $uploadDisplay"
    Write-Host " URL        : http://localhost:$($cfg["PORT"])$routePrefix/"
    Write-Host " Uploads    : enabled"
    Write-Host " Auth       : $authDisplay"
    Write-Host "============================================"
}
Write-Host ""

if (Is-True $cfg["OPEN_BROWSER"]) {
    Start-Process ("http://localhost:{0}{1}/" -f $cfg["PORT"], $routePrefix)
}

# ---------------------------------------------------------------------
# Upload folder watchdog
# ---------------------------------------------------------------------
if ((Is-True $cfg["GUARD_UPLOAD"]) -and $upPath -and (Test-Path -LiteralPath $GuardScript)) {
    $guardLog = Join-Path $BaseDir "logs\guard.log"
    if ($logAbs) { $guardLog = Join-Path (Split-Path -Parent $logAbs) "guard.log" }
    $guardExe = "`"$ExePath`""
    $guardArgs = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "`"$GuardScript`"",
        "-UploadDir", "`"$upPath`"",
        "-ExePath", $guardExe,
        "-LogFile", "`"$guardLog`""
    )
    Start-Process -FilePath "powershell" -WindowStyle Hidden -ArgumentList $guardArgs
    Write-Host "[INFO] Upload dir watchdog started - it will auto-recreate the upload folder."
}

# ---------------------------------------------------------------------
# Run the server
# ---------------------------------------------------------------------
$fullArgs = $argsList.ToArray() + @($serveDir)

Write-Host ""
if ($logAbs) {
    Write-Host "==== start $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====" | Out-File -FilePath $logAbs -Append -Encoding utf8
    Write-Host "[INFO] Log file: $logAbs"
    # Stream to console AND to the log file (UTF-8, no BOM).
    $writer = New-Object System.IO.StreamWriter($logAbs, $true, (New-Object System.Text.UTF8Encoding($false)))
    try {
        & $ExePath @fullArgs 2>&1 | ForEach-Object {
            $line = $_.ToString()
            Write-Host $line
            try { $writer.WriteLine($line); $writer.Flush() } catch { }
        }
    } finally {
        $writer.Close()
    }} else {
    & $ExePath @fullArgs
}

Write-Host ""
Write-Host "Server stopped."
exit 0
