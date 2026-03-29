param()

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$lockFile = Join-Path $projectRoot "album-locks.js"

function Normalize-AlbumRoute {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $route = $Value.Trim().Replace("\", "/")
    $route = $route -replace "^https?://[^/]+/", ""
    $route = $route.Trim("/")

    if ($route.EndsWith("/index.html")) {
        $route = $route.Substring(0, $route.Length - "/index.html".Length)
    }

    if ($route.EndsWith(".html")) {
        $route = $route.Substring(0, $route.Length - ".html".Length)
    }

    if (-not $route.StartsWith("albums/")) {
        $route = "albums/$route"
    }

    return $route.Trim("/")
}

function Get-RandomSalt {
    $bytes = New-Object byte[] 16
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Get-Sha256Hex {
    param([string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        $hash = $sha.ComputeHash($bytes)
        return ($hash | ForEach-Object { $_.ToString("x2") }) -join ""
    } finally {
        $sha.Dispose()
    }
}

$pageFile = Read-Host "Welke albumroute wil je vergrendelen? (bijv. albums/zovoc-jb1-pdk-jb1 of zovoc-jb1-pdk-jb1.html)"
if ([string]::IsNullOrWhiteSpace($pageFile)) {
    Write-Host "Geen paginanaam opgegeven." -ForegroundColor Red
    exit 1
}

$normalizedRoute = Normalize-AlbumRoute $pageFile
if ([string]::IsNullOrWhiteSpace($normalizedRoute)) {
    Write-Host "Geen geldige albumroute opgegeven." -ForegroundColor Red
    exit 1
}

$albumTitle = Read-Host "Welke titel wil je tonen in het ontgrendelscherm? (leeg = route)"
$hint = Read-Host "Welke hint wil je tonen? (optioneel)"
$code = Read-Host "Welke toegangscode wil je instellen?"

if ([string]::IsNullOrWhiteSpace($code)) {
    Write-Host "Geen code opgegeven." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $lockFile)) {
    Write-Host "album-locks.js niet gevonden." -ForegroundColor Red
    exit 1
}

$salt = Get-RandomSalt
$hash = Get-Sha256Hex "${salt}:$code"
$titleValue = if ([string]::IsNullOrWhiteSpace($albumTitle)) { $normalizedRoute } else { $albumTitle }
$hintValue = if ([string]::IsNullOrWhiteSpace($hint)) { "Vraag de code aan mij." } else { $hint }

$entry = "`"$normalizedRoute`": { title: `"$titleValue`", salt: `"$salt`", hash: `"$hash`", hint: `"$hintValue`" },"
$content = Get-Content -Raw -Path $lockFile

$escapedPageFile = [regex]::Escape($normalizedRoute)
$pattern = "(?m)^\s*`"$escapedPageFile`"\s*:\s*\{[^\r\n]*\},?\s*$"

if ([regex]::IsMatch($content, $pattern)) {
    $content = [regex]::Replace($content, $pattern, "    $entry")
} else {
    $content = $content -replace "\};\s*$", "    $entry`r`n};"
}

Set-Content -Path $lockFile -Value $content -NoNewline

Write-Host ""
Write-Host "Lock opgeslagen in album-locks.js" -ForegroundColor Green
Write-Host "Pagina : $normalizedRoute"
Write-Host "Titel  : $titleValue"
Write-Host "Hint   : $hintValue"
