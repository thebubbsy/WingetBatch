function Parse-WingetShowOutput {
    <#
    .SYNOPSIS
        Internal helper to parse 'winget show' output into a structured hashtable.
    #>
    param(
        [string]$Output,
        [string]$PackageId
    )

    $info = @{
        Id = $PackageId
        Version = $null
        Publisher = $null
        PublisherName = $null
        PublisherUrl = $null
        PublisherGitHub = $null
        Author = $null
        Homepage = $null
        Description = $null
        Category = $null
        Tags = @()
        License = $null
        LicenseUrl = $null
        Copyright = $null
        CopyrightUrl = $null
        PrivacyUrl = $null
        PackageUrl = $null
        ReleaseNotes = $null
        ReleaseNotesUrl = $null
        Installer = $null
        Pricing = $null
        StoreLicense = $null
        FreeTrial = $null
        AgeRating = $null
        Moniker = $null
    }

    # Optimized parsing: Replace sequential regex matching with O(1) string operations and switch
    # This significantly reduces CPU usage when parsing many packages in parallel
    foreach ($line in $Output -split "`n") {
        $colonIndex = $line.IndexOf(':')

        if ($colonIndex -gt 0) {
            # Extract key and value efficiently
            $key = $line.Substring(0, $colonIndex).Trim()
            $value = $line.Substring($colonIndex + 1).Trim()

            switch ($key) {
                'Version' { $info.Version = $value }
                'Publisher' {
                    $info.PublisherName = $value
                    $info.Publisher = $value
                }
                'Publisher Url' {
                    $info.PublisherUrl = $value
                    # Check if it's a GitHub URL
                    if ($value -match 'github\.com/([^/]+)') {
                        $info.PublisherGitHub = $value
                    }
                }
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
