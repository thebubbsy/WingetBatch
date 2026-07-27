<#
.SYNOPSIS
    WingetBatch Standalone Script
    
.DESCRIPTION
    This is an automatically generated standalone script containing all the functions
    from the WingetBatch module. You can dot-source this script directly if you don't
    want to install the module.
#>

# Region: Private/ConvertTo-SpectreEscaped.ps1
function ConvertTo-SpectreEscaped {
    <#
    .SYNOPSIS
        Escape special characters for Spectre Console markup.

    .DESCRIPTION
        Internal function to escape brackets so they are rendered literally in Spectre Console.
        [ becomes [[
        ] becomes ]]
    #>
    param(
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    if ($Text.IndexOf('[') -eq -1 -and $Text.IndexOf(']') -eq -1) { return $Text }
    return $Text.Replace('[', '[[').Replace(']', ']]')
}

# EndRegion

# Region: Private/Export-WingetHtmlReport.ps1
function Export-WingetHtmlReport {
    <#
    .SYNOPSIS
        Exports an array of objects to a highly styled, interactive HTML report.

    .DESCRIPTION
        Takes an array of objects, prompts the user for a save location, and generates
        a premium dark-mode HTML file containing all the data with sortable columns
        and a live search filter. Automatically opens the file in the default browser.

    .PARAMETER Data
        The array of custom objects to export.

    .PARAMETER ReportTitle
        The title to display at the top of the report.

    .PARAMETER ReportType
        A short string used for the generated filename (e.g., 'NewPackages').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Data,

        [Parameter(Mandatory=$true)]
        [string]$ReportTitle,

        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    if (-not $Data -or $Data.Count -eq 0) {
        Write-Warning "No data available to export to HTML."
        return
    }

    # Check directory
    $savePath = Split-Path $FilePath
    $filename = Split-Path $FilePath -Leaf
    if (-not $savePath) { $savePath = "." }
    $fullPath = Join-Path $savePath $filename

    Write-Host "Generating HTML report..." -ForegroundColor DarkGray

    # Extract column names from the first object
    $firstItem = $Data[0]
    $properties = if ($firstItem -is [PSCustomObject]) {
        $firstItem.PSObject.Properties.Name
    } elseif ($firstItem -is [Hashtable]) {
        $firstItem.Keys | Sort-Object
    } else {
        $firstItem | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
    }

    # Build Table Headers
    $thHtml = ""
    foreach ($prop in $properties) {
        $thHtml += "<th>$prop</th>`n"
    }

    # Build Table Rows
    $trHtml = ""
    foreach ($item in $Data) {
        $trHtml += "<tr>`n"
        foreach ($prop in $properties) {
            $val = if ($item -is [Hashtable]) { $item[$prop] } else { $item.$prop }
            # Escape HTML
            $escapedVal = [System.Net.WebUtility]::HtmlEncode([string]$val)
            $trHtml += "<td>$escapedVal</td>`n"
        }
        $trHtml += "</tr>`n"
    }

    # HTML Template
    $htmlReport = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$ReportTitle - WingetBatch</title>
    <style>
        :root {
            --bg-base: #09090b;
            --bg-card: rgba(24, 24, 27, 0.6);
            --border: rgba(255, 255, 255, 0.1);
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --accent: #10b981;
            --accent-hover: #059669;
        }
        body {
            background-color: var(--bg-base);
            color: var(--text-main);
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            margin: 0;
            padding: 2rem;
            min-height: 100vh;
            background-image: 
                radial-gradient(circle at 15% 50%, rgba(16, 185, 129, 0.05), transparent 25%),
                radial-gradient(circle at 85% 30%, rgba(56, 189, 248, 0.05), transparent 25%);
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        header {
            display: flex;
            justify-content: space-between;
            align-items: flex-end;
            margin-bottom: 2rem;
            border-bottom: 1px solid var(--border);
            padding-bottom: 1rem;
        }
        h1 {
            margin: 0;
            font-size: 2.5rem;
            font-weight: 700;
            letter-spacing: -0.025em;
            background: linear-gradient(to right, #fff, #94a3b8);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .meta {
            color: var(--text-muted);
            font-size: 0.875rem;
        }
        .controls {
            margin-bottom: 1.5rem;
            display: flex;
            gap: 1rem;
        }
        input[type="text"] {
            flex-grow: 1;
            background: rgba(0,0,0,0.3);
            border: 1px solid var(--border);
            color: var(--text-main);
            padding: 0.75rem 1rem;
            border-radius: 0.5rem;
            font-size: 1rem;
            outline: none;
            transition: border-color 0.2s, box-shadow 0.2s;
        }
        input[type="text"]:focus {
            border-color: var(--accent);
            box-shadow: 0 0 0 1px var(--accent);
        }
        .table-container {
            background: var(--bg-card);
            backdrop-filter: blur(12px);
            -webkit-backdrop-filter: blur(12px);
            border: 1px solid var(--border);
            border-radius: 1rem;
            overflow: auto;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
        }
        table {
            width: 100%;
            border-collapse: collapse;
            text-align: left;
        }
        th {
            background: rgba(255,255,255,0.02);
            color: var(--text-muted);
            font-weight: 600;
            font-size: 0.875rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            padding: 1rem;
            border-bottom: 1px solid var(--border);
            cursor: pointer;
            user-select: none;
            transition: background 0.2s;
        }
        th:hover {
            background: rgba(255,255,255,0.05);
            color: var(--text-main);
        }
        td {
            padding: 1rem;
            border-bottom: 1px solid rgba(255,255,255,0.05);
            font-size: 0.95rem;
            word-break: break-word;
        }
        tr:last-child td {
            border-bottom: none;
        }
        tr:hover td {
            background: rgba(255,255,255,0.02);
        }
        /* Sort indicators */
        th::after {
            content: '';
            display: inline-block;
            margin-left: 0.5rem;
            opacity: 0.3;
        }
        th.asc::after { content: '▲'; opacity: 1; color: var(--accent); }
        th.desc::after { content: '▼'; opacity: 1; color: var(--accent); }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div>
                <h1>$ReportTitle</h1>
                <div class="meta">Generated by WingetBatch • $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))</div>
            </div>
            <div class="meta">$($Data.Count) records found</div>
        </header>

        <div class="controls">
            <input type="text" id="searchInput" placeholder="Search across all fields..." onkeyup="filterTable()">
        </div>

        <div class="table-container">
            <table id="dataTable">
                <thead>
                    <tr>
                        $thHtml
                    </tr>
                </thead>
                <tbody>
                    $trHtml
                </tbody>
            </table>
        </div>
    </div>

    <script>
        // Client-side search filtering
        function filterTable() {
            const input = document.getElementById("searchInput");
            const filter = input.value.toLowerCase();
            const table = document.getElementById("dataTable");
            const tr = table.getElementsByTagName("tr");

            for (let i = 1; i < tr.length; i++) {
                let textValue = tr[i].textContent || tr[i].innerText;
                if (textValue.toLowerCase().indexOf(filter) > -1) {
                    tr[i].style.display = "";
                } else {
                    tr[i].style.display = "none";
                }
            }
        }

        // Client-side column sorting
        const getCellValue = (tr, idx) => tr.children[idx].innerText || tr.children[idx].textContent;
        const comparer = (idx, asc) => (a, b) => ((v1, v2) => 
            v1 !== '' && v2 !== '' && !isNaN(v1) && !isNaN(v2) ? v1 - v2 : v1.toString().localeCompare(v2)
            )(getCellValue(asc ? a : b, idx), getCellValue(asc ? b : a, idx));

        document.querySelectorAll('th').forEach(th => th.addEventListener('click', (() => {
            const table = th.closest('table');
            const tbody = table.querySelector('tbody');
            const asc = th.classList.contains('asc');
            
            // Remove sort classes from all headers
            table.querySelectorAll('th').forEach(el => {
                el.classList.remove('asc', 'desc');
            });
            
            // Add new sort class
            th.classList.add(asc ? 'desc' : 'asc');
            
            Array.from(tbody.querySelectorAll('tr'))
                .sort(comparer(Array.from(th.parentNode.children).indexOf(th), !asc))
                .forEach(tr => tbody.appendChild(tr));
        })));
    </script>
</body>
</html>
"@

    try {
        # Save and Open
        Write-Host "[INFO] Generating HTML report: $FilePath" -ForegroundColor Cyan
        $htmlReport | Out-File -FilePath $FilePath -Encoding UTF8 -Force
        
        if (Test-Path $FilePath) {
            Write-Host "[OK] Report saved successfully." -ForegroundColor Green
            Start-Process $FilePath
        }
    }
    catch {
        Write-Error "Failed to save HTML report: $_"
    }
}



# EndRegion

# Region: Private/Get-GitHubApiRequestCount.ps1
function Get-GitHubApiRequestCount {
    <#
    .SYNOPSIS
        Get current GitHub API request count for this hour.

    .DESCRIPTION
        Returns the number of GitHub API requests made in the current hour.
    #>

    [CmdletBinding()]
    param()

    $rateLimitFile = Join-Path (Get-WingetBatchConfigDir) "github_ratelimit.json"

    if (Test-Path $rateLimitFile) {
        try {
            $rateLimitData = Get-Content $rateLimitFile -Raw | ConvertFrom-Json
            $lastReset = [DateTime]$rateLimitData.LastReset
            $now = Get-Date

            # If more than 1 hour has passed, return 0
            if (($now - $lastReset).TotalHours -ge 1) {
                return 0
            }

            return [int]$rateLimitData.RequestCount
        }
        catch {
            return 0
        }
    }

    return 0
}

# EndRegion

# Region: Private/Get-PackageDetailsCache.ps1
function Get-PackageDetailsCache {
    <#
    .SYNOPSIS
        Retrieve cached package details.

    .DESCRIPTION
        Internal function to get cached package details from JSON file.
        Cache expires after 30 days.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId
    )

    $cacheFile = Join-Path (Get-WingetBatchConfigDir) "package_cache.json"

    if (-not (Test-Path $cacheFile)) {
        return $null
    }

    try {
        $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
        $packageCache = $cache.PSObject.Properties[$PackageId]

        if ($packageCache) {
            $cachedDate = [DateTime]$packageCache.CachedDate
            $daysSinceCached = ((Get-Date) - $cachedDate).TotalDays

            if ($daysSinceCached -lt 30) {
                return $packageCache.Details
            }
        }
    }
    catch {
        # Ignore cache read errors
    }

    return $null
}

# EndRegion

# Region: Private/Get-WingetBatchConfigDir.ps1
function Get-WingetBatchConfigDir {
    <#
    .SYNOPSIS
        Get the configuration directory path.

    .DESCRIPTION
        Internal function to get the path to the .wingetbatch configuration directory.
    #>
    if ($env:USERPROFILE) {
        $homeDir = $env:USERPROFILE
    } else {
        $homeDir = $HOME
    }
    return Join-Path $homeDir ".wingetbatch"
}

# EndRegion

# Region: Private/Get-WingetBatchGitHubToken.ps1
function Get-WingetBatchGitHubToken {
    <#
    .SYNOPSIS
        Retrieve the stored GitHub token.

    .DESCRIPTION
        Internal function to get the stored GitHub token for API authentication.
        Handles both secure CliXml and legacy plaintext formats with automatic migration.

    .OUTPUTS
        String - The GitHub token if found, otherwise $null
    #>

    [CmdletBinding()]
    param()

    $configDir = Get-WingetBatchConfigDir
    $tokenFile = Join-Path $configDir "github_token.clixml"
    $legacyFile = Join-Path $configDir "github_token.txt"

    # 1. Try to load from secure storage
    if (Test-Path $tokenFile) {
        try {
            $SecureToken = Import-Clixml -Path $tokenFile -ErrorAction Stop
            if ($SecureToken -is [System.Security.SecureString]) {
                return [System.Net.NetworkCredential]::new("", $SecureToken).Password
            }
        }
        catch {
            # If clixml is corrupted or not a SecureString, we'll try legacy as fallback
        }
    }

    # 2. Migration: Try legacy plaintext storage
    if (Test-Path $legacyFile) {
        try {
            $Token = (Get-Content $legacyFile -Raw).Trim()
            if (-not [string]::IsNullOrWhiteSpace($Token)) {
                # Silently migrate to secure format
                Set-WingetBatchGitHubToken -Token $Token | Out-Null
                return $Token
            }
        }
        catch {
            return $null
        }
    }

    return $null
}

# EndRegion

# Region: Private/Parse-WingetShowOutput.ps1
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

# EndRegion

# Region: Private/Register-WingetBatchCompleters.ps1
function Register-WingetBatchCompleters {
    <#
    .SYNOPSIS
        Registers tab-completion argument completers for WingetBatch commands.

    .DESCRIPTION
        Internal function called during module import to register PSReadLine-compatible
        argument completers for package IDs, sources, and configuration keys.
    #>

    # Package ID completer - searches installed packages for tab completion
    $packageIdCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        try {
            if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
                Import-Module Microsoft.WinGet.Client -ErrorAction SilentlyContinue
            }

            $installed = Get-WinGetPackage -ErrorAction SilentlyContinue
            if ($installed) {
                $installed |
                    Where-Object { $_.Id -like "$wordToComplete*" } |
                    Select-Object -First 20 -ExpandProperty Id |
                    ForEach-Object {
                        [System.Management.Automation.CompletionResult]::new(
                            "'$_'", $_, 'ParameterValue', $_
                        )
                    }
            }
        } catch {}
    }

    # Package search completer - searches the winget source
    $packageSearchCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        try {
            if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
                Import-Module Microsoft.WinGet.Client -ErrorAction SilentlyContinue
            }

            if ($wordToComplete.Length -ge 2) {
                $results = Microsoft.WinGet.Client\Find-WinGetPackage -Query $wordToComplete -Count 10 -ErrorAction SilentlyContinue
                if ($results) {
                    $results | ForEach-Object {
                        [System.Management.Automation.CompletionResult]::new(
                            "'$($_.Id)'", "$($_.Name) ($($_.Id))", 'ParameterValue', "$($_.Name) - $($_.Id)"
                        )
                    }
                }
            }
        } catch {}
    }

    # Source completer
    $sourceCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        @('winget', 'msstore') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }

    # Config key completer
    $configKeyCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        @('SearchMatchOption', 'UpdateInterval', 'CacheEnabled', 'NotificationsEnabled') |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
    }

    # Register completers for specific command/parameter combinations
    $idCommands = @(
        'Get-WingetPackageInfo'
        'Find-WingetDuplicate'
    )

    foreach ($cmd in $idCommands) {
        Register-ArgumentCompleter -CommandName $cmd -ParameterName 'Id' -ScriptBlock $packageIdCompleter -ErrorAction SilentlyContinue
    }

    Register-ArgumentCompleter -CommandName 'Install-WingetAll' -ParameterName 'Id' -ScriptBlock $packageSearchCompleter -ErrorAction SilentlyContinue
    Register-ArgumentCompleter -CommandName 'Install-WingetAll' -ParameterName 'Source' -ScriptBlock $sourceCompleter -ErrorAction SilentlyContinue
    Register-ArgumentCompleter -CommandName 'Get-WingetPackageInfo' -ParameterName 'Query' -ScriptBlock $packageSearchCompleter -ErrorAction SilentlyContinue
}

# EndRegion

# Region: Private/Set-PackageDetailsCache.ps1
function Set-PackageDetailsCache {
    <#
    .SYNOPSIS
        Store package details in cache.

    .DESCRIPTION
        Internal function to cache package details to JSON file with 30-day TTL.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId,

        [Parameter(Mandatory=$true)]
        [hashtable]$Details
    )

    $configDir = Get-WingetBatchConfigDir
    $cacheFile = Join-Path $configDir "package_cache.json"

    # Create config directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Load existing cache or create new
    $cache = @{}
    if (Test-Path $cacheFile) {
        try {
            $cacheJson = Get-Content $cacheFile -Raw | ConvertFrom-Json
            # Convert PSCustomObject to hashtable
            $cacheJson.PSObject.Properties | ForEach-Object {
                $cache[$_.Name] = $_.Value
            }
        }
        catch {
            # Start fresh if cache is corrupt
        }
    }

    # Add/update package entry
    $cache[$PackageId] = @{
        CachedDate = (Get-Date).ToString('o')
        Details = $Details
    }

    # Save cache
    try {
        $jsonContent = $cache | ConvertTo-Json -Depth 10 -Compress:$false
        [System.IO.File]::WriteAllText($cacheFile, $jsonContent, [System.Text.Encoding]::UTF8)
    }
    catch {
        Write-Verbose "Failed to write package cache: $_"
    }
}

# EndRegion

# Region: Private/Show-WingetPackageDetails.ps1
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

# EndRegion

# Region: Private/Start-PackageDetailJobs.ps1
function Start-PackageDetailJobs {
    param(
        [string[]]$PackageIds,
        [string]$ConfigDir
    )

    $maxConcurrentJobs = 100
    $totalPackages = $PackageIds.Count

    if ($totalPackages -eq 0) { return @(), @{} }

    $packagesPerJob = [Math]::Ceiling($totalPackages / $maxConcurrentJobs)
    if ($packagesPerJob -lt 1) { $packagesPerJob = 1 }

    $actualJobCount = [Math]::Ceiling($totalPackages / $packagesPerJob)

    $jobs = [System.Collections.Generic.List[Object]]::new()
    $jobPackageMap = @{}

    # Resolve winget.exe path for detail fetching (COM API has limited fields)
    $wingetExe = $null
    $testPaths = @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
        "C:\Users\$env:USERNAME\AppData\Local\Microsoft\WindowsApps\winget.exe"
    )
    foreach ($tp in $testPaths) {
        if (Test-Path $tp) { $wingetExe = $tp; break }
    }
    # Also check if winget is in PATH
    if (-not $wingetExe) {
        $cmd = Get-Command winget -ErrorAction SilentlyContinue
        if ($cmd) { $wingetExe = $cmd.Source }
    }

    $jobScript = {
        param($packageList, $cacheDir, $ParseSB, $WingetPath)
        $results = @{}

        # Define Parse-WingetShowOutput in the job scope from the passed script block
        if ($ParseSB) {
            Set-Item -Path function:Parse-WingetShowOutput -Value $ParseSB
        }

        $cacheFile = Join-Path $cacheDir "package_cache.json"
        $localCache = @{}

        # Read cache once at start of job
        if (Test-Path $cacheFile) {
            try {
                $cacheJson = Get-Content $cacheFile -Raw | ConvertFrom-Json
                if ($cacheJson) {
                    $cacheJson.PSObject.Properties | ForEach-Object {
                        $localCache[$_.Name] = $_.Value
                    }
                }
            }
            catch { }
        }

        foreach ($pkgIdItem in $packageList) {
            $packageId = [string]$pkgIdItem
            $cachedInfo = $null

            # Try to get from cache first
            if ($localCache.ContainsKey($packageId)) {
                $entry = $localCache[$packageId]
                if ($entry -and $entry.CachedDate) {
                    try {
                        $cachedDate = [DateTime]$entry.CachedDate
                        $daysSinceCached = ((Get-Date) - $cachedDate).TotalDays

                        if ($daysSinceCached -lt 30) {
                            $cachedInfo = $entry.Details
                        }
                    }
                    catch { }
                }
            }

            if ($cachedInfo) {
                $results[$packageId] = $cachedInfo
                continue
            }

            # Not in cache - try winget.exe for rich details, fall back to COM API for basic info
            $info = $null

            if ($WingetPath -and (Test-Path $WingetPath)) {
                try {
                    $output = & $WingetPath show --id $packageId --no-progress --disable-interactivity 2>&1 | Out-String
                    $info = Parse-WingetShowOutput -Output $output -PackageId $packageId
                }
                catch {
                    # Fall through to COM API
                }
            }

            if (-not $info -or -not $info.Version) {
                # Fallback: Use COM API (limited fields but always works)
                try {
                    Import-Module Microsoft.WinGet.Client -ErrorAction SilentlyContinue
                    $comResult = Find-WinGetPackage -Id $packageId -Exact -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($comResult) {
                        $info = @{
                            Id = $packageId
                            Version = $comResult.Version
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
                            Name = $comResult.Name
                        }
                    }
                }
                catch { }
            }

            if (-not $info) {
                $info = @{ Id = $packageId }
            }

            $results[$packageId] = $info
        }

        return $results
    }

    for ($i = 0; $i -lt $actualJobCount; $i++) {
        $startIndex = $i * $packagesPerJob
        $endIndex = [Math]::Min($startIndex + $packagesPerJob - 1, $totalPackages - 1)
        if ($startIndex -gt $endIndex) { break }

        $packageBatch = $PackageIds[$startIndex..$endIndex]

        $job = Start-WingetBatchJob -ScriptBlock $jobScript -ArgumentList (,$packageBatch), $ConfigDir, $function:Parse-WingetShowOutput, $wingetExe
        $jobs.Add($job)
        $jobPackageMap[$job.Id] = $packageBatch
    }

    return $jobs, $jobPackageMap
}

# EndRegion

# Region: Private/Start-WingetBatchJob.ps1
function Start-WingetBatchJob {
    <#
    .SYNOPSIS
        Internal helper to start a job using Start-ThreadJob if available, otherwise Start-Job.
    #>
    [CmdletBinding()]
    param(
        [ScriptBlock]$ScriptBlock,
        [Object[]]$ArgumentList
    )

    if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
        return Start-ThreadJob -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }
    else {
        return Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }
}

# EndRegion

# Region: Private/Start-WingetUpdateCheck.ps1
function Start-WingetUpdateCheck {
    <#
    .SYNOPSIS
        Internal function that runs the update check and displays notifications.

    .DESCRIPTION
        This function is called automatically from your PowerShell profile.
        It checks if updates are available and displays a notification.
    #>

    [CmdletBinding()]
    param()

    $configDir = Get-WingetBatchConfigDir
    $configFile = Join-Path $configDir "config.json"
    $cacheFile = Join-Path $configDir "update_cache.json"

    # Check if notifications are enabled
    if (-not (Test-Path $configFile)) {
        return
    }

    $config = Get-Content $configFile | ConvertFrom-Json

    if (-not $config.UpdateNotificationsEnabled) {
        return
    }

    # Check if we should run based on interval
    $shouldCheck = $false

    if ($config.CheckOnStartup -and -not $config.LastCheck) {
        $shouldCheck = $true
    }
    elseif ($config.LastCheck) {
        $lastCheck = [DateTime]::Parse($config.LastCheck)
        $hoursSinceCheck = ((Get-Date) - $lastCheck).TotalHours

        if ($config.CheckInterval -gt 0 -and $hoursSinceCheck -ge $config.CheckInterval) {
            $shouldCheck = $true
        }
        elseif ($config.CheckOnStartup) {
            $shouldCheck = $true
        }
    }
    else {
        $shouldCheck = $true
    }

    if (-not $shouldCheck) {
        # Load cached results if available
        if (Test-Path $cacheFile) {
            $cache = Get-Content $cacheFile | ConvertFrom-Json
            if ($cache.UpdateCount -gt 0) {
                Write-Host ""
                Write-Host "📦 " -NoNewline -ForegroundColor Cyan
                Write-Host "$($cache.UpdateCount) winget package update(s) available" -ForegroundColor Yellow
                Write-Host "   Run " -NoNewline -ForegroundColor DarkGray
                Write-Host "Get-WingetUpdates" -NoNewline -ForegroundColor White
                Write-Host " to view and install them" -ForegroundColor DarkGray
            }
        }
        return
    }

    # Run check in background job
    $job = Start-WingetBatchJob -ScriptBlock {
        param($configDir, $cacheFile)

        try {
            # Get list of packages with updates available
            $upgradeOutput = winget upgrade --disable-interactivity 2>&1 | Out-String
            $upgradeLines = $upgradeOutput -split "`n"
            $updatesAvailable = [System.Collections.Generic.List[Object]]::new()

            $headerFound = $false
            foreach ($line in $upgradeLines) {
                if ($line -match '^-+') {
                    $headerFound = $true
                    continue
                }

                if ($headerFound -and $line.Trim() -ne '' -and $line -notmatch 'upgrades available') {
                    # Extract package info
                    if ($line -match '([A-Za-z0-9\.\-_]+\.[A-Za-z0-9\.\-_]+)') {
                        $packageId = $matches[1].Trim()

                        # Try to get version info
                        if ($line -match '<\s*(.+?)\s*>') {
                            $installedVer = $matches[1].Trim()
                        }
                        else {
                            $installedVer = "Unknown"
                        }

                        $updatesAvailable.Add(@{
                            Id = $packageId
                            CurrentVersion = $installedVer
                        })
                    }
                }
            }

            # Save cache
            $cache = @{
                UpdateCount = $updatesAvailable.Count
                Updates = $updatesAvailable
                LastChecked = (Get-Date).ToString('o')
            }

            $cache | ConvertTo-Json | Out-File -FilePath $cacheFile -Encoding UTF8 -Force

            return $updatesAvailable.Count

        }
        catch {
            return -1
        }
    } -ArgumentList $configDir, $cacheFile

    # Update last check time
    $config.LastCheck = (Get-Date).ToString('o')
    $config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8 -Force

    # Wait briefly for job (non-blocking)
    Wait-Job -Job $job -Timeout 10 | Out-Null

    if ($job.State -eq 'Completed') {
        $updateCount = Receive-Job -Job $job

        if ($updateCount -gt 0) {
            Write-Host ""
            Write-Host "📦 " -NoNewline -ForegroundColor Cyan
            Write-Host "$updateCount winget package update(s) available" -ForegroundColor Yellow
            Write-Host "   Run " -NoNewline -ForegroundColor DarkGray
            Write-Host "Get-WingetUpdates" -NoNewline -ForegroundColor White
            Write-Host " to view and install them" -ForegroundColor DarkGray
        }
    }

    Remove-Job -Job $job -Force
}

# EndRegion

# Region: Private/Update-GitHubApiRequestCount.ps1
function Update-GitHubApiRequestCount {
    <#
    .SYNOPSIS
        Track GitHub API requests per hour.

    .DESCRIPTION
        Internal function to track and display GitHub API request usage.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$RequestCount = 1
    )

    $configDir = Get-WingetBatchConfigDir
    $rateLimitFile = Join-Path $configDir "github_ratelimit.json"

    # Create config directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $now = Get-Date

    # Load or create rate limit tracking data
    if (Test-Path $rateLimitFile) {
        try {
            $jsonData = Get-Content $rateLimitFile -Raw | ConvertFrom-Json
            $lastReset = [DateTime]$jsonData.LastReset

            # Reset counter if more than 1 hour has passed
            if (($now - $lastReset).TotalHours -ge 1) {
                $rateLimitData = @{
                    RequestCount = $RequestCount
                    LastReset = $now.ToString('o')
                }
            }
            else {
                # Accumulate requests - ensure we're working with integers
                $currentCount = [int]$jsonData.RequestCount
                $rateLimitData = @{
                    RequestCount = $currentCount + $RequestCount
                    LastReset = $jsonData.LastReset
                }
            }
        }
        catch {
            # If file is corrupt, create new
            $rateLimitData = @{
                RequestCount = $RequestCount
                LastReset = $now.ToString('o')
            }
        }
    }
    else {
        $rateLimitData = @{
            RequestCount = $RequestCount
            LastReset = $now.ToString('o')
        }
    }

    # Save updated data - ensure JSON is written properly
    $jsonContent = $rateLimitData | ConvertTo-Json -Compress:$false
    [System.IO.File]::WriteAllText($rateLimitFile, $jsonContent, [System.Text.Encoding]::UTF8)

    return [PSCustomObject]$rateLimitData
}

# EndRegion

# Region: Public/Disable-WingetUpdateNotifications.ps1
function Disable-WingetUpdateNotifications {
    <#
    .SYNOPSIS
        Disable automatic winget update notifications.

    .DESCRIPTION
        Removes the update check from your PowerShell profile and disables notifications.

    .EXAMPLE
        Disable-WingetUpdateNotifications
        Disables update notifications.
    #>

    [CmdletBinding()]
    param()

    $configDir = Get-WingetBatchConfigDir
    $configFile = Join-Path $configDir "config.json"

    # Update configuration
    if (Test-Path $configFile) {
        $config = Get-Content $configFile | ConvertFrom-Json
        $config.UpdateNotificationsEnabled = $false
        $config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8 -Force
    }

    # Remove from profile
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (Test-Path $profilePath) {
        $profileContent = Get-Content $profilePath -Raw

        # Remove the WingetBatch initialization block
        $pattern = '(?s)# WingetBatch - Update Notifications.*?Start-WingetUpdateCheck\s*\}'
        $newContent = $profileContent -replace $pattern, ''

        $newContent | Out-File -FilePath $profilePath -Encoding UTF8 -Force
    }

    Write-Host "✓ Update notifications disabled" -ForegroundColor Green
    Write-Host "  Restart your terminal for changes to take effect." -ForegroundColor DarkGray
}


# EndRegion

# Region: Public/Enable-WingetUpdateNotifications.ps1
function Enable-WingetUpdateNotifications {
    <#
    .SYNOPSIS
        Enable automatic winget update notifications in your PowerShell profile.

    .DESCRIPTION
        Adds a background check to your PowerShell profile that monitors for winget package updates.
        The check runs when you open a terminal and can optionally run on an interval.

    .PARAMETER Interval
        How often to check for updates (in hours). Default is 3 hours.
        Set to 0 to only check when opening a new terminal.

    .PARAMETER CheckOnStartup
        Check for updates every time you open a terminal. Default is $true.

    .EXAMPLE
        Enable-WingetUpdateNotifications
        Enables update notifications with default settings (check on startup and every 3 hours).

    .EXAMPLE
        Enable-WingetUpdateNotifications -Interval 6
        Check every 6 hours instead of 3.

    .EXAMPLE
        Enable-WingetUpdateNotifications -Interval 0 -CheckOnStartup $true
        Only check when opening a terminal, not on an interval.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Interval = 3,

        [Parameter()]
        [bool]$CheckOnStartup = $true
    )

    $configDir = Get-WingetBatchConfigDir
    $configFile = Join-Path $configDir "config.json"

    # Create config directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Save configuration
    $config = @{
        UpdateNotificationsEnabled = $true
        CheckInterval = $Interval
        CheckOnStartup = $CheckOnStartup
        LastCheck = $null
    }

    $config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8 -Force

    # Add to PowerShell profile
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    $profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue

    $initCode = @'

# WingetBatch - Update Notifications
if (Get-Module -ListAvailable -Name WingetBatch) {
    Import-Module WingetBatch -ErrorAction SilentlyContinue
    Start-WingetUpdateCheck
}
'@

    if ($profileContent -notmatch 'Start-WingetUpdateCheck') {
        Add-Content -Path $profilePath -Value $initCode
        Write-Host "✓ Update notifications enabled!" -ForegroundColor Green
        Write-Host "  Configuration saved to: $configFile" -ForegroundColor DarkGray
        Write-Host "  Profile updated: $profilePath" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Restart your terminal or run: " -NoNewline -ForegroundColor Cyan
        Write-Host ". `$PROFILE" -ForegroundColor Yellow
    }
    else {
        Write-Host "✓ Configuration updated!" -ForegroundColor Green
        Write-Host "  Update notifications were already enabled in your profile." -ForegroundColor DarkGray
    }
}


# EndRegion

# Region: Public/Export-WingetBatchConfig.ps1
function Export-WingetBatchConfig {
    <#
    .SYNOPSIS
        Export WingetBatch configuration and caches.
    
    .DESCRIPTION
        Compresses the user's ~/.wingetbatch directory into a zip archive.
        This includes the GitHub token, rate limits, caches, and general configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    $configDir = Get-WingetBatchConfigDir
    if (Test-Path $configDir) {
        # Ensure path has .zip extension
        if (-not $Path.EndsWith(".zip", [System.StringComparison]::OrdinalIgnoreCase)) {
            $Path = "$Path.zip"
        }
        Compress-Archive -Path "$configDir\*" -DestinationPath $Path -Force
        Write-Host "Exported WingetBatch configuration to $Path" -ForegroundColor Green
    } else {
        Write-Warning "No WingetBatch configuration found to export."
    }
}


# EndRegion

# Region: Public/Find-WingetDuplicate.ps1
function Find-WingetDuplicate {
    <#
    .SYNOPSIS
        Detect duplicate and redundant packages on the system.

    .DESCRIPTION
        Scans all installed winget packages and identifies potential duplicates:
        - Same package installed from multiple sources (winget + msstore)
        - Multiple versions of the same package family (e.g., Python 3.10 + 3.11 + 3.12)
        - Packages with overlapping functionality (same publisher, similar names)

        Helps reclaim disk space and reduce system clutter.

    .PARAMETER IncludeVersions
        Also flag multiple versions of the same package family.

    .PARAMETER ExportHtml
        Generate an HTML report of findings.

    .EXAMPLE
        Find-WingetDuplicate
        Finds packages installed from multiple sources.

    .EXAMPLE
        Find-WingetDuplicate -IncludeVersions
        Also detects multiple versions of the same package.

    .LINK
        https://github.com/thebubbsy/WingetBatch
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeVersions,

        [Parameter()]
        [switch]$ExportHtml
    )

    begin {
        if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch {
                Write-Error "Microsoft.WinGet.Client module is required."
                return
            }
        }
        if (-not (Get-Module -Name PwshSpectreConsole)) {
            if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
                Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
            }
        }
    }

    process {
        Write-Host ""
        Write-Host "  Scanning for duplicate packages..." -ForegroundColor Cyan

        $installed = Get-WinGetPackage -ErrorAction SilentlyContinue
        if (-not $installed -or $installed.Count -eq 0) {
            Write-Host "  No installed packages found." -ForegroundColor Yellow
            return
        }

        Write-Host "  Analyzing $($installed.Count) installed packages..." -ForegroundColor DarkGray

        $duplicates = [System.Collections.Generic.List[PSCustomObject]]::new()
        $versionClusters = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Strategy 1: Same package ID from multiple sources
        $idGroups = $installed | Group-Object -Property Id | Where-Object { $_.Count -gt 1 }
        foreach ($group in $idGroups) {
            $sources = ($group.Group | Select-Object -ExpandProperty Source -Unique) -join ', '
            $duplicates.Add([PSCustomObject]@{
                Type       = 'Multi-Source'
                PackageId  = $group.Name
                Name       = $group.Group[0].Name
                Count      = $group.Count
                Detail     = "Installed from: $sources"
                Versions   = ($group.Group | ForEach-Object { "$($_.Source):$($_.InstalledVersion)" }) -join ', '
            })
        }

        # Strategy 2: Same name, different IDs (potential duplicates)
        $nameGroups = $installed | Where-Object { $_.Name } | Group-Object -Property Name | Where-Object { $_.Count -gt 1 }
        foreach ($group in $nameGroups) {
            $ids = ($group.Group | Select-Object -ExpandProperty Id -Unique)
            if ($ids.Count -gt 1) {
                $duplicates.Add([PSCustomObject]@{
                    Type       = 'Name Collision'
                    PackageId  = ($ids -join ', ')
                    Name       = $group.Name
                    Count      = $group.Count
                    Detail     = "Multiple IDs: $($ids -join ', ')"
                    Versions   = ($group.Group | ForEach-Object { "$($_.Id):$($_.InstalledVersion)" }) -join ', '
                })
            }
        }

        # Strategy 3: Version clusters (same package family, multiple versions)
        if ($IncludeVersions) {
            # Group by package family (e.g., Python.Python.3.x -> Python.Python)
            $familyMap = @{}
            foreach ($pkg in $installed) {
                if (-not $pkg.Id) { continue }
                # Extract family: remove last segment if it looks like a version number
                $parts = $pkg.Id -split '\.'
                $family = $pkg.Id
                if ($parts.Count -ge 3 -and $parts[-1] -match '^\d+$') {
                    $family = ($parts[0..($parts.Count - 2)]) -join '.'
                }

                if (-not $familyMap.ContainsKey($family)) {
                    $familyMap[$family] = [System.Collections.Generic.List[object]]::new()
                }
                $familyMap[$family].Add($pkg)
            }

            foreach ($family in $familyMap.Keys) {
                $members = $familyMap[$family]
                if ($members.Count -gt 1) {
                    $versions = ($members | ForEach-Object { "$($_.Id) (v$($_.InstalledVersion))" }) -join ', '
                    $versionClusters.Add([PSCustomObject]@{
                        Type       = 'Version Cluster'
                        PackageId  = $family
                        Name       = $members[0].Name
                        Count      = $members.Count
                        Detail     = $versions
                        Versions   = ($members | ForEach-Object { $_.InstalledVersion }) -join ', '
                    })
                }
            }
        }

        # Display results
        $totalFindings = $duplicates.Count + $versionClusters.Count

        Write-Host ""
        if ($totalFindings -eq 0) {
            Write-Host "  [OK] No duplicates or redundant packages detected." -ForegroundColor Green
            Write-Host ""
            return
        }

        Write-Host "  Found " -ForegroundColor White -NoNewline
        Write-Host "$totalFindings" -ForegroundColor Yellow -NoNewline
        Write-Host " potential issue(s):" -ForegroundColor White
        Write-Host ""

        # Display duplicates
        if ($duplicates.Count -gt 0) {
            Write-Host "  DUPLICATES" -ForegroundColor Red
            Write-Host "  $('─' * 56)" -ForegroundColor DarkGray

            foreach ($dup in $duplicates) {
                Write-Host "  [$($dup.Type)] " -ForegroundColor Red -NoNewline
                Write-Host $dup.Name -ForegroundColor White -NoNewline
                Write-Host " ($($dup.Count) copies)" -ForegroundColor Gray
                Write-Host "    $($dup.Detail)" -ForegroundColor DarkGray
                Write-Host ""
            }
        }

        # Display version clusters
        if ($versionClusters.Count -gt 0) {
            Write-Host "  VERSION CLUSTERS" -ForegroundColor Yellow
            Write-Host "  $('─' * 56)" -ForegroundColor DarkGray

            foreach ($cluster in $versionClusters) {
                Write-Host "  [$($cluster.Count) versions] " -ForegroundColor Yellow -NoNewline
                Write-Host $cluster.PackageId -ForegroundColor White
                Write-Host "    $($cluster.Detail)" -ForegroundColor DarkGray
                Write-Host ""
            }
        }

        # Recommendations
        Write-Host "  RECOMMENDATIONS" -ForegroundColor Cyan
        Write-Host "  $('─' * 56)" -ForegroundColor DarkGray

        if ($duplicates.Count -gt 0) {
            Write-Host "  - Remove duplicate source installs:" -ForegroundColor White
            foreach ($dup in $duplicates | Where-Object { $_.Type -eq 'Multi-Source' }) {
                Write-Host "    Uninstall-WinGetPackage -Id '$($dup.PackageId)' --Source msstore" -ForegroundColor DarkGray
            }
        }
        if ($versionClusters.Count -gt 0) {
            Write-Host "  - Consider removing old versions you no longer need:" -ForegroundColor White
            foreach ($cluster in $versionClusters) {
                Write-Host "    Review: $($cluster.Detail)" -ForegroundColor DarkGray
            }
        }
        Write-Host ""

        # HTML Export
        if ($ExportHtml) {
            $allFindings = @($duplicates) + @($versionClusters)
            $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
            $exportPath = Join-Path $env:TEMP "WingetBatch_Duplicates_$timestamp.html"

            try {
                Export-WingetHtmlReport -Data $allFindings -ReportTitle "Duplicate Package Analysis" -FilePath $exportPath
                if (Test-Path $exportPath) {
                    Write-Host "  [OK] Report saved: $exportPath" -ForegroundColor Green
                    Invoke-Item $exportPath
                }
            } catch {
                Write-Host "  [FAIL] Could not generate report: $_" -ForegroundColor Red
            }
        }

        # Return structured data for pipeline
        [PSCustomObject]@{
            Duplicates      = $duplicates
            VersionClusters = $versionClusters
            TotalFindings   = $totalFindings
        }
    }
}

# EndRegion

# Region: Public/Get-WingetBatchConfig.ps1
function Get-WingetBatchConfig {
    <#
    .SYNOPSIS
        Retrieve WingetBatch global settings.

    .DESCRIPTION
        Gets the current module-level configuration.

    .EXAMPLE
        Get-WingetBatchConfig
    #>
    [CmdletBinding()]
    param()

    $configPath = Join-Path (Get-WingetBatchConfigDir) "config.json"
    
    if (Test-Path $configPath) {
        Get-Content $configPath -Raw | ConvertFrom-Json
    } else {
        Write-Warning "No configuration found."
    }
}

# EndRegion

# Region: Public/Get-WingetHistory.ps1
function Get-WingetHistory {
    <#
    .SYNOPSIS
        Display package installation history as a timeline.

    .DESCRIPTION
        Reads installation history from the Windows Registry and winget logs to
        display a chronological timeline of package installations, updates, and
        removals on the system.

        Supports filtering by date range, searching by package name, and exporting
        to HTML for audit purposes.

    .PARAMETER Days
        Show history from the last N days. Default: 30.

    .PARAMETER All
        Show all available history (no date filter).

    .PARAMETER Search
        Filter history entries by package name or ID.

    .PARAMETER ExportHtml
        Generate an HTML timeline report.

    .PARAMETER ExportJson
        Output raw history data as JSON for programmatic use.

    .EXAMPLE
        Get-WingetHistory
        Shows installations from the last 30 days.

    .EXAMPLE
        Get-WingetHistory -Days 7
        Shows what was installed in the last week.

    .EXAMPLE
        Get-WingetHistory -Search "python"
        Shows all Python-related installation events.

    .EXAMPLE
        Get-WingetHistory -All -ExportHtml
        Full history exported as an HTML report.

    .LINK
        https://github.com/thebubbsy/WingetBatch
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(1, 3650)]
        [int]$Days = 30,

        [Parameter()]
        [switch]$All,

        [Parameter()]
        [string]$Search,

        [Parameter()]
        [switch]$ExportHtml,

        [Parameter()]
        [switch]$ExportJson
    )

    begin {
        if (-not (Get-Module -Name PwshSpectreConsole)) {
            if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
                Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
            }
        }
    }

    process {
        Write-Host ""
        Write-Host "  Scanning installation history..." -ForegroundColor Cyan

        $history = [System.Collections.Generic.List[PSCustomObject]]::new()
        $cutoffDate = if ($All) { [DateTime]::MinValue } else { (Get-Date).AddDays(-$Days) }

        # Source 1: Windows Registry (Uninstall keys)
        $regPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        foreach ($regPath in $regPaths) {
            $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            foreach ($entry in $entries) {
                if (-not $entry.DisplayName) { continue }
                if (-not $entry.InstallDate) { continue }

                try {
                    $installDate = [DateTime]::ParseExact($entry.InstallDate, 'yyyyMMdd', $null)
                } catch {
                    try { $installDate = [DateTime]::Parse($entry.InstallDate) }
                    catch { continue }
                }

                if ($installDate -lt $cutoffDate) { continue }

                # Apply search filter
                if ($Search) {
                    $matchText = "$($entry.DisplayName) $($entry.Publisher) $($entry.PSChildName)"
                    if ($matchText -notlike "*$Search*") { continue }
                }

                $scope = if ($regPath -like 'HKCU:*') { 'User' } else { 'Machine' }

                $history.Add([PSCustomObject]@{
                    Date        = $installDate
                    Action      = 'Installed'
                    Name        = $entry.DisplayName
                    Version     = if ($entry.DisplayVersion) { $entry.DisplayVersion } else { '' }
                    Publisher   = if ($entry.Publisher) { $entry.Publisher } else { '' }
                    Scope       = $scope
                    Source      = 'Registry'
                    SizeMB      = if ($entry.EstimatedSize) { [Math]::Round($entry.EstimatedSize / 1024, 1) } else { $null }
                })
            }
        }

        # Source 2: Winget log files (if available)
        $wingetLogDir = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir"
        if (Test-Path $wingetLogDir) {
            $logFiles = Get-ChildItem -Path $wingetLogDir -Filter "*.log" -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $cutoffDate } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 20

            foreach ($logFile in $logFiles) {
                try {
                    $logContent = Get-Content $logFile.FullName -Tail 100 -ErrorAction SilentlyContinue
                    foreach ($line in $logContent) {
                        # Parse winget log entries for install/update operations
                        if ($line -match '(\d{4}-\d{2}-\d{2})\s+.*(?:Installing|Updating|Uninstalling)\s+.*?(\S+\.\S+)') {
                            $logDate = [DateTime]::Parse($Matches[1])
                            if ($logDate -lt $cutoffDate) { continue }

                            $action = if ($line -match 'Installing') { 'Installed' }
                                      elseif ($line -match 'Updating') { 'Updated' }
                                      elseif ($line -match 'Uninstalling') { 'Removed' }
                                      else { 'Unknown' }

                            $pkgId = $Matches[2]
                            if ($Search -and $pkgId -notlike "*$Search*") { continue }

                            $history.Add([PSCustomObject]@{
                                Date      = $logDate
                                Action    = $action
                                Name      = $pkgId
                                Version   = ''
                                Publisher = ''
                                Scope     = ''
                                Source    = 'WingetLog'
                                SizeMB    = $null
                            })
                        }
                    }
                } catch {}
            }
        }

        # Sort by date descending
        $history = [System.Collections.Generic.List[PSCustomObject]]($history | Sort-Object Date -Descending)

        if ($history.Count -eq 0) {
            Write-Host "  No installation history found" -ForegroundColor Yellow -NoNewline
            if (-not $All) { Write-Host " in the last $Days days" -ForegroundColor Yellow -NoNewline }
            Write-Host "." -ForegroundColor Yellow
            Write-Host ""
            return
        }

        # JSON export
        if ($ExportJson) {
            $history | ConvertTo-Json -Depth 5
            return
        }

        # Display timeline
        $dateRange = if ($All) { "all time" } else { "last $Days days" }
        Write-Host "  Found " -ForegroundColor White -NoNewline
        Write-Host "$($history.Count)" -ForegroundColor Green -NoNewline
        Write-Host " events ($dateRange)" -ForegroundColor White
        Write-Host ""

        # Group by date for timeline display
        $grouped = $history | Group-Object { $_.Date.ToString('yyyy-MM-dd') } | Sort-Object Name -Descending

        foreach ($dayGroup in $grouped) {
            $dateStr = $dayGroup.Name
            $dayOfWeek = ([DateTime]::Parse($dateStr)).DayOfWeek

            Write-Host "  $dateStr" -ForegroundColor Cyan -NoNewline
            Write-Host " ($dayOfWeek)" -ForegroundColor DarkGray
            Write-Host "  $('─' * 50)" -ForegroundColor DarkGray

            foreach ($event in $dayGroup.Group) {
                $actionColor = switch ($event.Action) {
                    'Installed' { 'Green' }
                    'Updated' { 'Yellow' }
                    'Removed' { 'Red' }
                    default { 'Gray' }
                }
                $actionIcon = switch ($event.Action) {
                    'Installed' { '+' }
                    'Updated' { '~' }
                    'Removed' { '-' }
                    default { '?' }
                }

                Write-Host "    [$actionIcon] " -ForegroundColor $actionColor -NoNewline
                Write-Host $event.Name -ForegroundColor White -NoNewline

                if ($event.Version) {
                    Write-Host " v$($event.Version)" -ForegroundColor Green -NoNewline
                }
                if ($event.Publisher) {
                    Write-Host " ($($event.Publisher))" -ForegroundColor DarkGray -NoNewline
                }
                if ($event.SizeMB) {
                    Write-Host " [$($event.SizeMB) MB]" -ForegroundColor DarkGray -NoNewline
                }
                Write-Host ""
            }
            Write-Host ""
        }

        # Summary stats
        $installCount = ($history | Where-Object { $_.Action -eq 'Installed' }).Count
        $updateCount = ($history | Where-Object { $_.Action -eq 'Updated' }).Count
        $removeCount = ($history | Where-Object { $_.Action -eq 'Removed' }).Count
        $totalSize = ($history | Where-Object { $_.SizeMB } | Measure-Object -Property SizeMB -Sum).Sum

        Write-Host "  Summary: " -ForegroundColor Cyan -NoNewline
        Write-Host "$installCount installed" -ForegroundColor Green -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host "$updateCount updated" -ForegroundColor Yellow -NoNewline
        Write-Host " | " -ForegroundColor DarkGray -NoNewline
        Write-Host "$removeCount removed" -ForegroundColor Red
        if ($totalSize) {
            Write-Host "  Total size: " -ForegroundColor Cyan -NoNewline
            Write-Host "$([Math]::Round($totalSize, 1)) MB" -ForegroundColor White
        }
        Write-Host ""

        # HTML Export
        if ($ExportHtml) {
            $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
            $exportPath = Join-Path $env:TEMP "WingetBatch_History_$timestamp.html"
            try {
                Export-WingetHtmlReport -Data $history -ReportTitle "Installation History ($dateRange)" -FilePath $exportPath
                if (Test-Path $exportPath) {
                    Write-Host "  [OK] Report saved: $exportPath" -ForegroundColor Green
                    Invoke-Item $exportPath
                }
            } catch {
                Write-Host "  [FAIL] Could not generate report: $_" -ForegroundColor Red
            }
        }
    }
}

# EndRegion

# Region: Public/Get-WingetMachineState.ps1
function Get-WingetMachineState {
    <#
    .SYNOPSIS
        Snapshot, compare, and reconcile machine package state.

    .DESCRIPTION
        Captures a complete inventory of all winget-managed packages on the system,
        exports it as a portable state manifest, compares two states for drift detection,
        and can reconcile the current machine to match a target state (install missing,
        optionally remove extraneous packages).

        This enables "Machine-as-Code" workflows: snapshot a golden machine, then
        replicate its package set onto any other Windows machine.

    .PARAMETER Export
        Export the current machine state to a manifest file.

    .PARAMETER Path
        Path to the state manifest file (.json or .yaml).

    .PARAMETER Compare
        Compare the current machine state against a saved manifest and report drift.

    .PARAMETER Reconcile
        Install missing packages and update outdated ones to match the target manifest.

    .PARAMETER RemoveExtraneous
        When used with -Reconcile, also uninstall packages not present in the manifest.

    .PARAMETER Format
        Output format for exported manifests: JSON (default) or YAML.

    .PARAMETER IncludeVersions
        Include specific version pins in the export (default: latest).

    .PARAMETER Source
        Only include packages from a specific source (e.g., winget, msstore).

    .EXAMPLE
        Get-WingetMachineState -Export -Path ".\golden-machine.json"
        Snapshots all installed packages to a JSON manifest.

    .EXAMPLE
        Get-WingetMachineState -Export -Path ".\state.yaml" -Format YAML -IncludeVersions
        Exports with exact version pins in YAML format.

    .EXAMPLE
        Get-WingetMachineState -Compare -Path ".\golden-machine.json"
        Shows what's missing, extra, or outdated vs the golden state.

    .EXAMPLE
        Get-WingetMachineState -Reconcile -Path ".\golden-machine.json"
        Installs all missing packages and updates outdated ones.

    .EXAMPLE
        Get-WingetMachineState -Reconcile -Path ".\golden-machine.json" -RemoveExtraneous
        Full reconciliation: install missing, update outdated, remove extraneous.

    .LINK
        https://github.com/thebubbsy/WingetBatch
    #>

    [CmdletBinding(DefaultParameterSetName = 'Export')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Export')]
        [switch]$Export,

        [Parameter(Mandatory, ParameterSetName = 'Compare')]
        [switch]$Compare,

        [Parameter(Mandatory, ParameterSetName = 'Reconcile')]
        [switch]$Reconcile,

        [Parameter(Mandatory, ParameterSetName = 'Compare')]
        [Parameter(Mandatory, ParameterSetName = 'Reconcile')]
        [Parameter(Mandatory, ParameterSetName = 'Export')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(ParameterSetName = 'Reconcile')]
        [switch]$RemoveExtraneous,

        [Parameter(ParameterSetName = 'Export')]
        [ValidateSet('JSON', 'YAML')]
        [string]$Format = 'JSON',

        [Parameter(ParameterSetName = 'Export')]
        [switch]$IncludeVersions,

        [Parameter(ParameterSetName = 'Export')]
        [string]$Source
    )

    begin {
        # Ensure COM API module
        if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch {
                Write-Error "Microsoft.WinGet.Client module is required. Install-Module Microsoft.WinGet.Client -Force"
                return
            }
        }

        # Ensure PwshSpectreConsole for rich output
        if (-not (Get-Module -Name PwshSpectreConsole)) {
            if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
                Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
            }
        }
    }

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'Export' { Invoke-StateExport }
            'Compare' { Invoke-StateCompare }
            'Reconcile' { Invoke-StateReconcile }
        }
    }

    end {
        function Invoke-StateExport {
            Write-Host ""
            Write-Host "  Capturing machine package state..." -ForegroundColor Cyan

            $installed = Get-WinGetPackage -ErrorAction SilentlyContinue
            if (-not $installed) {
                Write-Error "No installed packages found via COM API."
                return
            }

            # Filter by source if specified
            if ($Source) {
                $installed = $installed | Where-Object { $_.Source -eq $Source }
            }

            $packages = [System.Collections.Generic.List[object]]::new()
            foreach ($pkg in $installed) {
                $entry = [ordered]@{
                    id = $pkg.Id
                }
                if ($IncludeVersions -and $pkg.InstalledVersion) {
                    $entry['version'] = $pkg.InstalledVersion
                } else {
                    $entry['version'] = 'latest'
                }
                if ($pkg.Source) {
                    $entry['source'] = $pkg.Source
                }
                $packages.Add([PSCustomObject]$entry)
            }

            $manifest = [ordered]@{
                _metadata = [ordered]@{
                    generator    = "WingetBatch v$((Get-Module WingetBatch).Version)"
                    created      = (Get-Date).ToString('o')
                    hostname     = $env:COMPUTERNAME
                    username     = $env:USERNAME
                    os_version   = [System.Environment]::OSVersion.VersionString
                    package_count = $packages.Count
                }
                packages = $packages
            }

            # Resolve output path
            $outPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            $outDir = Split-Path $outPath -Parent
            if ($outDir -and -not (Test-Path $outDir)) {
                New-Item -ItemType Directory -Path $outDir -Force | Out-Null
            }

            if ($Format -eq 'YAML') {
                if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
                    Write-Warning "powershell-yaml module not found. Falling back to JSON."
                    $outPath = $outPath -replace '\.ya?ml$', '.json'
                    $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $outPath -Encoding utf8
                } else {
                    Import-Module powershell-yaml -ErrorAction SilentlyContinue
                    $manifest | ConvertTo-Yaml | Out-File -FilePath $outPath -Encoding utf8
                }
            } else {
                $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $outPath -Encoding utf8
            }

            Write-Host ""
            Write-Host "  [OK] " -ForegroundColor Green -NoNewline
            Write-Host "$($packages.Count) packages" -ForegroundColor White -NoNewline
            Write-Host " exported to " -ForegroundColor Green -NoNewline
            Write-Host $outPath -ForegroundColor Cyan
            Write-Host ""
        }

        function Invoke-StateCompare {
            $manifestPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            if (-not (Test-Path $manifestPath)) {
                Write-Error "State manifest not found: $manifestPath"
                return
            }

            Write-Host ""
            Write-Host "  Comparing machine state against manifest..." -ForegroundColor Cyan
            Write-Host "  Manifest: " -ForegroundColor Gray -NoNewline
            Write-Host $manifestPath -ForegroundColor White

            # Parse manifest
            $content = Get-Content -Raw -Path $manifestPath
            if ($manifestPath -match '\.ya?ml$') {
                if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
                    Write-Error "powershell-yaml module required for YAML manifests."
                    return
                }
                Import-Module powershell-yaml
                $manifest = ConvertFrom-Yaml $content
            } else {
                $manifest = $content | ConvertFrom-Json
            }

            $targetPackages = $manifest.packages
            if (-not $targetPackages) {
                Write-Error "No packages found in manifest."
                return
            }

            # Get current state
            $installed = Get-WinGetPackage -ErrorAction SilentlyContinue
            $installedMap = @{}
            foreach ($pkg in $installed) {
                if ($pkg.Id) { $installedMap[$pkg.Id] = $pkg }
            }

            # Build target map
            $targetMap = @{}
            foreach ($pkg in $targetPackages) {
                $targetMap[$pkg.id] = $pkg
            }

            # Classify drift
            $missing = [System.Collections.Generic.List[string]]::new()
            $outdated = [System.Collections.Generic.List[PSCustomObject]]::new()
            $extraneous = [System.Collections.Generic.List[string]]::new()
            $compliant = [System.Collections.Generic.List[string]]::new()

            foreach ($target in $targetPackages) {
                $pkgId = $target.id
                if ($installedMap.ContainsKey($pkgId)) {
                    $inst = $installedMap[$pkgId]
                    if ($inst.IsUpdateAvailable) {
                        $outdated.Add([PSCustomObject]@{
                            Id = $pkgId
                            Installed = $inst.InstalledVersion
                            Available = $inst.AvailableVersion
                        })
                    } else {
                        $compliant.Add($pkgId)
                    }
                } else {
                    $missing.Add($pkgId)
                }
            }

            foreach ($instId in $installedMap.Keys) {
                if (-not $targetMap.ContainsKey($instId)) {
                    $extraneous.Add($instId)
                }
            }

            # Display results
            Write-Host ""
            Write-Host "  Drift Analysis Report" -ForegroundColor White
            Write-Host "  $('=' * 50)" -ForegroundColor DarkGray

            if ($compliant.Count -gt 0) {
                Write-Host "  [OK] Compliant: " -ForegroundColor Green -NoNewline
                Write-Host "$($compliant.Count) packages" -ForegroundColor White
            }
            if ($missing.Count -gt 0) {
                Write-Host "  [!] Missing:   " -ForegroundColor Red -NoNewline
                Write-Host "$($missing.Count) packages" -ForegroundColor White
                foreach ($m in $missing) {
                    Write-Host "       - $m" -ForegroundColor Red
                }
            }
            if ($outdated.Count -gt 0) {
                Write-Host "  [~] Outdated:  " -ForegroundColor Yellow -NoNewline
                Write-Host "$($outdated.Count) packages" -ForegroundColor White
                foreach ($o in $outdated) {
                    Write-Host "       - $($o.Id) ($($o.Installed) -> $($o.Available))" -ForegroundColor Yellow
                }
            }
            if ($extraneous.Count -gt 0) {
                Write-Host "  [+] Extraneous:" -ForegroundColor Magenta -NoNewline
                Write-Host " $($extraneous.Count) packages" -ForegroundColor White
                foreach ($e in $extraneous) {
                    Write-Host "       - $e" -ForegroundColor DarkGray
                }
            }

            Write-Host ""
            $totalDrift = $missing.Count + $outdated.Count
            if ($totalDrift -eq 0) {
                Write-Host "  [OK] Machine is fully compliant with target state." -ForegroundColor Green
            } else {
                Write-Host "  [!] Drift detected: $totalDrift package(s) need attention." -ForegroundColor Yellow
                Write-Host "      Run: Get-WingetMachineState -Reconcile -Path '$Path'" -ForegroundColor DarkGray
            }
            Write-Host ""

            # Return structured object for pipeline use
            [PSCustomObject]@{
                Compliant  = $compliant.Count
                Missing    = $missing
                Outdated   = $outdated
                Extraneous = $extraneous
                IsCompliant = ($totalDrift -eq 0)
            }
        }

        function Invoke-StateReconcile {
            $manifestPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            if (-not (Test-Path $manifestPath)) {
                Write-Error "State manifest not found: $manifestPath"
                return
            }

            Write-Host ""
            Write-Host "  Reconciling machine state to target manifest..." -ForegroundColor Cyan

            # Parse manifest
            $content = Get-Content -Raw -Path $manifestPath
            if ($manifestPath -match '\.ya?ml$') {
                if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
                    Write-Error "powershell-yaml module required for YAML manifests."
                    return
                }
                Import-Module powershell-yaml
                $manifest = ConvertFrom-Yaml $content
            } else {
                $manifest = $content | ConvertFrom-Json
            }

            $targetPackages = $manifest.packages
            if (-not $targetPackages) {
                Write-Error "No packages found in manifest."
                return
            }

            # Get current state
            $installed = Get-WinGetPackage -ErrorAction SilentlyContinue
            $installedMap = @{}
            foreach ($pkg in $installed) {
                if ($pkg.Id) { $installedMap[$pkg.Id] = $pkg }
            }

            # Determine actions needed
            $toInstall = [System.Collections.Generic.List[PSCustomObject]]::new()
            $toUpdate = [System.Collections.Generic.List[PSCustomObject]]::new()
            $toRemove = [System.Collections.Generic.List[string]]::new()

            $targetMap = @{}
            foreach ($target in $targetPackages) {
                $pkgId = $target.id
                $targetMap[$pkgId] = $target

                if ($installedMap.ContainsKey($pkgId)) {
                    $inst = $installedMap[$pkgId]
                    if ($inst.IsUpdateAvailable) {
                        $toUpdate.Add([PSCustomObject]@{ Id = $pkgId; Version = $target.version })
                    }
                } else {
                    $toInstall.Add([PSCustomObject]@{ Id = $pkgId; Version = $target.version })
                }
            }

            if ($RemoveExtraneous) {
                foreach ($instId in $installedMap.Keys) {
                    if (-not $targetMap.ContainsKey($instId)) {
                        $toRemove.Add($instId)
                    }
                }
            }

            $totalActions = $toInstall.Count + $toUpdate.Count + $toRemove.Count
            if ($totalActions -eq 0) {
                Write-Host "  [OK] Machine is already compliant. No actions needed." -ForegroundColor Green
                return
            }

            Write-Host ""
            Write-Host "  Reconciliation Plan:" -ForegroundColor White
            if ($toInstall.Count -gt 0) { Write-Host "    Install: $($toInstall.Count) packages" -ForegroundColor Green }
            if ($toUpdate.Count -gt 0) { Write-Host "    Update:  $($toUpdate.Count) packages" -ForegroundColor Yellow }
            if ($toRemove.Count -gt 0) { Write-Host "    Remove:  $($toRemove.Count) packages" -ForegroundColor Red }
            Write-Host ""

            # Confirm
            $confirmMsg = "Proceed with reconciliation of $totalActions package(s)?"
            if (-not $PSCmdlet.ShouldContinue($confirmMsg, "WingetBatch State Reconciliation")) {
                Write-Host "  Cancelled." -ForegroundColor Yellow
                return
            }

            $successCount = 0
            $failCount = 0

            # Install missing
            foreach ($pkg in $toInstall) {
                Write-Host "  >>> Installing: " -ForegroundColor Green -NoNewline
                Write-Host $pkg.Id -ForegroundColor White
                try {
                    $installArgs = @{ Id = $pkg.Id; ErrorAction = 'Stop' }
                    if ($pkg.Version -and $pkg.Version -ne 'latest') {
                        $installArgs['Version'] = $pkg.Version
                    }
                    Microsoft.WinGet.Client\Install-WinGetPackage @installArgs | Out-Null
                    Write-Host "      [OK]" -ForegroundColor Green
                    $successCount++
                } catch {
                    Write-Host "      [FAIL] $_" -ForegroundColor Red
                    $failCount++
                }
            }

            # Update outdated
            foreach ($pkg in $toUpdate) {
                Write-Host "  >>> Updating: " -ForegroundColor Yellow -NoNewline
                Write-Host $pkg.Id -ForegroundColor White
                try {
                    Microsoft.WinGet.Client\Update-WinGetPackage -Id $pkg.Id -ErrorAction Stop | Out-Null
                    Write-Host "      [OK]" -ForegroundColor Green
                    $successCount++
                } catch {
                    Write-Host "      [FAIL] $_" -ForegroundColor Red
                    $failCount++
                }
            }

            # Remove extraneous
            foreach ($pkgId in $toRemove) {
                Write-Host "  >>> Removing: " -ForegroundColor Red -NoNewline
                Write-Host $pkgId -ForegroundColor White
                try {
                    Microsoft.WinGet.Client\Uninstall-WinGetPackage -Id $pkgId -ErrorAction Stop | Out-Null
                    Write-Host "      [OK]" -ForegroundColor Green
                    $successCount++
                } catch {
                    Write-Host "      [FAIL] $_" -ForegroundColor Red
                    $failCount++
                }
            }

            Write-Host ""
            Write-Host "  $('=' * 50)" -ForegroundColor DarkGray
            Write-Host "  Reconciliation complete: " -ForegroundColor Cyan -NoNewline
            Write-Host "$successCount succeeded" -ForegroundColor Green -NoNewline
            Write-Host ", " -ForegroundColor Gray -NoNewline
            Write-Host "$failCount failed" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })
            Write-Host ""
        }
    }
}

# EndRegion

# Region: Public/Get-WingetNewPackages.ps1
function Get-WingetNewPackages {
    <#
    .SYNOPSIS
        Get recently added NEW packages from the winget repository.

    .DESCRIPTION
        Queries the winget-pkgs GitHub repository to find packages that were recently
        added (not just updated) to the winget library. This function fetches ALL
        commits from the specified time period with no artificial limits.

    .PARAMETER Hours
        Number of hours to look back for new packages. Default is 12 hours.
        Use this for recent checks to conserve API requests.

    .PARAMETER Days
        Number of days to look back for new packages.
        Cannot be used with -Hours parameter.

    .PARAMETER GitHubToken
        Optional GitHub Personal Access Token for authentication.
        If not provided, will use stored token from Set-WingetBatchGitHubToken.

    .PARAMETER ExcludeTerm
        Exclude packages whose names contain this term (case-insensitive).
        Useful for filtering out packages from specific publishers.

    .EXAMPLE
        Get-WingetNewPackages
        Gets all packages added in the last 12 hours (default).

    .EXAMPLE
        Get-WingetNewPackages -Hours 24
        Gets all packages added in the last 24 hours.

    .EXAMPLE
        Get-WingetNewPackages -Days 7
        Gets all packages added in the last 7 days.

    .EXAMPLE
        Get-WingetNewPackages -Days 30
        Gets all packages added in the last 30 days.

    .EXAMPLE
        Get-WingetNewPackages -Days 30 -ExcludeTerm "Microsoft"
        Gets packages from the last 30 days, excluding any with "Microsoft" in the name.

    .LINK
        https://github.com/microsoft/winget-pkgs
    #>

    [CmdletBinding(DefaultParameterSetName='Hours')]
    param(
        [Parameter(ParameterSetName='Hours')]
        [int]$Hours = 12,

        [Parameter(ParameterSetName='Days')]
        [int]$Days,

        [Parameter()]
        [string]$GitHubToken,

        [Parameter()]
        [string]$ExcludeTerm,

        [Parameter()]
        [switch]$IWantToLiterallyInstallAllFuckingResults,

        [Parameter()]
        [switch]$ExportHtml,

        [Parameter()]
        [ValidateSet("Default", "Silent", "Interactive")]
        [string]$Mode,

        [Parameter()]
        [ValidateSet("User", "Machine")]
        [string]$Scope,

        [Parameter()]
        [string]$Architecture,

        [Parameter()]
        [string]$Override,

        [Parameter()]
        [string]$Location,

        [Parameter()]
        [switch]$ForceInstall,

        [Parameter()]
        [switch]$SkipDependencies,

        [Parameter()]
        [switch]$AllowHashMismatch
    )

    # Ensure PwshSpectreConsole is available
    if (-not (Get-Module -Name PwshSpectreConsole)) {
        if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
            Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
        }
    }

    # Determine time period
    if ($PSCmdlet.ParameterSetName -eq 'Days') {
        $timeSpan = [TimeSpan]::FromDays($Days)
        $timeDesc = "$Days day$(if ($Days -ne 1) { 's' })"
    }
    else {
        $timeSpan = [TimeSpan]::FromHours($Hours)
        $timeDesc = "$Hours hour$(if ($Hours -ne 1) { 's' })"
    }

    Write-Host "Searching for packages added to winget in the last " -ForegroundColor Cyan -NoNewline
    Write-Host $timeDesc -ForegroundColor Yellow -NoNewline
    Write-Host "..." -ForegroundColor Cyan

    try {
        # Calculate the date threshold
        $since = (Get-Date).Subtract($timeSpan).ToString("yyyy-MM-ddTHH:mm:ssZ")

        $newPackages = [System.Collections.Generic.List[PSCustomObject]]::new()
        $processedPackages = @{}
        $allCommits = [System.Collections.Generic.List[Object]]::new()
        $page = 1
        $perPage = 100

        # Prepare headers with optional GitHub token for higher rate limits
        $headers = @{
            'User-Agent' = 'PowerShell-WingetBatch'
            'Accept' = 'application/vnd.github.v3+json'
        }

        # Try to get stored token if not provided
        if (-not $GitHubToken) {
            $GitHubToken = Get-WingetBatchGitHubToken
        }

        # Show current API usage before starting
        $currentUsage = Get-GitHubApiRequestCount
        $limit = if ($GitHubToken) { 5000 } else { 60 }

        if ($GitHubToken) {
            $headers['Authorization'] = "Bearer $GitHubToken"
            Write-Host "Using stored GitHub token (5,000 req/hour) - " -ForegroundColor DarkGray -NoNewline
            Write-Host "$currentUsage" -ForegroundColor Cyan -NoNewline
            Write-Host " requests used this hour" -ForegroundColor DarkGray
        }
        else {
            Write-Host "No GitHub token (60 req/hour limit) - " -ForegroundColor DarkGray -NoNewline
            Write-Host "$currentUsage" -ForegroundColor Yellow -NoNewline
            Write-Host " requests used this hour" -ForegroundColor DarkGray
            Write-Host "Tip: Run " -NoNewline -ForegroundColor DarkGray
            Write-Host "New-WingetBatchGitHubToken" -NoNewline -ForegroundColor Yellow
            Write-Host " to avoid rate limits" -ForegroundColor DarkGray
        }

        # Fetch commits with pagination - NO LIMITS!
        Write-Host "Fetching commits from winget-pkgs repository..." -ForegroundColor Cyan

        $apiRequestsMade = 0
        $fetchMore = $true
        while ($fetchMore) {
            $apiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/commits?since=$since&per_page=$perPage&page=$page"

            try {
                $pageCommits = Invoke-RestMethod -Uri $apiUrl -Headers $headers
                $apiRequestsMade++

                if ($pageCommits.Count -eq 0) {
                    $fetchMore = $false
                }
                else {
                    $allCommits.AddRange(@($pageCommits))
                    Write-Host "  Fetched page $page - " -ForegroundColor DarkGray -NoNewline
                    Write-Host "$($allCommits.Count)" -ForegroundColor White -NoNewline
                    Write-Host " commits so far..." -ForegroundColor DarkGray
                    $page++

                    # If we got less than perPage, we're done
                    if ($pageCommits.Count -lt $perPage) {
                        $fetchMore = $false
                    }
                }
            }
            catch {
                Write-Warning "Failed to fetch page $page : $_"
                $fetchMore = $false
            }
        }

        # Update API request counter and get total usage
        $rateLimitData = Update-GitHubApiRequestCount -RequestCount $apiRequestsMade
        $totalUsage = $rateLimitData.RequestCount

        # Show final API usage
        Write-Host ""
        Write-Host "[API] GitHub API: " -ForegroundColor Cyan -NoNewline
        Write-Host "$apiRequestsMade" -ForegroundColor White -NoNewline
        Write-Host " requests made | " -ForegroundColor DarkGray -NoNewline
        Write-Host "$totalUsage" -ForegroundColor $(if ($totalUsage -gt ($limit * 0.8)) { "Red" } elseif ($totalUsage -gt ($limit * 0.5)) { "Yellow" } else { "Green" }) -NoNewline
        Write-Host "/$limit" -ForegroundColor DarkGray -NoNewline
        Write-Host " used this hour" -ForegroundColor DarkGray
        Write-Host ""
                            Write-Host "  - " -ForegroundColor Green -NoNewline
        Write-Host "$($allCommits.Count)" -ForegroundColor White -NoNewline
        Write-Host " commits" -ForegroundColor Green

        if ($allCommits.Count -eq 0) {
            Write-Warning "No commits found in the last $Days days. The winget-pkgs repository might have no recent activity."
            return
        }

        # Analyze commits for new package additions
        Write-Host "`nAnalyzing commits for new package additions..." -ForegroundColor Cyan
        Write-Host ""

        # Process commits directly
        $i = 0
        foreach ($commit in $allCommits) {
            # Null checks
            if (-not $commit.commit -or -not $commit.commit.message) {
                continue
            }

            $message = $commit.commit.message

            # Skip removal/deletion commits, updates, moves, and automatic updates
            if ($message -match '^(Remove|Delete|Deprecat|Update:|New version:|Automatic|Move)') {
                continue
            }

            # Extract package name and version
            $packageName = $null
            $version = $null

            # Pattern 1: "New package: PackageName version X.X.X"
            if ($message -match '^New package:\s*(.+?)\s+version\s+(.+?)(\s+\(#|\s*$)') {
                $packageName = $matches[1].Trim()
                $version = $matches[2].Trim()
            }
            # Pattern 2: "Add: PackageName version X.X.X"
            elseif ($message -match '^Add:\s*(.+?)\s+version\s+(.+?)(\s+\(#|\s*$)') {
                $packageName = $matches[1].Trim()
                $version = $matches[2].Trim()
            }
            # Pattern 3: "PackageName version X.X.X (#PR)"
            elseif ($message -match '^([A-Za-z0-9\.\-_]+)\s+version\s+(.+?)\s+\(#\d+\)') {
                $packageName = $matches[1].Trim()
                $version = $matches[2].Trim()
            }
            # Pattern 4: "PackageName version X.X.X"
            elseif ($message -match '^([A-Za-z0-9\.\-_]+)\s+version\s+(.+?)$') {
                $packageName = $matches[1].Trim()
                $version = $matches[2].Trim()
            }

            if ($packageName -and -not $processedPackages.ContainsKey($packageName)) {
                # Check if package should be excluded
                $shouldExclude = $false
                if ($ExcludeTerm -and $packageName -match [regex]::Escape($ExcludeTerm)) {
                    $shouldExclude = $true
                }

                if (-not $shouldExclude) {
                    try {
                        # Add to list first with placeholder URL
                        $newPackages.Add([PSCustomObject]@{
                            Name = $packageName
                            Version = $version
                            Date = if ($commit.commit.author -and $commit.commit.author.date) { $commit.commit.author.date } else { (Get-Date).ToString('o') }
                            Link = $null  # Will be filled later
                            Message = $message.Split("`n")[0]
                            Author = if ($commit.commit.author -and $commit.commit.author.name) { $commit.commit.author.name } else { "Unknown" }
                            SHA = if ($commit.sha) { $commit.sha.Substring(0, [Math]::Min(7, $commit.sha.Length)) } else { "Unknown" }
                        })
                        $processedPackages[$packageName] = $true
                    }
                    catch {
                        # Skip malformed commits
                    }
                }
            }

            $i++
            if ($i % 100 -eq 0 -or $i -eq $allCommits.Count) {
                $pct = [Math]::Round(($i / $allCommits.Count) * 100)
                Write-Host "`r  Progress: $i / $($allCommits.Count) commits ($pct%)..." -NoNewline -ForegroundColor DarkGray
            }
        }
        Write-Host ""  # New line after progress

        if ($newPackages.Count -eq 0) {
            if ($ExcludeTerm) {
                Write-Warning "No new packages found in the last $timeDesc (after excluding packages with '$ExcludeTerm')."
            }
            else {
                Write-Warning "No new packages found in the last $timeDesc. Try increasing the time period."
            }
            if ($PSCmdlet.ParameterSetName -eq 'Hours') {
                Write-Host "Tip: Try " -NoNewline -ForegroundColor DarkGray
                Write-Host "Get-WingetNewPackages -Days 7" -ForegroundColor Yellow
            }
            return
        }

                            Write-Host "  - " -ForegroundColor Green -NoNewline
        Write-Host "$($newPackages.Count)" -ForegroundColor White -NoNewline
        Write-Host " new package(s)" -NoNewline -ForegroundColor Green
        if ($ExcludeTerm) {
            Write-Host " (excluding '$ExcludeTerm')" -NoNewline -ForegroundColor Yellow
        }
        Write-Host ":" -ForegroundColor Green
        Write-Host ""

        # Display results in a formatted table
        $newPackages | Format-Table -AutoSize -Property @(
            @{Label='Package Name'; Expression={$_.Name}}
            @{Label='Version'; Expression={$_.Version}}
            @{Label='Date Added'; Expression={([DateTime]$_.Date).ToString('yyyy-MM-dd HH:mm')}}
        ) | Out-Host

        # Fetch detailed package info in parallel BEFORE showing selection UI
        Write-Host ""
        Write-Host "[WAIT] Fetching detailed package information in background..." -ForegroundColor DarkGray

        $configDir = Get-WingetBatchConfigDir
        $maxConcurrentJobs = 10
        $allPackageIds = @($newPackages | ForEach-Object { $_.Name })

        # Load cache to reduce API calls and IO
        $cacheFile = Join-Path $configDir "package_cache.json"
        $localCache = @{}
        if (Test-Path $cacheFile) {
            try {
                $json = Get-Content $cacheFile -Raw | ConvertFrom-Json
                if ($json -is [PSCustomObject]) {
                    $json.PSObject.Properties | ForEach-Object { $localCache[$_.Name] = $_.Value }
                }
            } catch {
                Write-Verbose "Failed to load cache: $_"
            }
        }

        # Filter packages to identify what needs fetching
        $packagesToFetchList = [System.Collections.Generic.List[string]]::new()
        $cachedResults = @{}

        foreach ($pkgId in $allPackageIds) {
            $isCached = $false
            if ($localCache.ContainsKey($pkgId)) {
                $entry = $localCache[$pkgId]
                if ($entry.CachedDate) {
                    try {
                        $cachedDate = [DateTime]$entry.CachedDate
                        # Check if fresh (< 30 days)
                        if ((Get-Date) -lt $cachedDate.AddDays(30)) {
                            $cachedResults[$pkgId] = $entry.Details
                            $isCached = $true
                        }
                    } catch {}
                }
            }

            if (-not $isCached) {
                $packagesToFetchList.Add($pkgId)
            }
        }

        $packagesToFetch = $packagesToFetchList.ToArray()
        $totalPackagesToFetch = $packagesToFetch.Count

        $packagesPerJob = if ($totalPackagesToFetch -gt 0) { [Math]::Ceiling($totalPackagesToFetch / $maxConcurrentJobs) } else { 0 }
        $actualJobCount = [Math]::Min($maxConcurrentJobs, $totalPackagesToFetch)

        $jobs = [System.Collections.Generic.List[Object]]::new()
        $jobPackageMap = @{}

        if ($cachedResults.Count -gt 0) {
            Write-Host "[OK] Found $($cachedResults.Count) packages in cache" -ForegroundColor Green
        }

        # Resolve winget.exe path for detail fetching
        $wingetExe = $null
        $testPaths = @(
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
            "C:\Users\$env:USERNAME\AppData\Local\Microsoft\WindowsApps\winget.exe"
        )
        foreach ($tp in $testPaths) {
            if (Test-Path $tp) { $wingetExe = $tp; break }
        }
        if (-not $wingetExe) {
            $cmd = Get-Command winget -ErrorAction SilentlyContinue
            if ($cmd) { $wingetExe = $cmd.Source }
        }

        for ($i = 0; $i -lt $actualJobCount; $i++) {
            $startIndex = $i * $packagesPerJob
            $endIndex = [Math]::Min($startIndex + $packagesPerJob - 1, $totalPackagesToFetch - 1)
            $packageBatch = $packagesToFetch[$startIndex..$endIndex]

            $job = Start-WingetBatchJob -ScriptBlock {
                param($packageList, $cacheDir, $ParseSB, $WingetPath)
                $results = @{}

                # Define Parse-WingetShowOutput in the job scope from the passed script block
                if ($ParseSB) {
                    Set-Item -Path function:Parse-WingetShowOutput -Value $ParseSB
                }

                foreach ($packageId in $packageList) {
                    $info = $null

                    # Try winget.exe for rich details
                    if ($WingetPath -and (Test-Path $WingetPath)) {
                        try {
                            $output = & $WingetPath show --id $packageId --no-progress --disable-interactivity 2>&1 | Out-String
                            $info = Parse-WingetShowOutput -Output $output -PackageId $packageId
                        }
                        catch { }
                    }

                    # Fallback: COM API (limited fields)
                    if (-not $info -or -not $info.Version) {
                        try {
                            Import-Module Microsoft.WinGet.Client -ErrorAction SilentlyContinue
                            $comResult = Find-WinGetPackage -Id $packageId -Exact -ErrorAction SilentlyContinue | Select-Object -First 1
                            if ($comResult) {
                                $info = @{
                                    Id = $packageId
                                    Version = $comResult.Version
                                    Name = $comResult.Name
                                    Publisher = $null
                                    PublisherName = $null
                                    Homepage = $null
                                    Description = $null
                                    Tags = @()
                                    License = $null
                                }
                            }
                        }
                        catch { }
                    }

                    if (-not $info) {
                        $info = @{ Id = $packageId }
                    }

                    $results[$packageId] = $info
                }

                return $results
            } -ArgumentList (,$packageBatch), $configDir, $function:Parse-WingetShowOutput, $wingetExe

            $jobs.Add($job)
            $jobPackageMap[$job.Id] = $packageBatch
        }

        Write-Host "   Started $actualJobCount background jobs processing $totalPackagesToFetch packages..." -ForegroundColor DarkGray
        Write-Host "   (~$packagesPerJob packages per job)" -ForegroundColor DarkGray

        if ($ExportHtml) {
            Write-Host "
[HTML] Exporting HTML report..." -ForegroundColor Cyan
            $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
            $defaultPath = "C:\temp\WingetBatch_New Packages_$timestamp.html".Replace(' ', '_')
            $exportPath = Read-Host "Enter path for HTML report [Default: $defaultPath]"
            if (-not $exportPath) { $exportPath = $defaultPath }
            if (-not $exportPath.EndsWith(".html")) { $exportPath += ".html" }
            
            try {
                Export-WingetHtmlReport -Data $newPackages -ReportTitle "New Packages" -FilePath $exportPath
                if (Test-Path $exportPath) {
                    Write-Host "[OK] Report successfully saved to $exportPath" -ForegroundColor Green
                    Invoke-Item $exportPath
                }
            } catch {
                Write-Host "[FAIL] Failed to generate HTML report: $_" -ForegroundColor Red
            }
        }

        # Interactive selection using Spectre Console
        if ($IWantToLiterallyInstallAllFuckingResults -or (Get-Module -Name PwshSpectreConsole)) {
            Write-Host ""

            try {
                # Create choices with package name and version for display
                $choices = $newPackages | ForEach-Object {
                    "$($_.Name) (v$($_.Version))"
                }

                if ($IWantToLiterallyInstallAllFuckingResults) {
                    Write-Host "Aggressive Install Mode Activated! Selecting ALL packages..." -ForegroundColor Magenta
                    $selectedChoices = $choices
                } else {
                    # Show multi-selection prompt (while jobs run in background)
                    $selectedChoices = Read-SpectreMultiSelection -Title "[cyan]Select packages to install (Space to toggle, Enter to confirm)[/]" `
                        -Choices $choices `
                        -PageSize 20 `
                        -Color "Green"
                }

                if ($selectedChoices.Count -gt 0) {
                            Write-Host "  - " -ForegroundColor Green -NoNewline
                    Write-Host "$($selectedChoices.Count)" -ForegroundColor White -NoNewline
                    Write-Host " package(s) for installation" -ForegroundColor Green
                    Write-Host ""

                    # Extract package IDs from the selections (remove version suffix)
                    $packagesToInstall = $selectedChoices | ForEach-Object {
                        if ($_ -match '^(.+?)\s+\(v') {
                            $matches[1]
                        }
                    }

                    # Determine which jobs contain the selected packages
                    Write-Host ""
                    $relevantJobs = [System.Collections.Generic.List[Object]]::new()
                    $irrelevantJobs = [System.Collections.Generic.List[Object]]::new()

                    foreach ($job in $jobs) {
                        $jobPackages = $jobPackageMap[$job.Id]
                        $hasSelectedPackage = $false

                        foreach ($selectedPkg in $packagesToInstall) {
                            if ($jobPackages -contains $selectedPkg) {
                                $hasSelectedPackage = $true
                                break
                            }
                        }

                        if ($hasSelectedPackage) {
                            $relevantJobs.Add($job)
                        }
                        else {
                            $irrelevantJobs.Add($job)
                        }
                    }

                    # Only wait for jobs that contain selected packages
                    $runningRelevantJobs = @($relevantJobs | Where-Object { $_.State -eq 'Running' })

                    if ($runningRelevantJobs.Count -gt 0) {
                        Write-Host "[WAIT] Waiting for $($runningRelevantJobs.Count) background jobs with selected packages..." -ForegroundColor DarkGray
                        $timeout = 30
                        $runningRelevantJobs | Wait-Job -Timeout $timeout | Out-Null
                    }
                    else {
                        Write-Host "[OK] Selected package details already fetched!" -ForegroundColor Green
                    }

                    # Stop irrelevant jobs immediately (user doesn't need them)
                    if ($irrelevantJobs.Count -gt 0) {
                        Write-Host "   Stopping $($irrelevantJobs.Count) irrelevant jobs..." -ForegroundColor DarkGray
                        $irrelevantJobs | Stop-Job -ErrorAction SilentlyContinue | Out-Null
                    }

                    # Collect results from relevant jobs only (each job returns a hashtable of multiple packages)
                    $allPackageDetails = @{}

                    # Add cached results first
                    foreach ($key in $cachedResults.Keys) {
                        $allPackageDetails[$key] = $cachedResults[$key]
                    }

                    $newResults = @{}

                    foreach ($job in $relevantJobs) {
                        if ($job.State -eq 'Completed') {
                            $jobResults = Receive-Job -Job $job
                            # Merge job results into master hashtable
                            foreach ($key in $jobResults.Keys) {
                                $allPackageDetails[$key] = $jobResults[$key]
                                $newResults[$key] = $jobResults[$key]
                            }
                        }
                        Remove-Job -Job $job -Force
                    }

                    # Update cache with new results
                    if ($newResults.Count -gt 0) {
                        foreach ($key in $newResults.Keys) {
                            $localCache[[string]$key] = @{
                                CachedDate = (Get-Date).ToString('o')
                                Details = $newResults[$key]
                            }
                        }

                        try {
                            $jsonContent = $localCache | ConvertTo-Json -Depth 10 -Compress:$false
                            [System.IO.File]::WriteAllText($cacheFile, $jsonContent, [System.Text.Encoding]::UTF8)
                        } catch {
                            Write-Verbose "Failed to save cache: $_"
                        }
                    }

                    # Clean up irrelevant jobs
                    foreach ($job in $irrelevantJobs) {
                        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                    }

                    # Fill in any missing selected packages with empty data
                    foreach ($pkgId in $packagesToInstall) {
                        if (-not $allPackageDetails.ContainsKey($pkgId)) {
                            $allPackageDetails[$pkgId] = @{ Id = $pkgId; Homepage = $null }
                        }
                    }

                    # Extract details only for selected packages
                    $packageDetails = @{}
                    foreach ($pkgId in $packagesToInstall) {
                        $packageDetails[$pkgId] = $allPackageDetails[$pkgId]
                    }

                    Write-Host ""

                    Show-WingetPackageDetails -PackageIds $packagesToInstall -DetailsMap $packageDetails -FallbackInfo $newPackages

                    # Ask user what to do next
                    $userChoice = $null
                    if ($IWantToLiterallyInstallAllFuckingResults) {
                        $userChoice = "Install selected packages"
                    }
                    elseif (Get-Module -Name PwshSpectreConsole) {
                        $userChoice = Read-SpectreSelection `
                            -Title "[yellow]What would you like to do?[/]" `
                            -Choices @("Install selected packages", "Go back and change selection", "Cancel") `
                            -Color "Green"
                    }
                    else {
                        Write-Host "Options:" -ForegroundColor Yellow
                        Write-Host "  1) Install selected packages" -ForegroundColor Green
                        Write-Host "  2) Go back and change selection" -ForegroundColor Cyan
                        Write-Host "  3) Cancel" -ForegroundColor Red
                        Write-Host ""
                        $choice = Read-Host "Enter your choice (1-3)"
                        $userChoice = switch ($choice) {
                            "1" { "Install selected packages" }
                            "2" { "Go back and change selection" }
                            "3" { "Cancel" }
                            default { "Install selected packages" }
                        }
                    }

                    if ($userChoice -eq "Go back and change selection") {
                        Write-Host "`nReturning to package selection..." -ForegroundColor Cyan
                        Write-Host ""
                        Write-Host "[!] NOTE: All selections will be cleared when returning to the menu." -ForegroundColor Yellow
                        Write-Host "   You will need to re-select your packages." -ForegroundColor Yellow
                        Write-Host ""
                        Write-Host "Previously selected packages:" -ForegroundColor Cyan
                        foreach ($pkg in $packagesToInstall) {
                            Write-Host "  - " -ForegroundColor Green -NoNewline
                            Write-Host $pkg -ForegroundColor White
                        }
                        Write-Host ""
                        Write-Host "Press any key to continue to selection menu..." -ForegroundColor DarkGray
                        try {
                            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                        }
                        catch {
                            Start-Sleep -Seconds 2
                        }
                        Write-Host ""

                        # Re-run the selection
                        try {
                            $packagesToInstall = Read-SpectreMultiSelection `
                                -Title "[cyan]Select packages to install (Space to select, Enter to confirm)[/]" `
                                -Choices $choices `
                                -PageSize 20 `
                                -Color "Green"

                            if ($packagesToInstall.Count -eq 0) {
                                Write-Host "`nNo packages selected." -ForegroundColor Yellow
                                # Clean up background jobs
                                Write-Host "Cleaning up background jobs..." -ForegroundColor DarkGray
                                $jobs | Stop-Job | Out-Null
                                $jobs | Remove-Job -Force | Out-Null
                                return
                            }

                            # Extract package IDs from selections (remove version suffix)
                            $packagesToInstallIds = $packagesToInstall | ForEach-Object {
                                if ($_ -match '^(.+?)\s+\(v') {
                                    $matches[1]
                                }
                            }

                            Write-Host "  - " -ForegroundColor Green -NoNewline
                            Write-Host "$($packagesToInstallIds.Count)" -ForegroundColor White -NoNewline
                            Write-Host " package(s)" -ForegroundColor Green
                            Write-Host ""

                            # Fetch details for newly selected packages (from cache or jobs)
                            Write-Host "[WAIT] Fetching package details..." -ForegroundColor DarkGray

                            # Load cache once before the loop to avoid repeated I/O
                            $cacheFile = Join-Path $configDir "package_cache.json"
                            $cache = $null
                            if (Test-Path $cacheFile) {
                                try {
                                    $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
                                } catch { }
                            }

                            $reselectedPackageDetails = @{}
                            foreach ($pkgId in $packagesToInstallIds) {
                                # Check if we already have it in packageDetails
                                if ($packageDetails.ContainsKey($pkgId)) {
                                    $reselectedPackageDetails[$pkgId] = $packageDetails[$pkgId]
                                }
                                else {
                                    # Try to get from cache
                                    $cached = $null

                                    if ($null -ne $cache) {
                                        try {
                                            $packageProperty = $cache.PSObject.Properties[$pkgId]
                                            if ($packageProperty) {
                                                $packageCache = $packageProperty.Value
                                                $cachedDate = [DateTime]$packageCache.CachedDate
                                                $daysSinceCached = ((Get-Date) - $cachedDate).TotalDays

                                                if ($daysSinceCached -lt 30) {
                                                    $cached = $packageCache.Details
                                                }
                                            }
                                        } catch { }
                                    }

                                    if ($cached) {
                                        $reselectedPackageDetails[$pkgId] = $cached
                                    }
                                    else {
                                        # Fetch details using resolved winget path or COM API fallback
                                        Write-Host "  Fetching $pkgId..." -ForegroundColor DarkGray
                                        $info = $null

                                        if ($wingetExe -and (Test-Path $wingetExe)) {
                                            try {
                                                $output = & $wingetExe show --id $pkgId --no-progress --disable-interactivity 2>&1 | Out-String
                                                $info = Parse-WingetShowOutput -Output $output -PackageId $pkgId
                                            }
                                            catch { }
                                        }

                                        if (-not $info -or -not $info.Version) {
                                            try {
                                                $comResult = Find-WinGetPackage -Id $pkgId -Exact -ErrorAction SilentlyContinue | Select-Object -First 1
                                                if ($comResult) {
                                                    $info = @{ Id = $pkgId; Version = $comResult.Version; Name = $comResult.Name }
                                                }
                                            }
                                            catch { }
                                        }

                                        if (-not $info) { $info = @{ Id = $pkgId } }

                                        Set-PackageDetailsCache -PackageId $pkgId -Details $info
                                        $reselectedPackageDetails[$pkgId] = $info
                                    }
                                }
                            }

                            $packagesToInstall = $packagesToInstallIds

                            # Re-display detailed info for new selection
                            Write-Host ""
                            Show-WingetPackageDetails -PackageIds $packagesToInstall -DetailsMap $reselectedPackageDetails -FallbackInfo $newPackages

                            # Ask again after re-selection
                            if (Get-Module -Name PwshSpectreConsole) {
                                $userChoice = Read-SpectreSelection `
                                    -Title "[yellow]Proceed with installation?[/]" `
                                    -Choices @("Install selected packages", "Cancel") `
                                    -Color "Green"
                            }
                            else {
                                Write-Host "Press " -NoNewline -ForegroundColor Yellow
                                Write-Host "Enter" -NoNewline -ForegroundColor White
                                Write-Host " to install, or " -NoNewline -ForegroundColor Yellow
                                Write-Host "Ctrl+C" -NoNewline -ForegroundColor Red
                                Write-Host " to cancel..." -ForegroundColor Yellow
                                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                                $userChoice = "Install selected packages"
                            }
                        }
                        catch {
                            Write-Warning "Failed to re-select packages."
                            $userChoice = "Cancel"
                        }
                    }

                    if ($userChoice -eq "Cancel") {
                        Write-Host "`nInstallation cancelled." -ForegroundColor Red
                        # Clean up background jobs
                        Write-Host "Cleaning up background jobs..." -ForegroundColor DarkGray
                        $jobs | Stop-Job | Out-Null
                        $jobs | Remove-Job -Force | Out-Null
                        return
                    }

                    Write-Host ""

                    # Install each selected package
                    Write-Host ("=" * 60) -ForegroundColor Cyan
                    Write-Host "Starting Installation Process" -ForegroundColor Cyan
                    Write-Host ("=" * 60) -ForegroundColor Cyan

                    $successCount = 0
                    $failCount = 0

                    foreach ($packageId in $packagesToInstall) {
                        Write-Host "`n>>> Installing: " -ForegroundColor Magenta -NoNewline
                        Write-Host $packageId -ForegroundColor White

                        try {
                            $installParams = @{
                                Id = $packageId
                                ErrorAction = 'Stop'
                            }
                            if ($PSBoundParameters.ContainsKey('Mode')) { $installParams['Mode'] = $Mode }
                            else { $installParams['Mode'] = 'Silent' } # Maintain default silent update behavior
                            if ($PSBoundParameters.ContainsKey('Scope')) { $installParams['Scope'] = $Scope }
                            if ($PSBoundParameters.ContainsKey('Architecture')) { $installParams['Architecture'] = $Architecture }
                            if ($PSBoundParameters.ContainsKey('Override')) { $installParams['Override'] = $Override }
                            if ($PSBoundParameters.ContainsKey('Location')) { $installParams['Location'] = $Location }
                            if ($ForceInstall) { $installParams['Force'] = $true }
                            if ($SkipDependencies) { $installParams['SkipDependencies'] = $true }
                            if ($AllowHashMismatch) { $installParams['AllowHashMismatch'] = $true }

                            Microsoft.WinGet.Client\Install-WinGetPackage @installParams | Out-Null
                            Write-Host "[OK] Successfully installed " -ForegroundColor Green -NoNewline
                            Write-Host $packageId -ForegroundColor White
                            $successCount++
                        }
                        catch {
                            Write-Host "[FAIL] Failed to install " -ForegroundColor Red -NoNewline
                            Write-Host $packageId -ForegroundColor White -NoNewline
                            Write-Host " ($_)" -ForegroundColor Red
                            $failCount++
                        }
                    }

                    Write-Host "`n" + ("=" * 60) -ForegroundColor Green
                    Write-Host "Installation Complete" -ForegroundColor Green
                    Write-Host ("=" * 60) -ForegroundColor Green
                            Write-Host "  - " -ForegroundColor Green -NoNewline
                    Write-Host $successCount -ForegroundColor White -NoNewline
                    Write-Host " | Failed: " -ForegroundColor Red -NoNewline
                    Write-Host $failCount -ForegroundColor White
                }
                else {
                    Write-Host "`nNo packages selected." -ForegroundColor Yellow
                    # Clean up background jobs since user didn't select anything
                    Write-Host "Cleaning up background jobs..." -ForegroundColor DarkGray
                    $jobs | Stop-Job | Out-Null
                    $jobs | Remove-Job -Force | Out-Null
                }
            }
            catch {
                Write-Warning "Interactive selection unavailable. Use 'winget install <PackageName>' to install."
                # Clean up background jobs on error
                if ($jobs) {
                    $jobs | Stop-Job -ErrorAction SilentlyContinue | Out-Null
                    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }
        else {
            Write-Host "`nTo install a package: " -ForegroundColor Cyan -NoNewline
            Write-Host "winget install " -ForegroundColor White -NoNewline
            Write-Host "<PackageName>" -ForegroundColor Yellow

            Write-Host "Note: Install PwshSpectreConsole for interactive package selection." -ForegroundColor DarkGray

            # Clean up background jobs since interactive selection not available
            if ($jobs) {
                Write-Host "Cleaning up background jobs..." -ForegroundColor DarkGray
                $jobs | Stop-Job -ErrorAction SilentlyContinue | Out-Null
                $jobs | Remove-Job -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
    catch {
        Write-Error "Failed to fetch new packages from GitHub: $_"
        if ($_.Exception.Response.StatusCode -eq 403 -or $_ -match 'rate limit') {
            Write-Host "`nâ”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”" -ForegroundColor Yellow
            Write-Host "[!] GitHub API Rate Limit Exceeded" -ForegroundColor Yellow
            Write-Host "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Unauthenticated requests are limited to 60 per hour." -ForegroundColor White
            Write-Host ""
            Write-Host "To get higher limits (5,000 requests/hour):" -ForegroundColor Cyan
            Write-Host "  1. Run: " -NoNewline -ForegroundColor White
            Write-Host "New-WingetBatchGitHubToken" -ForegroundColor Yellow
            Write-Host "     (Interactive wizard to create and save a token)" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "Or wait an hour and try again with a shorter time period." -ForegroundColor DarkGray
            Write-Host "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”" -ForegroundColor Yellow
        }
    }
}




# EndRegion

# Region: Public/Get-WingetPackageInfo.ps1
function Get-WingetPackageInfo {
    <#
    .SYNOPSIS
        Display rich, detailed information about a winget package.

    .DESCRIPTION
        Shows comprehensive package metadata in a beautiful terminal layout including:
        version info, publisher, license, pricing, install size, dependencies,
        available versions, and direct links. Similar to 'brew info' or 'apt show'.

        Fetches data from both the local COM API and the winget-pkgs GitHub repository
        for maximum detail.

    .PARAMETER Id
        The exact package identifier (e.g., "Git.Git", "Python.Python.3.12").

    .PARAMETER Query
        A search query to find packages (shows top matches with quick info).

    .PARAMETER ShowManifest
        Also display the raw winget manifest YAML from the GitHub repository.

    .PARAMETER ShowVersions
        List all available versions for the package.

    .EXAMPLE
        Get-WingetPackageInfo -Id "Git.Git"
        Shows full details for Git.

    .EXAMPLE
        Get-WingetPackageInfo -Query "visual studio code"
        Searches and shows info for matching packages.

    .EXAMPLE
        Get-WingetPackageInfo -Id "Python.Python.3.12" -ShowVersions
        Shows Python 3.12 info plus all available versions.

    .LINK
        https://github.com/thebubbsy/WingetBatch
    #>

    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByQuery', Position = 0)]
        [string]$Query,

        [Parameter()]
        [switch]$ShowManifest,

        [Parameter()]
        [switch]$ShowVersions
    )

    begin {
        if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch {
                Write-Error "Microsoft.WinGet.Client module is required."
                return
            }
        }
        if (-not (Get-Module -Name PwshSpectreConsole)) {
            if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
                Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
            }
        }
    }

    process {
        # Resolve package
        $package = $null

        if ($PSCmdlet.ParameterSetName -eq 'ByQuery') {
            Write-Host ""
            Write-Host "  Searching for: " -ForegroundColor Cyan -NoNewline
            Write-Host $Query -ForegroundColor Yellow

            $results = Microsoft.WinGet.Client\Find-WinGetPackage -Query $Query -Count 10 -ErrorAction SilentlyContinue
            if (-not $results -or $results.Count -eq 0) {
                Write-Host "  No packages found matching '$Query'" -ForegroundColor Red
                return
            }

            if ($results.Count -eq 1) {
                $package = $results[0]
            } else {
                # Show selection list
                Write-Host ""
                Write-Host "  Multiple matches found:" -ForegroundColor White
                Write-Host ""

                $choices = [System.Collections.Generic.List[string]]::new()
                $choiceMap = @{}
                foreach ($r in $results) {
                    $ver = if ($r.Version) { $r.Version } else { '?' }
                    $display = "$($r.Name) ($($r.Id)) v$ver [$($r.Source)]"
                    $choices.Add($display)
                    $choiceMap[$display] = $r
                }

                if (Get-Module -Name PwshSpectreConsole) {
                    $selected = Read-SpectreSelection -Title "[cyan]Select a package[/]" -Choices $choices -Color "Green"
                    if ($selected) { $package = $choiceMap[$selected] }
                } else {
                    for ($i = 0; $i -lt $choices.Count; $i++) {
                        Write-Host "  [$($i + 1)] " -ForegroundColor Cyan -NoNewline
                        Write-Host $choices[$i] -ForegroundColor White
                    }
                    $idx = Read-Host "  Enter number (1-$($choices.Count))"
                    if ($idx -match '^\d+$' -and [int]$idx -ge 1 -and [int]$idx -le $choices.Count) {
                        $package = $choiceMap[$choices[[int]$idx - 1]]
                    }
                }

                if (-not $package) {
                    Write-Host "  No selection made." -ForegroundColor Yellow
                    return
                }
            }
        } else {
            # Direct ID lookup
            $results = Microsoft.WinGet.Client\Find-WinGetPackage -Id $Id -Count 5 -ErrorAction SilentlyContinue
            if ($results) {
                $package = $results | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
                if (-not $package) { $package = $results[0] }
            }
        }

        if (-not $package) {
            Write-Host "  Package not found: $Id" -ForegroundColor Red
            return
        }

        # Also check if installed locally
        $localPkg = Get-WinGetPackage -Id $package.Id -ErrorAction SilentlyContinue

        # Display rich info
        Write-Host ""
        Write-Host "  $('─' * 56)" -ForegroundColor DarkGray

        # Package name header
        $nameStr = "  $($package.Name)"
        Write-Host $nameStr -ForegroundColor White -NoNewline
        if ($localPkg) {
            Write-Host " [Installed]" -ForegroundColor Green -NoNewline
        }
        Write-Host ""

        Write-Host "  $('─' * 56)" -ForegroundColor DarkGray
        Write-Host ""

        # Core info table
        $infoItems = [ordered]@{
            'Id'            = $package.Id
            'Name'          = $package.Name
            'Version'       = if ($package.Version) { $package.Version } else { 'Unknown' }
            'Source'        = if ($package.Source) { $package.Source } else { 'Unknown' }
        }

        if ($localPkg) {
            $infoItems['Installed Ver'] = if ($localPkg.InstalledVersion) { $localPkg.InstalledVersion } else { 'Unknown' }
            $infoItems['Update Available'] = if ($localPkg.IsUpdateAvailable) { 'Yes' } else { 'No' }
            if ($localPkg.IsUpdateAvailable -and $localPkg.AvailableVersion) {
                $infoItems['Latest Version'] = $localPkg.AvailableVersion
            }
        }

        $infoItems['Publisher'] = if ($package.Publisher) { $package.Publisher } else { 'Unknown' }

        # Calculate max key width for alignment
        $maxKeyLen = ($infoItems.Keys | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum

        foreach ($key in $infoItems.Keys) {
            $paddedKey = $key.PadRight($maxKeyLen + 2)
            $value = $infoItems[$key]
            $color = switch ($key) {
                'Update Available' { if ($value -eq 'Yes') { 'Yellow' } else { 'Green' } }
                'Id' { 'Cyan' }
                default { 'White' }
            }
            Write-Host "  $paddedKey" -ForegroundColor Gray -NoNewline
            Write-Host $value -ForegroundColor $color
        }

        Write-Host ""

        # Fetch extended details from GitHub (manifest) if possible
        if ($ShowManifest -or $ShowVersions) {
            Write-Host "  Fetching extended details from winget-pkgs..." -ForegroundColor DarkGray

            $token = $null
            try { $token = Get-WingetBatchGitHubToken } catch {}

            $headers = @{ 'User-Agent' = 'WingetBatch' }
            if ($token) { $headers['Authorization'] = "Bearer $token" }

            # Try to get the manifest from GitHub
            $packageIdPath = $package.Id -replace '\.', '/'
            $apiUrl = "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/$($packageIdPath.Substring(0,1).ToLower())/$packageIdPath"

            try {
                $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
                if ($response -is [array]) {
                    # Find the installer manifest
                    $installerManifest = $response | Where-Object { $_.name -match '\.installer\.yaml$' } | Select-Object -First 1
                    $localeManifest = $response | Where-Object { $_.name -match '\.locale\.' } | Select-Object -First 1

                    if ($localeManifest) {
                        $localeContent = Invoke-RestMethod -Uri $localeManifest.download_url -Headers $headers -ErrorAction SilentlyContinue
                        if ($localeContent) {
                            # Parse useful fields
                            $lines = $localeContent -split "`n"
                            foreach ($line in $lines) {
                                if ($line -match '^License:\s*(.+)') {
                                    Write-Host "  $('License'.PadRight($maxKeyLen + 2))" -ForegroundColor Gray -NoNewline
                                    Write-Host $Matches[1].Trim() -ForegroundColor White
                                }
                                if ($line -match '^LicenseUrl:\s*(.+)') {
                                    Write-Host "  $('License URL'.PadRight($maxKeyLen + 2))" -ForegroundColor Gray -NoNewline
                                    Write-Host $Matches[1].Trim() -ForegroundColor Cyan
                                }
                                if ($line -match '^PackageUrl:\s*(.+)') {
                                    Write-Host "  $('Homepage'.PadRight($maxKeyLen + 2))" -ForegroundColor Gray -NoNewline
                                    Write-Host $Matches[1].Trim() -ForegroundColor Cyan
                                }
                                if ($line -match '^ShortDescription:\s*(.+)') {
                                    Write-Host "  $('Description'.PadRight($maxKeyLen + 2))" -ForegroundColor Gray -NoNewline
                                    Write-Host $Matches[1].Trim() -ForegroundColor White
                                }
                                if ($line -match '^Moniker:\s*(.+)') {
                                    Write-Host "  $('Moniker'.PadRight($maxKeyLen + 2))" -ForegroundColor Gray -NoNewline
                                    Write-Host $Matches[1].Trim() -ForegroundColor DarkGray
                                }
                                if ($line -match '^- (\w+)$' -and $prevLine -match '^Tags:') {
                                    # Collect tags
                                }
                            }
                        }
                    }

                    if ($ShowVersions) {
                        Write-Host ""
                        Write-Host "  Available Versions:" -ForegroundColor White
                        $versions = $response | Where-Object { $_.type -eq 'dir' } | Select-Object -ExpandProperty name | Sort-Object -Descending
                        if ($versions) {
                            $showCount = [Math]::Min($versions.Count, 15)
                            for ($i = 0; $i -lt $showCount; $i++) {
                                $marker = if ($localPkg -and $localPkg.InstalledVersion -eq $versions[$i]) { ' *' } else { '' }
                                Write-Host "    - $($versions[$i])$marker" -ForegroundColor $(if ($marker) { 'Green' } else { 'Gray' })
                            }
                            if ($versions.Count -gt 15) {
                                Write-Host "    ... and $($versions.Count - 15) more" -ForegroundColor DarkGray
                            }
                        }
                    }

                    if ($ShowManifest -and $installerManifest) {
                        Write-Host ""
                        Write-Host "  Raw Installer Manifest:" -ForegroundColor White
                        Write-Host "  $('─' * 50)" -ForegroundColor DarkGray
                        $manifestContent = Invoke-RestMethod -Uri $installerManifest.download_url -Headers $headers -ErrorAction SilentlyContinue
                        if ($manifestContent) {
                            $manifestLines = ($manifestContent -split "`n") | Select-Object -First 40
                            foreach ($line in $manifestLines) {
                                Write-Host "  $line" -ForegroundColor DarkGray
                            }
                            if (($manifestContent -split "`n").Count -gt 40) {
                                Write-Host "  ... (truncated)" -ForegroundColor DarkGray
                            }
                        }
                    }
                }
            } catch {
                Write-Verbose "Could not fetch extended details from GitHub: $_"
            }
        }

        Write-Host ""
        Write-Host "  $('─' * 56)" -ForegroundColor DarkGray

        # Quick action hints
        Write-Host "  Actions: " -ForegroundColor DarkGray -NoNewline
        if ($localPkg) {
            if ($localPkg.IsUpdateAvailable) {
                Write-Host "Update-WinGetPackage -Id '$($package.Id)'" -ForegroundColor Yellow -NoNewline
            } else {
                Write-Host "Up to date" -ForegroundColor Green -NoNewline
            }
            Write-Host " | Uninstall-WinGetPackage -Id '$($package.Id)'" -ForegroundColor DarkGray
        } else {
            Write-Host "Install-WingetAll -Id '$($package.Id)'" -ForegroundColor Green
        }
        Write-Host ""
    }
}

# EndRegion

# Region: Public/Get-WingetUpdates.ps1
function Get-WingetUpdates {
    <#
    .SYNOPSIS
        Check for and install available winget package updates.

    .DESCRIPTION
        Displays a list of all installed winget packages that have updates available,
        with an interactive selection to choose which ones to update.
        Uses the Microsoft.WinGet.Client COM API for reliable package enumeration.

    .PARAMETER Force
        Skip the cache and force a fresh check for updates.

    .EXAMPLE
        Get-WingetUpdates
        Shows available updates and allows you to select which to install.

    .EXAMPLE
        Get-WingetUpdates -Force
        Forces a fresh check for updates.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$IWantToLiterallyUpdateAllFuckingResults,

        [Parameter()]
        [switch]$ExportHtml,

        [Parameter()]
        [ValidateSet("Default", "Silent", "Interactive")]
        [string]$Mode,

        [Parameter()]
        [ValidateSet("User", "Machine")]
        [string]$Scope,

        [Parameter()]
        [string]$Architecture,

        [Parameter()]
        [string]$Override,

        [Parameter()]
        [string]$Location,

        [Parameter()]
        [switch]$ForceInstall,

        [Parameter()]
        [switch]$SkipDependencies,

        [Parameter()]
        [switch]$AllowHashMismatch
    )

    # Ensure PwshSpectreConsole is available
    if (-not (Get-Module -Name PwshSpectreConsole)) {
        if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
            Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
        }
    }

    # Ensure Microsoft.WinGet.Client is available
    if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
        try {
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        }
        catch {
            Write-Error "Microsoft.WinGet.Client module is required. Install it with: Install-Module Microsoft.WinGet.Client -Force"
            return
        }
    }

    Write-Host "Checking for winget package updates..." -ForegroundColor Cyan

    # Check cache first
    $cacheFile = Join-Path (Get-WingetBatchConfigDir) "update_cache.json"
    $useCache = $false

    if (-not $Force -and (Test-Path $cacheFile)) {
        try {
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
            $cacheAge = ((Get-Date) - [DateTime]::Parse($cache.LastChecked)).TotalMinutes

            if ($cacheAge -lt 30 -and $cache.Updates.Count -gt 0) {
                $useCache = $true
                $updatesAvailable = [System.Collections.Generic.List[Object]]::new()
                foreach ($u in $cache.Updates) {
                    $updatesAvailable.Add($u)
                }
                Write-Host "Using cached results (checked $([Math]::Round($cacheAge, 0)) minutes ago)" -ForegroundColor DarkGray
            }
        }
        catch {
            # Cache is corrupt, ignore
        }
    }

    if (-not $useCache) {
        # Use COM API to get packages with updates available
        Write-Host "Querying installed packages via COM API..." -ForegroundColor DarkGray
        $installed = Get-WinGetPackage -ErrorAction SilentlyContinue
        $updatesAvailable = [System.Collections.Generic.List[Object]]::new()

        foreach ($pkg in $installed) {
            if ($pkg.IsUpdateAvailable) {
                $updatesAvailable.Add(@{
                    Id = $pkg.Id
                    Name = $pkg.Name
                    InstalledVersion = $pkg.Version
                    Source = $pkg.Source
                    DisplayLine = "$($pkg.Name) ($($pkg.Id)) $($pkg.Version)"
                })
            }
        }

        # Save to cache
        try {
            $cacheData = @{
                LastChecked = (Get-Date).ToString('o')
                Updates = @($updatesAvailable)
            } | ConvertTo-Json -Depth 5
            [System.IO.File]::WriteAllText($cacheFile, $cacheData, [System.Text.Encoding]::UTF8)
        }
        catch {
            Write-Verbose "Failed to save update cache: $_"
        }
    }

    if ($updatesAvailable.Count -eq 0) {
        Write-Host "[OK] All packages are up to date!" -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "  - " -ForegroundColor Green -NoNewline
    Write-Host "$($updatesAvailable.Count)" -ForegroundColor White -NoNewline
    Write-Host " update(s) available" -ForegroundColor Green
    Write-Host ""

    # HTML Export
    if ($ExportHtml) {
        Write-Host "`n[HTML] Exporting HTML report..." -ForegroundColor Cyan
        $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $defaultPath = "C:\temp\WingetBatch_Updates_$timestamp.html".Replace(' ', '_')
        $exportPath = Read-Host "Enter path for HTML report [Default: $defaultPath]"
        if (-not $exportPath) { $exportPath = $defaultPath }
        if (-not $exportPath.EndsWith(".html")) { $exportPath += ".html" }

        try {
            Export-WingetHtmlReport -Data $updatesAvailable -ReportTitle "Updates" -FilePath $exportPath
            if (Test-Path $exportPath) {
                Write-Host "[OK] Report successfully saved to $exportPath" -ForegroundColor Green
                Invoke-Item $exportPath
            }
        } catch {
            Write-Host "[FAIL] Failed to generate HTML report: $_" -ForegroundColor Red
        }
    }

    # Interactive selection
    if ($IWantToLiterallyUpdateAllFuckingResults) {
        $selectedPackages = $updatesAvailable | ForEach-Object { $_.Id }
    }
    elseif (Get-Module -Name PwshSpectreConsole) {
        try {
            $displayToId = @{}
            $displayLines = $updatesAvailable | ForEach-Object {
                $display = $_.DisplayLine
                $displayToId[$display] = $_.Id
                $display
            }

            $selectedLines = Read-SpectreMultiSelection -Title "[cyan]Select packages to update (Space to toggle, Enter to confirm)[/]" `
                -Choices $displayLines `
                -PageSize 20 `
                -Color "Green"

            if ($selectedLines.Count -eq 0) {
                Write-Host "No packages selected." -ForegroundColor Yellow
                return
            }

            $selectedPackages = $selectedLines | ForEach-Object { $displayToId[$_] }
        }
        catch {
            Write-Warning "Interactive selection error: $_"
            Write-Host "Packages with updates available:" -ForegroundColor Cyan
            $updatesAvailable | ForEach-Object {
                Write-Host "  - $($_.Id)" -ForegroundColor White
            }
            Write-Host ""
            Write-Host "Use 'Update-WinGetPackage -Id <PackageName>' to update manually." -ForegroundColor Yellow
            return
        }
    }
    else {
        # Fallback without interactive selection
        Write-Host "Packages with updates available:" -ForegroundColor Cyan
        $updatesAvailable | ForEach-Object {
            Write-Host "  - $($_.Id)" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "To update a package: " -ForegroundColor Cyan -NoNewline
        Write-Host "Update-WinGetPackage -Id <PackageName>" -ForegroundColor Yellow
        Write-Host "To update all: " -ForegroundColor Cyan -NoNewline
        Write-Host "Get-WingetUpdates -IWantToLiterallyUpdateAllFuckingResults" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Updating " -ForegroundColor Cyan -NoNewline
    Write-Host "$($selectedPackages.Count)" -ForegroundColor White -NoNewline
    Write-Host " package(s)..." -ForegroundColor Cyan
    Write-Host ""

    $successCount = 0
    $failCount = 0

    foreach ($packageId in $selectedPackages) {
        Write-Host ">>> Updating: " -ForegroundColor Magenta -NoNewline
        Write-Host $packageId -ForegroundColor White

        try {
            $installParams = @{
                Id = $packageId
                ErrorAction = 'Stop'
            }
            if ($PSBoundParameters.ContainsKey('Mode')) { $installParams['Mode'] = $Mode }
            else { $installParams['Mode'] = 'Silent' } # Maintain default silent update behavior
            if ($PSBoundParameters.ContainsKey('Scope')) { $installParams['Scope'] = $Scope }
            if ($PSBoundParameters.ContainsKey('Architecture')) { $installParams['Architecture'] = $Architecture }
            if ($PSBoundParameters.ContainsKey('Override')) { $installParams['Override'] = $Override }
            if ($PSBoundParameters.ContainsKey('Location')) { $installParams['Location'] = $Location }
            if ($ForceInstall) { $installParams['Force'] = $true }
            if ($SkipDependencies) { $installParams['SkipDependencies'] = $true }
            if ($AllowHashMismatch) { $installParams['AllowHashMismatch'] = $true }

            $result = Update-WinGetPackage @installParams
            Write-Host "[OK] Successfully updated " -ForegroundColor Green -NoNewline
            Write-Host $packageId -ForegroundColor White
            $successCount++
        }
        catch {
            Write-Host "[FAIL] Failed to update " -ForegroundColor Red -NoNewline
            Write-Host $packageId -ForegroundColor White -NoNewline
            Write-Host " ($_)" -ForegroundColor Red
            $failCount++
        }
        Write-Host ""
    }

    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "Update Complete" -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "  - " -ForegroundColor Green -NoNewline
    Write-Host $successCount -ForegroundColor White -NoNewline
    Write-Host " | Failed: " -ForegroundColor Red -NoNewline
    Write-Host $failCount -ForegroundColor White

    # Clear cache after updates
    if (Test-Path $cacheFile) {
        Remove-Item $cacheFile -Force
    }
}

# EndRegion

# Region: Public/Import-WingetBatchConfig.ps1
function Import-WingetBatchConfig {
    <#
    .SYNOPSIS
        Import WingetBatch configuration and caches from a zip archive.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    if (-not (Test-Path $Path)) {
        Write-Error "Backup file not found at $Path"
        return
    }
    $configDir = Get-WingetBatchConfigDir
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir | Out-Null
    }
    Expand-Archive -Path $Path -DestinationPath $configDir -Force
    Write-Host "Imported WingetBatch configuration from $Path" -ForegroundColor Green
}


# EndRegion

# Region: Public/Install-WingetAll.ps1
function Install-WingetAll {
    <#
    .SYNOPSIS
        Search for winget packages and install all results.

    .DESCRIPTION
        Searches for packages matching the provided search term and automatically
        installs all packages found in the search results.

    .PARAMETER SearchTerm
        The search term to find packages. Required.

    .PARAMETER Silent
        Skip the confirmation prompt and install immediately.

    .PARAMETER WhatIf
        Show what packages would be installed without actually installing them.

    .EXAMPLE
        Install-WingetAll "python"
        Searches for "python" and installs all matching packages after confirmation.

    .EXAMPLE
        Install-WingetAll "nodejs" -Silent
        Installs all nodejs packages without confirmation prompt.

    .EXAMPLE
        Install-WingetAll "python" -WhatIf
        Shows what would be installed without actually installing.

    .LINK
        https://github.com/microsoft/winget-cli
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [Alias('SearchTerms')]
        [string[]]$Query,

        [Parameter()]
        [string[]]$Id,

        [Parameter()]
        [ValidateSet("Equals", "EqualsCaseInsensitive", "StartsWithCaseInsensitive", "ContainsCaseInsensitive")]
        [string]$MatchOption,

        [Parameter()]
        [string]$Source,

        [Parameter()]
        [int]$LimitResult = 100,

        [Parameter()]
        [switch]$Silent,

        [Parameter()]
        [ValidateSet("Default", "Silent", "Interactive")]
        [string]$Mode,

        [Parameter()]
        [ValidateSet("User", "Machine")]
        [string]$Scope,

        [Parameter()]
        [string]$Architecture,

        [Parameter()]
        [string]$Override,

        [Parameter()]
        [string]$Location,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$SkipDependencies,

        [Parameter()]
        [switch]$AllowHashMismatch,

        [Parameter()]
        [switch]$IWantToLiterallyInstallAllFuckingResults,

        [Parameter()]
        [switch]$WhatIf
    )

    begin {
        # Ensure Microsoft.WinGet.Client is available (COM API - no winget.exe PATH dependency)
        if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
            try {
                Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            }
            catch {
                Write-Error "Microsoft.WinGet.Client module is required. Install it with: Install-Module Microsoft.WinGet.Client -Force"
                return
            }
        }

        # Check if PwshSpectreConsole is available
        if (-not (Get-Module -ListAvailable -Name PwshSpectreConsole)) {
            Write-Warning "PwshSpectreConsole module not found. Installing..."
            try {
                Install-Module -Name PwshSpectreConsole -Scope CurrentUser -Force -SkipPublisherCheck
                Import-Module PwshSpectreConsole
            }
            catch {
                Write-Error "Failed to install PwshSpectreConsole. Interactive selection will not be available."
                Write-Error $_
            }
        }
        else {
            Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
        }

        # Check SQLite Index Health
        $wingetDir = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\Microsoft.Winget.Source_8wekyb3d8bbwe\winget"
        if (Test-Path "$wingetDir\source.db") {
            $dbAge = (Get-Date) - (Get-Item "$wingetDir\source.db").LastWriteTime
            if ($dbAge.TotalDays -gt 7) {
                Write-Host ""
                Write-Host " [!] Your Winget local index cache is outdated ($([Math]::Floor($dbAge.TotalDays)) days old) or fragmented." -ForegroundColor Yellow
                Write-Host "     This can severely degrade search performance and return stale results." -ForegroundColor Gray
                Write-Host "     Recommendation: Run '" -ForegroundColor Gray -NoNewline
                Write-Host "winget source update --force" -ForegroundColor White -NoNewline
                Write-Host "' to rebuild it." -ForegroundColor Gray
                Write-Host ""
            }
        }

        # Determine MatchOption: Param overrides Config overrides Default
        $matchOptionEnum = "ContainsCaseInsensitive"
        if ($MatchOption) {
            $matchOptionEnum = $MatchOption
        }
        else {
            try {
                $configPath = Join-Path (Get-WingetBatchConfigDir) "config.json"
                if (Test-Path $configPath) {
                    $config = Get-Content $configPath -Raw | ConvertFrom-Json
                    if ($config.SearchMatchOption) {
                        $matchOptionEnum = $config.SearchMatchOption
                    }
                }
            } catch { }
        }

        # Output intent
        if ($Query) {
            Write-Host "Searching for packages matching: " -ForegroundColor Cyan -NoNewline
            Write-Host ($Query -join ", ") -ForegroundColor Yellow
        }
        if ($Id) {
            Write-Host "Searching for exact IDs: " -ForegroundColor Cyan -NoNewline
            Write-Host ($Id -join ", ") -ForegroundColor Yellow
        }
    }

    process {
        if (-not $Query -and -not $Id) {
            Write-Error "You must provide either a search query or a specific package ID."
            return
        }

        $allPackages = [System.Collections.Generic.List[Object]]::new()

        # Handle Explicit IDs
        if ($Id) {
            foreach ($i in $Id) {
                if ([string]::IsNullOrWhiteSpace($i)) { continue }
                Write-Host "Resolving ID: " -ForegroundColor Cyan -NoNewline
                Write-Host $i -ForegroundColor Yellow

                try {
                    $comArgs = @{ Id = $i; Count = $LimitResult; ErrorAction = 'Stop' }
                    if ($Source) { $comArgs.Source = $Source }
                    
                    $comResults = Microsoft.WinGet.Client\Find-WinGetPackage @comArgs
                    foreach ($result in $comResults) {
                        $allPackages.Add([PSCustomObject]@{
                            Id = $result.Id; Name = $result.Name
                            Version = if ($result.Version) { $result.Version } else { "Unknown" }
                            Source = if ($result.Source) { $result.Source } else { "Unknown" }
                            SearchTerm = $i
                        })
                    }
                } catch { Write-Warning "Failed to search for ID: $i" }
            }
        }

        # Handle Query searches
        if ($Query) {
            $searchQueries = $Query | ForEach-Object { $_ -split ',' } | Where-Object { $_ -ne '' }

            foreach ($q in $searchQueries) {
                $q = $q.Trim()
                if ([string]::IsNullOrWhiteSpace($q)) { continue }

                Write-Host "Searching for: " -ForegroundColor Cyan -NoNewline
                Write-Host $q -ForegroundColor Yellow

                $searchWords = $q -split '\s+' | Where-Object { $_ -ne '' }
                $queryPackages = [System.Collections.Generic.List[PSCustomObject]]::new()

                try {
                    $comArgs = @{ Count = $LimitResult; ErrorAction = 'Stop'; MatchOption = $matchOptionEnum }
                    if ($Source) { $comArgs.Source = $Source }

                    $comResults = @()

                    if ($q -match '^\d+$') {
                        # Smart Routing: Pure numbers bypass ID to prevent garbage matches, but retain Name, Tag, and Moniker
                        $nameArgs = $comArgs.Clone()
                        $nameArgs.Name = $q
                        $tagArgs = $comArgs.Clone()
                        $tagArgs.Tag = $q
                        $monikerArgs = $comArgs.Clone()
                        $monikerArgs.Moniker = $q

                        $comResults += Microsoft.WinGet.Client\Find-WinGetPackage @nameArgs
                        $comResults += Microsoft.WinGet.Client\Find-WinGetPackage @tagArgs
                        $comResults += Microsoft.WinGet.Client\Find-WinGetPackage @monikerArgs
                    }
                    else {
                        # Standard OR routing (Name, ID, Moniker, Tags)
                        $comArgs.Query = $q
                        $comResults = Microsoft.WinGet.Client\Find-WinGetPackage @comArgs
                    }

                    foreach ($result in $comResults) {
                        if (-not $result) { continue }
                        $packageId = $result.Id
                        $packageName = $result.Name
                        $packageVersion = if ($result.Version) { $result.Version } else { "Unknown" }
                        $packageSource = if ($result.Source) { $result.Source } else { "Unknown" }

                        # If multiple search words, filter to only packages matching ALL words
                        if ($searchWords.Count -gt 1) {
                            $matchesAll = $true
                            $combinedText = "$packageName $packageId"
                            foreach ($word in $searchWords) {
                                if ($combinedText.IndexOf($word, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                                    $matchesAll = $false; break
                                }
                            }
                            if ($matchesAll) {
                                $queryPackages.Add([PSCustomObject]@{ Id = $packageId; Name = $packageName; Version = $packageVersion; Source = $packageSource; SearchTerm = $q })
                            }
                        }
                        else {
                            $queryPackages.Add([PSCustomObject]@{ Id = $packageId; Name = $packageName; Version = $packageVersion; Source = $packageSource; SearchTerm = $q })
                        }
                    }
                }
                catch { Write-Warning "Failed to search for query: $q" }

                if ($queryPackages.Count -gt 0) {
                    $allPackages.AddRange([array]$queryPackages)
                } else {
                    Write-Warning "No packages found matching '$q'"
                }
            }
        }

        # Deduplicate all collected packages based on Id (preserving order)
        $seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $foundPackages = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($pkg in $allPackages) {
            if ($seenIds.Add([string]$pkg.Id)) {
                $foundPackages.Add($pkg)
            }
        }

        # Build a lookup map for faster access to package details
        $pkgMap = @{}
        if ($null -ne $foundPackages) {
            foreach ($pkg in $foundPackages) {
                # Use the first encounter of a package ID to match original behavior of Select-Object -First 1
                # Check for null Id to prevent hashtable errors and cast to string for safety
                if ($null -ne $pkg.Id -and -not $pkgMap.ContainsKey([string]$pkg.Id)) {
                    $pkgMap[[string]$pkg.Id] = $pkg
                }
            }
        }

        if ($foundPackages.Count -eq 0) {
            Write-Warning "No packages found matching '$($SearchTerms -join ", ")'"
            return
        }

        Write-Host "`nFound " -ForegroundColor Green -NoNewline
        Write-Host "$($foundPackages.Count)" -ForegroundColor White -NoNewline
        Write-Host " package(s)" -ForegroundColor Green

        if ($WhatIf) {
            Write-Host "`n[WhatIf] Would display interactive selection for:" -ForegroundColor Yellow

            $groups = @{}
            foreach ($pkg in $foundPackages) {
                if (-not $groups.ContainsKey($pkg.SearchTerm)) {
                    $groups[$pkg.SearchTerm] = [System.Collections.Generic.List[PSCustomObject]]::new()
                }
                $groups[$pkg.SearchTerm].Add($pkg)
            }

            foreach ($term in $groups.Keys) {
                Write-Host "$($term):" -ForegroundColor Yellow
                foreach ($pkg in $groups[$term]) {
                    Write-Host "  • " -ForegroundColor Cyan -NoNewline
                    Write-Host "$($pkg.Name) ($($pkg.Id))" -ForegroundColor White -NoNewline
                    if ($pkg.Version -ne "Unknown") {
                        Write-Host " v$($pkg.Version)" -ForegroundColor Green -NoNewline
                    }
                    if ($pkg.Source) {
                        $sColor = if ($pkg.Source -match 'msstore') { "Magenta" } else { "Cyan" }
                        Write-Host " [$($pkg.Source)]" -ForegroundColor $sColor
                    } else { Write-Host "" }
                }
            }
            return
        }

        # Prepare choices for selection with SearchTerm grouping prefix
        # Consolidating loops to improve performance (avoid double iteration and regex operations)
        $packageChoices = [System.Collections.Generic.List[string]]::new()
        $packageMap = @{}

        foreach ($pkg in $foundPackages) {
            $sourceColor = if ($pkg.Source -match 'msstore') { "magenta" } else { "cyan" }
            $versionStr = if ($pkg.Version -ne "Unknown") { " [green]v$($pkg.Version)[/]" } else { "" }

            $term = ConvertTo-SpectreEscaped $pkg.SearchTerm
            $name = ConvertTo-SpectreEscaped $pkg.Name
            $id = ConvertTo-SpectreEscaped $pkg.Id
            $source = ConvertTo-SpectreEscaped $pkg.Source

            $displayString = "[yellow][[$term]][/] $name ($id)$versionStr [$sourceColor]$source[/]"

            $packageChoices.Add($displayString)
            $packageMap[$displayString] = $pkg.Id
        }

        $packagesToInstall = @()

        # Interactive Selection using PwshSpectreConsole
        if ($IWantToLiterallyInstallAllFuckingResults -or $Silent) {
            $packagesToInstall = $foundPackages.Id
        }
        elseif (-not $Silent -and (Get-Module -Name PwshSpectreConsole)) {
            Write-Host ""

            try {
                # Create multi-selection prompt
                $selectedChoices = Read-SpectreMultiSelection -Title "[cyan]Select packages to install[/]" `
                    -Choices $packageChoices `
                    -PageSize 20 `
                    -Color "Green"

                if ($selectedChoices.Count -eq 0) {
                    Write-Host "`nNo packages selected. Exiting." -ForegroundColor Yellow
                    return
                }

                # Map back to IDs
                $packagesToInstall = $selectedChoices | ForEach-Object { $packageMap[$_] }

                Write-Host "`nSelected " -ForegroundColor Green -NoNewline
                Write-Host "$($packagesToInstall.Count)" -ForegroundColor White -NoNewline
                Write-Host " package(s) for installation" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to show interactive selection. Falling back to confirmation prompt."
                $packagesToInstall = $foundPackages.Id
            }
        }
        elseif (-not $Silent) {
            # Fallback for when Spectre Console is not available
            $packagesToInstall = $foundPackages.Id
        }
        else {
             # Silent mode
             $packagesToInstall = $foundPackages.Id
        }

        if (-not ($Silent -or $IWantToLiterallyInstallAllFuckingResults) -and $packagesToInstall.Count -gt 0) {
            Write-Host "`nFetching package details..." -ForegroundColor DarkGray
            $configDir = Get-WingetBatchConfigDir

            $jobsResult = Start-PackageDetailJobs -PackageIds $packagesToInstall -ConfigDir $configDir
            $jobs = $jobsResult[0]

            if ($jobs.Count -gt 0) {
                Write-Host "Waiting for background jobs..." -ForegroundColor DarkGray
                $jobs | Wait-Job | Out-Null

                $allPackageDetails = @{}
                foreach ($job in $jobs) {
                    $jobResults = Receive-Job -Job $job
                    foreach ($key in $jobResults.Keys) {
                        $allPackageDetails[$key] = $jobResults[$key]
                        Set-PackageDetailsCache -PackageId $key -Details $jobResults[$key]
                    }
                    Remove-Job -Job $job -Force
                }

                # Fill missing
                foreach ($pkgId in $packagesToInstall) {
                    if (-not $allPackageDetails.ContainsKey($pkgId)) {
                        $allPackageDetails[$pkgId] = @{ Id = $pkgId }
                    }
                }

                Show-WingetPackageDetails -PackageIds $packagesToInstall -DetailsMap $allPackageDetails -FallbackInfo $foundPackages -FallbackMap $pkgMap

                # Ask for confirmation
                Write-Host "Press " -NoNewline -ForegroundColor Yellow
                Write-Host "Enter" -NoNewline -ForegroundColor White
                Write-Host " to install, or " -NoNewline -ForegroundColor Yellow
                Write-Host "Ctrl+C" -NoNewline -ForegroundColor Red
                Write-Host " to cancel..." -ForegroundColor Yellow
                try {
                    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                }
                catch {
                    # Ignore
                }
            }
        }

        Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
        Write-Host "Starting Installation Process" -ForegroundColor Cyan
        Write-Host ("=" * 60) -ForegroundColor Cyan

        $successCount = 0
        $failCount = 0

        # Deduplicate IDs to ensure we don't install the same package twice
        $uniquePackagesToInstall = $packagesToInstall | Select-Object -Unique

        if ($uniquePackagesToInstall.Count -gt 0) {
            # Build summary list first (raw data)
            $summaryList = [System.Collections.Generic.List[PSCustomObject]]::new()

            foreach ($packageId in $uniquePackagesToInstall) {
                $pkgInfo = $pkgMap[$packageId]

                # Try to get publisher from details if available
                $publisher = $null
                if ($null -ne $allPackageDetails -and $allPackageDetails.ContainsKey($packageId)) {
                    $details = $allPackageDetails[$packageId]
                    if ($details.PublisherName) { $publisher = $details.PublisherName }
                    elseif ($details.Publisher) { $publisher = $details.Publisher }
                }

                if (-not $publisher) { $publisher = "" }

                if ($pkgInfo) {
                    $summaryList.Add([PSCustomObject]@{
                        Name = $pkgInfo.Name
                        Id = $pkgInfo.Id
                        Version = $pkgInfo.Version
                        Source = $pkgInfo.Source
                        SearchTerm = $pkgInfo.SearchTerm
                        Publisher = $publisher
                    })
                } else {
                    $summaryList.Add([PSCustomObject]@{
                        Name = $packageId
                        Id = $packageId
                        Version = "Unknown"
                        Source = "Unknown"
                        SearchTerm = "Manual"
                        Publisher = $publisher
                    })
                }
            }

            # Use Spectre Console table if available for better formatting
            if (Get-Module -Name PwshSpectreConsole) {
                Write-Host ""
                Write-Host "Package Installation Summary ($($summaryList.Count) packages)" -ForegroundColor Cyan

                $spectreList = [System.Collections.Generic.List[PSCustomObject]]::new()

                # Check if we have multiple unique search terms in the summary
                $uniqueSearchTerms = $summaryList | Select-Object -ExpandProperty SearchTerm -Unique
                $showSearchTerm = ($uniqueSearchTerms | Measure-Object).Count -gt 1

                # Check if we have any publishers to show
                $showPublisher = ($summaryList | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Publisher) } | Measure-Object).Count -gt 0

                foreach ($item in $summaryList) {
                    $verColor = if ($item.Version -ne "Unknown") { "green" } else { "grey" }
                    $srcColor = if ($item.Source -match 'msstore') { "magenta" } else { "cyan" }

                    $obj = [ordered]@{
                        Name = (ConvertTo-SpectreEscaped $item.Name)
                        Id = ConvertTo-SpectreEscaped $item.Id
                        Version = "[$verColor]$($item.Version)[/]"
                        Source = "[$srcColor]$($item.Source)[/]"
                    }

                    if ($showPublisher) {
                        $obj['Publisher'] = if ($item.Publisher) { (ConvertTo-SpectreEscaped $item.Publisher) } else { "" }
                    }

                    if ($showSearchTerm) {
                        $obj['Search Term'] = "[grey]$(ConvertTo-SpectreEscaped $item.SearchTerm)[/]"
                    }

                    $spectreList.Add([PSCustomObject]$obj)
                }

                $spectreList | Format-SpectreTable | Out-Host
            }
            else {
                Write-Host "`nPackage Installation Summary ($($summaryList.Count) packages):" -ForegroundColor Cyan

                # Simple modification for fallback table too
                $showPublisher = ($summaryList | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Publisher) } | Measure-Object).Count -gt 0

                $fallbackList = $summaryList | Select-Object Name, Id, Version, Source, Publisher, SearchTerm

                $props = [System.Collections.Generic.List[string]]::new()
                $props.AddRange([string[]]@('Name', 'Id', 'Version', 'Source'))

                if ($showPublisher) {
                    $props.Add('Publisher')
                }

                if (($summaryList | Select-Object -ExpandProperty SearchTerm -Unique | Measure-Object).Count -gt 1) {
                    $props.Add('SearchTerm')
                }

                $fallbackList | Format-Table -Property $props -AutoSize | Out-Host
            }
        }

        # Execute installations with progress tracking
        $totalToInstall = $uniquePackagesToInstall.Count
        $currentIdx = 0

        if (Get-Module -Name PwshSpectreConsole) {
            # Rich Spectre progress display
            $uniquePackagesToInstall | ForEach-Object {
                $packageId = $_
                $currentIdx++
                $pkgInfo = $pkgMap[$packageId]
                $pkgName = if ($pkgInfo) { $pkgInfo.Name } else { $packageId }

                Write-Host "`n>>> [$currentIdx/$totalToInstall] Installing: " -ForegroundColor Magenta -NoNewline
                Write-Host "$pkgName ($packageId)" -ForegroundColor White

                try {
                    $installParams = @{
                        Id = $packageId
                        ErrorAction = 'Stop'
                    }
                    if ($PSBoundParameters.ContainsKey('Mode')) { $installParams['Mode'] = $Mode }
                    if ($PSBoundParameters.ContainsKey('Scope')) { $installParams['Scope'] = $Scope }
                    if ($PSBoundParameters.ContainsKey('Architecture')) { $installParams['Architecture'] = $Architecture }
                    if ($PSBoundParameters.ContainsKey('Override')) { $installParams['Override'] = $Override }
                    if ($PSBoundParameters.ContainsKey('Location')) { $installParams['Location'] = $Location }
                    if ($Force) { $installParams['Force'] = $true }
                    if ($SkipDependencies) { $installParams['SkipDependencies'] = $true }
                    if ($AllowHashMismatch) { $installParams['AllowHashMismatch'] = $true }

                    Microsoft.WinGet.Client\Install-WinGetPackage @installParams | Out-Null
                    Write-Host "    [OK] " -ForegroundColor Green -NoNewline
                    Write-Host "Successfully installed $packageId" -ForegroundColor White
                    $successCount++
                }
                catch {
                    Write-Host "    [FAIL] " -ForegroundColor Red -NoNewline
                    Write-Host "$packageId - $_" -ForegroundColor Red
                    $failCount++
                }
            }
        }
        else {
            # Fallback: standard output
            foreach ($packageId in $uniquePackagesToInstall) {
                $currentIdx++
                $pkgInfo = $pkgMap[$packageId]
                $pkgName = if ($pkgInfo) { $pkgInfo.Name } else { $packageId }
                $pkgVersion = if ($pkgInfo -and $pkgInfo.Version -ne "Unknown") { "v$($pkgInfo.Version)" } else { "" }
                $pkgSource = if ($pkgInfo -and $pkgInfo.Source -ne "Unknown") { $pkgInfo.Source } else { "" }

                Write-Host "`n>>> [$currentIdx/$totalToInstall] Installing: " -ForegroundColor Magenta -NoNewline
                Write-Host "$pkgName ($packageId)" -ForegroundColor White -NoNewline
                if ($pkgVersion) { Write-Host " $pkgVersion" -ForegroundColor Green -NoNewline }
                if ($pkgSource) {
                    $sColor = if ($pkgSource -match 'msstore') { "Magenta" } else { "Cyan" }
                    Write-Host " from $pkgSource" -ForegroundColor $sColor
                } else { Write-Host "" }

                try {
                    $installParams = @{
                        Id = $packageId
                        ErrorAction = 'Stop'
                    }
                    if ($PSBoundParameters.ContainsKey('Mode')) { $installParams['Mode'] = $Mode }
                    if ($PSBoundParameters.ContainsKey('Scope')) { $installParams['Scope'] = $Scope }
                    if ($PSBoundParameters.ContainsKey('Architecture')) { $installParams['Architecture'] = $Architecture }
                    if ($PSBoundParameters.ContainsKey('Override')) { $installParams['Override'] = $Override }
                    if ($PSBoundParameters.ContainsKey('Location')) { $installParams['Location'] = $Location }
                    if ($Force) { $installParams['Force'] = $true }
                    if ($SkipDependencies) { $installParams['SkipDependencies'] = $true }
                    if ($AllowHashMismatch) { $installParams['AllowHashMismatch'] = $true }

                    Microsoft.WinGet.Client\Install-WinGetPackage @installParams | Out-Null
                    Write-Host "[OK] Successfully installed " -ForegroundColor Green -NoNewline
                    Write-Host $packageId -ForegroundColor White
                    $successCount++
                }
                catch {
                    Write-Host "[FAIL] Failed to install " -ForegroundColor Red -NoNewline
                    Write-Host $packageId -ForegroundColor White -NoNewline
                    Write-Host " ($_)" -ForegroundColor Red
                    $failCount++
                }
            }
        }

        Write-Host "`n" + ("=" * 60) -ForegroundColor Green
        Write-Host "Installation Complete" -ForegroundColor Green
        Write-Host ("=" * 60) -ForegroundColor Green
        Write-Host "Success: " -ForegroundColor Green -NoNewline
        Write-Host $successCount -ForegroundColor White -NoNewline
        Write-Host " | Failed: " -ForegroundColor Red -NoNewline
        Write-Host $failCount -ForegroundColor White
    }
}


# EndRegion

# Region: Public/Invoke-WinGetBatch.ps1
function Invoke-WinGetBatch {
    <#
    .SYNOPSIS
        Invoke Next-Generation idempotent package deployments using COM APIs and parallel downloading.

    .DESCRIPTION
        Reads package target states from a pipeline or manifest file (JSON/YAML), verifies local state
        idempotency using the native Microsoft.WinGet.Client COM APIs, parallelizes download operations,
        and serializes silent installation execution while trapping and mapping system exit codes.

    .PARAMETER Path
        Path to a JSON or YAML state manifest file defining the target package configurations.

    .PARAMETER Packages
        Optional array of package objects passed directly or via pipeline. Each package should have an 'Id' property
        and an optional 'Version' property.

    .PARAMETER ThrottleLimit
        Maximum number of concurrent downloads. Default is 4.

    .PARAMETER Silent
        Runs installations completely silently without user interaction.

    .PARAMETER WhatIf
        Previews the deployment plan, performing idempotency checks without downloading or installing anything.

    .EXAMPLE
        Invoke-WinGetBatch -Path .\packages.yaml

    .EXAMPLE
        Get-Content .\packages.json | ConvertFrom-Json | Invoke-WinGetBatch
    #>

    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Manifest', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Pipeline', ValueFromPipeline = $true)]
        [PSCustomObject[]]$Packages,

        [Parameter()]
        [int]$ThrottleLimit = 4,

        [Parameter()]
        [switch]$Silent,

        [Parameter()]
        [ValidateSet("Default", "Silent", "Interactive")]
        [string]$Mode,

        [Parameter()]
        [ValidateSet("User", "Machine")]
        [string]$Scope,

        [Parameter()]
        [string]$Architecture,

        [Parameter()]
        [string]$Override,

        [Parameter()]
        [string]$Location,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$SkipDependencies,

        [Parameter()]
        [switch]$AllowHashMismatch,

        [Parameter()]
        [switch]$WhatIf
    )

    begin {
        # Prepend WindowsApps folder to ensure winget and COM APIs resolve correctly
        $windowsAppsPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
        if ($env:PATH -notlike "*$windowsAppsPath*") {
            $env:PATH = "$windowsAppsPath;$env:PATH"
        }

        # Ensure Microsoft.WinGet.Client module is imported
        if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
            try {
                Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            }
            catch {
                Write-Error "Microsoft.WinGet.Client module is a required dependency. Please install it."
                return
            }
        }

        # Resolve winget.exe path for parallel script blocks
        $wingetExePath = (Get-Command winget -ErrorAction SilentlyContinue).Source
        if (-not $wingetExePath) {
            $wingetExePath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
        }

        # Initialize collections
        $targetPackages = [System.Collections.Generic.List[PSCustomObject]]::new()
        $executionQueue = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Manifest') {
            # Resolve full manifest path
            $manifestPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            if (-not (Test-Path $manifestPath)) {
                Write-Error "Manifest file not found at: $manifestPath"
                return
            }

            Write-Host "[SYSTEM] Parsing state manifest: " -NoNewline -ForegroundColor Cyan
            Write-Host $manifestPath -ForegroundColor White

            $content = Get-Content -Raw -Path $manifestPath
            $parsed = $null

            if ($manifestPath.EndsWith(".yaml") -or $manifestPath.EndsWith(".yml")) {
                if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
                    Write-Error "powershell-yaml module is required to parse YAML manifests."
                    return
                }
                $parsed = ConvertFrom-Yaml $content
            }
            elseif ($manifestPath.EndsWith(".json")) {
                $parsed = ConvertFrom-Json $content
            }
            else {
                Write-Error "Unsupported manifest format. Use .json, .yaml, or .yml"
                return
            }

            if ($parsed -and $parsed.packages) {
                foreach ($pkg in $parsed.packages) {
                    $targetPackages.Add([PSCustomObject]@{
                        Id      = $pkg.id
                        Version = if ($pkg.version) { $pkg.version } else { "latest" }
                    })
                }
            }
        }
        else {
            # Pipeline parameters input
            if ($null -ne $Packages) {
                foreach ($pkg in $Packages) {
                    if ($pkg.Id) {
                        $targetPackages.Add([PSCustomObject]@{
                            Id      = $pkg.Id
                            Version = if ($pkg.Version) { $pkg.Version } else { "latest" }
                        })
                    }
                }
            }
        }
    }

    end {
        if ($targetPackages.Count -eq 0) {
            Write-Host "[INFO] No packages resolved for deployment." -ForegroundColor Yellow
            return
        }

        Write-Host "`n[PHASE 1] Resolving and Checking Local State Idempotency..." -ForegroundColor Cyan

        # Query all installed packages once to optimize execution speed
        $installedList = Get-WinGetPackage -ErrorAction SilentlyContinue
        $installedMap = @{}
        foreach ($inst in $installedList) {
            if ($inst.Id -and -not $installedMap.ContainsKey($inst.Id)) {
                $installedMap[$inst.Id] = $inst
            }
        }

        # Validate local state idempotency against targets
        foreach ($target in $targetPackages) {
            $pkgId = $target.Id
            $targetVer = $target.Version

            Write-Host "   Checking " -NoNewline -ForegroundColor Gray
            Write-Host $pkgId -NoNewline -ForegroundColor White

            if ($installedMap.ContainsKey($pkgId)) {
                $installedPkg = $installedMap[$pkgId]
                $installedVer = $installedPkg.InstalledVersion
                $updateAvailable = $installedPkg.IsUpdateAvailable

                if ($targetVer -eq 'latest') {
                    if ($updateAvailable) {
                        Write-Host " [Outdated] Installed: $installedVer (Update Available)" -ForegroundColor Yellow
                        $executionQueue.Add($target)
                    }
                    else {
                        Write-Host " [Idempotent] Installed: $installedVer (Up to date)" -ForegroundColor Green
                    }
                }
                else {
                    # Compare specific versions
                    if ($installedVer -eq $targetVer) {
                        Write-Host " [Idempotent] Installed version matches target: $targetVer" -ForegroundColor Green
                    }
                    else {
                        Write-Host " [Mismatch] Installed: $installedVer | Target: $targetVer" -ForegroundColor Yellow
                        $executionQueue.Add($target)
                    }
                }
            }
            else {
                Write-Host " [Missing]" -ForegroundColor Red
                $executionQueue.Add($target)
            }
        }

        if ($executionQueue.Count -eq 0) {
            Write-Host "`n[OK] System state is fully idempotent. No actions required." -ForegroundColor Green
            return
        }

        Write-Host "`nDeployment execution queue compiled: " -NoNewline -ForegroundColor Cyan
        Write-Host "$($executionQueue.Count) packages require changes." -ForegroundColor White

        if ($WhatIf) {
            Write-Host "`n[WhatIf] Would execute split-phase deployment for:" -ForegroundColor Yellow
            foreach ($item in $executionQueue) {
                Write-Host "  -> $($item.Id) ($($item.Version))" -ForegroundColor Gray
            }
            return
        }

        # Phase 1: Parallel Downloads using ForEach-Object -Parallel
        Write-Host "`n[PHASE 2] Parallel Download Operations Launching..." -ForegroundColor Cyan
        $cacheDir = Join-Path $env:TEMP "winget_cache"
        if (-not (Test-Path $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }

        $downloads = $executionQueue | ForEach-Object -Parallel {
            $wingetPath = $using:wingetExePath
            $pkgId = $_.Id
            $dlPath = Join-Path $using:cacheDir $pkgId

            Write-Host "  >>> Downloading installer for $pkgId ..." -ForegroundColor DarkGray

            # Build argument array (no Invoke-Expression - safe from injection)
            $wingetArgs = @(
                'download'
                '--id', $pkgId
                '--exact'
                '--accept-package-agreements'
                '--accept-source-agreements'
                '--disable-interactivity'
                '--download-directory', $dlPath
            )
            if ($_.Version -ne "latest") {
                $wingetArgs += @('--version', $_.Version)
            }

            $process = Start-Process -FilePath $wingetPath -ArgumentList $wingetArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput "$dlPath\stdout.log" -RedirectStandardError "$dlPath\stderr.log"

            if ($process.ExitCode -eq 0) {
                Write-Host "   Cached installer: $pkgId" -ForegroundColor Green
                return [PSCustomObject]@{ Id = $pkgId; Downloaded = $true; Path = $dlPath }
            }
            else {
                Write-Host "   Failed download cache: $pkgId (Exit Code: $($process.ExitCode))" -ForegroundColor Red
                return [PSCustomObject]@{ Id = $pkgId; Downloaded = $false; Path = $null }
            }
        } -ThrottleLimit $ThrottleLimit

        $downloadResults = @{}
        foreach ($res in $downloads) {
            $downloadResults[$res.Id] = $res
        }

        # Phase 2: Serialized Sequential Installations
        Write-Host "`n[PHASE 3] Serialized Installation Queue Executing..." -ForegroundColor Cyan
        
        $successCount = 0
        $failCount = 0
        $rebootPending = $false
        $reportData = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($pkg in $executionQueue) {
            $pkgId = $pkg.Id
            $targetVer = $pkg.Version
            $dlResult = $downloadResults[$pkgId]

            Write-Host "`n>>> Deploying: " -NoNewline -ForegroundColor Magenta
            Write-Host $pkgId -ForegroundColor White

            if ($dlResult -and $dlResult.Downloaded) {
                Write-Host "Using pre-cached local installer." -ForegroundColor DarkGray
            }
            else {
                Write-Warning "Local cache missing. Falling back to dynamic installer fetch."
            }

            # Run installation using COM API (preferred) with CLI fallback
            $installSucceeded = $false
            $exitCode = -1

            try {
                # Primary: Use COM API for installation (no shell execution needed)
                $comInstallArgs = @{
                    Id = $pkgId
                    ErrorAction = 'Stop'
                }
                if ($Silent -or $Mode -eq 'Silent') { $comInstallArgs['Mode'] = 'Silent' }
                elseif ($Mode -eq 'Interactive') { $comInstallArgs['Mode'] = 'Interactive' }
                if ($Scope) { $comInstallArgs['Scope'] = $Scope }
                if ($Architecture) { $comInstallArgs['Architecture'] = $Architecture }
                if ($Location) { $comInstallArgs['Location'] = $Location }
                if ($Override) { $comInstallArgs['Override'] = $Override }
                if ($Force) { $comInstallArgs['Force'] = $true }
                if ($SkipDependencies) { $comInstallArgs['SkipDependencies'] = $true }
                if ($AllowHashMismatch) { $comInstallArgs['AllowHashMismatch'] = $true }

                Microsoft.WinGet.Client\Install-WinGetPackage @comInstallArgs | Out-Null
                $exitCode = 0
                $installSucceeded = $true
            }
            catch {
                # Fallback: Use winget CLI with safe argument array (no Invoke-Expression)
                Write-Verbose "COM API install failed, falling back to CLI: $_"
                $wingetArgs = @(
                    'install'
                    '--id', $pkgId
                    '--exact'
                    '--accept-package-agreements'
                    '--accept-source-agreements'
                    '--disable-interactivity'
                    '--no-progress'
                )
                if ($Silent -or $Mode -eq 'Silent') { $wingetArgs += '--silent' }
                elseif ($Mode -eq 'Interactive') { $wingetArgs += '--interactive' }
                if ($targetVer -ne "latest") { $wingetArgs += @('--version', $targetVer) }
                if ($Scope -eq "Machine") { $wingetArgs += '--machine' }
                elseif ($Scope -eq "User") { $wingetArgs += '--user' }
                if ($Architecture) { $wingetArgs += @('--architecture', $Architecture) }
                if ($Location) { $wingetArgs += @('--location', $Location) }
                if ($Override) { $wingetArgs += @('--override', $Override) }
                if ($Force) { $wingetArgs += '--force' }
                if ($SkipDependencies) { $wingetArgs += '--skip-dependencies' }
                if ($AllowHashMismatch) { $wingetArgs += '--ignore-security-hash' }

                $process = Start-Process -FilePath $wingetExePath -ArgumentList $wingetArgs -Wait -NoNewWindow -PassThru
                $exitCode = $process.ExitCode
                $installSucceeded = ($exitCode -eq 0)
            }

            # Exit Code Trapping & Telemetry Mapping
            $status = "Failed"
            $message = "Unknown installation error."

            switch ($exitCode) {
                0 {
                    $status = "Success"
                    $message = "Successfully installed package."
                    $successCount++
                    Write-Host "[OK] Successfully deployed " -NoNewline -ForegroundColor Green
                    Write-Host $pkgId -ForegroundColor White
                }
                3010 {
                    $status = "Success (Reboot Required)"
                    $message = "Installation successful, but system reboot is required."
                    $successCount++
                    $rebootPending = $true
                    Write-Host "[OK] Deployed (Reboot Required): " -NoNewline -ForegroundColor Yellow
                    Write-Host $pkgId -ForegroundColor White
                }
                1641 {
                    $status = "Success (Reboot Initiated)"
                    $message = "Installation successful, reboot has been initiated."
                    $successCount++
                    $rebootPending = $true
                    Write-Host "[OK] Deployed (Reboot Initiated): " -NoNewline -ForegroundColor Yellow
                    Write-Host $pkgId -ForegroundColor White
                }
                default {
                    $status = "Failed"
                    $message = "Installer returned non-zero code: $exitCode."
                    $failCount++
                    Write-Host " Installation failed for " -NoNewline -ForegroundColor Red
                    Write-Host $pkgId -NoNewline -ForegroundColor White
                    Write-Host " (Exit Code: $exitCode)" -ForegroundColor Red
                }
            }

            $reportData.Add([PSCustomObject]@{
                PackageId = $pkgId
                Version   = $targetVer
                Status    = $status
                ExitCode  = $exitCode
                Message   = $message
                Timestamp = (Get-Date).ToString("o")
            })
        }

        # Compile structured JSON report
        $reportDir = Join-Path $env:TEMP "winget_reports"
        if (-not (Test-Path $reportDir)) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }

        $reportPath = Join-Path $reportDir "deployment_report_$((Get-Date).ToString('yyyyMMdd_HHmmss')).json"
        $reportObj = [ordered]@{
            Summary = @{
                TotalInstalled = $executionQueue.Count
                Successful     = $successCount
                Failed         = $failCount
                RebootRequired = $rebootPending
            }
            Results = $reportData
        }

        $reportObj | ConvertTo-Json -Depth 5 | Out-File -FilePath $reportPath -Encoding utf8

        Write-Host "`n" + ("=" * 60) -ForegroundColor Green
        Write-Host "Deployment Operations Concluded" -ForegroundColor Green
        Write-Host ("=" * 60) -ForegroundColor Green
        Write-Host "   Successful: " -NoNewline -ForegroundColor Green
        Write-Host $successCount -ForegroundColor White
        Write-Host "   Failed:     " -NoNewline -ForegroundColor Red
        Write-Host $failCount -ForegroundColor White
        
        if ($rebootPending) {
            Write-Host "   A system reboot is pending to complete installation changes." -ForegroundColor Yellow
        }

        Write-Host "`nStructured JSON deployment audit report saved to:" -ForegroundColor Gray
        Write-Host "  $reportPath" -ForegroundColor Cyan
    }
}



# EndRegion

# Region: Public/Invoke-WingetBatchCleanup.ps1
function Invoke-WingetBatchCleanup {
    <#
    .SYNOPSIS
        Clean up WingetBatch caches and orphaned jobs.
    #>
    [CmdletBinding()]
    param()
    $configDir = Get-WingetBatchConfigDir
    $cacheFile = Join-Path $configDir "package_cache.json"
    $updateCacheFile = Join-Path $configDir "update_cache.json"
    
    $bytesFreed = 0
    if (Test-Path $cacheFile) {
        $bytesFreed += (Get-Item $cacheFile).Length
        Remove-Item $cacheFile -Force
    }
    if (Test-Path $updateCacheFile) {
        $bytesFreed += (Get-Item $updateCacheFile).Length
        Remove-Item $updateCacheFile -Force
    }
    
    # Clean orphaned jobs from current session
    $jobs = Get-Job -ErrorAction SilentlyContinue | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') }
    if ($jobs) {
        $jobs | Remove-Job -Force
    }
    
    $mbFreed = [math]::Round($bytesFreed / 1MB, 2)
    Write-Host "Cleanup complete. Freed $mbFreed MB of cache." -ForegroundColor Green
}


# EndRegion

# Region: Public/New-WingetBatchGitHubToken.ps1
function New-WingetBatchGitHubToken {
    <#
    .SYNOPSIS
        Interactive helper to create and save a GitHub Personal Access Token.

    .DESCRIPTION
        Opens GitHub token creation page and guides you through the process.
        Automatically saves the token once you paste it.

    .EXAMPLE
        New-WingetBatchGitHubToken
        Opens GitHub and helps you create a token.

    .LINK
        https://github.com/settings/tokens
    #>

    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "🔑 GitHub Token Setup Wizard" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "I'll help you create a GitHub token to avoid API rate limits." -ForegroundColor White
    Write-Host ""
    Write-Host "Benefits:" -ForegroundColor Cyan
    Write-Host "  • " -NoNewline -ForegroundColor DarkGray
    Write-Host "60 requests/hour" -NoNewline -ForegroundColor Red
    Write-Host " → " -NoNewline -ForegroundColor DarkGray
    Write-Host "5,000 requests/hour" -ForegroundColor Green
    Write-Host "  • No special permissions needed" -ForegroundColor DarkGray
    Write-Host "  • Free forever" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Press Enter to open GitHub in your browser..." -ForegroundColor Yellow
    $null = Read-Host

    # Open GitHub token creation page
    $tokenUrl = "https://github.com/settings/tokens/new?description=WingetBatch&scopes="
    Start-Process $tokenUrl

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "📋 Follow these steps on GitHub:" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. " -NoNewline -ForegroundColor Yellow
    Write-Host "The token is already named 'WingetBatch'" -ForegroundColor White
    Write-Host ""
    Write-Host "2. " -NoNewline -ForegroundColor Yellow
    Write-Host "Set expiration (or choose 'No expiration' for convenience)" -ForegroundColor White
    Write-Host ""
    Write-Host "3. " -NoNewline -ForegroundColor Yellow
    Write-Host "DON'T check any permission boxes - none needed!" -ForegroundColor White
    Write-Host ""
    Write-Host "4. " -NoNewline -ForegroundColor Yellow
    Write-Host "Click " -NoNewline -ForegroundColor White
    Write-Host "'Generate token' " -NoNewline -ForegroundColor Green
    Write-Host "at the bottom" -ForegroundColor White
    Write-Host ""
    Write-Host "5. " -NoNewline -ForegroundColor Yellow
    Write-Host "COPY the token (starts with 'ghp_')" -ForegroundColor White
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""

    # Prompt for token
    $secureInput = Read-Host "Paste your token here" -AsSecureString
    $token = [System.Net.NetworkCredential]::new("", $secureInput).Password

    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Host ""
        Write-Host "❌ No token provided. Setup cancelled." -ForegroundColor Red
        Write-Host "   Run this command again when you have your token." -ForegroundColor DarkGray
        return
    }

    # Validate token format
    if ($token -notmatch '^ghp_[a-zA-Z0-9]{36}$' -and $token -notmatch '^github_pat_[a-zA-Z0-9_]+$') {
        Write-Host ""
        Write-Host "⚠️  Warning: Token format doesn't look right." -ForegroundColor Yellow
        Write-Host "   Expected format: ghp_xxxxxxxxxxxx or github_pat_xxxxxxxxxxxx" -ForegroundColor DarkGray
        Write-Host ""
        $continue = Read-Host "Continue anyway? (y/n)"
        if ($continue -ne 'y') {
            Write-Host "Setup cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Test the token
    Write-Host ""
    Write-Host "Testing token..." -ForegroundColor Cyan
    try {
        $testUrl = "https://api.github.com/user"
        $response = Invoke-RestMethod -Uri $testUrl -Headers @{
            'Authorization' = "Bearer $token"
            'User-Agent' = 'PowerShell-WingetBatch'
        } -ErrorAction Stop

        Write-Host "✓ Token is valid!" -ForegroundColor Green
        Write-Host "  Authenticated as: " -NoNewline -ForegroundColor DarkGray
        Write-Host $response.login -ForegroundColor White
    }
    catch {
        Write-Host "❌ Token test failed!" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor DarkGray
        Write-Host ""
        $continue = Read-Host "Save token anyway? (y/n)"
        if ($continue -ne 'y') {
            Write-Host "Setup cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Save token
    Set-WingetBatchGitHubToken -Token $token

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "✓ Setup Complete!" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now use all WingetBatch commands without rate limits!" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Try: " -NoNewline -ForegroundColor DarkGray
    Write-Host "Get-WingetNewPackages -Days 30" -ForegroundColor Yellow
    Write-Host ""
}


# EndRegion

# Region: Public/Remove-WingetRecent.ps1
function Remove-WingetRecent {
    <#
    .SYNOPSIS
        Uninstall recently installed winget packages.

    .DESCRIPTION
        Shows packages installed in the last X days and allows interactive selection
        of which packages to uninstall.

    .PARAMETER Days
        Number of days to look back for recently installed packages. Default is 1 day.

    .EXAMPLE
        Remove-WingetRecent
        Shows packages installed in the last day and allows you to select which to uninstall.

    .EXAMPLE
        Remove-WingetRecent -Days 7
        Shows packages installed in the last 7 days.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Days = 1
    )

    # Ensure PwshSpectreConsole is available
    if (-not (Get-Module -Name PwshSpectreConsole)) {
        if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
            Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
        }
    }

    Write-Host "Searching for packages installed in the last " -ForegroundColor Cyan -NoNewline
    Write-Host "$Days day$(if ($Days -ne 1) { 's' })..." -ForegroundColor Yellow

    try {
        Write-Host "Reading Windows Registry for installation dates..." -ForegroundColor Cyan

        # Get installation dates from Windows Registry
        $uninstallPaths = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        $registryApps = @{}
        foreach ($path in $uninstallPaths) {
            try {
                Get-ItemProperty $path -ErrorAction SilentlyContinue | ForEach-Object {
                    $displayName = $_.DisplayName
                    $installDate = $_.InstallDate

                    if ($displayName -and $installDate) {
                        # Parse InstallDate (format: YYYYMMDD)
                        try {
                            $year = $installDate.Substring(0, 4)
                            $month = $installDate.Substring(4, 2)
                            $day = $installDate.Substring(6, 2)
                            $date = [DateTime]::ParseExact("$year-$month-$day", "yyyy-MM-dd", $null)

                            if (-not $registryApps.ContainsKey($displayName)) {
                                $registryApps[$displayName] = $date
                            }
                        }
                        catch {
                            # Skip invalid dates
                        }
                    }
                }
            }
            catch {
                # Skip inaccessible registry paths
            }
        }

        Write-Host "Found installation dates for $($registryApps.Count) programs" -ForegroundColor DarkGray
        Write-Host ""

        # Get list of installed packages from winget
        $listOutput = winget list --disable-interactivity 2>&1 | Out-String
        $listLines = $listOutput -split "`n"

        $installedPackages = [System.Collections.Generic.List[Object]]::new()
        $seenIds = @{}
        $headerFound = $false
        $idColStart = -1
        $idColEnd = -1
        $nameColEnd = -1

        $cutoffDate = (Get-Date).AddDays(-$Days).Date

        foreach ($line in $listLines) {
            # Find the header line to determine column positions
            if ($line -match '^Name\s+Id\s+') {
                $nameColEnd = $line.IndexOf('Id') - 1
                $idColStart = $line.IndexOf('Id')
                if ($line -match 'Version') {
                    $idColEnd = $line.IndexOf('Version') - 1
                } else {
                    $idColEnd = $line.Length
                }
                continue
            }

            # Skip until we find the header separator line (dashes)
            if ($line -match '^-+') {
                $headerFound = $true
                continue
            }

            if ($headerFound -and $line.Trim() -ne '' -and $idColStart -gt 0 -and $line.Length -gt $idColStart) {
                # Extract package ID and Name
                $endPos = if ($idColEnd -lt $line.Length) { $idColEnd } else { $line.Length }
                $packageId = $line.Substring($idColStart, $endPos - $idColStart).Trim()
                $packageName = if ($nameColEnd -gt 0 -and $line.Length -gt $nameColEnd) {
                    $line.Substring(0, $nameColEnd).Trim()
                } else {
                    ""
                }

                # Only process valid package IDs and avoid duplicates
                if ($packageId -and $packageId -match '^[A-Za-z0-9\.\-_]+$' -and -not $seenIds.ContainsKey($packageId)) {
                    # Try to find installation date from registry
                    $installDate = $null

                    # Try exact name match first
                    if ($registryApps.ContainsKey($packageName)) {
                        $installDate = $registryApps[$packageName]
                    }
                    else {
                        # Try fuzzy match - check if registry name contains package name or vice versa
                        foreach ($regName in $registryApps.Keys) {
                            # Check if regName contains packageName
                            if ($regName.Length -ge $packageName.Length -and $regName.IndexOf($packageName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                $installDate = $registryApps[$regName]
                                break
                            }
                            # Check if packageName contains regName
                            if ($packageName.Length -ge $regName.Length -and $packageName.IndexOf($regName, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                                $installDate = $registryApps[$regName]
                                break
                            }
                        }
                    }

                    # Only add if within time window (or no date found and we show all)
                    if ($installDate -and $installDate -ge $cutoffDate) {
                        $installedPackages.Add(@{
                            Id = $packageId
                            Name = $packageName
                            InstallDate = $installDate
                            DisplayLine = $line.Trim()
                        })
                        $seenIds[$packageId] = $true
                    }
                }
            }
        }

        if ($installedPackages.Count -eq 0) {
            Write-Warning "No packages installed in the last $Days day$(if ($Days -ne 1) { 's' })."
            Write-Host "Note: Only packages with registry install dates can be tracked." -ForegroundColor DarkGray
            return
        }

        # Sort by install date (most recent first)
        $installedPackages = $installedPackages | Sort-Object -Property InstallDate -Descending

        Write-Host "Found " -ForegroundColor Green -NoNewline
        Write-Host "$($installedPackages.Count)" -ForegroundColor White -NoNewline
        Write-Host " package(s) installed in the last $Days day$(if ($Days -ne 1) { 's' })" -ForegroundColor Green
        Write-Host ""

        # Interactive selection using Spectre Console
        if (Get-Module -Name PwshSpectreConsole) {
            try {
                # Create a lookup table: DisplayLine -> Id with install date
                $displayToId = @{}
                $displayLines = $installedPackages | ForEach-Object {
                    $dateStr = $_.InstallDate.ToString('yyyy-MM-dd')
                    $displayText = "($dateStr) $($_.Id)"
                    $displayToId[$displayText] = $_.Id
                    $displayText
                }

                $selectedLines = Read-SpectreMultiSelection -Title "[red]⚠ Select packages to UNINSTALL (Space to toggle, Enter to confirm)[/]" `
                    -Choices $displayLines `
                    -PageSize 20 `
                    -Color "Red"

                if ($selectedLines.Count -eq 0) {
                    Write-Host "No packages selected." -ForegroundColor Yellow
                    return
                }

                # Convert selected display lines back to package IDs
                $selectedPackages = $selectedLines | ForEach-Object { $displayToId[$_] }

                Write-Host ""
                Write-Host "⚠ WARNING: " -ForegroundColor Red -NoNewline
                Write-Host "You are about to UNINSTALL " -ForegroundColor Yellow -NoNewline
                Write-Host "$($selectedPackages.Count)" -ForegroundColor White -NoNewline
                Write-Host " package(s):" -ForegroundColor Yellow
                Write-Host ""

                foreach ($pkgId in $selectedPackages) {
                    Write-Host "   • " -ForegroundColor Red -NoNewline
                    Write-Host $pkgId -ForegroundColor White
                }

                Write-Host ""
                Write-Host "Type " -NoNewline -ForegroundColor Yellow
                Write-Host "YES" -NoNewline -ForegroundColor Red
                Write-Host " to confirm uninstallation, or anything else to cancel: " -NoNewline -ForegroundColor Yellow
                $confirmation = Read-Host

                if ($confirmation -ne "YES") {
                    Write-Host "Uninstallation cancelled." -ForegroundColor Green
                    return
                }

                Write-Host ""
                Write-Host ("=" * 60) -ForegroundColor Red
                Write-Host "Starting Uninstallation Process" -ForegroundColor Red
                Write-Host ("=" * 60) -ForegroundColor Red
                Write-Host ""

                $successCount = 0
                $failCount = 0

                foreach ($packageId in $selectedPackages) {
                    Write-Host ">>> Uninstalling: " -ForegroundColor Magenta -NoNewline
                    Write-Host $packageId -ForegroundColor White

                    winget uninstall --id $packageId --accept-source-agreements

                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✓ Successfully uninstalled " -ForegroundColor Green -NoNewline
                        Write-Host $packageId -ForegroundColor White
                        $successCount++
                    }
                    else {
                        Write-Host "✗ Failed to uninstall " -ForegroundColor Red -NoNewline
                        Write-Host $packageId -ForegroundColor White
                        $failCount++
                    }
                    Write-Host ""
                }

                Write-Host ("=" * 60) -ForegroundColor Green
                Write-Host "Uninstallation Complete" -ForegroundColor Green
                Write-Host ("=" * 60) -ForegroundColor Green
                Write-Host "Success: " -ForegroundColor Green -NoNewline
                Write-Host $successCount -ForegroundColor White -NoNewline
                Write-Host " | Failed: " -ForegroundColor Red -NoNewline
                Write-Host $failCount -ForegroundColor White
            }
            catch {
                Write-Warning "Interactive selection error: $_"
                Write-Host "Installed packages:" -ForegroundColor Cyan
                $installedPackages | ForEach-Object {
                    Write-Host "  • $($_.Id)" -ForegroundColor White
                }
                Write-Host ""
                Write-Host "Use 'winget uninstall <PackageName>' to uninstall manually." -ForegroundColor Yellow
                return
            }
        }
        else {
            Write-Host "Installed packages:" -ForegroundColor Cyan
            $installedPackages | ForEach-Object {
                Write-Host "  • $($_.Id)" -ForegroundColor White
            }
            Write-Host ""
            Write-Host "To uninstall a package: " -ForegroundColor Cyan -NoNewline
            Write-Host "winget uninstall <PackageName>" -ForegroundColor Yellow
            Write-Host "Note: Install PwshSpectreConsole for interactive package selection." -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Error "Failed to get installed packages: $_"
    }
}


# EndRegion

# Region: Public/Repair-WingetBatchManager.ps1
function Repair-WingetBatchManager {
    <#
    .SYNOPSIS
        Diagnose and repair common winget issues.

    .DESCRIPTION
        Checks for common winget problems including:
        - winget.exe not found in PATH
        - Microsoft.WinGet.Client module not installed
        - App Installer package not registered
        Attempts automatic repair for each detected issue.

    .EXAMPLE
        Repair-WingetBatchManager
        Runs full diagnostics and attempts automatic repair.
    #>

    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "WingetBatch Diagnostic & Repair Tool" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""

    $issuesFound = 0
    $issuesFixed = 0

    # Check 1: Microsoft.WinGet.Client module
    Write-Host "[CHECK] Microsoft.WinGet.Client module..." -ForegroundColor Cyan -NoNewline
    $wingetModule = Get-Module -ListAvailable -Name Microsoft.WinGet.Client | Select-Object -First 1
    if ($wingetModule) {
        Write-Host " OK (v$($wingetModule.Version))" -ForegroundColor Green
    }
    else {
        Write-Host " MISSING" -ForegroundColor Red
        $issuesFound++
        Write-Host "  [FIX] Installing Microsoft.WinGet.Client..." -ForegroundColor Yellow
        try {
            Install-Module -Name Microsoft.WinGet.Client -Scope CurrentUser -Force -SkipPublisherCheck
            Write-Host "  [OK] Installed successfully." -ForegroundColor Green
            $issuesFixed++
        }
        catch {
            Write-Host "  [FAIL] Could not install: $_" -ForegroundColor Red
        }
    }

    # Check 2: winget.exe in PATH
    Write-Host "[CHECK] winget.exe in PATH..." -ForegroundColor Cyan -NoNewline
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-Host " OK ($($wingetCmd.Source))" -ForegroundColor Green
    }
    else {
        Write-Host " NOT FOUND" -ForegroundColor Red
        $issuesFound++

        # Try known locations
        $knownPaths = @(
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
            "C:\Users\$env:USERNAME\AppData\Local\Microsoft\WindowsApps\winget.exe"
        )

        $foundPath = $knownPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($foundPath) {
            $wingetDir = Split-Path $foundPath -Parent
            Write-Host "  [FIX] Found winget at: $foundPath" -ForegroundColor Yellow
            Write-Host "  [FIX] Adding to current session PATH..." -ForegroundColor Yellow
            $env:PATH = "$wingetDir;$env:PATH"
            Write-Host "  [OK] winget.exe is now accessible in this session." -ForegroundColor Green
            Write-Host "  [NOTE] This fix is session-only. To persist, add to your system PATH:" -ForegroundColor DarkGray
            Write-Host "         $wingetDir" -ForegroundColor White
            $issuesFixed++
        }
        else {
            Write-Host "  [FIX] Attempting to re-register App Installer..." -ForegroundColor Yellow
            try {
                Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
                Write-Host "  [OK] App Installer re-registered. Restart your terminal." -ForegroundColor Green
                $issuesFixed++
            }
            catch {
                Write-Host "  [FAIL] Could not re-register App Installer: $_" -ForegroundColor Red
            }
        }
    }

    # Check 3: Repair-WinGetPackageManager
    Write-Host "[CHECK] WinGet Package Manager health..." -ForegroundColor Cyan -NoNewline
    try {
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        $version = Get-WinGetVersion -ErrorAction Stop
        Write-Host " OK (WinGet v$version)" -ForegroundColor Green
    }
    catch {
        Write-Host " DEGRADED" -ForegroundColor Yellow
        $issuesFound++
        Write-Host "  [FIX] Running Repair-WinGetPackageManager..." -ForegroundColor Yellow
        try {
            Repair-WinGetPackageManager -Force -ErrorAction Stop
            Write-Host "  [OK] Package manager repaired." -ForegroundColor Green
            $issuesFixed++
        }
        catch {
            Write-Host "  [FAIL] Repair failed: $_" -ForegroundColor Red
            Write-Host "  [TIP] Try running PowerShell as Administrator and retry." -ForegroundColor DarkGray
        }
    }

    # Check 4: COM API functional test
    Write-Host "[CHECK] COM API search functional test..." -ForegroundColor Cyan -NoNewline
    try {
        $testResult = Find-WinGetPackage -Query "Microsoft.PowerShell" -Count 1 -ErrorAction Stop
        if ($testResult) {
            Write-Host " OK (Search returned results)" -ForegroundColor Green
        }
        else {
            Write-Host " WARNING (Search returned no results)" -ForegroundColor Yellow
            $issuesFound++
        }
    }
    catch {
        Write-Host " FAILED" -ForegroundColor Red
        $issuesFound++
        Write-Host "  [!] COM API search is not functional: $_" -ForegroundColor Red
    }

    # Summary
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    if ($issuesFound -eq 0) {
        Write-Host "[OK] All checks passed. WingetBatch is fully operational." -ForegroundColor Green
    }
    elseif ($issuesFixed -eq $issuesFound) {
        Write-Host "[OK] Found $issuesFound issue(s), all repaired successfully." -ForegroundColor Green
        Write-Host "     You may need to restart your terminal for changes to take effect." -ForegroundColor DarkGray
    }
    else {
        Write-Host "[!] Found $issuesFound issue(s), repaired $issuesFixed." -ForegroundColor Yellow
        Write-Host "    Some issues require manual intervention (see above)." -ForegroundColor DarkGray
    }
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

# EndRegion

# Region: Public/Set-WingetBatchConfig.ps1
function Set-WingetBatchConfig {
    <#
    .SYNOPSIS
        Configure WingetBatch global settings.

    .DESCRIPTION
        Sets module-level configuration options such as the default SearchMatchOption.

    .PARAMETER SearchMatchOption
        Sets the default match behavior for search.
        Valid values: ContainsCaseInsensitive (default), EqualsCaseInsensitive, StartsWithCaseInsensitive.

    .EXAMPLE
        Set-WingetBatchConfig -SearchMatchOption EqualsCaseInsensitive
        Configures the module to strictly match package names instead of wildcard searching.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet("ContainsCaseInsensitive", "EqualsCaseInsensitive", "StartsWithCaseInsensitive")]
        [string]$SearchMatchOption
    )

    $configDir = Get-WingetBatchConfigDir
    $configPath = Join-Path $configDir "config.json"
    
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $config = @{}
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            # Convert PSObject back to hashtable
            $hash = @{}
            $config.psobject.properties | ForEach-Object { $hash[$_.Name] = $_.Value }
            $config = $hash
        } catch {
            Write-Warning "Existing config corrupt. Starting fresh."
        }
    }

    if ($PSBoundParameters.ContainsKey('SearchMatchOption')) {
        $config.SearchMatchOption = $SearchMatchOption
    }

    $config | ConvertTo-Json -Depth 5 | Out-File $configPath -Encoding UTF8
    Write-Host "WingetBatch configuration updated successfully." -ForegroundColor Green
}

# EndRegion

# Region: Public/Set-WingetBatchGitHubToken.ps1
function Set-WingetBatchGitHubToken {
    <#
    .SYNOPSIS
        Set or update the GitHub Personal Access Token for API authentication.

    .DESCRIPTION
        Stores a GitHub token securely to avoid API rate limits when checking for new packages.
        Without a token, you're limited to 60 requests/hour. With a token, you get 5,000 requests/hour.
        The token is stored securely using PowerShell's Export-Clixml with SecureString.

        For an interactive wizard, use New-WingetBatchGitHubToken instead.

    .PARAMETER Token
        Your GitHub Personal Access Token. Create one at https://github.com/settings/tokens
        No special permissions are required.

    .PARAMETER Remove
        Remove the stored GitHub token.

    .EXAMPLE
        Set-WingetBatchGitHubToken -Token "ghp_xxxxxxxxxxxx"
        Stores your GitHub token for future use.

    .EXAMPLE
        Set-WingetBatchGitHubToken -Remove
        Removes the stored GitHub token.

    .EXAMPLE
        New-WingetBatchGitHubToken
        Use the interactive wizard instead.

    .LINK
        https://github.com/settings/tokens
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='Set')]
        [string]$Token,

        [Parameter(Mandatory=$true, ParameterSetName='Remove')]
        [switch]$Remove
    )

    $configDir = Get-WingetBatchConfigDir
    $tokenFile = Join-Path $configDir "github_token.clixml"
    $legacyFile = Join-Path $configDir "github_token.txt"

    if ($Remove) {
        $removed = $false
        if (Test-Path $tokenFile) {
            Remove-Item $tokenFile -Force
            $removed = $true
        }
        if (Test-Path $legacyFile) {
            Remove-Item $legacyFile -Force
            $removed = $true
        }

        if ($removed) {
            Write-Host "✓ GitHub token removed successfully" -ForegroundColor Green
        }
        else {
            Write-Host "No GitHub token found to remove" -ForegroundColor Yellow
        }
        return
    }

    # Create config directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Store token securely
    try {
        $SecureToken = $Token | ConvertTo-SecureString -AsPlainText -Force
        $SecureToken | Export-Clixml -Path $tokenFile

        # Remove legacy plaintext file if it exists
        if (Test-Path $legacyFile) {
            Remove-Item $legacyFile -Force
        }

        Write-Host "✓ GitHub token saved securely!" -ForegroundColor Green
        Write-Host "  Location: $tokenFile" -ForegroundColor DarkGray
        Write-Host "  The token will now be used automatically for API requests." -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  ℹ Security Note:" -ForegroundColor Yellow
        Write-Host "  • Token stored securely using PowerShell encryption (bound to your user account)" -ForegroundColor DarkGray
        Write-Host "  • Only increases API rate limits - cannot modify repositories or access private data" -ForegroundColor DarkGray
        Write-Host "  • Revoke anytime at: https://github.com/settings/tokens" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "❌ Failed to save token securely: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}


# EndRegion

# Region: Public/Start-WingetUpdateCheck.ps1
function Start-WingetUpdateCheck {
    <#
    .SYNOPSIS
        Checks for winget updates in the background.

    .DESCRIPTION
        This command is typically triggered by your PowerShell profile if you've enabled update notifications via Enable-WingetUpdateNotifications.
        It runs winget upgrade in a background job and pops a native Windows toast notification if any updates are found.
        It respects the interval set in the configuration.

    .PARAMETER Force
        Ignore the configured check interval and check immediately.
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    $configDir = Get-WingetBatchConfigDir
    $configFile = Join-Path $configDir "config.json"

    if (-not (Test-Path $configFile)) {
        return
    }

    $config = Get-Content $configFile -Raw | ConvertFrom-Json
    if (-not $config.UpdateNotificationsEnabled) {
        return
    }

    if (-not $Force) {
        if ($config.LastCheck) {
            try {
                $lastCheckTime = [datetime]$config.LastCheck
                $interval = $config.CheckInterval
                if ($interval -gt 0 -and (Get-Date) -lt $lastCheckTime.AddHours($interval)) {
                    return
                }
            } catch {
                # Invalid date format, just proceed
            }
        } elseif (-not $config.CheckOnStartup) {
            # No LastCheck, but CheckOnStartup is false.
            $config.LastCheck = (Get-Date).ToString("o")
            $config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8 -Force
            return
        }
    }

    # Update LastCheck immediately to prevent multiple rapid checks from multiple terminal sessions
    $config.LastCheck = (Get-Date).ToString("o")
    $config | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8 -Force

    $jobScript = {
        try {
            $updates = winget upgrade 2>&1
            $updateCount = 0
            $packages = @()
            
            foreach ($line in $updates) {
                if ($line -match '^\s*[a-zA-Z]') {
                    # Filter out headers, empty lines, and non-package winget outputs
                    if ($line -notmatch 'Name\s+|Id\s+|Version\s+|Available\s+|Source\s+|-{5,}|No installed package found|Failed in attempting to update|upgrades available') {
                        $updateCount++
                        if ($packages.Count -lt 3) {
                            $parts = $line -split '\s{2,}'
                            if ($parts.Count -gt 0) {
                                $packages += $parts[0].Trim()
                            }
                        }
                    }
                }
            }

            if ($updateCount -gt 0) {
                $pkgText = $packages -join ", "
                if ($updateCount -gt 3) {
                    $pkgText += " and $($updateCount - 3) more"
                }

                Add-Type -AssemblyName System.Windows.Forms
                $balloon = New-Object System.Windows.Forms.NotifyIcon
                $path = (Get-Process -id $pid).Path
                $balloon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
                $balloon.BalloonTipIcon = "Info"
                $balloon.BalloonTipTitle = "Winget Updates Available ($updateCount)"
                $balloon.BalloonTipText = "Updates available for: $pkgText.`nRun 'Invoke-WinGetBatch' to install."
                $balloon.Visible = $true
                $balloon.ShowBalloonTip(10000)
                Start-Sleep -Seconds 10
                $balloon.Dispose()
            }
        } catch {
            # Ignore background job errors so it fails silently in profile
        }
    }

    # Start the check in a background job so it doesn't block the user's terminal startup
    Start-Job -ScriptBlock $jobScript -Name "WingetUpdateCheck" | Out-Null
}

# EndRegion

# Region: Public/Update-WingetBatch.ps1
function Update-WingetBatch {
    <#
    .SYNOPSIS
        Updates the WingetBatch module from the PowerShell Gallery.
    #>
    [CmdletBinding()]
    param()
    Write-Host "Checking for updates to WingetBatch module..." -ForegroundColor Cyan
    Update-Module -Name WingetBatch -Force -AcceptLicense -ErrorAction Stop
    Write-Host "WingetBatch module updated successfully!" -ForegroundColor Green
}


# EndRegion

# Region: Public/Watch-WingetPackages.ps1
function Watch-WingetPackages {
    <#
    .SYNOPSIS
        Live terminal dashboard for monitoring winget package state.

    .DESCRIPTION
        Displays a real-time refreshing dashboard showing:
        - Total installed packages count
        - Packages with available updates
        - Recently installed packages (last 7 days)
        - Source health status
        - Disk usage by package source
        - System winget version and health

        Refreshes automatically at a configurable interval. Press Ctrl+C to exit.

    .PARAMETER RefreshInterval
        Seconds between dashboard refreshes. Default: 30.

    .PARAMETER Once
        Display the dashboard once and exit (no refresh loop).

    .EXAMPLE
        Watch-WingetPackages
        Shows the live dashboard, refreshing every 30 seconds.

    .EXAMPLE
        Watch-WingetPackages -RefreshInterval 60
        Refresh every 60 seconds.

    .EXAMPLE
        Watch-WingetPackages -Once
        Show dashboard once (useful for scripts/CI).

    .LINK
        https://github.com/thebubbsy/WingetBatch
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(5, 3600)]
        [int]$RefreshInterval = 30,

        [Parameter()]
        [switch]$Once
    )

    begin {
        if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
            try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop }
            catch {
                Write-Error "Microsoft.WinGet.Client module is required."
                return
            }
        }
        if (-not (Get-Module -Name PwshSpectreConsole)) {
            if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
                Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
            }
        }
    }

    process {
        function Get-DashboardData {
            $data = @{}

            # Winget version
            try {
                $data['WingetVersion'] = (Get-WinGetVersion -ErrorAction Stop).ToString()
                $data['WingetHealthy'] = $true
            } catch {
                $data['WingetVersion'] = 'N/A'
                $data['WingetHealthy'] = $false
            }

            # Installed packages
            $installed = Get-WinGetPackage -ErrorAction SilentlyContinue
            $data['TotalPackages'] = if ($installed) { $installed.Count } else { 0 }

            # Updates available
            $updates = @()
            if ($installed) {
                $updates = @($installed | Where-Object { $_.IsUpdateAvailable })
            }
            $data['UpdatesAvailable'] = $updates.Count
            $data['UpdateList'] = $updates | Select-Object -First 10 Id, Name, InstalledVersion, AvailableVersion

            # Source breakdown
            $sourceGroups = @{}
            if ($installed) {
                foreach ($pkg in $installed) {
                    $src = if ($pkg.Source) { $pkg.Source } else { 'unknown' }
                    if (-not $sourceGroups.ContainsKey($src)) { $sourceGroups[$src] = 0 }
                    $sourceGroups[$src]++
                }
            }
            $data['Sources'] = $sourceGroups

            # Recently installed (from registry - last 7 days)
            $recentCount = 0
            try {
                $regPaths = @(
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
                )
                $sevenDaysAgo = (Get-Date).AddDays(-7)
                foreach ($regPath in $regPaths) {
                    $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue |
                        Where-Object { $_.InstallDate }
                    foreach ($entry in $entries) {
                        try {
                            $installDate = [DateTime]::ParseExact($entry.InstallDate, 'yyyyMMdd', $null)
                            if ($installDate -ge $sevenDaysAgo) { $recentCount++ }
                        } catch {}
                    }
                }
            } catch {}
            $data['RecentInstalls'] = $recentCount

            # Winget source index age
            $wingetDir = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\Microsoft.Winget.Source_8wekyb3d8bbwe\winget"
            if (Test-Path "$wingetDir\source.db") {
                $dbAge = (Get-Date) - (Get-Item "$wingetDir\source.db").LastWriteTime
                $data['IndexAge'] = "$([Math]::Floor($dbAge.TotalHours))h ago"
                $data['IndexStale'] = $dbAge.TotalDays -gt 7
            } else {
                $data['IndexAge'] = 'Unknown'
                $data['IndexStale'] = $false
            }

            # GitHub token status
            $data['GitHubAuth'] = $false
            try {
                $token = Get-WingetBatchGitHubToken
                if ($token) { $data['GitHubAuth'] = $true }
            } catch {}

            $data['Timestamp'] = Get-Date
            return $data
        }

        function Show-Dashboard {
            param($data)

            # Clear screen
            [Console]::Clear()

            $border = '═' * 62
            $thinBorder = '─' * 62

            Write-Host ""
            Write-Host "  ╔$border╗" -ForegroundColor Cyan
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "  WINGETBATCH LIVE DASHBOARD" -ForegroundColor White -NoNewline
            $padRight = 62 - 30
            Write-Host (" " * $padRight) -NoNewline
            Write-Host "║" -ForegroundColor Cyan
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            $timeStr = "  Last refresh: $($data.Timestamp.ToString('HH:mm:ss'))"
            Write-Host $timeStr -ForegroundColor DarkGray -NoNewline
            $padRight2 = 62 - $timeStr.Length
            Write-Host (" " * $padRight2) -NoNewline
            Write-Host "║" -ForegroundColor Cyan
            Write-Host "  ╠$border╣" -ForegroundColor Cyan

            # System Health Row
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "  SYSTEM HEALTH" -ForegroundColor Yellow -NoNewline
            Write-Host (" " * (62 - 15)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            $wingetStatus = if ($data.WingetHealthy) { "[OK]" } else { "[!!]" }
            $wingetColor = if ($data.WingetHealthy) { 'Green' } else { 'Red' }
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "    Winget Engine:    " -ForegroundColor Gray -NoNewline
            Write-Host "$wingetStatus v$($data.WingetVersion)" -ForegroundColor $wingetColor -NoNewline
            Write-Host (" " * (62 - 23 - $wingetStatus.Length - $data.WingetVersion.ToString().Length - 2)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            $indexStatus = if ($data.IndexStale) { "[STALE]" } else { "[FRESH]" }
            $indexColor = if ($data.IndexStale) { 'Yellow' } else { 'Green' }
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "    Source Index:     " -ForegroundColor Gray -NoNewline
            Write-Host "$indexStatus ($($data.IndexAge))" -ForegroundColor $indexColor -NoNewline
            $idxLen = 23 + $indexStatus.Length + $data.IndexAge.Length + 3
            Write-Host (" " * [Math]::Max(0, 62 - $idxLen)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            $authStatus = if ($data.GitHubAuth) { "[AUTHENTICATED]" } else { "[ANONYMOUS]" }
            $authColor = if ($data.GitHubAuth) { 'Green' } else { 'DarkGray' }
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "    GitHub API:       " -ForegroundColor Gray -NoNewline
            Write-Host $authStatus -ForegroundColor $authColor -NoNewline
            $authLen = 23 + $authStatus.Length
            Write-Host (" " * [Math]::Max(0, 62 - $authLen)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host (" " * 62) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            # Package Stats Row
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "  PACKAGE STATISTICS" -ForegroundColor Yellow -NoNewline
            Write-Host (" " * (62 - 20)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "    Total Installed:  " -ForegroundColor Gray -NoNewline
            Write-Host "$($data.TotalPackages)" -ForegroundColor White -NoNewline
            $totalLen = 23 + $data.TotalPackages.ToString().Length
            Write-Host (" " * [Math]::Max(0, 62 - $totalLen)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            $updateColor = if ($data.UpdatesAvailable -gt 0) { 'Yellow' } else { 'Green' }
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "    Updates Pending:  " -ForegroundColor Gray -NoNewline
            Write-Host "$($data.UpdatesAvailable)" -ForegroundColor $updateColor -NoNewline
            $updLen = 23 + $data.UpdatesAvailable.ToString().Length
            Write-Host (" " * [Math]::Max(0, 62 - $updLen)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "    Recent (7 days):  " -ForegroundColor Gray -NoNewline
            Write-Host "$($data.RecentInstalls)" -ForegroundColor White -NoNewline
            $recLen = 23 + $data.RecentInstalls.ToString().Length
            Write-Host (" " * [Math]::Max(0, 62 - $recLen)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host (" " * 62) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            # Source Breakdown
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host "  SOURCE BREAKDOWN" -ForegroundColor Yellow -NoNewline
            Write-Host (" " * (62 - 18)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            foreach ($src in $data.Sources.Keys | Sort-Object) {
                $count = $data.Sources[$src]
                $srcColor = if ($src -eq 'msstore') { 'Magenta' } elseif ($src -eq 'winget') { 'Cyan' } else { 'Gray' }
                $line = "    $($src): $($count)"
                Write-Host "  ║" -ForegroundColor Cyan -NoNewline
                Write-Host "    " -NoNewline
                Write-Host "$src" -ForegroundColor $srcColor -NoNewline
                Write-Host ": $count" -ForegroundColor White -NoNewline
                Write-Host (" " * [Math]::Max(0, 62 - $line.Length - 4)) -NoNewline
                Write-Host "║" -ForegroundColor Cyan
            }

            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            Write-Host (" " * 62) -NoNewline
            Write-Host "║" -ForegroundColor Cyan

            # Pending Updates (top 5)
            if ($data.UpdatesAvailable -gt 0) {
                Write-Host "  ║" -ForegroundColor Cyan -NoNewline
                Write-Host "  PENDING UPDATES (top 5)" -ForegroundColor Yellow -NoNewline
                Write-Host (" " * (62 - 25)) -NoNewline
                Write-Host "║" -ForegroundColor Cyan

                $shown = 0
                foreach ($upd in $data.UpdateList) {
                    if ($shown -ge 5) { break }
                    $line = "    $($upd.Id): $($upd.InstalledVersion) -> $($upd.AvailableVersion)"
                    if ($line.Length -gt 60) { $line = $line.Substring(0, 57) + "..." }
                    Write-Host "  ║" -ForegroundColor Cyan -NoNewline
                    Write-Host $line -ForegroundColor DarkGray -NoNewline
                    Write-Host (" " * [Math]::Max(0, 62 - $line.Length)) -NoNewline
                    Write-Host "║" -ForegroundColor Cyan
                    $shown++
                }

                if ($data.UpdatesAvailable -gt 5) {
                    Write-Host "  ║" -ForegroundColor Cyan -NoNewline
                    Write-Host "    ... and $($data.UpdatesAvailable - 5) more" -ForegroundColor DarkGray -NoNewline
                    $moreLine = "    ... and $($data.UpdatesAvailable - 5) more"
                    Write-Host (" " * [Math]::Max(0, 62 - $moreLine.Length)) -NoNewline
                    Write-Host "║" -ForegroundColor Cyan
                }

                Write-Host "  ║" -ForegroundColor Cyan -NoNewline
                Write-Host (" " * 62) -NoNewline
                Write-Host "║" -ForegroundColor Cyan
            }

            # Footer
            Write-Host "  ╠$border╣" -ForegroundColor Cyan
            Write-Host "  ║" -ForegroundColor Cyan -NoNewline
            $footer = "  Refresh: ${RefreshInterval}s | Ctrl+C to exit | Get-WingetUpdates to update"
            Write-Host $footer -ForegroundColor DarkGray -NoNewline
            Write-Host (" " * [Math]::Max(0, 62 - $footer.Length)) -NoNewline
            Write-Host "║" -ForegroundColor Cyan
            Write-Host "  ╚$border╝" -ForegroundColor Cyan
            Write-Host ""
        }

        # Main loop
        do {
            $dashboardData = Get-DashboardData
            Show-Dashboard -data $dashboardData

            if ($Once) { break }

            Start-Sleep -Seconds $RefreshInterval
        } while ($true)
    }
}

# EndRegion

