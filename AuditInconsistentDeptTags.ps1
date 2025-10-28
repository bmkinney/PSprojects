# Audit Inconsistent Department Code Tags
# This script identifies resources with non-standard department tag names across all subscriptions

# Ensure you're logged in to Azure
# Run: Connect-AzAccount if not already authenticated

Write-Host "Scanning Azure resources for inconsistent department tags across all subscriptions..." -ForegroundColor Cyan

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
Write-Host "Retrieving all accessible subscriptions..." -ForegroundColor Yellow
$subscriptions = Get-AzSubscription

Write-Host "Found $($subscriptions.Count) subscription(s). Processing..." -ForegroundColor Yellow

# Array to store results
$inconsistentResources = @()

# Iterate through each subscription
foreach ($subscription in $subscriptions) {
    Write-Host "`nProcessing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Cyan
    
    # Set the context to the current subscription
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null
    
    # Get all resources with tags in this subscription
    $allResources = Get-AzResource | Where-Object { $_.Tags -ne $null }
    
    Write-Host "  Found $($allResources.Count) resources with tags in this subscription..." -ForegroundColor Yellow
    
    foreach ($resource in $allResources) {
        $tags = $resource.Tags
        
        # Check if resource has the correct tag already
        $hasCorrectTag = $tags.ContainsKey($correctTagName)
        
        # Check for variations
        foreach ($variation in $deptTagVariations) {
            # Case-insensitive search through all tag keys
            $matchingKey = $tags.Keys | Where-Object { $_ -eq $variation }
            
            if ($matchingKey) {
                $inconsistentResources += [PSCustomObject]@{
                    SubscriptionName = $subscription.Name
                    SubscriptionId   = $subscription.Id
                    ResourceName     = $resource.Name
                    ResourceType     = $resource.ResourceType
                    ResourceGroup    = $resource.ResourceGroupName
                    Location         = $resource.Location
                    InconsistentTag  = $matchingKey
                    TagValue         = $tags[$matchingKey]
                    HasCorrectTag    = $hasCorrectTag
                    ResourceId       = $resource.ResourceId
                }
            }
        }
    }
}

# Display results
if ($inconsistentResources.Count -eq 0) {
    Write-Host "`nNo resources found with inconsistent department tag names across all subscriptions!" -ForegroundColor Green
} else {
    Write-Host "`nFound $($inconsistentResources.Count) resources with inconsistent department tags across all subscriptions:" -ForegroundColor Red
    
    # Display in table format
    $inconsistentResources | Format-Table -Property SubscriptionName, ResourceName, ResourceType, ResourceGroup, InconsistentTag, TagValue, HasCorrectTag -AutoSize
    
    # Option to export to CSV
    $exportChoice = Read-Host "`nWould you like to export these results to CSV? (Y/N)"
    if ($exportChoice -eq 'Y' -or $exportChoice -eq 'y') {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $exportPath = "c:\Users\briankinney\source\repos\AzurePolicy\InconsistentDeptTags_$timestamp.csv"
        $inconsistentResources | Export-Csv -Path $exportPath -NoTypeInformation
        Write-Host "Results exported to: $exportPath" -ForegroundColor Green
    }
    
    # Summary by tag variation
    Write-Host "`nSummary by Tag Name:" -ForegroundColor Cyan
    $inconsistentResources | Group-Object -Property InconsistentTag | 
        Select-Object Name, Count | 
        Sort-Object Count -Descending | 
        Format-Table -AutoSize
}

Write-Host "`nAudit complete!" -ForegroundColor Cyan
