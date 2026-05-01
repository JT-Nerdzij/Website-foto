Set-Location -LiteralPath "j:\Own stuff\Testing Site maken INFORMATICA\Test 3"

$navLinks = @(
    @{ href = '/'; label = 'Home' },
    @{ href = '/portfolio/'; label = 'Portfolio' },
    @{ href = '/overmij/'; label = 'Over mij' },
    @{ href = '/albums/'; label = 'Albums' },
    @{ href = '/social/'; label = 'Instagram' },
    @{ href = '/contact/'; label = 'Contact' }
)

Get-ChildItem -Recurse -Filter *.html | ForEach-Object {
    $path = $_.FullName
    $text = Get-Content -LiteralPath $path -Raw

    $activeHref = '/'
    if ($path -match '\\overmij\\index\.html$') { $activeHref = '/overmij/' }
    elseif ($path -match '\\contact\\index\.html$') { $activeHref = '/contact/' }
    elseif ($path -match '\\social\\index\.html$') { $activeHref = '/social/' }
    elseif ($path -match '\\portfolio\\index\.html$') { $activeHref = '/portfolio/' }
    elseif ($path -match '\\albums\\index\.html$') { $activeHref = '/albums/' }
    elseif ($path -match '\\albums\\.*\\index\.html$') { $activeHref = '/albums/' }
    elseif ($path -match '\\index\.html$' -and $path -notmatch '\\.+\\index\.html$') { $activeHref = '/' }

    $links = $navLinks | ForEach-Object {
        $cls = ''
        if ($_.href -eq $activeHref) { $cls = ' class="active"' }
        "                <a href=\"$($_.href)\"$cls>$($_.label)</a>"
    }
    $linksHtml = $links -join "`r`n"

    $newMenu = @"
            <div class="menu">`r`n$linksHtml`r`n        </div>
"@

    $pattern = '<div[^>]*class="menu">.*?</div>'
    if ($text -match $pattern) {
        $newText = [System.Text.RegularExpressions.Regex]::Replace(
            $text,
            $pattern,
            [System.Text.RegularExpressions.Regex]::Escape($newMenu),
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        if ($newText -ne $text) {
            Set-Content -LiteralPath $path -Value $newText
            Write-Host "Updated: $path"
        }
    }
}
