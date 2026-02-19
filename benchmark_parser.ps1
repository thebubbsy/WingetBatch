
$output = @"
Found MongoDB Shell [MongoDB.Shell]
Version: 2.3.2
Publisher: MongoDB, Inc.
Publisher Url: https://www.mongodb.com/
Publisher Support Url: https://www.mongodb.com/support
Author: MongoDB, Inc.
Moniker: mongosh
Description: The MongoDB Shell is the quickest way to connect to, configure, query, and work with your MongoDB database.
Homepage: https://www.mongodb.com/try/download/shell
License: SSPL
License Url: https://www.mongodb.com/licensing/server-side-public-license
Privacy Url: https://www.mongodb.com/legal/privacy-policy
Copyright: Copyright (c) MongoDB, Inc.
Copyright Url: https://www.mongodb.com/legal/copyright
Tags: mongodb, shell, cli, database, nosql
Installer:
  Installer Type: wix
  Installer Url: https://downloads.mongodb.com/compass/mongosh-2.3.2-x64.msi
  Installer SHA256: 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
  Product Code: {12345678-1234-1234-1234-123456789012}
"@

function Parse-Original {
    param($Output)
    $info = @{ Tags = @() }
    foreach ($line in $Output -split "`n") {
        if ($line -match '^\s*Version:\s*(.+)$') { $info.Version = $matches[1].Trim() }
        elseif ($line -match '^\s*Publisher:\s*(.+)$') { $info.Publisher = $matches[1].Trim() }
        elseif ($line -match '^\s*Publisher Url:\s*(.+)$') { $info.PublisherUrl = $matches[1].Trim() }
        elseif ($line -match '^\s*Author:\s*(.+)$') { $info.Author = $matches[1].Trim() }
        elseif ($line -match '^\s*Homepage:\s*(.+)$') { $info.Homepage = $matches[1].Trim() }
        elseif ($line -match '^\s*Description:\s*(.+)$') { $info.Description = $matches[1].Trim() }
        elseif ($line -match '^\s*Category:\s*(.+)$') { $info.Category = $matches[1].Trim() }
        elseif ($line -match '^\s*Tags:\s*(.+)$') { $info.Tags = $matches[1].Trim() -split ',\s*' }
        elseif ($line -match '^\s*License:\s*(.+)$') { $info.License = $matches[1].Trim() }
        elseif ($line -match '^\s*License Url:\s*(.+)$') { $info.LicenseUrl = $matches[1].Trim() }
        elseif ($line -match '^\s*Copyright:\s*(.+)$') { $info.Copyright = $matches[1].Trim() }
        elseif ($line -match '^\s*Copyright Url:\s*(.+)$') { $info.CopyrightUrl = $matches[1].Trim() }
        elseif ($line -match '^\s*Privacy Url:\s*(.+)$') { $info.PrivacyUrl = $matches[1].Trim() }
        elseif ($line -match '^\s*Package Url:\s*(.+)$') { $info.PackageUrl = $matches[1].Trim() }
        elseif ($line -match '^\s*Release Notes:\s*(.+)$') { $info.ReleaseNotes = $matches[1].Trim() }
        elseif ($line -match '^\s*Release Notes Url:\s*(.+)$') { $info.ReleaseNotesUrl = $matches[1].Trim() }
        elseif ($line -match '^\s*Installer Type:\s*(.+)$') { $info.Installer = $matches[1].Trim() }
        elseif ($line -match '^\s*Pricing:\s*(.+)$') { $info.Pricing = $matches[1].Trim() }
        elseif ($line -match '^\s*Store License:\s*(.+)$') { $info.StoreLicense = $matches[1].Trim() }
        elseif ($line -match '^\s*Free Trial:\s*(.+)$') { $info.FreeTrial = $matches[1].Trim() }
        elseif ($line -match '^\s*Age Rating:\s*(.+)$') { $info.AgeRating = $matches[1].Trim() }
        elseif ($line -match '^\s*Moniker:\s*(.+)$') { $info.Moniker = $matches[1].Trim() }
    }
    return $info
}

function Parse-Optimized {
    param($Output)
    $info = @{ Tags = @() }
    foreach ($line in $Output -split "`n") {
        $colonIndex = $line.IndexOf(':')
        if ($colonIndex -gt 0) {
            $key = $line.Substring(0, $colonIndex).Trim()
            $value = $line.Substring($colonIndex + 1).Trim()

            switch ($key) {
                'Version' { $info.Version = $value }
                'Publisher' { $info.Publisher = $value }
                'Publisher Url' { $info.PublisherUrl = $value }
                'Author' { $info.Author = $value }
                'Homepage' { $info.Homepage = $value }
                'Description' { $info.Description = $value }
                'Category' { $info.Category = $value }
                'Tags' { $info.Tags = $value -split ',\s*' }
                'License' { $info.License = $value }
                'License Url' { $info.LicenseUrl = $value }
                'Copyright' { $info.Copyright = $value }
                'Copyright Url' { $info.CopyrightUrl = $value }
                'Privacy Url' { $info.PrivacyUrl = $value }
                'Package Url' { $info.PackageUrl = $value }
                'Release Notes' { $info.ReleaseNotes = $value }
                'Release Notes Url' { $info.ReleaseNotesUrl = $value }
                'Installer Type' { $info.Installer = $value }
                'Pricing' { $info.Pricing = $value }
                'Store License' { $info.StoreLicense = $value }
                'Free Trial' { $info.FreeTrial = $value }
                'Age Rating' { $info.AgeRating = $value }
                'Moniker' { $info.Moniker = $value }
            }
        }
    }
    return $info
}

Write-Host "Warming up..."
for ($i = 0; $i -lt 100; $i++) { $null = Parse-Original $output; $null = Parse-Optimized $output }

Write-Host "Benchmarking Original..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt 10000; $i++) {
    $null = Parse-Original $output
}
$sw.Stop()
Write-Host "Original took: $($sw.ElapsedMilliseconds) ms"

Write-Host "Benchmarking Optimized..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt 10000; $i++) {
    $null = Parse-Optimized $output
}
$sw.Stop()
Write-Host "Optimized took: $($sw.ElapsedMilliseconds) ms"
