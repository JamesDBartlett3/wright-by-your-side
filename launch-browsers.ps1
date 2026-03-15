param(
    [string]$Url = "http://localhost:3000/",
    [int]$EdgeDebugPort = 9222,
    [string]$Browser,
    [string]$BrowserPath,
    [switch]$ListBrowsers,
    [switch]$NoPrompt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-BrowserCatalog {
    return @(
        [pscustomobject]@{
            Name = "Microsoft Edge"
            Aliases = @("edge", "msedge", "microsoft edge")
            ExecutableNames = @("msedge.exe")
            ProcessNames = @("msedge")
            InstallPaths = @(
                "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
            )
            UserDataDir = (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data")
        },
        [pscustomobject]@{
            Name = "Google Chrome"
            Aliases = @("chrome", "google chrome")
            ExecutableNames = @("chrome.exe")
            ProcessNames = @("chrome")
            InstallPaths = @(
                "C:\Program Files\Google\Chrome\Application\chrome.exe",
                "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
            )
            UserDataDir = (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data")
        },
        [pscustomobject]@{
            Name = "Brave"
            Aliases = @("brave", "brave browser")
            ExecutableNames = @("brave.exe", "brave-browser.exe")
            ProcessNames = @("brave", "brave-browser")
            InstallPaths = @(
                "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
                "C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\brave.exe"
            )
            UserDataDir = (Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data")
        },
        [pscustomobject]@{
            Name = "Vivaldi"
            Aliases = @("vivaldi")
            ExecutableNames = @("vivaldi.exe")
            ProcessNames = @("vivaldi")
            InstallPaths = @(
                "C:\Program Files\Vivaldi\Application\vivaldi.exe",
                "C:\Program Files (x86)\Vivaldi\Application\vivaldi.exe"
            )
            UserDataDir = (Join-Path $env:LOCALAPPDATA "Vivaldi\User Data")
        },
        [pscustomobject]@{
            Name = "Chromium"
            Aliases = @("chromium")
            ExecutableNames = @("chromium.exe")
            ProcessNames = @("chromium")
            InstallPaths = @(
                "C:\Program Files\Chromium\Application\chromium.exe",
                "C:\Program Files (x86)\Chromium\Application\chromium.exe"
            )
            UserDataDir = (Join-Path $env:LOCALAPPDATA "Chromium\User Data")
        },
        [pscustomobject]@{
            Name = "Opera"
            Aliases = @("opera")
            ExecutableNames = @("opera.exe", "launcher.exe")
            ProcessNames = @("opera", "launcher")
            InstallPaths = @(
                (Join-Path $env:LOCALAPPDATA "Programs\Opera\launcher.exe"),
                "C:\Program Files\Opera\launcher.exe",
                "C:\Program Files (x86)\Opera\launcher.exe"
            )
            UserDataDir = (Join-Path $env:APPDATA "Opera Software\Opera Stable")
        },
        [pscustomobject]@{
            Name = "Opera GX"
            Aliases = @("opera gx", "operagx", "gx")
            ExecutableNames = @("opera.exe", "launcher.exe")
            ProcessNames = @("opera", "launcher")
            InstallPaths = @(
                (Join-Path $env:LOCALAPPDATA "Programs\Opera GX\launcher.exe")
            )
            UserDataDir = (Join-Path $env:APPDATA "Opera Software\Opera GX Stable")
        },
        [pscustomobject]@{
            Name = "Arc"
            Aliases = @("arc")
            ExecutableNames = @("arc.exe")
            ProcessNames = @("arc")
            InstallPaths = @(
                (Join-Path $env:LOCALAPPDATA "Programs\Arc\Arc.exe")
            )
            UserDataDir = $null
        }
    )
}

function Add-BrowserCandidate {
    param(
        [hashtable]$Map,
        [pscustomobject]$Definition,
        [string]$Path,
        [string]$Source,
        [bool]$IsRunning
    )

    if (-not $Path) {
        return
    }

    try {
        $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    } catch {
        return
    }

    if (-not $Map.ContainsKey($resolvedPath)) {
        $Map[$resolvedPath] = [pscustomobject]@{
            Name = $Definition.Name
            Path = $resolvedPath
            UserDataDir = $Definition.UserDataDir
            Sources = New-Object System.Collections.Generic.List[string]
            IsRunning = $false
        }
    }

    if (-not $Map[$resolvedPath].Sources.Contains($Source)) {
        $Map[$resolvedPath].Sources.Add($Source)
    }

    if ($IsRunning) {
        $Map[$resolvedPath].IsRunning = $true
    }
}

function Get-RunningProcessPaths {
    param([string[]]$ProcessNames)

    $paths = @()
    foreach ($processName in $ProcessNames) {
        try {
            $processes = Get-CimInstance Win32_Process -Filter "Name = '$processName.exe'"
            foreach ($process in $processes) {
                if ($process.ExecutablePath) {
                    $paths += $process.ExecutablePath
                }
            }
        } catch {}
    }

    return $paths | Sort-Object -Unique
}

function Find-BrowsersOnPath {
    param([string[]]$ExecutableNames)

    $matches = @()
    foreach ($exe in $ExecutableNames) {
        try {
            $command = Get-Command $exe -CommandType Application -ErrorAction Stop
            if ($command.Source) {
                $matches += $command.Source
            }
        } catch {}
    }

    return $matches | Sort-Object -Unique
}

function Get-DiscoveredChromiumBrowsers {
    $catalog = Get-BrowserCatalog
    $found = @{}

    foreach ($definition in $catalog) {
        foreach ($path in (Get-RunningProcessPaths -ProcessNames $definition.ProcessNames)) {
            Add-BrowserCandidate -Map $found -Definition $definition -Path $path -Source "running process" -IsRunning $true
        }

        foreach ($path in (Find-BrowsersOnPath -ExecutableNames $definition.ExecutableNames)) {
            Add-BrowserCandidate -Map $found -Definition $definition -Path $path -Source "PATH" -IsRunning $false
        }

        foreach ($path in $definition.InstallPaths) {
            Add-BrowserCandidate -Map $found -Definition $definition -Path $path -Source "install directory" -IsRunning $false
        }
    }

    return @($found.Values | Sort-Object @{ Expression = "IsRunning"; Descending = $true }, Name, Path)
}

function Resolve-ExplicitBrowserChoice {
    param(
        [string]$RequestedBrowser,
        [string]$RequestedBrowserPath,
        [object[]]$DiscoveredBrowsers
    )

    if ($RequestedBrowserPath) {
        if (-not (Test-Path -LiteralPath $RequestedBrowserPath)) {
            throw "Browser path not found: $RequestedBrowserPath"
        }

        $resolvedPath = (Resolve-Path -LiteralPath $RequestedBrowserPath).Path
        $matching = $DiscoveredBrowsers | Where-Object { $_.Path -eq $resolvedPath } | Select-Object -First 1
        if ($matching) {
            return $matching
        }

        return [pscustomobject]@{
            Name = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
            Path = $resolvedPath
            UserDataDir = $null
            Sources = New-Object System.Collections.Generic.List[string]
            IsRunning = $false
        }
    }

    if (-not $RequestedBrowser) {
        return $null
    }

    $catalog = Get-BrowserCatalog
    $requestedKey = $RequestedBrowser.ToLowerInvariant()
    $definition = $catalog | Where-Object {
        $_.Name.ToLowerInvariant() -eq $requestedKey -or $_.Aliases -contains $requestedKey
    } | Select-Object -First 1

    if (-not $definition) {
        throw "Unknown browser name: $RequestedBrowser"
    }

    $matchingBrowser = $DiscoveredBrowsers | Where-Object {
        $_.Name -eq $definition.Name
    } | Sort-Object @{ Expression = "IsRunning"; Descending = $true }, Path | Select-Object -First 1

    if ($matchingBrowser) {
        return $matchingBrowser
    }

    throw "Requested browser '$RequestedBrowser' was not found in the current process list, PATH, or standard install directories."
}

function Select-BrowserInteractively {
    param([object[]]$DiscoveredBrowsers)

    if (-not $DiscoveredBrowsers -or $DiscoveredBrowsers.Count -eq 0) {
        throw "No supported Chromium-based browsers were found. Install Edge or another Chromium-based browser, or pass -BrowserPath explicitly."
    }

    if ($DiscoveredBrowsers.Count -eq 1 -or $NoPrompt) {
        return $DiscoveredBrowsers[0]
    }

    Write-Host "Discovered Chromium-based browsers:" -ForegroundColor Cyan
    for ($index = 0; $index -lt $DiscoveredBrowsers.Count; $index++) {
        $browserInfo = $DiscoveredBrowsers[$index]
        $runningMarker = if ($browserInfo.IsRunning) { "running" } else { "not running" }
        $sourceText = ($browserInfo.Sources | Sort-Object -Unique) -join ", "
        Write-Host ("  [{0}] {1} ({2})" -f ($index + 1), $browserInfo.Name, $runningMarker) -ForegroundColor Gray
        Write-Host ("      {0}" -f $browserInfo.Path) -ForegroundColor DarkGray
        Write-Host ("      found via: {0}" -f $sourceText) -ForegroundColor DarkGray
    }

    while ($true) {
        $choice = Read-Host "Choose a browser by number"
        $parsedChoice = 0
        if ([int]::TryParse($choice, [ref]$parsedChoice)) {
            if ($parsedChoice -ge 1 -and $parsedChoice -le $DiscoveredBrowsers.Count) {
                return $DiscoveredBrowsers[$parsedChoice - 1]
            }
        }
        Write-Host "Invalid choice. Enter one of the listed numbers." -ForegroundColor Yellow
    }
}

function Format-BrowserArgumentList {
    param(
        [pscustomobject]$SelectedBrowser,
        [int]$DebugPort,
        [string]$TargetUrl
    )

    $args = @(
        "--remote-debugging-port=$DebugPort"
    )

    if ($SelectedBrowser.UserDataDir) {
        $args += ('--user-data-dir="' + $SelectedBrowser.UserDataDir + '"')
    }

    $args += $TargetUrl
    return $args
}

Write-Host "Launching browsers for Playwright workflows..." -ForegroundColor Green

$discoveredBrowsers = @(Get-DiscoveredChromiumBrowsers)

if ($ListBrowsers) {
    if (-not $discoveredBrowsers -or $discoveredBrowsers.Count -eq 0) {
        Write-Host "No supported Chromium-based browsers were found." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "Discovered Chromium-based browsers:" -ForegroundColor Green
    foreach ($browserInfo in $discoveredBrowsers) {
        $runningMarker = if ($browserInfo.IsRunning) { "running" } else { "not running" }
        $sourceText = ($browserInfo.Sources | Sort-Object -Unique) -join ", "
        Write-Host ("- {0} ({1})" -f $browserInfo.Name, $runningMarker)
        Write-Host ("  Path: {0}" -f $browserInfo.Path)
        Write-Host ("  Found via: {0}" -f $sourceText)
    }
    exit 0
}

$selectedBrowser = Resolve-ExplicitBrowserChoice -RequestedBrowser $Browser -RequestedBrowserPath $BrowserPath -DiscoveredBrowsers $discoveredBrowsers
if (-not $selectedBrowser) {
    $selectedBrowser = Select-BrowserInteractively -DiscoveredBrowsers $discoveredBrowsers
}

if ($selectedBrowser.IsRunning) {
    Write-Host ("Warning: {0} is already running. Close all windows for best results." -f $selectedBrowser.Name) -ForegroundColor Yellow
}

$browserArgs = Format-BrowserArgumentList -SelectedBrowser $selectedBrowser -DebugPort $EdgeDebugPort -TargetUrl $Url

Write-Host ("`nLaunching {0} with debugging on port {1}..." -f $selectedBrowser.Name, $EdgeDebugPort) -ForegroundColor Cyan
Start-Process -FilePath $selectedBrowser.Path -ArgumentList $browserArgs
Write-Host ("{0} launched successfully!" -f $selectedBrowser.Name) -ForegroundColor Green

Write-Host "`nBrowsers are ready for Playwright testing!" -ForegroundColor Green
Write-Host ("  Browser: {0}" -f $selectedBrowser.Name) -ForegroundColor Gray
Write-Host ("  Executable: {0}" -f $selectedBrowser.Path) -ForegroundColor Gray
Write-Host ("  Debugging port: {0}" -f $EdgeDebugPort) -ForegroundColor Gray
Write-Host ("  Opened URL: {0}" -f $Url) -ForegroundColor Gray
Write-Host "`nUse 'npm run live-browser -- status' to inspect the shared browser window." -ForegroundColor Cyan