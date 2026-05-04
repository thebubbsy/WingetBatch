# Publishing WingetBatch to PowerShell Gallery

## Prerequisites

1. **PowerShell Gallery Account**
   - Create account at: https://www.powershellgallery.com/
   - Get your API key from: https://www.powershellgallery.com/account/apikeys

2. **Module Ready for Publishing**
   - ✅ Module manifest (.psd1) with all metadata
   - ✅ LICENSE file
   - ✅ README.md with documentation
   - ✅ All functions tested and working

## Publishing Steps

### 1. Test the Module Locally

```powershell
# Import and test the module
Import-Module .\WingetBatch.psd1 -Force

# Test all exported functions
Get-Command -Module WingetBatch

# Run Test-ModuleManifest to validate
Test-ModuleManifest .\WingetBatch.psd1
```

### 2. Set Your API Key

```powershell
# Store your PowerShell Gallery API key (one-time setup)
$apiKey = Read-Host -AsSecureString "Enter your PowerShell Gallery API Key"
$apiKeyPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($apiKey))
```

### 3. Publish to PowerShell Gallery

```powershell
# Navigate to the module directory
cd "C:\Users\user\OneDrive\Documents\PowerShell\Modules\WingetBatch"

# Publish the module
Publish-Module -Path . -NuGetApiKey $apiKeyPlain -Verbose

# Or if you want to test first (publish to a local repository)
Publish-Module -Path . -Repository PSGallery -NuGetApiKey $apiKeyPlain -WhatIf
```

### 4. Verify Publication

After publishing (takes a few minutes to process):

```powershell
# Search for your module
Find-Module -Name WingetBatch

# View details
Find-Module -Name WingetBatch | Format-List *

# Test installation
Install-Module -Name WingetBatch -Scope CurrentUser
```

## Updating the Module

When you make updates:

1. **Update the version number** in `WingetBatch.psd1`:
   ```powershell
   ModuleVersion = '2.0.1'  # Increment version
   ```

2. **Update ReleaseNotes** in `WingetBatch.psd1`

3. **Publish the new version**:
   ```powershell
   Publish-Module -Path . -NuGetApiKey $apiKeyPlain
   ```

## Version Numbering Guidelines

Follow Semantic Versioning (SemVer):
- **Major** (X.0.0): Breaking changes
- **Minor** (2.X.0): New features, backward compatible
- **Patch** (2.0.X): Bug fixes, backward compatible

Current version: **2.0.0** (Major feature release)

## Common Issues

### "Module already exists"
- You can't unpublish versions from PowerShell Gallery
- Increment version number and republish

### "Invalid manifest"
- Run `Test-ModuleManifest .\WingetBatch.psd1` to check for errors
- Ensure all fields are properly formatted

### "Missing required fields"
- Ensure Author, Description, and ModuleVersion are set
- Add ProjectUri and LicenseUri in PrivateData.PSData

## Gallery URLs

After publishing:
- **Module Page**: https://www.powershellgallery.com/packages/WingetBatch
- **Stats**: https://www.powershellgallery.com/stats/packages/WingetBatch

## Notes

- First publication takes longer to process (~10-15 minutes)
- Updates appear faster (~5 minutes)
- You cannot delete published versions
- Tags help with discoverability
- Good documentation increases downloads

## Support

- PowerShell Gallery Documentation: https://docs.microsoft.com/en-us/powershell/scripting/gallery/
- Publishing Guide: https://docs.microsoft.com/en-us/powershell/scripting/gallery/how-to/publishing-packages/publishing-a-package
