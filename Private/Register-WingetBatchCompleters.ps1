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

            $installed = Get-WinGetPackage -ErrorAction SilentlyContinue
            if ($installed) {
                $installed |
                    Where-Object { $_.Id -like "$wordToComplete*" } |
                    Select-Object -First 20 -ExpandProperty Id |
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

    # Config key completer
    $configKeyCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        @('SearchMatchOption', 'UpdateInterval', 'CacheEnabled', 'NotificationsEnabled') |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
    }

    # Register completers for specific command/parameter combinations
    $idCommands = @(
        'Get-WingetPackageInfo'
        'Find-WingetDuplicate'
    )

    foreach ($cmd in $idCommands) {
        Register-ArgumentCompleter -CommandName $cmd -ParameterName 'Id' -ScriptBlock $packageIdCompleter -ErrorAction SilentlyContinue
    }

    Register-ArgumentCompleter -CommandName 'Install-WingetAll' -ParameterName 'Id' -ScriptBlock $packageSearchCompleter -ErrorAction SilentlyContinue
    Register-ArgumentCompleter -CommandName 'Install-WingetAll' -ParameterName 'Source' -ScriptBlock $sourceCompleter -ErrorAction SilentlyContinue
    Register-ArgumentCompleter -CommandName 'Get-WingetPackageInfo' -ParameterName 'Query' -ScriptBlock $packageSearchCompleter -ErrorAction SilentlyContinue
}
