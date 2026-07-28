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
        Install-Module -Name Pode -Force -Scope CurrentUser -SkipPublisherCheck
    }
    Import-Module Pode -Force

    # Generate or validate API key
    if ([string]::IsNullOrEmpty($ApiKey)) {
        $ApiKey = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
        Write-Host "  Generated API Key: " -NoNewline -ForegroundColor DarkGray
        Write-Host $ApiKey -ForegroundColor Yellow
        Write-Host "  (Use header: X-API-Key: $ApiKey)" -ForegroundColor DarkGray
    }
    $disableAuth = ($ApiKey -eq 'none')

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

    # Start Pode server
    Start-PodeServer -Threads 4 {
        # Listener
        Add-PodeEndpoint -Address $using:Hostname -Port $using:Port -Protocol $(if ($using:Https) { 'Https' } else { 'Http' })

        # Middleware: API Key auth
        if (-not $using:disableAuth) {
            Add-PodeRouteMiddleware -Name 'ApiAuth' -ScriptBlock {
                $apiKey = $WebEvent.Headers['X-API-Key']
                if ($apiKey -ne $using:ApiKey) {
                    Set-PodeResponseStatus -Code 401
                    Write-PodeJsonResponse -Value @{ error = "Unauthorized"; message = "Invalid or missing X-API-Key header" }
                    return $false
                }
                return $true
            }
        }

        # Middleware: Rate limiting
        if ($using:MaxRequestsPerMinute -gt 0) {
            Add-PodeRouteMiddleware -Name 'RateLimit' -ScriptBlock {
                $clientIp = $WebEvent.Request.RemoteEndPoint.Address.IPAddressToString
                $key = "rate_$clientIp"
                $now = Get-Date
                $window = $now.AddMinutes(-1)

                if (-not $script:RateTable) { $script:RateTable = @{} }
                if (-not $script:RateTable.ContainsKey($key)) { $script:RateTable[$key] = [System.Collections.Generic.List[datetime]]::new() }

                $script:RateTable[$key].RemoveAll({ param($t) $t -lt $window })
                if ($script:RateTable[$key].Count -ge $using:MaxRequestsPerMinute) {
                    Set-PodeResponseStatus -Code 429
                    Write-PodeJsonResponse -Value @{ error = "Rate limit exceeded"; retry_after_seconds = 60 }
                    return $false
                }
                $script:RateTable[$key].Add($now)
                return $true
            }
        }

        # Middleware: Request logging
        if ($using:logFile) {
            Add-PodeRouteMiddleware -Name 'RequestLog' -ScriptBlock {
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
                version = "2.8.0"
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
                timestamp = (Get-Date -ToString 'o')
                hostname = $env:COMPUTERNAME
                winget_cli = $wingetOk
                winget_com = $comOk
                module_version = (Get-Module WingetBatch).Version.ToString()
                uptime_seconds = ((Get-Date) - $PodeServer.StartTime).TotalSeconds
            }
        }

        # GET /api/packages
        Add-PodeRoute -Method Get -Path '/api/packages' -ScriptBlock {
            $source = $QueryData.source
            $packages = Microsoft.WinGet.Client\Get-WinGetPackage
            if ($source) { $packages = $packages | Where-Object { $_.Source -eq $source } }
            Write-PodeJsonResponse -Value @{
                count = $packages.Count
                packages = @($packages | ForEach-Object {
                    @{ id = $_.Id; name = $_.Name; version = $_.InstalledVersion; source = $_.Source; available = $_.AvailableVersions }
                })
            }
        }

        # GET /api/packages/:id
        Add-PodeRoute -Method Get -Path '/api/packages/:id' -ScriptBlock {
            $id = $RouteParameters.id
            $pkg = Microsoft.WinGet.Client\Get-WinGetPackage -Id $id
            if (-not $pkg) {
                Set-PodeResponseStatus -Code 404
                Write-PodeJsonResponse -Value @{ error = "Not found"; message = "Package '$id' is not installed" }
                return
            }
            Write-PodeJsonResponse -Value @{
                id = $pkg.Id; name = $pkg.Name; installed_version = $pkg.InstalledVersion
                available_versions = $pkg.AvailableVersions; source = $pkg.Source
                update_available = ($pkg.AvailableVersions -and $pkg.AvailableVersions[0] -ne $pkg.InstalledVersion)
            }
        }

        # GET /api/search
        Add-PodeRoute -Method Get -Path '/api/search' -ScriptBlock {
            $query = $QueryData.q
            if (-not $query) {
                Set-PodeResponseStatus -Code 400
                Write-PodeJsonResponse -Value @{ error = "Bad request"; message = "Query parameter 'q' is required" }
                return
            }
            $limit = [int]($QueryData.limit ?? 25)
            $results = Microsoft.WinGet.Client\Find-WinGetPackage -Query $query -Count $limit
            Write-PodeJsonResponse -Value @{
                query = $query; count = $results.Count
                results = @($results | ForEach-Object {
                    @{ id = $_.Id; name = $_.Name; version = $_.Version; source = $_.Source; publisher = $_.Publisher }
                })
            }
        }

        # POST /api/packages/install
        Add-PodeRoute -Method Post -Path '/api/packages/install' -ScriptBlock {
            $body = $WebEvent.Data
            $ids = $body.packages ?? @($body.id)
            if (-not $ids -or $ids.Count -eq 0) {
                Set-PodeResponseStatus -Code 400
                Write-PodeJsonResponse -Value @{ error = "Bad request"; message = "Provide 'packages' array or 'id' field" }
                return
            }
            $results = @()
            foreach ($id in $ids) {
                try {
                    Microsoft.WinGet.Client\Install-WinGetPackage -Id $id -Mode Silent | Out-Null
                    $results += @{ id = $id; status = "installed" }
                } catch {
                    $results += @{ id = $id; status = "failed"; error = $_.Exception.Message }
                }
            }
            Write-PodeJsonResponse -Value @{ installed = ($results | Where-Object status -eq 'installed').Count; failed = ($results | Where-Object status -eq 'failed').Count; results = $results }
        }

        # POST /api/packages/uninstall
        Add-PodeRoute -Method Post -Path '/api/packages/uninstall' -ScriptBlock {
            $body = $WebEvent.Data
            $ids = $body.packages ?? @($body.id)
            if (-not $ids -or $ids.Count -eq 0) {
                Set-PodeResponseStatus -Code 400
                Write-PodeJsonResponse -Value @{ error = "Bad request"; message = "Provide 'packages' array or 'id' field" }
                return
            }
            $results = @()
            foreach ($id in $ids) {
                try {
                    Microsoft.WinGet.Client\Uninstall-WinGetPackage -Id $id -Mode Silent | Out-Null
                    $results += @{ id = $id; status = "uninstalled" }
                } catch {
                    $results += @{ id = $id; status = "failed"; error = $_.Exception.Message }
                }
            }
            Write-PodeJsonResponse -Value @{ uninstalled = ($results | Where-Object status -eq 'uninstalled').Count; failed = ($results | Where-Object status -eq 'failed').Count; results = $results }
        }

        # GET /api/updates
        Add-PodeRoute -Method Get -Path '/api/updates' -ScriptBlock {
            $updates = Get-WingetUpdates
            Write-PodeJsonResponse -Value @{
                count = ($updates ?? @()).Count
                updates = @($updates | ForEach-Object {
                    @{ id = $_.Id; name = $_.Name; installed = $_.InstalledVersion; available = $_.AvailableVersion; source = $_.Source }
                })
            }
        }

        # POST /api/updates/apply
        Add-PodeRoute -Method Post -Path '/api/updates/apply' -ScriptBlock {
            $body = $WebEvent.Data
            $ids = $body.packages  # Optional: specific packages, else all
            $updates = Get-WingetUpdates
            if ($ids) { $updates = $updates | Where-Object { $_.Id -in $ids } }

            $results = @()
            foreach ($pkg in $updates) {
                try {
                    Microsoft.WinGet.Client\Update-WinGetPackage -Id $pkg.Id -Mode Silent | Out-Null
                    $results += @{ id = $pkg.Id; status = "updated"; version = $pkg.AvailableVersion }
                } catch {
                    $results += @{ id = $pkg.Id; status = "failed"; error = $_.Exception.Message }
                }
            }
            Write-PodeJsonResponse -Value @{ updated = ($results | Where-Object status -eq 'updated').Count; failed = ($results | Where-Object status -eq 'failed').Count; results = $results }
        }

        # GET /api/state
        Add-PodeRoute -Method Get -Path '/api/state' -ScriptBlock {
            $packages = Microsoft.WinGet.Client\Get-WinGetPackage
            Write-PodeJsonResponse -Value @{
                hostname = $env:COMPUTERNAME
                timestamp = (Get-Date -ToString 'o')
                total_packages = $packages.Count
                by_source = ($packages | Group-Object Source | ForEach-Object { @{ source = $_.Name; count = $_.Count } })
                packages = @($packages | ForEach-Object { @{ id = $_.Id; name = $_.Name; version = $_.InstalledVersion } })
            }
        }

        # POST /api/state/export
        Add-PodeRoute -Method Post -Path '/api/state/export' -ScriptBlock {
            $body = $WebEvent.Data
            $format = $body.format ?? 'json'
            $tempPath = Join-Path $env:TEMP "wingetbatch_state_$(Get-Random).$format"
            try {
                Get-WingetMachineState -Export -Path $tempPath -Format $format
                $content = Get-Content $tempPath -Raw
                Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                Write-PodeJsonResponse -Value @{ status = "exported"; format = $format; content = ($content | ConvertFrom-Json) }
            } catch {
                Set-PodeResponseStatus -Code 500
                Write-PodeJsonResponse -Value @{ error = "Export failed"; message = $_.Exception.Message }
            }
        }

        # GET /api/history
        Add-PodeRoute -Method Get -Path '/api/history' -ScriptBlock {
            $days = [int]($QueryData.days ?? 30)
            $history = Get-WingetHistory -Days $days
            Write-PodeJsonResponse -Value @{
                days = $days; count = $history.Count
                entries = @($history | ForEach-Object {
                    @{ name = $_.Name; publisher = $_.Publisher; version = $_.Version; date = $_.InstallDate; action = $_.Action }
                })
            }
        }

        # GET /api/stats
        Add-PodeRoute -Method Get -Path '/api/stats' -ScriptBlock {
            $packages = Microsoft.WinGet.Client\Get-WinGetPackage
            $updates = Get-WingetUpdates
            Write-PodeJsonResponse -Value @{
                total_installed = $packages.Count
                updates_available = ($updates ?? @()).Count
                sources = @($packages | Group-Object Source | ForEach-Object { @{ name = $_.Name; count = $_.Count } })
                top_publishers = @($packages | Group-Object { ($_.Id -split '\.')[0] } | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ publisher = $_.Name; count = $_.Count } })
            }
        }
    }
}
