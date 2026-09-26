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
