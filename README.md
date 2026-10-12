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
                        ├─▶ AI·mana for Mac, or usage-relay ─▶ usage-relay.json ─────────▶ iPhone · iPad · Watch
Codex session logs ─────┘   on Windows and Linux               in iCloud Drive or OneDrive

Your API keys ───────────────────────────────────────────────────────────────────────────▶ read on the iPhone
```

The iPhone reads the summary that your computer publishes. Requests to API providers go directly from your device
to that provider. AI·mana runs no server and has no analytics. See [PRIVACY.md](PRIVACY.md).

## Get started

Setup has three steps. Follow them in order.

### What you need

- An iPhone or iPad with iOS / iPadOS 17 or later (Apple Watch: watchOS 10 or later).
- A Mac with Xcode 26 or later, to install the iPhone app. AI·mana is not in the App Store yet.
- An Apple ID. A free account works, but Apple makes apps built with it expire after 7 days, so you must rebuild
  every week.
- For Claude Code and Codex quotas: the computer where you use them (Mac, Windows or Linux) and a folder it shares
  with your iPhone (iCloud Drive or OneDrive). API balances need no computer.

### Step 1: install the app on your iPhone

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
2. Download the code and open the project:

   ```bash
   git clone https://github.com/p4ranoic0/AI-mana.git AImana
   cd AImana
   cp AImana/Config/Local.xcconfig.example AImana/Config/Local.xcconfig
   ```

3. Edit `AImana/Config/Local.xcconfig`: set your Team ID and a bundle prefix you own (for example `com.yourname`).
4. Generate and open the project:

   ```bash
   cd AImana && xcodegen generate && open AImana.xcodeproj
   ```

5. Connect your iPhone, choose the `AImana` scheme and your device, and press Run.

To track only API balances, you are done: add your keys in the app's settings.

### Step 2: publish your usage from your computer

Do this on the computer where you use Claude Code or Codex. Pick your system:

**Mac**

1. In the same Xcode project, choose the `AImanaMac` scheme and **My Mac**, and press Run. The app appears in the
   menu bar.
2. In its settings, install the Claude Code statusline integration and check that iCloud Drive is available.

The app publishes `iCloud Drive/AImana/usage-relay.json` by itself.

**Windows**

1. Install [Scoop](https://scoop.sh/) if you do not have it, then in PowerShell:

   ```powershell
   scoop bucket add aimana https://github.com/p4ranoic0/scoop-bucket
   scoop install usage-relay
   usage-relay setup
   ```

2. `setup` prints the path of the published file. Keep it for step 3.

Without Scoop: download the Windows ZIP from [Releases](https://github.com/p4ranoic0/AI-mana/releases), extract
all files into one folder, and run `.\usage-relay.exe setup` from that folder.

**Linux**

1. Install with [Homebrew](https://github.com/p4ranoic0/homebrew-tap), or download the Linux archive from
   [Releases](https://github.com/p4ranoic0/AI-mana/releases):

   ```sh
   brew install p4ranoic0/tap/usage-relay
   ```

   The binary needs the system `libcurl` (Ubuntu: `sudo apt install libcurl4`).
2. Publish into a folder that syncs with your iPhone:

   ```sh
   usage-relay setup --output /path/to/synced/folder/usage-relay.json
   ```

`setup` finds your Claude Code and Codex data, publishes once, installs the Claude statusline capture and schedules
a publish every five minutes in the background (a hidden scheduled task on Windows, a systemd user timer on Linux).

### Step 3: connect the iPhone

1. Open AI·mana on your iPhone and go to **Settings › Your computer**. On first launch, the dashboard shows the
   same button.
2. Tap **Choose relay file…** and pick `usage-relay.json` in the Files picker (folder `iCloud Drive/AImana`, or the
   one `setup` printed).
3. Your Claude Code and Codex quotas appear on the dashboard. Add the widgets, the Watch app or the Live Activity if
   you like.

### If something does not show up

- Windows or Linux: run `usage-relay doctor`. It checks each part and prints how to fix what is missing.
- Claude Code numbers appear after your next Claude Code message, when its statusline runs.
- iCloud for Windows can take a while to upload. OneDrive also works in the iPhone Files picker.
- To remove the background task and restore your previous statusline: `usage-relay uninstall`.

## More details

### Updating

- iPhone and Mac app: `git pull`, then run the schemes again from Xcode.
- Windows: `scoop update usage-relay`. Linux: `brew upgrade usage-relay`. The background task keeps working.

### Relay CLI reference

`usage-relay setup [--output FILE] [--interval MINUTES]`, `doctor`, `uninstall`, `run [--output FILE]`,
`check FILE`, `costs` and `--version`. The default output is `iCloudDrive/AImana/usage-relay.json` on Windows when
iCloud Drive exists (otherwise OneDrive, otherwise `AImana` in your user folder), and `~/AImana/usage-relay.json` on
Linux. If systemd is not available on Linux, `setup` prints a crontab line for you to add. Linux state uses
`${XDG_DATA_HOME:-~/.local/share}/aimana` and caches use `${XDG_CACHE_HOME:-~/.cache}/aimana`; Windows uses
`%LOCALAPPDATA%\AImana`. To build the CLI from source: `swift build -c release --package-path AImana/Relay`.

**WSL:** the Linux binary also works inside WSL. If Claude Code and Codex run on Windows, point it at their Windows
data and publish into the Windows synced folder:

```sh
WINHOME="$(wslpath "$(cmd.exe /C 'echo %USERPROFILE%' | tr -d '\r')")"
CLAUDE_CONFIG_DIR="$WINHOME/.claude" CODEX_HOME="$WINHOME/.codex" \
  usage-relay setup --output "$WINHOME/iCloudDrive/AImana/usage-relay.json"
```

### Tests

Run `swift test` in `AImana/AImanaCore` and in `AImana/Relay`.

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
