# OpenClaw Troubleshooting Toolkit

A collection of tools for diagnosing and troubleshooting OpenClaw installations on Windows systems.

## Contents

- [Troubleshoot-Openclaw.ps1](#troubleshoot-openclawps1) - Comprehensive diagnostic script

---

## Troubleshoot-Openclaw.ps1

A PowerShell diagnostic tool that performs automated health checks on your OpenClaw installation, identifying issues with dependencies, configuration, services, and system resources.

### Requirements

- **PowerShell**: Version 5.1 or later (included with Windows 10/11)
- **Operating System**: Windows 10/11 or Windows Server 2016+
- **Permissions**: Administrator rights recommended for full diagnostics

### Quick Start

```powershell
# Run the troubleshooter
.\Troubleshoot-Openclaw.ps1

# Or with execution policy bypass (if needed)
powershell -ExecutionPolicy Bypass -File .\Troubleshoot-Openclaw.ps1
```

### Usage

```powershell
# Basic usage
.\Troubleshoot-Openclaw.ps1

# With verbose output
.\Troubleshoot-Openclaw.ps1 -Verbose

# Custom configuration directory
.\Troubleshoot-Openclaw.ps1 -ConfigDir "D:\MyOpenClaw\.openclaw"
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Verbose` | Switch | Off | Show detailed information for each check |
| `-FixIssues` | Switch | Off | Reserved for future auto-fix functionality |
| `-ConfigDir` | String | `~\.openclaw` | Custom OpenClaw configuration directory |

### Diagnostic Categories

#### 1. Node.js Environment
- Node.js installation and version (≥22.0.0 required)
- npm and pnpm package managers

#### 2. OpenClaw Installation
- OpenClaw CLI availability and version
- Global npm package status

#### 3. Configuration Files
- Config directory (`~/.openclaw/`)
- Main config file (`openclaw.json`) syntax validation
- Gateway mode verification
- Environment file (`.env`)
- Workspace and memory directories

#### 4. API Keys & Authentication
- Anthropic, OpenAI, OpenRouter API keys
- Gateway token configuration

#### 5. Ports & Services
- Gateway port (18789) status
- Bridge port (18790) status
- Stale process detection
- WebSocket connectivity test

#### 6. Optional Dependencies
- Docker and Docker Compose
- Chrome/Chromium (browser automation)
- Ollama (local LLM)
- Git

#### 7. Network Connectivity
- API endpoint reachability (Anthropic, OpenAI, OpenRouter)
- npm registry access
- Proxy detection

#### 8. System Resources
- Memory (minimum 2 GB required)
- Disk space
- CPU information

#### 9. Environment Variables
All `OPENCLAW_*` variables including:
- `OPENCLAW_CONFIG_DIR`
- `OPENCLAW_WORKSPACE_DIR`
- `OPENCLAW_GATEWAY_PORT`
- `OPENCLAW_BRIDGE_PORT`
- `OPENCLAW_GATEWAY_BIND`
- `OPENCLAW_GATEWAY_TOKEN`
- `OPENCLAW_STATE_DIR`

### Output Format

The script uses color-coded status indicators:

| Icon | Color | Meaning |
|------|-------|---------|
| `[OK]` | Green | Check passed |
| `[!!]` | Yellow | Warning - functional but may need attention |
| `[X]` | Red | Failed - requires action |

### Sample Output

```
   ___                    ____ _
  / _ \ _ __   ___ _ __  / ___| | __ ___      __
 | | | | '_ \ / _ \ '_ \| |   | |/ _` \ \ /\ / /
 | |_| | |_) |  __/ | | | |___| | (_| |\ V  V /
  \___/| .__/ \___|_| |_|\____|_|\__,_| \_/\_/
       |_|

  Troubleshooting Script v1.0.0

============================================================
 Node.js Environment
============================================================
  [OK] Node.js Installed: Node.js found in PATH
  [OK] Node.js Version: Version 22.1.0 (>= 22.0.0 required)
  [OK] npm Available: npm version 10.8.0
  [!!] pnpm Available: pnpm not installed (recommended but optional)

...

============================================================
 TROUBLESHOOTING SUMMARY
============================================================

  Total Checks: 32
  Passed: 28 | Warnings: 3 | Failed: 1

  CRITICAL ISSUES:
    - LLM Provider: No API keys found for any LLM provider
      Fix: Set at least one of: ANTHROPIC_API_KEY, OPENAI_API_KEY, or OPENROUTER_API_KEY

  STATUS: OpenClaw installation has issues that need attention

  For more help, visit: https://docs.openclaw.ai/gateway/troubleshooting
  Report issues at: https://github.com/openclaw/openclaw/issues
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checks passed (may have warnings) |
| 1 | One or more critical failures detected |

### Common Issues & Solutions

#### Node.js Version Too Low

```powershell
# Install Node.js 22 LTS
winget install OpenJS.NodeJS.LTS
# Or download from https://nodejs.org/
```

#### No API Keys Configured

```powershell
# Set environment variable
$env:ANTHROPIC_API_KEY = "your-api-key-here"

# Or add to ~/.openclaw/.env
# ANTHROPIC_API_KEY=your-api-key-here
```

#### Gateway Port Already in Use

```powershell
# Find process using port 18789
Get-NetTCPConnection -LocalPort 18789 | Select-Object OwningProcess
Get-Process -Id <PID>

# Or change the port
$env:OPENCLAW_GATEWAY_PORT = "18800"
```

#### Stale Gateway Processes

```powershell
# Stop stale OpenClaw processes
Get-Process -Name "node" | Where-Object { $_.CommandLine -match "openclaw" } | Stop-Process

# Or restart the gateway properly
openclaw gateway restart
```

### Programmatic Usage

The script returns a results object for automation:

```powershell
$results = .\Troubleshoot-Openclaw.ps1

# Access results
$results.Passed.Count    # Number of passed checks
$results.Warnings.Count  # Number of warnings
$results.Failed.Count    # Number of failures

# Iterate failures
foreach ($fail in $results.Failed) {
    Write-Host "$($fail.Check): $($fail.Message)"
}
```

---

## Resources

- [OpenClaw Documentation](https://docs.openclaw.ai/)
- [Troubleshooting Guide](https://docs.openclaw.ai/gateway/troubleshooting)
- [GitHub Issues](https://github.com/openclaw/openclaw/issues)

## License

MIT License
