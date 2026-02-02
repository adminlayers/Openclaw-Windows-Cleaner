<#
.SYNOPSIS
    OpenClaw Installation Troubleshooting Script
.DESCRIPTION
    This script performs comprehensive diagnostics on an OpenClaw installation,
    checking all critical components, services, configurations, and dependencies.
.NOTES
    Author: OpenClaw Troubleshooter
    Version: 1.0.0
    Requires: PowerShell 5.1 or later
#>

[CmdletBinding()]
param(
    [switch]$Verbose,
    [switch]$FixIssues,
    [string]$ConfigDir = "$env:USERPROFILE\.openclaw"
)

#region Configuration
$script:GatewayPort = 18789
$script:BridgePort = 18790
$script:MinNodeVersion = [version]"22.0.0"
$script:Results = @{
    Passed = @()
    Warnings = @()
    Failed = @()
}
#endregion

#region Helper Functions
function Write-CheckHeader {
    param([string]$Title)
    Write-Host "`n" -NoNewline
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
}

function Write-CheckResult {
    param(
        [string]$Check,
        [ValidateSet('Pass', 'Warn', 'Fail')]
        [string]$Status,
        [string]$Message,
        [string]$Details = ""
    )

    $icon = switch ($Status) {
        'Pass' { '[OK]'; $color = 'Green' }
        'Warn' { '[!!]'; $color = 'Yellow' }
        'Fail' { '[X]'; $color = 'Red' }
    }

    Write-Host "  $icon " -ForegroundColor $color -NoNewline
    Write-Host "$Check`: " -NoNewline
    Write-Host $Message -ForegroundColor $color

    if ($Details -and $Verbose) {
        Write-Host "      Details: $Details" -ForegroundColor DarkGray
    }

    $result = @{
        Check = $Check
        Message = $Message
        Details = $Details
    }

    switch ($Status) {
        'Pass' { $script:Results.Passed += $result }
        'Warn' { $script:Results.Warnings += $result }
        'Fail' { $script:Results.Failed += $result }
    }
}

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Get-ProcessByPort {
    param([int]$Port)
    try {
        $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        if ($connections) {
            $pids = $connections | Select-Object -ExpandProperty OwningProcess -Unique
            foreach ($pid in $pids) {
                Get-Process -Id $pid -ErrorAction SilentlyContinue
            }
        }
    } catch {
        $null
    }
}
#endregion

#region Check Functions
function Test-NodeJsInstallation {
    Write-CheckHeader "Node.js Environment"

    # Check if Node.js is installed
    if (-not (Test-CommandExists "node")) {
        Write-CheckResult -Check "Node.js Installed" -Status Fail `
            -Message "Node.js is not installed or not in PATH" `
            -Details "OpenClaw requires Node.js >= 22. Install from https://nodejs.org/"
        return
    }

    Write-CheckResult -Check "Node.js Installed" -Status Pass -Message "Node.js found in PATH"

    # Check Node.js version
    try {
        $nodeVersionStr = (node --version 2>&1) -replace '^v', ''
        $nodeVersion = [version]$nodeVersionStr

        if ($nodeVersion -ge $script:MinNodeVersion) {
            Write-CheckResult -Check "Node.js Version" -Status Pass `
                -Message "Version $nodeVersionStr (>= 22.0.0 required)"
        } else {
            Write-CheckResult -Check "Node.js Version" -Status Fail `
                -Message "Version $nodeVersionStr is below minimum required (22.0.0)" `
                -Details "Please upgrade Node.js to version 22 or later"
        }
    } catch {
        Write-CheckResult -Check "Node.js Version" -Status Warn `
            -Message "Could not determine Node.js version" `
            -Details $_.Exception.Message
    }

    # Check npm
    if (Test-CommandExists "npm") {
        $npmVersion = npm --version 2>&1
        Write-CheckResult -Check "npm Available" -Status Pass -Message "npm version $npmVersion"
    } else {
        Write-CheckResult -Check "npm Available" -Status Warn `
            -Message "npm not found in PATH"
    }

    # Check for pnpm (preferred)
    if (Test-CommandExists "pnpm") {
        $pnpmVersion = pnpm --version 2>&1
        Write-CheckResult -Check "pnpm Available" -Status Pass `
            -Message "pnpm version $pnpmVersion (preferred package manager)"
    } else {
        Write-CheckResult -Check "pnpm Available" -Status Warn `
            -Message "pnpm not installed (recommended but optional)" `
            -Details "Install with: npm install -g pnpm"
    }
}

function Test-OpenClawInstallation {
    Write-CheckHeader "OpenClaw Installation"

    # Check if openclaw CLI is available
    if (Test-CommandExists "openclaw") {
        Write-CheckResult -Check "OpenClaw CLI" -Status Pass -Message "openclaw command found in PATH"

        # Try to get version
        try {
            $version = openclaw --version 2>&1
            Write-CheckResult -Check "OpenClaw Version" -Status Pass -Message "Version: $version"
        } catch {
            Write-CheckResult -Check "OpenClaw Version" -Status Warn `
                -Message "Could not determine version"
        }
    } else {
        Write-CheckResult -Check "OpenClaw CLI" -Status Fail `
            -Message "openclaw command not found in PATH" `
            -Details "Install OpenClaw following the official documentation"
    }

    # Check global npm installation
    try {
        $globalPackages = npm list -g --depth=0 2>&1
        if ($globalPackages -match "openclaw") {
            Write-CheckResult -Check "Global npm Package" -Status Pass `
                -Message "OpenClaw installed globally via npm"
        }
    } catch {
        # Not necessarily an error
    }
}

function Test-ConfigurationFiles {
    Write-CheckHeader "Configuration Files"

    # Check if config directory exists
    $configDir = if ($env:OPENCLAW_CONFIG_DIR) { $env:OPENCLAW_CONFIG_DIR } else { $ConfigDir }

    if (Test-Path $configDir) {
        Write-CheckResult -Check "Config Directory" -Status Pass `
            -Message "Found at: $configDir"
    } else {
        Write-CheckResult -Check "Config Directory" -Status Warn `
            -Message "Config directory not found at: $configDir" `
            -Details "This may be expected for new installations"
        return
    }

    # Check main config file
    $configFile = Join-Path $configDir "openclaw.json"
    if (Test-Path $configFile) {
        Write-CheckResult -Check "Main Config File" -Status Pass `
            -Message "openclaw.json exists"

        # Validate JSON
        try {
            $configContent = Get-Content $configFile -Raw
            # Remove JSON5 comments for basic validation
            $cleanJson = $configContent -replace '//.*$', '' -replace '/\*[\s\S]*?\*/', ''
            $null = $cleanJson | ConvertFrom-Json
            Write-CheckResult -Check "Config Syntax" -Status Pass -Message "Configuration is valid JSON"

            # Check for gateway mode
            if ($configContent -match '"mode"\s*:\s*"local"') {
                Write-CheckResult -Check "Gateway Mode" -Status Pass `
                    -Message "Gateway mode set to 'local'"
            } else {
                Write-CheckResult -Check "Gateway Mode" -Status Warn `
                    -Message "Gateway mode may not be set to 'local'" `
                    -Details "Ensure gateway.mode is set to 'local' for local execution"
            }
        } catch {
            Write-CheckResult -Check "Config Syntax" -Status Fail `
                -Message "Configuration file has syntax errors" `
                -Details $_.Exception.Message
        }
    } else {
        Write-CheckResult -Check "Main Config File" -Status Warn `
            -Message "openclaw.json not found" `
            -Details "Run 'openclaw' to start the configuration wizard"
    }

    # Check .env file
    $envFile = Join-Path $configDir ".env"
    if (Test-Path $envFile) {
        Write-CheckResult -Check "Environment File" -Status Pass `
            -Message ".env file exists"
    } else {
        Write-CheckResult -Check "Environment File" -Status Warn `
            -Message ".env file not found (optional)"
    }

    # Check workspace directory
    $workspaceDir = if ($env:OPENCLAW_WORKSPACE_DIR) {
        $env:OPENCLAW_WORKSPACE_DIR
    } else {
        Join-Path $configDir "workspace"
    }

    if (Test-Path $workspaceDir) {
        Write-CheckResult -Check "Workspace Directory" -Status Pass `
            -Message "Found at: $workspaceDir"
    } else {
        Write-CheckResult -Check "Workspace Directory" -Status Warn `
            -Message "Workspace directory not found at: $workspaceDir"
    }

    # Check memory directory
    $memoryDir = Join-Path $configDir "memory"
    if (Test-Path $memoryDir) {
        $sqliteFiles = Get-ChildItem -Path $memoryDir -Filter "*.sqlite" -ErrorAction SilentlyContinue
        Write-CheckResult -Check "Memory Storage" -Status Pass `
            -Message "Memory directory exists with $($sqliteFiles.Count) database(s)"
    } else {
        Write-CheckResult -Check "Memory Storage" -Status Warn `
            -Message "Memory directory not found (created on first use)"
    }
}

function Test-ApiKeys {
    Write-CheckHeader "API Keys & Authentication"

    $configDir = if ($env:OPENCLAW_CONFIG_DIR) { $env:OPENCLAW_CONFIG_DIR } else { $ConfigDir }
    $envFile = Join-Path $configDir ".env"
    $configFile = Join-Path $configDir "openclaw.json"

    $hasApiKey = $false

    # Check environment variables
    $apiKeyVars = @(
        @{ Name = "ANTHROPIC_API_KEY"; Provider = "Anthropic" },
        @{ Name = "OPENAI_API_KEY"; Provider = "OpenAI" },
        @{ Name = "OPENROUTER_API_KEY"; Provider = "OpenRouter" }
    )

    foreach ($keyVar in $apiKeyVars) {
        $value = [Environment]::GetEnvironmentVariable($keyVar.Name)
        if ($value) {
            $maskedKey = $value.Substring(0, [Math]::Min(8, $value.Length)) + "..." + $value.Substring([Math]::Max(0, $value.Length - 4))
            Write-CheckResult -Check "$($keyVar.Provider) API Key" -Status Pass `
                -Message "Found in environment ($maskedKey)"
            $hasApiKey = $true
        }
    }

    # Check .env file for API keys
    if (Test-Path $envFile) {
        $envContent = Get-Content $envFile -Raw -ErrorAction SilentlyContinue
        foreach ($keyVar in $apiKeyVars) {
            if (-not [Environment]::GetEnvironmentVariable($keyVar.Name)) {
                if ($envContent -match "$($keyVar.Name)\s*=\s*(.+)") {
                    Write-CheckResult -Check "$($keyVar.Provider) API Key" -Status Pass `
                        -Message "Found in .env file"
                    $hasApiKey = $true
                }
            }
        }
    }

    # Check config file for API keys
    if (Test-Path $configFile) {
        $configContent = Get-Content $configFile -Raw -ErrorAction SilentlyContinue
        if ($configContent -match "anthropic|openai|openrouter" -and $configContent -match "apiKey|api_key") {
            Write-CheckResult -Check "Config API Keys" -Status Pass `
                -Message "API key references found in config file"
            $hasApiKey = $true
        }
    }

    # Check gateway token
    if ($env:OPENCLAW_GATEWAY_TOKEN) {
        Write-CheckResult -Check "Gateway Token" -Status Pass `
            -Message "OPENCLAW_GATEWAY_TOKEN is set"
    } else {
        Write-CheckResult -Check "Gateway Token" -Status Warn `
            -Message "OPENCLAW_GATEWAY_TOKEN not set (may use default)"
    }

    if (-not $hasApiKey) {
        Write-CheckResult -Check "LLM Provider" -Status Fail `
            -Message "No API keys found for any LLM provider" `
            -Details "Set at least one of: ANTHROPIC_API_KEY, OPENAI_API_KEY, or OPENROUTER_API_KEY"
    }
}

function Test-PortsAndServices {
    Write-CheckHeader "Ports & Services"

    # Check Gateway Port
    $gatewayProcess = Get-ProcessByPort $script:GatewayPort
    if ($gatewayProcess) {
        $processName = $gatewayProcess.ProcessName -join ", "
        if ($processName -match "node|openclaw") {
            Write-CheckResult -Check "Gateway Port ($script:GatewayPort)" -Status Pass `
                -Message "OpenClaw Gateway is running (PID: $($gatewayProcess.Id -join ', '))"
        } else {
            Write-CheckResult -Check "Gateway Port ($script:GatewayPort)" -Status Fail `
                -Message "Port is in use by: $processName (PID: $($gatewayProcess.Id -join ', '))" `
                -Details "Stop the conflicting process or configure a different port"
        }
    } else {
        Write-CheckResult -Check "Gateway Port ($script:GatewayPort)" -Status Warn `
            -Message "Port is available (Gateway may not be running)" `
            -Details "Start the gateway with: openclaw gateway start"
    }

    # Check Bridge Port
    $bridgeProcess = Get-ProcessByPort $script:BridgePort
    if ($bridgeProcess) {
        $processName = $bridgeProcess.ProcessName -join ", "
        if ($processName -match "node|openclaw") {
            Write-CheckResult -Check "Bridge Port ($script:BridgePort)" -Status Pass `
                -Message "OpenClaw Bridge is running (PID: $($bridgeProcess.Id -join ', '))"
        } else {
            Write-CheckResult -Check "Bridge Port ($script:BridgePort)" -Status Fail `
                -Message "Port is in use by: $processName" `
                -Details "Stop the conflicting process or configure a different port"
        }
    } else {
        Write-CheckResult -Check "Bridge Port ($script:BridgePort)" -Status Warn `
            -Message "Port is available (Bridge may not be running)"
    }

    # Check for stale processes
    $nodeProcesses = Get-Process -Name "node" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "openclaw" -or $_.MainWindowTitle -match "openclaw" }

    if ($nodeProcesses -and $nodeProcesses.Count -gt 2) {
        Write-CheckResult -Check "Stale Processes" -Status Warn `
            -Message "Multiple OpenClaw-related Node processes detected ($($nodeProcesses.Count))" `
            -Details "Old gateway processes may prevent new ones from starting (Issue #5103)"
    } else {
        Write-CheckResult -Check "Stale Processes" -Status Pass `
            -Message "No stale processes detected"
    }

    # Test WebSocket connectivity
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connectResult = $tcpClient.BeginConnect("127.0.0.1", $script:GatewayPort, $null, $null)
        $wait = $connectResult.AsyncWaitHandle.WaitOne(2000, $false)

        if ($wait -and $tcpClient.Connected) {
            Write-CheckResult -Check "Gateway Connectivity" -Status Pass `
                -Message "Successfully connected to gateway on localhost:$script:GatewayPort"
            $tcpClient.Close()
        } else {
            Write-CheckResult -Check "Gateway Connectivity" -Status Warn `
                -Message "Could not connect to gateway" `
                -Details "Gateway may not be running or accepting connections"
        }
    } catch {
        Write-CheckResult -Check "Gateway Connectivity" -Status Warn `
            -Message "Connection test failed: $($_.Exception.Message)"
    }
}

function Test-OptionalDependencies {
    Write-CheckHeader "Optional Dependencies"

    # Docker
    if (Test-CommandExists "docker") {
        try {
            $dockerVersion = docker --version 2>&1
            $dockerRunning = docker info 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-CheckResult -Check "Docker" -Status Pass `
                    -Message "Installed and running ($dockerVersion)"
            } else {
                Write-CheckResult -Check "Docker" -Status Warn `
                    -Message "Installed but Docker daemon not running" `
                    -Details "Start Docker Desktop or the Docker service"
            }
        } catch {
            Write-CheckResult -Check "Docker" -Status Warn `
                -Message "Docker check failed"
        }
    } else {
        Write-CheckResult -Check "Docker" -Status Warn `
            -Message "Not installed (optional, for containerized sessions)"
    }

    # Docker Compose
    if (Test-CommandExists "docker-compose") {
        Write-CheckResult -Check "Docker Compose" -Status Pass -Message "Available"
    } elseif (Test-CommandExists "docker") {
        # Check for docker compose (v2 plugin)
        $composeV2 = docker compose version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-CheckResult -Check "Docker Compose" -Status Pass `
                -Message "Available (v2 plugin)"
        } else {
            Write-CheckResult -Check "Docker Compose" -Status Warn `
                -Message "Not available"
        }
    }

    # Chrome/Chromium (for browser automation)
    $chromePaths = @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles}\Chromium\Application\chrome.exe"
    )

    $chromeFound = $false
    foreach ($path in $chromePaths) {
        if (Test-Path $path) {
            $chromeVersion = (Get-Item $path).VersionInfo.FileVersion
            Write-CheckResult -Check "Chrome/Chromium" -Status Pass `
                -Message "Found at: $path (v$chromeVersion)"
            $chromeFound = $true
            break
        }
    }

    if (-not $chromeFound) {
        Write-CheckResult -Check "Chrome/Chromium" -Status Warn `
            -Message "Not found (optional, for browser automation)"
    }

    # Ollama (local LLM)
    if (Test-CommandExists "ollama") {
        try {
            $ollamaVersion = ollama --version 2>&1
            Write-CheckResult -Check "Ollama" -Status Pass `
                -Message "Installed ($ollamaVersion)"

            # Check if Ollama is running
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -TimeoutSec 2 -ErrorAction Stop
                Write-CheckResult -Check "Ollama Service" -Status Pass `
                    -Message "Running and accessible"
            } catch {
                Write-CheckResult -Check "Ollama Service" -Status Warn `
                    -Message "Not running or not accessible on port 11434"
            }
        } catch {
            Write-CheckResult -Check "Ollama" -Status Warn -Message "Version check failed"
        }
    } else {
        Write-CheckResult -Check "Ollama" -Status Warn `
            -Message "Not installed (optional, for local LLM support)"
    }

    # Git
    if (Test-CommandExists "git") {
        $gitVersion = git --version 2>&1
        Write-CheckResult -Check "Git" -Status Pass -Message $gitVersion
    } else {
        Write-CheckResult -Check "Git" -Status Warn `
            -Message "Not installed (recommended for version control)"
    }
}

function Test-NetworkConnectivity {
    Write-CheckHeader "Network Connectivity"

    $endpoints = @(
        @{ Name = "Anthropic API"; Url = "https://api.anthropic.com" },
        @{ Name = "OpenAI API"; Url = "https://api.openai.com" },
        @{ Name = "OpenRouter API"; Url = "https://openrouter.ai" },
        @{ Name = "npm Registry"; Url = "https://registry.npmjs.org" }
    )

    foreach ($endpoint in $endpoints) {
        try {
            $response = Invoke-WebRequest -Uri $endpoint.Url -Method Head -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            Write-CheckResult -Check $endpoint.Name -Status Pass `
                -Message "Reachable (HTTP $($response.StatusCode))"
        } catch [System.Net.WebException] {
            if ($_.Exception.Response) {
                # Got a response, even if it's an error code
                Write-CheckResult -Check $endpoint.Name -Status Pass `
                    -Message "Reachable (endpoint responded)"
            } else {
                Write-CheckResult -Check $endpoint.Name -Status Fail `
                    -Message "Not reachable" `
                    -Details $_.Exception.Message
            }
        } catch {
            Write-CheckResult -Check $endpoint.Name -Status Fail `
                -Message "Connection failed" `
                -Details $_.Exception.Message
        }
    }

    # Check for proxy settings
    $proxySettings = [System.Net.WebRequest]::GetSystemWebProxy()
    $testUri = [Uri]"https://api.anthropic.com"
    $proxyUri = $proxySettings.GetProxy($testUri)

    if ($proxyUri -ne $testUri) {
        Write-CheckResult -Check "Proxy Configuration" -Status Warn `
            -Message "System proxy detected: $proxyUri" `
            -Details "Ensure proxy allows connections to AI API endpoints"
    } else {
        Write-CheckResult -Check "Proxy Configuration" -Status Pass `
            -Message "No system proxy configured"
    }
}

function Test-SystemResources {
    Write-CheckHeader "System Resources"

    # Memory
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedPercent = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)

    if ($totalMemoryGB -ge 2) {
        Write-CheckResult -Check "Total Memory" -Status Pass `
            -Message "$totalMemoryGB GB (minimum 2 GB required)"
    } else {
        Write-CheckResult -Check "Total Memory" -Status Fail `
            -Message "$totalMemoryGB GB (minimum 2 GB required)"
    }

    if ($freeMemoryGB -ge 1) {
        Write-CheckResult -Check "Available Memory" -Status Pass `
            -Message "$freeMemoryGB GB free ($usedPercent% used)"
    } else {
        Write-CheckResult -Check "Available Memory" -Status Warn `
            -Message "$freeMemoryGB GB free ($usedPercent% used)" `
            -Details "Low memory may cause performance issues"
    }

    # Disk Space
    $configDir = if ($env:OPENCLAW_CONFIG_DIR) { $env:OPENCLAW_CONFIG_DIR } else { $ConfigDir }
    $drive = (Split-Path -Qualifier $configDir)

    if ($drive) {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'"
        if ($disk) {
            $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $totalSpaceGB = [math]::Round($disk.Size / 1GB, 2)

            if ($freeSpaceGB -ge 5) {
                Write-CheckResult -Check "Disk Space ($drive)" -Status Pass `
                    -Message "$freeSpaceGB GB free of $totalSpaceGB GB"
            } elseif ($freeSpaceGB -ge 1) {
                Write-CheckResult -Check "Disk Space ($drive)" -Status Warn `
                    -Message "$freeSpaceGB GB free of $totalSpaceGB GB" `
                    -Details "Consider freeing up disk space"
            } else {
                Write-CheckResult -Check "Disk Space ($drive)" -Status Fail `
                    -Message "$freeSpaceGB GB free of $totalSpaceGB GB" `
                    -Details "Critically low disk space"
            }
        }
    }

    # CPU
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average

    Write-CheckResult -Check "CPU" -Status Pass `
        -Message "$($cpu.Name) ($($cpu.NumberOfCores) cores, $([math]::Round($cpuLoad, 1))% load)"
}

function Test-EnvironmentVariables {
    Write-CheckHeader "Environment Variables"

    $openclawVars = @(
        @{ Name = "OPENCLAW_CONFIG_DIR"; Default = "$env:USERPROFILE\.openclaw"; Required = $false },
        @{ Name = "OPENCLAW_WORKSPACE_DIR"; Default = "$env:USERPROFILE\.openclaw\workspace"; Required = $false },
        @{ Name = "OPENCLAW_GATEWAY_PORT"; Default = "18789"; Required = $false },
        @{ Name = "OPENCLAW_BRIDGE_PORT"; Default = "18790"; Required = $false },
        @{ Name = "OPENCLAW_GATEWAY_BIND"; Default = "lan"; Required = $false },
        @{ Name = "OPENCLAW_GATEWAY_TOKEN"; Default = "(auto-generated)"; Required = $false },
        @{ Name = "OPENCLAW_STATE_DIR"; Default = "(config dir)"; Required = $false }
    )

    foreach ($var in $openclawVars) {
        $value = [Environment]::GetEnvironmentVariable($var.Name)
        if ($value) {
            Write-CheckResult -Check $var.Name -Status Pass `
                -Message "Set to: $value"
        } else {
            Write-CheckResult -Check $var.Name -Status Pass `
                -Message "Not set (using default: $($var.Default))"
        }
    }
}

function Show-Summary {
    Write-Host "`n"
    Write-Host "=" * 60 -ForegroundColor Magenta
    Write-Host " TROUBLESHOOTING SUMMARY" -ForegroundColor Magenta
    Write-Host "=" * 60 -ForegroundColor Magenta

    $totalChecks = $script:Results.Passed.Count + $script:Results.Warnings.Count + $script:Results.Failed.Count

    Write-Host "`n  Total Checks: $totalChecks" -ForegroundColor White
    Write-Host "  " -NoNewline
    Write-Host "Passed: $($script:Results.Passed.Count)" -ForegroundColor Green -NoNewline
    Write-Host " | " -NoNewline
    Write-Host "Warnings: $($script:Results.Warnings.Count)" -ForegroundColor Yellow -NoNewline
    Write-Host " | " -NoNewline
    Write-Host "Failed: $($script:Results.Failed.Count)" -ForegroundColor Red

    if ($script:Results.Failed.Count -gt 0) {
        Write-Host "`n  CRITICAL ISSUES:" -ForegroundColor Red
        foreach ($fail in $script:Results.Failed) {
            Write-Host "    - $($fail.Check): $($fail.Message)" -ForegroundColor Red
            if ($fail.Details) {
                Write-Host "      Fix: $($fail.Details)" -ForegroundColor DarkRed
            }
        }
    }

    if ($script:Results.Warnings.Count -gt 0) {
        Write-Host "`n  WARNINGS:" -ForegroundColor Yellow
        foreach ($warn in $script:Results.Warnings) {
            Write-Host "    - $($warn.Check): $($warn.Message)" -ForegroundColor Yellow
        }
    }

    Write-Host "`n" -NoNewline

    if ($script:Results.Failed.Count -eq 0 -and $script:Results.Warnings.Count -le 3) {
        Write-Host "  STATUS: " -NoNewline
        Write-Host "OpenClaw installation appears healthy!" -ForegroundColor Green
    } elseif ($script:Results.Failed.Count -eq 0) {
        Write-Host "  STATUS: " -NoNewline
        Write-Host "OpenClaw installation is functional with some warnings" -ForegroundColor Yellow
    } else {
        Write-Host "  STATUS: " -NoNewline
        Write-Host "OpenClaw installation has issues that need attention" -ForegroundColor Red
    }

    Write-Host "`n  For more help, visit: https://docs.openclaw.ai/gateway/troubleshooting" -ForegroundColor Cyan
    Write-Host "  Report issues at: https://github.com/openclaw/openclaw/issues`n" -ForegroundColor Cyan
}
#endregion

#region Main Execution
function Start-Troubleshooting {
    Clear-Host
    Write-Host @"

   ___                    ____ _
  / _ \ _ __   ___ _ __  / ___| | __ ___      __
 | | | | '_ \ / _ \ '_ \| |   | |/ _` \ \ /\ / /
 | |_| | |_) |  __/ | | | |___| | (_| |\ V  V /
  \___/| .__/ \___|_| |_|\____|_|\__,_| \_/\_/
       |_|

  Troubleshooting Script v1.0.0

"@ -ForegroundColor Cyan

    Write-Host "  Starting diagnostics..." -ForegroundColor White
    Write-Host "  Config Directory: $ConfigDir" -ForegroundColor DarkGray
    Write-Host "  Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray

    # Run all checks
    Test-NodeJsInstallation
    Test-OpenClawInstallation
    Test-ConfigurationFiles
    Test-ApiKeys
    Test-PortsAndServices
    Test-OptionalDependencies
    Test-NetworkConnectivity
    Test-SystemResources
    Test-EnvironmentVariables

    # Show summary
    Show-Summary

    # Return results for programmatic use
    return $script:Results
}

# Execute
$results = Start-Troubleshooting

# Exit with appropriate code
if ($results.Failed.Count -gt 0) {
    exit 1
} else {
    exit 0
}
#endregion
