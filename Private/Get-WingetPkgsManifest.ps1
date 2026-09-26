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
