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
                @{ Id = 'Python.Python.3.12'; Weight = 8; Reason = 'Scripting and service tooling' }
                @{ Id = 'GoLang.Go'; Weight = 7; Reason = 'High-performance service language' }
                @{ Id = 'Rustlang.Rustup'; Weight = 6; Reason = 'Systems programming language' }
                @{ Id = 'PostgreSQL.PostgreSQL'; Weight = 8; Reason = 'Relational database server' }
                @{ Id = 'Redis.Redis'; Weight = 7; Reason = 'In-memory cache and message broker' }
                @{ Id = 'Microsoft.DotNet.SDK.8'; Weight = 8; Reason = '.NET runtime and SDK' }
                @{ Id = 'OpenJS.NodeJS.LTS'; Weight = 8; Reason = 'JavaScript runtime for tooling' }
                @{ Id = 'JetBrains.DataGrip'; Weight = 6; Reason = 'Database IDE and query tool' }
                @{ Id = 'Postman.Postman'; Weight = 7; Reason = 'API testing and documentation' }
                @{ Id = 'Grafana.Agent'; Weight = 5; Reason = 'Observability and metrics' }
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
                @{ Id = 'Vercel.nextjs'; Weight = 6; Reason = 'React framework tooling' }
                @{ Id = 'Yarn.Yarn'; Weight = 6; Reason = 'Alternative package manager' }
                @{ Id = 'Microsoft.Edge.Dev'; Weight = 5; Reason = 'Chromium testing channel' }
                @{ Id = 'Nginx.Nginx'; Weight = 5; Reason = 'Local reverse proxy for dev' }
            )
        }
        'Data Scientist' = @{
            Keywords = @('data', 'science', 'ml', 'machine learning', 'ai', 'analytics', 'jupyter', 'pandas', 'numpy', 'tensorflow', 'pytorch', 'statistics', 'visualization')
            Packages = @(
                @{ Id = 'Python.Python.3.12'; Weight = 10; Reason = 'Primary data science runtime' }
                @{ Id = 'Anaconda.Anaconda3'; Weight = 9; Reason = 'Scientific computing distribution' }
                @{ Id = 'Microsoft.VisualStudioCode'; Weight = 8; Reason = 'Editor with Jupyter integration' }
                @{ Id = 'Git.Git'; Weight = 8; Reason = 'Experiment versioning' }
                @{ Id = 'Docker.DockerDesktop'; Weight = 7; Reason = 'Reproducible environments' }
                @{ Id = 'PostgreSQL.PostgreSQL'; Weight = 7; Reason = 'Data warehouse' }
                @{ Id = 'RProject.R'; Weight = 8; Reason = 'Statistical computing language' }
                @{ Id = 'RStudio.RStudio.OpenSource'; Weight = 7; Reason = 'R IDE and notebooks' }
                @{ Id = 'JetBrains.PyCharm.Community'; Weight = 7; Reason = 'Python IDE for ML projects' }
                @{ Id = 'Microsoft.PowerBI'; Weight = 6; Reason = 'Business intelligence dashboards' }
                @{ Id = 'Tableau.TableauDesktop'; Weight = 5; Reason = 'Advanced data visualization' }
                @{ Id = 'Julia.Julia'; Weight = 6; Reason = 'High-performance numerical computing' }
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
                @{ Id = 'Ansible.Ansible'; Weight = 7; Reason = 'Configuration management' }
                @{ Id = 'Grafana.Grafana'; Weight = 7; Reason = 'Monitoring dashboards' }
                @{ Id = 'Hashicorp.Vault'; Weight = 6; Reason = 'Secrets management' }
                @{ Id = 'Microsoft.VisualStudioCode'; Weight = 7; Reason = 'IaC editing' }
                @{ Id = 'PuTTY.PuTTY'; Weight = 5; Reason = 'SSH access to servers' }
                @{ Id = 'WiresharkFoundation.Wireshark'; Weight = 6; Reason = 'Network troubleshooting' }
                @{ Id = 'Python.Python.3.12'; Weight = 7; Reason = 'Automation scripting' }
            )
        }
        'Gamer' = @{
            Keywords = @('gaming', 'gamer', 'game', 'steam', 'twitch', 'discord', 'rgb', 'fps', 'esports', 'streaming', 'obs')
            Packages = @(
                @{ Id = 'Valve.Steam'; Weight = 10; Reason = 'Primary game library' }
                @{ Id = 'Discord.Discord'; Weight = 9; Reason = 'Voice chat and communities' }
                @{ Id = 'OBSProject.OBSStudio'; Weight = 8; Reason = 'Game streaming and recording' }
                @{ Id = 'EpicGames.EpicGamesLauncher'; Weight = 7; Reason = 'Epic game library' }
                @{ Id = 'RiotGames.RiotClient'; Weight = 7; Reason = 'League/Valorant client' }
                @{ Id = 'NVIDIA.GeForceExperience'; Weight = 8; Reason = 'GPU optimization and recording' }
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
                @{ Id = 'Unity.Unity'; Weight = 10; Reason = 'Game engine (C#)' }
                @{ Id = 'EpicGames.UnrealEngine'; Weight = 9; Reason = 'AAA game engine (C++/Blueprints)' }
                @{ Id = 'GodotEngine.GodotEngine'; Weight = 9; Reason = 'Open-source game engine' }
                @{ Id = 'BlenderFoundation.Blender'; Weight = 9; Reason = '3D modeling and animation' }
                @{ Id = 'Microsoft.VisualStudioCode'; Weight = 8; Reason = 'Scripting and shader editing' }
                @{ Id = 'Git.Git'; Weight = 8; Reason = 'Asset and code versioning' }
                @{ Id = 'GIMP.GIMP'; Weight = 7; Reason = '2D art and texture editing' }
                @{ Id = 'Inkscape.Inkscape'; Weight = 6; Reason = 'Vector art for UI/sprites' }
                @{ Id = 'Audacity.Audacity'; Weight = 6; Reason = 'Audio editing for SFX' }
                @{ Id = 'Microsoft.DotNet.SDK.8'; Weight = 7; Reason = 'C# development for Unity' }
                @{ Id = 'Microsoft.VisualStudio.Community'; Weight = 7; Reason = 'Full C++ IDE for Unreal' }
            )
        }
        'Security Researcher' = @{
            Keywords = @('security', 'pentest', 'hacking', 'ctf', 'forensics', 'malware', 'reverse engineering', 'vulnerability', 'red team', 'blue team', 'soc')
            Packages = @(
                @{ Id = 'WiresharkFoundation.Wireshark'; Weight = 10; Reason = 'Network packet analysis' }
                @{ Id = 'Python.Python.3.12'; Weight = 9; Reason = 'Exploit scripting and automation' }
                @{ Id = 'Git.Git'; Weight = 8; Reason = 'Tool and research versioning' }
                @{ Id = 'Nmap.Nmap'; Weight = 9; Reason = 'Network scanning and enumeration' }
                @{ Id = 'GnuPG.GnuPG'; Weight = 7; Reason = 'Encryption and signing' }
                @{ Id = 'KeePassXCTeam.KeePassXC'; Weight = 7; Reason = 'Credential management' }
                @{ Id = 'Microsoft.VisualStudioCode'; Weight = 7; Reason = 'Code analysis and scripting' }
                @{ Id = 'Docker.DockerDesktop'; Weight = 7; Reason = 'Isolated malware analysis labs' }
                @{ Id = 'Oracle.VirtualBox'; Weight = 8; Reason = 'Vulnerable VM labs' }
                @{ Id = 'Hex-Rays.IDA.Free'; Weight = 8; Reason = 'Binary reverse engineering' }
                @{ Id = 'Ghidra.Ghidra'; Weight = 8; Reason = 'NSA reverse engineering suite' }
                @{ Id = 'Tor.TorBrowser'; Weight = 6; Reason = 'Anonymous research browsing' }
            )
        }
        'Designer' = @{
            Keywords = @('design', 'graphic', 'ui', 'ux', 'figma', 'photoshop', 'illustrator', 'creative', 'photo', 'video', 'editing', 'adobe')
            Packages = @(
                @{ Id = 'Figma.Figma'; Weight = 10; Reason = 'UI/UX design and prototyping' }
                @{ Id = 'GIMP.GIMP'; Weight = 8; Reason = 'Raster image editing' }
                @{ Id = 'Inkscape.Inkscape'; Weight = 8; Reason = 'Vector graphics editor' }
                @{ Id = 'BlenderFoundation.Blender'; Weight = 7; Reason = '3D design and rendering' }
                @{ Id = 'DaVinciResolve.DaVinciResolve'; Weight = 7; Reason = 'Video editing and color grading' }
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
                @{ Id = 'Slack.Slack'; Weight = 7; Reason = 'Team communication' }
                @{ Id = 'Notion.Notion'; Weight = 8; Reason = 'Notes and project management' }
                @{ Id = 'Obsidian.Obsidian'; Weight = 8; Reason = 'Knowledge management (local-first)' }
                @{ Id = 'Todoist.Todoist'; Weight = 7; Reason = 'Task management' }
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
                @{ Id = 'Python.Python.3.12'; Weight = 8; Reason = 'Intro programming language' }
                @{ Id = 'Obsidian.Obsidian'; Weight = 8; Reason = 'Study notes and knowledge base' }
                @{ Id = 'Zotero.Zotero'; Weight = 8; Reason = 'Research paper management' }
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
        'Git.Git' = @('Microsoft.VisualStudioCode', 'Docker.DockerDesktop', 'OpenJS.NodeJS.LTS', 'Python.Python.3.12')
        'Docker.DockerDesktop' = @('Kubernetes.kubectl', 'Hashicorp.Terraform', 'Microsoft.VisualStudioCode', 'Git.Git')
        'Microsoft.VisualStudioCode' = @('Git.Git', 'Python.Python.3.12', 'OpenJS.NodeJS.LTS', 'Docker.DockerDesktop')
        'Python.Python.3.12' = @('Microsoft.VisualStudioCode', 'Anaconda.Anaconda3', 'Git.Git', 'JetBrains.PyCharm.Community')
        'OpenJS.NodeJS.LTS' = @('Microsoft.VisualStudioCode', 'Git.Git', 'Yarn.Yarn', 'Docker.DockerDesktop')
        'Valve.Steam' = @('Discord.Discord', 'OBSProject.OBSStudio', 'NVIDIA.GeForceExperience')
        'WiresharkFoundation.Wireshark' = @('Nmap.Nmap', 'Python.Python.3.12', 'Oracle.VirtualBox')
        'BlenderFoundation.Blender' = @('GIMP.GIMP', 'Inkscape.Inkscape', 'DaVinciResolve.DaVinciResolve')
        'PostgreSQL.PostgreSQL' = @('Redis.Redis', 'JetBrains.DataGrip', 'Docker.DockerDesktop')
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
    $recommendations = $scores.GetEnumerator() |
        Where-Object { -not $ExcludeInstalled -or $_.Key -notin $installedIds } |
        Sort-Object { $_.Value.Score } -Descending |
        Select-Object -First $MaxResults

    # Category filter
    if ($Category) {
        # Simple category mapping by package ID patterns
        $categoryMap = @{
            'Development' = @('Git', 'Code', 'Python', 'Node', 'DotNet', 'JetBrains', 'Rust', 'Go', 'Java')
            'DevOps' = @('Docker', 'Kubernetes', 'Terraform', 'Ansible', 'Helm', 'Grafana', 'Vault', 'Azure', 'AWS')
            'Gaming' = @('Steam', 'Discord', 'Epic', 'Riot', 'OBS', 'GeForce', 'GOG', 'Ubisoft')
            'Design' = @('Figma', 'GIMP', 'Inkscape', 'Blender', 'DaVinci', 'Audacity')
            'Security' = @('Wireshark', 'Nmap', 'Ghidra', 'IDA', 'KeePass', 'GnuPG', 'Tor', 'VirtualBox')
            'Productivity' = @('Office', 'Teams', 'Slack', 'Notion', 'Obsidian', 'Zoom', 'Todoist', 'ShareX')
            'Media' = @('VLC', 'OBS', 'Audacity', 'DaVinci', 'Spotify', 'GIMP')
            'Utilities' = @('7zip', 'AutoHotkey', 'PuTTY', 'ShareX')
        }
        $patterns = $categoryMap[$Category] ?? @()
        if ($patterns.Count -gt 0) {
            $recommendations = $recommendations | Where-Object {
                $id = $_.Key
                ($patterns | Where-Object { $id -match [regex]::Escape($_) }).Count -gt 0
            }
        }
    }

    # --- OUTPUT ---
    if ($recommendations.Count -eq 0) {
        Write-Host "`n  No recommendations found. Your machine is complete!`n" -ForegroundColor Green
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
        $choices = $recommendations | ForEach-Object { $_.Key }

        if (Get-Command Read-SpectreMultiSelection -ErrorAction SilentlyContinue) {
            $selected = Read-SpectreMultiSelection -Choices $choices -Title "Select packages to install"
        } else {
            Write-Host "  Enter numbers to install (comma-separated, or 'all'): " -NoNewline -ForegroundColor Yellow
            $input = Read-Host
            if ($input -eq 'all') {
                $selected = $choices
            } else {
                $indices = $input.Split(',') | ForEach-Object { [int]$_.Trim() - 1 }
                $selected = $indices | ForEach-Object { $choices[$_] }
            }
        }

        if ($selected -and $selected.Count -gt 0) {
            Write-Host "`n  Installing $($selected.Count) packages...`n" -ForegroundColor Green
            $j = 0
            foreach ($pkgId in $selected) {
                $j++
                Write-Host "  [$j/$($selected.Count)] Installing $pkgId..." -NoNewline -ForegroundColor Cyan
                try {
                    Microsoft.WinGet.Client\Install-WinGetPackage -Id $pkgId -Mode Silent | Out-Null
                    Write-Host " ✓" -ForegroundColor Green
                } catch {
                    Write-Host " ✗ ($($_.Exception.Message))" -ForegroundColor Red
                }
            }
            Write-Host "`n  Done! $($selected.Count) packages processed.`n" -ForegroundColor Green
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
