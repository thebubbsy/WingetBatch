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
