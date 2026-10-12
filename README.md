# AI·mana

**Your AI coding quotas and spend, native on iPhone, iPad, Apple Watch and Mac.**

[Español](README.es.md)

AI·mana shows how much of your Claude Code and Codex limits you have used, when each window resets, whether your
pace will run out before the reset, and what that usage would cost at public API prices. It also tracks prepaid
balances for API providers straight from your iPhone, without a Mac.

It is free and open source (MIT). It has no account and no server, and it uses **official data sources only**.

> AI·mana is an independent project. It is not affiliated with, endorsed by or sponsored by Anthropic, OpenAI,
> GitHub, OpenRouter, DeepSeek, Moonshot AI or xAI. Their names are used only to describe compatibility.

<p align="center">
  <img src="docs/screenshots/dashboard-light.png" width="200" alt="Dashboard, light theme">
  <img src="docs/screenshots/dashboard-dark.png" width="200" alt="Dashboard, dark theme">
  <img src="docs/screenshots/detail.png" width="200" alt="Claude Code detail with daily budget">
  <img src="docs/screenshots/balances.png" width="200" alt="API provider balances">
</p>

<p align="center">
  <img src="docs/screenshots/ipad-dashboard.png" height="300" alt="iPad dashboard">
  <img src="docs/screenshots/mac-menu.png" height="300" alt="Mac menu bar app">
  <img src="docs/screenshots/watch.png" height="200" alt="Apple Watch app">
</p>

## Features

**iPhone and iPad**
- A dashboard with each 5-hour and weekly window, shown as used or remaining, as bars or rings.
- A pace projection: will you hit the limit before it resets?
- API-equivalent cost estimates and history, computed on your Mac from local token counts.
- Home Screen and Lock Screen widgets, an interactive refresh button and a Control Center control.
- A Live Activity and the Dynamic Island for the provider you are watching.
- Siri and App Shortcuts ("How much Claude is left in AI·mana?").
- Notifications for fast pace, quota available again and a daily summary.
- Six languages: English, Spanish, Portuguese (Brazil), French, German and Italian.

**Apple Watch**
- An app and watch-face complications, synced from the iPhone.

**Mac (menu bar)**
- Reads Claude Code's official statusline data (`rate_limits`), which needs no credentials.
- Reads Codex's local session logs (`~/.codex/sessions`).
- Estimates costs from local token counts and public model prices.
- Publishes a small summary file to your iCloud Drive for the iPhone. It contains no credentials and no prompts.

**API providers, on the iPhone, no Mac needed** (with your own key)
- OpenRouter, GitHub Copilot, DeepSeek, Moonshot (Kimi) and xAI. Keys stay in the iOS Keychain.

## How it works

```
Claude Code statusline ─┐
Codex session logs ─────┼─▶ AI·mana for Mac ─▶ iCloud Drive/AImana/usage-relay.json ─▶ iPhone · iPad · Watch · widgets
                        │
Your API keys ──────────┴──────────────────────────────── (read directly on the iPhone) ─┘
```

The iPhone reads the summary that your Mac publishes. Requests to API providers go directly from your device to
that provider. AI·mana runs no server and has no analytics. See [PRIVACY.md](PRIVACY.md).

## Requirements

- iOS / iPadOS 17 or later, watchOS 10 or later, macOS 14 or later.
- Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- For Claude Code and Codex data: the AI·mana Mac app on a Mac signed in to the same iCloud account as the iPhone.
- An Apple ID. A free account works, but Apple makes apps built with it expire after 7 days, so you must rebuild
  every week.

## Build and install

To install the apps, build them from source:

```bash
git clone https://github.com/p4ranoic0/AI-mana.git AImana
cd AImana
cp AImana/Config/Local.xcconfig.example AImana/Config/Local.xcconfig
# Edit Local.xcconfig with your Team ID and a bundle prefix you own (for example com.yourname).
cd AImana && xcodegen generate && open AImana.xcodeproj
```

1. **Mac:** run the `AImanaMac` scheme. In its settings, install the Claude Code statusline integration and
   check that iCloud Drive is available. The app publishes automatically.
2. **iPhone:** run the `AImana` scheme on your device. In Settings › AImana for Mac, tap
   **Choose relay file…** and pick `iCloud Drive/AImana/usage-relay.json`.
3. Add the widgets, the Watch app or the Live Activity as you like.

Run the tests with `swift test` in `AImana/AImanaCore` and in `AImana/Relay`.

### Relay CLI for macOS and Linux

Download a prebuilt `usage-relay` binary for macOS or Linux from the
[Releases page](https://github.com/p4ranoic0/AI-mana/releases), or build from source.
With [Homebrew](https://github.com/p4ranoic0/homebrew-tap) on macOS or Linux:

```sh
brew install p4ranoic0/tap/usage-relay
```

On Linux, the binary also needs the system `libcurl` library (for Ubuntu: `apt install libcurl4`).
To build it from source, run `swift build -c release --package-path AImana/Relay`, then
`AImana/Relay/.build/release/usage-relay run --output /path/to/synced/usage-relay.json`.
Choose that file
on the iPhone with **Choose relay file…**. Without `--output`, Linux writes to
`~/AImana/usage-relay.json`. State and support files use `${XDG_DATA_HOME:-~/.local/share}/aimana`;
caches use `${XDG_CACHE_HOME:-~/.cache}/aimana`.

The `statusline` installer is unavailable through the Linux CLI because its generated script relies on
macOS `plutil` when `jq` is absent. The relay can still read an existing Claude statusline capture file
from its support directory, and it reads Codex session logs directly.

## Roadmap

- **Windows** (planned, no date): publish the relay file to a synced folder (iCloud for Windows, Dropbox,
  OneDrive or Syncthing) that the iPhone opens with **Choose relay file…**.

## When a provider changes something

AI·mana depends on formats that other companies control, and those can change without notice. Each provider's
parser is isolated and covered by fixture tests. If numbers look wrong, please open an issue using the
**Provider changed** template.

## Support the project

AI·mana is free. If it saves you from running out of quota halfway through a task, you can support its
development:

- [Ko-fi](https://ko-fi.com/post/AImana-your-AI-coding-quotas-on-iPhone-Watch-an-S1D028MW28): one-time or monthly, by card or PayPal. Write "AI·mana" in your message.
- Yape (from Peru): scan the QR code below with the Yape app.

<img src="docs/donate/yape.png" alt="Yape QR code to support AI·mana" width="180">

Stars, bug reports and translations help too.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
