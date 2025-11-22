<#
.SYNOPSIS
    Network Optimization and Speed Testing Script
.DESCRIPTION
    Optimizes Windows network settings and performs internet speed tests. Generates a visual HTML report.
.NOTES
    Author: Brian Kinney
    License: MIT
    Platform: Windows only
    Requires: PowerShell 5+, Administrator privileges
#>

# Cross-platform check
if ($env:OS -notlike '*Windows*') {
    Write-Host "This script is designed for Windows only." -ForegroundColor Red
    exit
}

# Admin check
function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Logging
$global:LogFile = Join-Path $PSScriptRoot "network-optimizer.log"
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$timestamp $Message" | Out-File -FilePath $global:LogFile -Append -Encoding UTF8
}

# Validate Y/N input
function Get-YesNo {
    param([string]$Prompt)
    while ($true) {
        $input = Read-Host $Prompt
        if ($input -match '^(Y|y|N|n)$') { return $input }
        Write-Host "Please enter Y or N." -ForegroundColor Yellow
    }
}

# Global variable to store test results
$script:TestResults = @{
    Timestamp = Get-Date
    NetworkInfo = @()
    CurrentSettings = @{}
    SpeedTest = @{}
    DownloadTests = @()
    OptimizationsApplied = $false
}

Write-Host "=== Network Optimizer & Speed Test ===" -ForegroundColor Cyan
Write-Host ""



function Get-NetworkSettings {
    Write-Host "Checking Current Network Settings..." -ForegroundColor Yellow
    Write-Log "Checking current network settings."
    
    $settings = @{}
    
    try {
        # Get TCP settings
        $tcpOutput = netsh int tcp show global | Out-String
        
        # Debug: Show raw output if patterns don't match
        # Write-Host "DEBUG OUTPUT:" -ForegroundColor Gray
        # Write-Host $tcpOutput -ForegroundColor Gray
        
        # Parse TCP settings with more flexible patterns
        if ($tcpOutput -match "(?:Receive Window Auto-Tuning Level|Auto-Tuning Level)\s*[:\-]\s*(\w+)") {
            $settings.AutoTuningLevel = $matches[1]
        } else {
            $settings.AutoTuningLevel = "Unknown"
        }
        
        if ($tcpOutput -match "ECN Capability\s*[:\-]\s*(\w+)") {
            $settings.ECNCapability = $matches[1]
        } else {
            $settings.ECNCapability = "Unknown"
        }
        
        if ($tcpOutput -match "(?:Timestamps|RFC 1323 Timestamps)\s*[:\-]\s*(\w+)") {
            $settings.Timestamps = $matches[1]
        } else {
            $settings.Timestamps = "Unknown"
        }
        
        if ($tcpOutput -match "(?:Receive-Side Scaling State|RSS State)\s*[:\-]\s*(\w+)") {
            $settings.RSS = $matches[1]
        } else {
            $settings.RSS = "Unknown"
        }
        
        if ($tcpOutput -match "(?:Receive Segment Coalescing State|RSC State)\s*[:\-]\s*(\w+)") {
            $settings.RSC = $matches[1]
        } else {
            $settings.RSC = "Unknown"
        }
        
        if ($tcpOutput -match "(?:Initial RTO|InitialRto)\s*[:\-]\s*(\d+)") {
            $settings.InitialRTO = $matches[1]
        } else {
            $settings.InitialRTO = "Unknown"
        }
        
        if ($tcpOutput -match "(?:HyStart)\s*[:\-]\s*(\w+)") {
            $settings.HyStart = $matches[1]
        } else {
            $settings.HyStart = "Unknown"
        }
        
        if ($tcpOutput -match "(?:Fast Open)\s*[:\-]\s*(\w+)") {
            $settings.FastOpen = $matches[1]
        } else {
            $settings.FastOpen = "Unknown"
        }
        
        if ($tcpOutput -match "(?:Proportional Rate Reduction|PRR)\s*[:\-]\s*(\w+)") {
            $settings.PRR = $matches[1]
        } else {
            $settings.PRR = "Unknown"
        }
        
        # Check network throttling
        $throttling = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -ErrorAction SilentlyContinue
        $settings.NetworkThrottling = if ($throttling -and $throttling.NetworkThrottlingIndex -eq 4294967295) { "Disabled" } else { "Enabled" }
        
        # Determine if settings are optimized (check for non-Unknown values)
        $isOptimized = (
            $settings.AutoTuningLevel -eq "normal" -and
            ($settings.ECNCapability -eq "enabled" -or $settings.ECNCapability -eq "default") -and
            $settings.RSS -eq "enabled" -and
            $settings.RSC -eq "enabled" -and
            $settings.NetworkThrottling -eq "Disabled"
        )
        
        $settings.IsOptimized = $isOptimized
        
        # Display current settings
        Write-Host "  Current TCP Settings:" -ForegroundColor Cyan
        Write-Host "    Auto-Tuning Level: $($settings.AutoTuningLevel)" -ForegroundColor $(if ($settings.AutoTuningLevel -eq "normal") { "Green" } else { "Yellow" })
        Write-Host "    ECN Capability: $($settings.ECNCapability)" -ForegroundColor $(if ($settings.ECNCapability -match "enabled|default") { "Green" } else { "Yellow" })
        Write-Host "    Timestamps: $($settings.Timestamps)" -ForegroundColor $(if ($settings.Timestamps -ne "disabled") { "Green" } else { "Yellow" })
        Write-Host "    RSS (Receive-Side Scaling): $($settings.RSS)" -ForegroundColor $(if ($settings.RSS -eq "enabled") { "Green" } else { "Yellow" })
        Write-Host "    RSC (Receive Segment Coalescing): $($settings.RSC)" -ForegroundColor $(if ($settings.RSC -eq "enabled") { "Green" } else { "Yellow" })
        Write-Host "    HyStart: $($settings.HyStart)" -ForegroundColor $(if ($settings.HyStart -ne "disabled" -and $settings.HyStart -ne "Unknown") { "Green" } else { "Yellow" })
        Write-Host "    Fast Open: $($settings.FastOpen)" -ForegroundColor $(if ($settings.FastOpen -ne "disabled" -and $settings.FastOpen -ne "Unknown") { "Green" } else { "Yellow" })
        Write-Host "    PRR (Proportional Rate Reduction): $($settings.PRR)" -ForegroundColor $(if ($settings.PRR -ne "disabled" -and $settings.PRR -ne "Unknown") { "Green" } else { "Yellow" })
        Write-Host "    Network Throttling: $($settings.NetworkThrottling)" -ForegroundColor $(if ($settings.NetworkThrottling -eq "Disabled") { "Green" } else { "Yellow" })
        Write-Host ""
        
        if ($isOptimized) {
            Write-Host "  ✓ Network settings are OPTIMIZED" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ Network settings are NOT OPTIMIZED" -ForegroundColor Yellow
            Write-Host "    Consider running optimization to improve performance." -ForegroundColor Yellow
        }
        Write-Host ""
        
        $script:TestResults.CurrentSettings = $settings
        Write-Log "Network settings checked. Optimized: $isOptimized"
    }
    catch {
        Write-Host "  ⚠ Error retrieving network settings: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Log "Error retrieving network settings: $($_.Exception.Message)"
        Write-Host "  This may require administrator privileges." -ForegroundColor Yellow
        Write-Host ""
        $script:TestResults.CurrentSettings = @{
            AutoTuningLevel = "Unknown"
            ECNCapability = "Unknown"
            Timestamps = "Unknown"
            RSS = "Unknown"
            RSC = "Unknown"
            HyStart = "Unknown"
            FastOpen = "Unknown"
            PRR = "Unknown"
            NetworkThrottling = "Unknown"
            IsOptimized = $false
        }
    }
}

function Set-NetworkOptimization {
    Write-Host "Optimizing Network Settings..." -ForegroundColor Yellow
    Write-Log "Optimizing network settings."
    
    try {
        # Disable Large Send Offload for better performance
        Write-Host "  - Configuring network adapter settings..."
        Get-NetAdapterAdvancedProperty -Name "*" -RegistryKeyword "*LSOv2IPv4" -ErrorAction SilentlyContinue | 
            Set-NetAdapterAdvancedProperty -RegistryValue 0 -ErrorAction SilentlyContinue
        
        # Set DNS cache settings
        Write-Host "  - Optimizing DNS cache..."
        Set-DnsClientServerAddress -InterfaceAlias "*" -ResetServerAddresses -ErrorAction SilentlyContinue
        Clear-DnsClientCache
        
        # Optimize TCP settings (using only valid parameters)
        Write-Host "  - Configuring TCP settings..."
        netsh int tcp set global autotuninglevel=normal
        netsh int tcp set global ecncapability=enabled
        netsh int tcp set global timestamps=enabled
        netsh int tcp set global rss=enabled
        netsh int tcp set global rsc=enabled
        netsh int tcp set global hystart=enabled
        netsh int tcp set global fastopen=enabled
        netsh int tcp set global prr=enabled
        
        # Optimize network throttling
        Write-Host "  - Disabling network throttling..."
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" `
            -Name "NetworkThrottlingIndex" -Value 0xffffffff -PropertyType DWord -Force | Out-Null
        # Verify registry change
        $throttleCheck = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -ErrorAction SilentlyContinue
        if ($throttleCheck.NetworkThrottlingIndex -eq 4294967295) {
            Write-Host "  ✓ Network throttling successfully disabled!" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ Network throttling registry value did NOT persist!" -ForegroundColor Yellow
            Write-Host "    Try running PowerShell as Administrator, or check for group policies or security software that may revert this setting." -ForegroundColor Yellow
        }
        $script:TestResults.OptimizationsApplied = $true
        Write-Host "  ✓ Network optimization complete!" -ForegroundColor Green
        Write-Log "Network optimization complete."
        Write-Host ""
    }
    catch {
        Write-Host "  ⚠ Some optimizations may require administrator privileges" -ForegroundColor Yellow
        Write-Log "Optimization failed: $($_.Exception.Message)"
        Write-Host ""
    }
}

function Test-InternetSpeed {
    Write-Host "Running Internet Speed Test..." -ForegroundColor Yellow
    Write-Log "Running internet speed test."
    
    # Check if Speedtest CLI is installed
    $speedtestPath = Get-Command speedtest -ErrorAction SilentlyContinue
    
    if (-not $speedtestPath) {
        Write-Host "  Speedtest CLI not found. Installing..." -ForegroundColor Yellow
        
        # Download and install Speedtest CLI
        $downloadUrl = "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip"
        $zipPath = "$env:TEMP\speedtest.zip"
        $extractPath = "$env:TEMP\speedtest"
        
        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
            $speedtestExe = "$extractPath\speedtest.exe"
        }
        catch {
            Write-Host "  ⚠ Could not download Speedtest CLI. Using alternative method..." -ForegroundColor Yellow
            Test-InternetSpeedAlternative
            return
        }
    }
    else {
        $speedtestExe = "speedtest"
    }
    
    try {
        Write-Host "  Running test (this may take a minute)..." -ForegroundColor Cyan
        & $speedtestExe --accept-license --accept-gdpr
        Write-Log "Speedtest CLI completed."
        Write-Host ""
    }
    catch {
        Write-Host "  ⚠ Speedtest failed, using alternative method..." -ForegroundColor Yellow
        Write-Log "Speedtest CLI failed. Using alternative method."
        Test-InternetSpeedAlternative
    }
}

function Test-InternetSpeedAlternative {
    Write-Host "  Testing latency..." -ForegroundColor Cyan
    Write-Log "Testing latency with ping."
    
    # Test latency
    $ping = Test-Connection -ComputerName "8.8.8.8" -Count 4 -ErrorAction SilentlyContinue
    if ($ping) {
        $avgLatency = ($ping | Measure-Object -Property ResponseTime -Average).Average
        Write-Host "  Average Latency: $([math]::Round($avgLatency, 2)) ms" -ForegroundColor Green
        Write-Log "Ping latency: $([math]::Round($avgLatency, 2)) ms"
        $script:TestResults.SpeedTest = @{
            Latency = [math]::Round($avgLatency, 2)
            Download = 0
            Upload = 0
            Method = "Ping Test"
        }
    }
    
    Write-Host ""
}

function Test-DownloadSpeed {
    Write-Host "Testing Download Speed with Large File..." -ForegroundColor Yellow
    Write-Log "Testing large file download speed."
    
    # Test files from various CDNs - updated URLs
    $testFiles = @(
        @{Url = "https://speed.cloudflare.com/__down?bytes=104857600"; Size = 100; Name = "Cloudflare 100MB"},
        @{Url = "https://ash-speed.hetzner.com/100MB.bin"; Size = 100; Name = "Hetzner 100MB"},
        @{Url = "http://speedtest.tele2.net/100MB.zip"; Size = 100; Name = "Tele2 100MB"}
    )
    
    $downloadPath = "$env:TEMP\speedtest_download.bin"
    
    foreach ($testFile in $testFiles) {
        Write-Host "  Testing: $($testFile.Name)" -ForegroundColor Cyan
        
        try {
            # Remove existing file
            if (Test-Path $downloadPath) {
                Remove-Item $downloadPath -Force
            }
            
            $startTime = Get-Date
            
            # Download with progress - added headers for Cloudflare
            $ProgressPreference = 'SilentlyContinue'
            $headers = @{
                'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            }
            Invoke-WebRequest -Uri $testFile.Url -OutFile $downloadPath -Headers $headers -UseBasicParsing -TimeoutSec 60 -MaximumRedirection 5
            $ProgressPreference = 'Continue'
            
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            
            if (Test-Path $downloadPath) {
                $fileSize = (Get-Item $downloadPath).Length
                $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
                $speedMbps = [math]::Round(($fileSize * 8) / ($duration * 1000000), 2)
                
                Write-Host "    File Size: $fileSizeMB MB" -ForegroundColor Green
                Write-Host "    Download Time: $([math]::Round($duration, 2)) seconds" -ForegroundColor Green
                Write-Host "    Download Speed: $speedMbps Mbps" -ForegroundColor Green
                Write-Log "Download test: $($testFile.Name) $fileSizeMB MB in $([math]::Round($duration, 2)) sec, $speedMbps Mbps"
                # Store results
                $script:TestResults.DownloadTests += @{
                    Server = $testFile.Name
                    FileSizeMB = $fileSizeMB
                    DurationSeconds = [math]::Round($duration, 2)
                    SpeedMbps = $speedMbps
                }
                # Clean up
                Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
                break
            }
        }
        catch {
            Write-Host "    ⚠ Failed to test with this server: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Log "Download test failed for $($testFile.Name): $($_.Exception.Message)"
            continue
        }
    }
}

function Get-NetworkInfo {
    Write-Host "Current Network Configuration:" -ForegroundColor Yellow
    Write-Log "Getting network adapter info."
    
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    
    foreach ($adapter in $adapters) {
        Write-Host "  Adapter: $($adapter.Name)" -ForegroundColor Cyan
        Write-Host "    Status: $($adapter.Status)" -ForegroundColor Green
        Write-Host "    Link Speed: $($adapter.LinkSpeed)" -ForegroundColor Green
        Write-Log "Adapter: $($adapter.Name), Status: $($adapter.Status), LinkSpeed: $($adapter.LinkSpeed)"
        
        $ipConfig = Get-NetIPAddress -InterfaceAlias $adapter.Name -ErrorAction SilentlyContinue | 
                    Where-Object { $_.AddressFamily -eq "IPv4" }
        if ($ipConfig) {
            Write-Host "    IP Address: $($ipConfig.IPAddress)" -ForegroundColor Green
            Write-Log "IP Address: $($ipConfig.IPAddress)"
        }
        
        # Store network info
        $script:TestResults.NetworkInfo += @{
            Name = $adapter.Name
            Status = $adapter.Status
            LinkSpeed = $adapter.LinkSpeed
            IPAddress = if ($ipConfig) { $ipConfig.IPAddress } else { "N/A" }
        }
        
        Write-Host ""
    }
}

# Function to generate HTML report with graphs
function Generate-HTMLReport {
    param (
        [string]$OutputPath
    )
    
    Write-Host "Generating HTML Report..." -ForegroundColor Yellow
    
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Network Speed Test Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }
        h1 {
            color: #667eea;
            text-align: center;
            margin-bottom: 10px;
        }
        .timestamp {
            text-align: center;
            color: #666;
            margin-bottom: 30px;
            font-size: 14px;
        }
        .section {
            margin-bottom: 30px;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 8px;
        }
        .section h2 {
            color: #764ba2;
            margin-top: 0;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
            margin: 15px 0;
        }
        .info-card {
            background: white;
            padding: 15px;
            border-radius: 6px;
            border-left: 4px solid #667eea;
        }
        .info-card h3 {
            margin: 0 0 10px 0;
            font-size: 14px;
            color: #666;
            text-transform: uppercase;
        }
        .info-card p {
            margin: 5px 0;
            font-size: 16px;
            font-weight: bold;
            color: #333;
        }
        .chart-container {
            position: relative;
            height: 300px;
            margin: 20px 0;
        }
        .metric {
            display: inline-block;
            margin: 10px 20px 10px 0;
            padding: 15px 25px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 8px;
            font-weight: bold;
        }
        .metric-label {
            font-size: 12px;
            opacity: 0.9;
        }
        .metric-value {
            font-size: 24px;
            margin-top: 5px;
        }
        .status-badge {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: bold;
        }
        .status-success {
            background: #28a745;
            color: white;
        }
        .status-warning {
            background: #ffc107;
            color: #333;
        }
        @media print {
            body {
                background: white;
            }
            .container {
                box-shadow: none;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Network Speed Test Report</h1>
        <div class="timestamp">Generated: $($script:TestResults.Timestamp.ToString('MMMM dd, yyyy HH:mm:ss'))</div>
        
        <div class="section">
            <h2>📊 Network Configuration</h2>
            <div class="info-grid">
"@

    # Add network adapter info
    foreach ($adapter in $script:TestResults.NetworkInfo) {
        $html += @"
                <div class="info-card">
                    <h3>$($adapter.Name)</h3>
                    <p>Status: <span class="status-badge status-success">$($adapter.Status)</span></p>
                    <p>Speed: $($adapter.LinkSpeed)</p>
                    <p>IP: $($adapter.IPAddress)</p>
                </div>
"@
    }

    $html += @"
            </div>
        </div>
"@

    # Add current network settings section
    if ($script:TestResults.CurrentSettings.Count -gt 0) {
        $settings = $script:TestResults.CurrentSettings
        $optimizationStatus = if ($settings.IsOptimized) { "Optimized" } else { "Not Optimized" }
        $optimizationClass = if ($settings.IsOptimized) { "status-success" } else { "status-warning" }
        $html += @"
        <div class=\"section\">
            <h2>⚙️ Current Network Settings</h2>
            <p>Status: <span class=\"status-badge $optimizationClass\">$optimizationStatus</span></p>
            <div class=\"info-grid\">
                <div class=\"info-card\">
                    <h3>Auto-Tuning Level</h3>
                    <p>$($settings.AutoTuningLevel)</p>
                </div>
                <div class=\"info-card\">
                    <h3>ECN Capability</h3>
                    <p>$($settings.ECNCapability)</p>
                </div>
                <div class=\"info-card\">
                    <h3>Timestamps</h3>
                    <p>$($settings.Timestamps)</p>
                </div>
                <div class=\"info-card\">
                    <h3>RSS (Receive-Side Scaling)</h3>
                    <p>$($settings.RSS)</p>
                </div>
                <div class=\"info-card\">
                    <h3>RSC (Receive Segment Coalescing)</h3>
                    <p>$($settings.RSC)</p>
                </div>
                <div class=\"info-card\">
                    <h3>HyStart</h3>
                    <p>$($settings.HyStart)</p>
                </div>
                <div class=\"info-card\">
                    <h3>Fast Open</h3>
                    <p>$($settings.FastOpen)</p>
                </div>
                <div class=\"info-card\">
                    <h3>PRR</h3>
                    <p>$($settings.PRR)</p>
                </div>
                <div class=\"info-card\">
                    <h3>Network Throttling</h3>
                    <p>$($settings.NetworkThrottling)</p>
                </div>
            </div>
        </div>
"@
    }

    # Add speed test results if available
    if ($script:TestResults.SpeedTest.Count -gt 0) {
        $latency = if ($script:TestResults.SpeedTest.Latency) { $script:TestResults.SpeedTest.Latency } else { 0 }
        $download = if ($script:TestResults.SpeedTest.Download) { $script:TestResults.SpeedTest.Download } else { 0 }
        $upload = if ($script:TestResults.SpeedTest.Upload) { $script:TestResults.SpeedTest.Upload } else { 0 }
        
        $html += @"
        <div class="section">
            <h2>⚡ Internet Speed Test</h2>
            <div>
                <div class="metric">
                    <div class="metric-label">LATENCY</div>
                    <div class="metric-value">$latency ms</div>
                </div>
"@
        if ($download -gt 0) {
            $html += @"
                <div class="metric">
                    <div class="metric-label">DOWNLOAD</div>
                    <div class="metric-value">$download Mbps</div>
                </div>
"@
        }
        if ($upload -gt 0) {
            $html += @"
                <div class="metric">
                    <div class="metric-label">UPLOAD</div>
                    <div class="metric-value">$upload Mbps</div>
                </div>
"@
        }
        
        $html += @"
            </div>
            <div class="chart-container">
                <canvas id="speedChart"></canvas>
            </div>
        </div>
"@
    }

    # Add download test results if available
    if ($script:TestResults.DownloadTests.Count -gt 0) {
        $downloadTest = $script:TestResults.DownloadTests[0]
        
        $html += @"
        <div class="section">
            <h2>📥 Large File Download Test</h2>
            <div class="info-grid">
                <div class="info-card">
                    <h3>Server</h3>
                    <p>$($downloadTest.Server)</p>
                </div>
                <div class="info-card">
                    <h3>File Size</h3>
                    <p>$($downloadTest.FileSizeMB) MB</p>
                </div>
                <div class="info-card">
                    <h3>Duration</h3>
                    <p>$($downloadTest.DurationSeconds) seconds</p>
                </div>
                <div class="info-card">
                    <h3>Speed</h3>
                    <p>$($downloadTest.SpeedMbps) Mbps</p>
                </div>
            </div>
            <div class="chart-container">
                <canvas id="downloadChart"></canvas>
            </div>
        </div>
"@
    }

    # Add optimization status
    $optimizationStatus = if ($script:TestResults.OptimizationsApplied) { "Applied" } else { "Not Applied" }
    $optimizationClass = if ($script:TestResults.OptimizationsApplied) { "status-success" } else { "status-warning" }
    
    $html += @"
        <div class="section">
            <h2>⚙️ Network Optimizations</h2>
            <p>Status: <span class="status-badge $optimizationClass">$optimizationStatus</span></p>
            <p style="margin-top: 15px; color: #666; font-size: 14px;">
                Optimizations include: TCP auto-tuning, ECN capability, RSS, RSC, HyStart, Fast Open, PRR, and network throttling disabled.
            </p>
        </div>
        
        <script>
            // Speed Test Chart
"@

    if ($script:TestResults.SpeedTest.Count -gt 0) {
        $latency = if ($script:TestResults.SpeedTest.Latency) { $script:TestResults.SpeedTest.Latency } else { 0 }
        $download = if ($script:TestResults.SpeedTest.Download) { $script:TestResults.SpeedTest.Download } else { 0 }
        $upload = if ($script:TestResults.SpeedTest.Upload) { $script:TestResults.SpeedTest.Upload } else { 0 }
        
        $html += @"
            const speedCtx = document.getElementById('speedChart').getContext('2d');
            new Chart(speedCtx, {
                type: 'bar',
                data: {
                    labels: ['Latency (ms)', 'Download (Mbps)', 'Upload (Mbps)'],
                    datasets: [{
                        label: 'Speed Test Results',
                        data: [$latency, $download, $upload],
                        backgroundColor: [
                            'rgba(102, 126, 234, 0.8)',
                            'rgba(118, 75, 162, 0.8)',
                            'rgba(155, 89, 182, 0.8)'
                        ],
                        borderColor: [
                            'rgba(102, 126, 234, 1)',
                            'rgba(118, 75, 162, 1)',
                            'rgba(155, 89, 182, 1)'
                        ],
                        borderWidth: 2
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            display: false
                        }
                    },
                    scales: {
                        y: {
                            beginAtZero: true
                        }
                    }
                }
            });
"@
    }

    if ($script:TestResults.DownloadTests.Count -gt 0) {
        $downloadTest = $script:TestResults.DownloadTests[0]
        $expectedTime = [math]::Round($downloadTest.FileSizeMB / ($downloadTest.SpeedMbps / 8), 2)
        
        $html += @"
            
            // Download Test Chart
            const downloadCtx = document.getElementById('downloadChart').getContext('2d');
            new Chart(downloadCtx, {
                type: 'doughnut',
                data: {
                    labels: ['Download Speed (Mbps)', 'Theoretical Max (100 Mbps)'],
                    datasets: [{
                        data: [$($downloadTest.SpeedMbps), $(100 - $downloadTest.SpeedMbps)],
                        backgroundColor: [
                            'rgba(118, 75, 162, 0.8)',
                            'rgba(200, 200, 200, 0.3)'
                        ],
                        borderColor: [
                            'rgba(118, 75, 162, 1)',
                            'rgba(200, 200, 200, 0.5)'
                        ],
                        borderWidth: 2
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            position: 'bottom'
                        }
                    }
                }
            });
"@
    }

    $html += @"
        </script>
    </div>
</body>
</html>
"@

    # Save HTML file
    $html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "  ✓ Report saved to: $OutputPath" -ForegroundColor Green
    
    # Open in browser
    Start-Process $OutputPath
    Write-Host "  ✓ Opening report in default browser..." -ForegroundColor Green
    Write-Host ""
    Write-Host "  💡 Tip: Use your browser's 'Print to PDF' feature to save as PDF" -ForegroundColor Cyan
    Write-Host ""
}

# Main execution
try {
    if (-not (Test-Admin)) {
        Write-Host "⚠ Warning: Not running as Administrator. Some optimizations may be skipped." -ForegroundColor Yellow
        Write-Log "Not running as Administrator."
        Write-Host "  For full optimization, run PowerShell as Administrator and execute this script again." -ForegroundColor Yellow
        Write-Host ""
        $continue = Get-YesNo "Continue anyway? (Y/N)"
        if ($continue -notin @('Y','y')) { exit }
        Write-Host ""
    }
    # Show current network info
    Get-NetworkInfo
    # Check current network settings
    Get-NetworkSettings
    # Optimize network settings
    if (Test-Admin) {
        $optimize = Get-YesNo "Optimize network settings? (Y/N)"
        if ($optimize -match '^(Y|y)$') { Set-NetworkOptimization }
    }
    # Run speed test
    $speedTest = Get-YesNo "Run internet speed test? (Y/N)"
    if ($speedTest -match '^(Y|y)$') { Test-InternetSpeed }
    # Test large file download
    $downloadTest = Get-YesNo "Test download speed with large file? (Y/N)"
    if ($downloadTest -match '^(Y|y)$') { Test-DownloadSpeed }
    Write-Host "=== Testing Complete ===" -ForegroundColor Cyan
    Write-Log "Testing complete."
    Write-Host ""
    # Generate report in the script directory
    $reportPath = Join-Path $PSScriptRoot "Network-Speed-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    Generate-HTMLReport -OutputPath $reportPath
    Write-Log "Report generated: $reportPath"
    Write-Host "Note: Network optimizations may require a restart to take full effect." -ForegroundColor Yellow
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Log "Error: $_"
}

