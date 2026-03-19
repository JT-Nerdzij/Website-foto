Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Convert-ToSlug {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $normalized = $Value.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder

    foreach ($char in $normalized.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($char)
        }
    }

    $slug = $builder.ToString() -replace "[^a-z0-9]+", "-" -replace "^-|-$", ""
    return ($slug -replace "-{2,}", "-")
}

function Escape-Html {
    param([string]$Value)

    return $Value.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace('"', "&quot;")
}

function Encode-AlbumPath {
    param([string]$Value)

    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Value))
}

function Set-Status {
    param(
        [System.Windows.Forms.Label]$Label,
        [string]$Message,
        [System.Drawing.Color]$Color
    )

    $Label.Text = $Message
    $Label.ForeColor = $Color
}

function Build-AlbumCardMarkup {
    param(
        [string]$PageFileName,
        [string]$FolderName,
        [string]$CoverFileName,
        [string]$AlbumTitle
    )

    return @"
            <div class="card">
                <a href="$(Escape-Html $PageFileName)"><img src="images/$(Escape-Html $FolderName)/$(Escape-Html $CoverFileName)" alt="Something went wrong"></a>
                <a href="$(Escape-Html $PageFileName)"><h2>$(Escape-Html $AlbumTitle)</h2></a>
            </div>

"@
}

function Build-AlbumPageMarkup {
    param(
        [string]$AlbumTitle,
        [string]$FolderName,
        [System.Collections.ArrayList]$ImageEntries
    )

    $cardMarkup = foreach ($entry in $ImageEntries) {
        $imagePath = "images/$FolderName/$($entry.StoredName)"
        $encodedPath = Encode-AlbumPath $imagePath
@"
    <div class="card">
        <img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==" data-encoded-src="$encodedPath" alt="sport foto">
    </div>
"@
    }

    $cards = ($cardMarkup -join "`r`n`r`n")

    return @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>$(Escape-Html $AlbumTitle) - NoordzijMaaktFoto's</title>
    <link rel="stylesheet" href="style-album.css">
</head>

<body>

<header>
    <nav>
        <div class="logo">
            <a href="index.html">
                <img src="images/A7B6644A-5A80-4DDD-BE12-BBC40FE37A35.png" alt="Logo"> 
                NoordzijMaaktFoto's</a>
        </div>
        <input type="checkbox" id="menu-toggle" class="menu-toggle">
        <label for="menu-toggle" class="menu-button">Menu</label>
            <div class="menu">
                <a href="index.html">Home</a>
                <a href="overmij.html">Over mij</a>
                <a href="albums.html"><u>Albums</u></a>
                <a href="social.html">Instagram</a>
                <a href="contact.html">Contact</a>
            </div>
    </nav>
</header>

<div class="container">
    <div class="page-header">
        <h1>$(Escape-Html $AlbumTitle)</h1>
        <a href="albums.html" class="terugknop"><h3>Back</h3></a>
    </div>

<div class="photo-grid">

$cards
</div>
</div>

<footer class="main-footer">
    <div class="footer-container">
        <div class="footer-column brand">
            <div class="footer-logo">
                <img src="images/A7B6644A-5A80-4DDD-BE12-BBC40FE37A35.png" alt="Logo">
                <span>NoordzijMaaktFoto's</span>
                <p>&copy; 2026</p>
            </div>
        </div>

        <div class="footer-column">
            <h3>Navigatie</h3>
            <ul>
                <li><a href="index.html">Home</a></li>
                <li><a href="albums.html">Albums</a></li>
                <li><a href="overmij.html">Over Mij</a></li>
            </ul>
        </div>

        <div class="footer-column">
            <h3>Support</h3>
            <ul>
                <li><a href="contact.html">Contact</a></li>
                <li><a href="social.html">Instagram</a></li>
            </ul>
        </div>
    </div>
</footer>

<script src="album-locks.js"></script>
<script src="album-access.js"></script>
<script src="album-lightbox.js"></script>

</body>
</html>
"@
}

function New-StoredImageName {
    param([string]$OriginalName)

    $extension = [System.IO.Path]::GetExtension($OriginalName).ToLowerInvariant()
    $randomPart = ([guid]::NewGuid().ToString("N")).Substring(0, 20)
    return "img-$randomPart$extension"
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "NoordzijMaaktFoto's - Album Upload"
$form.Size = New-Object System.Drawing.Size(860, 720)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Nieuw album aanmaken"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(24, 20)
$form.Controls.Add($titleLabel)

$infoLabel = New-Object System.Windows.Forms.Label
$infoLabel.Text = "Kies je projectmap, vul de albumgegevens in en selecteer de foto's. Dit paneel maakt daarna automatisch een nieuwe albumpagina en voegt het album toe aan albums.html."
$infoLabel.AutoSize = $false
$infoLabel.Size = New-Object System.Drawing.Size(790, 48)
$infoLabel.Location = New-Object System.Drawing.Point(24, 58)
$form.Controls.Add($infoLabel)

$projectPathBox = New-Object System.Windows.Forms.TextBox
$projectPathBox.ReadOnly = $true
$projectPathBox.Size = New-Object System.Drawing.Size(600, 30)
$projectPathBox.Location = New-Object System.Drawing.Point(24, 120)
$projectPathBox.Text = $projectRoot
$form.Controls.Add($projectPathBox)

$pickProjectButton = New-Object System.Windows.Forms.Button
$pickProjectButton.Text = "Kies projectmap"
$pickProjectButton.Size = New-Object System.Drawing.Size(170, 34)
$pickProjectButton.Location = New-Object System.Drawing.Point(640, 118)
$form.Controls.Add($pickProjectButton)

$projectStatus = New-Object System.Windows.Forms.Label
$projectStatus.Text = "Huidige map: $projectRoot"
$projectStatus.AutoSize = $true
$projectStatus.Location = New-Object System.Drawing.Point(24, 160)
$form.Controls.Add($projectStatus)

$albumTitleLabel = New-Object System.Windows.Forms.Label
$albumTitleLabel.Text = "Albumtitel"
$albumTitleLabel.AutoSize = $true
$albumTitleLabel.Location = New-Object System.Drawing.Point(24, 205)
$form.Controls.Add($albumTitleLabel)

$albumTitleBox = New-Object System.Windows.Forms.TextBox
$albumTitleBox.Size = New-Object System.Drawing.Size(380, 30)
$albumTitleBox.Location = New-Object System.Drawing.Point(24, 228)
$form.Controls.Add($albumTitleBox)

$albumFileLabel = New-Object System.Windows.Forms.Label
$albumFileLabel.Text = "Bestandsnaam pagina"
$albumFileLabel.AutoSize = $true
$albumFileLabel.Location = New-Object System.Drawing.Point(432, 205)
$form.Controls.Add($albumFileLabel)

$albumFileBox = New-Object System.Windows.Forms.TextBox
$albumFileBox.Size = New-Object System.Drawing.Size(380, 30)
$albumFileBox.Location = New-Object System.Drawing.Point(432, 228)
$form.Controls.Add($albumFileBox)

$albumFolderLabel = New-Object System.Windows.Forms.Label
$albumFolderLabel.Text = "Naam fotomap"
$albumFolderLabel.AutoSize = $true
$albumFolderLabel.Location = New-Object System.Drawing.Point(24, 276)
$form.Controls.Add($albumFolderLabel)

$albumFolderBox = New-Object System.Windows.Forms.TextBox
$albumFolderBox.Size = New-Object System.Drawing.Size(380, 30)
$albumFolderBox.Location = New-Object System.Drawing.Point(24, 299)
$form.Controls.Add($albumFolderBox)

$selectImagesButton = New-Object System.Windows.Forms.Button
$selectImagesButton.Text = "Kies foto's"
$selectImagesButton.Size = New-Object System.Drawing.Size(170, 34)
$selectImagesButton.Location = New-Object System.Drawing.Point(432, 297)
$form.Controls.Add($selectImagesButton)

$coverLabel = New-Object System.Windows.Forms.Label
$coverLabel.Text = "Omslagfoto voor albums.html"
$coverLabel.AutoSize = $true
$coverLabel.Location = New-Object System.Drawing.Point(24, 346)
$form.Controls.Add($coverLabel)

$coverComboBox = New-Object System.Windows.Forms.ComboBox
$coverComboBox.DropDownStyle = "DropDownList"
$coverComboBox.Size = New-Object System.Drawing.Size(380, 30)
$coverComboBox.Location = New-Object System.Drawing.Point(24, 369)
$form.Controls.Add($coverComboBox)

$imageListLabel = New-Object System.Windows.Forms.Label
$imageListLabel.Text = "Geselecteerde foto's"
$imageListLabel.AutoSize = $true
$imageListLabel.Location = New-Object System.Drawing.Point(24, 418)
$form.Controls.Add($imageListLabel)

$imageListBox = New-Object System.Windows.Forms.ListBox
$imageListBox.Size = New-Object System.Drawing.Size(788, 150)
$imageListBox.Location = New-Object System.Drawing.Point(24, 442)
$form.Controls.Add($imageListBox)

$resultLabel = New-Object System.Windows.Forms.Label
$resultLabel.Text = "Nog niets uitgevoerd."
$resultLabel.AutoSize = $true
$resultLabel.Location = New-Object System.Drawing.Point(24, 605)
$form.Controls.Add($resultLabel)

$createAlbumButton = New-Object System.Windows.Forms.Button
$createAlbumButton.Text = "Album aanmaken"
$createAlbumButton.Size = New-Object System.Drawing.Size(180, 40)
$createAlbumButton.Location = New-Object System.Drawing.Point(632, 598)
$form.Controls.Add($createAlbumButton)

$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$folderDialog.Description = "Kies de projectmap van je website"
$folderDialog.SelectedPath = $projectRoot

$fileDialog = New-Object System.Windows.Forms.OpenFileDialog
$fileDialog.Multiselect = $true
$fileDialog.Filter = "Afbeeldingen|*.jpg;*.jpeg;*.png;*.webp;*.gif"

$selectedFiles = New-Object System.Collections.ArrayList
$autoUpdateFileName = $true
$autoUpdateFolderName = $true

$albumTitleBox.Add_TextChanged({
    $slug = Convert-ToSlug $albumTitleBox.Text
    if ($autoUpdateFileName) {
        $albumFileBox.Text = if ($slug) { "$slug.html" } else { "" }
    }
    if ($autoUpdateFolderName) {
        $albumFolderBox.Text = $slug
    }
})

$albumFileBox.Add_TextChanged({
    $expected = Convert-ToSlug $albumTitleBox.Text
    $expectedValue = if ($expected) { "$expected.html" } else { "" }
    $autoUpdateFileName = ($albumFileBox.Text -eq "" -or $albumFileBox.Text -eq $expectedValue)
})

$albumFolderBox.Add_TextChanged({
    $expected = Convert-ToSlug $albumTitleBox.Text
    $autoUpdateFolderName = ($albumFolderBox.Text -eq "" -or $albumFolderBox.Text -eq $expected)
})

$pickProjectButton.Add_Click({
    if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $projectPathBox.Text = $folderDialog.SelectedPath
        Set-Status -Label $projectStatus -Message "Geselecteerde map: $($folderDialog.SelectedPath)" -Color ([System.Drawing.Color]::FromArgb(17, 108, 50))
    }
})

$selectImagesButton.Add_Click({
    if ($fileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedFiles.Clear()
        $imageListBox.Items.Clear()
        $coverComboBox.Items.Clear()

        foreach ($fileName in $fileDialog.FileNames) {
            $fileInfo = Get-Item $fileName
            [void]$selectedFiles.Add($fileInfo)
            [void]$imageListBox.Items.Add($fileInfo.Name)
            [void]$coverComboBox.Items.Add($fileInfo.Name)
        }

        if ($coverComboBox.Items.Count -gt 0) {
            $coverComboBox.SelectedIndex = 0
        }

        Set-Status -Label $resultLabel -Message "$($selectedFiles.Count) foto('s) geselecteerd." -Color ([System.Drawing.Color]::Black)
    }
})

$createAlbumButton.Add_Click({
    $albumTitle = $albumTitleBox.Text.Trim()
    $pageFileName = $albumFileBox.Text.Trim()
    $folderName = $albumFolderBox.Text.Trim()
    $coverFileName = [string]$coverComboBox.SelectedItem
    $projectPath = $projectPathBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($albumTitle) -or
        [string]::IsNullOrWhiteSpace($pageFileName) -or
        [string]::IsNullOrWhiteSpace($folderName) -or
        $selectedFiles.Count -eq 0 -or
        [string]::IsNullOrWhiteSpace($coverFileName)) {
        Set-Status -Label $resultLabel -Message "Vul alle velden in en kies minimaal een foto." -Color ([System.Drawing.Color]::FromArgb(162, 45, 45))
        return
    }

    if (-not $pageFileName.EndsWith(".html")) {
        $pageFileName = "$pageFileName.html"
        $albumFileBox.Text = $pageFileName
    }

    $albumsHtmlPath = Join-Path $projectPath "albums.html"
    $imagesPath = Join-Path $projectPath "images"
    $targetImageFolderPath = Join-Path $imagesPath $folderName
    $albumPagePath = Join-Path $projectPath $pageFileName

    if (-not (Test-Path $albumsHtmlPath)) {
        Set-Status -Label $resultLabel -Message "albums.html is niet gevonden in deze map." -Color ([System.Drawing.Color]::FromArgb(162, 45, 45))
        return
    }

    if (Test-Path $albumPagePath) {
        Set-Status -Label $resultLabel -Message "Er bestaat al een pagina met deze bestandsnaam." -Color ([System.Drawing.Color]::FromArgb(162, 45, 45))
        return
    }

    try {
        New-Item -ItemType Directory -Force -Path $targetImageFolderPath | Out-Null

        $imageEntries = New-Object System.Collections.ArrayList
        foreach ($file in $selectedFiles) {
            $entry = [pscustomobject]@{
                SourceName = $file.Name
                SourcePath = $file.FullName
                StoredName = New-StoredImageName -OriginalName $file.Name
            }
            [void]$imageEntries.Add($entry)
            Copy-Item -Path $entry.SourcePath -Destination (Join-Path $targetImageFolderPath $entry.StoredName) -Force
        }

        $albumPageMarkup = Build-AlbumPageMarkup -AlbumTitle $albumTitle -FolderName $folderName -ImageEntries $imageEntries
        [System.IO.File]::WriteAllText($albumPagePath, $albumPageMarkup, [System.Text.Encoding]::UTF8)

        $albumsHtml = [System.IO.File]::ReadAllText($albumsHtmlPath)
        if ($albumsHtml.Contains("href=""$pageFileName""")) {
            throw "Deze album-link bestaat al in albums.html."
        }

        $coverEntry = $imageEntries | Where-Object { $_.SourceName -eq $coverFileName } | Select-Object -First 1
        if (-not $coverEntry) {
            $coverEntry = $imageEntries | Select-Object -First 1
        }

        $cardMarkup = Build-AlbumCardMarkup -PageFileName $pageFileName -FolderName $folderName -CoverFileName $coverEntry.StoredName -AlbumTitle $albumTitle
        $marker = '<div class="grid">'
        if (-not $albumsHtml.Contains($marker)) {
            throw "Ik kon de album-grid in albums.html niet vinden."
        }

        $updatedAlbumsHtml = $albumsHtml.Replace($marker, "$marker`r`n`r`n$cardMarkup")
        [System.IO.File]::WriteAllText($albumsHtmlPath, $updatedAlbumsHtml, [System.Text.Encoding]::UTF8)

        Set-Status -Label $resultLabel -Message "Album succesvol aangemaakt. Vergeet niet je site daarna te uploaden." -Color ([System.Drawing.Color]::FromArgb(17, 108, 50))
        [System.Windows.Forms.MessageBox]::Show(
            "Klaar.`r`n`r`nPagina: $pageFileName`r`nFotomap: images/$folderName`r`nAlbums-overzicht: bijgewerkt",
            "Album aangemaakt",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch {
        Set-Status -Label $resultLabel -Message $_.Exception.Message -Color ([System.Drawing.Color]::FromArgb(162, 45, 45))
    }
})

[void]$form.ShowDialog()
