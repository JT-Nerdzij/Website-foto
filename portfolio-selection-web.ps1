param(
    [string]$AlbumsRoot = (Join-Path $PSScriptRoot "albums"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "portfolio\\selection.json"),
    [int]$PageSize = 100,
    [int]$Port = 8765
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ImageFilePath([string]$src) {
    if ($null -eq $src) { return "" }
    $value = [string]$src
    if (-not $value) { return "" }
    if ($value.StartsWith("/")) { $value = $value.Substring(1) }
    $value = $value -replace "/", "\\"
    return (Join-Path $PSScriptRoot $value)
}

function Normalize-AlbumPath([string]$slug) {
    if (-not $slug) { return "/albums/" }
    return "/albums/$slug/"
}

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

function Load-ExistingSelection([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        return @()
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw
        if (-not $raw) { return @() }
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $parsed -or $null -eq $parsed.items) {
            return @()
        }
        $items = @($parsed.items)
        return $items | Where-Object { $_ -and $_.src }
    } catch {
        return @()
    }
}

function Normalize-PhotoSrc([string]$src) {
    $value = ""
    if ($null -ne $src) { $value = [string]$src }
    if (-not $value) { return "" }
    if ($value.StartsWith("data:image/")) { return "" }
    if (-not $value.StartsWith("/")) { return "/$value" }
    return $value
}

function Get-ContentType([string]$path) {
    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    switch ($ext) {
        ".jpg" { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".png" { "image/png" }
        ".gif" { "image/gif" }
        ".webp" { "image/webp" }
        ".svg" { "image/svg+xml" }
        ".json" { "application/json; charset=utf-8" }
        ".html" { "text/html; charset=utf-8" }
        ".js" { "application/javascript; charset=utf-8" }
        ".css" { "text/css; charset=utf-8" }
        default { "application/octet-stream" }
    }
}

function Write-BinaryResponse($context, [byte[]]$bytes, [string]$contentType, [int]$statusCode = 200) {
    $context.Response.StatusCode = $statusCode
    $context.Response.ContentType = $contentType
    try {
        $context.Response.ContentLength64 = $bytes.Length
    } catch {
        try { $context.Response.SendChunked = $true } catch { }
    }
    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $context.Response.OutputStream.Close()
}

function New-ThumbnailBytes([string]$filePath, [int]$maxWidth, [int]$maxHeight) {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop | Out-Null

    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $ms = [System.IO.MemoryStream]::new([byte[]]$bytes)
    try {
        $img = [System.Drawing.Image]::FromStream($ms)
        try {
            $srcW = [double]$img.Width
            $srcH = [double]$img.Height
            if ($srcW -le 0 -or $srcH -le 0) { return $null }

            $scaleW = [double]$maxWidth / $srcW
            $scaleH = [double]$maxHeight / $srcH
            $scale = [Math]::Min($scaleW, $scaleH)
            if ($scale -gt 1.0) { $scale = 1.0 }

            $dstW = [int][Math]::Max(1, [Math]::Floor($srcW * $scale))
            $dstH = [int][Math]::Max(1, [Math]::Floor($srcH * $scale))

            $bmp = New-Object System.Drawing.Bitmap $dstW, $dstH
            try {
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                try {
                    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                    $g.DrawImage($img, 0, 0, $dstW, $dstH)
                } finally {
                    $g.Dispose()
                }

                $out = New-Object System.IO.MemoryStream
                try {
                    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" } | Select-Object -First 1
                    $encParams = New-Object System.Drawing.Imaging.EncoderParameters 1
                    $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 70L)
                    $bmp.Save($out, $codec, $encParams)
                    return $out.ToArray()
                } finally {
                    $out.Dispose()
                }
            } finally {
                $bmp.Dispose()
            }
        } finally {
            $img.Dispose()
        }
    } finally {
        $ms.Dispose()
    }
}

function Write-JsonResponse($context, $obj, [int]$statusCode = 200) {
    $json = $obj | ConvertTo-Json -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $context.Response.StatusCode = $statusCode
    $context.Response.ContentType = "application/json; charset=utf-8"
    try {
        $context.Response.ContentLength64 = $bytes.Length
    } catch {
        try { $context.Response.SendChunked = $true } catch { }
    }
    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $context.Response.OutputStream.Close()
}

function Write-TextResponse($context, [string]$text, [string]$contentType = "text/plain; charset=utf-8", [int]$statusCode = 200) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $context.Response.StatusCode = $statusCode
    $context.Response.ContentType = $contentType
    try {
        $context.Response.ContentLength64 = $bytes.Length
    } catch {
        try { $context.Response.SendChunked = $true } catch { }
    }
    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $context.Response.OutputStream.Close()
}

function Read-RequestBodyText($context) {
    $enc = [System.Text.Encoding]::UTF8
    $reader = New-Object System.IO.StreamReader($context.Request.InputStream, $enc)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

if (-not (Test-Path -LiteralPath $AlbumsRoot)) {
    throw "AlbumsRoot bestaat niet: $AlbumsRoot"
}

$existing = Load-ExistingSelection $OutputPath
$existingSet = New-Object System.Collections.Generic.HashSet[string]
foreach ($entry in @($existing)) {
    $normalized = Normalize-PhotoSrc ([string]$entry.src)
    if ($normalized) { [void]$existingSet.Add($normalized) }
}

Write-Host ""
Write-Host ("Huidige portfolio selectie: {0} foto's" -f $existingSet.Count) -ForegroundColor Cyan

$items = New-Object System.Collections.Generic.List[object]

$indexPaths = @(Get-ChildItem -LiteralPath $AlbumsRoot -Filter "index.html" -Recurse -File -ErrorAction SilentlyContinue)
foreach ($indexPath in $indexPaths) {
    if (-not $indexPath) { continue }
    if ($indexPath.Length -le 0) { continue }

    $albumSlug = Split-Path -Leaf (Split-Path -Parent $indexPath.FullName)
    $albumPath = Normalize-AlbumPath $albumSlug
    $html = Get-Content -LiteralPath $indexPath.FullName -Raw

    $titleMatch = [regex]::Match($html, "<h1[^>]*>(.*?)</h1>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $albumTitle = if ($titleMatch.Success) { Strip-Tags $titleMatch.Groups[1].Value } else { $albumSlug }

    $imgTags = [regex]::Matches($html, '<img\s+[^>]*>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $imageIndex = 0

    foreach ($imgTag in $imgTags) {
        $tag = $imgTag.Value
        $encoded = Get-Attr $tag "data-encoded-src"
        $src = ""
        if (-not $encoded) { continue }

        $decoded = Try-DecodeBase64 $encoded
        if (-not $decoded) { continue }
        $src = $decoded

        $src = Normalize-PhotoSrc $src
        if (-not $src) { continue }

        $alt = Get-Attr $tag "alt"
        $page = [Math]::Floor($imageIndex / $PageSize) + 1

        $items.Add([pscustomobject]@{
            album      = $albumPath
            albumTitle = $albumTitle
            src        = $src
            alt        = $alt
            page       = $page
            selected   = $existingSet.Contains($src)
        })

        $imageIndex += 1
    }
}

if ($items.Count -eq 0) {
    throw "Geen foto's gevonden in album index.html bestanden."
}

$itemsArray = $items.ToArray()

$itemsBySrc = @{}
foreach ($item in $itemsArray) {
    if ($item -and $item.src -and -not $itemsBySrc.ContainsKey([string]$item.src)) {
        $itemsBySrc[[string]$item.src] = $item
    }
}

$htmlPage = @'
<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Portfolio selectie</title>
  <style>
    :root { --bg:#0b0f17; --panel:#111827; --card:#0f172a; --text:#e5e7eb; --muted:#94a3b8; --accent:#38bdf8; --border:#243044; }
    body { margin:0; font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial; background:var(--bg); color:var(--text); }
    header { padding:12px 16px; background:linear-gradient(180deg,#0b0f17,#0b0f17cc); position:sticky; top:0; border-bottom:1px solid var(--border); z-index:10; }
    .row { display:flex; gap:10px; align-items:center; flex-wrap:wrap; }
    select,input,button { background:var(--panel); color:var(--text); border:1px solid var(--border); border-radius:10px; padding:10px 12px; font-size:14px; }
    input { min-width:260px; }
    button { cursor:pointer; }
    button.primary { background:var(--accent); color:#031018; border-color:transparent; font-weight:700; }
    main { display:grid; grid-template-columns: 1fr 340px; gap:12px; padding:12px 16px 16px; }
    .grid { display:grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap:10px; align-content:start; }
    .card { background:var(--card); border:1px solid var(--border); border-radius:14px; overflow:hidden; position:relative; }
    .card img { width:100%; height:120px; object-fit:cover; display:block; background:#0b1220; }
    .card .meta { padding:8px 10px; font-size:12px; color:var(--muted); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
    .card .check { position:absolute; top:8px; left:8px; width:22px; height:22px; border-radius:7px; background:#00000066; border:1px solid #ffffff40; display:flex; align-items:center; justify-content:center; }
    .card .check::after { content:""; width:10px; height:6px; border-left:3px solid transparent; border-bottom:3px solid transparent; transform: rotate(-45deg); opacity:0; }
    .card.selected .check::after { border-left-color:#e5e7eb; border-bottom-color:#e5e7eb; opacity:1; }
    .card.selected { outline:2px solid var(--accent); border-color:transparent; }
    .side { background:var(--panel); border:1px solid var(--border); border-radius:14px; padding:12px; position:sticky; top:74px; height: calc(100vh - 98px); overflow:auto; }
    .side h2 { margin:0 0 8px; font-size:16px; }
    .side .muted { color:var(--muted); font-size:12px; margin-bottom:10px; }
    .preview { width:100%; aspect-ratio: 4/3; background:#0b1220; border:1px solid var(--border); border-radius:12px; overflow:hidden; display:flex; align-items:center; justify-content:center; }
    .preview img { width:100%; height:100%; object-fit:contain; }
    .pill { display:inline-flex; gap:8px; align-items:center; font-size:12px; color:var(--muted); }
    .toast { margin-top:10px; font-size:12px; color:var(--muted); }
  </style>
</head>
<body>
  <header>
    <div class="row">
      <strong>Portfolio selectie</strong>
      <span class="pill" id="countPill"></span>
      <select id="album"></select>
      <input id="q" placeholder="Zoek op album of bestandsnaam..." />
      <button class="primary" id="save">Opslaan</button>
    </div>
    <div class="toast" id="toast"></div>
  </header>
  <main>
    <section class="grid" id="grid" aria-label="Foto's"></section>
    <aside class="side">
      <h2>Preview</h2>
      <div class="muted" id="previewMeta">Klik op een foto.</div>
      <div class="preview"><img id="previewImg" alt="Preview" /></div>
    </aside>
  </main>
  <script>
    const state = { items: [], selected: new Set(), album: "ALL", q: "" };
    const el = (id) => document.getElementById(id);
    const grid = el("grid");
    const toast = el("toast");
    const countPill = el("countPill");
    const previewImg = el("previewImg");
    const previewMeta = el("previewMeta");

    const setToast = (msg) => { toast.textContent = msg || ""; };
    const setCount = () => { countPill.textContent = `Geselecteerd: ${state.selected.size}`; };

    const byAlbumThenSrc = (a,b) => {
      const aa = (a.albumTitle||"").toLowerCase(), bb = (b.albumTitle||"").toLowerCase();
      if (aa < bb) return -1; if (aa > bb) return 1;
      return (a.src||"").localeCompare(b.src||"");
    };

    const fileName = (src) => (src||"").split("/").pop() || src;

    const renderAlbums = () => {
      const sel = el("album");
      const titles = Array.from(new Set(state.items.map(i => i.albumTitle).filter(Boolean))).sort((a,b)=>a.localeCompare(b));
      sel.innerHTML = "";
      const optAll = document.createElement("option");
      optAll.value = "ALL"; optAll.textContent = "Alle albums";
      sel.appendChild(optAll);
      titles.forEach(t => {
        const o = document.createElement("option");
        o.value = t; o.textContent = t;
        sel.appendChild(o);
      });
      sel.value = state.album;
    };

    const matches = (item) => {
      if (state.album !== "ALL" && item.albumTitle !== state.album) return false;
      const q = state.q.trim().toLowerCase();
      if (!q) return true;
      return (item.albumTitle||"").toLowerCase().includes(q) || (item.src||"").toLowerCase().includes(q);
    };

    const renderGrid = () => {
      const frag = document.createDocumentFragment();
      const items = state.items.filter(matches).sort(byAlbumThenSrc);
      items.forEach(item => {
        const card = document.createElement("button");
        card.type = "button";
        card.className = "card" + (state.selected.has(item.src) ? " selected" : "");
        card.title = item.albumTitle || "";
        card.style.textAlign = "left";
        card.style.padding = "0";
        card.style.border = "1px solid var(--border)";

        const img = document.createElement("img");
        img.loading = "lazy";
        img.src = `/thumb?src=${encodeURIComponent(item.src)}`;
        img.alt = item.alt || "foto";

        const meta = document.createElement("div");
        meta.className = "meta";
        meta.textContent = `${item.albumTitle || "Album"} • ${fileName(item.src)}`;

        const check = document.createElement("div");
        check.className = "check";
        // check mark is rendered via CSS to avoid font/encoding issues

        card.append(img, meta, check);

        card.addEventListener("click", () => {
          if (state.selected.has(item.src)) state.selected.delete(item.src);
          else state.selected.add(item.src);
          previewImg.src = item.src;
          previewMeta.textContent = `${item.albumTitle || ""}\\n${item.src}`;
          setCount();
          renderGrid();
        });

        frag.appendChild(card);
      });
      grid.innerHTML = "";
      grid.appendChild(frag);
    };

    const load = async () => {
      setToast("Laden...");
      const res = await fetch("/api/items", { cache: "no-store" });
      const data = await res.json();
      state.items = data.items || [];
      state.selected = new Set((state.items || []).filter(i => i.selected).map(i => i.src));
      renderAlbums();
      setCount();
      renderGrid();
      setToast("");
    };

    el("album").addEventListener("change", (e) => { state.album = e.target.value; renderGrid(); });
    let qTimer = null;
    el("q").addEventListener("input", (e) => {
      clearTimeout(qTimer);
      qTimer = setTimeout(() => { state.q = e.target.value || ""; renderGrid(); }, 200);
    });

    el("save").addEventListener("click", async () => {
      setToast("Opslaan...");
      const body = JSON.stringify({ selectedSrc: Array.from(state.selected) });
      const res = await fetch("/api/save", { method:"POST", headers:{ "Content-Type":"application/json" }, body });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setToast(data.error || "Opslaan mislukt.");
        return;
      }
      setToast(`Opgeslagen (${data.count||0}). Je kan dit tabblad sluiten.`);
    });

    load().catch(err => setToast(String(err)));
  </script>
</body>
</html>
'@

$listener = [System.Net.HttpListener]::new()
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host ""
Write-Host ("Web picker gestart op {0}" -f $prefix) -ForegroundColor Green
Write-Host "Sluit met Ctrl+C." -ForegroundColor DarkGray

try {
    Start-Process $prefix | Out-Null
} catch {
    Write-Host ("Kon browser niet automatisch openen. Open handmatig: {0}" -f $prefix) -ForegroundColor Yellow
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $path = $context.Request.Url.AbsolutePath

        if ($path -eq "/" -or $path -eq "/index.html") {
            Write-TextResponse $context $htmlPage "text/html; charset=utf-8" 200
            continue
        }

        if ($path -eq "/api/items") {
            Write-JsonResponse $context @{ items = $itemsArray } 200
            continue
        }

        if ($path -eq "/api/save") {
            if ($context.Request.HttpMethod -ne "POST") {
                Write-JsonResponse $context @{ error = "Use POST" } 405
                continue
            }

            $raw = Read-RequestBodyText $context
            $payload = $null
            try { $payload = $raw | ConvertFrom-Json -ErrorAction Stop } catch { }
            if ($null -eq $payload -or $null -eq $payload.selectedSrc) {
                Write-JsonResponse $context @{ error = "Invalid JSON" } 400
                continue
            }

            $selectedSrc = @($payload.selectedSrc | ForEach-Object { Normalize-PhotoSrc ([string]$_) } | Where-Object { $_ })
            if ($selectedSrc.Count -eq 0) {
                Write-JsonResponse $context @{ error = "Geen foto's geselecteerd." } 400
                continue
            }

            $selectedItems = @(
                $selectedSrc | ForEach-Object {
                    if ($itemsBySrc.ContainsKey($_)) { $itemsBySrc[$_] } else { $null }
                } | Where-Object { $_ }
            )

            if ($selectedItems.Count -eq 0) {
                Write-JsonResponse $context @{ error = "Geen geldige foto's geselecteerd." } 400
                continue
            }

            $outputObject = @{
                version = 1
                items   = @($selectedItems | ForEach-Object {
                    @{
                        album      = $_.album
                        albumTitle = $_.albumTitle
                        src        = $_.src
                        alt        = $_.alt
                        page       = $_.page
                    }
                })
            }

            $outputDir = Split-Path -Parent $OutputPath
            if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
                New-Item -ItemType Directory -Path $outputDir | Out-Null
            }
            $json = $outputObject | ConvertTo-Json -Depth 6
            Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8

            Write-Host ("Geschreven: {0} ({1})" -f $OutputPath, $outputObject.items.Count) -ForegroundColor Green
            Write-JsonResponse $context @{ ok = $true; count = $outputObject.items.Count } 200
            continue
        }

        if ($path -eq "/thumb") {
            $src = ""
            try { $src = [string]$context.Request.QueryString["src"] } catch { $src = "" }
            $src = Normalize-PhotoSrc $src
            if (-not $src) {
                Write-TextResponse $context "Bad request" "text/plain; charset=utf-8" 400
                continue
            }

            $fsPath = Resolve-ImageFilePath $src
            if (-not $fsPath -or -not (Test-Path -LiteralPath $fsPath)) {
                Write-TextResponse $context "Not found" "text/plain; charset=utf-8" 404
                continue
            }

            try {
                $thumbBytes = New-ThumbnailBytes -filePath $fsPath -maxWidth 420 -maxHeight 320
                if ($null -eq $thumbBytes) {
                    Write-TextResponse $context "Unsupported" "text/plain; charset=utf-8" 415
                    continue
                }
                Write-BinaryResponse $context $thumbBytes "image/jpeg" 200
            } catch {
                Write-TextResponse $context "Error" "text/plain; charset=utf-8" 500
            }
            continue
        }

        if ($path.StartsWith("/images/")) {
            $fsPath = Resolve-ImageFilePath $path
            if (-not $fsPath -or -not (Test-Path -LiteralPath $fsPath)) {
                Write-TextResponse $context "Not found" "text/plain; charset=utf-8" 404
                continue
            }
            try {
                $bytes = [System.IO.File]::ReadAllBytes($fsPath)
                $context.Response.StatusCode = 200
                $context.Response.ContentType = Get-ContentType $fsPath
                $context.Response.ContentLength64 = $bytes.Length
                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $context.Response.OutputStream.Close()
            } catch {
                Write-TextResponse $context "Error" "text/plain; charset=utf-8" 500
            }
            continue
        }

        Write-TextResponse $context "Not found" "text/plain; charset=utf-8" 404
    }
} finally {
    try { $listener.Stop() } catch { }
    try { $listener.Close() } catch { }
}
