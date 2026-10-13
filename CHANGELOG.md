# Changelog

All notable changes to AI·mana are documented here. This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
