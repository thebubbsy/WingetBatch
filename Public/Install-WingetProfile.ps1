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
                'Python.Python.3.12', 'Docker.DockerDesktop', 'Microsoft.DotNet.SDK.8',
                'GoLang.Go', 'PostgreSQL.PostgreSQL', 'Redis.Redis',
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
                'Python.Python.3.12', 'Anaconda.Anaconda3', 'RProject.R',
                'RStudio.RStudio.OpenSource', 'Microsoft.VisualStudioCode',
                'Git.Git', 'Docker.DockerDesktop', 'PostgreSQL.PostgreSQL',
                'Julia.Julia', 'Microsoft.PowerBI'
            )
        }
        'DevOps' = @{
            Name = "DevOps & Platform Engineering"
            Description = "Infrastructure, containers, cloud CLIs, monitoring"
            Author = "WingetBatch"
            Packages = @(
                'Git.Git', 'Docker.DockerDesktop', 'Kubernetes.kubectl',
                'Hashicorp.Terraform', 'Helm.Helm', 'Microsoft.AzureCLI',
                'Amazon.AWSCLI', 'Python.Python.3.12', 'Microsoft.VisualStudioCode',
                'Grafana.Grafana', 'WiresharkFoundation.Wireshark', 'PuTTY.PuTTY'
            )
        }
        'Designer' = @{
            Name = "Creative & Design"
            Description = "Image editing, vector art, 3D, and video"
            Author = "WingetBatch"
            Packages = @(
                'Figma.Figma', 'GIMP.GIMP', 'Inkscape.Inkscape',
                'BlenderFoundation.Blender', 'DaVinciResolve.DaVinciResolve',
                'Audacity.Audacity', 'OBSProject.OBSStudio', 'VideoLAN.VLC',
                'Git.Git', '7zip.7zip'
            )
        }
        'Security' = @{
            Name = "Security Research Lab"
            Description = "Network analysis, RE tools, and lab infrastructure"
            Author = "WingetBatch"
            Packages = @(
                'WiresharkFoundation.Wireshark', 'Nmap.Nmap', 'Python.Python.3.12',
                'Oracle.VirtualBox', 'Ghidra.Ghidra', 'GnuPG.GnuPG',
                'KeePassXCTeam.KeePassXC', 'Git.Git', 'Microsoft.VisualStudioCode',
                'Docker.DockerDesktop', 'Tor.TorBrowser'
            )
        }
        'Productivity' = @{
            Name = "Productivity & Office"
            Description = "Communication, notes, and workflow tools"
            Author = "WingetBatch"
            Packages = @(
                'Mozilla.Firefox', 'Obsidian.Obsidian', 'Microsoft.Teams',
                'Slack.Slack', 'Zoom.Zoom', 'ShareX.ShareX',
                '7zip.7zip', 'VideoLAN.VLC', 'Notion.Notion', 'Todoist.Todoist'
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
        foreach ($profile in $builtInProfiles.GetEnumerator() | Sort-Object Key) {
            Write-Host "  $($profile.Key.PadRight(14))" -NoNewline -ForegroundColor Yellow
            Write-Host " $($profile.Value.Name)" -NoNewline -ForegroundColor White
            Write-Host " ($($profile.Value.Packages.Count) pkgs)" -ForegroundColor DarkGray
            Write-Host "  $(''.PadRight(14)) $($profile.Value.Description)" -ForegroundColor DarkGray
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
        $profile = @{
            name = "My Setup - $env:COMPUTERNAME"
            description = "Exported from $($env:COMPUTERNAME) on $(Get-Date -Format 'yyyy-MM-dd')"
            author = $env:USERNAME
            created = (Get-Date -ToString 'o')
            packages = @($installed | ForEach-Object { $_.Id } | Sort-Object)
        }
        $profile | ConvertTo-Json -Depth 5 | Set-Content -Path $ExportPath -Encoding UTF8
        Write-Host ""
        Write-Host "  ✓ Profile exported: $ExportPath" -ForegroundColor Green
        Write-Host "    $($profile.packages.Count) packages | Share this file or host it on GitHub." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # --- LOAD PROFILE ---
    $profile = $null

    if ($Url) {
        Write-Host "  Fetching profile from: $Url" -ForegroundColor DarkGray
        try {
            $raw = Invoke-RestMethod -Uri $Url -ErrorAction Stop
            $profile = if ($raw -is [string]) { $raw | ConvertFrom-Json -AsHashtable } else { $raw }
        } catch {
            Write-Error "Failed to fetch profile: $($_.Exception.Message)"
            return
        }
    }
    elseif ($Path) {
        $profile = Get-Content -Path $Path -Raw | ConvertFrom-Json -AsHashtable
    }
    else {
        $profile = $builtInProfiles[$Name]
    }

    if (-not $profile -or -not $profile.Packages) {
        Write-Error "Invalid profile: no 'packages' array found."
        return
    }

    $profileName = $profile.Name ?? $profile.name ?? "Custom Profile"
    $packageList = $profile.Packages ?? $profile.packages

    # --- Filter installed ---
    $toInstall = $packageList
    if ($SkipInstalled) {
        $installed = Microsoft.WinGet.Client\Get-WinGetPackage -ErrorAction SilentlyContinue
        $installedIds = @($installed | ForEach-Object { $_.Id })
        $toInstall = $packageList | Where-Object { $_ -notin $installedIds }
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
    if ($profile.Description -or $profile.description) {
        Write-Host "  $($profile.Description ?? $profile.description)" -ForegroundColor DarkGray
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
    $confirm = $PSCmdlet.ShouldContinue("Install $($toInstall.Count) packages from '$profileName'?", "Confirm Profile Install")
    if (-not $confirm) {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }

    $success = 0; $failed = 0
    $j = 0
    foreach ($pkgId in $toInstall) {
        $j++
        Write-Host "  [$j/$($toInstall.Count)] $pkgId" -NoNewline -ForegroundColor Cyan
        Write-Host "..." -NoNewline
        try {
            Microsoft.WinGet.Client\Install-WinGetPackage -Id $pkgId -Mode Silent | Out-Null
            Write-Host " ✓" -ForegroundColor Green
            $success++
        } catch {
            Write-Host " ✗ ($($_.Exception.Message))" -ForegroundColor Red
            $failed++
        }
    }

    Write-Host ""
    Write-Host "  Profile '$profileName' complete: $success installed, $failed failed." -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
    Write-Host ""
}
