param(
    [string]$AlbumsRoot = (Join-Path $PSScriptRoot "albums"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "portfolio\\selection.json"),
    [int]$PageSize = 100
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

function Parse-IndexList([string]$inputValue, [int]$max) {
    $result = New-Object System.Collections.Generic.HashSet[int]
    $trimmed = ""
    if ($null -ne $inputValue) {
        $trimmed = [string]$inputValue
    }
    $trimmed = $trimmed.Trim()
    if (-not $trimmed) { return $result }
    if ($trimmed -ieq "all") {
        1..$max | ForEach-Object { [void]$result.Add($_) }
        return $result
    }

    foreach ($token in ($trimmed -split ",")) {
        $t = $token.Trim()
        if (-not $t) { continue }

        if ($t -match '^(\d+)$') {
            $value = [int]$Matches[1]
            if ($value -ge 1 -and $value -le $max) { [void]$result.Add($value) }
            continue
        }

        if ($t -match '^(\d+)\s*-\s*(\d+)$') {
            $start = [int]$Matches[1]
            $end = [int]$Matches[2]
            if ($start -gt $end) { $tmp = $start; $start = $end; $end = $tmp }
            $start = [Math]::Max(1, $start)
            $end = [Math]::Min($max, $end)
            if ($start -le $end) {
                $start..$end | ForEach-Object { [void]$result.Add($_) }
            }
            continue
        }
    }

    return $result
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
    if ($null -ne $src) {
        $value = [string]$src
    }
    if (-not $value) { return "" }
    if ($value.StartsWith("data:image/")) { return "" }
    if (-not $value.StartsWith("/")) { return "/$value" }
    return $value
}

function Show-ThumbnailPicker([object]$items, [System.Collections.Generic.HashSet[string]]$existingSet) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    } catch {
        return [pscustomobject]@{
            Mode   = "gui_unavailable"
            Reason = ("WinForms niet beschikbaar: {0}" -f $_.Exception.Message)
        }
    }

    try {
        if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
            return [pscustomobject]@{
                Mode   = "gui_unavailable"
                Reason = ("Niet in STA thread (ApartmentState={0}). Start via start-portfolio-selection.cmd." -f [System.Threading.Thread]::CurrentThread.ApartmentState)
            }
        }
    } catch {
        return [pscustomobject]@{
            Mode   = "gui_unavailable"
            Reason = ("Kon ApartmentState niet lezen: {0}" -f $_.Exception.Message)
        }
    }

    [System.Windows.Forms.Application]::EnableVisualStyles()

    try {
    try {
        Add-Type -Namespace Win32 -Name User32 -MemberDefinition @"
using System;
using System.Runtime.InteropServices;
public static class User32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction SilentlyContinue | Out-Null
    } catch { }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Portfolio selectie"
    $form.Width = 1200
    $form.Height = 780
    $form.StartPosition = "Manual"
    $form.ShowInTaskbar = $true
    $form.TopMost = $true
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal

    $topPanel = New-Object System.Windows.Forms.Panel
    $topPanel.Dock = "Top"
    $topPanel.Height = 56
    $topPanel.Padding = "12,10,12,10"

    $albumLabel = New-Object System.Windows.Forms.Label
    $albumLabel.Text = "Album:"
    $albumLabel.AutoSize = $true
    $albumLabel.Top = 18
    $albumLabel.Left = 12

    $albumCombo = New-Object System.Windows.Forms.ComboBox
    $albumCombo.DropDownStyle = "DropDownList"
    $albumCombo.Width = 320
    $albumCombo.Left = 66
    $albumCombo.Top = 14

    $searchLabel = New-Object System.Windows.Forms.Label
    $searchLabel.Text = "Zoek:"
    $searchLabel.AutoSize = $true
    $searchLabel.Top = 18
    $searchLabel.Left = 404

    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.Width = 360
    $searchBox.Left = 450
    $searchBox.Top = 14

    $hintLabel = New-Object System.Windows.Forms.Label
    $hintLabel.Text = "Tip: klik op een foto voor preview, vink aan/uit en klik OK."
    $hintLabel.AutoSize = $true
    $hintLabel.Top = 18
    $hintLabel.Left = 828

    $topPanel.Controls.AddRange(@($albumLabel, $albumCombo, $searchLabel, $searchBox, $hintLabel))

    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Dock = "Bottom"
    $bottomPanel.Height = 64
    $bottomPanel.Padding = "12,10,12,10"

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.AutoSize = $true
    $statusLabel.Left = 12
    $statusLabel.Top = 22

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Width = 120
    $okButton.Height = 34
    $okButton.Anchor = "Right"
    $okButton.Top = 16

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Annuleren"
    $cancelButton.Width = 120
    $cancelButton.Height = 34
    $cancelButton.Anchor = "Right"
    $cancelButton.Top = 16

    $bottomPanel.Controls.Add($statusLabel)
    $bottomPanel.Controls.Add($okButton)
    $bottomPanel.Controls.Add($cancelButton)

    $split = New-Object System.Windows.Forms.SplitContainer
    $split.Dock = "Fill"
    $split.Orientation = [System.Windows.Forms.Orientation]::Vertical
    $split.SplitterWidth = 6

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Dock = "Fill"
    $listView.View = [System.Windows.Forms.View]::LargeIcon
    $listView.CheckBoxes = $true
    $listView.MultiSelect = $true
    $listView.HideSelection = $false
    $listView.ShowItemToolTips = $true

    $imageList = New-Object System.Windows.Forms.ImageList
    $imageList.ImageSize = New-Object System.Drawing.Size(140, 105)
    $imageList.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit
    $listView.LargeImageList = $imageList

    $previewPanel = New-Object System.Windows.Forms.Panel
    $previewPanel.Dock = "Fill"
    $previewPanel.Padding = "12,12,12,12"

    $previewTitle = New-Object System.Windows.Forms.Label
    $previewTitle.AutoSize = $true
    $previewTitle.Text = "Preview"
    $previewTitle.Dock = "Top"
    $previewTitle.Font = New-Object System.Drawing.Font($previewTitle.Font.FontFamily, 12, [System.Drawing.FontStyle]::Bold)

    $previewMeta = New-Object System.Windows.Forms.Label
    $previewMeta.AutoSize = $false
    $previewMeta.Height = 62
    $previewMeta.Dock = "Top"
    $previewMeta.Padding = "0,8,0,0"

    $previewBox = New-Object System.Windows.Forms.PictureBox
    $previewBox.Dock = "Fill"
    $previewBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $previewBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $previewBox.BackColor = [System.Drawing.Color]::White

    $previewPanel.Controls.Add($previewBox)
    $previewPanel.Controls.Add($previewMeta)
    $previewPanel.Controls.Add($previewTitle)

    $split.Panel1.Controls.Add($listView)
    $split.Panel2.Controls.Add($previewPanel)

    $form.Controls.Add($split)
    $form.Controls.Add($bottomPanel)
    $form.Controls.Add($topPanel)

    $okButton.Left = $form.ClientSize.Width - 12 - $okButton.Width
    $cancelButton.Left = $okButton.Left - 10 - $cancelButton.Width

    $form.Add_Resize({
        param($sender, $e)
        $okButton.Left = $form.ClientSize.Width - 12 - $okButton.Width
        $cancelButton.Left = $okButton.Left - 10 - $cancelButton.Width
    })

    $form.Add_Shown({
        param($sender, $e)
        try {
            $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
            $targetWidth = [Math]::Min($form.Width, $wa.Width)
            $targetHeight = [Math]::Min($form.Height, $wa.Height)
            if ($targetWidth -gt 0 -and $targetHeight -gt 0) {
                $form.Size = New-Object System.Drawing.Size($targetWidth, $targetHeight)
            }
            $x = [int]($wa.Left + (($wa.Width - $form.Width) / 2))
            $y = [int]($wa.Top + (($wa.Height - $form.Height) / 2))
            $form.Location = New-Object System.Drawing.Point($x, $y)
        } catch { }

        try {
            $split.Panel1MinSize = 520
            $split.Panel2MinSize = 260
            $desired = [Math]::Min(820, [Math]::Max($split.Panel1MinSize, $split.Width - $split.Panel2MinSize))
            if ($desired -gt 0) {
                $split.SplitterDistance = $desired
            }
        } catch { }

        try {
            $form.Activate() | Out-Null
            $form.BringToFront()
            $form.Focus() | Out-Null
            try {
                [Win32.User32]::ShowWindowAsync($form.Handle, 9) | Out-Null
                [Win32.User32]::SetForegroundWindow($form.Handle) | Out-Null
            } catch { }
            $form.TopMost = $false
        } catch { }
    })

    $buffer = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $items) {
        [void]$buffer.Add($entry)
    }
    $itemsList = $buffer.ToArray()
    $albumTitles = @("Alle albums") + @(
        $itemsList | Select-Object -ExpandProperty albumTitle | Where-Object { $_ } | Sort-Object -Unique
    )
    [void]$albumCombo.Items.AddRange($albumTitles)
    $albumCombo.SelectedIndex = 0

    $thumbCache = @{}
    $previewImage = $null
    $refreshToken = 0

    $thumbTimer = New-Object System.Windows.Forms.Timer
    $thumbTimer.Interval = 20
    $thumbQueue = New-Object System.Collections.Generic.Queue[object]

    $searchDebounce = New-Object System.Windows.Forms.Timer
    $searchDebounce.Interval = 250
    $searchDebounce.Stop()

    $setPreview = {
        param([object]$item)

        if ($null -ne $previewImage) {
            try { $previewImage.Dispose() } catch { }
            $previewImage = $null
        }

        if ($null -eq $item) {
            $previewBox.Image = $null
            $previewMeta.Text = ""
            return
        }

        $src = [string]$item.src
        $filePath = Resolve-ImageFilePath $src

        $previewMeta.Text = ("{0}`n{1}" -f ([string]$item.albumTitle), $src)

        if (-not $filePath -or -not (Test-Path -LiteralPath $filePath)) {
            $previewBox.Image = $null
            return
        }

        try {
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $ms = [System.IO.MemoryStream]::new([byte[]]$bytes)
            try {
                $img = [System.Drawing.Image]::FromStream($ms)
                try {
                    $previewImage = New-Object System.Drawing.Bitmap($img)
                } finally {
                    try { $img.Dispose() } catch { }
                }
            } finally {
                try { $ms.Dispose() } catch { }
            }
            $previewBox.Image = $previewImage
        } catch {
            $previewBox.Image = $null
        }
    }

    $makeThumb = {
        param([string]$filePath)
        if (-not $filePath -or -not (Test-Path -LiteralPath $filePath)) {
            return $null
        }
        if ($thumbCache.ContainsKey($filePath)) {
            return $thumbCache[$filePath]
        }

        try {
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $ms = [System.IO.MemoryStream]::new([byte[]]$bytes)
            try {
                $img = [System.Drawing.Image]::FromStream($ms)
                try {
                    $thumb = $img.GetThumbnailImage(140, 105, $null, [IntPtr]::Zero)
                    $thumbCache[$filePath] = $thumb
                    return $thumb
                } finally {
                    $img.Dispose()
                }
            } finally {
                try { $ms.Dispose() } catch { }
            }
        } catch {
            return $null
        }
    }

    $thumbTimer.Add_Tick({
        param($sender, $e)
        $processed = 0
        while ($thumbQueue.Count -gt 0 -and $processed -lt 10) {
            $job = $thumbQueue.Dequeue()
            if ($null -eq $job) { continue }
            if ($job.Token -ne $refreshToken) { continue }

            $idx = [int]$job.Index
            $filePath = [string]$job.FilePath

            $thumb = & $makeThumb $filePath
            if ($null -ne $thumb) {
                try {
                    $imageList.Images[$idx] = $thumb
                    $listView.Invalidate()
                } catch { }
            }

            $processed += 1
        }

        if ($thumbQueue.Count -eq 0) {
            $thumbTimer.Stop()
        }
    })

    $refresh = {
        $refreshToken += 1
        $thumbTimer.Stop()
        $thumbQueue.Clear()

        $listView.BeginUpdate()
        try {
            $listView.Items.Clear()
            $imageList.Images.Clear()

            $albumFilter = [string]$albumCombo.SelectedItem
            $query = [string]$searchBox.Text
            if ($null -eq $query) { $query = "" }
            $query = $query.Trim().ToLowerInvariant()

            $filtered = $itemsList
            if ($albumFilter -and $albumFilter -ne "Alle albums") {
                $filtered = $filtered | Where-Object { $_.albumTitle -eq $albumFilter }
            }

            if ($query) {
                $filtered = $filtered | Where-Object {
                    ([string]$_.src).ToLowerInvariant().Contains($query) -or
                    ([string]$_.albumTitle).ToLowerInvariant().Contains($query)
                }
            }

            $filtered = $filtered | Sort-Object albumTitle, src

            $index = 0
            foreach ($item in $filtered) {
                $src = [string]$item.src
                $filePath = Resolve-ImageFilePath $src

                $blank = New-Object System.Drawing.Bitmap 140, 105
                [void]$imageList.Images.Add($blank)
                if ($filePath) {
                    $thumbQueue.Enqueue([pscustomobject]@{ Token = $refreshToken; Index = $index; FilePath = $filePath })
                }

            $display = ""
            try {
                $display = [System.IO.Path]::GetFileName($filePath)
            } catch {
                $display = ""
            }
            if (-not $display) { $display = [string]$item.src }

            $lvItem = New-Object System.Windows.Forms.ListViewItem
            $lvItem.Text = $display
            $lvItem.ImageIndex = $index
            $lvItem.Tag = $item
            $lvItem.ToolTipText = ("{0}`n{1}" -f ([string]$item.albumTitle), ([string]$item.src))
            if ($existingSet -and $existingSet.Contains($src)) {
                $lvItem.Checked = $true
            }
            [void]$listView.Items.Add($lvItem)
                $index += 1
            }

            $checkedCount = @($listView.CheckedItems).Count
            $statusLabel.Text = ("Geselecteerd: {0}" -f $checkedCount)

            if ($listView.Items.Count -gt 0) {
                try {
                    $first = $listView.Items[0]
                    if ($null -ne $first -and $null -ne $first.Tag) {
                        $first.Selected = $true
                        $listView.Select()
                        & $setPreview $first.Tag
                    } else {
                        & $setPreview $null
                    }
                } catch {
                    & $setPreview $null
                }
            } else {
                & $setPreview $null
            }
        } finally {
            $listView.EndUpdate()
        }

        if ($thumbQueue.Count -gt 0) {
            $thumbTimer.Start()
        }
    }

    $albumCombo.Add_SelectedIndexChanged({ param($sender, $e) & $refresh })
    $searchBox.Add_TextChanged({
        param($sender, $e)
        $searchDebounce.Stop()
        $searchDebounce.Start()
    })
    $searchDebounce.Add_Tick({
        param($sender, $e)
        $searchDebounce.Stop()
        & $refresh
    })

    $listView.Add_ItemChecked({
        param($sender, $e)
        $checkedCount = @($listView.CheckedItems).Count
        $statusLabel.Text = ("Geselecteerd: {0}" -f $checkedCount)

        try {
            if ($null -ne $e -and $null -ne $e.Item -and $null -ne $e.Item.Tag) {
                & $setPreview $e.Item.Tag
            }
        } catch { }
    })

    $listView.Add_SelectedIndexChanged({
        param($sender, $e)
        try {
            if ($listView.SelectedItems.Count -gt 0) {
                & $setPreview $listView.SelectedItems[0].Tag
            } else {
                & $setPreview $null
            }
        } catch {
            & $setPreview $null
        }
    })

    $listView.Add_MouseUp({
        param($sender, $e)
        try {
            $hit = $listView.HitTest($e.Location)
            if ($hit -and $hit.Item) {
                $hit.Item.Selected = $true
                $listView.Select()
                if ($hit.Item.Tag) {
                    & $setPreview $hit.Item.Tag
                }
            }
        } catch { }
    })

    $result = $null

    $okButton.Add_Click({
        $result = @($listView.CheckedItems | ForEach-Object { $_.Tag })
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $cancelButton.Add_Click({
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Close()
    })

    Write-Host ""
    Write-Host "Preview picker wordt geopend... (check ook je taakbalk)" -ForegroundColor Cyan

    & $refresh
    $dialog = $form.ShowDialog()

    foreach ($thumb in $thumbCache.Values) {
        try { $thumb.Dispose() } catch { }
    }
    if ($null -ne $previewImage) {
        try { $previewImage.Dispose() } catch { }
    }

    if ($dialog -ne [System.Windows.Forms.DialogResult]::OK) {
        return [pscustomobject]@{ Mode = "gui"; Cancelled = $true; Items = @() }
    }

    return [pscustomobject]@{ Mode = "gui"; Cancelled = $false; Items = @($result) }
    } catch {
        $position = ""
        try { $position = [string]$_.InvocationInfo.PositionMessage } catch { }
        return [pscustomobject]@{
            Mode   = "gui_unavailable"
            Reason = ("GUI fout: {0}{1}" -f $_.Exception.Message, $position)
        }
    }
}

if (-not (Test-Path -LiteralPath $AlbumsRoot)) {
    throw "AlbumsRoot bestaat niet: $AlbumsRoot"
}

$existing = Load-ExistingSelection $OutputPath
$existingSet = New-Object System.Collections.Generic.HashSet[string]
foreach ($entry in @($existing)) {
    $normalized = Normalize-PhotoSrc ([string]$entry.src)
    if ($normalized) {
        [void]$existingSet.Add($normalized)
    }
}

if ($existingSet.Count -gt 0) {
    Write-Host ""
    Write-Host ("Huidige portfolio selectie: {0} foto's" -f $existingSet.Count) -ForegroundColor Cyan
    $existing |
        ForEach-Object {
            $albumValue = ""
            if ($null -ne $_.albumTitle -and [string]$_.albumTitle) {
                $albumValue = [string]$_.albumTitle
            } elseif ($null -ne $_.album -and [string]$_.album) {
                $albumValue = [string]$_.album
            }
            [pscustomobject]@{
                Album = $albumValue
                Src   = (Normalize-PhotoSrc ([string]$_.src))
            }
        } |
        Where-Object { $_.Src } |
        Sort-Object Album, Src |
        Group-Object Album |
        ForEach-Object {
            Write-Host ("- {0} ({1})" -f $_.Name, $_.Count) -ForegroundColor DarkCyan
            $_.Group | ForEach-Object { Write-Host ("  {0}" -f $_.Src) -ForegroundColor DarkGray }
        }
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "Huidige portfolio selectie: (leeg)" -ForegroundColor DarkGray
    Write-Host ""
}

$albumIndexFiles = Get-ChildItem -LiteralPath $AlbumsRoot -Directory |
    ForEach-Object { Join-Path $_.FullName "index.html" } |
    Where-Object { Test-Path -LiteralPath $_ }

$items = New-Object System.Collections.Generic.List[object]

foreach ($indexPath in $albumIndexFiles) {
    $fileInfo = Get-Item -LiteralPath $indexPath
    if ($fileInfo.Length -le 0) {
        continue
    }

    $albumSlug = Split-Path -Leaf (Split-Path -Parent $indexPath)
    $albumPath = Normalize-AlbumPath $albumSlug

    $html = Get-Content -LiteralPath $indexPath -Raw

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

$hasOutGridView = $null -ne (Get-Command Out-GridView -ErrorAction SilentlyContinue)
$selected = @()
$guiResult = $null
$guiError = ""

try {
    $guiResult = Show-ThumbnailPicker -items $items -existingSet $existingSet
} catch {
    $details = ""
    try {
        $details = $_ | Format-List * -Force | Out-String
    } catch {
        $details = $_.Exception.ToString()
    }
    $guiError = $details
}

if ($guiResult -and $guiResult.Mode -eq "gui") {
    if ($guiResult.Cancelled) {
        Write-Host ""
        Write-Host "Geannuleerd. Er is niets aangepast." -ForegroundColor Yellow
        return
    }
    $selected = @($guiResult.Items)
} elseif ($guiResult -and $guiResult.Mode -eq "gui_unavailable") {
    Write-Host ""
    Write-Host ("Preview picker kon niet starten: {0}" -f ([string]$guiResult.Reason)) -ForegroundColor Yellow
    Write-Host "Tip: gebruik start-portfolio-selection.cmd (dit start de juiste PowerShell host)." -ForegroundColor DarkGray
} elseif ($hasOutGridView) {
    if ($guiError) {
        Write-Host ""
        Write-Host "Preview picker crashte en valt terug op Out-GridView. Details:" -ForegroundColor Yellow
        Write-Host $guiError -ForegroundColor DarkYellow
    }
    $selected = $items |
        Sort-Object @{ Expression = "selected"; Descending = $true }, "albumTitle", "src" |
        Select-Object selected, albumTitle, album, page, src, alt |
        Out-GridView -Title "Selecteer portfolio foto's en klik OK" -PassThru
} else {
    $albums = $items | Group-Object albumTitle | Sort-Object Name
    Write-Host ""
    Write-Host "Out-GridView is niet beschikbaar. Console selectie wordt gebruikt." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Albums:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $albums.Count; $i += 1) {
        $idx = $i + 1
        Write-Host ("[{0}] {1} ({2})" -f $idx, $albums[$i].Name, $albums[$i].Count)
    }

    $albumInput = Read-Host "Kies album nummers (bijv. 1,3-4) of 'all'"
    $albumIndexes = Parse-IndexList $albumInput $albums.Count
    if ($albumIndexes.Count -eq 0) {
        throw "Geen albums geselecteerd."
    }

    $pool = New-Object System.Collections.Generic.List[object]
    foreach ($idx in $albumIndexes) {
        $pool.AddRange($albums[$idx - 1].Group)
    }

    $pool = $pool | Sort-Object albumTitle, src
    Write-Host ""
    Write-Host ("Foto's in selectiepool: {0}" -f $pool.Count) -ForegroundColor Cyan
    Write-Host "Tip: typ 'all' om alles te selecteren." -ForegroundColor DarkGray
    Write-Host ""

    $preview = $pool | Select-Object -First 25
    for ($i = 0; $i -lt $preview.Count; $i += 1) {
        $idx = $i + 1
        Write-Host ("[{0}] {1}  {2}" -f $idx, $preview[$i].albumTitle, $preview[$i].src)
    }
    if ($pool.Count -gt $preview.Count) {
        Write-Host ("... ({0} meer niet getoond)" -f ($pool.Count - $preview.Count)) -ForegroundColor DarkGray
    }

    $photoInput = Read-Host "Kies foto nummers binnen deze pool (bijv. 1,2,10-25) of 'all'"
    $photoIndexes = Parse-IndexList $photoInput $pool.Count
    if ($photoIndexes.Count -eq 0) {
        throw "Geen foto's geselecteerd."
    }

    $selected = foreach ($idx in ($photoIndexes | Sort-Object)) { $pool[$idx - 1] }
}

$selectedCount = @($selected).Count
if ($selectedCount -eq 0) {
    throw "Geen foto's geselecteerd."
}

$selected = @(
    $selected | ForEach-Object {
        if ($null -eq $_) { return $null }
        if ($_ -is [System.Windows.Forms.ListViewItem]) { return $_.Tag }
        if ($_.psobject.Properties.Match("album").Count -gt 0) { return $_ }
        if ($_.psobject.Properties.Match("Tag").Count -gt 0) { return $_.Tag }
        return $null
    } | Where-Object { $_ -and $_.psobject.Properties.Match("album").Count -gt 0 -and $_.psobject.Properties.Match("src").Count -gt 0 }
)

$selectedCount = @($selected).Count
if ($selectedCount -eq 0) {
    throw "Geen foto's geselecteerd."
}

$outputObject = @{
    version = 1
    items   = @($selected | ForEach-Object {
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

Write-Host ""
Write-Host ("Geschreven: {0}" -f $OutputPath) -ForegroundColor Green
Write-Host ("Aantal geselecteerd: {0}" -f $outputObject.items.Count) -ForegroundColor Green
