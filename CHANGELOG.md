# Changelog

All notable changes to AI·mana are documented here. This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.3.0] - 2026-11-08

### Added

- Optional direct access on Mac and iPhone, off by default: sign in with Claude or ChatGPT on the iPhone, or let the
  Mac read the session Claude Code or Codex already keeps. A notice explains the providers' terms before it turns on.
- The dashboard says when it is showing relay data because direct access failed.
- Windows and Linux tray app: click the icon to see your Claude Code and Codex quotas on the computer. With direct
  access on, it reads the session the CLI already keeps; otherwise it shows what `usage-relay` publishes. The Windows
  installer includes it; Linux gets a `.deb`.
- Optional direct access on Android, off by default: sign in with Claude (paste the code) or ChatGPT (device code,
  or the browser when device codes are off). Sessions are encrypted with the Android Keystore and kept out of backups.
- API balances on Android with your own keys: DeepSeek, Moonshot (Kimi), xAI, OpenRouter and GitHub Copilot, with the
  same numbers as the iPhone.
- Android and the Windows/Linux tray say when a newer release is out (one anonymous request to GitHub a day; can be
  turned off in Settings). Android's About shows the installed version instead of a fixed number.
- An old reading says why when it can tell: your computer stopped publishing (with how long ago), or the CLI simply
  hasn't been used since. On iPhone, Mac, Android and the Windows/Linux tray.

### Changed

- Retry-After limits now survive app and widget restarts.

### Fixed

- Windows: `usage-relay setup` and the installer no longer fail when `~/.claude/settings.json` has a top-level `true` or
  `false` value, which left the scheduled task uninstalled.

## [1.2.0] - 2026-10-14

### Added

- Android app preview (Kotlin, Jetpack Compose) that reads the same relay file, with the same numbers as the iPhone app.
- Windows installer, Mac app download and a signed Android APK in every release.
- Install website with step-by-step guides for every device: https://p4ranoic0.github.io/AI-mana/

### Fixed

- iPhone demo mode now shows sample costs.

## [1.1.1] - 2026-10-13

### Changed

- The iPhone, iPad, widgets and Watch now say "your computer" instead of "your Mac" for the relay, which can run on a Mac, Windows or Linux. The Settings section is now called "Your computer".

### Fixed

- The Linux systemd timer and printed cron command now keep the custom Claude, Codex, data and cache folders used during setup.

## [1.1.0] - 2026-10-12

### Added

- Native Windows x86_64 relay and scheduled background publishing, with iCloud Drive and OneDrive output defaults.
- `usage-relay setup`, `doctor`, and `uninstall` for Windows and Linux, including Claude statusline capture.
- End-to-end CI checks of setup, scheduled publishing and uninstall on Windows and Linux.
- [Homebrew tap](https://github.com/p4ranoic0/homebrew-tap) that installs the relay CLI on macOS and Linux.

## [1.0.0] - 2026-10-11

### Added

- Native iPhone and iPad dashboard for Claude Code and Codex usage windows, reset times, pace projections, cost estimates and history.
- Home Screen and Lock Screen widgets, interactive refresh, a Control Center control, Live Activity, Siri and App Shortcuts.
- Apple Watch app and watch-face complications synced from the iPhone.
- Mac menu bar app that reads local Claude Code statusline data and Codex session logs and shares a small summary through iCloud Drive.
- `usage-relay` CLI for macOS and Linux, with downloadable release archives for macOS universal, Linux x86_64 and Linux aarch64.
- Direct iPhone balance tracking for OpenRouter, GitHub Copilot, DeepSeek, Moonshot (Kimi) and xAI using the user's API keys.
- English, Spanish, Portuguese (Brazil), French, German and Italian localizations.
