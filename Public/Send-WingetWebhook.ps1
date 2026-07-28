function Send-WingetWebhook {
    <#
    .SYNOPSIS
        Send package event notifications to Discord, Slack, or Teams webhooks.

    .DESCRIPTION
        Push rich notifications to chat platforms when package events occur:
        updates available, maintenance completed, drift detected, installs finished,
        or compliance violations found.

        Supports Discord embeds, Slack Block Kit, and Teams Adaptive Cards.
        Configure once with Set-WingetBatchConfig, then use anywhere.

    .PARAMETER Platform
        Target platform: Discord, Slack, or Teams.

    .PARAMETER WebhookUrl
        The webhook URL. If not specified, reads from saved config.

    .PARAMETER Event
        Event type: UpdatesAvailable, MaintenanceComplete, DriftDetected,
        InstallComplete, ComplianceViolation, Custom.

    .PARAMETER Title
        Notification title (for Custom events).

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

        [Parameter()]
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

        [switch]$SaveConfig,

        [Parameter(ParameterSetName = 'Test', Mandatory)]
        [switch]$Test
    )

    # --- Resolve webhook URL ---
    $configDir = Get-WingetBatchConfigDir
    $configPath = Join-Path $configDir "config.json"
    $config = @{}
    if (Test-Path $configPath) {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json -AsHashtable
    }

    if (-not $WebhookUrl) {
        $key = "webhook_$($Platform.ToLower())"
        $WebhookUrl = $config[$key]
    }

    if (-not $WebhookUrl) {
        Write-Error "No webhook URL for $Platform. Provide -WebhookUrl or save one with -SaveConfig."
        return
    }

    # --- Save config ---
    if ($SaveConfig) {
        $key = "webhook_$($Platform.ToLower())"
        $config[$key] = $WebhookUrl
        $config | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
        Write-Host "  ✓ $Platform webhook URL saved to config." -ForegroundColor Green
        if ($Test) { } else { return }
    }

    # --- Build notification content ---
    $hostname = $env:COMPUTERNAME
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    if ($Test) {
        $Event = 'Custom'
        $Title = "WingetBatch Test Notification"
        $Message = "Webhook integration is working! Sent from $hostname at $timestamp."
        $Data = @{ Platform = $Platform; Hostname = $hostname }
    }

    # Default titles/messages per event
    $eventDefaults = @{
        'UpdatesAvailable' = @{ Title = "📦 Updates Available"; Color = 0xFFA500; Emoji = "📦" }
        'MaintenanceComplete' = @{ Title = "🔧 Maintenance Complete"; Color = 0x00CC00; Emoji = "🔧" }
        'DriftDetected' = @{ Title = "⚠️ Configuration Drift Detected"; Color = 0xFF4444; Emoji = "⚠️" }
        'InstallComplete' = @{ Title = "✅ Installation Complete"; Color = 0x00AAFF; Emoji = "✅" }
        'ComplianceViolation' = @{ Title = "🚨 Compliance Violation"; Color = 0xFF0000; Emoji = "🚨" }
        'Custom' = @{ Title = "WingetBatch Notification"; Color = 0x7289DA; Emoji = "📋" }
    }

    $defaults = $eventDefaults[$Event]
    if (-not $Title) { $Title = $defaults.Title }
    if (-not $Message) { $Message = "Event: $Event on $hostname at $timestamp" }

    # --- Format per platform ---
    $body = $null
    $contentType = 'application/json'

    switch ($Platform) {
        'Discord' {
            # Discord embed format
            $fields = @()
            if ($Data) {
                foreach ($entry in $Data.GetEnumerator()) {
                    $fields += @{ name = $entry.Key; value = "$($entry.Value)"; inline = $true }
                }
            }
            $fields += @{ name = "Host"; value = $hostname; inline = $true }
            $fields += @{ name = "Time"; value = $timestamp; inline = $true }

            $body = @{
                username = "WingetBatch"
                embeds = @(@{
                    title = "$($defaults.Emoji) $Title"
                    description = $Message
                    color = $defaults.Color
                    fields = $fields
                    footer = @{ text = "WingetBatch v2.8.0 | $hostname" }
                    timestamp = (Get-Date -ToString 'o')
                })
            } | ConvertTo-Json -Depth 10 -Compress
        }
        'Slack' {
            # Slack Block Kit format
            $blocks = @(
                @{ type = "header"; text = @{ type = "plain_text"; text = "$($defaults.Emoji) $Title" } }
                @{ type = "section"; text = @{ type = "mrkdwn"; text = $Message } }
            )

            if ($Data -and $Data.Count -gt 0) {
                $dataText = ($Data.GetEnumerator() | ForEach-Object { "*$($_.Key):* $($_.Value)" }) -join "`n"
                $blocks += @{ type = "section"; text = @{ type = "mrkdwn"; text = $dataText } }
            }

            $blocks += @{ type = "context"; elements = @(@{ type = "mrkdwn"; text = "WingetBatch | $hostname | $timestamp" }) }

            $body = @{ blocks = $blocks } | ConvertTo-Json -Depth 10 -Compress
        }
        'Teams' {
            # Teams Adaptive Card (MessageCard format for simplicity)
            $sections = @(@{
                activityTitle = $Title
                activitySubtitle = "$hostname - $timestamp"
                text = $Message
                facts = @()
            })

            if ($Data) {
                foreach ($entry in $Data.GetEnumerator()) {
                    $sections[0].facts += @{ name = $entry.Key; value = "$($entry.Value)" }
                }
            }
            $sections[0].facts += @{ name = "Host"; value = $hostname }

            $body = @{
                '@type' = "MessageCard"
                '@context' = "http://schema.org/extensions"
                themeColor = $defaults.Color.ToString("X6")
                summary = $Title
                sections = $sections
            } | ConvertTo-Json -Depth 10 -Compress
        }
    }

    # --- Send ---
    try {
        $response = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $body -ContentType $contentType -ErrorAction Stop
        Write-Host "  ✓ Notification sent to $Platform ($Event)" -ForegroundColor Green
        return [PSCustomObject]@{
            Success = $true
            Platform = $Platform
            Event = $Event
            Timestamp = $timestamp
        }
    }
    catch {
        Write-Error "Failed to send $Platform webhook: $($_.Exception.Message)"
        return [PSCustomObject]@{
            Success = $false
            Platform = $Platform
            Event = $Event
            Error = $_.Exception.Message
        }
    }
}
