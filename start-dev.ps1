<#
.SYNOPSIS
    Portable dev-session launcher: starts a dev server, opens a shared
    Chromium-based browser with CDP, and sets the live-browser base URL.

.DESCRIPTION
    Works on any repo that has a package.json with a "dev", "start", or
    "serve" script.  Auto-detects the port and base path from config files
    when possible.  Override any value with parameters.

.PARAMETER DevCommand
    npm script to run (default: auto-detect from package.json).

.PARAMETER Port
    Port the dev server listens on (default: auto-detect).

.PARAMETER BasePath
    URL base path, e.g. "/my-repo" (default: auto-detect from config).

.PARAMETER Url
    Full URL to open.  Overrides Port and BasePath.

.PARAMETER EdgeDebugPort
    CDP port for Edge (default: 9222).

.PARAMETER Browser
    Preferred Chromium-based browser name, such as "edge", "chrome",
    "brave", or "vivaldi".

.PARAMETER BrowserPath
    Full path to a Chromium-based browser executable.

.PARAMETER NoBrowserPrompt
    Do not prompt when multiple browsers are found. Use the first discovered
    browser, preferring running browsers.

.PARAMETER SkipServer
    Do not start or detect a local dev server. Use this for arbitrary live
    websites, userscript workflows, or extension page analysis.

.PARAMETER SkipBrowser
    Start only the dev server, skip launching the browser.
#>

param(
    [string]$ProjectRoot = (Get-Location).Path,
    [string]$DevCommand,
    [int]$Port,
    [string]$BasePath,
    [string]$Url,
    [int]$EdgeDebugPort = 9222,
    [string]$Browser,
    [string]$BrowserPath,
    [switch]$NoBrowserPrompt,
    [switch]$SkipServer,
    [switch]$SkipBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ResolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

# ---- helpers ----

function Get-PackageJson {
    param([string]$RootPath)

    $packagePath = Join-Path $RootPath "package.json"
    if (-not (Test-Path $packagePath)) {
        Write-Error "No package.json found in $RootPath"
        exit 1
    }
    return Get-Content $packagePath -Raw | ConvertFrom-Json
}

function Find-DevScript {
    param($pkg)
    foreach ($name in @("dev", "start", "serve")) {
        $script = $pkg.scripts.$name
        if ($script) { return $name }
    }
    Write-Error "No dev/start/serve script found in package.json"
    exit 1
}

function Detect-Port {
    param($pkg, [string]$scriptName)
    $script = $pkg.scripts.$scriptName
    # Check for explicit --port flag in the script
    if ($script -match '--port[= ]+(\d+)') {
        return [int]$Matches[1]
    }

    # Framework defaults
    if ($script -match 'astro')     { return 4321 }
    if ($script -match 'next')      { return 3000 }
    if ($script -match 'nuxt')      { return 3000 }
    if ($script -match 'vite')      { return 5173 }
    if ($script -match 'webpack')   { return 8080 }
    if ($script -match 'gatsby')    { return 8000 }
    if ($script -match 'remix')     { return 3000 }
    if ($script -match 'angular')   { return 4200 }
    if ($script -match 'ng ')       { return 4200 }

    # Fallback
    return 3000
}

function Detect-BasePath {
    param([string]$RootPath)

    # Astro: base in astro.config.mjs / astro.config.ts
    foreach ($name in @("astro.config.mjs", "astro.config.ts", "astro.config.js")) {
        $configPath = Join-Path $RootPath $name
        if (Test-Path $configPath) {
            $content = Get-Content $configPath -Raw
            if ($content -match 'base\s*[:=]\s*[''"]([^''"]+)[''"]') {
                return $Matches[1]
            }
        }
    }

    # Vite: base in vite.config.*
    foreach ($name in @("vite.config.ts", "vite.config.js", "vite.config.mjs")) {
        $configPath = Join-Path $RootPath $name
        if (Test-Path $configPath) {
            $content = Get-Content $configPath -Raw
            if ($content -match 'base\s*:\s*[''"]([^''"]+)[''"]') {
                return $Matches[1]
            }
        }
    }

    # Next.js: basePath in next.config.*
    foreach ($name in @("next.config.js", "next.config.mjs", "next.config.ts")) {
        $configPath = Join-Path $RootPath $name
        if (Test-Path $configPath) {
            $content = Get-Content $configPath -Raw
            if ($content -match 'basePath\s*:\s*[''"]([^''"]+)[''"]') {
                return $Matches[1]
            }
        }
    }

    return ""
}

function Test-ServerReady {
    param([string]$testUrl)
    try {
        $response = Invoke-WebRequest -Uri $testUrl -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
        return ($null -ne $response)
    } catch {
        return $false
    }
}

# ---- main ----

if ($SkipServer) {
    if (-not $Url) {
        Write-Error "-Url is required when -SkipServer is used."
        exit 1
    }

    Write-Host "Dev server : skipped"
    Write-Host "URL        : $Url"
    Write-Host ""
} else {
    $pkg = Get-PackageJson -RootPath $ResolvedProjectRoot

    # Resolve dev command
    if (-not $DevCommand) {
        $DevCommand = Find-DevScript $pkg
    }

    # Resolve port
    if ($Port -eq 0) {
        $Port = Detect-Port $pkg $DevCommand
    }

    # Resolve base path
    if (-not $BasePath) {
        $BasePath = Detect-BasePath -RootPath $ResolvedProjectRoot
    }

    # Build the full URL
    if (-not $Url) {
        $basePart = $BasePath.TrimStart("/")
        if ($basePart) {
            $Url = "http://localhost:$Port/$basePart/"
        } else {
            $Url = "http://localhost:$Port/"
        }
    }

    Write-Host "Dev command : npm run $DevCommand"
    Write-Host "Port        : $Port"
    Write-Host "Base path   : $(if ($BasePath) { $BasePath } else { '(none)' })"
    Write-Host "URL         : $Url"
    Write-Host ""

    # Check if server is already running
    $alreadyRunning = Test-ServerReady $Url
    if ($alreadyRunning) {
        Write-Host "Dev server is already running at $Url"
    } else {
        Write-Host "Starting dev server (npm run $DevCommand)..."
        # Start in a minimised window so it does not block
        $npmPath = (Get-Command npm -ErrorAction SilentlyContinue).Source
        if (-not $npmPath) {
            Write-Error "npm not found on PATH"
            exit 1
        }
        Start-Process cmd.exe -ArgumentList ('/c', 'cd /d', ('"' + $ResolvedProjectRoot + '"'), '&&', 'npm', 'run', $DevCommand) `
            -WindowStyle Minimized

        # Poll until the server responds (up to 60 s)
        $maxWait = 60
        $elapsed = 0
        while (-not (Test-ServerReady $Url)) {
            Start-Sleep -Seconds 2
            $elapsed += 2
            if ($elapsed -ge $maxWait) {
                Write-Warning "Dev server did not respond after ${maxWait}s.  Continuing anyway..."
                break
            }
            Write-Host "  Waiting for server... (${elapsed}s)"
        }
        if (Test-ServerReady $Url) {
            Write-Host "Dev server is ready."
        }
    }
}

# Set environment variable so live-browser.mjs picks up the URL
$env:PLAYWRIGHT_LIVE_BASE_URL = $Url

# Launch shared browser
if (-not $SkipBrowser) {
    Write-Host ""
    Write-Host "Launching shared Chromium browser (CDP port $EdgeDebugPort)..."

    $launchScript = Join-Path $PSScriptRoot "launch-browsers.ps1"
    if (Test-Path $launchScript) {
        $launchArgs = @{
            Url = $Url
            EdgeDebugPort = $EdgeDebugPort
        }
        if ($Browser) {
            $launchArgs.Browser = $Browser
        }
        if ($BrowserPath) {
            $launchArgs.BrowserPath = $BrowserPath
        }
        if ($NoBrowserPrompt) {
            $launchArgs.NoPrompt = $true
        }

        & $launchScript @launchArgs
    } else {
        # Inline fallback: launch Edge directly
        $edgePath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
        if (-not (Test-Path $edgePath)) {
            $edgePath = "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
        }
        $edgeUserData = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data"
        $edgeArgs = @(
            ('--remote-debugging-port=' + $EdgeDebugPort),
            ('--user-data-dir="' + $edgeUserData + '"'),
            $Url
        )
        Start-Process $edgePath -ArgumentList $edgeArgs
    }
}

Write-Host ""
Write-Host "Project root: $ResolvedProjectRoot"
Write-Host "Ready. Use 'npm run live-browser -- <command>' to interact."
Write-Host "Run  'npm run live-browser -- help' for available commands."
