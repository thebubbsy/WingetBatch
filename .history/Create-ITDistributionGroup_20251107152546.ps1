# Create IT Distribution Group Script
# Creates InformationTechnology@possabilitygroup.com.au distribution group
# Adds members and enables external sending

# Connect to Exchange Online (if not already connected)
# Uncomment the following lines if you need to connect first:
# Install-Module -Name ExchangeOnlineManagement -Force -Scope CurrentUser
# Connect-ExchangeOnline

# Distribution Group Details
$groupName = "InformationTechnology"
$groupEmail = "InformationTechnology@possabilitygroup.com.au"
$groupDisplayName = "Information Technology"

# Member email addresses
$members = @(
    "Steven.Offen@possabilitygroup.com.au",
    "Charlie.Tran@possabilitygroup.com.au",
    "Raghu.Vannala@possabilitygroup.com.au",
    "Mark.Wilson@possabilitygroup.com.au",
    "Matthew.Bubb@possabilitygroup.com.au",
    "Shane.Johns@possabilitygroup.com.au",
    "Steven.Mouzakis@possabilitygroup.com.au",
    "Abdul.Majeed@possabilitygroup.com.au",
    "Vhybhavi.Guska@possabilitygroup.com.au",
    "phone.tun@possabilitygroup.com.au",
    "Apoorv.Singh@possabilitygroup.com.au",
    "Natalie.Vipiana@possabilitygroup.com.au",
    "Louise.Cronk@lifestylesolutions.org.au",
    "Sarah.Graham@possabilitygroup.com.au",
    "Nathan.Horton@possabilitygroup.com.au",
    "Travis.Hunt@possabilitygroup.com.au",
    "Stuart.Richardson@possabilitygroup.com.au",
    "Ahmed.Faris@possabilitygroup.com.au",
    "Nico.Georgaki@possabilitygroup.com.au",
    "Abby.Lynch@possabilitygroup.com.au",
    "Iby.Boztepe@possabilitygroup.com.au",
    "Terence.Zhao@possabilitygroup.com.au"
)

try {
    # Check if the distribution group already exists
    $existingGroup = Get-DistributionGroup -Identity $groupEmail -ErrorAction SilentlyContinue

    if ($existingGroup) {
        Write-Host "Distribution group already exists: $groupEmail" -ForegroundColor Yellow
        Write-Host "Will add members to existing group..." -ForegroundColor Cyan
    }
    else {
        Write-Host "Creating distribution group: $groupEmail" -ForegroundColor Cyan

        # Create the distribution group
        New-DistributionGroup -Name $groupName `
                              -DisplayName $groupDisplayName `
                              -PrimarySmtpAddress $groupEmail `
                              -ErrorAction Stop

        Write-Host "✓ Distribution group created successfully" -ForegroundColor Green

        # Wait a moment for the group to be fully created
        Start-Sleep -Seconds 3
    }

    # Add members to the group
    Write-Host "`nAdding members to the group..." -ForegroundColor Cyan
    $successCount = 0
    $failCount = 0

    foreach ($member in $members) {
        try {
            # Get the mailbox specifically to avoid ambiguity
            $mailbox = Get-Mailbox -Identity $member -ErrorAction Stop
            Add-DistributionGroupMember -Identity $groupEmail -Member $mailbox.PrimarySmtpAddress -ErrorAction Stop
            Write-Host "  ✓ Added: $member" -ForegroundColor Green
            $successCount++
        }
        catch {
            Write-Host "  ✗ Failed to add: $member - $($_.Exception.Message)" -ForegroundColor Red
            $failCount++
        }
    }

    Write-Host "`nMember Addition Summary:" -ForegroundColor Cyan
    Write-Host "  Success: $successCount" -ForegroundColor Green
    Write-Host "  Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })

    # Enable external sending (allow external senders to email this group)
    Write-Host "`nConfiguring external sending permissions..." -ForegroundColor Cyan

    Set-DistributionGroup -Identity $groupEmail `
                          -RequireSenderAuthenticationEnabled $false `
                          -ErrorAction Stop

    Write-Host "✓ External sending enabled - external users can now send to this group" -ForegroundColor Green

    # Display group information
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Distribution Group Created Successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Group Name: $groupDisplayName"
    Write-Host "Email Address: $groupEmail"
    Write-Host "Total Members: $($members.Count)"
    Write-Host "External Sending: Enabled"
    Write-Host "`nYou can view the group with: Get-DistributionGroup -Identity '$groupEmail'"
    Write-Host "You can view members with: Get-DistributionGroupMember -Identity '$groupEmail'"
}
catch {
    Write-Host "`n✗ Error occurred: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nTroubleshooting tips:" -ForegroundColor Yellow
    Write-Host "1. Ensure you're connected to Exchange Online: Connect-ExchangeOnline"
    Write-Host "2. Verify you have permissions to create distribution groups"
    Write-Host "3. Check if the group already exists: Get-DistributionGroup -Identity '$groupEmail'"
}
