param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$ConfigPath,
  [string[]]$Tests = @("*"),
  [switch]$ShowWatcherLogs,
  [switch]$FailOnMissingSelectors
)

$ErrorActionPreference = "Continue"
$results = @()
$StepDelayMs = 700
$ToolkitRoot = $PSScriptRoot
$ResolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$LiveBrowserScript = Join-Path $ToolkitRoot "live-browser.mjs"

$normalizedPatterns = @()
foreach ($raw in $Tests) {
  foreach ($piece in ($raw -split ",")) {
    $p = $piece.Trim().Trim('"').Trim("'")
    if ($p) {
      $normalizedPatterns += $p
    }
  }
}

if (-not $normalizedPatterns -or $normalizedPatterns.Count -eq 0) {
  $normalizedPatterns = @("*")
}

$script:TestPatterns = @($normalizedPatterns)

$config = [ordered]@{
  baseUrl = [string]$env:PLAYWRIGHT_LIVE_BASE_URL
  primaryPath = "/"
  secondaryPath = "/"
  fillValue = "qa@example.com"
  typeValue = "-typed"
  pressKey = "Enter"
  networkProbePath = "/robots.txt?lb_probe=smoke"
  viewportUseIsolatedTabs = $false
  crawlDepth = 1
  crawlMaxLinks = 8
  crawlParallelTabs = 4
  crawlIncludePaths = @()
}

$script:SelectorPool = @{
  text = @()
  html = @()
  attr = @()
  visible = @()
  screenshot = @()
  click = @()
  fill = @()
  type = @()
  press = @()
  select = @()
  check = @()
  hover = @()
  wait = @()
  scroll = @()
}

if ($ConfigPath) {
  $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
  $loadedConfig = Get-Content $resolvedConfigPath -Raw | ConvertFrom-Json
  foreach ($property in $loadedConfig.PSObject.Properties) {
    $config[$property.Name] = $property.Value
  }
}

function Should-RunTest {
  param([string]$Name)

  foreach ($pattern in $script:TestPatterns) {
    if ($Name -like $pattern) {
      return $true
    }
  }

  return $false
}

function Should-RunAny {
  param([string[]]$Names)

  foreach ($n in $Names) {
    if (Should-RunTest -Name $n) {
      return $true
    }
  }

  return $false
}

function Invoke-Live {
  param(
    [string]$Name,
    [string[]]$CommandArgs,
    [switch]$NoDelay,
    [switch]$AllowSkip
  )

  if (-not (Should-RunTest -Name $Name)) {
    Write-Host "SKIP: $Name" -ForegroundColor DarkYellow
    return
  }

  if ($AllowSkip -and (-not $CommandArgs -or $CommandArgs.Count -eq 0)) {
    Write-Host "SKIP: $Name (no config)" -ForegroundColor DarkYellow
    return
  }

  Write-Host "`n=== $Name ===" -ForegroundColor Cyan
  Write-Host ("ARGS: " + ($CommandArgs -join " | ")) -ForegroundColor DarkGray

  Push-Location $ResolvedProjectRoot
  try {
    & node $LiveBrowserScript @CommandArgs
    $code = $LASTEXITCODE
  } finally {
    Pop-Location
  }

  $script:results += [pscustomobject]@{
    Command = $Name
    ExitCode = $code
  }

  if ($code -eq 0) {
    Write-Host "PASS: $Name" -ForegroundColor Green
  } else {
    Write-Host "FAIL($code): $Name" -ForegroundColor Red
  }

  if (-not $NoDelay) {
    Start-Sleep -Milliseconds $StepDelayMs
  }
}

function Add-Result {
  param(
    [string]$Name,
    [int]$ExitCode
  )

  $script:results += [pscustomobject]@{
    Command = $Name
    ExitCode = $ExitCode
  }

  if ($ExitCode -eq 0) {
    Write-Host "PASS: $Name" -ForegroundColor Green
  } else {
    Write-Host "FAIL($ExitCode): $Name" -ForegroundColor Red
  }
}

function Invoke-ViewportTest {
  param(
    [string]$Name,
    [int]$Width,
    [int]$Height
  )

  if (-not (Should-RunTest -Name $Name)) {
    Write-Host "SKIP: $Name" -ForegroundColor DarkYellow
    return
  }

  Write-Host "`n=== $Name ===" -ForegroundColor Cyan
  Write-Host ("ARGS: viewport | $Width | $Height") -ForegroundColor DarkGray

  $useIsolatedTabs = [bool]$config.viewportUseIsolatedTabs
  $oldIsolated = $env:PLAYWRIGHT_LIVE_ISOLATED
  if ($useIsolatedTabs) {
    $env:PLAYWRIGHT_LIVE_ISOLATED = "1"
  }

  try {
    Push-Location $ResolvedProjectRoot
    try {
      & node $LiveBrowserScript viewport "$Width" "$Height"
      $setCode = $LASTEXITCODE
    } finally {
      Pop-Location
    }

    if ($setCode -ne 0) {
      Add-Result -Name $Name -ExitCode $setCode
      Start-Sleep -Milliseconds $StepDelayMs
      return
    }

    Start-Sleep -Milliseconds $StepDelayMs

    Write-Host "Resetting viewport control..." -ForegroundColor DarkGray
    Push-Location $ResolvedProjectRoot
    try {
      & node $LiveBrowserScript viewport reset
      $resetCode = $LASTEXITCODE
    } finally {
      Pop-Location
    }

    if ($resetCode -eq 0) {
      Add-Result -Name $Name -ExitCode 0
    } else {
      Add-Result -Name $Name -ExitCode $resetCode
    }

    Start-Sleep -Milliseconds $StepDelayMs
  } finally {
    if ($useIsolatedTabs) {
      if ($null -eq $oldIsolated) {
        Remove-Item Env:PLAYWRIGHT_LIVE_ISOLATED -ErrorAction SilentlyContinue
      } else {
        $env:PLAYWRIGHT_LIVE_ISOLATED = $oldIsolated
      }
    }
  }
}

function Test-WatcherWithTrigger {
  param(
    [string]$Name,
    [string]$WatchCommand,
    [int]$WatchMs,
    [string]$TriggerExpression,
    [string]$ExpectedMarker
  )

  if (-not (Should-RunTest -Name $Name)) {
    Write-Host "SKIP: $Name" -ForegroundColor DarkYellow
    return
  }

  Write-Host "`n=== $Name ===" -ForegroundColor Cyan

  $logDir = Join-Path $ResolvedProjectRoot "test-results\live-browser"
  New-Item -ItemType Directory -Path $logDir -Force | Out-Null
  $logBase = Join-Path $logDir ($Name.Replace(" ", "-"))
  $stdoutPath = "$logBase.stdout.log"
  $stderrPath = "$logBase.stderr.log"

  if (Test-Path $stdoutPath) { Remove-Item $stdoutPath -Force }
  if (Test-Path $stderrPath) { Remove-Item $stderrPath -Force }

  $watchProc = Start-Process -FilePath node `
    -ArgumentList @($LiveBrowserScript, $WatchCommand, "$WatchMs") `
    -WorkingDirectory $ResolvedProjectRoot `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -WindowStyle Hidden `
    -PassThru

  Start-Sleep -Milliseconds 900

  Push-Location $ResolvedProjectRoot
  try {
    & node $LiveBrowserScript eval $TriggerExpression | Out-Null
  } finally {
    Pop-Location
  }

  $watchProc.WaitForExit()
  $watchCode = $watchProc.ExitCode
  $logText = ""
  if (Test-Path $stdoutPath) { $logText += (Get-Content $stdoutPath -Raw) }
  if (Test-Path $stderrPath) {
    $logText += "`n"
    $logText += (Get-Content $stderrPath -Raw)
  }

  if ($logText.Contains($ExpectedMarker)) {
    if ($ShowWatcherLogs) {
      Write-Host "Watcher log ($Name):" -ForegroundColor DarkCyan
      Write-Host $logText
    }
    Add-Result -Name $Name -ExitCode 0
    return
  }

  Write-Host "Expected marker not found: $ExpectedMarker" -ForegroundColor Yellow
  Write-Host "Watcher exit code: $watchCode" -ForegroundColor Yellow
  if ($logText) {
    Write-Host "Watcher log:" -ForegroundColor Yellow
    Write-Host $logText
  }
  Add-Result -Name $Name -ExitCode 1
}

function New-CommandArgs {
  param(
    [string]$Command,
    [object[]]$Values
  )

  $args = @($Command)
  foreach ($value in $Values) {
    if ($null -eq $value) {
      return @()
    }

    $stringValue = [string]$value
    if ([string]::IsNullOrWhiteSpace($stringValue)) {
      return @()
    }

    $args += $stringValue
  }

  return $args
}

function Invoke-LiveRaw {
  param(
    [string[]]$CommandArgs,
    [switch]$CaptureOutput
  )

  Push-Location $ResolvedProjectRoot
  try {
    if ($CaptureOutput) {
      $output = & node $LiveBrowserScript @CommandArgs
      $code = $LASTEXITCODE
      return [pscustomobject]@{
        ExitCode = $code
        Output = ($output -join "`n")
      }
    }

    & node $LiveBrowserScript @CommandArgs
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE }
  } finally {
    Pop-Location
  }
}

function Invoke-LiveParallelCommands {
  param(
    [object[]]$Specs,
    [int]$MaxParallel = 1
  )

  if (-not $Specs -or $Specs.Count -eq 0) {
    return
  }

  if ($MaxParallel -lt 1) { $MaxParallel = 1 }
  if ($MaxParallel -gt 12) { $MaxParallel = 12 }

  $queue = New-Object System.Collections.Generic.Queue[object]
  foreach ($spec in $Specs) {
    if (-not (Should-RunTest -Name $spec.Name)) {
      Write-Host "SKIP: $($spec.Name)" -ForegroundColor DarkYellow
      continue
    }

    $queue.Enqueue($spec)
  }

  if ($queue.Count -eq 0) {
    return
  }

  $logDir = Join-Path $ResolvedProjectRoot "test-results\live-browser"
  New-Item -ItemType Directory -Path $logDir -Force | Out-Null

  $oldIsolated = $env:PLAYWRIGHT_LIVE_ISOLATED
  $env:PLAYWRIGHT_LIVE_ISOLATED = "1"

  $running = @()
  try {
    while ($queue.Count -gt 0 -or $running.Count -gt 0) {
      while ($queue.Count -gt 0 -and $running.Count -lt $MaxParallel) {
        $spec = $queue.Dequeue()
        Write-Host "`n=== $($spec.Name) ===" -ForegroundColor Cyan
        Write-Host ("ARGS: " + ($spec.Args -join " | ")) -ForegroundColor DarkGray

        $token = [Guid]::NewGuid().ToString("N")
        $safeName = ($spec.Name -replace "[^A-Za-z0-9_-]", "_")
        $stdoutPath = Join-Path $logDir ("parallel-{0}-{1}.stdout.log" -f $safeName, $token)
        $stderrPath = Join-Path $logDir ("parallel-{0}-{1}.stderr.log" -f $safeName, $token)
        $argumentList = @($LiveBrowserScript) + @($spec.Args)

        $proc = Start-Process -FilePath node `
          -ArgumentList $argumentList `
          -WorkingDirectory $ResolvedProjectRoot `
          -RedirectStandardOutput $stdoutPath `
          -RedirectStandardError $stderrPath `
          -WindowStyle Hidden `
          -PassThru

        $running += [pscustomobject]@{
          Spec = $spec
          Proc = $proc
          Stdout = $stdoutPath
          Stderr = $stderrPath
        }
      }

      if ($running.Count -eq 0) {
        continue
      }

      $stillRunning = @()
      foreach ($item in $running) {
        if (-not $item.Proc.HasExited) {
          $stillRunning += $item
          continue
        }

        $exitCode = $item.Proc.ExitCode
        Add-Result -Name $item.Spec.Name -ExitCode $exitCode

        if ($exitCode -ne 0) {
          $errText = ""
          if (Test-Path $item.Stdout) { $errText += (Get-Content $item.Stdout -Raw) }
          if (Test-Path $item.Stderr) {
            if ($errText) { $errText += "`n" }
            $errText += (Get-Content $item.Stderr -Raw)
          }

          if ($errText) {
            Write-Host "Failure output:" -ForegroundColor Yellow
            Write-Host $errText
          }
        }
      }

      $running = $stillRunning
      if ($running.Count -gt 0) {
        Start-Sleep -Milliseconds 200
      }
    }
  } finally {
    if ($null -eq $oldIsolated) {
      Remove-Item Env:PLAYWRIGHT_LIVE_ISOLATED -ErrorAction SilentlyContinue
    } else {
      $env:PLAYWRIGHT_LIVE_ISOLATED = $oldIsolated
    }
  }

  Start-Sleep -Milliseconds $StepDelayMs
}

function Ensure-TrailingSlash {
  param([string]$Url)

  if ([string]::IsNullOrWhiteSpace($Url)) {
    return $Url
  }

  if ($Url.EndsWith("/")) {
    return $Url
  }

  return ($Url + "/")
}

function Resolve-BaseUrlHint {
  $configured = ([string]$config.baseUrl).Trim()
  if (-not [string]::IsNullOrWhiteSpace($configured)) {
    try {
      $uri = [Uri]$configured
      if ($uri.Scheme -eq "http" -or $uri.Scheme -eq "https") {
        return (Ensure-TrailingSlash -Url $configured)
      }
    } catch {}
  }

  $status = Invoke-LiveRaw -CommandArgs @("status") -CaptureOutput
  if ($status.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($status.Output)) {
    return ""
  }

  $matches = [regex]::Matches($status.Output, "https?://(?:localhost|127\\.0\\.0\\.1)(?::\\d+)?[^\r\n\s]*")
  foreach ($match in $matches) {
    $candidate = $match.Value
    try {
      $uri = [Uri]$candidate
      $segments = @($uri.AbsolutePath.Trim("/").Split("/", [System.StringSplitOptions]::RemoveEmptyEntries))
      if ($segments.Count -gt 0) {
        return "$($uri.Scheme)://$($uri.Authority)/$($segments[0])/"
      }
      return "$($uri.Scheme)://$($uri.Authority)/"
    } catch {
      continue
    }
  }

  return ""
}

function Resolve-RouteTarget {
  param([string]$PathOrUrl)

  $value = ([string]$PathOrUrl).Trim()
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $value
  }

  if ($value -match "^https?://") {
    return $value
  }

  $base = [string]$script:BaseUrlHint
  if ($value.StartsWith("/") -and -not [string]::IsNullOrWhiteSpace($base)) {
    try {
      $baseUri = [Uri](Ensure-TrailingSlash -Url $base)
      return ([Uri]::new($baseUri, $value.TrimStart('/'))).AbsoluteUri
    } catch {
      return $value
    }
  }

  if ($value.StartsWith("/") -and [string]::IsNullOrWhiteSpace($base)) {
    throw "Cannot resolve relative route '$value' because no base URL was discovered. Set config.baseUrl or PLAYWRIGHT_LIVE_BASE_URL."
  }

  return $value
}

function Add-SelectorCandidate {
  param(
    [string]$Type,
    [string]$Value
  )

  if (-not $script:SelectorPool.ContainsKey($Type)) {
    return
  }

  $candidate = [string]$Value
  if ([string]::IsNullOrWhiteSpace($candidate)) {
    return
  }

  if ($script:SelectorPool[$Type] -notcontains $candidate) {
    $script:SelectorPool[$Type] += $candidate
  }
}

function Ensure-ProbeSelectorCandidate {
  param([string]$PoolType)

  if ($PoolType -eq "select") {
    $probe = Invoke-LiveRaw -CommandArgs @("eval", "(() => { const id='lb-probe-select'; let el=document.getElementById(id); if (!el) { const host=document.createElement('div'); host.id='lb-probe-host'; host.style.position='fixed'; host.style.left='8px'; host.style.top='8px'; host.style.zIndex='2147483647'; host.style.background='rgba(255,255,255,0.98)'; host.style.padding='4px'; host.style.border='1px solid #999'; el=document.createElement('select'); el.id=id; const opt=document.createElement('option'); opt.value='lb_probe_option'; opt.textContent='Probe Option'; el.appendChild(opt); host.appendChild(el); document.body.appendChild(host); } return '#'+id; })()") -CaptureOutput
    if ($probe.ExitCode -eq 0) {
      $selector = ($probe.Output).Trim()
      if (-not [string]::IsNullOrWhiteSpace($selector)) {
        Add-SelectorCandidate -Type "select" -Value $selector
        return $true
      }
    }

    return $false
  }

  if ($PoolType -eq "check") {
    $probe = Invoke-LiveRaw -CommandArgs @("eval", "(() => { const id='lb-probe-check'; let el=document.getElementById(id); if (!el) { const host=(document.getElementById('lb-probe-host') || (() => { const h=document.createElement('div'); h.id='lb-probe-host'; h.style.position='fixed'; h.style.left='8px'; h.style.top='8px'; h.style.zIndex='2147483647'; h.style.background='rgba(255,255,255,0.98)'; h.style.padding='4px'; h.style.border='1px solid #999'; document.body.appendChild(h); return h; })()); el=document.createElement('input'); el.id=id; el.type='checkbox'; host.appendChild(el); } return '#'+id; })()") -CaptureOutput
    if ($probe.ExitCode -eq 0) {
      $selector = ($probe.Output).Trim()
      if (-not [string]::IsNullOrWhiteSpace($selector)) {
        Add-SelectorCandidate -Type "check" -Value $selector
        return $true
      }
    }

    return $false
  }

  return $false
}

function Remove-ProbeFixture {
  $cleanup = Invoke-LiveRaw -CommandArgs @("eval", "(() => { const host = document.getElementById('lb-probe-host'); if (host) host.remove(); return 'ok'; })()") -CaptureOutput
  return ($cleanup.ExitCode -eq 0)
}

function Add-SelectorsFromPageData {
  param($Data)

  if (-not $Data) {
    return
  }

  foreach ($selector in @($Data.textSelectors)) { Add-SelectorCandidate -Type "text" -Value $selector }
  foreach ($selector in @($Data.htmlSelectors)) { Add-SelectorCandidate -Type "html" -Value $selector }
  foreach ($selector in @($Data.visibleSelectors)) { Add-SelectorCandidate -Type "visible" -Value $selector }
  foreach ($selector in @($Data.screenshotSelectors)) { Add-SelectorCandidate -Type "screenshot" -Value $selector }
  foreach ($selector in @($Data.clickSelectors)) {
    Add-SelectorCandidate -Type "click" -Value $selector
    Add-SelectorCandidate -Type "hover" -Value $selector
  }
  foreach ($selector in @($Data.fillSelectors)) {
    Add-SelectorCandidate -Type "fill" -Value $selector
    Add-SelectorCandidate -Type "type" -Value $selector
    Add-SelectorCandidate -Type "press" -Value $selector
    Add-SelectorCandidate -Type "wait" -Value $selector
  }
  foreach ($selector in @($Data.selectSelectors)) { Add-SelectorCandidate -Type "select" -Value $selector }
  foreach ($selector in @($Data.checkSelectors)) { Add-SelectorCandidate -Type "check" -Value $selector }
  foreach ($selector in @($Data.scrollSelectors)) { Add-SelectorCandidate -Type "scroll" -Value $selector }

  foreach ($pair in @($Data.attrCandidates)) {
    if ($pair.selector -and $pair.attribute) {
      Add-SelectorCandidate -Type "attr" -Value ($pair.selector + "|||" + $pair.attribute)
    }
  }
}

function Get-PageProbeData {
  $maxLinks = [int]$config.crawlMaxLinks
  if ($maxLinks -lt 0) { $maxLinks = 0 }
  if ($maxLinks -gt 50) { $maxLinks = 50 }

  $result = Invoke-LiveRaw -CommandArgs @("crawl", "$maxLinks") -CaptureOutput
  if ($result.ExitCode -ne 0) {
    return $null
  }

  try {
    return ($result.Output | ConvertFrom-Json)
  } catch {
    Write-Host "WARN: Could not parse crawl probe output as JSON." -ForegroundColor Yellow
    return $null
  }
}

function Crawl-SelectorPool {
  if (-not (Should-RunAny -Names @("text", "html", "attr", "visible", "screenshot", "click", "fill", "type", "press", "select", "check", "uncheck", "hover", "wait", "scroll selector"))) {
    return
  }

  Write-Host "`n=== selector crawl ===" -ForegroundColor Cyan

  $crawlDepth = [int]$config.crawlDepth
  if ($crawlDepth -lt 0) { $crawlDepth = 0 }
  if ($crawlDepth -gt 5) { $crawlDepth = 5 }

  $maxLinks = [int]$config.crawlMaxLinks
  if ($maxLinks -lt 0) { $maxLinks = 0 }
  if ($maxLinks -gt 50) { $maxLinks = 50 }

  $parallelTabs = [int]$config.crawlParallelTabs
  if ($parallelTabs -lt 1) { $parallelTabs = 1 }
  if ($parallelTabs -gt 12) { $parallelTabs = 12 }

  $includePaths = @()
  foreach ($p in @($config.crawlIncludePaths)) {
    if ($null -eq $p) { continue }
    $s = ([string]$p).Trim()
    if (-not [string]::IsNullOrWhiteSpace($s)) {
      $includePaths += $s
    }
  }

  $includePathsJson = ($includePaths | ConvertTo-Json -Compress)
  if (-not $includePathsJson) { $includePathsJson = "[]" }

  Write-Host ("crawlDepth={0}, crawlMaxLinks={1}, crawlParallelTabs={2}" -f $crawlDepth, $maxLinks, $parallelTabs) -ForegroundColor DarkGray

  $crawlResult = Invoke-LiveRaw -CommandArgs @("crawl-site", "$crawlDepth", "$maxLinks", "$parallelTabs", $includePathsJson) -CaptureOutput
  if ($crawlResult.ExitCode -ne 0) {
    Write-Host "WARN: crawl-site command failed; selector-dependent tests may be skipped." -ForegroundColor Yellow
    return
  }

  try {
    $crawlData = ($crawlResult.Output | ConvertFrom-Json)
  } catch {
    Write-Host "WARN: Could not parse crawl-site output as JSON." -ForegroundColor Yellow
    return
  }

  Add-SelectorsFromPageData -Data $crawlData

  $pageCount = @($crawlData.pages).Count
  $failureCount = @($crawlData.failedPaths).Count
  Write-Host ("crawled pages: {0}, failed paths: {1}" -f $pageCount, $failureCount) -ForegroundColor DarkGray

  foreach ($type in $script:SelectorPool.Keys | Sort-Object) {
    $count = @($script:SelectorPool[$type]).Count
    Write-Host ("  {0}: {1}" -f $type, $count) -ForegroundColor DarkGray
  }
}

function Invoke-LiveWithSelectorFallback {
  param(
    [string]$Name,
    [string]$PoolType,
    [scriptblock]$BuildArgs
  )

  if (-not (Should-RunTest -Name $Name)) {
    Write-Host "SKIP: $Name" -ForegroundColor DarkYellow
    return
  }

  $candidates = @($script:SelectorPool[$PoolType])
  if (-not $candidates -or $candidates.Count -eq 0) {
    $probeReady = Ensure-ProbeSelectorCandidate -PoolType $PoolType
    if ($probeReady) {
      $candidates = @($script:SelectorPool[$PoolType])
    }
  }

  if (-not $candidates -or $candidates.Count -eq 0) {
    if ($FailOnMissingSelectors) {
      Write-Host "FAIL: $Name (no discovered selector of type $PoolType)" -ForegroundColor Red
      Add-Result -Name $Name -ExitCode 1
      Start-Sleep -Milliseconds $StepDelayMs
      return
    }

    Write-Host "SKIP: $Name (no discovered selector of type $PoolType)" -ForegroundColor DarkYellow
    return
  }

  Write-Host "`n=== $Name ===" -ForegroundColor Cyan

  foreach ($candidate in $candidates) {
    $commandArgs = & $BuildArgs $candidate
    if (-not $commandArgs -or @($commandArgs).Count -eq 0) {
      continue
    }

    Write-Host ("TRY: " + ($commandArgs -join " | ")) -ForegroundColor DarkGray
    $runResult = Invoke-LiveRaw -CommandArgs $commandArgs
    if ($runResult.ExitCode -eq 0) {
      Add-Result -Name $Name -ExitCode 0
      Start-Sleep -Milliseconds $StepDelayMs
      return
    }
  }

  Add-Result -Name $Name -ExitCode 1
  Start-Sleep -Milliseconds $StepDelayMs
}

Write-Host "Project root: $ResolvedProjectRoot" -ForegroundColor Yellow
Write-Host "Test filters: $($script:TestPatterns -join ', ')" -ForegroundColor Yellow
Write-Host "Show watcher logs: $ShowWatcherLogs" -ForegroundColor Yellow
if ($ConfigPath) {
  Write-Host "Config path: $resolvedConfigPath" -ForegroundColor Yellow
}

$script:BaseUrlHint = Resolve-BaseUrlHint
if (-not [string]::IsNullOrWhiteSpace($script:BaseUrlHint)) {
  Write-Host "Base URL hint: $script:BaseUrlHint" -ForegroundColor Yellow
} else {
  Write-Host "Base URL hint: (none discovered)" -ForegroundColor DarkYellow
}

try {
  $null = Resolve-RouteTarget -PathOrUrl ([string]$config.primaryPath)
  $null = Resolve-RouteTarget -PathOrUrl ([string]$config.secondaryPath)
} catch {
  Write-Host $_ -ForegroundColor Red
  exit 1
}

$allTestNames = @(
  "help", "status", "capture", "links", "meta", "eval",
  "open primary", "open secondary", "back", "forward", "reload", "scroll bottom", "scroll top", "scroll selector",
  "text", "html", "attr", "visible", "screenshot",
  "click", "fill", "type", "press", "select", "check", "uncheck", "hover", "wait",
  "console trigger-verify", "network trigger-verify", "storage show", "storage cookies", "storage clear",
  "viewport sd", "viewport full-hd", "viewport 4k", "viewport tablet", "viewport smartphone",
  "pdf"
)

$matchedTestNames = @($allTestNames | Where-Object { Should-RunTest -Name $_ })

if (-not $matchedTestNames -or $matchedTestNames.Count -eq 0) {
  Write-Host "No tests matched current filters: $($script:TestPatterns -join ', ')" -ForegroundColor Yellow
  exit 0
}

Invoke-Live "help" @("help") -NoDelay
Invoke-Live "status" @("status")
Invoke-Live "open primary" @("open", (Resolve-RouteTarget -PathOrUrl ([string]$config.primaryPath)))
Crawl-SelectorPool

$parallelTabs = [int]$config.crawlParallelTabs
if ($parallelTabs -lt 1) { $parallelTabs = 1 }
if ($parallelTabs -gt 12) { $parallelTabs = 12 }

Invoke-LiveParallelCommands -MaxParallel $parallelTabs -Specs @(
  [pscustomobject]@{ Name = "capture"; Args = @("capture") },
  [pscustomobject]@{ Name = "links"; Args = @("links") },
  [pscustomobject]@{ Name = "meta"; Args = @("meta") },
  [pscustomobject]@{ Name = "eval"; Args = @("eval", "document.title") },
  [pscustomobject]@{ Name = "scroll bottom"; Args = @("scroll", "bottom") },
  [pscustomobject]@{ Name = "scroll top"; Args = @("scroll", "top") },
  [pscustomobject]@{ Name = "storage show"; Args = @("storage", "show") },
  [pscustomobject]@{ Name = "storage cookies"; Args = @("storage", "cookies") },
  [pscustomobject]@{ Name = "pdf"; Args = @("pdf") }
)

Invoke-Live "open secondary" @("open", (Resolve-RouteTarget -PathOrUrl ([string]$config.secondaryPath)))
Invoke-Live "back" @("back")
Invoke-Live "forward" @("forward")
Invoke-Live "reload" @("reload")
Invoke-LiveWithSelectorFallback "scroll selector" "scroll" { param($s) @("scroll", $s) }
Invoke-LiveWithSelectorFallback "text" "text" { param($s) @("text", $s) }
Invoke-LiveWithSelectorFallback "html" "html" { param($s) @("html", $s) }
Invoke-LiveWithSelectorFallback "attr" "attr" {
  param($pair)
  $parts = [string]$pair -split "\|\|\|", 2
  if ($parts.Count -lt 2) { return @() }
  @("attr", $parts[0], $parts[1])
}
Invoke-LiveWithSelectorFallback "visible" "visible" { param($s) @("visible", $s) }
Invoke-LiveWithSelectorFallback "screenshot" "screenshot" { param($s) @("screenshot", $s) }
Invoke-LiveWithSelectorFallback "click" "click" { param($s) @("click", $s) }
Invoke-LiveWithSelectorFallback "fill" "fill" { param($s) @("fill", $s, [string]$config.fillValue) }
Invoke-LiveWithSelectorFallback "type" "type" { param($s) @("type", $s, [string]$config.typeValue) }
Invoke-LiveWithSelectorFallback "press" "press" { param($s) @("press", $s, [string]$config.pressKey) }
Invoke-LiveWithSelectorFallback "select" "select" {
  param($s)
  $escapedSelector = ([string]$s).Replace("'", "\\'")
  $valueProbe = Invoke-LiveRaw -CommandArgs @("eval", "(() => { const el = document.querySelector('$escapedSelector'); if (!el || el.tagName.toLowerCase() !== 'select') return ''; const opt = el.querySelector('option[value]'); return opt ? opt.value : ''; })()") -CaptureOutput
  $candidateValue = ($valueProbe.Output).Trim()
  if ([string]::IsNullOrWhiteSpace($candidateValue)) { return @() }
  @("select", $s, $candidateValue)
}
Invoke-LiveWithSelectorFallback "check" "check" { param($s) @("check", $s) }
Invoke-LiveWithSelectorFallback "uncheck" "check" { param($s) @("uncheck", $s) }

# Ensure probe controls do not interfere with real interaction tests.
[void](Remove-ProbeFixture)

Invoke-LiveWithSelectorFallback "hover" "hover" { param($s) @("hover", $s) }
Invoke-LiveWithSelectorFallback "wait" "wait" { param($s) @("wait", $s) }

Test-WatcherWithTrigger `
  -Name "console trigger-verify" `
  -WatchCommand "console" `
  -WatchMs 3500 `
  -TriggerExpression "(() => { console.log('LB_CONSOLE_PROBE_SMOKE'); return 'ok'; })()" `
  -ExpectedMarker "LB_CONSOLE_PROBE_SMOKE"

$networkProbePath = [string]$config.networkProbePath
if (-not $networkProbePath.StartsWith("/")) {
  $networkProbePath = "/$networkProbePath"
}
$escapedProbePath = $networkProbePath.Replace("'", "\\'")

Test-WatcherWithTrigger `
  -Name "network trigger-verify" `
  -WatchCommand "network" `
  -WatchMs 4500 `
  -TriggerExpression "(() => { const u = '$escapedProbePath'; fetch(u).catch(() => {}); return u; })()" `
  -ExpectedMarker ($networkProbePath.TrimStart('/').Split('?')[-1])

Invoke-Live "storage clear" @("storage", "clear")
Invoke-ViewportTest "viewport sd" 640 480
Invoke-ViewportTest "viewport full-hd" 1920 1080
Invoke-ViewportTest "viewport 4k" 3840 2160
Invoke-ViewportTest "viewport tablet" 768 1024
Invoke-ViewportTest "viewport smartphone" 390 844

Write-Host "`n=== viewport global cleanup ===" -ForegroundColor Cyan
$cleanup = Invoke-LiveRaw -CommandArgs @("viewport", "reset-all")
if ($cleanup.ExitCode -eq 0) {
  Write-Host "PASS: viewport global cleanup" -ForegroundColor Green
} else {
  Write-Host "WARN: viewport global cleanup failed" -ForegroundColor Yellow
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Yellow
if ($results.Count -eq 0) {
  Write-Host "Matched tests ran no executable commands (all matched tests were skipped)." -ForegroundColor Yellow
  Write-Host "Matched test names: $($matchedTestNames -join ', ')" -ForegroundColor DarkYellow
  exit 0
}

$results | Format-Table -AutoSize

$failed = $results | Where-Object { $_.ExitCode -ne 0 }
if ($failed.Count -gt 0) {
  Write-Host "`nFailed commands:" -ForegroundColor Red
  $failed | Format-Table -AutoSize
  exit 1
}

Write-Host "`nAll commands passed." -ForegroundColor Green
