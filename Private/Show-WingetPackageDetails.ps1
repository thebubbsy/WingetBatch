function Show-WingetPackageDetails {
    param(
        [string[]]$PackageIds,
        [hashtable]$DetailsMap,
        [array]$FallbackInfo = @(),
        [hashtable]$FallbackMap = @{}
    )

    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "📦 SELECTED PACKAGES - DETAILED INFORMATION" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""

    foreach ($pkgId in $PackageIds) {
        $details = $DetailsMap[$pkgId]
        # Try to find fallback info from the original search results if available
        $pkgInfo = if ($FallbackMap.Count -gt 0) { $FallbackMap[$pkgId] } else { $null }

        if (-not $pkgInfo) {
            $pkgInfo = $FallbackInfo | Where-Object { $_.Name -eq $pkgId -or $_.Id -eq $pkgId } | Select-Object -First 1
        }

        # Determine package name for header
        $pkgName = if ($details.Name) { $details.Name } elseif ($pkgInfo.Name) { $pkgInfo.Name } else { $null }
        $headerText = if ($pkgName -and $pkgName -ne $pkgId) { "$pkgName ($pkgId)" } else { $pkgId }

        Write-Host "▶ " -ForegroundColor Yellow -NoNewline
        Write-Host " $headerText " -ForegroundColor White -BackgroundColor DarkBlue
        Write-Host ""

        # Description (The "blurb")
        if ($details.Description) {
            Write-Host "  ℹ️  Description: " -ForegroundColor DarkGray -NoNewline
            Write-Host $details.Description -ForegroundColor Gray
            Write-Host ""
        }

        # --- Basic Info ---
        # Version
        if ($details.Version -or ($pkgInfo -and $pkgInfo.Version)) {
            Write-Host "  🔖 Version:     " -ForegroundColor DarkGray -NoNewline
            $ver = if ($details.Version) { $details.Version } else { $pkgInfo.Version }
            Write-Host $ver -ForegroundColor Green
        }

        # Source
        if ($pkgInfo -and $pkgInfo.Source -and $pkgInfo.Source -ne "Unknown") {
            Write-Host "  💾 Source:      " -ForegroundColor DarkGray -NoNewline
            $sColor = if ($pkgInfo.Source -match 'msstore') { "Magenta" } else { "Cyan" }
            Write-Host $pkgInfo.Source -ForegroundColor $sColor
        }

        # Category
        if ($details.Category) {
            Write-Host "  📂 Category:    " -ForegroundColor DarkGray -NoNewline
            Write-Host $details.Category -ForegroundColor Cyan
        }

        # Source
        if ($pkgInfo -and $pkgInfo.Source) {
            Write-Host "  💾 Source:      " -ForegroundColor DarkGray -NoNewline
            $sColor = "Cyan"
            if ($pkgInfo.Source -match 'msstore') { $sColor = "Magenta" }
            Write-Host $pkgInfo.Source -ForegroundColor $sColor
        }

        # Pricing & Free Trial
        if ($details.Pricing) {
            Write-Host "  💰 Pricing:     " -ForegroundColor DarkGray -NoNewline
            Write-Host $details.Pricing -ForegroundColor Green -NoNewline

            if ($details.FreeTrial) {
                Write-Host " (Free Trial Available)" -ForegroundColor Green
            } else {
                Write-Host ""
            }
        }

        # Age Rating
        if ($details.AgeRating) {
            Write-Host "  🔞 Age Rating:  " -ForegroundColor DarkGray -NoNewline
            Write-Host $details.AgeRating -ForegroundColor White
        }

        Write-Host ""

        # --- Publisher Info ---
        # Publisher
        if ($details.PublisherName -or $details.Publisher) {
            Write-Host "  🏢 Publisher:   " -ForegroundColor DarkGray -NoNewline
            $pub = if ($details.PublisherName) { $details.PublisherName } else { $details.Publisher }
            Write-Host $pub -ForegroundColor White
        }

        # Author
        if ($details.Author) {
            Write-Host "  👤 Author:      " -ForegroundColor DarkGray -NoNewline
            Write-Host $details.Author -ForegroundColor White
        }

        # Copyright
        if ($details.Copyright) {
            Write-Host "  ©️  Copyright:   " -ForegroundColor DarkGray -NoNewline
            Write-Host $details.Copyright -ForegroundColor Gray
        }

        if ($details.PublisherName -or $details.Publisher -or $details.Author -or $details.Copyright) {
             Write-Host ""
        }

        # --- Tech Info ---
        # Installer Type & Moniker
        if ($details.Installer) {
            Write-Host "  💿 Installer:   " -ForegroundColor DarkGray -NoNewline
            Write-Host $details.Installer -ForegroundColor Cyan -NoNewline
            if ($details.Moniker) {
                Write-Host " (command: " -ForegroundColor DarkGray -NoNewline
                Write-Host $details.Moniker -ForegroundColor Yellow -NoNewline
                Write-Host ")" -ForegroundColor DarkGray
            }
            Write-Host ""
        }

        # Tags
        if ($details.Tags -and $details.Tags.Count -gt 0) {
            Write-Host "  🏷️  Tags:        " -ForegroundColor DarkGray -NoNewline
            Write-Host ($details.Tags -join ", ") -ForegroundColor Yellow
            Write-Host ""
        }

        # --- Links ---
        $links = [System.Collections.Generic.List[PSCustomObject]]::new()
        if ($details.Homepage) { $links.Add([PSCustomObject]@{ Label="Homepage"; Url=$details.Homepage; Color="Blue" }) }
        if ($details.PublisherGitHub) { $links.Add([PSCustomObject]@{ Label="Source"; Url=$details.PublisherGitHub; Color="Magenta" }) }
        elseif ($details.PublisherUrl) { $links.Add([PSCustomObject]@{ Label="Publisher"; Url=$details.PublisherUrl; Color="Blue" }) }

        if ($details.ReleaseNotesUrl) { $links.Add([PSCustomObject]@{ Label="Release Notes"; Url=$details.ReleaseNotesUrl; Color="Blue" }) }
        if ($details.LicenseUrl) { $links.Add([PSCustomObject]@{ Label="License"; Url=$details.LicenseUrl; Color="Blue" }) }
        if ($details.PrivacyUrl) { $links.Add([PSCustomObject]@{ Label="Privacy"; Url=$details.PrivacyUrl; Color="Blue" }) }
        if ($details.PackageUrl) { $links.Add([PSCustomObject]@{ Label="Package"; Url=$details.PackageUrl; Color="Blue" }) }

        if ($links.Count -gt 0) {
            Write-Host "  🔗 Links:" -ForegroundColor Cyan
            foreach ($link in $links) {
                # Determine icon
                $icon = switch ($link.Label) {
                    "Homepage"      { "🏠" }
                    "Source"        { "💾" }
                    "Publisher"     { "🏢" }
                    "Release Notes" { "📝" }
                    "License"       { "⚖️" }
                    "Privacy"       { "🔒" }
                    "Package"       { "📦" }
                    Default         { "• " }
                }

                # Align manually (max label length + 2)
                $padLen = 15 - $link.Label.Length
                if ($padLen -lt 0) { $padLen = 0 }
                $padding = " " * $padLen
                Write-Host "     $icon $($link.Label):$padding" -ForegroundColor DarkGray -NoNewline
                Write-Host $link.Url -ForegroundColor $link.Color
            }
            Write-Host ""
        }

        # License (Text)
        if ($details.License) {
            Write-Host "  ⚖️  License:     " -ForegroundColor DarkGray -NoNewline
            Write-Host $details.License -ForegroundColor White
            Write-Host ""
        }

        # Installation Command
        Write-Host "  💻 Command:     " -ForegroundColor DarkGray -NoNewline
        Write-Host "winget install --id `"$pkgId`" -e" -ForegroundColor Cyan
        Write-Host ""
    }

    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host ""
}
