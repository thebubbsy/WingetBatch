$paths = $env:PSModulePath -split ';' | Where-Object { $_ -notmatch 'PowerShell[\\/]7' }
$env:PSModulePath = $paths -join ';'
Import-Module PowerShellGet -Force
.\publish.ps1
