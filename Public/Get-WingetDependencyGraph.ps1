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
