# TODO

## Next Iteration

- Add per-browser launch flag templates where needed (for example, browser-specific startup arguments beyond `--remote-debugging-port` and optional `--user-data-dir`).
- Add per-browser profile directory handling so each supported browser can use a stable, explicit profile path when required.
- Add a browser capability map documenting which launch flags are known-good per browser.
- Add validation checks that warn when a chosen browser path is valid but known profile/flag behavior is unverified.
- Add optional `-ProfileDir` override so users can force a profile location from the command line.
- Add tests that exercise browser selection plus browser-specific launch argument construction.
