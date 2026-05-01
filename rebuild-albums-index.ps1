param(
    [string]$AlbumsRoot = (Join-Path $PSScriptRoot "albums"),
    [string]$AlbumsIndexPath = (Join-Path $PSScriptRoot "albums\\index.html"),
    [string]$BackupDir = (Join-Path $PSScriptRoot "_trash\\albums-index-backups")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Try-DecodeBase64([string]$value) {
    try {
        $bytes = [System.Convert]::FromBase64String($value)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        return ""
    }
}

function Strip-Tags([string]$value) {
    if (-not $value) { return "" }
    $noTags = [regex]::Replace($value, "<[^>]+>", "")
    return [System.Net.WebUtility]::HtmlDecode($noTags).Trim()
}

function Get-Attr([string]$tag, [string]$name) {
    if (-not $tag) { return "" }
    if (-not $name) { return "" }
    $escapedName = [regex]::Escape($name)
    $pattern = $escapedName + '\s*=\s*"([^"]*)"'
    $match = [regex]::Match($tag, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        return [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
    }
    return ""
}

function Normalize-PhotoSrc([string]$src) {
    $value = ""
    if ($null -ne $src) { $value = [string]$src }
    if (-not $value) { return "" }
    if ($value.StartsWith("data:image/")) { return "" }
    $value = $value.Trim()
    if (-not $value.StartsWith("/")) { $value = "/$value" }
    return $value
}

function Resolve-LocalPath([string]$src) {
    if (-not $src) { return "" }
    $value = [string]$src
    $value = $value.Trim()
    if ($value.StartsWith("/")) { $value = $value.Substring(1) }
    $value = $value -replace "/", "\\"
    return (Join-Path $PSScriptRoot $value)
}

function Try-GetImageAspectRatio([string]$filePath) {
    if (-not $filePath -or -not (Test-Path -LiteralPath $filePath)) { return $null }
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop | Out-Null
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $ms = [System.IO.MemoryStream]::new([byte[]]$bytes)
        try {
            $img = [System.Drawing.Image]::FromStream($ms)
            try {
                if ($img.Width -le 0 -or $img.Height -le 0) { return $null }
                return ([double]$img.Width) / ([double]$img.Height)
            } finally {
                $img.Dispose()
            }
        } finally {
            $ms.Dispose()
        }
    } catch {
        return $null
    }
}

function Get-AlbumCardData([string]$slug) {
    $albumDir = Join-Path $AlbumsRoot $slug
    $indexPath = Join-Path $albumDir "index.html"
    if (-not (Test-Path -LiteralPath $indexPath)) { return $null }

    $html = Get-Content -LiteralPath $indexPath -Raw
    $titleMatch = [regex]::Match($html, "<h1[^>]*>(.*?)</h1>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $title = if ($titleMatch.Success) { Strip-Tags $titleMatch.Groups[1].Value } else { $slug }

    $imgTags = [regex]::Matches($html, '<img\s+[^>]*>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $thumb = ""
    $bestThumb = ""
    $bestScore = [double]::PositiveInfinity
    $desired = 1.5 # roughly 3:2 for card covers
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $checked = 0

    foreach ($imgTag in $imgTags) {
        $tag = $imgTag.Value
        $encoded = Get-Attr $tag "data-encoded-src"
        if (-not $encoded) { continue }
        $decoded = Try-DecodeBase64 $encoded
        if (-not $decoded) { continue }

        $src = Normalize-PhotoSrc $decoded
        if (-not $src) { continue }
        if ($seen.Contains($src)) { continue }
        [void]$seen.Add($src)

        if (-not $thumb) { $thumb = $src } # fallback: first photo

        $local = Resolve-LocalPath $src
        $ratio = Try-GetImageAspectRatio $local
        if ($null -eq $ratio) { continue }

        # Score: prefer landscape, and aspect ratio close to desired.
        $diff = [Math]::Abs([Math]::Log($ratio / $desired))
        $portraitPenalty = if ($ratio -lt 1.0) { 2.0 } else { 0.0 }
        $score = $diff + $portraitPenalty
        if ($score -lt $bestScore) {
            $bestScore = $score
            $bestThumb = $src
        }

        $checked += 1
        if ($checked -ge 30) { break } # keep it fast per album
    }

    if ($bestThumb) { $thumb = $bestThumb }
    if (-not $thumb) { $thumb = "/images/A7B6644A-5A80-4DDD-BE12-BBC40FE37A35.png" }

    return [pscustomobject]@{
        slug  = $slug
        title = $title
        thumb = $thumb
        href  = "/albums/$slug/"
    }
}

function Replace-GridInnerHtml([string]$html, [string]$innerHtml) {
    $pattern = '(?is)^(.*?)(<div\s+class\s*=\s*"grid"\s*>)(.*?)(</div>\s*</div>\s*<footer\b)(.*)$'
    $m = [regex]::Match($html, $pattern)
    if (-not $m.Success) {
        throw "Kon grid blok niet vinden met verwachte structuur."
    }
    return $m.Groups[1].Value + $m.Groups[2].Value + $innerHtml + $m.Groups[4].Value + $m.Groups[5].Value
}

if (-not (Test-Path -LiteralPath $AlbumsIndexPath)) {
    throw "Niet gevonden: $AlbumsIndexPath"
}

$albums = @(Get-ChildItem -LiteralPath $AlbumsRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
$cards = New-Object System.Collections.Generic.List[object]
foreach ($slug in $albums) {
    $data = Get-AlbumCardData $slug
    if ($data) { $cards.Add($data) }
}

if ($cards.Count -eq 0) {
    throw "Geen albums gevonden om te rebuilden."
}

$cardsHtml = ($cards | Sort-Object title, slug | ForEach-Object {
@"

            <div class="card">
                <a href="$($_.href)"><img src="$($_.thumb)" alt="Something went wrong"></a>
                <a href="$($_.href)"><h2>$([System.Net.WebUtility]::HtmlEncode($_.title))</h2></a>
            </div>

"@
}) -join ""

$html = Get-Content -LiteralPath $AlbumsIndexPath -Raw
$newHtml = Replace-GridInnerHtml -html $html -innerHtml $cardsHtml

if (-not (Test-Path -LiteralPath $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}
$backupPath = Join-Path $BackupDir ("albums-index-{0}.html" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))
Set-Content -LiteralPath $backupPath -Value $html -Encoding UTF8

Set-Content -LiteralPath $AlbumsIndexPath -Value $newHtml -Encoding UTF8

Write-Host ("Rebuilt albums/index.html. Backup: {0}" -f $backupPath) -ForegroundColor Green
