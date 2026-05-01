param(
    [string]$AlbumsRoot = (Join-Path $PSScriptRoot "albums"),
    [string]$ImagesRoot = (Join-Path $PSScriptRoot "images"),
    [string]$AlbumsIndexPath = (Join-Path $PSScriptRoot "albums\\index.html"),
    [string]$PortfolioSelectionPath = (Join-Path $PSScriptRoot "portfolio\\selection.json"),
    [int]$Port = 8766
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

    $sample = ""
    if ($photoSrcs.Count -gt 0) { $sample = [string]$photoSrcs[0] }

    return [pscustomobject]@{
        slug         = $slug
        title        = $albumTitle
        albumDir     = $albumDir
        indexPath    = $indexPath
        photos       = @($photoSrcs)
        photoCount   = $photoSrcs.Count
        imageFolders = @($imageFolders)
        sampleSrc    = $sample
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

function Write-JsonResponse($context, $obj, [int]$statusCode = 200) {
    $json = $obj | ConvertTo-Json -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $context.Response.StatusCode = $statusCode
    $context.Response.ContentType = "application/json; charset=utf-8"
    try { $context.Response.ContentLength64 = $bytes.Length } catch { try { $context.Response.SendChunked = $true } catch { } }
    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $context.Response.OutputStream.Close()
}

function Write-TextResponse($context, [string]$text, [string]$contentType = "text/plain; charset=utf-8", [int]$statusCode = 200) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $context.Response.StatusCode = $statusCode
    $context.Response.ContentType = $contentType
    try { $context.Response.ContentLength64 = $bytes.Length } catch { try { $context.Response.SendChunked = $true } catch { } }
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

$htmlPage = @'
<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Albums verwijderen</title>
  <style>
    :root { --bg:#0b0f17; --panel:#111827; --card:#0f172a; --text:#e5e7eb; --muted:#94a3b8; --accent:#fb7185; --border:#243044; }
    body { margin:0; font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial; background:var(--bg); color:var(--text); }
    header { padding:12px 16px; border-bottom:1px solid var(--border); position:sticky; top:0; background:linear-gradient(180deg,#0b0f17,#0b0f17cc); z-index:10; }
    .row { display:flex; gap:10px; align-items:center; flex-wrap:wrap; }
    input,button { background:var(--panel); color:var(--text); border:1px solid var(--border); border-radius:10px; padding:10px 12px; font-size:14px; }
    input { min-width:280px; }
    button { cursor:pointer; }
    button.danger { background:var(--accent); color:#2a060d; border-color:transparent; font-weight:800; }
    main { display:grid; grid-template-columns: 1fr 380px; gap:12px; padding:12px 16px 16px; }
    .list { display:grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap:10px; align-content:start; }
    .card { background:var(--card); border:1px solid var(--border); border-radius:14px; overflow:hidden; padding:10px; text-align:left; }
    .card strong { display:block; margin-bottom:4px; }
    .card .muted { color:var(--muted); font-size:12px; }
    .card.active { outline:2px solid var(--accent); border-color:transparent; }
    aside { background:var(--panel); border:1px solid var(--border); border-radius:14px; padding:12px; position:sticky; top:74px; height: calc(100vh - 98px); overflow:auto; }
    .warning { color:#fecdd3; font-size:12px; line-height:1.4; }
    .kv { font-size:12px; color:var(--muted); white-space:pre-wrap; }
    .toast { margin-top:10px; font-size:12px; color:var(--muted); }
  </style>
</head>
<body>
  <header>
    <div class="row">
      <strong>Albums verwijderen</strong>
      <input id="q" placeholder="Zoek album..." />
      <span class="toast" id="toast"></span>
    </div>
  </header>
  <main>
    <section class="list" id="list" aria-label="Albums"></section>
    <aside>
      <h2 style="margin:0 0 8px;font-size:16px;">Geselecteerd</h2>
      <div class="warning">Dit verplaatst bestanden naar <code>_trash</code> (geen permanente delete). Toch: check altijd even of je het juiste album kiest.</div>
      <div class="kv" id="details" style="margin-top:10px;"></div>
      <div style="margin-top:12px;">
        <div class="kv">Type exact de slug om te bevestigen:</div>
        <input id="confirm" placeholder="bijv. LeythonMA" />
      </div>
      <div style="margin-top:10px;">
        <button class="danger" id="delete">Verplaats naar prullenbak</button>
      </div>
    </aside>
  </main>
  <script>
    const el = (id) => document.getElementById(id);
    const listEl = el("list");
    const toast = el("toast");
    const details = el("details");
    const confirmEl = el("confirm");
    let albums = [];
    let active = null;

    const setToast = (t) => toast.textContent = t || "";
    const esc = (s) => (s||"").replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;");

    const render = () => {
      const q = (el("q").value || "").trim().toLowerCase();
      listEl.innerHTML = "";
      const frag = document.createDocumentFragment();
      albums
        .filter(a => !q || (a.title||"").toLowerCase().includes(q) || (a.slug||"").toLowerCase().includes(q))
        .sort((a,b) => (a.title||a.slug||"").localeCompare(b.title||b.slug||""))
        .forEach(a => {
          const btn = document.createElement("button");
          btn.type = "button";
          btn.className = "card" + (active && active.slug === a.slug ? " active" : "");
          btn.addEventListener("click", () => { active = a; confirmEl.value = ""; renderDetails(); render(); });
          btn.innerHTML = `<strong>${esc(a.title||a.slug)}</strong>
            <div class="muted">slug: ${esc(a.slug)} • foto's: ${a.photoCount}</div>`;
          frag.appendChild(btn);
        });
      listEl.appendChild(frag);
    };

    const renderDetails = () => {
      if (!active) { details.textContent = "Klik links op een album."; return; }
      details.textContent =
        `Slug: ${active.slug}\n` +
        `Titel: ${active.title}\n` +
        `Foto's: ${active.photoCount}\n` +
        `Album map: ${active.albumDir}\n` +
        `Index: ${active.indexPath}\n` +
        `Image folders: ${(active.imageFolders||[]).join(", ")}`;
    };

    const load = async () => {
      setToast("Laden...");
      const res = await fetch("/api/albums", { cache:"no-store" });
      const data = await res.json();
      albums = data.albums || [];
      setToast("");
      renderDetails();
      render();
    };

    el("q").addEventListener("input", () => render());

    el("delete").addEventListener("click", async () => {
      if (!active) return;
      const confirmText = (confirmEl.value || "").trim();
      setToast("Bezig met verwijderen...");
      const res = await fetch("/api/delete", {
        method:"POST",
        headers:{ "Content-Type":"application/json" },
        body: JSON.stringify({ slug: active.slug, confirm: confirmText })
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) { setToast(data.error || "Mislukt."); return; }
      setToast(`Verplaatst naar _trash. (${data.movedCount||0} paden)`);
      active = null;
      confirmEl.value = "";
      await load();
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
Write-Host ("Album delete tool gestart op {0}" -f $prefix) -ForegroundColor Green
Write-Host "Sluit met Ctrl+C." -ForegroundColor DarkGray

try { Start-Process $prefix | Out-Null } catch { Write-Host ("Open handmatig: {0}" -f $prefix) -ForegroundColor Yellow }

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $path = $context.Request.Url.AbsolutePath

        if ($path -eq "/" -or $path -eq "/index.html") {
            Write-TextResponse $context $htmlPage "text/html; charset=utf-8" 200
            continue
        }

        if ($path -eq "/api/albums") {
            $albums = Load-Albums
            Write-JsonResponse $context @{ albums = $albums } 200
            continue
        }

        if ($path -eq "/api/delete") {
            if ($context.Request.HttpMethod -ne "POST") {
                Write-JsonResponse $context @{ error = "Use POST" } 405
                continue
            }

            $raw = Read-RequestBodyText $context
            $payload = $null
            try { $payload = $raw | ConvertFrom-Json -ErrorAction Stop } catch { }
            $slug = if ($payload -and $payload.slug) { [string]$payload.slug } else { "" }
            $confirm = if ($payload -and $payload.confirm) { [string]$payload.confirm } else { "" }

            if (-not $slug) {
                Write-JsonResponse $context @{ error = "Missing slug" } 400
                continue
            }
            if ($confirm -ne $slug) {
                Write-JsonResponse $context @{ error = "Bevestiging klopt niet. Type exact de slug." } 400
                continue
            }

            $info = Get-AlbumInfo $slug
            if (-not $info) {
                Write-JsonResponse $context @{ error = "Album niet gevonden: $slug" } 404
                continue
            }

            $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
            $trashRoot = Join-Path $PSScriptRoot ("_trash\\album-delete\\{0}\\{1}" -f $timestamp, $slug)
            Ensure-Dir $trashRoot

            $moved = New-Object System.Collections.Generic.List[string]

            # album pages
            $m1 = Move-ToTrash -sourcePath (Join-Path $AlbumsRoot $slug) -trashRoot $trashRoot
            if ($m1) { $moved.Add($m1) }

            $m2 = Move-ToTrash -sourcePath (Join-Path $PSScriptRoot $slug) -trashRoot $trashRoot
            if ($m2) { $moved.Add($m2) }

            $m3 = Move-ToTrash -sourcePath (Join-Path $PSScriptRoot ("{0}.html" -f $slug)) -trashRoot $trashRoot
            if ($m3) { $moved.Add($m3) }

            # referenced image folders
            foreach ($folderName in @($info.imageFolders)) {
                if (-not $folderName) { continue }
                $candidate = Join-Path $ImagesRoot $folderName
                $m = Move-ToTrash -sourcePath $candidate -trashRoot $trashRoot
                if ($m) { $moved.Add($m) }
            }

            $albumsIndexChanged = $false
            try { $albumsIndexChanged = Remove-AlbumFromAlbumsIndex $slug } catch { $albumsIndexChanged = $false }

            $portfolioChanged = $false
            try { $portfolioChanged = Remove-AlbumFromPortfolioSelection -photoSrcs @($info.photos) } catch { $portfolioChanged = $false }

            Write-Host ("Verplaatst album {0} naar {1}" -f $slug, $trashRoot) -ForegroundColor Yellow
            Write-JsonResponse $context @{
                ok               = $true
                trashRoot        = $trashRoot
                movedCount       = $moved.Count
                albumsIndexChanged = $albumsIndexChanged
                portfolioChanged = $portfolioChanged
            } 200
            continue
        }

        Write-TextResponse $context "Not found" "text/plain; charset=utf-8" 404
    }
} finally {
    try { $listener.Stop() } catch { }
    try { $listener.Close() } catch { }
}
