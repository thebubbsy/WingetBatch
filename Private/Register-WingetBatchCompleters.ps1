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
