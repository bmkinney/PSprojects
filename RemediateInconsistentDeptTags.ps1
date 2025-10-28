# Remediate Inconsistent Department Code Tags
# This script removes inconsistent department tag names and adds the correct 'DeptCode' tag

# Ensure you're logged in to Azure
# Run: Connect-AzAccount if not already authenticated

Write-Host "Starting remediation of inconsistent department tags across all subscriptions..." -ForegroundColor Cyan
Write-Host "WARNING: This script will modify resource tags!" -ForegroundColor Yellow

# Define the correct tag name
$correctTagName = "DeptCode"

# Define variations of department tags to look for (case-insensitive)
$deptTagVariations = @(
    "Dept",
    "Department",
    "Dpmt",
    "DepartmentCode",
    "Dept-Code",
    "Dept_Code",
    "DeptId",
    "DepartmentId",
    "DepCode",
    "DeptNo",
    "DepartmentNumber"
)

# Get all subscriptions
Write-Host "`nRetrieving all accessible subscriptions..." -ForegroundColor Yellow
$subscriptions = Get-AzSubscription

Write-Host "Found $($subscriptions.Count) subscription(s). Processing..." -ForegroundColor Yellow

# Array to store resources that need remediation
$resourcesToRemediate = @()

# Iterate through each subscription to find resources
foreach ($subscription in $subscriptions) {
    Write-Host "`nScanning subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Cyan
    
    # Set the context to the current subscription
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null
    
    # Get all resources with tags in this subscription
    $allResources = Get-AzResource | Where-Object { $_.Tags -ne $null }
    
    Write-Host "  Found $($allResources.Count) resources with tags..." -ForegroundColor Yellow
    
    foreach ($resource in $allResources) {
        $tags = $resource.Tags
        
        # Check for variations
        foreach ($variation in $deptTagVariations) {
            # Case-insensitive search through all tag keys
            $matchingKey = $tags.Keys | Where-Object { $_ -eq $variation }
            
            if ($matchingKey) {
                $resourcesToRemediate += [PSCustomObject]@{
                    SubscriptionName = $subscription.Name
                    SubscriptionId   = $subscription.Id
                    ResourceName     = $resource.Name
                    ResourceType     = $resource.ResourceType
                    ResourceGroup    = $resource.ResourceGroupName
                    Resource         = $resource
                    InconsistentTag  = $matchingKey
                    TagValue         = $tags[$matchingKey]
                    HasCorrectTag    = $tags.ContainsKey($correctTagName)
                    AllTags          = $tags
                }
            }
        }
    }
}

# Display findings
if ($resourcesToRemediate.Count -eq 0) {
    Write-Host "`nNo resources found with inconsistent department tags. Nothing to remediate!" -ForegroundColor Green
    exit
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Found $($resourcesToRemediate.Count) resources requiring remediation:" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Cyan

$resourcesToRemediate | Format-Table -Property SubscriptionName, ResourceName, ResourceType, ResourceGroup, InconsistentTag, TagValue, HasCorrectTag -AutoSize

# Ask for confirmation mode
Write-Host "`nHow would you like to proceed?" -ForegroundColor Cyan
Write-Host "1. Yes to All (automatically remediate all resources)" -ForegroundColor Yellow
Write-Host "2. Confirm Each (review and confirm each resource individually)" -ForegroundColor Yellow
Write-Host "3. Cancel (exit without making changes)" -ForegroundColor Yellow
$confirmMode = Read-Host "`nEnter your choice (1, 2, or 3)"

if ($confirmMode -eq "3") {
    Write-Host "Operation cancelled. No changes made." -ForegroundColor Yellow
    exit
}

$yesToAll = ($confirmMode -eq "1")
$remediatedCount = 0
$skippedCount = 0
$errorCount = 0

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Starting Remediation Process" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

foreach ($item in $resourcesToRemediate) {
    # Set context to the correct subscription
    Set-AzContext -SubscriptionId $item.SubscriptionId | Out-Null
    
    if (-not $yesToAll) {
        Write-Host "`n--- Resource Details ---" -ForegroundColor Cyan
        Write-Host "Subscription: $($item.SubscriptionName)"
        Write-Host "Resource: $($item.ResourceName)"
        Write-Host "Type: $($item.ResourceType)"
        Write-Host "Resource Group: $($item.ResourceGroup)"
        Write-Host "Current Tag: $($item.InconsistentTag) = $($item.TagValue)"
        
        if ($item.HasCorrectTag) {
            Write-Host "WARNING: This resource already has a '$correctTagName' tag!" -ForegroundColor Red
            Write-Host "Existing '$correctTagName' value will be overwritten!" -ForegroundColor Red
        }
        
        Write-Host "`nAction: Remove '$($item.InconsistentTag)' and set '$correctTagName' = '$($item.TagValue)'" -ForegroundColor Yellow
        
        $response = Read-Host "Proceed with this change? (Y/N/A for Yes to All)"
        
        if ($response -eq "A" -or $response -eq "a") {
            $yesToAll = $true
        } elseif ($response -ne "Y" -and $response -ne "y") {
            Write-Host "Skipped." -ForegroundColor Yellow
            $skippedCount++
            continue
        }
    }
    
    try {
        # Remove the old inconsistent tag first
        $tagToRemove = @{ $item.InconsistentTag = $item.TagValue }
        Write-Host "  Removing tag '$($item.InconsistentTag)'..." -ForegroundColor Gray
        Update-AzTag -ResourceId $item.Resource.ResourceId -Tag $tagToRemove -Operation Delete | Out-Null
        
        # Wait 10 seconds before adding the new tag
        Write-Host "  Waiting 10 seconds before adding correct tag..." -ForegroundColor Gray
        Start-Sleep -Seconds 10
        
        # Add/update the correct tag
        $tagToAdd = @{ $correctTagName = $item.TagValue }
        Write-Host "  Adding tag '$correctTagName' = '$($item.TagValue)'..." -ForegroundColor Gray
        Update-AzTag -ResourceId $item.Resource.ResourceId -Tag $tagToAdd -Operation Merge | Out-Null
        
        Write-Host "✓ Successfully remediated: $($item.ResourceName)" -ForegroundColor Green
        $remediatedCount++
        
    } catch {
        Write-Host "✗ Error remediating $($item.ResourceName): $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Remediation Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total resources processed: $($resourcesToRemediate.Count)" -ForegroundColor White
Write-Host "Successfully remediated: $remediatedCount" -ForegroundColor Green
Write-Host "Skipped: $skippedCount" -ForegroundColor Yellow
Write-Host "Errors: $errorCount" -ForegroundColor Red
Write-Host "========================================`n" -ForegroundColor Cyan
