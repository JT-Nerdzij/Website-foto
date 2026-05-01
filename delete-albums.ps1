param(
    [string]$AlbumsRoot = (Join-Path $PSScriptRoot "albums"),
    [string]$ImagesRoot = (Join-Path $PSScriptRoot "images"),
    [string]$AlbumsIndexPath = (Join-Path $PSScriptRoot "albums\\index.html"),
    [string]$PortfolioSelectionPath = (Join-Path $PSScriptRoot "portfolio\\selection.json")
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
    if ($value.StartsWith("/")) { $value = $value.Substring(1) }
    $value = $value -replace "\\", "/"
    return "/$value"
}

function Get-AlbumInfo([string]$slug) {
    $albumDir = Join-Path $AlbumsRoot $slug
    $indexPath = Join-Path $albumDir "index.html"
    if (-not (Test-Path -LiteralPath $indexPath)) {
        return $null
    }

    $html = Get-Content -LiteralPath $indexPath -Raw
    $titleMatch = [regex]::Match($html, "<h1[^>]*>(.*?)</h1>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $albumTitle = if ($titleMatch.Success) { Strip-Tags $titleMatch.Groups[1].Value } else { $slug }

    $imgTags = [regex]::Matches($html, '<img\s+[^>]*>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $photoSrcs = New-Object System.Collections.Generic.List[string]
    $imageFolders = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($imgTag in $imgTags) {
        $tag = $imgTag.Value
        $encoded = Get-Attr $tag "data-encoded-src"
        if (-not $encoded) { continue }
        $decoded = Try-DecodeBase64 $encoded
        if (-not $decoded) { continue }

        $normalized = Normalize-PhotoSrc $decoded
        if (-not $normalized) { continue }
        $photoSrcs.Add($normalized)

        $clean = $decoded.TrimStart("/")
        if ($clean -match '^(images)/([^/]+)/') {
            [void]$imageFolders.Add($Matches[2])
        }
    }

    return [pscustomobject]@{
        slug         = $slug
        title        = $albumTitle
        albumDir     = $albumDir
        indexPath    = $indexPath
        photos       = @($photoSrcs)
        photoCount   = $photoSrcs.Count
        imageFolders = @($imageFolders)
    }
}

function Load-Albums() {
    $slugs = @(Get-ChildItem -LiteralPath $AlbumsRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($slug in $slugs) {
        $info = Get-AlbumInfo $slug
        if ($info) { $result.Add($info) }
    }
    return $result.ToArray()
}

function Ensure-Dir([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

function Move-ToTrash([string]$sourcePath, [string]$trashRoot) {
    if (-not $sourcePath) { return $null }
    if (-not (Test-Path -LiteralPath $sourcePath)) { return $null }

    $name = Split-Path -Leaf $sourcePath
    $dest = Join-Path $trashRoot $name
    $i = 1
    while (Test-Path -LiteralPath $dest) {
        $dest = Join-Path $trashRoot ("{0}-{1}" -f $name, $i)
        $i += 1
    }

    Move-Item -LiteralPath $sourcePath -Destination $dest -Force
    return $dest
}

function Remove-AlbumFromAlbumsIndex([string]$slug) {
    $rebuild = Join-Path $PSScriptRoot "rebuild-albums-index.ps1"
    if (Test-Path -LiteralPath $rebuild) {
        try {
            & $rebuild | Out-Null
            return $true
        } catch {
            # fall back
        }
    }

    if (-not (Test-Path -LiteralPath $AlbumsIndexPath)) { return $false }
    $html = Get-Content -LiteralPath $AlbumsIndexPath -Raw
    $pattern = [regex]::Escape("/albums/$slug/")
    $cardPattern = '(?is)<div\s+class\s*=\s*"card"\s*>.*?' + $pattern + '.*?</div>'
    $newHtml = [regex]::Replace($html, $cardPattern, "")
    if ($newHtml -ne $html) {
        Set-Content -LiteralPath $AlbumsIndexPath -Value $newHtml -Encoding UTF8
        return $true
    }
    return $false
}

function Remove-AlbumFromPortfolioSelection([string[]]$photoSrcs) {
    if (-not (Test-Path -LiteralPath $PortfolioSelectionPath)) { return $false }
    $raw = Get-Content -LiteralPath $PortfolioSelectionPath -Raw
    if (-not $raw) { return $false }
    $json = $null
    try { $json = $raw | ConvertFrom-Json -ErrorAction Stop } catch { return $false }
    if ($null -eq $json -or $null -eq $json.items) { return $false }

    $removeSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in @($photoSrcs)) {
        if ($p) { [void]$removeSet.Add([string]$p) }
    }

    $before = @($json.items).Count
    $kept = @($json.items | Where-Object { $_ -and $_.src -and -not $removeSet.Contains([string]$_.src) })
    $after = $kept.Count
    if ($after -eq $before) { return $false }

    $out = @{
        version = 1
        items   = @($kept | ForEach-Object {
            @{
                album      = $_.album
                albumTitle = $_.albumTitle
                src        = $_.src
                alt        = $_.alt
                page       = $_.page
            }
        })
    }
    $outJson = $out | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $PortfolioSelectionPath -Value $outJson -Encoding UTF8
    return $true
}

if (-not (Test-Path -LiteralPath $AlbumsRoot)) {
    throw "AlbumsRoot bestaat niet: $AlbumsRoot"
}

$albums = Load-Albums
if ($albums.Count -eq 0) {
    throw "Geen albums gevonden in: $AlbumsRoot"
}

Write-Host ""
Write-Host "Album delete tool (veilig: verplaatst naar _trash)" -ForegroundColor Cyan
Write-Host ""

$albumsSorted = $albums | Sort-Object title, slug
for ($i = 0; $i -lt $albumsSorted.Count; $i += 1) {
    $idx = $i + 1
    Write-Host ("[{0}] {1}  (slug: {2}, foto's: {3})" -f $idx, $albumsSorted[$i].title, $albumsSorted[$i].slug, $albumsSorted[$i].photoCount)
}

Write-Host ""
$pick = Read-Host "Kies album nummer(s) (bijv. 1 of 1,3) of 'q' om te stoppen"
if (-not $pick -or $pick.Trim().ToLowerInvariant() -eq "q") { return }

$indexes = New-Object System.Collections.Generic.List[int]
foreach ($token in ($pick -split ",")) {
    $t = $token.Trim()
    if (-not $t) { continue }
    if ($t -match '^\d+$') {
        $v = [int]$t
        if ($v -ge 1 -and $v -le $albumsSorted.Count) { $indexes.Add($v) }
    }
}
if ($indexes.Count -eq 0) {
    throw "Geen geldige keuze."
}

$targets = @($indexes | Select-Object -Unique | Sort-Object | ForEach-Object { $albumsSorted[$_ - 1] })

Write-Host ""
Write-Host "Gekozen albums:" -ForegroundColor Yellow
foreach ($a in $targets) {
    Write-Host ("- {0} (slug: {1})" -f $a.title, $a.slug)
}

Write-Host ""
Write-Host "Dit verplaatst o.a.:" -ForegroundColor DarkYellow
Write-Host "- albums/<slug>"
Write-Host "- <slug>.html"
Write-Host "- <slug> (map)"
Write-Host "- images/<map(pen) die in album staan>"
Write-Host "- en haalt het album uit albums/index.html + portfolio/selection.json (als nodig)"

Write-Host ""
$confirm = Read-Host "Type DELETE om door te gaan"
if ($confirm -ne "DELETE") {
    Write-Host "Geannuleerd." -ForegroundColor Yellow
    return
}

$timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$trashRoot = Join-Path $PSScriptRoot ("_trash\\album-delete\\{0}" -f $timestamp)
Ensure-Dir $trashRoot

foreach ($info in $targets) {
    $albumTrash = Join-Path $trashRoot $info.slug
    Ensure-Dir $albumTrash

    $moved = @()
    $moved += Move-ToTrash -sourcePath (Join-Path $AlbumsRoot $info.slug) -trashRoot $albumTrash
    $moved += Move-ToTrash -sourcePath (Join-Path $PSScriptRoot $info.slug) -trashRoot $albumTrash
    $moved += Move-ToTrash -sourcePath (Join-Path $PSScriptRoot ("{0}.html" -f $info.slug)) -trashRoot $albumTrash

    foreach ($folderName in @($info.imageFolders)) {
        if (-not $folderName) { continue }
        $candidate = Join-Path $ImagesRoot $folderName
        $moved += Move-ToTrash -sourcePath $candidate -trashRoot $albumTrash
    }

    $albumsIndexChanged = $false
    try { $albumsIndexChanged = Remove-AlbumFromAlbumsIndex $info.slug } catch { $albumsIndexChanged = $false }

    $portfolioChanged = $false
    try { $portfolioChanged = Remove-AlbumFromPortfolioSelection -photoSrcs @($info.photos) } catch { $portfolioChanged = $false }

    Write-Host ""
    Write-Host ("OK: {0} -> {1}" -f $info.slug, $albumTrash) -ForegroundColor Green
    if ($albumsIndexChanged) { Write-Host " - albums/index.html aangepast" -ForegroundColor DarkGreen }
    if ($portfolioChanged) { Write-Host " - portfolio/selection.json aangepast" -ForegroundColor DarkGreen }
}

Write-Host ""
Write-Host ("Klaar. Trash: {0}" -f $trashRoot) -ForegroundColor Cyan
