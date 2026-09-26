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
