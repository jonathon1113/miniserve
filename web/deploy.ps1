param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$Template,
    [int]$Overwrite = 0,
    [string]$UploadPath = "",
    [string]$AllowDelete = "0",
    [string]$RmPrefix = "",
    [string]$RoutePrefix = "",
    [switch]$RootOnly,
    [int]$AutoGitIgnore = 1,
    [int]$ArchiveOk = 1,
    [string]$FaviconRoute = "/__miniserve_internal/favicon.svg"
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $Root)) { Write-Output "ERROR: root not found: $Root"; exit 1 }
if (-not (Test-Path -LiteralPath $Template)) { Write-Output "ERROR: template not found: $Template"; exit 1 }

$templateText = [System.IO.File]::ReadAllText($Template, [System.Text.Encoding]::UTF8)

function Get-Injected([string]$text) {
    $t = $text.Replace('__UPLOAD_PATH__', $UploadPath)
    $t = $t.Replace('__ALLOW_DELETE__', $AllowDelete)
    $t = $t.Replace('__RM_PREFIX__', $RmPrefix)
    $t = $t.Replace('__ROUTE_PREFIX__', $RoutePrefix)
    $t = $t.Replace('__ARCHIVE_OK__', $ArchiveOk)
    $t = $t.Replace('__FAVICON_ROUTE__', $FaviconRoute)
    $homeUrl = "/"
    if ($RoutePrefix) {
        $homeUrl = $RoutePrefix.TrimEnd("/")
        if (-not $homeUrl.StartsWith("/")) { $homeUrl = "/" + $homeUrl }
        $homeUrl = $homeUrl + "/"
    }
    $t = $t.Replace('__HOME_URL__', $homeUrl)
    return $t
}

# Files we generated ourselves carry this marker; they are always refreshed so
# that config changes (upload dir, delete permission, ...) take effect.
$marker = '<!-- miniserve-generated'

$created = 0
$kept = 0
$refreshed = 0

# Directories we never touch (VCS metadata, dependency trees, etc.)
$excluded = @('.git', '.svn', '.hg', 'node_modules', '__pycache__', '.venv', 'venv',
               'target', 'dist', 'build', '.idea', '.vscode', '.next', '.cache')

function Get-Excluded([string]$name) {
    $n = $name.ToLower()
    foreach ($e in $excluded) { if ($n -eq $e) { return $true } }
    if ($name.StartsWith('.')) { return $true }
    return $false
}

# Root folder first, then every sub folder (so the style follows you into any level).
# NOTE: -Recurse flattens the whole tree, so we must filter on the RELATIVE path,
# otherwise excluded folders would still contribute their descendants.
$rootItem = Get-Item -LiteralPath $Root
$rootFull = $rootItem.FullName.TrimEnd('\')
$dirs = @($rootItem)
if (-not $RootOnly) {
    $dirs += Get-ChildItem -LiteralPath $Root -Directory -Recurse -Force -ErrorAction SilentlyContinue |
             Where-Object {
                 $rel = $_.FullName.Substring($rootFull.Length).TrimStart('\')
                 $bad = $false
                 foreach ($p in ($rel -split '\\')) { if (Get-Excluded $p) { $bad = $true; break } }
                 -not $bad
             }
}

foreach ($dir in $dirs) {
    $target = Join-Path $dir.FullName "index.html"
    if (Test-Path -LiteralPath $target) {
        $existing = [System.IO.File]::ReadAllText($target)
        # Ours = has the marker, or still contains un-injected placeholders (older version)
        $isOurs = $existing.Contains($marker) -or $existing.Contains('__UPLOAD_PATH__')
        if (($Overwrite -ne 1) -and (-not $isOurs)) {
            $kept++          # user's own file -> never touch it
            continue
        }
        # File is ours: regenerate from the template so template updates take effect.
        [System.IO.File]::WriteAllText($target, (Get-Injected $templateText), $utf8NoBom)
        $refreshed++
        continue
    }
    try {
        [System.IO.File]::WriteAllText($target, (Get-Injected $templateText), $utf8NoBom)
        $created++
    } catch {
        Write-Output ("SKIP: " + $target)
    }
}

Write-Output ("Index pages created: {0}, refreshed: {1}, kept: {2}" -f $created, $refreshed, $kept)

# ---------------------------------------------------------------------
# RootOnly mode: remove stale generated index.html from sub folders.
# Only files carrying our marker are touched, user files stay intact.
# ---------------------------------------------------------------------
if ($RootOnly) {
    $removed = 0
    $stale = Get-ChildItem -LiteralPath $Root -Directory -Recurse -Force -ErrorAction SilentlyContinue |
             Where-Object {
                 $rel = $_.FullName.Substring($rootFull.Length).TrimStart('')
                 $bad = $false
                 foreach ($p in ($rel -split '\\')) { if (Get-Excluded $p) { $bad = $true; break } }
                 -not $bad
             }
    foreach ($dir in $stale) {
        $target = Join-Path $dir.FullName "index.html"
        if (-not (Test-Path -LiteralPath $target)) { continue }
        try {
            $content = [System.IO.File]::ReadAllText($target)
            if ($content.Contains($marker)) {
                Remove-Item -LiteralPath $target -Force
                $removed++
            }
        } catch { }
    }
    if ($removed -gt 0) {
        Write-Output ("Removed {0} stale index.html from sub folders (RECURSIVE_INDEX=0)" -f $removed)
    }
}

# If the shared folder is a git repo, keep the generated index.html out of commits.
if ($AutoGitIgnore -eq 1) {
    if (Test-Path -LiteralPath (Join-Path $rootFull ".git")) {
        $gi = Join-Path $rootFull ".gitignore"
        $lines = @()
        if (Test-Path -LiteralPath $gi) {
            $lines = [System.IO.File]::ReadAllLines($gi)
        }
        if ($lines -notcontains "index.html") {
            $lines += "index.html"
            [System.IO.File]::WriteAllLines($gi, $lines, $utf8NoBom)
            Write-Output "Added 'index.html' to .gitignore"
        }
    }
}

exit 0
