<#
.SYNOPSIS
    WingetBatch Standalone Script
    
.DESCRIPTION
    This is an automatically generated standalone script containing all the functions
    from the WingetBatch module. You can dot-source this script directly if you don't
    want to install the module.
#>

# Region: Private/Compare-WingetVersion.ps1
function Compare-WingetVersion {
    <#
    .SYNOPSIS
        Compare two package version strings. Returns -1, 0 or 1.

    .DESCRIPTION
        Package versions are not always valid [version] values ("1.2.3.4.5",
        "2024.01", "1.0.0-beta2"), and sorting them as text puts 9.0 above 10.0.
        Segments are split on . - + _ and compared numerically when both are numbers.
        A numeric segment beats a text segment, and a release beats its pre-release
        ("1.0" > "1.0-beta").
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][AllowNull()][string]$ReferenceVersion,
        [AllowEmptyString()][AllowNull()][string]$DifferenceVersion
    )

    # Split on separators, then between letters and digits ("beta10" -> "beta", "10")
    $split = {
        param($v)
        if (-not $v) { return @() }
        @($v.Trim().TrimStart('vV') -split '[.\-+_ ]' | ForEach-Object { $_ -split '(?<=\d)(?=\D)|(?<=\D)(?=\d)' } | Where-Object { $_ -ne '' })
    }
    $a = & $split $ReferenceVersion
    $b = & $split $DifferenceVersion

    $max = [Math]::Max($a.Count, $b.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $x = if ($i -lt $a.Count) { $a[$i] } else { $null }
        $y = if ($i -lt $b.Count) { $b[$i] } else { $null }

        $xNum = $null -ne $x -and $x -match '^\d+$'
        $yNum = $null -ne $y -and $y -match '^\d+$'

        # A missing segment counts as 0 against a number, and as "release" against text
        if ($null -eq $x) { if ($yNum) { $x = '0'; $xNum = $true } else { return 1 } }
        if ($null -eq $y) { if ($xNum) { $y = '0'; $yNum = $true } else { return -1 } }

        if ($xNum -and $yNum) {
            $xt = $x.TrimStart('0'); $yt = $y.TrimStart('0')
            if ($xt.Length -ne $yt.Length) { return [Math]::Sign($xt.Length - $yt.Length) }
            $c = [string]::CompareOrdinal($xt, $yt)
            if ($c -ne 0) { return [Math]::Sign($c) }
        }
        elseif ($xNum) { return 1 }
        elseif ($yNum) { return -1 }
        else {
            $c = [string]::Compare($x, $y, [System.StringComparison]::OrdinalIgnoreCase)
            if ($c -ne 0) { return [Math]::Sign($c) }
        }
    }
    return 0
}

# EndRegion

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

# Region: Private/ConvertTo-WingetActionResult.ps1
function ConvertTo-WingetActionResult {
    <#
    .SYNOPSIS
        Normalize a Microsoft.WinGet.Client install/update/uninstall result.

    .DESCRIPTION
        Install-WinGetPackage, Update-WinGetPackage and Uninstall-WinGetPackage do not
        throw when the installer fails - they return a result object whose Status is
        something other than 'Ok'. This turns that object into a flat result that
        callers can trust.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        $Result,

        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [ValidateSet('Install', 'Update', 'Uninstall')]
        [string]$Action
    )

    if ($null -eq $Result) {
        return [PSCustomObject]@{
            Id             = $Id
            Action         = $Action
            Succeeded      = $false
            Status         = 'NoResult'
            RebootRequired = $false
            Message        = 'WinGet returned no result.'
        }
    }

    # Cmdlets occasionally emit more than one object; the result is the last one
    $r = @($Result)[-1]
    $status = [string]$r.Status

    $succeeded = $status -eq 'Ok'
    $message = $null

    # Updating something that is already current is not a failure
    if (-not $succeeded -and $Action -eq 'Update' -and $status -eq 'NoApplicableUpgrade') {
        $succeeded = $true
        $message = 'Already up to date.'
    }

    if (-not $succeeded) {
        $parts = [System.Collections.Generic.List[string]]::new()
        $parts.Add($(if ($status) { $status } else { 'Failed' }))
        if ($r.InstallerErrorCode) { $parts.Add("installer exit code $($r.InstallerErrorCode)") }
        if ($r.UninstallerErrorCode) { $parts.Add("uninstaller exit code $($r.UninstallerErrorCode)") }
        if ($r.ExtendedErrorCode -and $r.ExtendedErrorCode.Message) { $parts.Add($r.ExtendedErrorCode.Message) }
        $message = $parts -join ' - '
    }

    [PSCustomObject]@{
        Id             = $Id
        Action         = $Action
        Succeeded      = $succeeded
        Status         = $(if ($status) { $status } else { 'Unknown' })
        RebootRequired = [bool]$r.RebootRequired
        Message        = $message
    }
}

# EndRegion

# Region: Private/Export-WingetHtmlReport.ps1
function Export-WingetHtmlReport {
    <#
    .SYNOPSIS
        Exports an array of objects to a highly styled, interactive HTML report.

    .DESCRIPTION
        Writes an array of objects to a dark-mode HTML file with sortable columns
        and a live search filter. Callers are responsible for opening it.

    .PARAMETER Data
        The array of custom objects to export.

    .PARAMETER ReportTitle
        The title to display at the top of the report.

    .PARAMETER FilePath
        Where to write the .html file. Missing folders are created.
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

    # Make sure the target folder exists (the default C:\temp often does not)
    $saveDir = Split-Path $FilePath -Parent
    if ($saveDir -and -not (Test-Path $saveDir)) {
        New-Item -ItemType Directory -Path $saveDir -Force | Out-Null
    }
    $titleHtml = [System.Net.WebUtility]::HtmlEncode($ReportTitle)

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
        $thHtml += "<th>$([System.Net.WebUtility]::HtmlEncode([string]$prop))</th>`n"
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
    <title>$titleHtml - WingetBatch</title>
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
                <h1>$titleHtml</h1>
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

    # Callers report the path and open the file themselves
    try {
        $htmlReport | Out-File -FilePath $FilePath -Encoding UTF8 -Force
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

# Region: Private/Get-WingetBatchConfigData.ps1
function Get-WingetBatchConfigData {
    <#
    .SYNOPSIS
        Read ~/.wingetbatch/config.json as a case-insensitive hashtable.

    .DESCRIPTION
        config.json is shared by several commands (update notifications, search match
        option, webhooks). Always read-modify-write through this function and
        Save-WingetBatchConfigData so one command does not wipe another's settings.
    #>
    [CmdletBinding()]
    param()

    $config = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    $configPath = Join-Path (Get-WingetBatchConfigDir) "config.json"

    if (Test-Path $configPath) {
        try {
            $json = Get-Content $configPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($json) {
                foreach ($prop in $json.PSObject.Properties) { $config[$prop.Name] = $prop.Value }
            }
        }
        catch {
            Write-Warning "WingetBatch config.json could not be read ($($_.Exception.Message)). Using defaults."
        }
    }
    return $config
}

function Save-WingetBatchConfigData {
    <#
    .SYNOPSIS
        Write the config hashtable back to ~/.wingetbatch/config.json.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    $configDir = Get-WingetBatchConfigDir
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    $configPath = Join-Path $configDir "config.json"

    $ordered = [ordered]@{}
    foreach ($key in ($Config.Keys | Sort-Object)) { $ordered[$key] = $Config[$key] }
    $ordered | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
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

# Region: Private/Get-WingetPkgsManifest.ps1
function Get-WingetPkgsHeaders {
    <#
    .SYNOPSIS
        GitHub API headers for winget-pkgs requests (adds the stored token if present).
    #>
    $headers = @{
        'User-Agent' = 'PowerShell-WingetBatch'
        'Accept'     = 'application/vnd.github.v3+json'
    }
    $token = Get-WingetBatchGitHubToken
    if ($token) { $headers['Authorization'] = "Bearer $token" }
    return $headers
}

function Get-WingetPkgsPackagePath {
    <#
    .SYNOPSIS
        Repository path of a package in microsoft/winget-pkgs.
        "Git.Git" -> "manifests/g/Git/Git"
    #>
    param([Parameter(Mandatory)][string]$PackageId)

    $firstLetter = $PackageId.Substring(0, 1).ToLowerInvariant()
    return "manifests/$firstLetter/$($PackageId -replace '\.', '/')"
}

function Get-WingetPkgsVersions {
    <#
    .SYNOPSIS
        List the published versions of a package in winget-pkgs, newest first.

    .DESCRIPTION
        Each version is a folder under the package path. Folders that do not look like
        versions (e.g. the "Insiders" sub-package under Microsoft.VisualStudioCode) are
        skipped when real version folders exist. Returns objects with Name and Url.
        Uses one GitHub API request.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackageId)

    $path = Get-WingetPkgsPackagePath -PackageId $PackageId
    $uri = "https://api.github.com/repos/microsoft/winget-pkgs/contents/$path"

    $listing = Invoke-RestMethod -Uri $uri -Headers (Get-WingetPkgsHeaders) -ErrorAction Stop
    Update-GitHubApiRequestCount -RequestCount 1 | Out-Null

    $dirs = @($listing | Where-Object { $_.type -eq 'dir' })
    $versionDirs = @($dirs | Where-Object { $_.name -match '^[vV]?\d' })
    if ($versionDirs.Count -eq 0) { $versionDirs = $dirs }

    $versions = foreach ($d in $versionDirs) {
        [PSCustomObject]@{ Name = $d.name; Url = $d.url }
    }
    if (-not $versions) { return @() }
    Sort-WingetVersion -InputObject @($versions) -Property Name -Descending
}

function Get-WingetPkgsManifest {
    <#
    .SYNOPSIS
        Download manifest files for one version of a package from winget-pkgs.

    .DESCRIPTION
        Returns an object with Version, Installer, Locale (default/en-US locale) and
        VersionManifest properties holding the raw YAML text. File listing uses one
        GitHub API request; file contents come from raw.githubusercontent.com, which
        is not counted against the API rate limit.

    .PARAMETER Version
        Version folder name. Omit for the latest version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [string]$Version
    )

    $headers = Get-WingetPkgsHeaders

    if (-not $Version) {
        $latest = Get-WingetPkgsVersions -PackageId $PackageId | Select-Object -First 1
        if (-not $latest) { return $null }
        $Version = $latest.Name
    }

    $path = Get-WingetPkgsPackagePath -PackageId $PackageId
    $files = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-pkgs/contents/$path/$Version" -Headers $headers -ErrorAction Stop
    Update-GitHubApiRequestCount -RequestCount 1 | Out-Null

    $yamlFiles = @($files | Where-Object { $_.type -eq 'file' -and $_.name -match '\.ya?ml$' })

    $installerFile = $yamlFiles | Where-Object { $_.name -match '\.installer\.ya?ml$' } | Select-Object -First 1
    $localeFiles = @($yamlFiles | Where-Object { $_.name -match '\.locale\.' })
    $versionFile = $yamlFiles | Where-Object { $_.name -notmatch '\.(installer|locale)\.' } | Select-Object -First 1

    $fetch = {
        param($file)
        if (-not $file) { return $null }
        try { [string](Invoke-RestMethod -Uri $file.download_url -Headers @{ 'User-Agent' = 'PowerShell-WingetBatch' } -ErrorAction Stop) }
        catch { $null }
    }

    $versionYaml = & $fetch $versionFile

    # Prefer the manifest's declared default locale, then en-US, then whatever exists
    $defaultLocale = Get-WingetYamlValue -Yaml $versionYaml -Key 'DefaultLocale'
    $localeFile = $null
    if ($defaultLocale) { $localeFile = $localeFiles | Where-Object { $_.name -like "*.locale.$defaultLocale.yaml" } | Select-Object -First 1 }
    if (-not $localeFile) { $localeFile = $localeFiles | Where-Object { $_.name -like '*.locale.en-US.yaml' } | Select-Object -First 1 }
    if (-not $localeFile) { $localeFile = $localeFiles | Select-Object -First 1 }

    [PSCustomObject]@{
        PackageId       = $PackageId
        Version         = $Version
        Installer       = & $fetch $installerFile
        Locale          = & $fetch $localeFile
        VersionManifest = $versionYaml
    }
}

function Get-WingetYamlValue {
    <#
    .SYNOPSIS
        Read a top-level scalar value from a winget manifest without a YAML module.
        Handles plain, quoted and block (| / >) values.
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$Yaml,
        [Parameter(Mandatory)][string]$Key
    )

    if (-not $Yaml) { return $null }
    $lines = $Yaml -split "\r?\n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^$([regex]::Escape($Key)):\s*(.*)$") {
            $value = $Matches[1].Trim()
            if ($value -match '^[|>][-+]?$') {
                $block = [System.Collections.Generic.List[string]]::new()
                for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                    if ($lines[$j] -match '^\S') { break }
                    $block.Add($lines[$j].Trim())
                }
                $joiner = if ($value.StartsWith('|')) { "`n" } else { ' ' }
                return ($block -join $joiner).Trim()
            }
            return $value.Trim('"', "'")
        }
    }
    return $null
}

# EndRegion

# Region: Private/Get-WingetSourceIndexAge.ps1
function Get-WingetSourceIndexAge {
    <#
    .SYNOPSIS
        How old the local winget source index is, as a TimeSpan ($null if unknown).

    .DESCRIPTION
        Current WinGet versions ship the index inside the Microsoft.Winget.Source app
        package (index.db); older ones kept source.db under App Installer's LocalState.
    #>
    [CmdletBinding()]
    param()

    $candidates = [System.Collections.Generic.List[string]]::new()
    try {
        $pkg = Get-AppxPackage -Name 'Microsoft.Winget.Source' -ErrorAction Stop |
            Sort-Object Version -Descending | Select-Object -First 1
        if ($pkg -and $pkg.InstallLocation) {
            $candidates.Add((Join-Path $pkg.InstallLocation 'Public\index.db'))
            $candidates.Add((Join-Path $pkg.InstallLocation 'index.db'))
        }
    }
    catch {
        Write-Verbose "Get-AppxPackage unavailable: $_"
    }
    $candidates.Add("$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\Microsoft.Winget.Source_8wekyb3d8bbwe\winget\source.db")

    foreach ($path in $candidates) {
        if (Test-Path $path) {
            return (Get-Date) - (Get-Item $path).LastWriteTime
        }
    }
    return $null
}

# EndRegion

# Region: Private/Install-WingetBatchDependency.ps1
function Install-WingetBatchDependency {
    <#
    .SYNOPSIS
        Install or update a PowerShell Gallery module without interactive prompts.

    .DESCRIPTION
        Works with both PSResourceGet (Install-PSResource, the default in newer
        PowerShell, where Install-Module may be an alias that prompts for trust)
        and classic PowerShellGet. Throws on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Update
    )

    if (Get-Command Install-PSResource -ErrorAction SilentlyContinue) {
        if ($Update -and (Get-Command Update-PSResource -ErrorAction SilentlyContinue) -and (Get-InstalledPSResource -Name $Name -ErrorAction SilentlyContinue)) {
            Update-PSResource -Name $Name -TrustRepository -AcceptLicense -Quiet -ErrorAction Stop
        }
        else {
            Install-PSResource -Name $Name -Scope CurrentUser -TrustRepository -AcceptLicense -Quiet -Reinstall:$Update -ErrorAction Stop
        }
    }
    elseif ($Update) {
        Update-Module -Name $Name -Force -AcceptLicense -ErrorAction Stop
    }
    else {
        Install-Module -Name $Name -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber -ErrorAction Stop
    }
}

# EndRegion

# Region: Private/Invoke-WingetPackageAction.ps1
function Invoke-WingetPackageAction {
    <#
    .SYNOPSIS
        Install, update or uninstall one package and report whether it really worked.

    .DESCRIPTION
        Single entry point for package changes. Always calls the Microsoft.WinGet.Client
        cmdlets by their module-qualified name (other modules such as Cobalt export
        commands with the same names), matches the ID exactly instead of by substring,
        and returns a ConvertTo-WingetActionResult object instead of assuming success
        when no exception is thrown.

    .PARAMETER Options
        Optional install settings: Mode, Scope, Architecture, Override, Location,
        Force, SkipDependencies, AllowHashMismatch. Keys the target cmdlet does not
        support are ignored.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Install', 'Update', 'Uninstall')]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter()]
        [string]$Version,

        [Parameter()]
        [string]$Source,

        [Parameter()]
        [hashtable]$Options = @{}
    )

    $cmd = Get-Command -Name "Microsoft.WinGet.Client\$Action-WinGetPackage" -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return [PSCustomObject]@{
            Id = $Id; Action = $Action; Succeeded = $false; Status = 'ModuleMissing'
            RebootRequired = $false; Message = 'Microsoft.WinGet.Client is not available.'
        }
    }

    $params = @{
        Id          = $Id
        MatchOption = 'EqualsCaseInsensitive'
        ErrorAction = 'Stop'
    }
    if ($Version -and $Version -ne 'latest') { $params['Version'] = $Version }
    if ($Source) { $params['Source'] = $Source }

    foreach ($key in $Options.Keys) {
        $value = $Options[$key]
        if ($null -eq $value -or ($value -is [string] -and $value -eq '')) { continue }
        if (-not $cmd.Parameters.ContainsKey($key)) { continue }
        if ($cmd.Parameters[$key].SwitchParameter) {
            if ([bool]$value) { $params[$key] = $true }
        }
        else {
            $params[$key] = $value
        }
    }

    # Installed copies of this exact ID. ARP\... and MSIX\... IDs make the -Id search
    # throw CatalogError, so fall back to listing everything and filtering.
    $findInstalled = {
        try {
            @(Microsoft.WinGet.Client\Get-WinGetPackage -Id $Id -MatchOption EqualsCaseInsensitive -ErrorAction Stop)
        }
        catch {
            @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue | Where-Object { $_.Id -eq $Id })
        }
    }
    $countInstalled = { @(& $findInstalled).Count }
    $getVersion = { & $findInstalled | Select-Object -First 1 -ExpandProperty InstalledVersion }
    # Counted before an uninstall so we can confirm a copy went away
    $before = if ($Action -eq 'Uninstall') { & $countInstalled } else { 0 }
    $versionBefore = if ($Action -eq 'Update') { [string](& $getVersion) } else { $null }

    try {
        # Programs known only from Add/Remove Programs (ARP\...) or MSIX (MSIX\...) cannot
        # be found by ID search (CatalogError); act on the installed package object instead.
        $byObject = {
            $pkg = & $findInstalled | Select-Object -First 1
            if (-not $pkg) { throw "Package '$Id' is not installed." }
            $objParams = @{ PSCatalogPackage = $pkg; ErrorAction = 'Stop' }
            foreach ($k in $params.Keys) {
                if ($k -notin 'Id', 'MatchOption', 'Source', 'Version', 'ErrorAction') { $objParams[$k] = $params[$k] }
            }
            & $cmd @objParams
        }
        if ($Action -ne 'Install' -and $Id -match '^(ARP|MSIX)\\') {
            $result = & $byObject
        }
        else {
            try { $result = & $cmd @params }
            catch {
                if ($Action -ne 'Install' -and $_.Exception.Message -match 'CatalogError') { $result = & $byObject }
                else { throw }
            }
        }
        $normalized = ConvertTo-WingetActionResult -Result $result -Id $Id -Action $Action

        # Some uninstallers exit 0 without removing anything (WinGet then reports Ok),
        # and NSIS uninstallers finish a few seconds after returning. Confirm removal.
        if ($normalized.Succeeded -and $Action -eq 'Uninstall' -and $before -gt 0) {
            $deadline = (Get-Date).AddSeconds(30)
            while ((& $countInstalled) -ge $before -and (Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 3
            }
            if ((& $countInstalled) -ge $before) {
                $normalized.Succeeded = $false
                $normalized.Status = 'StillInstalled'
                $normalized.Message = "WinGet reported success, but $Id is still installed (the uninstaller did not remove it)."
            }
        }
        # An update that "succeeds" but leaves the same version installed (installer
        # declined, or WinGet mis-orders versions like "1.5.11+hash" vs "1.5.11")
        if ($normalized.Succeeded -and $Action -eq 'Update' -and $normalized.Status -eq 'Ok' -and $versionBefore) {
            $deadline = (Get-Date).AddSeconds(20)
            $versionAfter = [string](& $getVersion)
            while ($versionAfter -eq $versionBefore -and (Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 3
                $versionAfter = [string](& $getVersion)
            }
            if ($versionAfter -eq $versionBefore) {
                $normalized.Succeeded = $false
                $normalized.Status = 'NotUpdated'
                $normalized.Message = "WinGet reported success, but $Id is still at $versionBefore."
            }
        }
        $normalized
    }
    catch {
        [PSCustomObject]@{
            Id             = $Id
            Action         = $Action
            Succeeded      = $false
            Status         = 'Error'
            RebootRequired = $false
            Message        = $_.Exception.Message
        }
    }
}

# EndRegion

# Region: Private/New-WingetSnapshot.ps1
function New-WingetSnapshot {
    <#
    .SYNOPSIS
        Save the current installed-package state to ~/.wingetbatch/snapshots.
        Returns the snapshot as a hashtable.
    #>
    [CmdletBinding()]
    param([string]$Label = 'manual')

    $snapshotDir = Join-Path (Get-WingetBatchConfigDir) "snapshots"
    if (-not (Test-Path $snapshotDir)) {
        New-Item -Path $snapshotDir -ItemType Directory -Force | Out-Null
    }

    # Milliseconds keep IDs unique when an auto-snapshot and a manual one land in the same second
    $id = "snap_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')"
    $packages = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue)

    $snapshot = [ordered]@{
        Id           = $id
        Timestamp    = (Get-Date).ToString('o')
        Label        = $Label
        Hostname     = $env:COMPUTERNAME
        PackageCount = $packages.Count
        Packages     = @($packages | ForEach-Object {
            [ordered]@{ Id = $_.Id; Name = $_.Name; Version = $_.InstalledVersion; Source = $_.Source }
        })
    }

    $filePath = Join-Path $snapshotDir "$id.json"
    $snapshot | ConvertTo-Json -Depth 5 -Compress | Set-Content -Path $filePath -Encoding UTF8
    return $snapshot
}

function Invoke-WingetAutoSnapshot {
    <#
    .SYNOPSIS
        Take a snapshot before a change, if auto-snapshots are enabled
        (Restore-WingetSnapshot -AutoSnapshot $true). Never throws.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Reason)

    try {
        $autoConfigPath = Join-Path (Get-WingetBatchConfigDir) "snapshot_config.json"
        if (-not (Test-Path $autoConfigPath)) { return }
        $autoConfig = Get-Content $autoConfigPath -Raw | ConvertFrom-Json
        if (-not $autoConfig.AutoSnapshot) { return }

        $snap = New-WingetSnapshot -Label "auto: before $Reason"
        Write-Host "  [SNAPSHOT] Saved $($snap.Id) (undo with Restore-WingetSnapshot -UndoLast 1)" -ForegroundColor DarkGray
    }
    catch {
        Write-Verbose "Auto-snapshot skipped: $_"
    }
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
    # Description, Release Notes and Tags can span several indented lines under
    # their label ("Description:" followed by the text on the next lines)
    $blockKey = $null
    $blockLines = [System.Collections.Generic.List[string]]::new()
    $flushBlock = {
        if ($blockKey -and $blockLines.Count -gt 0) {
            switch ($blockKey) {
                'Description' { $info.Description = ($blockLines -join ' ').Trim() }
                'Release Notes' { $info.ReleaseNotes = ($blockLines -join "`n").Trim() }
                'Tags' { $info.Tags = @($blockLines | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
            }
        }
        $blockLines.Clear()
    }

    foreach ($rawLine in $Output -split "`n") {
        $line = $rawLine.TrimEnd("`r")

        if ($blockKey) {
            if ($line -match '^\s+\S') {
                $blockLines.Add($line.Trim())
                continue
            }
            & $flushBlock
            $blockKey = $null
        }

        $colonIndex = $line.IndexOf(':')
        if ($colonIndex -gt 0 -and $line -match '^(Description|Release Notes|Tags):\s*$') {
            $blockKey = $Matches[1]
            continue
        }

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
    if ($blockKey) { & $flushBlock }

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

            # Enumerating installed packages takes seconds; reuse the list for a minute
            if (-not $script:CompleterInstalledIds -or ((Get-Date) - $script:CompleterInstalledAt).TotalSeconds -gt 60) {
                $script:CompleterInstalledIds = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue |
                    Where-Object { $_.Source } | ForEach-Object { $_.Id } | Sort-Object)
                $script:CompleterInstalledAt = Get-Date
            }
            $word = ([string]$wordToComplete).Trim("'", '"')
            if ($script:CompleterInstalledIds) {
                $script:CompleterInstalledIds |
                    Where-Object { $_ -like "$word*" } |
                    Select-Object -First 20 |
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

    # Installed package IDs: commands that act on what is already on this machine
    Register-ArgumentCompleter -CommandName 'Get-WingetChangelog' -ParameterName 'PackageId' -ScriptBlock $packageIdCompleter -ErrorAction SilentlyContinue

    # Any package in the source catalog
    foreach ($cmd in 'Get-WingetHealthScore', 'Get-WingetDependencyGraph', 'Export-WingetOffline', 'Invoke-WingetFleet') {
        Register-ArgumentCompleter -CommandName $cmd -ParameterName 'PackageId' -ScriptBlock $packageSearchCompleter -ErrorAction SilentlyContinue
    }
    Register-ArgumentCompleter -CommandName 'Install-WingetAll' -ParameterName 'Id' -ScriptBlock $packageSearchCompleter -ErrorAction SilentlyContinue
    Register-ArgumentCompleter -CommandName 'Get-WingetPackageInfo' -ParameterName 'Id' -ScriptBlock $packageSearchCompleter -ErrorAction SilentlyContinue
    Register-ArgumentCompleter -CommandName 'Get-WingetPackageInfo' -ParameterName 'Query' -ScriptBlock $packageSearchCompleter -ErrorAction SilentlyContinue

    Register-ArgumentCompleter -CommandName 'Install-WingetAll' -ParameterName 'Source' -ScriptBlock $sourceCompleter -ErrorAction SilentlyContinue
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

# Region: Private/Set-WingetPackageVersion.ps1
function Set-WingetPackageVersion {
    <#
    .SYNOPSIS
        Move an installed package to an exact version (up or down) and verify it.

    .DESCRIPTION
        Installing an older version on top of a newer one is unreliable: MSI packages
        usually refuse while WinGet still reports 'Ok', and a package can switch
        installer technology between versions (VLC: MSI 3.0.23 vs EXE 3.0.21), which
        leaves two registered copies sharing one folder. So downgrades remove the
        package first and then install the pinned version. Every path ends by checking
        the version WinGet actually sees.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Version,
        [string]$Source
    )

    $getInstalled = {
        @(Microsoft.WinGet.Client\Get-WinGetPackage -Id $Id -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue) |
            ForEach-Object { [string]$_.InstalledVersion }
    }
    $isTarget = { param($v) $v -and (Compare-WingetVersion -ReferenceVersion $v -DifferenceVersion $Version) -eq 0 }
    $fail = {
        param($status, $message)
        [PSCustomObject]@{ Id = $Id; Action = 'Install'; Succeeded = $false; Status = $status; RebootRequired = $false; Message = $message }
    }

    # Remove every installed copy. The COM API cannot target one of several installed
    # versions (it returns MULTIPLE_APPLICATIONS_FOUND), so fall back to the CLI.
    $removeAll = {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        # Uninstalling one copy can re-expose another registration, so re-check a few times
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            if (@(& $getInstalled).Count -eq 0) { return $true }
            $r = Invoke-WingetPackageAction -Action Uninstall -Id $Id -Source $Source -Options @{ Mode = 'Silent' }
            if (-not $r.Succeeded -and $winget) {
                & $winget.Source uninstall --id $Id --exact --all-versions --silent --disable-interactivity --accept-source-agreements 2>&1 | Out-Null
            }
        }
        return (@(& $getInstalled).Count -eq 0)
    }

    $current = @(& $getInstalled)
    if ($current.Count -eq 1 -and (& $isTarget $current[0])) {
        return [PSCustomObject]@{ Id = $Id; Action = 'Install'; Succeeded = $true; Status = 'Ok'; RebootRequired = $false; Message = 'Already at target version.' }
    }

    $isDowngrade = @($current | Where-Object { (Compare-WingetVersion -ReferenceVersion $_ -DifferenceVersion $Version) -gt 0 }).Count -gt 0
    if ($isDowngrade -or $current.Count -gt 1) {
        Write-Verbose "Removing $Id ($($current -join ', ')) before installing $Version"
        if (-not (& $removeAll)) {
            return (& $fail 'UninstallFailed' "Could not remove the installed version(s) $($current -join ', ') before installing $Version.")
        }
        $result = Invoke-WingetPackageAction -Action Install -Id $Id -Version $Version -Source $Source -Options @{ Mode = 'Silent' }
    }
    else {
        $result = Invoke-WingetPackageAction -Action Install -Id $Id -Version $Version -Source $Source -Options @{ Mode = 'Silent'; Force = $true }
    }

    if ($result.Succeeded) {
        $after = @(& $getInstalled)
        if ($after.Count -ne 1 -or -not (& $isTarget $after[0])) {
            $result.Succeeded = $false
            $result.Status = 'VersionMismatch'
            $result.Message = "WinGet reported success but installed version(s) are: $(if ($after) { $after -join ', ' } else { 'none' }), expected $Version."
        }
    }
    return $result
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

# Region: Private/Sort-WingetVersion.ps1
function Sort-WingetVersion {
    <#
    .SYNOPSIS
        Sort objects (or strings) by package version using Compare-WingetVersion.

    .PARAMETER Property
        Property holding the version. Omit to sort plain strings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [string]$Property,

        [switch]$Descending
    )

    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $InputObject) { if ($null -ne $item) { $list.Add($item) } }

    $sign = if ($Descending) { -1 } else { 1 }
    $list.Sort([System.Comparison[object]] {
        param($x, $y)
        $vx = if ($Property) { [string]$x.$Property } else { [string]$x }
        $vy = if ($Property) { [string]$y.$Property } else { [string]$y }
        $sign * (Compare-WingetVersion -ReferenceVersion $vx -DifferenceVersion $vy)
    })

    $list.ToArray()
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
                    $comResult = Microsoft.WinGet.Client\Find-WinGetPackage -Id $packageId -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue | Select-Object -First 1
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

        $job = Start-WingetBatchJob -ScriptBlock $jobScript -ArgumentList (,$packageBatch), $ConfigDir, ${function:Parse-WingetShowOutput}, $wingetExe
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
        return Start-ThreadJob -Name 'WingetBatchDetails' -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }
    else {
        return Start-Job -Name 'WingetBatchDetails' -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }
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

    # Update configuration (merge, so other settings are kept)
    $config = Get-WingetBatchConfigData
    if ($config.Count -gt 0) {
        $config['UpdateNotificationsEnabled'] = $false
        Save-WingetBatchConfigData -Config $config
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

    # Merge into the existing config so other settings (search options, webhooks) survive
    $config = Get-WingetBatchConfigData
    $config['UpdateNotificationsEnabled'] = $true
    $config['CheckInterval'] = $Interval
    $config['CheckOnStartup'] = $CheckOnStartup
    $config['LastCheck'] = $null
    Save-WingetBatchConfigData -Config $config

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

# Region: Public/Export-WingetOffline.ps1
function Export-WingetOffline {
    <#
    .SYNOPSIS
        Download packages for air-gapped/offline deployment.

    .DESCRIPTION
        Creates a portable offline package repository containing installers,
        manifests, and a self-contained deployment script. Designed for
        environments where target machines have no internet access.

        Installers are downloaded with WinGet's own Export-WinGetPackage, which picks
        the installer for the requested architecture, verifies its SHA-256 hash against
        the manifest, and saves the manifest next to it. The generated
        Install-Offline.ps1 reads each manifest's silent switches, so installers run
        unattended with the arguments their publisher documented.

        The output folder can be copied via USB/network share to isolated machines
        and deployed with Install-Offline.ps1 (works in Windows PowerShell 5.1 and 7).

    .PARAMETER PackageId
        Package IDs to download for offline use.

    .PARAMETER FromManifest
        Path to a JSON/YAML manifest of packages (e.g. from Get-WingetMachineState -Export).

    .PARAMETER FromInstalled
        Download installers for all currently installed winget-source packages.

    .PARAMETER OutputPath
        Destination folder for the offline repository. Default: .\WingetOffline

    .PARAMETER IncludeDependencies
        Also download package dependencies.

    .PARAMETER Architecture
        Preferred installer architecture: X64, X86, Arm64. Default: X64.

    .PARAMETER VerifyHash
        Reject installers whose hash does not match the manifest. Default: true.

    .PARAMETER Deploy
        Generate and include the offline deployment script.

    .EXAMPLE
        Export-WingetOffline -PackageId "Git.Git","Python.Python.3.13" -OutputPath "E:\OfflineRepo" -Deploy
        Downloads Git and Python installers to a USB drive folder with an install script.

    .EXAMPLE
        Export-WingetOffline -FromManifest ".\lab-packages.json" -OutputPath "\\fileserver\offline"
        Downloads all packages from a manifest to a network share.

    .EXAMPLE
        Export-WingetOffline -FromInstalled -OutputPath "D:\AirGap" -Deploy
        Full machine clone: downloads everything installed + deployment script.

    .NOTES
        Author: Matthew Bubb
        Microsoft Store (msstore) packages are skipped: offline Store downloads need an
        organizational Entra ID account.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory, Position = 0)]
        [string[]]$PackageId,

        [Parameter(ParameterSetName = 'Manifest', Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$FromManifest,

        [Parameter(ParameterSetName = 'Installed', Mandatory)]
        [switch]$FromInstalled,

        [string]$OutputPath = ".\WingetOffline",

        [switch]$IncludeDependencies,

        [ValidateSet('X64', 'X86', 'Arm64')]
        [string]$Architecture = 'X64',

        [bool]$VerifyHash = $true,

        [switch]$Deploy
    )

    if (-not (Get-Command Microsoft.WinGet.Client\Export-WinGetPackage -ErrorAction SilentlyContinue)) {
        Write-Error "Export-WinGetPackage is not available. Update the module: Install-Module Microsoft.WinGet.Client -Force"
        return
    }

    # --- Resolve package list: objects with Id and Version ('latest' = newest) ---
    $packages = [System.Collections.Generic.List[PSCustomObject]]::new()

    switch ($PSCmdlet.ParameterSetName) {
        'ById' {
            foreach ($id in $PackageId) { $packages.Add([PSCustomObject]@{ Id = $id; Version = 'latest' }) }
        }
        'Manifest' {
            $raw = Get-Content -Path $FromManifest -Raw
            $entries = @()
            if ($FromManifest -match '\.ya?ml$') {
                if (Get-Module -ListAvailable -Name powershell-yaml) {
                    Import-Module powershell-yaml -ErrorAction Stop
                    $entries = @((ConvertFrom-Yaml $raw).packages)
                }
                else {
                    # Minimal fallback: "- id: X" or "- X" list items
                    $entries = @($raw -split "\r?\n" | Where-Object { $_ -match '^\s*-\s*(?:id:\s*)?([\w\.\-]+)\s*$' } | ForEach-Object { $Matches[1] })
                }
            }
            else {
                $manifest = $raw | ConvertFrom-Json
                $entries = if ($manifest.packages) { @($manifest.packages) } elseif ($manifest.Packages) { @($manifest.Packages) } else { @($manifest) }
            }
            foreach ($e in $entries) {
                if ($e -is [string]) { $packages.Add([PSCustomObject]@{ Id = $e; Version = 'latest' }); continue }
                $id = if ($e.id) { $e.id } else { $e.Id }
                $ver = if ($e.version) { $e.version } elseif ($e.Version) { $e.Version } else { 'latest' }
                $src = if ($e.source) { $e.source } else { $e.Source }
                if ($id -and $src -ne 'msstore') { $packages.Add([PSCustomObject]@{ Id = [string]$id; Version = [string]$ver }) }
            }
        }
        'Installed' {
            $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue | Where-Object { $_.Source -eq 'winget' }
            foreach ($p in $installed) { $packages.Add([PSCustomObject]@{ Id = $p.Id; Version = 'latest' }) }
            Write-Host "  Exporting $($packages.Count) installed winget packages for offline use." -ForegroundColor Cyan
        }
    }

    if ($packages.Count -eq 0) {
        Write-Error "No packages to export."
        return
    }

    # --- Create output structure ---
    $repoPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $installersDir = Join-Path $repoPath "installers"
    New-Item -Path $installersDir -ItemType Directory -Force | Out-Null

    # --- Banner ---
    Write-Host ""
    Write-Host "  WingetBatch Offline Repository" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Packages:   " -NoNewline -ForegroundColor DarkGray; Write-Host $packages.Count -ForegroundColor White
    Write-Host "  Output:     " -NoNewline -ForegroundColor DarkGray; Write-Host $repoPath -ForegroundColor White
    Write-Host "  Arch:       " -NoNewline -ForegroundColor DarkGray; Write-Host $Architecture -ForegroundColor White
    Write-Host "  Verify:     " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($VerifyHash) { "SHA-256 (enforced by WinGet)" } else { "Skip" }) -ForegroundColor White
    Write-Host ""

    $manifestEntries = [System.Collections.Generic.List[object]]::new()
    $successCount = 0
    $failCount = 0
    $total = $packages.Count
    $i = 0

    foreach ($pkg in $packages) {
        $i++
        Write-Progress -Activity "Downloading offline packages" -Status "[$i/$total] $($pkg.Id)" -PercentComplete (($i / $total) * 100)
        Write-Host "  [$i/$total] " -NoNewline -ForegroundColor DarkGray
        Write-Host $pkg.Id -NoNewline -ForegroundColor Cyan
        Write-Host "..." -NoNewline

        $safeName = $pkg.Id -replace '[^\w\.\-]', '_'
        $pkgDir = Join-Path $installersDir $safeName
        if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force }
        New-Item -Path $pkgDir -ItemType Directory -Force | Out-Null

        try {
            $params = @{
                Id                = $pkg.Id
                MatchOption       = 'EqualsCaseInsensitive'
                Source            = 'winget'
                DownloadDirectory = $pkgDir
                Architecture      = $Architecture
                ErrorAction       = 'Stop'
            }
            if ($pkg.Version -and $pkg.Version -ne 'latest') { $params['Version'] = $pkg.Version }
            if (-not $IncludeDependencies) { $params['SkipDependencies'] = $true }
            if (-not $VerifyHash) { $params['AllowHashMismatch'] = $true }

            $result = @(Microsoft.WinGet.Client\Export-WinGetPackage @params)[-1]
            if ($result -and [string]$result.Status -ne 'Ok') {
                throw "WinGet status: $($result.Status)"
            }

            # WinGet writes the installer plus a .yaml manifest describing it
            $yaml = Get-ChildItem $pkgDir -Filter *.yaml -File | Select-Object -First 1
            $installer = Get-ChildItem $pkgDir -File | Where-Object { $_.Extension -ne '.yaml' } | Sort-Object Length -Descending | Select-Object -First 1
            if (-not $installer) { throw "No installer was downloaded." }

            $yamlText = if ($yaml) { Get-Content $yaml.FullName -Raw } else { '' }
            $version = Get-WingetYamlValue -Yaml $yamlText -Key 'PackageVersion'
            $type = if ($yamlText -match '(?m)^\s*-?\s*InstallerType:\s*(\S+)') { $Matches[1].ToLowerInvariant() } else { $installer.Extension.TrimStart('.').ToLowerInvariant() }
            $silent = if ($yamlText -match '(?m)^\s+Silent:\s*(.+)$') { $Matches[1].Trim().Trim('"', "'") } elseif ($yamlText -match '(?m)^\s+SilentWithProgress:\s*(.+)$') { $Matches[1].Trim().Trim('"', "'") } else { $null }
            $hash = (Get-FileHash -Path $installer.FullName -Algorithm SHA256).Hash
            $sizeMb = [Math]::Round($installer.Length / 1MB, 1)

            $manifestEntries.Add([ordered]@{
                Id         = $pkg.Id
                Version    = $version
                File       = "installers/$safeName/$($installer.Name)"
                Manifest   = $(if ($yaml) { "installers/$safeName/$($yaml.Name)" } else { $null })
                Type       = $type
                SilentArgs = $silent
                Hash       = $hash
                Size       = "${sizeMb}MB"
                Status     = 'Downloaded'
            })
            Write-Host " OK v$version (${sizeMb}MB, $type)" -ForegroundColor Green
            $successCount++
        }
        catch {
            Write-Host " FAILED ($($_.Exception.Message))" -ForegroundColor Red
            $failCount++
            $manifestEntries.Add([ordered]@{ Id = $pkg.Id; Status = 'Failed'; Error = $_.Exception.Message })
            Remove-Item $pkgDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Progress -Activity "Downloading offline packages" -Completed

    # --- Save manifest ---
    $manifestFile = Join-Path $repoPath "offline_manifest.json"
    [ordered]@{
        Created      = (Get-Date).ToString('o')
        Hostname     = $env:COMPUTERNAME
        Architecture = $Architecture
        Generator    = "WingetBatch v$((Get-Module WingetBatch).Version)"
        Packages     = $manifestEntries
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestFile -Encoding UTF8

    # --- Generate deployment script (must run on Windows PowerShell 5.1 too) ---
    if ($Deploy) {
        $deployScript = @'
# WingetBatch Offline Deployment Script
# Run this on the target machine from the offline repository folder.
# Usage: .\Install-Offline.ps1 -All
#        .\Install-Offline.ps1 -PackageId Git.Git

param(
    [switch]$All,
    [string[]]$PackageId
)

$ErrorActionPreference = 'Continue'
$repo = $PSScriptRoot
$manifestPath = Join-Path $repo "offline_manifest.json"

if (-not (Test-Path $manifestPath)) {
    Write-Error "offline_manifest.json not found. Run this from the offline repo folder."
    exit 1
}
if (-not $All -and -not $PackageId) {
    Write-Host "Specify -All or -PackageId <id>." -ForegroundColor Yellow
    exit 1
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$packages = @($manifest.Packages | Where-Object { $_.Status -eq 'Downloaded' })
# "-File" / cmd.exe callers pass "a,b" as one string
$PackageId = @($PackageId | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($PackageId) { $packages = @($packages | Where-Object { $PackageId -contains $_.Id }) }

# Silent switches for installer technologies when the manifest has none
$defaultSilent = @{
    inno     = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
    nullsoft = '/S'
    burn     = '/quiet /norestart'
    wix      = '/qn /norestart'
    msi      = '/qn /norestart'
    exe      = '/S'
}

Write-Host ""
Write-Host "  WingetBatch Offline Deployment" -ForegroundColor Cyan
Write-Host "  Packages: $($packages.Count) | Source: $repo" -ForegroundColor DarkGray
Write-Host ""

$success = 0; $failed = 0; $reboot = $false
foreach ($pkg in $packages) {
    $filePath = Join-Path $repo $pkg.File
    if (-not (Test-Path $filePath)) {
        Write-Host "  [SKIP] $($pkg.Id) - file missing" -ForegroundColor Yellow
        continue
    }
    if ((Get-FileHash -Path $filePath -Algorithm SHA256).Hash -ne $pkg.Hash) {
        Write-Host "  [SKIP] $($pkg.Id) - file hash does not match the manifest" -ForegroundColor Red
        $failed++
        continue
    }

    Write-Host "  [INSTALL] $($pkg.Id) v$($pkg.Version) ($($pkg.Type))..." -NoNewline -ForegroundColor Cyan
    $silent = if ($pkg.SilentArgs) { $pkg.SilentArgs } else { $defaultSilent[$pkg.Type] }
    try {
        $exitCode = 0
        switch -Regex ($pkg.Type) {
            '^(msix|appx)$' {
                Add-AppxPackage -Path $filePath -ErrorAction Stop
            }
            '^(msi|wix)$' {
                $argsList = "/i `"$filePath`" $silent"
                $exitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList $argsList -Wait -PassThru).ExitCode
            }
            '^(zip|portable)$' {
                $dest = Join-Path $env:LOCALAPPDATA "Programs\$($pkg.Id)"
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                if ($pkg.Type -eq 'zip') { Expand-Archive -Path $filePath -DestinationPath $dest -Force }
                else { Copy-Item -Path $filePath -Destination $dest -Force }
                Write-Host " (extracted to $dest)" -NoNewline -ForegroundColor DarkGray
            }
            default {
                $proc = if ($silent) { Start-Process -FilePath $filePath -ArgumentList $silent -Wait -PassThru } else { Start-Process -FilePath $filePath -Wait -PassThru }
                $exitCode = $proc.ExitCode
            }
        }
        if (@(0, 3010, 1641) -notcontains $exitCode) { throw "Exit code: $exitCode" }
        if ($exitCode -ne 0) { $reboot = $true }
        Write-Host " OK" -ForegroundColor Green
        $success++
    } catch {
        Write-Host " FAILED ($($_.Exception.Message))" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "  Complete: $success installed, $failed failed." -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
if ($reboot) { Write-Host "  A restart is required to finish at least one installation." -ForegroundColor Yellow }
Write-Host ""
'@
        $deployPath = Join-Path $repoPath "Install-Offline.ps1"
        $deployScript | Set-Content -Path $deployPath -Encoding UTF8
    }

    # --- Summary ---
    Write-Host ""
    Write-Host "  Offline repository complete" -ForegroundColor White
    Write-Host "  Downloaded: $successCount | Failed: $failCount | Total: $total" -ForegroundColor White
    Write-Host "  Path: $repoPath" -ForegroundColor White
    if ($Deploy) {
        Write-Host "  Deploy: .\Install-Offline.ps1 -All" -ForegroundColor White
    }
    Write-Host ""

    return [PSCustomObject]@{
        OutputPath   = $repoPath
        Downloaded   = $successCount
        Failed       = $failCount
        Total        = $total
        ManifestFile = $manifestFile
        DeployScript = if ($Deploy) { (Join-Path $repoPath "Install-Offline.ps1") } else { $null }
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

        $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
        $installed = @($installed)
        if ($installed.Count -eq 0) {
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
                $sources = @($installed | Where-Object { $_.Id -eq $dup.PackageId } | ForEach-Object { $_.Source } | Where-Object { $_ } | Select-Object -Unique)
                $removeFrom = if ($sources -contains 'msstore') { 'msstore' } else { $sources | Select-Object -Last 1 }
                Write-Host "    Uninstall-WinGetPackage -Id '$($dup.PackageId)' -Source $removeFrom" -ForegroundColor DarkGray
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

# Region: Public/Get-WingetChangelog.ps1
function Get-WingetChangelog {
    <#
    .SYNOPSIS
        Show what changed between package versions (release notes diff).

    .DESCRIPTION
        Fetches release notes and changelog information between two versions
        of a package. Aggregates data from GitHub Releases, winget-pkgs commit
        history, and package manifest changes to answer: "What actually changed
        between v1.2 and v1.3?"

    .PARAMETER PackageId
        The package ID to check changelog for.

    .PARAMETER FromVersion
        Starting version (older). If omitted, uses installed version.

    .PARAMETER ToVersion
        Ending version (newer). If omitted, uses latest available.

    .PARAMETER ShowManifestDiff
        Also show changes to the winget manifest (installer URLs, switches, etc).

    .PARAMETER Limit
        Maximum number of versions to show in the changelog. Default: 10.

    .PARAMETER OpenInBrowser
        Open the GitHub releases page in the default browser.

    .EXAMPLE
        Get-WingetChangelog -PackageId "Microsoft.VisualStudioCode"
        Shows recent version changes for VS Code.

    .EXAMPLE
        Get-WingetChangelog -PackageId "Git.Git" -FromVersion "2.43.0" -ToVersion "2.45.0"
        Shows what changed between Git 2.43 and 2.45.

    .EXAMPLE
        Get-WingetChangelog -PackageId "Python.Python.3.12" -ShowManifestDiff
        Shows version history plus manifest changes.

    .NOTES
        Author: Matthew Bubb
        Data sourced from winget-pkgs GitHub repository commit history.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [Alias('Id')]
        [string]$PackageId,

        [string]$FromVersion,

        [string]$ToVersion,

        [switch]$ShowManifestDiff,

        [ValidateRange(1, 50)]
        [int]$Limit = 10,

        [switch]$OpenInBrowser
    )

    process {

        # --- Resolve versions ---
        $installedVersion = $null
        $latestVersion = $null

        try {
            $pkg = Microsoft.WinGet.Client\Get-WinGetPackage -Id $PackageId -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($pkg) {
                $installedVersion = $pkg.InstalledVersion
                if ($pkg.AvailableVersions -and $pkg.AvailableVersions.Count -gt 0) {
                    $latestVersion = $pkg.AvailableVersions[0]
                }
            }
        } catch { }

        # Default to "what changed since my version" only when there is something newer;
        # otherwise show the most recent $Limit versions
        if (-not $FromVersion -and $installedVersion -and $pkg.IsUpdateAvailable) { $FromVersion = $installedVersion }

        Write-Host ""
        Write-Host "  Package Changelog" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Package:  " -NoNewline -ForegroundColor DarkGray; Write-Host $PackageId -ForegroundColor White
        if ($installedVersion) {
            Write-Host "  Installed:" -NoNewline -ForegroundColor DarkGray; Write-Host " $installedVersion" -ForegroundColor Yellow
        }
        if ($latestVersion) {
            Write-Host "  Latest:   " -NoNewline -ForegroundColor DarkGray; Write-Host " $latestVersion" -ForegroundColor Green
        }
        Write-Host ""

        $packagePath = Get-WingetPkgsPackagePath -PackageId $PackageId
        $repoUrl = "https://github.com/microsoft/winget-pkgs/tree/master/$packagePath"

        try {
            $sortedVersions = @(Get-WingetPkgsVersions -PackageId $PackageId)
            if ($sortedVersions.Count -eq 0) { throw "No versions found in winget-pkgs." }
            if (-not $latestVersion) { $latestVersion = $sortedVersions[0].Name }

            # Keep versions inside the requested range (either bound may be omitted)
            $inRange = @($sortedVersions | Where-Object {
                (-not $FromVersion -or (Compare-WingetVersion -ReferenceVersion $_.Name -DifferenceVersion $FromVersion) -ge 0) -and
                (-not $ToVersion -or (Compare-WingetVersion -ReferenceVersion $_.Name -DifferenceVersion $ToVersion) -le 0)
            })
            if ($inRange.Count -eq 0) { $inRange = $sortedVersions }

            $displayVersions = @($inRange | Select-Object -First $Limit)

            if (-not (Get-WingetBatchGitHubToken) -and $displayVersions.Count -gt 10) {
                Write-Warning "Showing $($displayVersions.Count) versions uses about $($displayVersions.Count + 1) GitHub API requests (60/hour without a token)."
            }

            Write-Host "  Version History ($($displayVersions.Count) of $($sortedVersions.Count) total):" -ForegroundColor White
            Write-Host "  $('─' * 55)" -ForegroundColor DarkGray

            $prevManifest = $null
            # Oldest first when diffing so each entry shows what it changed
            foreach ($ver in $displayVersions) {
                $versionName = $ver.Name
                $isInstalled = $installedVersion -and (Compare-WingetVersion -ReferenceVersion $versionName -DifferenceVersion $installedVersion) -eq 0
                $isLatest = $latestVersion -and (Compare-WingetVersion -ReferenceVersion $versionName -DifferenceVersion $latestVersion) -eq 0

                $marker = if ($isInstalled -and $isLatest) { "◆ " }
                          elseif ($isInstalled) { "● " }
                          elseif ($isLatest) { "★ " }
                          else { "  " }

                $color = if ($isInstalled) { 'Yellow' } elseif ($isLatest) { 'Green' } else { 'White' }
                Write-Host "  $marker" -NoNewline -ForegroundColor $color
                Write-Host "v$versionName" -NoNewline -ForegroundColor $color
                if ($isInstalled) { Write-Host " (installed)" -NoNewline -ForegroundColor DarkYellow }
                if ($isLatest) { Write-Host " (latest)" -NoNewline -ForegroundColor DarkGreen }
                Write-Host ""

                $manifest = $null
                try {
                    $manifest = Get-WingetPkgsManifest -PackageId $PackageId -Version $versionName
                } catch {
                    $status = [int]$_.Exception.Response.StatusCode
                    if ($status -in 403, 429) {
                        Write-Warning "GitHub rate limit reached. Run New-WingetBatchGitHubToken for 5,000 requests/hour."
                        break
                    }
                    Write-Verbose "Could not fetch details for ${versionName}: $_"
                }

                if ($manifest) {
                    # Release notes live in the locale manifest
                    $notes = Get-WingetYamlValue -Yaml $manifest.Locale -Key 'ReleaseNotes'
                    $notesUrl = Get-WingetYamlValue -Yaml $manifest.Locale -Key 'ReleaseNotesUrl'
                    if ($notes) {
                        $notes = ($notes -replace '\s+', ' ').Trim()
                        if ($notes.Length -gt 160) { $notes = $notes.Substring(0, 157) + "..." }
                        Write-Host "      $notes" -ForegroundColor DarkGray
                    }
                    if ($notesUrl) {
                        Write-Host "      Notes: $notesUrl" -ForegroundColor DarkGray
                    }

                    # Manifest diff against the next-older displayed version
                    if ($ShowManifestDiff -and $prevManifest -and $manifest.Installer -and $prevManifest.Installer) {
                        $diffChanges = @()
                        $urlsNew = @([regex]::Matches($manifest.Installer, 'InstallerUrl:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
                        $urlsOld = @([regex]::Matches($prevManifest.Installer, 'InstallerUrl:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
                        $hostsNew = @($urlsNew | ForEach-Object { ([uri]$_).Host } | Select-Object -Unique)
                        $hostsOld = @($urlsOld | ForEach-Object { ([uri]$_).Host } | Select-Object -Unique)
                        if (Compare-Object $hostsNew $hostsOld) { $diffChanges += "Download host changed: $($hostsOld -join ', ') -> $($hostsNew -join ', ')" }

                        $typesNew = @([regex]::Matches($manifest.Installer, 'InstallerType:\s*(\w+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
                        $typesOld = @([regex]::Matches($prevManifest.Installer, 'InstallerType:\s*(\w+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
                        if (Compare-Object $typesNew $typesOld) { $diffChanges += "Installer type: $($typesOld -join ', ') -> $($typesNew -join ', ')" }

                        $archNew = @([regex]::Matches($manifest.Installer, 'Architecture:\s*(\w+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
                        $archOld = @([regex]::Matches($prevManifest.Installer, 'Architecture:\s*(\w+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
                        $added = @($archNew | Where-Object { $_ -notin $archOld })
                        $dropped = @($archOld | Where-Object { $_ -notin $archNew })
                        if ($added) { $diffChanges += "Architectures added: $($added -join ', ')" }
                        if ($dropped) { $diffChanges += "Architectures dropped: $($dropped -join ', ')" }

                        $depsNew = @([regex]::Matches($manifest.Installer, 'PackageIdentifier:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne $PackageId })
                        $depsOld = @([regex]::Matches($prevManifest.Installer, 'PackageIdentifier:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne $PackageId })
                        if (Compare-Object $depsNew $depsOld) { $diffChanges += "Dependencies: $(@($depsOld) -join ', ') -> $(@($depsNew) -join ', ')" }

                        foreach ($change in $diffChanges) {
                            # Changes are relative to the next-newer version shown above
                            Write-Host "      Δ (vs newer) $change" -ForegroundColor DarkCyan
                        }
                    }
                    $prevManifest = $manifest
                }
            }

            Write-Host ""
            Write-Host "  Legend: ◆ installed+latest | ● installed | ★ latest" -ForegroundColor DarkGray
            Write-Host "  Source: $repoUrl" -ForegroundColor DarkGray
            Write-Host ""

            if ($OpenInBrowser) {
                Start-Process $repoUrl
            }
        }
        catch {
            $status = [int]$_.Exception.Response.StatusCode
            if ($status -eq 404) {
                Write-Error "$PackageId was not found in winget-pkgs (it may come from another source)."
            }
            elseif ($status -in 403, 429) {
                Write-Error "GitHub rate limit reached. Run New-WingetBatchGitHubToken for 5,000 requests/hour."
            }
            else {
                Write-Error "Could not fetch version history for ${PackageId}: $($_.Exception.Message)"
            }
        }
    }
}

# EndRegion

# Region: Public/Get-WingetDependencyGraph.ps1
function Get-WingetDependencyGraph {
    <#
    .SYNOPSIS
        Visualize package dependency relationships as a graph.

    .DESCRIPTION
        Queries winget package manifests for dependency information and renders
        the relationships as a directed graph. Supports multiple output formats:
        Mermaid (for GitHub/docs), DOT (for Graphviz), ASCII tree, and structured
        object output for pipeline use.

        Can visualize dependencies for a specific package, all installed packages,
        or a curated list. Also detects circular dependencies and orphan packages.

    .PARAMETER PackageId
        One or more package IDs to analyze dependencies for.

    .PARAMETER AllInstalled
        Build a graph of all installed packages and their relationships.

    .PARAMETER Format
        Output format: Mermaid (default), DOT, Tree, or Object.

    .PARAMETER Depth
        Maximum dependency depth to traverse. Default: 3.

    .PARAMETER IncludeExternal
        Include external dependencies (Windows Features, Store packages).

    .PARAMETER HighlightCircular
        Detect and highlight circular dependency chains.

    .PARAMETER OutputPath
        Save the graph output to a file instead of displaying it.

    .EXAMPLE
        Get-WingetDependencyGraph -PackageId "Python.Python.3.12"
        Shows the dependency tree for Python 3.12.

    .EXAMPLE
        Get-WingetDependencyGraph -PackageId "Microsoft.VisualStudioCode" -Format DOT
        Outputs Graphviz DOT format for rendering with dot/neato.

    .EXAMPLE
        Get-WingetDependencyGraph -AllInstalled -Format Mermaid -Depth 2
        Generates a Mermaid diagram of all installed package relationships.

    .EXAMPLE
        Get-WingetDependencyGraph -PackageId "Git.Git","Node.js" -Format Tree
        ASCII tree view of dependencies for Git and Node.js.

    .NOTES
        Author: Matthew Bubb
        Dependency data is sourced from winget-pkgs GitHub manifests and local COM API.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory, Position = 0, ValueFromPipeline)]
        [Alias('Id')]
        [string[]]$PackageId,

        [Parameter(ParameterSetName = 'AllInstalled', Mandatory)]
        [switch]$AllInstalled,

        [ValidateSet('Mermaid', 'DOT', 'Tree', 'Object')]
        [string]$Format = 'Mermaid',

        [ValidateRange(1, 10)]
        [int]$Depth = 3,

        [switch]$IncludeExternal,

        [switch]$HighlightCircular,

        [string]$OutputPath
    )

    begin {
        $graph = @{
            Nodes = [System.Collections.Generic.Dictionary[string, hashtable]]::new([System.StringComparer]::OrdinalIgnoreCase)
            Edges = [System.Collections.Generic.List[hashtable]]::new()
            Circular = [System.Collections.Generic.List[string]]::new()
        }
        $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $inStack = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        function Add-GraphNode {
            param([string]$Id, [string]$Label, [string]$Type = 'package')
            if (-not $graph.Nodes.ContainsKey($Id)) {
                $graph.Nodes[$Id] = @{ Id = $Id; Label = $Label; Type = $Type; Dependencies = @(); Dependents = @() }
            }
        }

        function Add-GraphEdge {
            param([string]$From, [string]$To, [string]$Relation = 'depends-on')
            $graph.Edges.Add(@{ From = $From; To = $To; Relation = $Relation })
            if ($graph.Nodes.ContainsKey($From)) { $graph.Nodes[$From].Dependencies += $To }
            if ($graph.Nodes.ContainsKey($To)) { $graph.Nodes[$To].Dependents += $From }
        }

        function Get-PackageDependencies {
            param([string]$Id, [int]$CurrentDepth)

            if ($CurrentDepth -gt $Depth) { return }
            if ($visited.Contains($Id)) {
                # Circular dependency detection
                if ($inStack.Contains($Id) -and $HighlightCircular) {
                    $graph.Circular.Add($Id)
                }
                return
            }

            $visited.Add($Id) | Out-Null
            $inStack.Add($Id) | Out-Null

            # Try COM API first for installed package info
            try {
                $pkgResult = Microsoft.WinGet.Client\Get-WinGetPackage -Id $Id -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($pkgResult) {
                    Add-GraphNode -Id $Id -Label "$($pkgResult.Name) ($Id)" -Type 'installed'
                }
            } catch { }

            # Fetch manifest from GitHub for dependency info
            $manifestDeps = Get-ManifestDependencies -PkgId $Id
            if ($manifestDeps) {
                Add-GraphNode -Id $Id -Label $Id -Type 'package'
                foreach ($dep in $manifestDeps) {
                    $depId = $dep.PackageIdentifier
                    $depType = if ($dep.Type) { $dep.Type } else { 'package' }

                    if (-not $IncludeExternal -and $depType -in @('WindowsFeature', 'WindowsStore')) {
                        continue
                    }

                    Add-GraphNode -Id $depId -Label $depId -Type $depType
                    Add-GraphEdge -From $Id -To $depId -Relation $depType
                    Get-PackageDependencies -Id $depId -CurrentDepth ($CurrentDepth + 1)
                }
            }

            $inStack.Remove($Id) | Out-Null
        }

        function Get-ManifestDependencies {
            param([string]$PkgId)

            try {
                $manifest = Get-WingetPkgsManifest -PackageId $PkgId
                if (-not $manifest -or -not $manifest.Installer) { return $null }

                # Dependencies can sit at the top level or under each installer; collect
                # PackageDependencies (and WindowsFeatures when requested) wherever they appear.
                $deps = [System.Collections.Generic.List[hashtable]]::new()
                $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $section = $null
                foreach ($line in ($manifest.Installer -split "\r?\n")) {
                    if ($line -match '^\s*(PackageDependencies|WindowsFeatures|WindowsLibraries|ExternalDependencies):\s*$') {
                        $section = $Matches[1]; continue
                    }
                    if ($section -eq 'PackageDependencies' -and $line -match '^\s*-\s*PackageIdentifier:\s*(\S+)') {
                        if ($seen.Add($Matches[1])) { $deps.Add(@{ PackageIdentifier = $Matches[1]; Type = 'package' }) }
                        continue
                    }
                    if ($section -eq 'PackageDependencies' -and $line -match '^\s*MinimumVersion:') { continue }
                    if ($section -eq 'WindowsFeatures' -and $line -match '^\s*-\s*(\S+)') {
                        if ($seen.Add($Matches[1])) { $deps.Add(@{ PackageIdentifier = $Matches[1]; Type = 'WindowsFeature' }) }
                        continue
                    }
                    # Any other key ends the current list
                    if ($line -match '^\s*[A-Za-z]+:' -and $line -notmatch '^\s*-') { $section = $null }
                }
                return $deps.ToArray()
            } catch {
                $status = [int]$_.Exception.Response.StatusCode
                if ($status -in 403, 429) {
                    Write-Warning "GitHub rate limit reached while reading $PkgId. Run New-WingetBatchGitHubToken for 5,000 requests/hour."
                }
                Write-Verbose "Could not fetch manifest for ${PkgId}: $_"
            }
            return $null
        }
    }
    process {
        if ($AllInstalled) {
            Write-Progress -Activity "Building dependency graph" -Status "Enumerating installed packages..." -PercentComplete 0
            # Only WinGet-sourced packages have winget-pkgs manifests
            $installed = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue | Where-Object { $_.Source -eq 'winget' })
            $total = $installed.Count
            if (-not (Get-WingetBatchGitHubToken) -and $total -gt 25) {
                Write-Warning "Scanning $total packages needs about $($total * 2) GitHub API requests; without a token the limit is 60/hour. Run New-WingetBatchGitHubToken first."
            }
            $i = 0

            foreach ($pkg in $installed) {
                $i++
                Write-Progress -Activity "Building dependency graph" -Status "Analyzing $($pkg.Id)" -PercentComplete (($i / $total) * 100)
                Add-GraphNode -Id $pkg.Id -Label "$($pkg.Name)" -Type 'installed'
                Get-PackageDependencies -Id $pkg.Id -CurrentDepth 1
            }
            Write-Progress -Activity "Building dependency graph" -Completed
        }
        else {
            foreach ($id in $PackageId) {
                Add-GraphNode -Id $id -Label $id -Type 'root'
                Get-PackageDependencies -Id $id -CurrentDepth 1
            }
        }
    }

    end {
        # Generate output based on format
        $output = switch ($Format) {
            'Mermaid' { Format-MermaidGraph }
            'DOT' { Format-DOTGraph }
            'Tree' { Format-TreeGraph }
            'Object' {
                [PSCustomObject]@{
                    Nodes = $graph.Nodes.Values | ForEach-Object {
                        [PSCustomObject]@{ Id = $_.Id; Label = $_.Label; Type = $_.Type; Dependencies = $_.Dependencies; Dependents = $_.Dependents }
                    }
                    Edges = $graph.Edges | ForEach-Object { [PSCustomObject]$_ }
                    CircularDependencies = $graph.Circular
                    Stats = [PSCustomObject]@{
                        TotalNodes = $graph.Nodes.Count
                        TotalEdges = $graph.Edges.Count
                        CircularCount = $graph.Circular.Count
                        OrphanNodes = ($graph.Nodes.Values | Where-Object { $_.Dependencies.Count -eq 0 -and $_.Dependents.Count -eq 0 }).Count
                    }
                }
            }
        }

        if ($OutputPath) {
            $output | Set-Content -Path $OutputPath -Encoding UTF8
            Write-Host "  Graph saved to: $OutputPath" -ForegroundColor Green
            Write-Host "  Nodes: $($graph.Nodes.Count) | Edges: $($graph.Edges.Count)" -ForegroundColor DarkGray
        } else {
            $output
        }

        # Warn about circular dependencies
        if ($graph.Circular.Count -gt 0) {
            Write-Warning "Circular dependencies detected: $($graph.Circular -join ', ')"
        }
    }
}

function Format-MermaidGraph {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("graph TD")

    # Node definitions with shapes based on type
    foreach ($node in $graph.Nodes.Values) {
        $safeId = $node.Id -replace '[^a-zA-Z0-9]', '_'
        $label = $node.Label -replace '"', '#quot;'
        switch ($node.Type) {
            'root' { [void]$sb.AppendLine("    $safeId[/`"$label`"/]") }  # Parallelogram for root
            'installed' { [void]$sb.AppendLine("    $safeId[`"$label`"]") }  # Rectangle
            'WindowsFeature' { [void]$sb.AppendLine("    $safeId((`"$label`"))") }  # Circle
            default { [void]$sb.AppendLine("    $safeId[`"$label`"]") }
        }
    }

    # Edges
    foreach ($edge in $graph.Edges) {
        $fromSafe = $edge.From -replace '[^a-zA-Z0-9]', '_'
        $toSafe = $edge.To -replace '[^a-zA-Z0-9]', '_'
        $style = if ($edge.Relation -eq 'WindowsFeature') { '-.->' } else { '-->' }
        [void]$sb.AppendLine("    $fromSafe $style $toSafe")
    }

    # Highlight circular
    if ($graph.Circular.Count -gt 0) {
        [void]$sb.AppendLine("")
        foreach ($circ in $graph.Circular) {
            $safeId = $circ -replace '[^a-zA-Z0-9]', '_'
            [void]$sb.AppendLine("    style $safeId stroke:#f00,stroke-width:3px")
        }
    }

    $sb.ToString()
}

function Format-DOTGraph {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("digraph WingetDependencies {")
    [void]$sb.AppendLine("    rankdir=LR;")
    [void]$sb.AppendLine("    node [shape=box, style=rounded, fontname=`"Segoe UI`"];")
    [void]$sb.AppendLine("    edge [fontname=`"Segoe UI`", fontsize=10];")
    [void]$sb.AppendLine("")

    foreach ($node in $graph.Nodes.Values) {
        $attrs = "label=`"$($node.Label -replace '"', '\"')`""
        switch ($node.Type) {
            'root' { $attrs += ", style=`"rounded,bold`", color=`"#2196F3`"" }
            'installed' { $attrs += ", color=`"#4CAF50`"" }
            'WindowsFeature' { $attrs += ", shape=ellipse, color=`"#FF9800`"" }
        }
        $safeId = "`"$($node.Id)`""
        [void]$sb.AppendLine("    $safeId [$attrs];")
    }

    [void]$sb.AppendLine("")
    foreach ($edge in $graph.Edges) {
        $style = if ($edge.Relation -eq 'WindowsFeature') { " [style=dashed, label=`"feature`"]" } else { "" }
        [void]$sb.AppendLine("    `"$($edge.From)`" -> `"$($edge.To)`"$style;")
    }

    [void]$sb.AppendLine("}")
    $sb.ToString()
}

function Format-TreeGraph {
    $sb = [System.Text.StringBuilder]::new()
    $roots = $graph.Nodes.Values | Where-Object { $_.Type -eq 'root' -or $_.Dependents.Count -eq 0 }

    function Write-TreeNode {
        param([hashtable]$Node, [string]$Prefix = "", [bool]$IsLast = $true, [bool]$IsRoot = $false)

        $connector = if ($IsRoot) { "" } elseif ($IsLast) { "└── " } else { "├── " }
        $typeIcon = switch ($Node.Type) {
            'root' { "◆" }
            'installed' { "●" }
            'WindowsFeature' { "○" }
            default { "○" }
        }

        [void]$sb.AppendLine("$Prefix$connector$typeIcon $($Node.Label)")

        $childPrefix = if ($IsRoot) { "" } elseif ($IsLast) { "$Prefix    " } else { "$Prefix│   " }
        $deps = @($Node.Dependencies | Select-Object -Unique)
        for ($i = 0; $i -lt $deps.Count; $i++) {
            $childId = $deps[$i]
            if ($graph.Nodes.ContainsKey($childId)) {
                Write-TreeNode -Node $graph.Nodes[$childId] -Prefix $childPrefix -IsLast ($i -eq $deps.Count - 1)
            }
        }
    }

    foreach ($root in $roots) {
        Write-TreeNode -Node $root -IsRoot $true
        [void]$sb.AppendLine("")
    }

    $sb.ToString()
}

# EndRegion

# Region: Public/Get-WingetHealthScore.ps1
function Get-WingetHealthScore {
    <#
    .SYNOPSIS
        Rate package trustworthiness and maintenance health.

    .DESCRIPTION
        Analyzes a package across multiple health dimensions and produces a
        composite 0-100 score with letter grade (A+ through F). Checks:

        - Freshness: How recently was the package updated in winget-pkgs?
        - Publisher Activity: Is the publisher's GitHub repo active?
        - Version Maturity: Stable releases vs pre-release/alpha/beta
        - Manifest Quality: Complete metadata (license, homepage, description)
        - Update Cadence: Regular updates vs abandoned
        - Source Trust: Official source vs third-party

        Answers the question: "Should I trust this package?"

    .PARAMETER PackageId
        One or more package IDs to analyze.

    .PARAMETER AllInstalled
        Score all installed packages (batch audit).

    .PARAMETER MinScore
        Only show packages below this score (for auditing).

    .PARAMETER Detailed
        Show full breakdown of each scoring dimension.

    .PARAMETER ExportReport
        Save health report to JSON.

    .EXAMPLE
        Get-WingetHealthScore -PackageId "Git.Git"
        Shows health score and grade for Git.

    .EXAMPLE
        Get-WingetHealthScore -PackageId "SomeObscure.Tool" -Detailed
        Full breakdown of why a package scored low.

    .EXAMPLE
        Get-WingetHealthScore -AllInstalled -MinScore 50
        Audit: show all installed packages scoring below 50.

    .NOTES
        Author: Matthew Bubb
        Scores are heuristic-based using public GitHub/winget-pkgs data.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory, Position = 0, ValueFromPipeline)]
        [string[]]$PackageId,

        [Parameter(ParameterSetName = 'AllInstalled', Mandatory)]
        [switch]$AllInstalled,

        [ValidateRange(0, 100)]
        [int]$MinScore = 100,

        [switch]$Detailed,

        [string]$ExportReport
    )

    begin {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        function Get-SingleHealthScore {
            param([string]$Id)

            $score = @{
                Freshness = 0       # 0-25: How recently updated
                PublisherActivity = 0  # 0-20: GitHub activity
                VersionMaturity = 0    # 0-20: Stable vs pre-release
                ManifestQuality = 0    # 0-20: Metadata completeness
                UpdateCadence = 0      # 0-15: Regular update pattern
            }
            $details = @{
                LastModified = $null
                LatestVersion = $null
                PublisherRepo = $null
                VersionCount = 0
                HasLicense = $false
                HasHomepage = $false
                HasDescription = $false
                IsPreRelease = $false
                SourceTrust = 'Unknown'
            }

            # --- Fetch manifest data from GitHub ---
            try {
                $versions = @(Get-WingetPkgsVersions -PackageId $Id)
                if ($versions.Count -eq 0) { throw "No versions found" }
                $details.VersionCount = $versions.Count
                $latestVersion = $versions[0].Name
                $details.LatestVersion = $latestVersion

                # FRESHNESS: date of the most recent commit touching this package
                $path = Get-WingetPkgsPackagePath -PackageId $Id
                $commits = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-pkgs/commits?path=$path&per_page=1" -Headers (Get-WingetPkgsHeaders) -ErrorAction SilentlyContinue
                Update-GitHubApiRequestCount -RequestCount 1 | Out-Null
                if ($commits -and $commits[0].commit.committer.date) {
                    $details.LastModified = [datetime]$commits[0].commit.committer.date
                    $age = ((Get-Date) - $details.LastModified).TotalDays
                    $score.Freshness = if ($age -le 30) { 25 } elseif ($age -le 90) { 20 } elseif ($age -le 180) { 15 } elseif ($age -le 365) { 10 } elseif ($age -le 730) { 5 } else { 2 }
                }
                else {
                    $score.Freshness = 10  # unknown: neutral
                }

                # MANIFEST QUALITY: the descriptive fields live in the locale manifest
                $manifest = Get-WingetPkgsManifest -PackageId $Id -Version $latestVersion
                $locale = $manifest.Locale
                $details.HasLicense = [bool](Get-WingetYamlValue -Yaml $locale -Key 'License')
                $details.HasHomepage = [bool]((Get-WingetYamlValue -Yaml $locale -Key 'PackageUrl') -or (Get-WingetYamlValue -Yaml $locale -Key 'PublisherUrl'))
                $details.HasDescription = [bool]((Get-WingetYamlValue -Yaml $locale -Key 'ShortDescription') -or (Get-WingetYamlValue -Yaml $locale -Key 'Description'))
                $details.PublisherRepo = Get-WingetYamlValue -Yaml $locale -Key 'PublisherUrl'
                if (-not $details.PublisherRepo) { $details.PublisherRepo = Get-WingetYamlValue -Yaml $locale -Key 'PackageUrl' }

                $qualityScore = 0
                if ($details.HasLicense) { $qualityScore += 7 }
                if ($details.HasHomepage) { $qualityScore += 7 }
                if ($details.HasDescription) { $qualityScore += 6 }
                $score.ManifestQuality = $qualityScore

                # VERSION MATURITY: judge the version string and package ID only
                # (searching the whole manifest matched words like "Source")
                $details.IsPreRelease = ($latestVersion -match '(?i)(alpha|beta|preview|nightly|canary|insider|dev|\brc\d*\b|-rc)') -or
                                        ($Id -match '(?i)\.(Preview|Beta|Nightly|Canary|Insiders?|Dev)$')
                if ($details.IsPreRelease) {
                    $score.VersionMaturity = 8
                } elseif ((Compare-WingetVersion -ReferenceVersion $latestVersion -DifferenceVersion '1.0') -lt 0) {
                    $score.VersionMaturity = 12  # 0.x releases
                } elseif ($versions.Count -ge 3) {
                    $score.VersionMaturity = 20
                } else {
                    $score.VersionMaturity = 15
                }

                # UPDATE CADENCE: how many releases have been published to winget
                if ($versions.Count -ge 30) { $score.UpdateCadence = 15 }
                elseif ($versions.Count -ge 15) { $score.UpdateCadence = 12 }
                elseif ($versions.Count -ge 5) { $score.UpdateCadence = 9 }
                elseif ($versions.Count -ge 2) { $score.UpdateCadence = 6 }
                else { $score.UpdateCadence = 3 }

                # PUBLISHER ACTIVITY: recent commit + sustained release history
                $activity = 0
                if ($details.LastModified -and ((Get-Date) - $details.LastModified).TotalDays -le 180) { $activity += 10 }
                elseif ($details.LastModified -and ((Get-Date) - $details.LastModified).TotalDays -le 365) { $activity += 5 }
                if ($versions.Count -ge 10) { $activity += 10 } elseif ($versions.Count -ge 3) { $activity += 5 }
                $score.PublisherActivity = $activity

                $details.SourceTrust = 'winget-pkgs (community repository)'
            }
            catch {
                $status = [int]$_.Exception.Response.StatusCode
                if ($status -in 403, 429) {
                    Write-Warning "GitHub rate limit reached while scoring $Id. Run New-WingetBatchGitHubToken for 5,000 requests/hour."
                    $details.SourceTrust = 'Unknown (rate limited)'
                }
                else {
                    # Package not found on GitHub - low trust
                    $details.SourceTrust = 'Not found in winget-pkgs'
                }
                $score.Freshness = 3
                $score.PublisherActivity = 3
                $score.VersionMaturity = 5
                $score.ManifestQuality = 3
                $score.UpdateCadence = 2
            }
            # --- Composite Score ---
            $total = $score.Freshness + $score.PublisherActivity + $score.VersionMaturity + $score.ManifestQuality + $score.UpdateCadence

            # Letter grade
            $grade = if ($total -ge 90) { 'A+' }
                     elseif ($total -ge 80) { 'A' }
                     elseif ($total -ge 70) { 'B' }
                     elseif ($total -ge 60) { 'C' }
                     elseif ($total -ge 50) { 'D' }
                     else { 'F' }

            $gradeColor = if ($total -ge 80) { 'Green' }
                          elseif ($total -ge 60) { 'Yellow' }
                          else { 'Red' }

            return @{
                PackageId = $Id
                Score = $total
                Grade = $grade
                GradeColor = $gradeColor
                Breakdown = $score
                Details = $details
            }
        }
    }

    process {
        $ids = @()
        if ($AllInstalled) {
            # Only winget-sourced packages have winget-pkgs manifests
            $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue | Where-Object { $_.Source -eq 'winget' }
            $ids = @($installed | ForEach-Object { $_.Id })
            if (-not (Get-WingetBatchGitHubToken) -and $ids.Count -gt 15) {
                Write-Warning "Scoring $($ids.Count) packages needs about $($ids.Count * 3) GitHub API requests; without a token the limit is 60/hour. Run New-WingetBatchGitHubToken first."
            }
            Write-Host "`n  Scoring $($ids.Count) installed packages...`n" -ForegroundColor Cyan
        } else {
            $ids = $PackageId
        }

        $i = 0
        foreach ($id in $ids) {
            $i++
            if ($AllInstalled) {
                Write-Progress -Activity "Health Scoring" -Status "[$i/$($ids.Count)] $id" -PercentComplete (($i / $ids.Count) * 100)
            }

            $health = Get-SingleHealthScore -Id $id

            # Filter by min score
            if ($health.Score -lt $MinScore -or -not $AllInstalled) {
                $results.Add([PSCustomObject]@{
                    PackageId = $health.PackageId
                    Score = $health.Score
                    Grade = $health.Grade
                    Freshness = $health.Breakdown.Freshness
                    PublisherActivity = $health.Breakdown.PublisherActivity
                    VersionMaturity = $health.Breakdown.VersionMaturity
                    ManifestQuality = $health.Breakdown.ManifestQuality
                    UpdateCadence = $health.Breakdown.UpdateCadence
                    Details = $health.Details
                })

                # Display
                $bar = ('█' * [Math]::Round($health.Score / 5)).PadRight(20, '░')
                Write-Host "  $($health.Grade) " -NoNewline -ForegroundColor $health.GradeColor
                Write-Host "$bar " -NoNewline -ForegroundColor $health.GradeColor
                Write-Host "$($health.Score)/100 " -NoNewline -ForegroundColor White
                Write-Host $id -ForegroundColor Cyan

                if ($Detailed) {
                    Write-Host "      Freshness:        $($health.Breakdown.Freshness)/25" -ForegroundColor DarkGray
                    Write-Host "      Publisher:        $($health.Breakdown.PublisherActivity)/20" -ForegroundColor DarkGray
                    Write-Host "      Version Maturity: $($health.Breakdown.VersionMaturity)/20" -ForegroundColor DarkGray
                    Write-Host "      Manifest Quality: $($health.Breakdown.ManifestQuality)/20" -ForegroundColor DarkGray
                    Write-Host "      Update Cadence:   $($health.Breakdown.UpdateCadence)/15" -ForegroundColor DarkGray
                    Write-Host "      Source: $($health.Details.SourceTrust)" -ForegroundColor DarkGray
                    if ($health.Details.LastModified) {
                        Write-Host "      Last updated: $($health.Details.LastModified.ToString('yyyy-MM-dd')) (v$($health.Details.LatestVersion))" -ForegroundColor DarkGray
                    }
                    if ($health.Details.PublisherRepo) {
                        Write-Host "      URL: $($health.Details.PublisherRepo)" -ForegroundColor DarkGray
                    }
                    Write-Host ""
                }
            }
        }

        if ($AllInstalled) { Write-Progress -Activity "Health Scoring" -Completed }
    }

    end {
        # Summary
        if ($results.Count -gt 1) {
            $avg = [Math]::Round(($results | Measure-Object Score -Average).Average, 1)
            $lowCount = ($results | Where-Object { $_.Score -lt 50 }).Count
            Write-Host ""
            Write-Host "  Summary: $($results.Count) packages scored | Average: $avg/100 | Below 50: $lowCount" -ForegroundColor DarkGray
            Write-Host ""
        }

        # Export
        if ($ExportReport) {
            $report = @{
                Timestamp = (Get-Date).ToString('o')
                Hostname = $env:COMPUTERNAME
                PackageCount = $results.Count
                AverageScore = [Math]::Round(($results | Measure-Object Score -Average).Average, 1)
                Packages = @($results | ForEach-Object {
                    @{ Id = $_.PackageId; Score = $_.Score; Grade = $_.Grade }
                })
            }
            $report | ConvertTo-Json -Depth 5 | Set-Content -Path $ExportReport -Encoding UTF8
            Write-Host "  Report saved: $ExportReport" -ForegroundColor Green
        }

        return $results
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

    .PARAMETER PassThru
        Return the history entries as objects instead of printing the timeline.

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
        [switch]$ExportJson,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        if (-not (Get-Module -Name PwshSpectreConsole)) {
            if (Get-Module -ListAvailable -Name PwshSpectreConsole) {
                Import-Module PwshSpectreConsole -ErrorAction SilentlyContinue
            }
        }
    }

    process {
        if (-not $PassThru) {
            Write-Host ""
            Write-Host "  Scanning installation history..." -ForegroundColor Cyan
        }

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

        if ($PassThru) {
            return $history.ToArray()
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

            foreach ($entry in $dayGroup.Group) {
                $actionColor = switch ($entry.Action) {
                    'Installed' { 'Green' }
                    'Updated' { 'Yellow' }
                    'Removed' { 'Red' }
                    default { 'Gray' }
                }
                $actionIcon = switch ($entry.Action) {
                    'Installed' { '+' }
                    'Updated' { '~' }
                    'Removed' { '-' }
                    default { '?' }
                }

                Write-Host "    [$actionIcon] " -ForegroundColor $actionColor -NoNewline
                Write-Host $entry.Name -ForegroundColor White -NoNewline

                if ($entry.Version) {
                    Write-Host " v$($entry.Version)" -ForegroundColor Green -NoNewline
                }
                if ($entry.Publisher) {
                    Write-Host " ($($entry.Publisher))" -ForegroundColor DarkGray -NoNewline
                }
                if ($entry.SizeMB) {
                    Write-Host " [$($entry.SizeMB) MB]" -ForegroundColor DarkGray -NoNewline
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

        Only packages that come from a WinGet source (winget, msstore) are exported and
        considered for removal. Programs WinGet merely sees in Add/Remove Programs
        (drivers, runtimes, OEM tools) cannot be reinstalled from a manifest and are
        never touched unless -IncludeUnmanaged is used for export.

    .PARAMETER Export
        Export the current machine state to a manifest file.

    .PARAMETER Path
        Path to the state manifest file (.json or .yaml).

    .PARAMETER Compare
        Compare the current machine state against a saved manifest and report drift.

    .PARAMETER Reconcile
        Install missing packages and update outdated ones to match the target manifest.

    .PARAMETER RemoveExtraneous
        When used with -Reconcile, also uninstall WinGet-sourced packages not present in the manifest.

    .PARAMETER Force
        With -Reconcile, skip the confirmation prompt (for unattended use).

    .PARAMETER Format
        Output format for exported manifests: JSON (default) or YAML.

    .PARAMETER IncludeVersions
        Include specific version pins in the export (default: latest).

    .PARAMETER IncludeUnmanaged
        Also export packages that have no WinGet source (informational only; they cannot be reinstalled).

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

        [Parameter(ParameterSetName = 'Reconcile')]
        [switch]$Force,

        [Parameter(ParameterSetName = 'Export')]
        [ValidateSet('JSON', 'YAML')]
        [string]$Format = 'JSON',

        [Parameter(ParameterSetName = 'Export')]
        [switch]$IncludeVersions,

        [Parameter(ParameterSetName = 'Export')]
        [switch]$IncludeUnmanaged,

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

        # --- Helpers (defined here so they exist before process{} calls them) ---

        function Read-StateManifest {
            param([string]$ManifestPath)

            if (-not (Test-Path $ManifestPath)) {
                throw "State manifest not found: $ManifestPath"
            }
            $content = Get-Content -Raw -Path $ManifestPath
            if ($ManifestPath -match '\.ya?ml$') {
                if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
                    throw "powershell-yaml module required for YAML manifests (Install-Module powershell-yaml)."
                }
                Import-Module powershell-yaml -ErrorAction Stop
                $manifest = ConvertFrom-Yaml $content
            }
            else {
                $manifest = $content | ConvertFrom-Json
            }

            $targets = foreach ($pkg in @($manifest.packages)) {
                if (-not $pkg) { continue }
                $id = if ($pkg -is [string]) { $pkg } else { [string]$pkg.id }
                if (-not $id) { continue }
                $ver = if ($pkg -isnot [string] -and $pkg.version) { [string]$pkg.version } else { 'latest' }
                $src = if ($pkg -isnot [string] -and $pkg.source) { [string]$pkg.source } else { $null }
                [PSCustomObject]@{ Id = $id; Version = $ver; Source = $src }
            }
            if (-not $targets) { throw "No packages found in manifest: $ManifestPath" }
            return @($targets)
        }

        function Get-InstalledMap {
            $map = @{}
            foreach ($pkg in (Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue)) {
                if ($pkg.Id -and -not $map.ContainsKey($pkg.Id)) { $map[$pkg.Id] = $pkg }
            }
            return $map
        }

        # Returns the drift between a target list and the installed map
        function Get-StateDrift {
            param($Targets, [hashtable]$InstalledMap)

            $missing = [System.Collections.Generic.List[PSCustomObject]]::new()
            $outdated = [System.Collections.Generic.List[PSCustomObject]]::new()
            $compliant = [System.Collections.Generic.List[string]]::new()
            $unmanageable = [System.Collections.Generic.List[string]]::new()
            $targetIds = @{}

            foreach ($t in $Targets) {
                $targetIds[$t.Id] = $true
                if ($InstalledMap.ContainsKey($t.Id)) {
                    $inst = $InstalledMap[$t.Id]
                    if ($t.Version -ne 'latest') {
                        # Pinned: compliant only when exactly that version is installed
                        if ((Compare-WingetVersion -ReferenceVersion $inst.InstalledVersion -DifferenceVersion $t.Version) -eq 0) {
                            $compliant.Add($t.Id)
                        }
                        else {
                            $outdated.Add([PSCustomObject]@{ Id = $t.Id; Installed = $inst.InstalledVersion; Target = $t.Version; Pinned = $true; Source = $inst.Source })
                        }
                    }
                    elseif ($inst.IsUpdateAvailable) {
                        $outdated.Add([PSCustomObject]@{ Id = $t.Id; Installed = $inst.InstalledVersion; Target = @($inst.AvailableVersions)[0]; Pinned = $false; Source = $inst.Source })
                    }
                    else {
                        $compliant.Add($t.Id)
                    }
                }
                elseif ($t.Id -match '^(ARP|MSIX)\\') {
                    # Add/Remove Programs entries from old exports cannot be installed by WinGet
                    $unmanageable.Add($t.Id)
                }
                else {
                    $missing.Add($t)
                }
            }

            # Extraneous = WinGet-sourced packages not in the manifest. Unsourced entries are ignored.
            $extraneous = [System.Collections.Generic.List[string]]::new()
            foreach ($id in $InstalledMap.Keys) {
                if (-not $targetIds.ContainsKey($id) -and $InstalledMap[$id].Source) {
                    $extraneous.Add($id)
                }
            }

            [PSCustomObject]@{
                Missing      = $missing
                Outdated     = $outdated
                Compliant    = $compliant
                Extraneous   = @($extraneous | Sort-Object)
                Unmanageable = $unmanageable
            }
        }

        function Invoke-StateExport {
            Write-Host ""
            Write-Host "  Capturing machine package state..." -ForegroundColor Cyan

            $installed = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue)
            if ($installed.Count -eq 0) {
                Write-Error "No installed packages found via COM API."
                return
            }

            $skipped = 0
            if (-not $IncludeUnmanaged) {
                $managed = @($installed | Where-Object { $_.Source })
                $skipped = $installed.Count - $managed.Count
                $installed = $managed
            }
            if ($Source) {
                $installed = @($installed | Where-Object { $_.Source -eq $Source })
            }

            $packages = [System.Collections.Generic.List[object]]::new()
            foreach ($pkg in ($installed | Sort-Object Id)) {
                $entry = [ordered]@{ id = $pkg.Id }
                $entry['version'] = if ($IncludeVersions -and $pkg.InstalledVersion) { $pkg.InstalledVersion } else { 'latest' }
                if ($pkg.Source) { $entry['source'] = $pkg.Source }
                $packages.Add([PSCustomObject]$entry)
            }

            $manifest = [ordered]@{
                _metadata = [ordered]@{
                    generator     = "WingetBatch v$((Get-Module WingetBatch).Version)"
                    created       = (Get-Date).ToString('o')
                    hostname      = $env:COMPUTERNAME
                    username      = $env:USERNAME
                    os_version    = [System.Environment]::OSVersion.VersionString
                    package_count = $packages.Count
                }
                packages = $packages
            }

            $outPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            $outDir = Split-Path $outPath -Parent
            if ($outDir -and -not (Test-Path $outDir)) {
                New-Item -ItemType Directory -Path $outDir -Force | Out-Null
            }

            if ($Format -eq 'YAML' -and -not (Get-Module -ListAvailable -Name powershell-yaml)) {
                Write-Warning "powershell-yaml module not found. Falling back to JSON."
                $outPath = $outPath -replace '\.ya?ml$', '.json'
                $Format = 'JSON'
            }
            if ($Format -eq 'YAML') {
                Import-Module powershell-yaml -ErrorAction Stop
                $manifest | ConvertTo-Yaml | Out-File -FilePath $outPath -Encoding utf8
            }
            else {
                $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $outPath -Encoding utf8
            }

            Write-Host ""
            Write-Host "  [OK] " -ForegroundColor Green -NoNewline
            Write-Host "$($packages.Count) packages" -ForegroundColor White -NoNewline
            Write-Host " exported to " -ForegroundColor Green -NoNewline
            Write-Host $outPath -ForegroundColor Cyan
            if ($skipped -gt 0) {
                Write-Host "  Skipped $skipped programs with no WinGet source (use -IncludeUnmanaged to list them)." -ForegroundColor DarkGray
            }
            Write-Host ""
        }

        function Invoke-StateCompare {
            $manifestPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            try { $targets = Read-StateManifest -ManifestPath $manifestPath }
            catch { Write-Error $_.Exception.Message; return }

            Write-Host ""
            Write-Host "  Comparing machine state against manifest..." -ForegroundColor Cyan
            Write-Host "  Manifest: " -ForegroundColor Gray -NoNewline
            Write-Host $manifestPath -ForegroundColor White

            $drift = Get-StateDrift -Targets $targets -InstalledMap (Get-InstalledMap)

            Write-Host ""
            Write-Host "  Drift Analysis Report" -ForegroundColor White
            Write-Host "  $('=' * 50)" -ForegroundColor DarkGray

            if ($drift.Compliant.Count -gt 0) {
                Write-Host "  [OK] Compliant: " -ForegroundColor Green -NoNewline
                Write-Host "$($drift.Compliant.Count) packages" -ForegroundColor White
            }
            if ($drift.Missing.Count -gt 0) {
                Write-Host "  [!] Missing:   " -ForegroundColor Red -NoNewline
                Write-Host "$($drift.Missing.Count) packages" -ForegroundColor White
                foreach ($m in $drift.Missing) {
                    $v = if ($m.Version -ne 'latest') { " (v$($m.Version))" } else { '' }
                    Write-Host "       - $($m.Id)$v" -ForegroundColor Red
                }
            }
            if ($drift.Outdated.Count -gt 0) {
                Write-Host "  [~] Outdated:  " -ForegroundColor Yellow -NoNewline
                Write-Host "$($drift.Outdated.Count) packages" -ForegroundColor White
                foreach ($o in $drift.Outdated) {
                    $pin = if ($o.Pinned) { ' (pinned)' } else { '' }
                    Write-Host "       - $($o.Id) ($($o.Installed) -> $($o.Target))$pin" -ForegroundColor Yellow
                }
            }
            if ($drift.Extraneous.Count -gt 0) {
                Write-Host "  [+] Extraneous:" -ForegroundColor Magenta -NoNewline
                Write-Host " $($drift.Extraneous.Count) packages" -ForegroundColor White
                foreach ($e in $drift.Extraneous) {
                    Write-Host "       - $e" -ForegroundColor DarkGray
                }
            }
            if ($drift.Unmanageable.Count -gt 0) {
                Write-Host "  [-] Skipped:   $($drift.Unmanageable.Count) manifest entries have no WinGet source and cannot be installed" -ForegroundColor DarkGray
            }

            Write-Host ""
            $totalDrift = $drift.Missing.Count + $drift.Outdated.Count
            if ($totalDrift -eq 0) {
                Write-Host "  [OK] Machine is fully compliant with target state." -ForegroundColor Green
            }
            else {
                Write-Host "  [!] Drift detected: $totalDrift package(s) need attention." -ForegroundColor Yellow
                Write-Host "      Run: Get-WingetMachineState -Reconcile -Path '$Path'" -ForegroundColor DarkGray
            }
            Write-Host ""

            # Return structured object for pipeline use
            [PSCustomObject]@{
                Compliant   = $drift.Compliant.Count
                Missing     = @($drift.Missing | ForEach-Object { $_.Id })
                Outdated    = $drift.Outdated
                Extraneous  = $drift.Extraneous
                IsCompliant = ($totalDrift -eq 0)
            }
        }

        function Invoke-StateReconcile {
            $manifestPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
            try { $targets = Read-StateManifest -ManifestPath $manifestPath }
            catch { Write-Error $_.Exception.Message; return }

            Write-Host ""
            Write-Host "  Reconciling machine state to target manifest..." -ForegroundColor Cyan

            $drift = Get-StateDrift -Targets $targets -InstalledMap (Get-InstalledMap)
            $toRemove = if ($RemoveExtraneous) { $drift.Extraneous } else { @() }

            $totalActions = $drift.Missing.Count + $drift.Outdated.Count + $toRemove.Count
            if ($totalActions -eq 0) {
                Write-Host "  [OK] Machine is already compliant. No actions needed." -ForegroundColor Green
                return
            }

            Write-Host ""
            Write-Host "  Reconciliation Plan:" -ForegroundColor White
            foreach ($m in $drift.Missing) { Write-Host "    + install  $($m.Id)$(if ($m.Version -ne 'latest') { " v$($m.Version)" })" -ForegroundColor Green }
            foreach ($o in $drift.Outdated) { Write-Host "    ~ $(if ($o.Pinned) { 'pin    ' } else { 'update ' }) $($o.Id) $($o.Installed) -> $($o.Target)" -ForegroundColor Yellow }
            foreach ($r in $toRemove) { Write-Host "    - remove   $r" -ForegroundColor Red }
            Write-Host ""

            if (-not $Force) {
                $confirmMsg = "Proceed with reconciliation of $totalActions package(s)?"
                if (-not $PSCmdlet.ShouldContinue($confirmMsg, "WingetBatch State Reconciliation")) {
                    Write-Host "  Cancelled." -ForegroundColor Yellow
                    return
                }
            }

            Invoke-WingetAutoSnapshot -Reason 'Get-WingetMachineState -Reconcile'

            $successCount = 0
            $failCount = 0
            $report = {
                param($result)
                if ($result.Succeeded) {
                    Write-Host "      [OK]" -ForegroundColor Green
                    return $true
                }
                Write-Host "      [FAIL] $($result.Message)" -ForegroundColor Red
                return $false
            }

            foreach ($pkg in $drift.Missing) {
                Write-Host "  >>> Installing: " -ForegroundColor Green -NoNewline
                Write-Host $pkg.Id -ForegroundColor White
                $r = Invoke-WingetPackageAction -Action Install -Id $pkg.Id -Version $pkg.Version -Source $pkg.Source -Options @{ Mode = 'Silent' }
                if (& $report $r) { $successCount++ } else { $failCount++ }
            }

            foreach ($pkg in $drift.Outdated) {
                Write-Host "  >>> $(if ($pkg.Pinned) { 'Pinning' } else { 'Updating' }): " -ForegroundColor Yellow -NoNewline
                Write-Host "$($pkg.Id) -> $($pkg.Target)" -ForegroundColor White
                if ($pkg.Pinned) {
                    # Verified move to an exact (possibly older) version
                    $r = Set-WingetPackageVersion -Id $pkg.Id -Version $pkg.Target -Source $pkg.Source
                }
                else {
                    $r = Invoke-WingetPackageAction -Action Update -Id $pkg.Id -Source $pkg.Source -Options @{ Mode = 'Silent' }
                }
                if (& $report $r) { $successCount++ } else { $failCount++ }
            }

            foreach ($pkgId in $toRemove) {
                Write-Host "  >>> Removing: " -ForegroundColor Red -NoNewline
                Write-Host $pkgId -ForegroundColor White
                $r = Invoke-WingetPackageAction -Action Uninstall -Id $pkgId -Options @{ Mode = 'Silent' }
                if (& $report $r) { $successCount++ } else { $failCount++ }
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

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'Export' { Invoke-StateExport }
            'Compare' { Invoke-StateCompare }
            'Reconcile' { Invoke-StateReconcile }
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
        # GitHub expects UTC; formatting local time with a 'Z' suffix shifted the window by the UTC offset
        $since = (Get-Date).ToUniversalTime().Subtract($timeSpan).ToString("yyyy-MM-ddTHH:mm:ssZ")

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
                # Rate limiting on the first page means there is nothing to show - surface it
                $statusCode = [int]$_.Exception.Response.StatusCode
                if ($page -eq 1 -and $statusCode -in 403, 429) { throw }
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
            Write-Warning "No commits found in the last $timeDesc. The winget-pkgs repository might have no recent activity."
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
                            $comResult = Microsoft.WinGet.Client\Find-WinGetPackage -Id $packageId -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue | Select-Object -First 1
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
            } -ArgumentList (,$packageBatch), $configDir, ${function:Parse-WingetShowOutput}, $wingetExe

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
                                                $comResult = Microsoft.WinGet.Client\Find-WinGetPackage -Id $pkgId -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue | Select-Object -First 1
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
                    $installOptions = @{
                        Mode = $(if ($Mode) { $Mode } else { 'Silent' })
                        Scope = $Scope; Architecture = $Architecture; Override = $Override; Location = $Location
                        Force = [bool]$ForceInstall; SkipDependencies = [bool]$SkipDependencies; AllowHashMismatch = [bool]$AllowHashMismatch
                    }

                    Invoke-WingetAutoSnapshot -Reason 'Get-WingetNewPackages'

                    foreach ($packageId in $packagesToInstall) {
                        Write-Host "`n>>> Installing: " -ForegroundColor Magenta -NoNewline
                        Write-Host $packageId -ForegroundColor White

                        # New packages come from the winget-pkgs repository, i.e. the winget source
                        $result = Invoke-WingetPackageAction -Action Install -Id $packageId -Source 'winget' -Options $installOptions
                        if ($result.Succeeded) {
                            Write-Host "[OK] Successfully installed " -ForegroundColor Green -NoNewline
                            Write-Host $packageId -ForegroundColor White
                            $successCount++
                        }
                        else {
                            Write-Host "[FAIL] Failed to install " -ForegroundColor Red -NoNewline
                            Write-Host $packageId -ForegroundColor White -NoNewline
                            Write-Host " ($($result.Message))" -ForegroundColor Red
                            $failCount++
                        }
                    }

                    Write-Host ("`n" + ("=" * 60)) -ForegroundColor Green
                    Write-Host "Installation Complete" -ForegroundColor Green
                    Write-Host ("=" * 60) -ForegroundColor Green
                    Write-Host "Installed: " -ForegroundColor Green -NoNewline
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
            Write-Host "`n$("-" * 62)" -ForegroundColor Yellow
            Write-Host "[!] GitHub API Rate Limit Exceeded" -ForegroundColor Yellow
            Write-Host ("-" * 62) -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Unauthenticated requests are limited to 60 per hour." -ForegroundColor White
            Write-Host ""
            Write-Host "To get higher limits (5,000 requests/hour):" -ForegroundColor Cyan
            Write-Host "  1. Run: " -NoNewline -ForegroundColor White
            Write-Host "New-WingetBatchGitHubToken" -ForegroundColor Yellow
            Write-Host "     (Interactive wizard to create and save a token)" -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "Or wait an hour and try again with a shorter time period." -ForegroundColor DarkGray
            Write-Host ("-" * 62) -ForegroundColor Yellow
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

        # Also check if installed locally (exact ID match; -Id alone is a substring search)
        $localPkg = Microsoft.WinGet.Client\Get-WinGetPackage -Id $package.Id -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue | Select-Object -First 1

        # Extended details come from the package's winget-pkgs manifest
        $manifest = $null
        $versionList = $null
        if ($ShowManifest -or $ShowVersions) {
            Write-Host ""
            Write-Host "  Fetching extended details from winget-pkgs..." -ForegroundColor DarkGray
            try {
                $versionList = @(Get-WingetPkgsVersions -PackageId $package.Id)
                if ($versionList.Count -gt 0) {
                    $manifest = Get-WingetPkgsManifest -PackageId $package.Id -Version $versionList[0].Name
                }
            }
            catch {
                $status = [int]$_.Exception.Response.StatusCode
                if ($status -in 403, 429) {
                    Write-Host "  GitHub rate limit reached - run New-WingetBatchGitHubToken for 5,000 requests/hour." -ForegroundColor Yellow
                }
                else {
                    Write-Host "  Package not found in winget-pkgs (it may come from another source)." -ForegroundColor DarkGray
                }
            }
        }

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
            if ($localPkg.IsUpdateAvailable -and @($localPkg.AvailableVersions).Count -gt 0) {
                $infoItems['Latest Version'] = @($localPkg.AvailableVersions)[0]
            }
        }

        if ($manifest) {
            $fields = [ordered]@{
                'Publisher'   = 'Publisher'
                'Description' = 'ShortDescription'
                'License'     = 'License'
                'License URL' = 'LicenseUrl'
                'Homepage'    = 'PackageUrl'
                'Release Notes' = 'ReleaseNotesUrl'
                'Moniker'     = 'Moniker'
            }
            foreach ($label in $fields.Keys) {
                $value = Get-WingetYamlValue -Yaml $manifest.Locale -Key $fields[$label]
                if ($value) { $infoItems[$label] = $value }
            }
            $installerType = Get-WingetYamlValue -Yaml $manifest.Installer -Key 'InstallerType'
            if (-not $installerType -and $manifest.Installer -match '(?m)^\s+InstallerType:\s*(\S+)') { $installerType = $Matches[1] }
            if ($installerType) { $infoItems['Installer'] = $installerType }
        }

        # Calculate max key width for alignment
        $maxKeyLen = ($infoItems.Keys | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum

        foreach ($key in $infoItems.Keys) {
            $paddedKey = $key.PadRight($maxKeyLen + 2)
            $value = $infoItems[$key]
            $color = switch ($key) {
                'Update Available' { if ($value -eq 'Yes') { 'Yellow' } else { 'Green' } }
                'Id' { 'Cyan' }
                { $_ -in 'License URL', 'Homepage', 'Release Notes' } { 'Cyan' }
                default { 'White' }
            }
            Write-Host "  $paddedKey" -ForegroundColor Gray -NoNewline
            Write-Host $value -ForegroundColor $color
        }

        if ($ShowVersions -and $versionList) {
            Write-Host ""
            Write-Host "  Available Versions ($($versionList.Count)):" -ForegroundColor White
            $showCount = [Math]::Min($versionList.Count, 15)
            for ($i = 0; $i -lt $showCount; $i++) {
                $v = $versionList[$i].Name
                $isInstalled = $localPkg -and (Compare-WingetVersion -ReferenceVersion $localPkg.InstalledVersion -DifferenceVersion $v) -eq 0
                $marker = if ($isInstalled) { ' * installed' } else { '' }
                Write-Host "    - $v$marker" -ForegroundColor $(if ($isInstalled) { 'Green' } else { 'Gray' })
            }
            if ($versionList.Count -gt 15) {
                Write-Host "    ... and $($versionList.Count - 15) more" -ForegroundColor DarkGray
            }
        }

        if ($ShowManifest -and $manifest -and $manifest.Installer) {
            Write-Host ""
            Write-Host "  Installer Manifest (v$($manifest.Version)):" -ForegroundColor White
            Write-Host "  $('─' * 50)" -ForegroundColor DarkGray
            $manifestLines = $manifest.Installer -split "\r?\n"
            foreach ($line in ($manifestLines | Select-Object -First 40)) {
                Write-Host "  $line" -ForegroundColor DarkGray
            }
            if ($manifestLines.Count -gt 40) {
                Write-Host "  ... (truncated)" -ForegroundColor DarkGray
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

# Region: Public/Get-WingetRecommend.ps1
function Get-WingetRecommend {
    <#
    .SYNOPSIS
        AI-powered package recommendations using local heuristic matching.

    .DESCRIPTION
        Recommends packages based on a persona/role description or by analyzing
        your current installed packages ("clone this machine's personality").

        Uses a curated knowledge base of package archetypes mapped to roles,
        combined with co-occurrence analysis of your installed packages to
        suggest complementary software you're likely missing.

        No external AI/LLM required — pure local heuristic matching that
        feels magic.

    .PARAMETER Persona
        A role or description of what you do. Examples:
        "backend developer", "data scientist", "gamer", "devops engineer",
        "web developer", "game developer", "security researcher", "student"

    .PARAMETER ClonePersonality
        Analyze installed packages and recommend complementary ones you're missing.
        Uses co-occurrence patterns and archetype matching.

    .PARAMETER Category
        Filter recommendations to a category: Development, Productivity, Gaming,
        Design, DevOps, Security, Media, Utilities.

    .PARAMETER MaxResults
        Maximum recommendations to return. Default: 20.

    .PARAMETER ExcludeInstalled
        Hide packages already installed. Default: true.

    .PARAMETER Install
        Interactively select and install recommended packages.

    .PARAMETER Explain
        Show why each package was recommended (matching reasoning).

    .EXAMPLE
        Get-WingetRecommend -Persona "backend developer"
        Recommends packages for a backend dev workflow.

    .EXAMPLE
        Get-WingetRecommend -ClonePersonality
        Analyzes your machine and suggests what's missing.

    .EXAMPLE
        Get-WingetRecommend -Persona "data scientist" -Install
        Shows recommendations then lets you pick which to install.

    .EXAMPLE
        Get-WingetRecommend -Category DevOps -Explain
        DevOps packages with reasoning for each recommendation.

    .NOTES
        Author: Matthew Bubb
        The recommendation engine uses a local archetype database with
        co-occurrence scoring. No data leaves your machine.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Persona')]
    param(
        [Parameter(ParameterSetName = 'Persona', Mandatory, Position = 0)]
        [string]$Persona,

        [Parameter(ParameterSetName = 'Clone', Mandatory)]
        [switch]$ClonePersonality,

        [Parameter()]
        [ValidateSet('Development', 'Productivity', 'Gaming', 'Design', 'DevOps', 'Security', 'Media', 'Utilities')]
        [string]$Category,

        [ValidateRange(5, 100)]
        [int]$MaxResults = 20,

        [bool]$ExcludeInstalled = $true,

        [switch]$Install,

        [switch]$Explain
    )

    # --- ARCHETYPE KNOWLEDGE BASE ---
    # Each archetype: keywords that match, packages with weights and reasons
    $archetypes = @{
        'Backend Developer' = @{
            Keywords = @('backend', 'api', 'server', 'microservice', 'database', 'sql', 'rest', 'grpc', 'dotnet', 'java', 'python', 'go', 'rust', 'node')
            Packages = @(
                @{ Id = 'Git.Git'; Weight = 10; Reason = 'Version control foundation' }
                @{ Id = 'Docker.DockerDesktop'; Weight = 9; Reason = 'Container-based service orchestration' }
                @{ Id = 'Microsoft.VisualStudioCode'; Weight = 9; Reason = 'Primary code editor with extensions' }
                @{ Id = 'JetBrains.IntelliJIDEA.Community'; Weight = 7; Reason = 'JVM language IDE' }
                @{ Id = 'Python.Python.3.13'; Weight = 8; Reason = 'Scripting and service tooling' }
                @{ Id = 'GoLang.Go'; Weight = 7; Reason = 'High-performance service language' }
                @{ Id = 'Rustlang.Rustup'; Weight = 6; Reason = 'Systems programming language' }
                @{ Id = 'PostgreSQL.PostgreSQL.17'; Weight = 8; Reason = 'Relational database server' }
                @{ Id = 'Redis.Redis'; Weight = 7; Reason = 'In-memory cache and message broker' }
                @{ Id = 'Microsoft.DotNet.SDK.10'; Weight = 8; Reason = '.NET runtime and SDK' }
                @{ Id = 'OpenJS.NodeJS.LTS'; Weight = 8; Reason = 'JavaScript runtime for tooling' }
                @{ Id = 'JetBrains.DataGrip'; Weight = 6; Reason = 'Database IDE and query tool' }
                @{ Id = 'Postman.Postman'; Weight = 7; Reason = 'API testing and documentation' }
                @{ Id = 'GrafanaLabs.Alloy'; Weight = 5; Reason = 'Observability and metrics' }
                @{ Id = 'Kubernetes.kubectl'; Weight = 6; Reason = 'Container orchestration CLI' }
            )
        }
        'Frontend Developer' = @{
            Keywords = @('frontend', 'web', 'react', 'vue', 'angular', 'css', 'html', 'javascript', 'typescript', 'ui', 'ux', 'svelte', 'nextjs')
            Packages = @(
                @{ Id = 'Microsoft.VisualStudioCode'; Weight = 10; Reason = 'Editor with best JS/TS support' }
                @{ Id = 'OpenJS.NodeJS.LTS'; Weight = 10; Reason = 'JavaScript runtime and npm ecosystem' }
                @{ Id = 'Git.Git'; Weight = 9; Reason = 'Version control' }
                @{ Id = 'Google.Chrome'; Weight = 8; Reason = 'Primary dev browser with DevTools' }
                @{ Id = 'Mozilla.Firefox.DeveloperEdition'; Weight = 7; Reason = 'Secondary testing browser' }
                @{ Id = 'Figma.Figma'; Weight = 7; Reason = 'Design-to-code collaboration' }
                @{ Id = 'Yarn.Yarn'; Weight = 6; Reason = 'Alternative package manager' }
                @{ Id = 'Microsoft.Edge.Dev'; Weight = 5; Reason = 'Chromium testing channel' }
                @{ Id = 'nginxinc.nginx'; Weight = 5; Reason = 'Local reverse proxy for dev' }
            )
        }
        'Data Scientist' = @{
            Keywords = @('data', 'science', 'ml', 'machine learning', 'ai', 'analytics', 'jupyter', 'pandas', 'numpy', 'tensorflow', 'pytorch', 'statistics', 'visualization')
            Packages = @(
                @{ Id = 'Python.Python.3.13'; Weight = 10; Reason = 'Primary data science runtime' }
                @{ Id = 'Anaconda.Anaconda3'; Weight = 9; Reason = 'Scientific computing distribution' }
                @{ Id = 'Microsoft.VisualStudioCode'; Weight = 8; Reason = 'Editor with Jupyter integration' }
                @{ Id = 'Git.Git'; Weight = 8; Reason = 'Experiment versioning' }
                @{ Id = 'Docker.DockerDesktop'; Weight = 7; Reason = 'Reproducible environments' }
                @{ Id = 'PostgreSQL.PostgreSQL.17'; Weight = 7; Reason = 'Data warehouse' }
                @{ Id = 'RProject.R'; Weight = 8; Reason = 'Statistical computing language' }
                @{ Id = 'Posit.RStudio'; Weight = 7; Reason = 'R IDE and notebooks' }
                @{ Id = 'JetBrains.PyCharm.Community'; Weight = 7; Reason = 'Python IDE for ML projects' }
                @{ Id = 'Microsoft.PowerBI'; Weight = 6; Reason = 'Business intelligence dashboards' }
                @{ Id = 'Tableau.Desktop'; Weight = 5; Reason = 'Advanced data visualization' }
                @{ Id = 'Julialang.Julia'; Weight = 6; Reason = 'High-performance numerical computing' }
            )
        }
        'DevOps Engineer' = @{
            Keywords = @('devops', 'infrastructure', 'ci/cd', 'pipeline', 'terraform', 'ansible', 'kubernetes', 'cloud', 'aws', 'azure', 'monitoring', 'sre', 'platform')
            Packages = @(
                @{ Id = 'Git.Git'; Weight = 10; Reason = 'Infrastructure-as-code versioning' }
                @{ Id = 'Hashicorp.Terraform'; Weight = 9; Reason = 'Infrastructure provisioning' }
                @{ Id = 'Kubernetes.kubectl'; Weight = 9; Reason = 'Cluster management' }
                @{ Id = 'Docker.DockerDesktop'; Weight = 9; Reason = 'Container development' }
                @{ Id = 'Microsoft.AzureCLI'; Weight = 8; Reason = 'Azure cloud management' }
                @{ Id = 'Amazon.AWSCLI'; Weight = 8; Reason = 'AWS cloud management' }
                @{ Id = 'Helm.Helm'; Weight = 7; Reason = 'Kubernetes package manager' }
                @{ Id = 'GrafanaLabs.Grafana.OSS'; Weight = 7; Reason = 'Monitoring dashboards' }
                @{ Id = 'Hashicorp.Vault'; Weight = 6; Reason = 'Secrets management' }
                @{ Id = 'Microsoft.VisualStudioCode'; Weight = 7; Reason = 'IaC editing' }
                @{ Id = 'PuTTY.PuTTY'; Weight = 5; Reason = 'SSH access to servers' }
                @{ Id = 'WiresharkFoundation.Wireshark'; Weight = 6; Reason = 'Network troubleshooting' }
                @{ Id = 'Python.Python.3.13'; Weight = 7; Reason = 'Automation scripting' }
            )
        }
        'Gamer' = @{
            Keywords = @('gaming', 'gamer', 'game', 'steam', 'twitch', 'discord', 'rgb', 'fps', 'esports', 'streaming', 'obs')
            Packages = @(
                @{ Id = 'Valve.Steam'; Weight = 10; Reason = 'Primary game library' }
                @{ Id = 'Discord.Discord'; Weight = 9; Reason = 'Voice chat and communities' }
                @{ Id = 'OBSProject.OBSStudio'; Weight = 8; Reason = 'Game streaming and recording' }
                @{ Id = 'EpicGames.EpicGamesLauncher'; Weight = 7; Reason = 'Epic game library' }
                @{ Id = 'Elgato.StreamDeck'; Weight = 6; Reason = 'Stream control deck software' }
                @{ Id = 'Mozilla.Firefox'; Weight = 5; Reason = 'Gaming wikis and guides' }
                @{ Id = 'Spotify.Spotify'; Weight = 6; Reason = 'Gaming music' }
                @{ Id = 'GOG.Galaxy'; Weight = 6; Reason = 'DRM-free game library' }
                @{ Id = 'Ubisoft.Connect'; Weight = 5; Reason = 'Ubisoft game library' }
            )
        }
        'Game Developer' = @{
            Keywords = @('game dev', 'game development', 'unity', 'unreal', 'godot', 'gamedev', 'indie', 'shader', '3d', 'blender', 'pixel art')
            Packages = @(
                @{ Id = 'Unity.UnityHub'; Weight = 10; Reason = 'Installs and manages Unity editor versions' }
                @{ Id = 'GodotEngine.GodotEngine'; Weight = 9; Reason = 'Open-source game engine' }
                @{ Id = 'BlenderFoundation.Blender'; Weight = 9; Reason = '3D modeling and animation' }
                @{ Id = 'Microsoft.VisualStudioCode'; Weight = 8; Reason = 'Scripting and shader editing' }
                @{ Id = 'Git.Git'; Weight = 8; Reason = 'Asset and code versioning' }
                @{ Id = 'GIMP.GIMP'; Weight = 7; Reason = '2D art and texture editing' }
                @{ Id = 'Inkscape.Inkscape'; Weight = 6; Reason = 'Vector art for UI/sprites' }
                @{ Id = 'Audacity.Audacity'; Weight = 6; Reason = 'Audio editing for SFX' }
                @{ Id = 'Microsoft.DotNet.SDK.10'; Weight = 7; Reason = 'C# development for Unity' }
                @{ Id = 'Microsoft.VisualStudio.Community'; Weight = 7; Reason = 'Full C++ IDE for Unreal' }
            )
        }
        'Security Researcher' = @{
            Keywords = @('security', 'pentest', 'hacking', 'ctf', 'forensics', 'malware', 'reverse engineering', 'vulnerability', 'red team', 'blue team', 'soc')
            Packages = @(
                @{ Id = 'WiresharkFoundation.Wireshark'; Weight = 10; Reason = 'Network packet analysis' }
                @{ Id = 'Python.Python.3.13'; Weight = 9; Reason = 'Exploit scripting and automation' }
                @{ Id = 'Git.Git'; Weight = 8; Reason = 'Tool and research versioning' }
                @{ Id = 'Insecure.Nmap'; Weight = 9; Reason = 'Network scanning and enumeration' }
                @{ Id = 'GnuPG.GnuPG'; Weight = 7; Reason = 'Encryption and signing' }
                @{ Id = 'KeePassXCTeam.KeePassXC'; Weight = 7; Reason = 'Credential management' }
                @{ Id = 'Microsoft.VisualStudioCode'; Weight = 7; Reason = 'Code analysis and scripting' }
                @{ Id = 'Docker.DockerDesktop'; Weight = 7; Reason = 'Isolated malware analysis labs' }
                @{ Id = 'Oracle.VirtualBox'; Weight = 8; Reason = 'Vulnerable VM labs' }
                @{ Id = 'Hex-Rays.IDA.Free'; Weight = 8; Reason = 'Binary reverse engineering' }
                @{ Id = 'x64dbg.x64dbg'; Weight = 8; Reason = 'Open-source debugger for reverse engineering' }
                @{ Id = 'TorProject.TorBrowser'; Weight = 6; Reason = 'Anonymous research browsing' }
            )
        }
        'Designer' = @{
            Keywords = @('design', 'graphic', 'ui', 'ux', 'figma', 'photoshop', 'illustrator', 'creative', 'photo', 'video', 'editing', 'adobe')
            Packages = @(
                @{ Id = 'Figma.Figma'; Weight = 10; Reason = 'UI/UX design and prototyping' }
                @{ Id = 'GIMP.GIMP'; Weight = 8; Reason = 'Raster image editing' }
                @{ Id = 'Inkscape.Inkscape'; Weight = 8; Reason = 'Vector graphics editor' }
                @{ Id = 'BlenderFoundation.Blender'; Weight = 7; Reason = '3D design and rendering' }
                @{ Id = 'KDE.Kdenlive'; Weight = 7; Reason = 'Open-source video editing' }
                @{ Id = 'Audacity.Audacity'; Weight = 6; Reason = 'Audio editing' }
                @{ Id = 'OBSProject.OBSStudio'; Weight = 6; Reason = 'Screen recording for portfolios' }
                @{ Id = 'Mozilla.Firefox'; Weight = 5; Reason = 'Design inspiration browsing' }
                @{ Id = 'Google.Chrome'; Weight = 5; Reason = 'Web design testing' }
                @{ Id = 'Git.Git'; Weight = 6; Reason = 'Design asset versioning' }
                @{ Id = 'VideoLAN.VLC'; Weight = 5; Reason = 'Media format preview' }
            )
        }
        'Productivity' = @{
            Keywords = @('productivity', 'office', 'notes', 'organization', 'writing', 'email', 'calendar', 'meeting', 'remote', 'work')
            Packages = @(
                @{ Id = 'Microsoft.Office'; Weight = 9; Reason = 'Document and spreadsheet suite' }
                @{ Id = 'Microsoft.Teams'; Weight = 8; Reason = 'Meetings and collaboration' }
                @{ Id = 'SlackTechnologies.Slack'; Weight = 7; Reason = 'Team communication' }
                @{ Id = 'Notion.Notion'; Weight = 8; Reason = 'Notes and project management' }
                @{ Id = 'Obsidian.Obsidian'; Weight = 8; Reason = 'Knowledge management (local-first)' }
                @{ Id = 'Doist.Todoist'; Weight = 7; Reason = 'Task management' }
                @{ Id = 'Zoom.Zoom'; Weight = 7; Reason = 'Video conferencing' }
                @{ Id = 'Mozilla.Firefox'; Weight = 6; Reason = 'Research browser' }
                @{ Id = '7zip.7zip'; Weight = 6; Reason = 'File compression utility' }
                @{ Id = 'ShareX.ShareX'; Weight = 7; Reason = 'Screenshots and screen recording' }
                @{ Id = 'AutoHotkey.AutoHotkey'; Weight = 6; Reason = 'Workflow automation hotkeys' }
            )
        }
        'Student' = @{
            Keywords = @('student', 'school', 'university', 'college', 'study', 'learning', 'course', 'homework', 'research', 'academic')
            Packages = @(
                @{ Id = 'Microsoft.VisualStudioCode'; Weight = 9; Reason = 'Free code editor for CS courses' }
                @{ Id = 'Git.Git'; Weight = 9; Reason = 'Assignment version control' }
                @{ Id = 'Python.Python.3.13'; Weight = 8; Reason = 'Intro programming language' }
                @{ Id = 'Obsidian.Obsidian'; Weight = 8; Reason = 'Study notes and knowledge base' }
                @{ Id = 'DigitalScholar.Zotero'; Weight = 8; Reason = 'Research paper management' }
                @{ Id = 'Mozilla.Firefox'; Weight = 7; Reason = 'Research browser with containers' }
                @{ Id = 'VideoLAN.VLC'; Weight = 6; Reason = 'Lecture video playback' }
                @{ Id = 'Audacity.Audacity'; Weight = 5; Reason = 'Audio note recording' }
                @{ Id = 'GIMP.GIMP'; Weight = 5; Reason = 'Free image editing for projects' }
                @{ Id = '7zip.7zip'; Weight = 6; Reason = 'Extract course materials' }
                @{ Id = 'Discord.Discord'; Weight = 6; Reason = 'Study group communication' }
            )
        }
    }

    # --- CO-OCCURRENCE MATRIX (commonly paired packages) ---
    $coOccurrence = @{
        'Git.Git' = @('Microsoft.VisualStudioCode', 'Docker.DockerDesktop', 'OpenJS.NodeJS.LTS', 'Python.Python.3.13')
        'Docker.DockerDesktop' = @('Kubernetes.kubectl', 'Hashicorp.Terraform', 'Microsoft.VisualStudioCode', 'Git.Git')
        'Microsoft.VisualStudioCode' = @('Git.Git', 'Python.Python.3.13', 'OpenJS.NodeJS.LTS', 'Docker.DockerDesktop')
        'Python.Python.3.13' = @('Microsoft.VisualStudioCode', 'Anaconda.Anaconda3', 'Git.Git', 'JetBrains.PyCharm.Community')
        'OpenJS.NodeJS.LTS' = @('Microsoft.VisualStudioCode', 'Git.Git', 'Yarn.Yarn', 'Docker.DockerDesktop')
        'Valve.Steam' = @('Discord.Discord', 'OBSProject.OBSStudio')
        'WiresharkFoundation.Wireshark' = @('Insecure.Nmap', 'Python.Python.3.13', 'Oracle.VirtualBox')
        'BlenderFoundation.Blender' = @('GIMP.GIMP', 'Inkscape.Inkscape', 'KDE.Kdenlive')
        'PostgreSQL.PostgreSQL.17' = @('Redis.Redis', 'JetBrains.DataGrip', 'Docker.DockerDesktop')
    }

    # --- GET INSTALLED PACKAGES ---
    $installedIds = @()
    if ($ExcludeInstalled -or $ClonePersonality) {
        try {
            $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
            $installedIds = @($installed | ForEach-Object { $_.Id })
        } catch {
            Write-Verbose "Could not enumerate installed packages: $_"
        }
    }

    # --- SCORING ENGINE ---
    $scores = @{}  # PackageId -> @{ Score; Reasons; Source }

    function Add-Score {
        param([string]$Id, [double]$Weight, [string]$Reason, [string]$Source)
        if (-not $scores.ContainsKey($Id)) {
            $scores[$Id] = @{ Score = 0; Reasons = @(); Sources = @() }
        }
        $scores[$Id].Score += $Weight
        $scores[$Id].Reasons += $Reason
        $scores[$Id].Sources += $Source
    }

    if ($ClonePersonality) {
        # Analyze installed packages for archetype matching
        Write-Host "`n  Analyzing $($installedIds.Count) installed packages..." -ForegroundColor Cyan

        # Score each archetype by how many of its packages you already have
        $archetypeScores = @{}
        foreach ($arch in $archetypes.GetEnumerator()) {
            $matchCount = ($arch.Value.Packages | Where-Object { $_.Id -in $installedIds }).Count
            $totalPkgs = $arch.Value.Packages.Count
            $archetypeScores[$arch.Key] = $matchCount / [Math]::Max($totalPkgs, 1)
        }

        # Top matching archetypes
        $topArchetypes = $archetypeScores.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3
        Write-Host "  Detected personality: " -NoNewline -ForegroundColor DarkGray
        Write-Host ($topArchetypes | ForEach-Object { "$($_.Key) ($([Math]::Round($_.Value * 100))%)" }) -ForegroundColor Yellow -Separator ", "

        # Recommend missing packages from top archetypes
        foreach ($arch in $topArchetypes) {
            $archetype = $archetypes[$arch.Key]
            foreach ($pkg in $archetype.Packages) {
                if ($pkg.Id -notin $installedIds) {
                    $adjustedWeight = $pkg.Weight * $arch.Value  # Scale by archetype match
                    Add-Score -Id $pkg.Id -Weight $adjustedWeight -Reason "$($pkg.Reason) [$($arch.Key)]" -Source 'archetype'
                }
            }
        }

        # Co-occurrence recommendations
        foreach ($instId in $installedIds) {
            if ($coOccurrence.ContainsKey($instId)) {
                foreach ($paired in $coOccurrence[$instId]) {
                    if ($paired -notin $installedIds) {
                        Add-Score -Id $paired -Weight 4 -Reason "Commonly paired with $instId" -Source 'co-occurrence'
                    }
                }
            }
        }
    }
    else {
        # Persona-based matching
        $personaLower = $Persona.ToLower()
        $matchedArchetypes = @()

        foreach ($arch in $archetypes.GetEnumerator()) {
            $keywordHits = ($arch.Value.Keywords | Where-Object { $personaLower -match [regex]::Escape($_) }).Count
            if ($keywordHits -gt 0) {
                $matchedArchetypes += @{ Name = $arch.Key; Relevance = $keywordHits / $arch.Value.Keywords.Count; Data = $arch.Value }
            }
        }

        if ($matchedArchetypes.Count -eq 0) {
            # Fuzzy fallback: check for partial matches
            foreach ($arch in $archetypes.GetEnumerator()) {
                $nameWords = $arch.Key.ToLower().Split(' ')
                $personaWords = $personaLower.Split(' ')
                $overlap = ($nameWords | Where-Object { $_ -in $personaWords }).Count
                if ($overlap -gt 0) {
                    $matchedArchetypes += @{ Name = $arch.Key; Relevance = $overlap / $nameWords.Count; Data = $arch.Value }
                }
            }
        }

        if ($matchedArchetypes.Count -eq 0) {
            Write-Host "`n  No exact archetype match for '$Persona'." -ForegroundColor Yellow
            Write-Host "  Available personas: $($archetypes.Keys -join ', ')" -ForegroundColor DarkGray
            Write-Host "  Try a more specific description or use -ClonePersonality.`n" -ForegroundColor DarkGray
            return
        }

        # Sort by relevance and show matches
        $matchedArchetypes = $matchedArchetypes | Sort-Object { $_.Relevance } -Descending
        Write-Host "`n  Matched archetypes: " -NoNewline -ForegroundColor DarkGray
        Write-Host ($matchedArchetypes | ForEach-Object { "$($_.Name) ($([Math]::Round($_.Relevance * 100))%)" }) -ForegroundColor Cyan -Separator ", "

        # Score packages from matched archetypes
        foreach ($match in $matchedArchetypes) {
            foreach ($pkg in $match.Data.Packages) {
                $adjustedWeight = $pkg.Weight * $match.Relevance
                Add-Score -Id $pkg.Id -Weight $adjustedWeight -Reason "$($pkg.Reason) [$($match.Name)]" -Source 'persona'
            }
        }

        # Boost with co-occurrence from installed packages
        foreach ($instId in $installedIds) {
            if ($coOccurrence.ContainsKey($instId)) {
                foreach ($paired in $coOccurrence[$instId]) {
                    if ($scores.ContainsKey($paired)) {
                        $scores[$paired].Score += 2  # Boost already-recommended
                    }
                }
            }
        }
    }

    # --- FILTER ---
    $candidates = $scores.GetEnumerator() | Where-Object { -not $ExcludeInstalled -or $_.Key -notin $installedIds }

    # Category filter (applied before MaxResults so the limit counts matching packages)
    if ($Category) {
        # Simple category mapping by package ID patterns
        $categoryMap = @{
            'Development' = @('Git', 'Code', 'Python', 'Node', 'DotNet', 'JetBrains', 'Rust', 'Go', 'Java')
            'DevOps' = @('Docker', 'Kubernetes', 'Terraform', 'Helm', 'Grafana', 'Vault', 'Azure', 'AWS')
            'Gaming' = @('Steam', 'Discord', 'Epic', 'OBS', 'GOG', 'Ubisoft')
            'Design' = @('Figma', 'GIMP', 'Inkscape', 'Blender', 'Kdenlive', 'Audacity')
            'Security' = @('Wireshark', 'Nmap', 'x64dbg', 'IDA', 'KeePass', 'GnuPG', 'Tor', 'VirtualBox')
            'Productivity' = @('Office', 'Teams', 'Slack', 'Notion', 'Obsidian', 'Zoom', 'Todoist', 'ShareX')
            'Media' = @('VLC', 'OBS', 'Audacity', 'Kdenlive', 'Spotify', 'GIMP')
            'Utilities' = @('7zip', 'AutoHotkey', 'PuTTY', 'ShareX')
        }
        $patterns = $categoryMap[$Category]
        if ($patterns) {
            $candidates = $candidates | Where-Object {
                $id = $_.Key
                @($patterns | Where-Object { $id -match [regex]::Escape($_) }).Count -gt 0
            }
        }
    }

    $recommendations = @($candidates | Sort-Object { $_.Value.Score } -Descending | Select-Object -First $MaxResults)
    # --- OUTPUT ---
    if ($recommendations.Count -eq 0) {
        Write-Host "`n  No recommendations found$(if ($Category) { " in $Category" }). Everything suggested is already installed.`n" -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "  ║           WingetBatch Recommendations                   ║" -ForegroundColor Magenta
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""

    $i = 0
    foreach ($rec in $recommendations) {
        $i++
        $scoreBar = '#' * [Math]::Min([Math]::Round($rec.Value.Score), 20)
        $scoreBar = $scoreBar.PadRight(20, '.')
        Write-Host "  $($i.ToString().PadLeft(2)). " -NoNewline -ForegroundColor White
        Write-Host $rec.Key -NoNewline -ForegroundColor Cyan
        Write-Host " [$scoreBar] " -NoNewline -ForegroundColor DarkGray
        Write-Host "$([Math]::Round($rec.Value.Score, 1))pts" -ForegroundColor Yellow

        if ($Explain) {
            foreach ($reason in ($rec.Value.Reasons | Select-Object -Unique)) {
                Write-Host "      → $reason" -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ""
    Write-Host "  $($recommendations.Count) recommendations | Sources: $(($recommendations | ForEach-Object { $_.Value.Sources } | Select-Object -Unique) -join ', ')" -ForegroundColor DarkGray
    Write-Host ""

    # --- INTERACTIVE INSTALL ---
    if ($Install) {
        $choices = @($recommendations | ForEach-Object { $_.Key })
        $selected = @()

        try {
            $selected = @(Read-SpectreMultiSelection -Choices $choices -Title "[cyan]Select packages to install[/]" -PageSize 20 -Color "Green")
        }
        catch {
            Write-Host "  Enter numbers to install (comma-separated, or 'all'): " -NoNewline -ForegroundColor Yellow
            $answer = Read-Host
            if ($answer -eq 'all') {
                $selected = $choices
            } else {
                $selected = @($answer -split '[,\s]+' | Where-Object { $_ -match '^\d+$' -and [int]$_ -ge 1 -and [int]$_ -le $choices.Count } |
                    ForEach-Object { $choices[[int]$_ - 1] } | Select-Object -Unique)
            }
        }

        if ($selected.Count -gt 0) {
            Write-Host "`n  Installing $($selected.Count) packages...`n" -ForegroundColor Green
            Invoke-WingetAutoSnapshot -Reason 'Get-WingetRecommend -Install'
            $ok = 0
            $j = 0
            foreach ($pkgId in $selected) {
                $j++
                Write-Host "  [$j/$($selected.Count)] Installing $pkgId..." -NoNewline -ForegroundColor Cyan
                $r = Invoke-WingetPackageAction -Action Install -Id $pkgId -Source 'winget' -Options @{ Mode = 'Silent' }
                if ($r.Succeeded) {
                    Write-Host " OK" -ForegroundColor Green
                    $ok++
                } else {
                    Write-Host " FAILED ($($r.Message))" -ForegroundColor Red
                }
            }
            Write-Host "`n  Done: $ok of $($selected.Count) installed.`n" -ForegroundColor $(if ($ok -eq $selected.Count) { 'Green' } else { 'Yellow' })
        }
    }
    # Return structured data for pipeline use
    $recommendations | ForEach-Object {
        [PSCustomObject]@{
            PackageId = $_.Key
            Score = [Math]::Round($_.Value.Score, 2)
            Reasons = ($_.Value.Reasons | Select-Object -Unique)
            Sources = ($_.Value.Sources | Select-Object -Unique)
        }
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

    .PARAMETER ListOnly
        Return the available updates as objects without prompting or installing.
        Use this from scripts, scheduled tasks and the REST server.

    .EXAMPLE
        Get-WingetUpdates
        Shows available updates and allows you to select which to install.

    .EXAMPLE
        Get-WingetUpdates -Force
        Forces a fresh check for updates.

    .EXAMPLE
        Get-WingetUpdates -ListOnly | Where-Object Source -eq 'winget'
        Lists pending updates as objects for further processing.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$ListOnly,

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

    if (-not $ListOnly) {
        Write-Host "Checking for winget package updates..." -ForegroundColor Cyan
    }

    # Check cache first
    $configDir = Get-WingetBatchConfigDir
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    $cacheFile = Join-Path $configDir "update_cache.json"
    $useCache = $false
    $updatesAvailable = [System.Collections.Generic.List[PSCustomObject]]::new()

    if (-not $Force -and (Test-Path $cacheFile)) {
        try {
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
            $cacheAge = ((Get-Date) - [DateTime]::Parse($cache.LastChecked)).TotalMinutes

            # Only trust caches written in the current format (they carry AvailableVersion)
            if ($cacheAge -lt 30 -and @($cache.Updates).Count -gt 0 -and $null -ne @($cache.Updates)[0].AvailableVersion) {
                $useCache = $true
                foreach ($u in $cache.Updates) {
                    $updatesAvailable.Add([PSCustomObject]@{
                        Id = $u.Id; Name = $u.Name; InstalledVersion = $u.InstalledVersion
                        AvailableVersion = $u.AvailableVersion; Source = $u.Source
                    })
                }
                if (-not $ListOnly) {
                    Write-Host "Using cached results (checked $([Math]::Round($cacheAge, 0)) minutes ago, -Force to refresh)" -ForegroundColor DarkGray
                }
            }
        }
        catch {
            # Cache is corrupt, ignore
        }
    }

    if (-not $useCache) {
        if (-not $ListOnly) {
            Write-Host "Querying installed packages via COM API..." -ForegroundColor DarkGray
        }
        $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue

        foreach ($pkg in $installed) {
            if ($pkg.IsUpdateAvailable) {
                $updatesAvailable.Add([PSCustomObject]@{
                    Id               = $pkg.Id
                    Name             = $pkg.Name
                    InstalledVersion = $pkg.InstalledVersion
                    AvailableVersion = @($pkg.AvailableVersions)[0]
                    Source           = $pkg.Source
                })
            }
        }

        # Save to cache (also read by the profile update notification)
        try {
            $cacheData = @{
                LastChecked = (Get-Date).ToString('o')
                UpdateCount = $updatesAvailable.Count
                Updates     = @($updatesAvailable)
            } | ConvertTo-Json -Depth 5
            [System.IO.File]::WriteAllText($cacheFile, $cacheData, [System.Text.Encoding]::UTF8)
        }
        catch {
            Write-Verbose "Failed to save update cache: $_"
        }
    }

    if ($ListOnly) {
        return $updatesAvailable.ToArray()
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
        $defaultPath = "C:\temp\WingetBatch_Updates_$timestamp.html"
        $exportPath = Read-Host "Enter path for HTML report [Default: $defaultPath]"
        if (-not $exportPath) { $exportPath = $defaultPath }
        if (-not $exportPath.EndsWith(".html")) { $exportPath += ".html" }

        try {
            Export-WingetHtmlReport -Data $updatesAvailable.ToArray() -ReportTitle "Updates" -FilePath $exportPath
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
        $selectedPackages = @($updatesAvailable)
    }
    else {
        try {
            $displayToPkg = @{}
            $displayLines = foreach ($u in $updatesAvailable) {
                $name = ConvertTo-SpectreEscaped $u.Name
                $id = ConvertTo-SpectreEscaped $u.Id
                $from = ConvertTo-SpectreEscaped ([string]$u.InstalledVersion)
                $to = ConvertTo-SpectreEscaped ([string]$u.AvailableVersion)
                $display = "$name ($id) [grey]$from[/] -> [green]$to[/]"
                if ($u.Source -and $u.Source -ne 'winget') { $display += " [magenta]$(ConvertTo-SpectreEscaped $u.Source)[/]" }
                $displayToPkg[$display] = $u
                $display
            }

            $selectedLines = Read-SpectreMultiSelection -Title "[cyan]Select packages to update (Space to toggle, Enter to confirm)[/]" `
                -Choices $displayLines `
                -PageSize 20 `
                -Color "Green"

            if (@($selectedLines).Count -eq 0) {
                Write-Host "No packages selected." -ForegroundColor Yellow
                return
            }

            $selectedPackages = @($selectedLines | ForEach-Object { $displayToPkg[$_] })
        }
        catch {
            Write-Warning "Interactive selection error: $_"
            Write-Host "Packages with updates available:" -ForegroundColor Cyan
            $updatesAvailable | ForEach-Object {
                Write-Host "  - $($_.Id) ($($_.InstalledVersion) -> $($_.AvailableVersion))" -ForegroundColor White
            }
            Write-Host ""
            Write-Host "To update all: " -ForegroundColor Cyan -NoNewline
            Write-Host "Get-WingetUpdates -IWantToLiterallyUpdateAllFuckingResults" -ForegroundColor Yellow
            return
        }
    }

    Write-Host ""
    Write-Host "Updating " -ForegroundColor Cyan -NoNewline
    Write-Host "$($selectedPackages.Count)" -ForegroundColor White -NoNewline
    Write-Host " package(s)..." -ForegroundColor Cyan
    Write-Host ""

    $successCount = 0
    $failCount = 0
    $rebootNeeded = $false
    $failures = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Default to silent updates unless the caller chose a mode
    $installOptions = @{
        Mode = $(if ($Mode) { $Mode } else { 'Silent' })
        Scope = $Scope; Architecture = $Architecture; Override = $Override; Location = $Location
        Force = [bool]$ForceInstall; SkipDependencies = [bool]$SkipDependencies; AllowHashMismatch = [bool]$AllowHashMismatch
    }

    Invoke-WingetAutoSnapshot -Reason 'Get-WingetUpdates'

    $i = 0
    foreach ($pkg in $selectedPackages) {
        $i++
        Write-Host ">>> [$i/$($selectedPackages.Count)] Updating: " -ForegroundColor Magenta -NoNewline
        Write-Host "$($pkg.Id) " -ForegroundColor White -NoNewline
        Write-Host "$($pkg.InstalledVersion) -> $($pkg.AvailableVersion)" -ForegroundColor DarkGray

        $result = Invoke-WingetPackageAction -Action Update -Id $pkg.Id -Source $pkg.Source -Options $installOptions

        if ($result.Succeeded) {
            Write-Host "[OK] Successfully updated " -ForegroundColor Green -NoNewline
            Write-Host $pkg.Id -ForegroundColor White
            if ($result.RebootRequired) { $rebootNeeded = $true }
            $successCount++
        }
        else {
            Write-Host "[FAIL] Failed to update " -ForegroundColor Red -NoNewline
            Write-Host $pkg.Id -ForegroundColor White -NoNewline
            Write-Host " ($($result.Message))" -ForegroundColor Red
            $failures.Add($result)
            $failCount++
        }
        Write-Host ""
    }

    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "Update Complete" -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "Updated: " -ForegroundColor Green -NoNewline
    Write-Host $successCount -ForegroundColor White -NoNewline
    Write-Host " | Failed: " -ForegroundColor Red -NoNewline
    Write-Host $failCount -ForegroundColor White
    foreach ($f in $failures) {
        Write-Host "  - $($f.Id): $($f.Message)" -ForegroundColor DarkGray
    }
    if ($rebootNeeded) {
        Write-Host "A restart is required to finish at least one update." -ForegroundColor Yellow
    }

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

        # Check source index freshness
        $dbAge = Get-WingetSourceIndexAge
        if ($null -ne $dbAge -and $dbAge.TotalDays -gt 7) {
            Write-Host ""
            Write-Host " [!] Your Winget local index is $([Math]::Floor($dbAge.TotalDays)) days old." -ForegroundColor Yellow
            Write-Host "     Searches may return stale results." -ForegroundColor Gray
            Write-Host "     Recommendation: Run '" -ForegroundColor Gray -NoNewline
            Write-Host "winget source update" -ForegroundColor White -NoNewline
            Write-Host "' to refresh it." -ForegroundColor Gray
            Write-Host ""
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
                    # -Id means this exact package, not every ID containing it (VideoLAN.VLC must not pull in VideoLAN.VLC.Nightly)
                    $comArgs = @{ Id = $i; MatchOption = 'EqualsCaseInsensitive'; Count = $LimitResult; ErrorAction = 'Stop' }
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
            Write-Warning "No packages found matching '$(@($Query) + @($Id) -join ", ")'"
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

        Write-Host ("`n" + ("=" * 60)) -ForegroundColor Cyan
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

                $spectreList | Format-SpectreTable -AllowMarkup | Out-Host
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
        $totalToInstall = @($uniquePackagesToInstall).Count
        $currentIdx = 0
        $rebootNeeded = $false
        $failures = [System.Collections.Generic.List[PSCustomObject]]::new()

        $installOptions = @{
            Mode = $Mode; Scope = $Scope; Architecture = $Architecture
            Override = $Override; Location = $Location
            Force = [bool]$Force; SkipDependencies = [bool]$SkipDependencies; AllowHashMismatch = [bool]$AllowHashMismatch
        }

        if ($totalToInstall -gt 0) { Invoke-WingetAutoSnapshot -Reason 'Install-WingetAll' }

        foreach ($packageId in $uniquePackagesToInstall) {
            $currentIdx++
            $pkgInfo = $pkgMap[$packageId]
            $pkgName = if ($pkgInfo) { $pkgInfo.Name } else { $packageId }
            $pkgVersion = if ($pkgInfo -and $pkgInfo.Version -ne "Unknown") { "v$($pkgInfo.Version)" } else { "" }
            $pkgSource = if ($pkgInfo -and $pkgInfo.Source -ne "Unknown") { $pkgInfo.Source } else { $Source }

            Write-Host "`n>>> [$currentIdx/$totalToInstall] Installing: " -ForegroundColor Magenta -NoNewline
            Write-Host "$pkgName ($packageId)" -ForegroundColor White -NoNewline
            if ($pkgVersion) { Write-Host " $pkgVersion" -ForegroundColor Green -NoNewline }
            if ($pkgSource) {
                $sColor = if ($pkgSource -match 'msstore') { "Magenta" } else { "Cyan" }
                Write-Host " from $pkgSource" -ForegroundColor $sColor
            } else { Write-Host "" }

            # Pin the source the package was found in so an ID that exists in both
            # winget and msstore installs the one the user picked
            $result = Invoke-WingetPackageAction -Action Install -Id $packageId -Source $pkgSource -Options $installOptions

            if ($result.Succeeded) {
                Write-Host "    [OK] " -ForegroundColor Green -NoNewline
                Write-Host "Successfully installed $packageId" -ForegroundColor White
                if ($result.RebootRequired) { $rebootNeeded = $true }
                $successCount++
            }
            else {
                Write-Host "    [FAIL] " -ForegroundColor Red -NoNewline
                Write-Host "$packageId - $($result.Message)" -ForegroundColor Red
                $failures.Add($result)
                $failCount++
            }
        }

        Write-Host ("`n" + ("=" * 60)) -ForegroundColor Green
        Write-Host "Installation Complete" -ForegroundColor Green
        Write-Host ("=" * 60) -ForegroundColor Green
        Write-Host "Success: " -ForegroundColor Green -NoNewline
        Write-Host $successCount -ForegroundColor White -NoNewline
        Write-Host " | Failed: " -ForegroundColor Red -NoNewline
        Write-Host $failCount -ForegroundColor White
        foreach ($f in $failures) {
            Write-Host "  - $($f.Id): $($f.Message)" -ForegroundColor DarkGray
        }
        if ($rebootNeeded) {
            Write-Host "A restart is required to finish at least one installation." -ForegroundColor Yellow
        }
    }
}


# EndRegion

# Region: Public/Install-WingetProfile.ps1
function Install-WingetProfile {
    <#
    .SYNOPSIS
        Install packages from shareable community setup profiles.

    .DESCRIPTION
        Loads a curated package profile (JSON) from a URL, GitHub gist, local file,
        or the built-in profile library, then installs all listed packages.

        Profiles are the ecosystem builder: anyone can publish a "Gamer Setup",
        "DevOps Toolkit", or "Data Science Stack" as a simple JSON file and share
        it with a URL. One command replicates an entire workflow.

    .PARAMETER Url
        URL to a profile JSON file (GitHub raw, gist, any HTTP).

    .PARAMETER Path
        Path to a local profile JSON file.

    .PARAMETER Name
        Name of a built-in profile: Developer, Gamer, DataScience, DevOps,
        Designer, Security, Productivity, Minimal.

    .PARAMETER List
        Show available built-in profiles and their package counts.

    .PARAMETER WhatIf
        Show what would be installed without actually installing.

    .PARAMETER SkipInstalled
        Skip packages already installed. Default: true.

    .PARAMETER Force
        Install without asking for confirmation.

    .PARAMETER Export
        Export your current installed packages as a shareable profile.

    .PARAMETER ExportPath
        Path for exported profile. Default: .\my-profile.json

    .EXAMPLE
        Install-WingetProfile -Name Developer
        Installs the built-in Developer profile.

    .EXAMPLE
        Install-WingetProfile -Url "https://raw.githubusercontent.com/user/repo/main/profile.json"
        Installs from a community-shared profile URL.

    .EXAMPLE
        Install-WingetProfile -Export -ExportPath ".\my-setup.json"
        Exports your installed packages as a shareable profile.

    .EXAMPLE
        Install-WingetProfile -List
        Shows all built-in profiles.

    .NOTES
        Author: Matthew Bubb
        Profile format: { "name": "...", "packages": ["Id1", "Id2", ...] }
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(ParameterSetName = 'ByUrl', Mandatory)]
        [string]$Url,

        [Parameter(ParameterSetName = 'ByPath', Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$Path,

        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [ValidateSet('Developer', 'Gamer', 'DataScience', 'DevOps', 'Designer', 'Security', 'Productivity', 'Minimal')]
        [string]$Name = 'Developer',

        [Parameter(ParameterSetName = 'List', Mandatory)]
        [switch]$List,

        [switch]$WhatIf,

        [bool]$SkipInstalled = $true,

        [switch]$Force,

        [Parameter(ParameterSetName = 'Export', Mandatory)]
        [switch]$Export,

        [Parameter(ParameterSetName = 'Export')]
        [string]$ExportPath = ".\my-profile.json"
    )

    # --- BUILT-IN PROFILE LIBRARY ---
    $builtInProfiles = @{
        'Developer' = @{
            Name = "Full-Stack Developer"
            Description = "Everything a modern software developer needs"
            Author = "WingetBatch"
            Packages = @(
                'Git.Git', 'Microsoft.VisualStudioCode', 'OpenJS.NodeJS.LTS',
                'Python.Python.3.13', 'Docker.DockerDesktop', 'Microsoft.DotNet.SDK.10',
                'GoLang.Go', 'PostgreSQL.PostgreSQL.17', 'Redis.Redis',
                'Postman.Postman', 'Microsoft.WindowsTerminal', '7zip.7zip'
            )
        }
        'Gamer' = @{
            Name = "Gaming Setup"
            Description = "Game libraries, streaming, and communication"
            Author = "WingetBatch"
            Packages = @(
                'Valve.Steam', 'Discord.Discord', 'OBSProject.OBSStudio',
                'EpicGames.EpicGamesLauncher', 'GOG.Galaxy', 'Spotify.Spotify',
                'Mozilla.Firefox', 'VideoLAN.VLC', '7zip.7zip'
            )
        }
        'DataScience' = @{
            Name = "Data Science Stack"
            Description = "Python, R, Jupyter, and visualization tools"
            Author = "WingetBatch"
            Packages = @(
                'Python.Python.3.13', 'Anaconda.Anaconda3', 'RProject.R',
                'Posit.RStudio', 'Microsoft.VisualStudioCode',
                'Git.Git', 'Docker.DockerDesktop', 'PostgreSQL.PostgreSQL.17',
                'Julialang.Julia', 'Microsoft.PowerBI'
            )
        }
        'DevOps' = @{
            Name = "DevOps & Platform Engineering"
            Description = "Infrastructure, containers, cloud CLIs, monitoring"
            Author = "WingetBatch"
            Packages = @(
                'Git.Git', 'Docker.DockerDesktop', 'Kubernetes.kubectl',
                'Hashicorp.Terraform', 'Helm.Helm', 'Microsoft.AzureCLI',
                'Amazon.AWSCLI', 'Python.Python.3.13', 'Microsoft.VisualStudioCode',
                'GrafanaLabs.Grafana.OSS', 'WiresharkFoundation.Wireshark', 'PuTTY.PuTTY'
            )
        }
        'Designer' = @{
            Name = "Creative & Design"
            Description = "Image editing, vector art, 3D, and video"
            Author = "WingetBatch"
            Packages = @(
                'Figma.Figma', 'GIMP.GIMP', 'Inkscape.Inkscape',
                'BlenderFoundation.Blender', 'KDE.Kdenlive',
                'Audacity.Audacity', 'OBSProject.OBSStudio', 'VideoLAN.VLC',
                'Git.Git', '7zip.7zip'
            )
        }
        'Security' = @{
            Name = "Security Research Lab"
            Description = "Network analysis, RE tools, and lab infrastructure"
            Author = "WingetBatch"
            Packages = @(
                'WiresharkFoundation.Wireshark', 'Insecure.Nmap', 'Python.Python.3.13',
                'Oracle.VirtualBox', 'x64dbg.x64dbg', 'GnuPG.GnuPG',
                'KeePassXCTeam.KeePassXC', 'Git.Git', 'Microsoft.VisualStudioCode',
                'Docker.DockerDesktop', 'TorProject.TorBrowser'
            )
        }
        'Productivity' = @{
            Name = "Productivity & Office"
            Description = "Communication, notes, and workflow tools"
            Author = "WingetBatch"
            Packages = @(
                'Mozilla.Firefox', 'Obsidian.Obsidian', 'Microsoft.Teams',
                'SlackTechnologies.Slack', 'Zoom.Zoom', 'ShareX.ShareX',
                '7zip.7zip', 'VideoLAN.VLC', 'Notion.Notion', 'Doist.Todoist'
            )
        }
        'Minimal' = @{
            Name = "Minimal Essentials"
            Description = "Bare minimum: browser, editor, git, terminal"
            Author = "WingetBatch"
            Packages = @(
                'Git.Git', 'Microsoft.VisualStudioCode', 'Mozilla.Firefox',
                'Microsoft.WindowsTerminal', '7zip.7zip'
            )
        }
    }

    # --- LIST ---
    if ($List) {
        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "  ║           Built-in Setup Profiles                   ║" -ForegroundColor Cyan
        Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        foreach ($profileData in $builtInProfiles.GetEnumerator() | Sort-Object Key) {
            Write-Host "  $($profileData.Key.PadRight(14))" -NoNewline -ForegroundColor Yellow
            Write-Host " $($profileData.Value.Name)" -NoNewline -ForegroundColor White
            Write-Host " ($($profileData.Value.Packages.Count) pkgs)" -ForegroundColor DarkGray
            Write-Host "  $(''.PadRight(14)) $($profileData.Value.Description)" -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Host "  Usage: Install-WingetProfile -Name <ProfileName>" -ForegroundColor DarkGray
        Write-Host "  Custom: Install-WingetProfile -Url <url> | -Path <file>" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # --- EXPORT ---
    if ($Export) {
        $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
        $profileData = @{
            name = "My Setup - $env:COMPUTERNAME"
            description = "Exported from $($env:COMPUTERNAME) on $(Get-Date -Format 'yyyy-MM-dd')"
            author = $env:USERNAME
            created = (Get-Date).ToString('o')
            packages = @($installed | Where-Object { $_.Source } | ForEach-Object { $_.Id } | Sort-Object)
        }
        $profileData | ConvertTo-Json -Depth 5 | Set-Content -Path $ExportPath -Encoding UTF8
        Write-Host ""
        Write-Host "  ✓ Profile exported: $ExportPath" -ForegroundColor Green
        Write-Host "    $($profileData.packages.Count) packages | Share this file or host it on GitHub." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # --- LOAD PROFILE ---
    $profileData = $null

    if ($Url) {
        Write-Host "  Fetching profile from: $Url" -ForegroundColor DarkGray
        try {
            $raw = Invoke-RestMethod -Uri $Url -ErrorAction Stop
            $profileData = if ($raw -is [string]) { $raw | ConvertFrom-Json } else { $raw }
        } catch {
            Write-Error "Failed to fetch profile: $($_.Exception.Message)"
            return
        }
    }
    elseif ($Path) {
        # PSCustomObject property access is case-insensitive, so "packages" and "Packages" both work
        $profileData = Get-Content -Path $Path -Raw | ConvertFrom-Json
    }
    else {
        $profileData = $builtInProfiles[$Name]
    }

    if (-not $profileData -or -not $profileData.Packages) {
        Write-Error "Invalid profile: no 'packages' array found."
        return
    }

    $profileName = if ($profileData.Name) { [string]$profileData.Name } else { "Custom Profile" }
    # Entries may be plain IDs or objects with an id (e.g. a Get-WingetMachineState export)
    $packageList = @($profileData.Packages | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.id) { [string]$_.id } } | Where-Object { $_ })

    # --- Filter installed ---
    $toInstall = $packageList
    if ($SkipInstalled) {
        $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
        $installedIds = @($installed | ForEach-Object { $_.Id })
        $toInstall = @($packageList | Where-Object { $_ -notin $installedIds })
        $skippedCount = $packageList.Count - $toInstall.Count
    }

    # --- Display ---
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "  ║           $profileName" -NoNewline -ForegroundColor Magenta
    Write-Host (" ".PadRight([Math]::Max(0, 40 - $profileName.Length))) -NoNewline -ForegroundColor Magenta
    Write-Host "║" -ForegroundColor Magenta
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
    if ($profileData.Description) {
        Write-Host "  $($profileData.Description)" -ForegroundColor DarkGray
        Write-Host ""
    }
    Write-Host "  Total: $($packageList.Count) | To install: $($toInstall.Count)" -NoNewline -ForegroundColor White
    if ($SkipInstalled -and $skippedCount -gt 0) {
        Write-Host " | Already installed: $skippedCount" -NoNewline -ForegroundColor Green
    }
    Write-Host ""
    Write-Host ""

    if ($toInstall.Count -eq 0) {
        Write-Host "  ✓ All packages already installed. Nothing to do!" -ForegroundColor Green
        Write-Host ""
        return
    }

    # Show package list
    foreach ($pkg in $toInstall) {
        Write-Host "    • $pkg" -ForegroundColor Cyan
    }
    Write-Host ""

    if ($WhatIf) {
        Write-Host "  [WhatIf] Would install $($toInstall.Count) packages. Remove -WhatIf to execute." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # --- INSTALL ---
    if (-not $Force -and -not $PSCmdlet.ShouldContinue("Install $($toInstall.Count) packages from '$profileName'?", "Confirm Profile Install")) {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }

    Invoke-WingetAutoSnapshot -Reason "Install-WingetProfile $profileName"

    $success = 0; $failed = 0
    $j = 0
    foreach ($pkgId in $toInstall) {
        $j++
        Write-Host "  [$j/$($toInstall.Count)] $pkgId" -NoNewline -ForegroundColor Cyan
        Write-Host "..." -NoNewline
        $r = Invoke-WingetPackageAction -Action Install -Id $pkgId -Options @{ Mode = 'Silent' }
        if ($r.Succeeded) {
            Write-Host " OK" -ForegroundColor Green
            $success++
        } else {
            Write-Host " FAILED ($($r.Message))" -ForegroundColor Red
            $failed++
        }
    }
    Write-Host ""
    Write-Host "  Profile '$profileName' complete: $success installed, $failed failed." -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host ""
}

# EndRegion

# Region: Public/Invoke-WinGetBatch.ps1
function Invoke-WinGetBatch {
    <#
    .SYNOPSIS
        Idempotent, manifest-driven package deployments using the WinGet COM API.

    .DESCRIPTION
        Reads package target states from a pipeline or manifest file (JSON/YAML), verifies local state
        idempotency using the Microsoft.WinGet.Client COM API, then installs missing packages, updates
        outdated ones and applies version pins one at a time. Each result is checked against WinGet's
        reported status and written to a JSON report in ~/.wingetbatch/reports.

    .PARAMETER Path
        Path to a JSON or YAML state manifest file defining the target package configurations.

    .PARAMETER Packages
        Optional array of package objects passed directly or via pipeline. Each package should have an 'Id' property
        and an optional 'Version' property.

    .PARAMETER ThrottleLimit
        Deprecated and ignored (kept so existing scripts keep working). WinGet downloads each installer during its install.

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
                        Source  = $pkg.source
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
                            Source  = $pkg.Source
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
        $installedList = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
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
                        $executionQueue.Add([PSCustomObject]@{ Id = $pkgId; Version = $targetVer; Operation = 'Update'; Source = $installedPkg.Source })
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
                        $executionQueue.Add([PSCustomObject]@{ Id = $pkgId; Version = $targetVer; Operation = 'Install'; Source = $installedPkg.Source })
                    }
                }
            }
            else {
                Write-Host " [Missing]" -ForegroundColor Red
                $executionQueue.Add([PSCustomObject]@{ Id = $pkgId; Version = $targetVer; Operation = 'Install'; Source = $target.Source })
            }
        }

        if ($executionQueue.Count -eq 0) {
            Write-Host "`n[OK] System state is fully idempotent. No actions required." -ForegroundColor Green
            return
        }

        Write-Host "`nDeployment execution queue compiled: " -NoNewline -ForegroundColor Cyan
        Write-Host "$($executionQueue.Count) packages require changes." -ForegroundColor White

        if ($WhatIf) {
            Write-Host "`n[WhatIf] Would deploy:" -ForegroundColor Yellow
            foreach ($item in $executionQueue) {
                Write-Host "  -> $($item.Operation) $($item.Id) ($($item.Version))" -ForegroundColor Gray
            }
            return
        }

        if ($PSBoundParameters.ContainsKey('ThrottleLimit')) {
            Write-Verbose "-ThrottleLimit is ignored: installers are fetched by WinGet during each install."
        }

        Write-Host "`n[PHASE 2] Installing (one package at a time)..." -ForegroundColor Cyan

        Invoke-WingetAutoSnapshot -Reason 'Invoke-WinGetBatch'

        $installOptions = @{
            Mode = $(if ($Silent) { 'Silent' } else { $Mode })
            Scope = $Scope; Architecture = $Architecture; Override = $Override; Location = $Location
            Force = [bool]$Force; SkipDependencies = [bool]$SkipDependencies; AllowHashMismatch = [bool]$AllowHashMismatch
        }

        $successCount = 0
        $failCount = 0
        $rebootPending = $false
        $reportData = [System.Collections.Generic.List[PSCustomObject]]::new()
        $i = 0

        foreach ($pkg in $executionQueue) {
            $i++
            Write-Host "`n>>> [$i/$($executionQueue.Count)] $($pkg.Operation): " -NoNewline -ForegroundColor Magenta
            Write-Host $pkg.Id -NoNewline -ForegroundColor White
            if ($pkg.Version -ne 'latest') { Write-Host " v$($pkg.Version)" -ForegroundColor Green } else { Write-Host "" }

            $result = Invoke-WingetPackageAction -Action $pkg.Operation -Id $pkg.Id -Version $pkg.Version -Source $pkg.Source -Options $installOptions

            if ($result.Succeeded) {
                $successCount++
                if ($result.RebootRequired) {
                    $rebootPending = $true
                    $status = "Success (Reboot Required)"
                    Write-Host "[OK] Deployed (restart required): " -NoNewline -ForegroundColor Yellow
                }
                else {
                    $status = "Success"
                    Write-Host "[OK] Deployed " -NoNewline -ForegroundColor Green
                }
                Write-Host $pkg.Id -ForegroundColor White
            }
            else {
                $failCount++
                $status = "Failed"
                Write-Host "[FAIL] " -NoNewline -ForegroundColor Red
                Write-Host $pkg.Id -NoNewline -ForegroundColor White
                Write-Host " ($($result.Message))" -ForegroundColor Red
            }

            $reportData.Add([PSCustomObject]@{
                PackageId      = $pkg.Id
                Operation      = $pkg.Operation
                Version        = $pkg.Version
                Status         = $status
                WinGetStatus   = $result.Status
                RebootRequired = $result.RebootRequired
                Message        = $(if ($result.Message) { $result.Message } else { "OK" })
                Timestamp      = (Get-Date).ToString("o")
            })
        }

        # Compile structured JSON report
        $reportDir = Join-Path (Get-WingetBatchConfigDir) "reports"
        if (-not (Test-Path $reportDir)) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }

        $reportPath = Join-Path $reportDir "deployment_report_$((Get-Date).ToString('yyyyMMdd_HHmmss')).json"
        $reportObj = [ordered]@{
            Summary = [ordered]@{
                Total          = $executionQueue.Count
                Successful     = $successCount
                Failed         = $failCount
                RebootRequired = $rebootPending
            }
            Results = $reportData
        }

        $reportObj | ConvertTo-Json -Depth 5 | Out-File -FilePath $reportPath -Encoding utf8

        Write-Host ("`n" + ("=" * 60)) -ForegroundColor Green
        Write-Host "Deployment Complete" -ForegroundColor Green
        Write-Host ("=" * 60) -ForegroundColor Green
        Write-Host "   Successful: " -NoNewline -ForegroundColor Green
        Write-Host $successCount -ForegroundColor White
        Write-Host "   Failed:     " -NoNewline -ForegroundColor Red
        Write-Host $failCount -ForegroundColor White

        if ($rebootPending) {
            Write-Host "   A restart is required to finish at least one installation." -ForegroundColor Yellow
        }

        Write-Host "`nJSON deployment report saved to:" -ForegroundColor Gray
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
    
    # Clean up finished WingetBatch jobs only (leave the user's own jobs alone)
    $jobs = Get-Job -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in 'WingetBatchDetails', 'WingetUpdateCheck' -and $_.State -in @('Completed', 'Failed', 'Stopped')
    }
    if ($jobs) {
        $jobs | Remove-Job -Force
    }
    
    $mbFreed = [math]::Round($bytesFreed / 1MB, 2)
    Write-Host "Cleanup complete. Freed $mbFreed MB of cache." -ForegroundColor Green
}


# EndRegion

# Region: Public/Invoke-WingetFleet.ps1
function Invoke-WingetFleet {
    <#
    .SYNOPSIS
        Execute winget operations across multiple remote machines simultaneously.

    .DESCRIPTION
        SCCM-lite for people who hate SCCM. Push package installs, updates, uninstalls,
        and state queries to N machines over WinRM or SSH with parallel execution,
        aggregated reporting, and failure resilience.

        Supports machine lists from files, Active Directory OUs, or inline arrays.
        Results are collected into a structured report with per-machine status.

    .PARAMETER Computers
        Array of computer names/IPs to target.

    .PARAMETER ComputerFile
        Path to a text file with one computer name per line.

    .PARAMETER Action
        Operation to perform: Install, Uninstall, Update, UpdateAll, List, State, Query.

    .PARAMETER PackageId
        Package ID(s) for Install/Uninstall/Query actions.

    .PARAMETER Credential
        PSCredential for remote authentication. Defaults to current user.

    .PARAMETER UseSSH
        Use SSH instead of WinRM for remote connectivity.

    .PARAMETER ThrottleLimit
        Maximum concurrent remote sessions. Default: 10.

    .PARAMETER TimeoutSeconds
        Per-machine operation timeout. Default: 300.

    .PARAMETER ExportReport
        Save aggregated results to a JSON report file.

    .PARAMETER RetryFailed
        Automatically retry failed machines once.

    .EXAMPLE
        Invoke-WingetFleet -Computers "PC01","PC02","PC03" -Action UpdateAll
        Updates all packages on 3 machines in parallel.

    .EXAMPLE
        Invoke-WingetFleet -ComputerFile ".\lab-machines.txt" -Action Install -PackageId "Git.Git","Python.Python.3.12"
        Installs Git and Python on all machines in the file.

    .EXAMPLE
        Invoke-WingetFleet -Computers "Server01" -Action State -Credential (Get-Credential)
        Queries full package state on Server01 with explicit credentials.

    .EXAMPLE
        Invoke-WingetFleet -ComputerFile ".\fleet.txt" -Action List -ExportReport ".\fleet-report.json"
        Lists all packages on every machine and exports a JSON report.

    .NOTES
        Author: Matthew Bubb
        Requires: WinRM (Enable-PSRemoting) or SSH configured on target machines.
        WingetBatch module must be available on remote machines for full functionality.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Inline')]
    param(
        [Parameter(ParameterSetName = 'Inline', Mandatory, Position = 0)]
        [Alias('Machines', 'Hosts')]
        [string[]]$Computers,

        [Parameter(ParameterSetName = 'File', Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ComputerFile,

        [Parameter(Mandatory)]
        [ValidateSet('Install', 'Uninstall', 'Update', 'UpdateAll', 'List', 'State', 'Query')]
        [string]$Action,

        [Parameter()]
        [string[]]$PackageId,

        [Parameter()]
        [PSCredential]$Credential,

        [switch]$UseSSH,

        [ValidateRange(1, 50)]
        [int]$ThrottleLimit = 10,

        [ValidateRange(30, 3600)]
        [int]$TimeoutSeconds = 300,

        [string]$ExportReport,

        [switch]$RetryFailed
    )

    # --- Resolve computer list ---
    if ($ComputerFile) {
        $Computers = Get-Content -Path $ComputerFile | Where-Object { $_.Trim() -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() }
    }

    if (-not $Computers -or $Computers.Count -eq 0) {
        Write-Error "No target computers specified."
        return
    }

    # Validate package IDs for actions that need them
    if ($Action -in @('Install', 'Uninstall', 'Update', 'Query') -and -not $PackageId) {
        Write-Error "Action '$Action' requires -PackageId parameter."
        return
    }

    # --- Banner ---
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║           WingetBatch Fleet Operations              ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Targets:   " -NoNewline -ForegroundColor DarkGray; Write-Host "$($Computers.Count) machines" -ForegroundColor White
    Write-Host "  Action:    " -NoNewline -ForegroundColor DarkGray; Write-Host $Action -ForegroundColor Yellow
    if ($PackageId) {
        Write-Host "  Packages:  " -NoNewline -ForegroundColor DarkGray; Write-Host ($PackageId -join ', ') -ForegroundColor White
    }
    Write-Host "  Transport: " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($UseSSH) { "SSH" } else { "WinRM" }) -ForegroundColor White
    Write-Host "  Parallel:  " -NoNewline -ForegroundColor DarkGray; Write-Host "$ThrottleLimit concurrent" -ForegroundColor White
    Write-Host ""

    # --- Build remote script block ---
    # Runs on the target machine (Windows PowerShell 5.1 or 7), so it cannot use
    # WingetBatch's private helpers and must stay 5.1-compatible.
    $remoteScript = {
        param($ActionParam, $PackageIds, $TimeoutSec)

        $result = @{
            Computer   = $env:COMPUTERNAME
            Action     = $ActionParam
            Timestamp  = (Get-Date).ToString('o')
            Status     = 'Unknown'
            Packages   = @()
            Errors     = @()
            DurationMs = 0
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        # WinGet cmdlets report installer failures in .Status instead of throwing
        function Invoke-Op {
            param([string]$Verb, [string]$Id, [string]$Source)
            $params = @{ Id = $Id; MatchOption = 'EqualsCaseInsensitive'; Mode = 'Silent'; ErrorAction = 'Stop' }
            if ($Source) { $params['Source'] = $Source }
            try {
                $r = @(& "Microsoft.WinGet.Client\$Verb-WinGetPackage" @params)
                $status = if ($r.Count -gt 0) { [string]$r[-1].Status } else { 'NoResult' }
                $ok = ($status -eq 'Ok') -or ($Verb -eq 'Update' -and $status -eq 'NoApplicableUpgrade')
                return @{ Ok = $ok; Status = $status; Reboot = ($r.Count -gt 0 -and [bool]$r[-1].RebootRequired) }
            }
            catch {
                return @{ Ok = $false; Status = $_.Exception.Message; Reboot = $false }
            }
        }

        try {
            if (-not (Get-Module -ListAvailable Microsoft.WinGet.Client)) {
                $result.Status = 'Error'
                $result.Errors += "Microsoft.WinGet.Client not available on this machine"
                return ($result | ConvertTo-Json -Depth 5 -Compress)
            }
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop

            switch ($ActionParam) {
                'List' {
                    $pkgs = @(Microsoft.WinGet.Client\Get-WinGetPackage)
                    $result.Packages = @($pkgs | ForEach-Object {
                        @{ Id = $_.Id; Name = $_.Name; Version = $_.InstalledVersion; Source = $_.Source }
                    })
                    $result.Status = 'Success'
                }
                'State' {
                    $pkgs = @(Microsoft.WinGet.Client\Get-WinGetPackage)
                    $result.Packages = @($pkgs | ForEach-Object {
                        @{ Id = $_.Id; Name = $_.Name; Version = $_.InstalledVersion; Source = $_.Source; Available = @($_.AvailableVersions)[0]; UpdateAvailable = [bool]$_.IsUpdateAvailable }
                    })
                    $result.TotalCount = $pkgs.Count
                    $result.UpdatesAvailable = @($pkgs | Where-Object { $_.IsUpdateAvailable }).Count
                    $result.Status = 'Success'
                }
                { $_ -in 'Install', 'Uninstall', 'Update' } {
                    $pastTense = @{ Install = 'Installed'; Uninstall = 'Uninstalled'; Update = 'Updated' }[$ActionParam]
                    foreach ($id in $PackageIds) {
                        $op = Invoke-Op -Verb $ActionParam -Id $id
                        if ($op.Ok) { $result.Packages += @{ Id = $id; Status = $pastTense; RebootRequired = $op.Reboot } }
                        else { $result.Packages += @{ Id = $id; Status = 'Failed'; Error = $op.Status } }
                    }
                }
                'UpdateAll' {
                    $updatable = @(Microsoft.WinGet.Client\Get-WinGetPackage | Where-Object { $_.IsUpdateAvailable })
                    foreach ($pkg in $updatable) {
                        $op = Invoke-Op -Verb 'Update' -Id $pkg.Id -Source $pkg.Source
                        if ($op.Ok) { $result.Packages += @{ Id = $pkg.Id; Status = 'Updated'; Version = @($pkg.AvailableVersions)[0]; RebootRequired = $op.Reboot } }
                        else { $result.Packages += @{ Id = $pkg.Id; Status = 'Failed'; Error = $op.Status } }
                    }
                    $result.UpdatesAvailable = $updatable.Count
                }
                'Query' {
                    foreach ($id in $PackageIds) {
                        $found = Microsoft.WinGet.Client\Get-WinGetPackage -Id $id -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($found) {
                            $result.Packages += @{ Id = $id; Installed = $true; Version = $found.InstalledVersion; Name = $found.Name; UpdateAvailable = [bool]$found.IsUpdateAvailable }
                        } else {
                            $result.Packages += @{ Id = $id; Installed = $false }
                        }
                    }
                    $result.Status = 'Success'
                }
            }

            if ($ActionParam -in 'Install', 'Uninstall', 'Update', 'UpdateAll') {
                $failedCount = @($result.Packages | Where-Object { $_.Status -eq 'Failed' }).Count
                $result.Status = if ($failedCount -eq 0) { 'Success' } elseif ($failedCount -lt $result.Packages.Count) { 'PartialFailure' } else { 'Error' }
                if ($failedCount -gt 0) {
                    $result.Errors += @($result.Packages | Where-Object { $_.Status -eq 'Failed' } | ForEach-Object { "$($_.Id): $($_.Error)" })
                }
            }
        } catch {
            $result.Status = 'Error'
            $result.Errors += $_.Exception.Message
        }

        $sw.Stop()
        $result.DurationMs = $sw.ElapsedMilliseconds
        return ($result | ConvertTo-Json -Depth 5 -Compress)
    }

    # --- Execute across fleet ---
    $results = [System.Collections.Generic.List[hashtable]]::new()
    $sessionParams = @{}
    if ($Credential) { $sessionParams['Credential'] = $Credential }

    # One place that knows how to reach a machine (WinRM or SSH)
    $invokeRemote = {
        param([string]$Computer, [switch]$AsJob)
        $target = if ($UseSSH) { @{ HostName = $Computer } } else { @{ ComputerName = $Computer } }
        Invoke-Command @target @sessionParams -ScriptBlock $remoteScript -ArgumentList $Action, $PackageId, $TimeoutSeconds -AsJob:$AsJob -ErrorAction Stop
    }

    $total = $Computers.Count
    $completed = 0

    for ($batchStart = 0; $batchStart -lt $total; $batchStart += $ThrottleLimit) {
        $batch = $Computers[$batchStart..([Math]::Min($batchStart + $ThrottleLimit - 1, $total - 1))]
        $jobMap = @{}

        foreach ($computer in $batch) {
            $completed++
            Write-Progress -Activity "Fleet: $Action" -Status "[$completed/$total] $computer" -PercentComplete (($completed / $total) * 100)
            try {
                $job = & $invokeRemote -Computer $computer -AsJob
                $jobMap[$job.Id] = @{ Job = $job; Computer = $computer }
            }
            catch {
                $results.Add(@{ Computer = $computer; Status = 'Error'; Errors = @($_.Exception.Message) })
            }
        }

        # Wait for batch
        $batchJobs = @($jobMap.Values | ForEach-Object { $_.Job })
        if ($batchJobs.Count -gt 0) {
            $batchJobs | Wait-Job -Timeout $TimeoutSeconds | Out-Null
        }

        # Collect results
        foreach ($entry in $jobMap.Values) {
            $job = $entry.Job
            $computer = $entry.Computer
            try {
                if ($job.State -eq 'Running') {
                    Stop-Job $job -ErrorAction SilentlyContinue
                    $results.Add(@{ Computer = $computer; Status = 'Timeout'; Errors = @("No response within $TimeoutSeconds seconds") })
                    continue
                }
                $output = Receive-Job $job -ErrorAction Stop
                if ($output) {
                    $parsed = @($output)[-1] | ConvertFrom-Json -AsHashtable
                    # Report under the name we targeted (the remote COMPUTERNAME may differ, e.g. IPs)
                    $parsed['Computer'] = $computer
                    $results.Add($parsed)
                } else {
                    $results.Add(@{ Computer = $computer; Status = 'NoResponse'; Errors = @('Job returned no output') })
                }
            } catch {
                $results.Add(@{ Computer = $computer; Status = 'Error'; Errors = @($_.Exception.Message) })
            }
            finally {
                Remove-Job $job -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Progress -Activity "Fleet: $Action" -Completed

    # --- Retry failed ---
    if ($RetryFailed) {
        $failedMachines = @($results | Where-Object { $_.Status -in @('Error', 'NoResponse', 'Timeout') } | ForEach-Object { $_.Computer })
        if ($failedMachines.Count -gt 0) {
            Write-Host "  Retrying $($failedMachines.Count) failed machines..." -ForegroundColor Yellow
            foreach ($computer in $failedMachines) {
                $idx = $results.FindIndex([Predicate[hashtable]] { param($r) $r.Computer -eq $computer })
                try {
                    $output = & $invokeRemote -Computer $computer
                    $parsed = @($output)[-1] | ConvertFrom-Json -AsHashtable
                    $parsed['Computer'] = $computer
                    if ($idx -ge 0) { $results[$idx] = $parsed }
                } catch {
                    if ($idx -ge 0) { $results[$idx]['Errors'] = @($results[$idx]['Errors']) + "Retry failed: $($_.Exception.Message)" }
                }
            }
        }
    }

    # --- Aggregate Report ---
    $successCount = @($results | Where-Object { $_.Status -eq 'Success' }).Count
    $partialCount = @($results | Where-Object { $_.Status -eq 'PartialFailure' }).Count
    $failedCount = @($results | Where-Object { $_.Status -in @('Error', 'NoResponse', 'Timeout') }).Count

    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────┐" -ForegroundColor White
    Write-Host "  │              Fleet Operation Results                 │" -ForegroundColor White
    Write-Host "  ├─────────────────────────────────────────────────────┤" -ForegroundColor White
    Write-Host "  │  " -NoNewline -ForegroundColor White
    Write-Host "Success: $successCount" -NoNewline -ForegroundColor Green
    Write-Host "  |  " -NoNewline -ForegroundColor White
    Write-Host "Partial: $partialCount" -NoNewline -ForegroundColor Yellow
    Write-Host "  |  " -NoNewline -ForegroundColor White
    Write-Host "Failed: $failedCount" -NoNewline -ForegroundColor Red
    Write-Host "  │" -ForegroundColor White
    Write-Host "  └─────────────────────────────────────────────────────┘" -ForegroundColor White
    Write-Host ""

    # Per-machine summary
    foreach ($r in ($results | Sort-Object { $_.Computer })) {
        $icon = switch ($r.Status) {
            'Success' { '✓' }
            'PartialFailure' { '◐' }
            default { '✗' }
        }
        $color = switch ($r.Status) {
            'Success' { 'Green' }
            'PartialFailure' { 'Yellow' }
            default { 'Red' }
        }
        $duration = if ($r.DurationMs) { " ($([Math]::Round($r.DurationMs / 1000, 1))s)" } else { "" }
        Write-Host "  $icon " -NoNewline -ForegroundColor $color
        Write-Host "$($r.Computer)" -NoNewline -ForegroundColor White
        Write-Host " — $($r.Status)$duration" -ForegroundColor $color

        if ($r.Errors -and $r.Errors.Count -gt 0) {
            foreach ($err in $r.Errors | Select-Object -First 2) {
                Write-Host "      $err" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ""

    # --- Export ---
    if ($ExportReport) {
        $report = @{
            Timestamp = (Get-Date).ToString('o')
            Action = $Action
            PackageIds = $PackageId
            TotalMachines = $total
            Success = $successCount
            PartialFailure = $partialCount
            Failed = $failedCount
            Results = $results
        }
        $report | ConvertTo-Json -Depth 10 | Set-Content -Path $ExportReport -Encoding UTF8
        Write-Host "  Report saved: $ExportReport" -ForegroundColor Green
        Write-Host ""
    }

    # Return structured results for pipeline
    $results | ForEach-Object { [PSCustomObject]$_ }
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

# Region: Public/Register-WingetMaintenance.ps1
function Register-WingetMaintenance {
    <#
    .SYNOPSIS
        Register a scheduled maintenance task for automatic winget package management.

    .DESCRIPTION
        Creates a Windows Scheduled Task that automatically updates, cleans up, and/or
        audits installed packages on a configurable schedule. Supports daily, weekly,
        and monthly recurrence with customizable actions and notification preferences.

        The maintenance task runs as SYSTEM by default (for machine-wide updates) or
        as the current user (for per-user packages). Results are logged to a JSON
        report in the WingetBatch config directory.

    .PARAMETER Schedule
        Recurrence pattern: Daily, Weekly, or Monthly. Default: Weekly.

    .PARAMETER Time
        Time of day to run maintenance (24h format). Default: 03:00.

    .PARAMETER DayOfWeek
        For Weekly schedule: which day(s) to run. Default: Sunday.

    .PARAMETER DayOfMonth
        For Monthly schedule: which day of the month. Default: 1.

    .PARAMETER Action
        What maintenance actions to perform. Multiple allowed.
        Options: UpdateAll, UpdateOutdated, CleanupTemp, AuditDrift, NotifyOnly.
        Default: UpdateAll, CleanupTemp.

    .PARAMETER TaskName
        Custom name for the scheduled task. Default: "WingetBatch Maintenance".

    .PARAMETER RunAsSystem
        Run the task as SYSTEM (elevated, machine-wide). Default: true.
        Set -RunAsSystem:$false to run as current user.

    .PARAMETER IncludeStore
        Include Microsoft Store packages in updates. Default: false.

    .PARAMETER MaxDurationMinutes
        Maximum execution time before the task is killed. Default: 120.

    .PARAMETER Unregister
        Remove the scheduled maintenance task.

    .PARAMETER Status
        Show the current maintenance task configuration and last run result.

    .PARAMETER RunNow
        Trigger the maintenance task immediately (for testing).

    .EXAMPLE
        Register-WingetMaintenance
        Registers weekly Sunday 3AM maintenance with update-all and temp cleanup.

    .EXAMPLE
        Register-WingetMaintenance -Schedule Daily -Time 02:00 -Action UpdateAll, AuditDrift
        Daily 2AM maintenance that updates all packages and audits drift.

    .EXAMPLE
        Register-WingetMaintenance -Status
        Shows current task configuration, next run time, and last result.

    .EXAMPLE
        Register-WingetMaintenance -Unregister
        Removes the scheduled maintenance task.

    .NOTES
        Author: Matthew Bubb
        Requires: Run as Administrator for -RunAsSystem (default).
    #>
    [CmdletBinding(DefaultParameterSetName = 'Register')]
    param(
        [Parameter(ParameterSetName = 'Register')]
        [ValidateSet('Daily', 'Weekly', 'Monthly')]
        [string]$Schedule = 'Weekly',

        [Parameter(ParameterSetName = 'Register')]
        [ValidatePattern('^([01]\d|2[0-3]):[0-5]\d$')]
        [string]$Time = '03:00',

        [Parameter(ParameterSetName = 'Register')]
        [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
        [string[]]$DayOfWeek = @('Sunday'),

        [Parameter(ParameterSetName = 'Register')]
        [ValidateRange(1, 31)]
        [int]$DayOfMonth = 1,

        [Parameter(ParameterSetName = 'Register')]
        [ValidateSet('UpdateAll', 'UpdateOutdated', 'CleanupTemp', 'AuditDrift', 'NotifyOnly')]
        [string[]]$Action = @('UpdateAll', 'CleanupTemp'),

        [Parameter(ParameterSetName = 'Register')]
        [string]$TaskName = 'WingetBatch Maintenance',

        [Parameter(ParameterSetName = 'Register')]
        [bool]$RunAsSystem = $true,

        [Parameter(ParameterSetName = 'Register')]
        [switch]$IncludeStore,

        [Parameter(ParameterSetName = 'Register')]
        [ValidateRange(10, 480)]
        [int]$MaxDurationMinutes = 120,

        [Parameter(ParameterSetName = 'Unregister', Mandatory)]
        [switch]$Unregister,

        [Parameter(ParameterSetName = 'Status', Mandatory)]
        [switch]$Status,

        [Parameter(ParameterSetName = 'Register')]
        [switch]$RunNow
    )

    # --- Config directory ---
    $configDir = Get-WingetBatchConfigDir
    $logDir = Join-Path $configDir "maintenance"
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # --- STATUS ---
    if ($Status) {
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $existingTask) {
            Write-Host "`n  No maintenance task registered." -ForegroundColor Yellow
            Write-Host "  Run 'Register-WingetMaintenance' to create one.`n" -ForegroundColor DarkGray
            return
        }

        $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
        $lastResult = if ($info.LastTaskResult -eq 0) { "Success" } 
                      elseif ($info.LastTaskResult -eq 267011) { "Never run" }
                      else { "Exit code: $($info.LastTaskResult)" }

        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "  ║       WingetBatch Maintenance Status            ║" -ForegroundColor Cyan
        Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Task Name:    " -NoNewline -ForegroundColor DarkGray; Write-Host $TaskName -ForegroundColor White
        Write-Host "  State:        " -NoNewline -ForegroundColor DarkGray; Write-Host $existingTask.State -ForegroundColor $(if ($existingTask.State -eq 'Ready') { 'Green' } else { 'Yellow' })
        Write-Host "  Next Run:     " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($info.NextRunTime) { $info.NextRunTime } else { 'Not scheduled' }) -ForegroundColor White
        Write-Host "  Last Run:     " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($info.LastRunTime -and $info.LastRunTime.Year -gt 2000) { $info.LastRunTime } else { 'Never' }) -ForegroundColor White
        Write-Host "  Last Result:  " -NoNewline -ForegroundColor DarkGray; Write-Host $lastResult -ForegroundColor $(if ($lastResult -eq 'Success' -or $lastResult -eq 'Never run') { 'Green' } else { 'Red' })
        Write-Host ""

        # Show last report if available
        $lastReport = Get-ChildItem -Path $logDir -Filter "maintenance_*.json" -ErrorAction SilentlyContinue | 
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($lastReport) {
            $report = Get-Content $lastReport.FullName -Raw | ConvertFrom-Json
            Write-Host "  Last Report:  " -NoNewline -ForegroundColor DarkGray
            Write-Host "$($report.UpdatedCount) updated, $($report.FailedCount) failed, $($report.SkippedCount) skipped" -ForegroundColor White
            Write-Host "  Report File:  " -NoNewline -ForegroundColor DarkGray
            Write-Host $lastReport.FullName -ForegroundColor DarkGray
        }
        Write-Host ""
        return
    }

    # --- UNREGISTER ---
    if ($Unregister) {
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $existingTask) {
            Write-Host "  Task '$TaskName' not found. Nothing to remove." -ForegroundColor Yellow
            return
        }
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "  ✓ Maintenance task '$TaskName' removed." -ForegroundColor Green
        return
    }

    # --- REGISTER ---
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($RunAsSystem -and -not $isAdmin) {
        Write-Warning "RunAsSystem requires Administrator privileges. Falling back to current user."
        $RunAsSystem = $false
    }

    if ($Action -contains 'AuditDrift' -and -not (Test-Path (Join-Path $configDir "machine_state_baseline.json"))) {
        Write-Warning "AuditDrift needs a baseline. Create one with: Get-WingetMachineState -Export -Path '$(Join-Path $configDir "machine_state_baseline.json")'"
    }

    # Values baked into the generated script. Single quotes are doubled so paths
    # containing apostrophes cannot break out of the string literals.
    $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
    $modulePath = Join-Path $PSScriptRoot "..\WingetBatch.psd1"
    if (-not (Test-Path $modulePath)) { $modulePath = Join-Path (Get-Module WingetBatch).ModuleBase "WingetBatch.psd1" }
    $modulePath = [System.IO.Path]::GetFullPath($modulePath)
    $actionList = ($Action | ForEach-Object { & $q $_ }) -join ', '
    $doUpdate = ($Action -contains 'UpdateAll' -or $Action -contains 'UpdateOutdated')
    $doCheck = $doUpdate -or ($Action -contains 'NotifyOnly')

    $maintenanceScript = @"
# WingetBatch Maintenance Script
# Auto-generated by Register-WingetMaintenance on $((Get-Date).ToString('yyyy-MM-dd HH:mm'))
# Actions: $($Action -join ', ')

`$ErrorActionPreference = 'Continue'
`$ProgressPreference = 'SilentlyContinue'
`$logDir = $(& $q $logDir)
`$configDir = $(& $q $configDir)
`$modulePath = $(& $q $modulePath)
`$reportPath = Join-Path `$logDir "maintenance_`$(Get-Date -Format 'yyyyMMdd_HHmmss').json"

"@

    if ($Schedule -eq 'Monthly') {
        # Task Scheduler cmdlets have no monthly trigger: the task runs daily and exits
        # unless today is the chosen day (or the month's last day for days 29-31).
        $maintenanceScript += @"
# --- Monthly gate ---
`$today = Get-Date
`$runDay = [Math]::Min($DayOfMonth, [DateTime]::DaysInMonth(`$today.Year, `$today.Month))
if (`$today.Day -ne `$runDay) { exit 0 }

"@
    }

    $maintenanceScript += @"
`$report = [ordered]@{
    Timestamp        = (Get-Date).ToString('o')
    Hostname         = `$env:COMPUTERNAME
    Actions          = @($actionList)
    UpdatesAvailable = 0
    UpdatedCount     = 0
    FailedCount      = 0
    SkippedCount     = 0
    UpdatedPackages  = @()
    FailedPackages   = @()
    Errors           = @()
}

function Save-Report {
    `$report | ConvertTo-Json -Depth 6 | Set-Content -Path `$reportPath -Encoding UTF8
}

try {
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
} catch {
    `$report.Errors += "Failed to import Microsoft.WinGet.Client: `$_"
    Save-Report
    exit 1
}

"@

    if ($doCheck) {
        $storeFilter = if ($IncludeStore) { '' } else { " | Where-Object { `$_.Source -ne 'msstore' }" }
        $maintenanceScript += @"
# --- Check for updates ---
try {
    `$updates = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction Stop | Where-Object { `$_.IsUpdateAvailable }$storeFilter)
    `$report.UpdatesAvailable = `$updates.Count
} catch {
    `$updates = @()
    `$report.Errors += "Update check failed: `$_"
}

"@
    }

    if ($doUpdate) {
        $maintenanceScript += @"
# --- Update packages (result status is checked; the cmdlet does not throw on installer failure) ---
foreach (`$pkg in `$updates) {
    try {
        `$params = @{ Id = `$pkg.Id; MatchOption = 'EqualsCaseInsensitive'; Mode = 'Silent'; ErrorAction = 'Stop' }
        if (`$pkg.Source) { `$params['Source'] = `$pkg.Source }
        `$r = @(Microsoft.WinGet.Client\Update-WinGetPackage @params)[-1]
        if (`$r -and [string]`$r.Status -eq 'Ok') {
            `$report.UpdatedCount++
            `$report.UpdatedPackages += `$pkg.Id
        } else {
            `$report.FailedCount++
            `$report.FailedPackages += @{ Id = `$pkg.Id; Error = [string]`$r.Status }
        }
    } catch {
        `$report.FailedCount++
        `$report.FailedPackages += @{ Id = `$pkg.Id; Error = `$_.Exception.Message }
    }
}

"@
    }
    elseif ($doCheck) {
        $maintenanceScript += @"
# NotifyOnly: report what is pending without changing anything
`$report.SkippedCount = `$updates.Count

"@
    }

    if ($Action -contains 'CleanupTemp') {
        $maintenanceScript += @"
# --- Cleanup Temp Files ---
try {
    `$tempPaths = @(
        (Join-Path `$env:TEMP "WinGet"),
        (Join-Path `$env:LOCALAPPDATA "Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\TempState")
    )
    foreach (`$p in `$tempPaths) {
        if (Test-Path `$p) {
            Get-ChildItem -Path `$p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} catch {
    `$report.Errors += "Cleanup phase failed: `$_"
}

"@
    }

    $maintenanceScript += @"
# WingetBatch is only needed for drift audits and webhooks
`$wingetBatchLoaded = `$false
if ($(if ($Action -contains 'AuditDrift') { '$true' } else { '$false' }) -or (Test-Path (Join-Path `$configDir 'config.json'))) {
    try { Import-Module WingetBatch -ErrorAction Stop; `$wingetBatchLoaded = `$true }
    catch {
        try { Import-Module `$modulePath -ErrorAction Stop; `$wingetBatchLoaded = `$true }
        catch { `$report.Errors += "Could not load WingetBatch: `$_" }
    }
}

"@

    if ($Action -contains 'AuditDrift') {
        $maintenanceScript += @"
# --- Audit Drift ---
try {
    `$statePath = Join-Path `$configDir "machine_state_baseline.json"
    if (-not (Test-Path `$statePath)) {
        `$report.Errors += "Drift audit skipped: no baseline at `$statePath"
    } elseif (`$wingetBatchLoaded) {
        `$drift = Get-WingetMachineState -Compare -Path `$statePath 6>`$null
        `$report.Drift = [ordered]@{
            IsCompliant = `$drift.IsCompliant
            Missing     = @(`$drift.Missing)
            Outdated    = @(`$drift.Outdated | ForEach-Object { `$_.Id })
            Extraneous  = @(`$drift.Extraneous)
        }
    }
} catch {
    `$report.Errors += "Drift audit failed: `$_"
}

"@
    }

    $maintenanceScript += @"
# --- Webhook notifications (webhooks saved with Send-WingetWebhook -SaveConfig) ---
if (`$wingetBatchLoaded) {
    try {
        `$cfg = Get-Content (Join-Path `$configDir 'config.json') -Raw | ConvertFrom-Json
        foreach (`$platform in 'Discord', 'Slack', 'Teams') {
            `$url = `$cfg."webhook_`$(`$platform.ToLower())"
            if (-not `$url) { continue }
            `$msg = "`$(`$report.UpdatesAvailable) update(s) available, `$(`$report.UpdatedCount) updated, `$(`$report.FailedCount) failed."
            if (`$report.Drift -and -not `$report.Drift.IsCompliant) { `$msg += " Drift detected against baseline." }
            Send-WingetWebhook -Platform `$platform -WebhookUrl `$url -Event MaintenanceComplete -Message `$msg 6>`$null | Out-Null
        }
    } catch {
        `$report.Errors += "Webhook notification failed: `$_"
    }
}

# --- Save Report ---
Save-Report

# Keep only last 30 reports
Get-ChildItem -Path `$logDir -Filter "maintenance_*.json" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 30 |
    Remove-Item -Force -ErrorAction SilentlyContinue

exit `$(if (`$report.FailedCount -gt 0 -or `$report.Errors.Count -gt 0) { 1 } else { 0 })
"@

    # Save the maintenance script
    $scriptPath = Join-Path $configDir "maintenance_task.ps1"
    $maintenanceScript | Set-Content -Path $scriptPath -Encoding UTF8

    # Build scheduled task
    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) {
        Write-Error "pwsh.exe (PowerShell 7) was not found in PATH. The maintenance task requires PowerShell 7."
        return
    }

    $taskAction = New-ScheduledTaskAction `
        -Execute $pwshPath `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

    # Trigger
    $timeParts = $Time.Split(':')
    $triggerTime = New-TimeSpan -Hours ([int]$timeParts[0]) -Minutes ([int]$timeParts[1])
    $startTime = (Get-Date).Date + $triggerTime
    if ($startTime -lt (Get-Date)) { $startTime = $startTime.AddDays(1) }

    switch ($Schedule) {
        'Daily'   { $trigger = New-ScheduledTaskTrigger -Daily -At $startTime }
        'Weekly'  { $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $startTime }
        'Monthly' { $trigger = New-ScheduledTaskTrigger -Daily -At $startTime }  # gated to $DayOfMonth inside the script
    }

    # Settings
    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Minutes $MaxDurationMinutes) `
        -StartWhenAvailable `
        -DontStopOnIdleEnd `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    # Principal (Highest only when we can actually grant it)
    if ($RunAsSystem) {
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    } else {
        $runLevel = if ($isAdmin) { 'Highest' } else { 'Limited' }
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel $runLevel
    }

    # Register (overwrite if exists)
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    $scheduleText = switch ($Schedule) {
        'Daily'   { "Daily at $Time" }
        'Weekly'  { "Weekly ($($DayOfWeek -join ', ')) at $Time" }
        'Monthly' { "Monthly on day $DayOfMonth at $Time" }
    }

    try {
        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $taskAction `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description "WingetBatch automated maintenance: $($Action -join ', '). $scheduleText." `
            -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "Failed to register scheduled task: $($_.Exception.Message)"
        return
    }


    # Output confirmation
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║     WingetBatch Maintenance Registered          ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Schedule:   " -NoNewline -ForegroundColor DarkGray; Write-Host $scheduleText -ForegroundColor White
    Write-Host "  Actions:    " -NoNewline -ForegroundColor DarkGray; Write-Host ($Action -join ', ') -ForegroundColor White
    Write-Host "  Run As:     " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($RunAsSystem) { "SYSTEM" } else { $env:USERNAME }) -ForegroundColor White
    Write-Host "  Store Pkgs: " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($IncludeStore) { "Included" } else { "Excluded" }) -ForegroundColor White
    Write-Host "  Timeout:    " -NoNewline -ForegroundColor DarkGray; Write-Host "${MaxDurationMinutes}m" -ForegroundColor White
    Write-Host "  Script:     " -NoNewline -ForegroundColor DarkGray; Write-Host $scriptPath -ForegroundColor DarkGray
    Write-Host "  Reports:    " -NoNewline -ForegroundColor DarkGray; Write-Host $logDir -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Commands:" -ForegroundColor DarkGray
    Write-Host "    Register-WingetMaintenance -Status    # Check status" -ForegroundColor DarkGray
    Write-Host "    Register-WingetMaintenance -RunNow    # Test run" -ForegroundColor DarkGray
    Write-Host "    Register-WingetMaintenance -Unregister # Remove" -ForegroundColor DarkGray
    Write-Host ""

    # Optional: run immediately
    if ($RunNow) {
        Write-Host "  Triggering maintenance now..." -ForegroundColor Cyan
        Start-ScheduledTask -TaskName $TaskName
        Start-Sleep -Seconds 2
        $taskState = (Get-ScheduledTask -TaskName $TaskName).State
        Write-Host "  Task state: $taskState" -ForegroundColor $(if ($taskState -eq 'Running') { 'Green' } else { 'Yellow' })
    }
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

        Install dates come from the Windows uninstall registry. Each installed package
        (from the WinGet COM API) is matched to its registry entry by registry key for
        Add/Remove Programs entries, then by exact display name, then by a cautious
        prefix match. Packages that cannot be matched confidently are left out rather
        than guessed, because this list feeds an uninstall.

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
        [ValidateRange(1, 3650)]
        [int]$Days = 1
    )

    $plural = if ($Days -ne 1) { 's' } else { '' }
    Write-Host "Searching for packages installed in the last " -ForegroundColor Cyan -NoNewline
    Write-Host "$Days day$plural..." -ForegroundColor Yellow

    # --- Registry install dates ---
    $uninstallPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $datesByKey = @{}   # registry key name (PSChildName) -> date
    $datesByName = @{}  # DisplayName -> date (case-insensitive)
    foreach ($path in $uninstallPaths) {
        foreach ($entry in (Get-ItemProperty $path -ErrorAction SilentlyContinue)) {
            if (-not $entry.DisplayName -or -not $entry.InstallDate) { continue }
            try {
                $date = [DateTime]::ParseExact([string]$entry.InstallDate, 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture)
            }
            catch { continue }
            if (-not $datesByKey.ContainsKey($entry.PSChildName)) { $datesByKey[$entry.PSChildName] = $date }
            if (-not $datesByName.ContainsKey($entry.DisplayName)) { $datesByName[$entry.DisplayName] = $date }
        }
    }

    Write-Host "Found installation dates for $($datesByName.Count) programs" -ForegroundColor DarkGray
    Write-Host ""

    # --- Installed packages (COM API: full names, no console-width truncation, any locale) ---
    try {
        $installed = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction Stop)
    }
    catch {
        Write-Error "Failed to get installed packages: $_"
        return
    }

    $cutoffDate = (Get-Date).AddDays(-$Days).Date
    $installedPackages = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($pkg in $installed) {
        if (-not $pkg.Id) { continue }
        $installDate = $null

        # 1. ARP\<scope>\<arch>\<registry key> IDs point straight at the registry entry
        if ($pkg.Id -match '^ARP\\.+\\([^\\]+)$' -and $datesByKey.ContainsKey($Matches[1])) {
            $installDate = $datesByKey[$Matches[1]]
        }
        # 2. Exact display name
        elseif ($pkg.Name -and $datesByName.ContainsKey($pkg.Name)) {
            $installDate = $datesByName[$pkg.Name]
        }
        # 3. Registry name starts with the package name ("7-Zip" -> "7-Zip 24.08 (x64)").
        #    Short names ("Go", "Git") are skipped: too likely to hit an unrelated program.
        elseif ($pkg.Name -and $pkg.Name.Length -ge 5) {
            $candidates = @($datesByName.Keys | Where-Object { $_.StartsWith($pkg.Name, [StringComparison]::OrdinalIgnoreCase) })
            if ($candidates.Count -eq 1) { $installDate = $datesByName[$candidates[0]] }
        }

        if ($installDate -and $installDate -ge $cutoffDate) {
            $installedPackages.Add([PSCustomObject]@{
                Id          = $pkg.Id
                Name        = $pkg.Name
                Version     = $pkg.InstalledVersion
                Source      = $pkg.Source
                InstallDate = $installDate
            })
        }
    }

    if ($installedPackages.Count -eq 0) {
        Write-Warning "No packages installed in the last $Days day$plural."
        Write-Host "Note: Only packages with registry install dates can be tracked." -ForegroundColor DarkGray
        return
    }

    $installedPackages = @($installedPackages | Sort-Object -Property InstallDate -Descending)

    Write-Host "Found " -ForegroundColor Green -NoNewline
    Write-Host "$($installedPackages.Count)" -ForegroundColor White -NoNewline
    Write-Host " package(s) installed in the last $Days day$plural" -ForegroundColor Green
    Write-Host ""

    try {
        $displayToPkg = @{}
        $displayLines = foreach ($p in $installedPackages) {
            $display = "($($p.InstallDate.ToString('yyyy-MM-dd'))) $(ConvertTo-SpectreEscaped $p.Name) [grey]$(ConvertTo-SpectreEscaped $p.Id)[/]"
            $displayToPkg[$display] = $p
            $display
        }

        $selectedLines = Read-SpectreMultiSelection -Title "[red]Select packages to UNINSTALL (Space to toggle, Enter to confirm)[/]" `
            -Choices $displayLines `
            -PageSize 20 `
            -Color "Red"
    }
    catch {
        Write-Warning "Interactive selection error: $_"
        Write-Host "Recently installed packages:" -ForegroundColor Cyan
        $installedPackages | ForEach-Object {
            Write-Host "  - ($($_.InstallDate.ToString('yyyy-MM-dd'))) $($_.Name) [$($_.Id)]" -ForegroundColor White
        }
        return
    }

    if (@($selectedLines).Count -eq 0) {
        Write-Host "No packages selected." -ForegroundColor Yellow
        return
    }

    $selectedPackages = @($selectedLines | ForEach-Object { $displayToPkg[$_] })

    Write-Host ""
    Write-Host "WARNING: " -ForegroundColor Red -NoNewline
    Write-Host "You are about to UNINSTALL " -ForegroundColor Yellow -NoNewline
    Write-Host "$($selectedPackages.Count)" -ForegroundColor White -NoNewline
    Write-Host " package(s):" -ForegroundColor Yellow
    Write-Host ""
    foreach ($p in $selectedPackages) {
        Write-Host "   - " -ForegroundColor Red -NoNewline
        Write-Host "$($p.Name) ($($p.Id))" -ForegroundColor White
    }

    Write-Host ""
    Write-Host "Type " -NoNewline -ForegroundColor Yellow
    Write-Host "YES" -NoNewline -ForegroundColor Red
    Write-Host " to confirm uninstallation, or anything else to cancel: " -NoNewline -ForegroundColor Yellow
    $confirmation = Read-Host

    if ($confirmation -cne "YES") {
        Write-Host "Uninstallation cancelled." -ForegroundColor Green
        return
    }

    Invoke-WingetAutoSnapshot -Reason 'Remove-WingetRecent'

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Red
    Write-Host "Starting Uninstallation Process" -ForegroundColor Red
    Write-Host ("=" * 60) -ForegroundColor Red
    Write-Host ""

    $successCount = 0
    $failCount = 0

    foreach ($p in $selectedPackages) {
        Write-Host ">>> Uninstalling: " -ForegroundColor Magenta -NoNewline
        Write-Host $p.Id -ForegroundColor White

        $result = Invoke-WingetPackageAction -Action Uninstall -Id $p.Id -Source $p.Source

        if ($result.Succeeded) {
            Write-Host "[OK] Successfully uninstalled " -ForegroundColor Green -NoNewline
            Write-Host $p.Id -ForegroundColor White
            $successCount++
        }
        else {
            Write-Host "[FAIL] Failed to uninstall " -ForegroundColor Red -NoNewline
            Write-Host $p.Id -ForegroundColor White -NoNewline
            Write-Host " ($($result.Message))" -ForegroundColor Red
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
            Install-WingetBatchDependency -Name Microsoft.WinGet.Client
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
        $version = Microsoft.WinGet.Client\Get-WinGetVersion -ErrorAction Stop
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
        $testResult = Microsoft.WinGet.Client\Find-WinGetPackage -Query "Microsoft.PowerShell" -Count 1 -ErrorAction Stop
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

# Region: Public/Restore-WingetSnapshot.ps1
function Restore-WingetSnapshot {
    <#
    .SYNOPSIS
        Package-level rollback: undo installs, updates, and uninstalls.

    .DESCRIPTION
        Maintains a timeline of package state snapshots and enables rollback
        to any previous point. Snapshots are taken manually (-Take) or automatically
        before every WingetBatch install/update/uninstall once -AutoSnapshot $true is set.

        A rollback reinstalls packages removed since the snapshot (at the snapshot's
        version) and uninstalls WinGet-sourced packages added since. With
        -RestoreVersions it also moves updated packages back to their snapshot version.
        Programs without a WinGet source are never uninstalled.

    .PARAMETER Take
        Capture a snapshot of the current package state right now.

    .PARAMETER Label
        Human-readable label for the snapshot (e.g., "before-vscode-update").

    .PARAMETER List
        Show all available snapshots with timestamps and labels.

    .PARAMETER Restore
        Roll back to a specific snapshot (use with -SnapshotId).

    .PARAMETER UndoLast
        Roll back to the Nth most recent snapshot. With auto-snapshots on,
        -UndoLast 1 undoes the most recent WingetBatch operation.

    .PARAMETER Since
        Restore to the latest snapshot taken at or before this date/time.

    .PARAMETER Diff
        Show what changed since a snapshot (the most recent one by default).

    .PARAMETER SnapshotId
        Target snapshot identifier for Restore operations.

    .PARAMETER DiffSnapshotId
        Snapshot to compare against for -Diff.

    .PARAMETER RestoreVersions
        Also install the snapshot's version of packages that were updated or downgraded since.

    .PARAMETER Force
        Skip the confirmation prompt.

    .PARAMETER PruneOld
        Remove snapshots older than N days.

    .PARAMETER AutoSnapshot
        Enable or disable automatic snapshots before every install/uninstall/update.

    .EXAMPLE
        Restore-WingetSnapshot -Take -Label "before-big-update"
        Manually captures current state with a label.

    .EXAMPLE
        Restore-WingetSnapshot -List
        Shows all snapshots: ID, date, label, package count.

    .EXAMPLE
        Restore-WingetSnapshot -UndoLast 1 -RestoreVersions
        Rolls back to the most recent snapshot, including version changes.

    .EXAMPLE
        Restore-WingetSnapshot -Since "2025-01-15"
        Restores to the state as of January 15th.

    .EXAMPLE
        Restore-WingetSnapshot -Diff -DiffSnapshotId "snap_20250115_143022"
        Shows what changed since that snapshot.

    .NOTES
        Author: Matthew Bubb
        Snapshots stored in ~/.wingetbatch/snapshots/ as JSON.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Take')]
    param(
        [Parameter(ParameterSetName = 'Take')]
        [switch]$Take,

        [Parameter(ParameterSetName = 'Take')]
        [string]$Label,

        [Parameter(ParameterSetName = 'List', Mandatory)]
        [switch]$List,

        [Parameter(ParameterSetName = 'Restore', Mandatory)]
        [switch]$Restore,

        [Parameter(ParameterSetName = 'Restore', Mandatory)]
        [string]$SnapshotId,

        [Parameter(ParameterSetName = 'Undo', Mandatory)]
        [ValidateRange(1, 1000)]
        [int]$UndoLast,

        [Parameter(ParameterSetName = 'Since', Mandatory)]
        [datetime]$Since,

        [Parameter(ParameterSetName = 'Restore')]
        [Parameter(ParameterSetName = 'Undo')]
        [Parameter(ParameterSetName = 'Since')]
        [switch]$RestoreVersions,

        [Parameter(ParameterSetName = 'Restore')]
        [Parameter(ParameterSetName = 'Undo')]
        [Parameter(ParameterSetName = 'Since')]
        [switch]$Force,

        [Parameter(ParameterSetName = 'Diff', Mandatory)]
        [switch]$Diff,

        [Parameter(ParameterSetName = 'Diff')]
        [string]$DiffSnapshotId,

        [Parameter(ParameterSetName = 'Prune', Mandatory)]
        [ValidateRange(1, 3650)]
        [int]$PruneOld,

        [Parameter(ParameterSetName = 'Auto', Mandatory)]
        [bool]$AutoSnapshot
    )

    # --- Snapshot storage ---
    $configDir = Get-WingetBatchConfigDir
    $snapshotDir = Join-Path $configDir "snapshots"
    if (-not (Test-Path $snapshotDir)) {
        New-Item -Path $snapshotDir -ItemType Directory -Force | Out-Null
    }
    $autoConfigPath = Join-Path $configDir "snapshot_config.json"

    # --- Helper: Load snapshot ---
    function Get-SnapshotFile {
        param([string]$Id)
        $path = Join-Path $snapshotDir "$Id.json"
        if (Test-Path $path) {
            return (Get-Content $path -Raw | ConvertFrom-Json)
        }
        return $null
    }

    # --- Helper: All snapshots, newest first ---
    function Get-AllSnapshots {
        $all = foreach ($file in (Get-ChildItem -Path $snapshotDir -Filter "snap_*.json" -ErrorAction SilentlyContinue)) {
            try { Get-Content $file.FullName -Raw | ConvertFrom-Json } catch { }
        }
        @($all | Sort-Object { [datetime]$_.Timestamp } -Descending)
    }

    # --- AUTO SNAPSHOT CONFIG ---
    if ($PSCmdlet.ParameterSetName -eq 'Auto') {
        $config = @{ AutoSnapshot = $AutoSnapshot; Updated = (Get-Date).ToString('o') }
        $config | ConvertTo-Json | Set-Content -Path $autoConfigPath -Encoding UTF8
        if ($AutoSnapshot) {
            Write-Host "  Auto-snapshot enabled. State is captured before every WingetBatch install/update/uninstall." -ForegroundColor Green
            Write-Host "  Undo the last operation with: Restore-WingetSnapshot -UndoLast 1" -ForegroundColor DarkGray
        } else {
            Write-Host "  Auto-snapshot disabled." -ForegroundColor Yellow
        }
        return
    }

    # --- LIST ---
    if ($List) {
        $snapshots = Get-AllSnapshots
        if ($snapshots.Count -eq 0) {
            Write-Host "`n  No snapshots found. Take one with: Restore-WingetSnapshot -Take`n" -ForegroundColor Yellow
            return
        }

        Write-Host ""
        Write-Host "  Package State Snapshots" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  $("#".PadLeft(3))  $("ID".PadRight(28)) $("Date".PadRight(20)) $("Pkgs".PadLeft(5))  Label" -ForegroundColor DarkGray
        Write-Host "  $('─' * 76)" -ForegroundColor DarkGray

        $i = 0
        foreach ($snap in $snapshots) {
            $i++
            $date = ([datetime]$snap.Timestamp).ToString("yyyy-MM-dd HH:mm:ss")
            Write-Host "  $($i.ToString().PadLeft(3))  " -NoNewline -ForegroundColor DarkGray
            Write-Host "$($snap.Id.PadRight(28)) " -NoNewline -ForegroundColor White
            Write-Host "$($date.PadRight(20)) " -NoNewline -ForegroundColor DarkGray
            Write-Host "$(([string]$snap.PackageCount).PadLeft(5))  " -NoNewline -ForegroundColor Cyan
            Write-Host $snap.Label -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "  $i snapshots | Undo to #N: Restore-WingetSnapshot -UndoLast N" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # --- TAKE ---
    if ($PSCmdlet.ParameterSetName -eq 'Take') {
        $snap = New-WingetSnapshot -Label $(if ($Label) { $Label } else { 'manual' })
        Write-Host ""
        Write-Host "  Snapshot captured: " -NoNewline -ForegroundColor Green
        Write-Host $snap.Id -ForegroundColor Cyan
        Write-Host "    Packages: $($snap.PackageCount) | Label: $($snap.Label)" -ForegroundColor DarkGray
        Write-Host "    Path: $(Join-Path $snapshotDir "$($snap.Id).json")" -ForegroundColor DarkGray
        Write-Host ""
        return [PSCustomObject]$snap
    }

    # --- PRUNE ---
    if ($PSCmdlet.ParameterSetName -eq 'Prune') {
        $cutoff = (Get-Date).AddDays(-$PruneOld)
        $oldSnaps = @(Get-ChildItem -Path $snapshotDir -Filter "snap_*.json" | Where-Object { $_.LastWriteTime -lt $cutoff })
        if ($oldSnaps.Count -eq 0) {
            Write-Host "  No snapshots older than $PruneOld days." -ForegroundColor Green
        } else {
            $oldSnaps | Remove-Item -Force
            Write-Host "  Pruned $($oldSnaps.Count) snapshots older than $PruneOld days." -ForegroundColor Green
        }
        return
    }

    # Current state, used by Diff and rollback
    $currentPkgs = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue)
    $current = @{}
    foreach ($p in $currentPkgs) { if ($p.Id) { $current[$p.Id] = $p } }

    # --- DIFF ---
    if ($Diff) {
        $targetSnap = if ($DiffSnapshotId) { Get-SnapshotFile -Id $DiffSnapshotId } else { Get-AllSnapshots | Select-Object -First 1 }
        if (-not $targetSnap) {
            if ($DiffSnapshotId) { Write-Error "Snapshot '$DiffSnapshotId' not found." }
            else { Write-Host "  No snapshots to diff against." -ForegroundColor Yellow }
            return
        }

        $snapshotIds = @{}
        foreach ($p in $targetSnap.Packages) { $snapshotIds[$p.Id] = $p.Version }

        $added = @($current.Keys | Where-Object { -not $snapshotIds.ContainsKey($_) } | Sort-Object)
        $removed = @($snapshotIds.Keys | Where-Object { -not $current.ContainsKey($_) } | Sort-Object)
        $updated = @($current.Keys | Where-Object { $snapshotIds.ContainsKey($_) -and [string]$current[$_].InstalledVersion -ne [string]$snapshotIds[$_] } | Sort-Object)

        Write-Host ""
        Write-Host "  Diff: $($targetSnap.Id) -> now" -ForegroundColor Cyan
        Write-Host "  Snapshot: $(([datetime]$targetSnap.Timestamp).ToString('yyyy-MM-dd HH:mm')) ($($targetSnap.PackageCount) pkgs, $($targetSnap.Label))" -ForegroundColor DarkGray
        Write-Host "  Current:  $($currentPkgs.Count) packages" -ForegroundColor DarkGray
        Write-Host ""

        foreach ($id in $added | Select-Object -First 20) { Write-Host "    + $id ($($current[$id].InstalledVersion))" -ForegroundColor Green }
        foreach ($id in $removed | Select-Object -First 20) { Write-Host "    - $id (was $($snapshotIds[$id]))" -ForegroundColor Red }
        foreach ($id in $updated | Select-Object -First 20) { Write-Host "    ~ $id : $($snapshotIds[$id]) -> $($current[$id].InstalledVersion)" -ForegroundColor Yellow }
        if (($added.Count + $removed.Count + $updated.Count) -eq 0) {
            Write-Host "  No changes since this snapshot." -ForegroundColor Green
        }
        elseif ([Math]::Max([Math]::Max($added.Count, $removed.Count), $updated.Count) -gt 20) {
            Write-Host "  (first 20 of each shown) Added: $($added.Count) Removed: $($removed.Count) Changed: $($updated.Count)" -ForegroundColor DarkGray
        }
        Write-Host ""
        return [PSCustomObject]@{ SnapshotId = $targetSnap.Id; Added = $added; Removed = $removed; Changed = $updated }
    }

    # --- Resolve rollback target ---
    $targetSnap = $null
    switch ($PSCmdlet.ParameterSetName) {
        'Undo' {
            $snapshots = Get-AllSnapshots
            if ($snapshots.Count -lt $UndoLast) {
                Write-Error "Not enough snapshots to undo $UndoLast operation(s). Available: $($snapshots.Count)"
                return
            }
            $targetSnap = $snapshots[$UndoLast - 1]
        }
        'Since' {
            $targetSnap = Get-AllSnapshots | Where-Object { [datetime]$_.Timestamp -le $Since } | Select-Object -First 1
            if (-not $targetSnap) {
                Write-Error "No snapshot found at or before $($Since.ToString('yyyy-MM-dd HH:mm'))."
                return
            }
        }
        'Restore' {
            $targetSnap = Get-SnapshotFile -Id $SnapshotId
            if (-not $targetSnap) {
                Write-Error "Snapshot '$SnapshotId' not found. Use -List to see available snapshots."
                return
            }
        }
    }

    Write-Host ""
    Write-Host "  Rolling back to: $($targetSnap.Id) ($(([datetime]$targetSnap.Timestamp).ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor Cyan
    Write-Host "  Label: $($targetSnap.Label)" -ForegroundColor DarkGray

    # --- Plan ---
    $snapshotPkgs = @{}
    foreach ($p in $targetSnap.Packages) { $snapshotPkgs[$p.Id] = $p }

    $toInstall = @($snapshotPkgs.Values | Where-Object { -not $current.ContainsKey($_.Id) -and $_.Source } | Sort-Object Id)
    $toUninstall = @($current.Values | Where-Object { -not $snapshotPkgs.ContainsKey($_.Id) -and $_.Source } | Sort-Object Id)
    $skipped = @($current.Values | Where-Object { -not $snapshotPkgs.ContainsKey($_.Id) -and -not $_.Source })
    $toRevert = @()
    if ($RestoreVersions) {
        $toRevert = @($current.Values | Where-Object {
            $_.Source -and $snapshotPkgs.ContainsKey($_.Id) -and $snapshotPkgs[$_.Id].Version -and
            [string]$_.InstalledVersion -ne [string]$snapshotPkgs[$_.Id].Version
        } | Sort-Object Id)
    }

    Write-Host ""
    Write-Host "  Rollback Plan:" -ForegroundColor White
    foreach ($p in $toInstall) { Write-Host "    + reinstall $($p.Id) v$($p.Version)" -ForegroundColor Green }
    foreach ($p in $toUninstall) { Write-Host "    - uninstall $($p.Id) ($($p.InstalledVersion))" -ForegroundColor Red }
    foreach ($p in $toRevert) { Write-Host "    ~ revert    $($p.Id) $($p.InstalledVersion) -> $($snapshotPkgs[$p.Id].Version)" -ForegroundColor Yellow }
    if ($skipped.Count -gt 0) {
        Write-Host "    ($($skipped.Count) newly added program(s) have no WinGet source and will be left alone)" -ForegroundColor DarkGray
    }
    Write-Host ""

    $totalActions = $toInstall.Count + $toUninstall.Count + $toRevert.Count
    if ($totalActions -eq 0) {
        Write-Host "  Already at target state. Nothing to do." -ForegroundColor Green
        if (-not $RestoreVersions) {
            Write-Host "  (Version changes are only rolled back with -RestoreVersions.)" -ForegroundColor DarkGray
        }
        return
    }

    if (-not $Force) {
        $confirm = $PSCmdlet.ShouldContinue("Apply $totalActions change(s) to restore snapshot $($targetSnap.Id)?", "Confirm Rollback")
        if (-not $confirm) {
            Write-Host "  Rollback cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Safety snapshot so the rollback itself can be undone
    New-WingetSnapshot -Label "pre-rollback-safety" | Out-Null

    $successCount = 0
    $failCount = 0
    $run = {
        param($label, $result)
        Write-Host "  $label" -NoNewline
        if ($result.Succeeded) { Write-Host " [OK]" -ForegroundColor Green; return $true }
        Write-Host " [FAIL] $($result.Message)" -ForegroundColor Red
        return $false
    }

    foreach ($p in $toInstall) {
        $r = Invoke-WingetPackageAction -Action Install -Id $p.Id -Version $p.Version -Source $p.Source -Options @{ Mode = 'Silent' }
        if (& $run "+ Installing $($p.Id) v$($p.Version)..." $r) { $successCount++ } else { $failCount++ }
    }
    foreach ($p in $toUninstall) {
        $r = Invoke-WingetPackageAction -Action Uninstall -Id $p.Id -Source $p.Source -Options @{ Mode = 'Silent' }
        if (& $run "- Uninstalling $($p.Id)..." $r) { $successCount++ } else { $failCount++ }
    }
    foreach ($p in $toRevert) {
        $ver = $snapshotPkgs[$p.Id].Version
        $r = Set-WingetPackageVersion -Id $p.Id -Version $ver -Source $p.Source
        if (& $run "~ Reverting $($p.Id) to $ver..." $r) { $successCount++ } else { $failCount++ }
    }

    Write-Host ""
    Write-Host "  Rollback complete: $successCount succeeded, $failCount failed." -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host "  (Safety snapshot saved: undo this rollback with Restore-WingetSnapshot -UndoLast 1)" -ForegroundColor DarkGray
    Write-Host ""
}

# EndRegion

# Region: Public/Send-WingetWebhook.ps1
function Send-WingetWebhook {
    <#
    .SYNOPSIS
        Send package event notifications to Discord, Slack, or Teams webhooks.

    .DESCRIPTION
        Push rich notifications to chat platforms when package events occur:
        updates available, maintenance completed, drift detected, installs finished,
        or compliance violations found.

        Supports Discord embeds, Slack Block Kit, and Teams Adaptive Cards (works with
        Teams Workflows "When a Teams webhook request is received" URLs).

        Save a URL once with -SaveConfig; Register-WingetMaintenance also uses saved
        webhooks to report each run.

    .PARAMETER Platform
        Target platform: Discord, Slack, or Teams.

    .PARAMETER WebhookUrl
        The webhook URL. If not specified, reads from saved config.

    .PARAMETER Event
        Event type: UpdatesAvailable, MaintenanceComplete, DriftDetected,
        InstallComplete, ComplianceViolation, Custom.

    .PARAMETER Title
        Notification title (defaults to a title for the event).

    .PARAMETER Message
        Notification body/message content.

    .PARAMETER Data
        Hashtable of additional data to include in the notification.

    .PARAMETER SaveConfig
        Save the webhook URL to config for future use.

    .PARAMETER Test
        Send a test notification to verify the webhook works.

    .EXAMPLE
        Send-WingetWebhook -Platform Discord -WebhookUrl "https://discord.com/api/webhooks/..." -Event UpdatesAvailable -Data @{Count=5}
        Notify Discord that 5 updates are available.

    .EXAMPLE
        Send-WingetWebhook -Platform Slack -Event MaintenanceComplete -Message "Weekly maintenance: 12 updated, 0 failed"
        Notify Slack channel about maintenance results.

    .EXAMPLE
        Send-WingetWebhook -Platform Teams -Test
        Send a test notification to verify Teams webhook.

    .EXAMPLE
        Send-WingetWebhook -Platform Discord -SaveConfig -WebhookUrl "https://..."
        Save Discord webhook URL to config for automatic use.

    .NOTES
        Author: Matthew Bubb
        Webhook URLs are stored in ~/.wingetbatch/config.json (not encrypted).
    #>
    [CmdletBinding(DefaultParameterSetName = 'Send')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Discord', 'Slack', 'Teams')]
        [string]$Platform,

        [Parameter(ParameterSetName = 'Send')]
        [Parameter(ParameterSetName = 'Test')]
        [Parameter(ParameterSetName = 'Save', Mandatory)]
        [string]$WebhookUrl,

        [Parameter(ParameterSetName = 'Send', Mandatory)]
        [ValidateSet('UpdatesAvailable', 'MaintenanceComplete', 'DriftDetected', 'InstallComplete', 'ComplianceViolation', 'Custom')]
        [string]$Event,

        [Parameter(ParameterSetName = 'Send')]
        [string]$Title,

        [Parameter(ParameterSetName = 'Send')]
        [string]$Message,

        [Parameter(ParameterSetName = 'Send')]
        [hashtable]$Data,

        [Parameter(ParameterSetName = 'Save', Mandatory)]
        [Parameter(ParameterSetName = 'Test')]
        [switch]$SaveConfig,

        [Parameter(ParameterSetName = 'Test', Mandatory)]
        [switch]$Test
    )

    $configKey = "webhook_$($Platform.ToLower())"
    $config = Get-WingetBatchConfigData

    # --- Save config ---
    if ($SaveConfig) {
        if (-not $WebhookUrl) {
            Write-Error "-SaveConfig needs -WebhookUrl."
            return
        }
        $config[$configKey] = $WebhookUrl
        Save-WingetBatchConfigData -Config $config
        Write-Host "  $Platform webhook URL saved to config." -ForegroundColor Green
        if (-not $Test) { return }
    }

    # --- Resolve webhook URL ---
    if (-not $WebhookUrl) {
        $WebhookUrl = $config[$configKey]
    }
    if (-not $WebhookUrl) {
        Write-Error "No webhook URL for $Platform. Provide -WebhookUrl or save one with -SaveConfig."
        return
    }

    # --- Build notification content ---
    $hostname = $env:COMPUTERNAME
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $moduleVersion = (Get-Module WingetBatch).Version

    if ($Test) {
        $Event = 'Custom'
        $Title = "WingetBatch Test Notification"
        $Message = "Webhook integration is working! Sent from $hostname at $timestamp."
        $Data = @{ Platform = $Platform; Hostname = $hostname }
    }

    # Default titles/messages per event
    $eventDefaults = @{
        'UpdatesAvailable'    = @{ Title = "Updates Available"; Color = 0xFFA500; Emoji = "📦" }
        'MaintenanceComplete' = @{ Title = "Maintenance Complete"; Color = 0x00CC00; Emoji = "🔧" }
        'DriftDetected'       = @{ Title = "Configuration Drift Detected"; Color = 0xFF4444; Emoji = "⚠️" }
        'InstallComplete'     = @{ Title = "Installation Complete"; Color = 0x00AAFF; Emoji = "✅" }
        'ComplianceViolation' = @{ Title = "Compliance Violation"; Color = 0xFF0000; Emoji = "🚨" }
        'Custom'              = @{ Title = "WingetBatch Notification"; Color = 0x7289DA; Emoji = "📋" }
    }

    $defaults = $eventDefaults[$Event]
    if (-not $Title) { $Title = $defaults.Title }
    if (-not $Message) { $Message = "Event: $Event on $hostname at $timestamp" }
    $fullTitle = "$($defaults.Emoji) $Title"

    # --- Format per platform ---
    $body = $null

    switch ($Platform) {
        'Discord' {
            $fields = @()
            if ($Data) {
                foreach ($entry in $Data.GetEnumerator()) {
                    $fields += @{ name = [string]$entry.Key; value = "$($entry.Value)"; inline = $true }
                }
            }
            $fields += @{ name = "Host"; value = $hostname; inline = $true }
            $fields += @{ name = "Time"; value = $timestamp; inline = $true }

            $body = @{
                username = "WingetBatch"
                embeds   = @(@{
                    title       = $fullTitle
                    description = $Message
                    color       = $defaults.Color
                    fields      = $fields
                    footer      = @{ text = "WingetBatch v$moduleVersion | $hostname" }
                    timestamp   = (Get-Date).ToUniversalTime().ToString('o')
                })
            }
        }
        'Slack' {
            $blocks = @(
                @{ type = "header"; text = @{ type = "plain_text"; text = $fullTitle } }
                @{ type = "section"; text = @{ type = "mrkdwn"; text = $Message } }
            )

            if ($Data -and $Data.Count -gt 0) {
                $dataText = ($Data.GetEnumerator() | ForEach-Object { "*$($_.Key):* $($_.Value)" }) -join "`n"
                $blocks += @{ type = "section"; text = @{ type = "mrkdwn"; text = $dataText } }
            }

            $blocks += @{ type = "context"; elements = @(@{ type = "mrkdwn"; text = "WingetBatch v$moduleVersion | $hostname | $timestamp" }) }

            # "text" is the fallback shown in notifications
            $body = @{ text = "$fullTitle - $Message"; blocks = $blocks }
        }
        'Teams' {
            # Adaptive Card: accepted by Teams Workflows webhooks (Office 365 connectors,
            # which used the old MessageCard format, have been retired)
            $facts = @()
            if ($Data) {
                foreach ($entry in $Data.GetEnumerator()) {
                    $facts += @{ title = [string]$entry.Key; value = "$($entry.Value)" }
                }
            }
            $facts += @{ title = "Host"; value = $hostname }
            $facts += @{ title = "Time"; value = $timestamp }

            $body = @{
                type        = "message"
                attachments = @(@{
                    contentType = "application/vnd.microsoft.card.adaptive"
                    content     = @{
                        '$schema' = "http://adaptivecards.io/schemas/adaptive-card.json"
                        type      = "AdaptiveCard"
                        version   = "1.4"
                        body      = @(
                            @{ type = "TextBlock"; text = $fullTitle; weight = "Bolder"; size = "Medium"; wrap = $true }
                            @{ type = "TextBlock"; text = $Message; wrap = $true }
                            @{ type = "FactSet"; facts = $facts }
                        )
                    }
                })
            }
        }
    }

    $json = $body | ConvertTo-Json -Depth 10 -Compress

    # --- Send ---
    try {
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json; charset=utf-8' -ErrorAction Stop | Out-Null
        Write-Host "  Notification sent to $Platform ($Event)" -ForegroundColor Green
        return [PSCustomObject]@{
            Success   = $true
            Platform  = $Platform
            Event     = $Event
            Timestamp = $timestamp
        }
    }
    catch {
        Write-Error "Failed to send $Platform webhook: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Success  = $false
            Platform = $Platform
            Event    = $Event
            Error    = $_.Exception.Message
        }
    }
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

    $config = Get-WingetBatchConfigData

    if ($PSBoundParameters.ContainsKey('SearchMatchOption')) {
        $config['SearchMatchOption'] = $SearchMatchOption
    }

    Save-WingetBatchConfigData -Config $config
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

# Region: Public/Start-WingetServer.ps1
function Start-WingetServer {
    <#
    .SYNOPSIS
        Start a REST API server for remote winget package management.

    .DESCRIPTION
        Launches a Pode-based HTTP API server that exposes WingetBatch operations
        as RESTful endpoints. Enables remote package management, monitoring, and
        automation from any HTTP client, CI/CD pipeline, or management dashboard.

        Endpoints include package listing, search, install, update, uninstall,
        machine state management, and system health monitoring. All responses
        are JSON. Optional API key authentication secures the endpoints.

    .PARAMETER Port
        TCP port to listen on. Default: 8484.

    .PARAMETER ApiKey
        API key for authentication. If not specified, generates a random key
        and displays it on startup. Pass 'none' to disable authentication.

    .PARAMETER Hostname
        Hostname/IP to bind to. Default: localhost. Use '0.0.0.0' for all interfaces.

    .PARAMETER Https
        Enable HTTPS with a self-signed certificate.

    .PARAMETER OpenBrowser
        Open the API documentation page in the default browser on startup.

    .PARAMETER MaxRequestsPerMinute
        Rate limit per client IP. Default: 60. Set 0 to disable.

    .PARAMETER LogRequests
        Log all API requests to a file in the config directory.

    .EXAMPLE
        Start-WingetServer
        Starts the API on localhost:8484 with a generated API key.

    .EXAMPLE
        Start-WingetServer -Port 9000 -ApiKey "my-secret-key" -Hostname 0.0.0.0
        Starts on all interfaces, port 9000, with a custom API key.

    .EXAMPLE
        Start-WingetServer -ApiKey none -OpenBrowser
        Starts without authentication and opens docs in browser.

    .NOTES
        Author: Matthew Bubb
        Requires: Pode module (auto-installed if missing).
        API Docs: http://localhost:8484/ (when running)
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1024, 65535)]
        [int]$Port = 8484,

        [string]$ApiKey,

        [string]$Hostname = 'localhost',

        [switch]$Https,

        [switch]$OpenBrowser,

        [ValidateRange(0, 10000)]
        [int]$MaxRequestsPerMinute = 60,

        [switch]$LogRequests
    )

    # Ensure Pode is available
    if (-not (Get-Module -ListAvailable -Name Pode)) {
        Write-Host "  Installing Pode module (REST API framework)..." -ForegroundColor Cyan
        Install-WingetBatchDependency -Name Pode
    }
    Import-Module Pode -Force

    # Generate or validate API key
    if ([string]::IsNullOrEmpty($ApiKey)) {
        # Cryptographically random key (Get-Random is predictable)
        $bytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24)
        $ApiKey = [Convert]::ToBase64String($bytes).Replace('+', 'A').Replace('/', 'B').TrimEnd('=')
        Write-Host "  Generated API Key: " -NoNewline -ForegroundColor DarkGray
        Write-Host $ApiKey -ForegroundColor Yellow
        Write-Host "  (Use header: X-API-Key: $ApiKey)" -ForegroundColor DarkGray
    }
    $disableAuth = ($ApiKey -eq 'none')
    if ($Hostname -notin 'localhost', '127.0.0.1', '::1' -and -not $Https) {
        Write-Warning "Listening on $Hostname over plain HTTP: the API key and all traffic can be read on the network. Use -Https."
    }
    if ($Hostname -notin 'localhost', '127.0.0.1', '::1' -and $disableAuth) {
        Write-Warning "Authentication is disabled on a network-reachable address. Anyone who can reach port $Port can install or remove software."
    }

    # Shared across Pode's worker runspaces. $using: hands each runspace its own copy,
    # so the table lives in process-wide AppDomain data instead.
    $rateKey = "WingetBatch.RateTable.$Port"
    [System.AppDomain]::CurrentDomain.SetData($rateKey, [hashtable]::Synchronized(@{}))
    $moduleVersion = [string](Get-Module WingetBatch).Version
    $serverStart = Get-Date

    # Config
    $configDir = Get-WingetBatchConfigDir
    $logFile = if ($LogRequests) { Join-Path $configDir "server_requests.log" } else { $null }
    $protocol = if ($Https) { "https" } else { "http" }
    $baseUrl = "${protocol}://${Hostname}:$Port"

    # Banner
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║         WingetBatch API Server                      ║" -ForegroundColor Cyan
    Write-Host "  ║         Remote Package Management                   ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  URL:      " -NoNewline -ForegroundColor DarkGray; Write-Host $baseUrl -ForegroundColor White
    Write-Host "  Docs:     " -NoNewline -ForegroundColor DarkGray; Write-Host "$baseUrl/" -ForegroundColor White
    Write-Host "  Auth:     " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($disableAuth) { "Disabled" } else { "API Key (X-API-Key header)" }) -ForegroundColor White
    Write-Host "  Rate:     " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($MaxRequestsPerMinute -gt 0) { "$MaxRequestsPerMinute req/min" } else { "Unlimited" }) -ForegroundColor White
    Write-Host "  Logging:  " -NoNewline -ForegroundColor DarkGray; Write-Host $(if ($LogRequests) { $logFile } else { "Off" }) -ForegroundColor White
    Write-Host ""
    Write-Host "  Press Ctrl+C to stop the server." -ForegroundColor DarkGray
    Write-Host ""

    if ($OpenBrowser) {
        Start-Process $baseUrl
    }

    # Start Pode server. The main block runs in this scope (plain variables work there);
    # route and middleware scriptblocks run in worker runspaces and need $using:.
    Start-PodeServer -Threads 4 {
        # Listener
        if ($Https) {
            Add-PodeEndpoint -Address $Hostname -Port $Port -Protocol Https -SelfSigned
        } else {
            Add-PodeEndpoint -Address $Hostname -Port $Port -Protocol Http
        }

        # Handler errors go to ~/.wingetbatch/server_errors_*.log instead of vanishing into a 500
        New-PodeLoggingMethod -File -Name 'server_errors' -Path $configDir | Enable-PodeErrorLogging

        # Middleware: API Key auth
        if (-not $disableAuth) {
            Add-PodeMiddleware -Name 'ApiAuth' -ScriptBlock {
                $apiKey = [string](Get-PodeHeader -Name 'X-API-Key')
                # Constant-time comparison so response timing does not leak the key
                $given = [System.Text.Encoding]::UTF8.GetBytes($apiKey)
                $expected = [System.Text.Encoding]::UTF8.GetBytes([string]$using:ApiKey)
                if (-not [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals($given, $expected)) {
                    Set-PodeResponseStatus -Code 401
                    Write-PodeJsonResponse -Value @{ error = "Unauthorized"; message = "Invalid or missing X-API-Key header" }
                    return $false
                }
                return $true
            }
        }

        # Middleware: Rate limiting
        if ($MaxRequestsPerMinute -gt 0) {
            Add-PodeMiddleware -Name 'RateLimit' -ScriptBlock {
                $clientIp = $WebEvent.Request.RemoteEndPoint.Address.IPAddressToString
                $key = "rate_$clientIp"
                $now = Get-Date
                $window = $now.AddMinutes(-1)

                $table = [System.AppDomain]::CurrentDomain.GetData($using:rateKey)
                [System.Threading.Monitor]::Enter($table.SyncRoot)
                try {
                    if (-not $table.ContainsKey($key)) { $table[$key] = [System.Collections.Generic.List[datetime]]::new() }
                    $hits = $table[$key]
                    [void]$hits.RemoveAll([Predicate[datetime]] { param($t) $t -lt $window })
                    if ($hits.Count -ge $using:MaxRequestsPerMinute) {
                        Set-PodeResponseStatus -Code 429
                        Write-PodeJsonResponse -Value @{ error = "Rate limit exceeded"; retry_after_seconds = 60 }
                        return $false
                    }
                    $hits.Add($now)
                    Add-PodeHeader -Name 'X-RateLimit-Remaining' -Value ([string]($using:MaxRequestsPerMinute - $hits.Count))
                }
                finally {
                    [System.Threading.Monitor]::Exit($table.SyncRoot)
                }
                return $true
            }
        }

        # Middleware: Request logging
        if ($logFile) {
            Add-PodeMiddleware -Name 'RequestLog' -ScriptBlock {
                $entry = "$(Get-Date -Format 'o') | $($WebEvent.Request.HttpMethod) $($WebEvent.Request.Url.PathAndQuery) | $($WebEvent.Request.RemoteEndPoint.Address)"
                Add-Content -Path $using:logFile -Value $entry
                return $true
            }
        }

        # --- ROUTES ---

        # GET / - API documentation
        Add-PodeRoute -Method Get -Path '/' -ScriptBlock {
            Write-PodeJsonResponse -Value @{
                name = "WingetBatch API"
                version = $using:moduleVersion
                description = "REST API for remote winget package management"
                endpoints = @(
                    @{ method = "GET"; path = "/api/health"; description = "Server health check" }
                    @{ method = "GET"; path = "/api/packages"; description = "List installed packages" }
                    @{ method = "GET"; path = "/api/packages/:id"; description = "Get package details" }
                    @{ method = "GET"; path = "/api/search?q=query"; description = "Search winget source" }
                    @{ method = "POST"; path = "/api/packages/install"; description = "Install package(s)" }
                    @{ method = "POST"; path = "/api/packages/uninstall"; description = "Uninstall package(s)" }
                    @{ method = "GET"; path = "/api/updates"; description = "List available updates" }
                    @{ method = "POST"; path = "/api/updates/apply"; description = "Apply all updates" }
                    @{ method = "GET"; path = "/api/state"; description = "Get machine state" }
                    @{ method = "POST"; path = "/api/state/export"; description = "Export machine state" }
                    @{ method = "GET"; path = "/api/history"; description = "Installation history" }
                    @{ method = "GET"; path = "/api/stats"; description = "Package statistics" }
                )
                auth = if ($using:disableAuth) { "none" } else { "X-API-Key header" }
            }
        }

        # GET /api/health
        Add-PodeRoute -Method Get -Path '/api/health' -ScriptBlock {
            $wingetOk = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
            $comOk = $null -ne (Get-Module -ListAvailable Microsoft.WinGet.Client)
            Write-PodeJsonResponse -Value @{
                status = "healthy"
                timestamp = (Get-Date).ToString('o')
                hostname = $env:COMPUTERNAME
                winget_cli = $wingetOk
                winget_com = $comOk
                module_version = $using:moduleVersion
                uptime_seconds = [int]((Get-Date) - $using:serverStart).TotalSeconds
            }
        }

        # GET /api/packages
        Add-PodeRoute -Method Get -Path '/api/packages' -ScriptBlock {
            $source = $WebEvent.Query['source']
            $packages = Microsoft.WinGet.Client\Get-WinGetPackage
            if ($source) { $packages = $packages | Where-Object { $_.Source -eq $source } }
            Write-PodeJsonResponse -Value @{
                count = $packages.Count
                packages = @($packages | ForEach-Object {
                    @{ id = $_.Id; name = $_.Name; version = $_.InstalledVersion; source = $_.Source; update_available = [bool]$_.IsUpdateAvailable; available = @($_.AvailableVersions)[0] }
                })
            }
        }

        # GET /api/packages/:id
        Add-PodeRoute -Method Get -Path '/api/packages/:id' -ScriptBlock {
            $id = $WebEvent.Parameters['id']
            $pkg = Microsoft.WinGet.Client\Get-WinGetPackage -Id $id -MatchOption EqualsCaseInsensitive -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $pkg) {
                Set-PodeResponseStatus -Code 404
                Write-PodeJsonResponse -Value @{ error = "Not found"; message = "Package '$id' is not installed" }
                return
            }
            Write-PodeJsonResponse -Value @{
                id = $pkg.Id; name = $pkg.Name; installed_version = $pkg.InstalledVersion
                available_versions = $pkg.AvailableVersions; source = $pkg.Source
                update_available = [bool]$pkg.IsUpdateAvailable
            }
        }

        # GET /api/search
        Add-PodeRoute -Method Get -Path '/api/search' -ScriptBlock {
            $query = $WebEvent.Query['q']
            if (-not $query) {
                Set-PodeResponseStatus -Code 400
                Write-PodeJsonResponse -Value @{ error = "Bad request"; message = "Query parameter 'q' is required" }
                return
            }
            $limit = if ($WebEvent.Query['limit']) { [int]$WebEvent.Query['limit'] } else { 25 }
            $results = Microsoft.WinGet.Client\Find-WinGetPackage -Query $query -Count $limit
            Write-PodeJsonResponse -Value @{
                query = $query; count = $results.Count
                results = @($results | ForEach-Object {
                    @{ id = $_.Id; name = $_.Name; version = $_.Version; source = $_.Source }
                })
            }
        }

        # POST /api/packages/install
        Add-PodeRoute -Method Post -Path '/api/packages/install' -ScriptBlock {
            $body = $WebEvent.Data
            $ids = @(if ($body.packages) { $body.packages } elseif ($body.id) { $body.id })
            if (-not $ids -or $ids.Count -eq 0) {
                Set-PodeResponseStatus -Code 400
                Write-PodeJsonResponse -Value @{ error = "Bad request"; message = "Provide 'packages' array or 'id' field" }
                return
            }
            $results = @()
            foreach ($id in $ids) {
                try {
                    $r = @(Microsoft.WinGet.Client\Install-WinGetPackage -Id $id -MatchOption EqualsCaseInsensitive -Mode Silent -ErrorAction Stop)[-1]
                    if ([string]$r.Status -eq 'Ok') { $results += @{ id = $id; status = "installed"; reboot_required = [bool]$r.RebootRequired } }
                    else { $results += @{ id = $id; status = "failed"; error = [string]$r.Status } }
                } catch {
                    $results += @{ id = $id; status = "failed"; error = $_.Exception.Message }
                }
            }
            Write-PodeJsonResponse -Value @{ installed = @($results | Where-Object { $_.status -eq 'installed' }).Count; failed = @($results | Where-Object { $_.status -eq 'failed' }).Count; results = $results }
        }

        # POST /api/packages/uninstall
        Add-PodeRoute -Method Post -Path '/api/packages/uninstall' -ScriptBlock {
            $body = $WebEvent.Data
            $ids = @(if ($body.packages) { $body.packages } elseif ($body.id) { $body.id })
            if (-not $ids -or $ids.Count -eq 0) {
                Set-PodeResponseStatus -Code 400
                Write-PodeJsonResponse -Value @{ error = "Bad request"; message = "Provide 'packages' array or 'id' field" }
                return
            }
            $results = @()
            foreach ($id in $ids) {
                try {
                    $r = @(Microsoft.WinGet.Client\Uninstall-WinGetPackage -Id $id -MatchOption EqualsCaseInsensitive -Mode Silent -ErrorAction Stop)[-1]
                    if ([string]$r.Status -eq 'Ok') { $results += @{ id = $id; status = "uninstalled" } }
                    else { $results += @{ id = $id; status = "failed"; error = [string]$r.Status } }
                } catch {
                    $results += @{ id = $id; status = "failed"; error = $_.Exception.Message }
                }
            }
            Write-PodeJsonResponse -Value @{ uninstalled = @($results | Where-Object { $_.status -eq 'uninstalled' }).Count; failed = @($results | Where-Object { $_.status -eq 'failed' }).Count; results = $results }
        }

        # GET /api/updates
        Add-PodeRoute -Method Get -Path '/api/updates' -ScriptBlock {
            $updates = @(Get-WingetUpdates -ListOnly -Force)
            Write-PodeJsonResponse -Value @{
                count = $updates.Count
                updates = @($updates | ForEach-Object {
                    @{ id = $_.Id; name = $_.Name; installed = $_.InstalledVersion; available = $_.AvailableVersion; source = $_.Source }
                })
            }
        }

        # POST /api/updates/apply
        Add-PodeRoute -Method Post -Path '/api/updates/apply' -ScriptBlock {
            $body = $WebEvent.Data
            $ids = $body.packages  # Optional: specific packages, else all
            $updates = @(Get-WingetUpdates -ListOnly -Force)
            if ($ids) { $updates = @($updates | Where-Object { $_.Id -in $ids }) }

            $results = @()
            foreach ($pkg in $updates) {
                try {
                    $upd = @{ Id = $pkg.Id; MatchOption = 'EqualsCaseInsensitive'; Mode = 'Silent'; ErrorAction = 'Stop' }
                    if ($pkg.Source) { $upd['Source'] = $pkg.Source }
                    $r = @(Microsoft.WinGet.Client\Update-WinGetPackage @upd)[-1]
                    if ([string]$r.Status -eq 'Ok') { $results += @{ id = $pkg.Id; status = "updated"; version = $pkg.AvailableVersion; reboot_required = [bool]$r.RebootRequired } }
                    else { $results += @{ id = $pkg.Id; status = "failed"; error = [string]$r.Status } }
                } catch {
                    $results += @{ id = $pkg.Id; status = "failed"; error = $_.Exception.Message }
                }
            }
            Write-PodeJsonResponse -Value @{ updated = @($results | Where-Object { $_.status -eq 'updated' }).Count; failed = @($results | Where-Object { $_.status -eq 'failed' }).Count; results = $results }
        }

        # GET /api/state
        Add-PodeRoute -Method Get -Path '/api/state' -ScriptBlock {
            $packages = Microsoft.WinGet.Client\Get-WinGetPackage
            Write-PodeJsonResponse -Value @{
                hostname = $env:COMPUTERNAME
                timestamp = (Get-Date).ToString('o')
                total_packages = $packages.Count
                by_source = ($packages | Group-Object Source | ForEach-Object { @{ source = $_.Name; count = $_.Count } })
                packages = @($packages | ForEach-Object { @{ id = $_.Id; name = $_.Name; version = $_.InstalledVersion } })
            }
        }

        # POST /api/state/export
        Add-PodeRoute -Method Post -Path '/api/state/export' -ScriptBlock {
            $body = $WebEvent.Data
            $format = if ($body.format -eq 'yaml') { 'YAML' } else { 'JSON' }
            $tempPath = Join-Path $env:TEMP "wingetbatch_state_$([guid]::NewGuid().ToString('N')).$($format.ToLower())"
            try {
                Get-WingetMachineState -Export -Path $tempPath -Format $format 6>$null
                $content = Get-Content $tempPath -Raw
                Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                $parsed = if ($format -eq 'JSON') { $content | ConvertFrom-Json } else { $content }
                Write-PodeJsonResponse -Value @{ status = "exported"; format = $format; content = $parsed }
            } catch {
                Set-PodeResponseStatus -Code 500
                Write-PodeJsonResponse -Value @{ error = "Export failed"; message = $_.Exception.Message }
            }
        }

        # GET /api/history
        Add-PodeRoute -Method Get -Path '/api/history' -ScriptBlock {
            $days = if ($WebEvent.Query['days']) { [int]$WebEvent.Query['days'] } else { 30 }
            $history = @(Get-WingetHistory -Days $days -PassThru)
            Write-PodeJsonResponse -Value @{
                days = $days; count = $history.Count
                entries = @($history | ForEach-Object {
                    @{ name = $_.Name; publisher = $_.Publisher; version = $_.Version; date = $_.Date.ToString('yyyy-MM-dd'); action = $_.Action; scope = $_.Scope }
                })
            }
        }

        # GET /api/stats
        Add-PodeRoute -Method Get -Path '/api/stats' -ScriptBlock {
            $packages = @(Microsoft.WinGet.Client\Get-WinGetPackage)
            Write-PodeJsonResponse -Value @{
                total_installed = $packages.Count
                updates_available = @($packages | Where-Object { $_.IsUpdateAvailable }).Count
                sources = @($packages | Group-Object Source | ForEach-Object { @{ name = $_.Name; count = $_.Count } })
                top_publishers = @($packages | Group-Object { ($_.Id -split '\.')[0] } | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ publisher = $_.Name; count = $_.Count } })
            }
        }
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
        It prints the last known update count straight away, then refreshes the list in a background job and pops a
        Windows notification if any updates are found. Results are cached so Get-WingetUpdates can show them instantly.
        It respects the interval set in the configuration.

    .PARAMETER Force
        Ignore the configured check interval and check immediately.
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    $configDir = Get-WingetBatchConfigDir
    $config = Get-WingetBatchConfigData
    if (-not $config['UpdateNotificationsEnabled']) {
        return
    }

    $cacheFile = Join-Path $configDir "update_cache.json"

    # Show what we already know without waiting for a new check
    if (Test-Path $cacheFile) {
        try {
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
            $count = if ($null -ne $cache.UpdateCount) { [int]$cache.UpdateCount } else { @($cache.Updates).Count }
            if ($count -gt 0) {
                Write-Host "$count winget package update(s) available - run " -ForegroundColor Yellow -NoNewline
                Write-Host "Get-WingetUpdates" -ForegroundColor White
            }
        }
        catch { }
    }

    if (-not $Force) {
        if ($config['LastCheck']) {
            try {
                $lastCheckTime = [datetime]$config['LastCheck']
                $interval = [double]$config['CheckInterval']
                if ($interval -gt 0 -and (Get-Date) -lt $lastCheckTime.AddHours($interval)) {
                    return
                }
                if ($interval -le 0 -and -not $config['CheckOnStartup']) {
                    return
                }
            } catch {
                # Invalid date format, just proceed
            }
        } elseif (-not $config['CheckOnStartup']) {
            # First run with startup checks disabled: start the interval clock now
            $config['LastCheck'] = (Get-Date).ToString("o")
            Save-WingetBatchConfigData -Config $config
            return
        }
    }

    # Update LastCheck immediately to prevent multiple rapid checks from multiple terminal sessions
    $config['LastCheck'] = (Get-Date).ToString("o")
    Save-WingetBatchConfigData -Config $config

    $jobScript = {
        param($CacheFile)
        try {
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            $updates = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction Stop | Where-Object { $_.IsUpdateAvailable } | ForEach-Object {
                [PSCustomObject]@{
                    Id               = $_.Id
                    Name             = $_.Name
                    InstalledVersion = $_.InstalledVersion
                    AvailableVersion = @($_.AvailableVersions)[0]
                    Source           = $_.Source
                }
            })

            # Same format Get-WingetUpdates reads, so it can skip its own scan
            @{
                LastChecked = (Get-Date).ToString('o')
                UpdateCount = $updates.Count
                Updates     = $updates
            } | ConvertTo-Json -Depth 5 | Set-Content -Path $CacheFile -Encoding UTF8

            if ($updates.Count -gt 0) {
                $names = @($updates | Select-Object -First 3 | ForEach-Object { if ($_.Name) { $_.Name } else { $_.Id } })
                $pkgText = $names -join ", "
                if ($updates.Count -gt 3) {
                    $pkgText += " and $($updates.Count - 3) more"
                }

                Add-Type -AssemblyName System.Windows.Forms
                Add-Type -AssemblyName System.Drawing
                $balloon = New-Object System.Windows.Forms.NotifyIcon
                $balloon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -Id $PID).Path)
                $balloon.BalloonTipIcon = "Info"
                $balloon.BalloonTipTitle = "Winget Updates Available ($($updates.Count))"
                $balloon.BalloonTipText = "Updates available for: $pkgText.`nRun 'Get-WingetUpdates' to install."
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
    Start-Job -ScriptBlock $jobScript -ArgumentList (Join-Path $configDir "update_cache.json") -Name "WingetUpdateCheck" | Out-Null
}

# EndRegion

# Region: Public/Test-WingetCompliance.ps1
function Test-WingetCompliance {
    <#
    .SYNOPSIS
        Test machine package compliance against policy definitions.

    .DESCRIPTION
        Enterprise-lite policy enforcement for winget packages. Define required
        packages, banned packages, and version floors in a policy file, then
        test any machine for compliance. Returns structured pass/fail results
        with detailed violation reporting.

        Supports auto-remediation: install missing required packages and
        uninstall banned ones with a single switch.

    .PARAMETER PolicyPath
        Path to a policy definition file (JSON or YAML).

    .PARAMETER RequiredPackages
        Inline array of required package IDs (must be installed).

    .PARAMETER BannedPackages
        Inline array of banned package IDs (must NOT be installed).

    .PARAMETER VersionFloors
        Hashtable of package ID -> minimum version (e.g., @{'Git.Git'='2.40.0'}).

    .PARAMETER Remediate
        Automatically fix violations: install missing required, uninstall banned.

    .PARAMETER ExportReport
        Save compliance report to a JSON file.

    .PARAMETER Strict
        Fail on ANY violation (default: report all but exit 0 unless -Strict).

    .PARAMETER NewPolicy
        Generate a policy template file from current installed packages.

    .EXAMPLE
        Test-WingetCompliance -PolicyPath ".\company-policy.json"
        Tests compliance against a shared policy file.

    .EXAMPLE
        Test-WingetCompliance -RequiredPackages "Git.Git","Python.Python.3.12" -BannedPackages "TikTok.TikTok"
        Quick inline compliance check.

    .EXAMPLE
        Test-WingetCompliance -PolicyPath ".\policy.json" -Remediate
        Test and auto-fix all violations.

    .EXAMPLE
        Test-WingetCompliance -NewPolicy -PolicyPath ".\baseline-policy.json"
        Generate a policy template from current machine state.

    .NOTES
        Author: Matthew Bubb
        Policy format: JSON with 'required', 'banned', 'version_floors' arrays.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Inline')]
    param(
        [Parameter(ParameterSetName = 'File', Mandatory)]
        [Parameter(ParameterSetName = 'Generate')]
        [string]$PolicyPath,

        [Parameter(ParameterSetName = 'Inline')]
        [string[]]$RequiredPackages,

        [Parameter(ParameterSetName = 'Inline')]
        [string[]]$BannedPackages,

        [Parameter(ParameterSetName = 'Inline')]
        [hashtable]$VersionFloors,

        [switch]$Remediate,

        [string]$ExportReport,

        [switch]$Strict,

        [Parameter(ParameterSetName = 'Generate', Mandatory)]
        [switch]$NewPolicy
    )

    $configDir = Get-WingetBatchConfigDir

    # --- GENERATE POLICY TEMPLATE ---
    if ($NewPolicy) {
        $packages = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
        $policy = @{
            name = "Machine Baseline Policy"
            version = "1.0"
            created = (Get-Date).ToString('o')
            description = "Generated from $($env:COMPUTERNAME) on $(Get-Date -Format 'yyyy-MM-dd')"
            required = @($packages | Where-Object { $_.Source } | ForEach-Object { $_.Id } | Sort-Object)
            banned = @()
            version_floors = @{}
        }

        $outPath = if ($PolicyPath) { $PolicyPath } else { Join-Path $configDir "compliance_policy.json" }
        $policy | ConvertTo-Json -Depth 5 | Set-Content -Path $outPath -Encoding UTF8
        Write-Host ""
        Write-Host "  ✓ Policy template generated: $outPath" -ForegroundColor Green
        Write-Host "    $($policy.required.Count) packages marked as required." -ForegroundColor DarkGray
        Write-Host "    Edit 'banned' and 'version_floors' to customize." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # --- LOAD POLICY ---
    $required = @()
    $banned = @()
    $floors = @{}

    if ($PolicyPath) {
        if (-not (Test-Path $PolicyPath)) {
            Write-Error "Policy file not found: $PolicyPath"
            return
        }
        # Plain PSCustomObject: property access is case-insensitive ('required' or 'Required')
        $policy = Get-Content -Path $PolicyPath -Raw | ConvertFrom-Json
        $required = @($policy.required | Where-Object { $_ })
        $banned = @($policy.banned | Where-Object { $_ })
        $floors = @{}
        if ($policy.version_floors) {
            foreach ($prop in $policy.version_floors.PSObject.Properties) { $floors[$prop.Name] = [string]$prop.Value }
        }
        $policyName = if ($policy.name) { $policy.name } else { Split-Path $PolicyPath -Leaf }
    } else {
        $required = $RequiredPackages ?? @()
        $banned = $BannedPackages ?? @()
        $floors = $VersionFloors ?? @{}
        $policyName = "Inline Policy"
    }

    if ($required.Count -eq 0 -and $banned.Count -eq 0 -and $floors.Count -eq 0) {
        Write-Host "  No policy rules defined. Nothing to check." -ForegroundColor Yellow
        return
    }

    # --- GET INSTALLED PACKAGES ---
    $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
    $installedMap = @{}
    $sourceMap = @{}
    foreach ($pkg in $installed) {
        $installedMap[$pkg.Id] = $pkg.InstalledVersion
        $sourceMap[$pkg.Id] = $pkg.Source
    }

    # --- EVALUATE COMPLIANCE ---
    $violations = [System.Collections.Generic.List[hashtable]]::new()
    $compliant = [System.Collections.Generic.List[hashtable]]::new()

    # Check required
    foreach ($id in $required) {
        if ($installedMap.ContainsKey($id)) {
            $compliant.Add(@{ Rule = 'Required'; PackageId = $id; Status = 'Pass'; Detail = "Installed ($($installedMap[$id]))" })
        } else {
            $violations.Add(@{ Rule = 'Required'; PackageId = $id; Status = 'Fail'; Detail = 'Not installed'; Remediation = 'Install' })
        }
    }

    # Check banned
    foreach ($id in $banned) {
        if ($installedMap.ContainsKey($id)) {
            $violations.Add(@{ Rule = 'Banned'; PackageId = $id; Status = 'Fail'; Detail = "Installed ($($installedMap[$id])) but prohibited"; Remediation = 'Uninstall' })
        } else {
            $compliant.Add(@{ Rule = 'Banned'; PackageId = $id; Status = 'Pass'; Detail = 'Not installed (correct)' })
        }
    }

    # Check version floors
    foreach ($entry in $floors.GetEnumerator()) {
        $id = $entry.Key
        $minVersion = $entry.Value
        if (-not $installedMap.ContainsKey($id)) {
            $violations.Add(@{ Rule = 'VersionFloor'; PackageId = $id; Status = 'Fail'; Detail = "Not installed (requires >= $minVersion)"; Remediation = 'Install' })
        } else {
            $currentVer = $installedMap[$id]
            $isCompliant = (Compare-WingetVersion -ReferenceVersion $currentVer -DifferenceVersion $minVersion) -ge 0
            if ($isCompliant) {
                $compliant.Add(@{ Rule = 'VersionFloor'; PackageId = $id; Status = 'Pass'; Detail = "$currentVer >= $minVersion" })
            } else {
                $violations.Add(@{ Rule = 'VersionFloor'; PackageId = $id; Status = 'Fail'; Detail = "$currentVer < $minVersion"; Remediation = 'Update' })
            }
        }
    }

    # --- OUTPUT ---
    $totalChecks = $violations.Count + $compliant.Count
    $isCompliant = $violations.Count -eq 0

    Write-Host ""
    if ($isCompliant) {
        Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "  ║          ✓ COMPLIANT                           ║" -ForegroundColor Green
        Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Green
    } else {
        Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "  ║          ✗ NON-COMPLIANT                       ║" -ForegroundColor Red
        Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  Policy:   " -NoNewline -ForegroundColor DarkGray; Write-Host $policyName -ForegroundColor White
    Write-Host "  Checks:   " -NoNewline -ForegroundColor DarkGray; Write-Host "$totalChecks ($($compliant.Count) pass, $($violations.Count) fail)" -ForegroundColor White
    Write-Host ""

    # Show violations
    if ($violations.Count -gt 0) {
        Write-Host "  Violations:" -ForegroundColor Red
        foreach ($v in $violations) {
            $icon = switch ($v.Rule) { 'Required' { '!' }; 'Banned' { '⊘' }; 'VersionFloor' { '↑' } }
            Write-Host "    $icon " -NoNewline -ForegroundColor Red
            Write-Host "$($v.PackageId)" -NoNewline -ForegroundColor White
            Write-Host " [$($v.Rule)] " -NoNewline -ForegroundColor DarkGray
            Write-Host "— $($v.Detail)" -ForegroundColor Red
        }
        Write-Host ""
    }

    # Show passing (verbose)
    if ($VerbosePreference -ne 'SilentlyContinue' -and $compliant.Count -gt 0) {
        Write-Host "  Passing:" -ForegroundColor Green
        foreach ($c in $compliant | Select-Object -First 20) {
            Write-Host "    ✓ $($c.PackageId) — $($c.Detail)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    # --- REMEDIATE ---
    if ($Remediate -and $violations.Count -gt 0) {
        Write-Host "  Remediating $($violations.Count) violations..." -ForegroundColor Cyan
        Write-Host ""

        Invoke-WingetAutoSnapshot -Reason 'Test-WingetCompliance -Remediate'
        $fixed = 0
        foreach ($v in $violations) {
            $label = switch ($v.Remediation) { 'Install' { '+ Installing' } 'Uninstall' { '- Uninstalling' } 'Update' { '^ Updating' } }
            Write-Host "    $label $($v.PackageId)..." -NoNewline -ForegroundColor Cyan
            $r = Invoke-WingetPackageAction -Action $v.Remediation -Id $v.PackageId -Source $sourceMap[$v.PackageId] -Options @{ Mode = 'Silent' }
            if ($r.Succeeded) {
                Write-Host " [OK]" -ForegroundColor Green
                $fixed++
            } else {
                Write-Host " [FAIL] $($r.Message)" -ForegroundColor Red
            }
        }
        Write-Host ""
        Write-Host "  Fixed $fixed of $($violations.Count) violation(s)." -ForegroundColor $(if ($fixed -eq $violations.Count) { 'Green' } else { 'Yellow' })
        Write-Host ""
        Write-Host "  Remediation complete. Re-run to verify compliance." -ForegroundColor Cyan
        Write-Host ""
    }

    # --- EXPORT ---
    if ($ExportReport) {
        $report = @{
            Timestamp = (Get-Date).ToString('o')
            Hostname = $env:COMPUTERNAME
            Policy = $policyName
            Compliant = $isCompliant
            TotalChecks = $totalChecks
            PassCount = $compliant.Count
            FailCount = $violations.Count
            Violations = $violations
            Passing = $compliant
        }
        $report | ConvertTo-Json -Depth 5 | Set-Content -Path $ExportReport -Encoding UTF8
        Write-Host "  Report saved: $ExportReport" -ForegroundColor Green
    }

    # --- RETURN ---
    $result = [PSCustomObject]@{
        Compliant = $isCompliant
        Policy = $policyName
        TotalChecks = $totalChecks
        PassCount = $compliant.Count
        FailCount = $violations.Count
        Violations = $violations | ForEach-Object { [PSCustomObject]$_ }
    }

    if ($Strict -and -not $isCompliant) {
        Write-Error "COMPLIANCE FAILURE: $($violations.Count) violations detected (Strict mode)."
    }

    return $result
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
    $before = (Get-Module WingetBatch).Version
    Install-WingetBatchDependency -Name WingetBatch -Update
    $after = (Get-Module -ListAvailable WingetBatch | Sort-Object Version -Descending | Select-Object -First 1).Version
    if ($after -le $before) {
        Write-Host "WingetBatch is already up to date (v$before)." -ForegroundColor Green
        return
    }
    Write-Host "Installed v$after. Run 'Import-Module WingetBatch -Force' or open a new terminal to use it." -ForegroundColor Cyan
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
                $data['WingetVersion'] = (Microsoft.WinGet.Client\Get-WinGetVersion -ErrorAction Stop).ToString()
                $data['WingetHealthy'] = $true
            } catch {
                $data['WingetVersion'] = 'N/A'
                $data['WingetHealthy'] = $false
            }

            # Installed packages
            $installed = @(Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue)
            $data['TotalPackages'] = if ($installed) { $installed.Count } else { 0 }

            # Updates available
            $updates = @()
            if ($installed) {
                $updates = @($installed | Where-Object { $_.IsUpdateAvailable })
            }
            $data['UpdatesAvailable'] = $updates.Count
            $data['UpdateList'] = $updates | Select-Object -First 10 Id, Name, InstalledVersion, @{ Name = 'AvailableVersion'; Expression = { @($_.AvailableVersions)[0] } }

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
            $indexAge = Get-WingetSourceIndexAge
            if ($null -ne $indexAge) {
                $data['IndexAge'] = if ($indexAge.TotalHours -lt 48) { "$([Math]::Floor($indexAge.TotalHours))h ago" } else { "$([Math]::Floor($indexAge.TotalDays))d ago" }
                $data['IndexStale'] = $indexAge.TotalDays -gt 7
            } else {
                $data['IndexAge'] = 'Unknown'
                $data['IndexStale'] = $null
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

            # Clear screen between refreshes (not possible when output is redirected, e.g. -Once in CI)
            if (-not $Once -and -not [Console]::IsOutputRedirected) {
                try { [Console]::Clear() } catch { }
            }

            $width = 62
            $border = '═' * $width

            # One boxed row made of colored segments, padded to the box width
            function Write-Row {
                param([object[]]$Parts = @())
                Write-Host "  ║" -ForegroundColor Cyan -NoNewline
                $len = 0
                for ($i = 0; $i -lt $Parts.Count; $i += 2) {
                    $text = [string]$Parts[$i]
                    $room = $width - $len
                    if ($room -le 0) { break }
                    if ($text.Length -gt $room) { $text = $text.Substring(0, [Math]::Max(0, $room - 3)) + '...' }
                    Write-Host $text -ForegroundColor $Parts[$i + 1] -NoNewline
                    $len += $text.Length
                }
                Write-Host (' ' * [Math]::Max(0, $width - $len)) -NoNewline
                Write-Host "║" -ForegroundColor Cyan
            }

            Write-Host ""
            Write-Host "  ╔$border╗" -ForegroundColor Cyan
            Write-Row @('  WINGETBATCH LIVE DASHBOARD', 'White')
            Write-Row @("  Last refresh: $($data.Timestamp.ToString('HH:mm:ss'))", 'DarkGray')
            Write-Host "  ╠$border╣" -ForegroundColor Cyan

            # System Health
            Write-Row @('  SYSTEM HEALTH', 'Yellow')
            $ver = ([string]$data.WingetVersion).TrimStart('v')
            if ($data.WingetHealthy) { Write-Row @('    Winget Engine:    ', 'Gray', "[OK] v$ver", 'Green') }
            else { Write-Row @('    Winget Engine:    ', 'Gray', '[!!] unavailable', 'Red') }
            $indexStatus = if ($null -eq $data.IndexStale) { "[?]" } elseif ($data.IndexStale) { "[STALE]" } else { "[FRESH]" }
            Write-Row @('    Source Index:     ', 'Gray', "$indexStatus ($($data.IndexAge))", $(if ($data.IndexStale) { 'Yellow' } else { 'Green' }))
            Write-Row @('    GitHub API:       ', 'Gray', $(if ($data.GitHubAuth) { '[AUTHENTICATED]' } else { '[ANONYMOUS]' }), $(if ($data.GitHubAuth) { 'Green' } else { 'DarkGray' }))
            Write-Row

            # Package Stats
            Write-Row @('  PACKAGE STATISTICS', 'Yellow')
            Write-Row @('    Total Installed:  ', 'Gray', "$($data.TotalPackages)", 'White')
            Write-Row @('    Updates Pending:  ', 'Gray', "$($data.UpdatesAvailable)", $(if ($data.UpdatesAvailable -gt 0) { 'Yellow' } else { 'Green' }))
            Write-Row @('    Recent (7 days):  ', 'Gray', "$($data.RecentInstalls)", 'White')
            Write-Row

            # Source Breakdown
            Write-Row @('  SOURCE BREAKDOWN', 'Yellow')
            foreach ($src in $data.Sources.Keys | Sort-Object) {
                $srcColor = if ($src -eq 'msstore') { 'Magenta' } elseif ($src -eq 'winget') { 'Cyan' } else { 'Gray' }
                $label = if ($src -eq 'unknown') { 'no source (ARP/MSIX)' } else { $src }
                Write-Row @('    ', 'Gray', $label, $srcColor, ": $($data.Sources[$src])", 'White')
            }
            Write-Row

            # Pending Updates (top 5)
            if ($data.UpdatesAvailable -gt 0) {
                Write-Row @('  PENDING UPDATES (top 5)', 'Yellow')
                foreach ($upd in @($data.UpdateList) | Select-Object -First 5) {
                    Write-Row @("    $($upd.Id): $($upd.InstalledVersion) -> $($upd.AvailableVersion)", 'DarkGray')
                }
                if ($data.UpdatesAvailable -gt 5) {
                    Write-Row @("    ... and $($data.UpdatesAvailable - 5) more", 'DarkGray')
                }
                Write-Row
            }

            # Footer
            Write-Host "  ╠$border╣" -ForegroundColor Cyan
            $footer = if ($Once) { "  Get-WingetUpdates to install updates" } else { "  Refresh: ${RefreshInterval}s | Ctrl+C to exit | Get-WingetUpdates" }
            Write-Row @($footer, 'DarkGray')
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

