# Wright By Your Side: A Playwright Toolkit for On-Screen Browser Automation and Testing
<img width="1536" height="1024" alt="wright-by-your-side" src="https://github.com/user-attachments/assets/4f82feea-b262-47f9-b9c0-36eacddb2535" />

This toolkit lets you attach Playwright to the same Chromium-based browser window you are already using.

That means both you and your coding agent can inspect a live page, click on it, read text from it, watch console and network activity, and take screenshots without switching to a separate automated test browser.

## What This Is

If you are new to the JavaScript tooling world, here is the short version:

- `Node.js` is the program that runs JavaScript files on your computer.
- `npm` is the package manager that comes with Node.js. It installs dependencies and runs named scripts from `package.json`.
- `PowerShell` is the Windows shell used here to launch the browser and local dev servers.
- `Playwright` is the browser automation library this toolkit uses.
- `CDP` means Chrome DevTools Protocol. It is the connection method that lets this toolkit attach to an existing Chromium-based browser window.

You do not need to understand all of that in depth to use this project. The practical part is:

1. Install Node.js.
2. Run `npm install` once.
3. Start the toolkit.
4. Use `npm run live-browser -- ...` commands to inspect or control the page.

## What Each File Does

- `live-browser.mjs`: the main command-line tool that talks to the shared browser
- `launch-browsers.ps1`: discovers and starts a supported Chromium-based browser with the remote-debugging mode that Playwright needs
- `start-dev.ps1`: starts a local dev server and the shared browser for a target project
- `verify-live-browser.ps1`: runs a smoke test against the toolkit commands
- `smoke.config.example.json`: example config for project-specific selectors and routes
- `package.json`: tells `npm` which commands exist and which dependency to install

## Before You Start

You need:

1. Node.js installed on Windows.
2. A Chromium-based browser installed (Edge, Chrome, Brave, Vivaldi, Chromium, Opera, Opera GX, or Arc).
3. A PowerShell window.

## Supported Browsers

This toolkit supports Chromium-based browsers that expose the Chrome DevTools Protocol.

In practice, you should treat these as the supported paths:

- Microsoft Edge: supported and most tested in this bundle
- Google Chrome, Brave, Vivaldi, Chromium, Opera, Opera GX, Arc: supported through launcher discovery and explicit selection

You should treat these as unsupported:

- Firefox
- Safari
- browsers that do not expose a compatible CDP endpoint

If a browser is not on the supported list, assume it probably will not work unless you verify it yourself.

## Browser Discovery

The launcher now includes a Chromium-based browser discovery step.

When you run `start-dev.ps1` or `launch-browsers.ps1`, the toolkit can:

1. check the current Windows process list for running Chromium-based browsers
2. search `PATH` for known Chromium browser executables
3. search common Windows installation directories for supported Chromium-based browsers
4. show you the discovered browsers and let you choose one

The launcher knows about common Windows installs for:

- Microsoft Edge
- Google Chrome
- Brave
- Vivaldi
- Chromium
- Opera
- Opera GX
- Arc

This is a convenience feature, not a hard guarantee. If a browser is Chromium-based and installed somewhere unusual, you can still launch it by passing its executable path directly.

### List What the Launcher Found

```powershell
powershell -ExecutionPolicy Bypass -File .\launch-browsers.ps1 -ListBrowsers
```

### Choose Interactively

If multiple supported browsers are found and you do not force a choice, the launcher will show a numbered list and ask which one you want to use.

### Force a Browser by Name

```powershell
powershell -ExecutionPolicy Bypass -File .\launch-browsers.ps1 -Browser chrome
```

Other examples:

```powershell
powershell -ExecutionPolicy Bypass -File .\launch-browsers.ps1 -Browser edge
powershell -ExecutionPolicy Bypass -File .\launch-browsers.ps1 -Browser brave
```

### Force a Browser by Executable Path

```powershell
powershell -ExecutionPolicy Bypass -File .\launch-browsers.ps1 -BrowserPath "C:\Program Files\Google\Chrome\Application\chrome.exe"
```

### Skip the Prompt and Use the First Match

```powershell
powershell -ExecutionPolicy Bypass -File .\launch-browsers.ps1 -NoPrompt
```

When `-NoPrompt` is used, the launcher picks the first discovered browser, preferring a running browser over a non-running one.

To check that Node.js and `npm` are installed, open PowerShell and run:

```powershell
node --version
npm --version
```

If both commands print version numbers, you are ready.

If they say the command is not recognized, install Node.js first and then reopen PowerShell.

## First-Time Setup

Open PowerShell in the `wright-by-your-side` folder and run:

```powershell
npm install
```

What this does:

- reads `package.json`
- downloads the toolkit dependency it needs
- creates a `node_modules` folder

You usually only need to do this once for each copy of the toolkit.

## The Two Main Ways To Use It

There are two common setups.

### Option 1: The Toolkit Lives at the Root of the Project

Example:

```text
my-project/
	package.json
	live-browser.mjs
	start-dev.ps1
	launch-browsers.ps1
```

In that case, open PowerShell in the project root and run:

```powershell
npm install
npm run start-dev
```

Then try:

```powershell
npm run live-browser -- status
npm run live-browser -- capture
npm run live-browser -- meta
```

### Option 2: The Toolkit Lives in a Subfolder or Its Own Repo

Example:

```text
my-project/
	package.json
	src/
	tools/
		wright-by-your-side/
```

In that case, the toolkit needs to know where the real app lives. That is what `-ProjectRoot` is for.

If you are inside the toolkit folder and the project is one folder up:

```powershell
npm install
powershell -ExecutionPolicy Bypass -File .\start-dev.ps1 -ProjectRoot ..
```

Then you can run commands like:

```powershell
node .\live-browser.mjs status
node .\live-browser.mjs capture
```

## Beginner Workflow for a Local Website

If your site has a local development server, this is the easiest path.

### Step 1: Open PowerShell in the toolkit folder

If you are already there, skip this.

### Step 2: Install dependencies

```powershell
npm install
```

### Step 3: Start the app and shared browser

If the toolkit is at the app root:

```powershell
npm run start-dev
```

If the toolkit is in a subfolder:

```powershell
powershell -ExecutionPolicy Bypass -File .\start-dev.ps1 -ProjectRoot ..
```

If multiple supported browsers are installed, the script may show you a selection prompt before launching the shared browser.

What this script tries to do:

- find the app's `package.json`
- find a `dev`, `start`, or `serve` script
- guess the local URL and port
- start the local dev server if needed
- discover Chromium-based browsers and launch the one you choose with remote debugging enabled
- set the base URL for `live-browser.mjs`

### Step 4: Confirm that the browser connection works

Run:

```powershell
npm run live-browser -- status
```

or, if you are using the toolkit from a subfolder:

```powershell
node .\live-browser.mjs status
```

This should print the browser tabs that the toolkit can see.

### Step 5: Run a simple command

Try:

```powershell
npm run live-browser -- capture
```

This saves a screenshot, page HTML, and metadata under `test-results/live-browser/`.

## Beginner Workflow for an Already-Live Website

If you do not want to start a local dev server and just want to inspect a live site, use `-SkipServer`.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\start-dev.ps1 -SkipServer -Url "https://example.com"
```

This means:

- do not try to start a local app
- open the Chromium-based browser you choose to the given URL
- still allow the toolkit to attach to that browser window

That is useful for userscript work or page-behavior investigation on existing sites.

### Choose a Specific Browser From `start-dev.ps1`

You can pass the same browser-selection options through the startup script:

```powershell
powershell -ExecutionPolicy Bypass -File .\start-dev.ps1 -Browser chrome
powershell -ExecutionPolicy Bypass -File .\start-dev.ps1 -BrowserPath "C:\Program Files\Google\Chrome\Application\chrome.exe"
powershell -ExecutionPolicy Bypass -File .\start-dev.ps1 -NoBrowserPrompt
```

## Understanding the Main Commands

These are good starter commands:

```powershell
npm run live-browser -- help
npm run live-browser -- status
npm run live-browser -- capture
npm run live-browser -- meta
npm run live-browser -- links
```

What they do:

- `help`: prints the command list
- `status`: lists the pages in the shared browser
- `capture`: saves screenshot, HTML, and metadata
- `meta`: prints title, meta tags, and canonical URL
- `links`: lists links on the current page

Some interactive examples:

```powershell
npm run live-browser -- text "main h1"
npm run live-browser -- click "a[href]"
npm run live-browser -- fill "input" "hello@example.com"
npm run live-browser -- console 5000
npm run live-browser -- network 5000
```

## What `npm run ...` Means

If you are new to `npm`, this syntax can feel strange.

When you run:

```powershell
npm run start-dev
```

`npm` looks in `package.json`, finds the script called `start-dev`, and runs the command stored there.

When you run:

```powershell
npm run live-browser -- status
```

`npm` runs the `live-browser` script from `package.json`, and everything after `--` is passed to `live-browser.mjs`.

The `--` is important. It separates the npm command from the tool's own arguments.

## Smoke Verifier

`verify-live-browser.ps1` is the included test script.

Its job is to make sure the toolkit commands still work against a real browser.

### What It Tests Automatically

It always covers the commands that are generic enough to work on most pages:

- `help`
- `status`
- `capture`
- `links`
- `meta`
- `eval`
- `open`, `back`, `forward`, `reload`
- `scroll`
- console and network watcher tests
- storage commands
- viewport size changes and automatic reset
- PDF export

The verifier now runs a safe subset of independent commands in parallel worker tabs. It uses the same `crawlParallelTabs` setting as the crawler.
Stateful navigation/interactions still run sequentially to keep behavior deterministic.

By default, viewport smoke checks run on your active page so you can visually see each size change.
If you prefer non-intrusive viewport checks, set `viewportUseIsolatedTabs` to `true` in your smoke config.
At the end of a verifier run, the toolkit also performs a global viewport cleanup (`viewport reset-all`) to clear residual emulation on all open tabs.
You can also run that cleanup manually:

```powershell
node .\live-browser.mjs viewport reset-all
```

### What Needs a Config File

Commands like these depend on your page structure:

- `text`
- `html`
- `attr`
- `visible`
- `screenshot`
- `click`
- `fill`
- `type`
- `press`
- `select`
- `check`
- `hover`
- `wait`

Those commands only make sense if the verifier knows which selectors exist on your site.

That is why the toolkit includes `smoke.config.example.json`.

### Crawl-First Selector Discovery

Before running selector-dependent tests, the verifier now performs a lightweight crawl:

1. starts at the root route
2. follows internal links up to the configured crawl depth
3. scans each discovered page for testable selector types
4. builds a selector pool by type
5. for each selector-based test, tries candidates from that pool until one succeeds

This means the verifier no longer depends on a single hardcoded selector for commands like `text`, `click`, `fill`, `hover`, and `wait`.

You can control how far that crawl goes:

- `baseUrl`: strongly recommended when multiple unrelated tabs are open. It anchors navigation and crawl to your target site.
- `viewportUseIsolatedTabs`: when `true`, viewport smoke checks run in temporary tabs. Default is `false`.
- `crawlDepth`: how many internal link levels to follow from the root route. The default is `1`.
- `crawlMaxLinks`: maximum number of links to collect per page during a crawl. The default is `8`.
- `crawlParallelTabs`: how many background tabs are opened at once while crawling. The default is `4`.
- `crawlIncludePaths`: extra routes to scan directly, even if they are deeper than the normal click-depth limit or not linked from the start page.

In practice:

- `crawlDepth: 0` scans only the root route.
- `crawlDepth: 1` scans the root route plus pages linked directly from it.
- `crawlDepth: 2` also scans links discovered from those child pages.

Use `crawlIncludePaths` for pages such as hidden admin screens, deep docs pages, or routes that only appear after app state changes.

The crawler keeps your main tab as the active tab and processes discovered routes in background worker tabs. Each worker tab is closed immediately after its probe completes.

Some selector types may still be skipped on pages that simply do not contain that element type (for example, no `<select>` or no checkbox/radio inputs).

For `select`, `check`, and `uncheck`, the verifier also has a fallback probe path: if crawl discovery finds none, it can inject temporary probe controls into the current page so those command paths can still be exercised.

By default, selector-dependent tests are skipped when no selector candidate is discovered for that type.

If you want strict behavior (fail instead of skip), run the verifier with:

```powershell
powershell -ExecutionPolicy Bypass -File .\verify-live-browser.ps1 -ProjectRoot . -FailOnMissingSelectors
```

### First-Time Verifier Setup

Copy the example config:

```powershell
Copy-Item .\smoke.config.example.json .\smoke.config.json
```

Then edit `smoke.config.json` so the selectors match your site.

After that, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\verify-live-browser.ps1 -ProjectRoot . -ConfigPath .\smoke.config.json
```

### Run Only a Few Tests

You can filter the verifier to specific test names:

```powershell
powershell -ExecutionPolicy Bypass -File .\verify-live-browser.ps1 -ProjectRoot . -Tests "help,status,meta"
```

Another example:

```powershell
powershell -ExecutionPolicy Bypass -File .\verify-live-browser.ps1 -ProjectRoot . -ConfigPath .\smoke.config.json -Tests "text*","click*","fill*"
```

## Environment Variables

Most people can ignore these at first, but they are useful when you need more control.

- `PLAYWRIGHT_CDP_URL`: CDP connection URL. Default: `http://127.0.0.1:9222`
- `PLAYWRIGHT_LIVE_BASE_URL`: optional base URL hint used by `open` and page-ranking logic. If not set, the toolkit infers a base from the currently focused tab.
- `PLAYWRIGHT_LIVE_ISOLATED`: set to `1` to run each command against a dedicated isolated tab instead of the active page. Useful for scripted workflows that should not disturb the visible browser state.
- `PLAYWRIGHT_LIVE_OUTPUT_DIR`: where screenshots, HTML, PDFs, and window-state files are saved

When the verifier is given relative routes (like `/` or `/about`) and cannot determine a safe base URL, it now fails fast instead of navigating an unrelated tab.

Example of setting one in PowerShell for the current session:

```powershell
$env:PLAYWRIGHT_LIVE_BASE_URL = "http://localhost:4321/my-app/"
```

## Output Files

By default, output files go under:

```text
test-results/live-browser/
```

Typical files include:

- screenshot files
- captured HTML
- page metadata JSON
- PDF exports
- temporary watcher logs
- viewport window-state data used during reset

## Troubleshooting

### `node` or `npm` is not recognized

Node.js is not installed, or PowerShell needs to be reopened after install.

### The toolkit cannot connect to the browser

The browser needs to be running with a compatible CDP port exposed. Use this toolkit's launcher, or start the browser manually with `--remote-debugging-port=9222` (or whatever port `PLAYWRIGHT_CDP_URL` is set to).

### `start-dev.ps1` cannot find `package.json`

You probably pointed `-ProjectRoot` at the wrong folder.

If you are working on a live site instead of a local app, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\start-dev.ps1 -SkipServer -Url "https://example.com"
```

### A selector command fails

The selector probably does not match anything on the current page.

Start with simple commands like:

```powershell
npm run live-browser -- capture
npm run live-browser -- links
```

Then inspect the page and choose more specific selectors.

### The browser is connected, but the wrong tab is chosen

Run:

```powershell
npm run live-browser -- status
```

Then bring the desired tab to the front in your shared browser and run the command again.

## Notes

- Microsoft Edge is the most tested browser for this toolkit.
- Google Chrome, Brave, Vivaldi, Chromium, Opera, Opera GX, and Arc are also supported through the launcher's browser discovery and selection.
- The toolkit operates the same page you are looking at.
- Firefox is not supported by this toolkit.
