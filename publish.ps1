$env:TEMP = "C:\temp"
$env:TMP = "C:\temp"
$env:NUGET_PACKAGES = "C:\temp\nuget_cache"
$env:NUGET_HTTP_CACHE_PATH = "C:\temp\nuget_http_cache"
$apiKey = [Environment]::GetEnvironmentVariable("PSGALLERY_API_KEY", "User")
if ($apiKey) {
    Publish-Module -Path "C:\Users\user\.gemini\antigravity\scratch\WingetBatch" -NuGetApiKey $apiKey -Force -Verbose
} else {
    Write-Error "API key not found"
}
