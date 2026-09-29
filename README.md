<p align="center">
  <img src="NagaControl/Icon/icon-1024.png" width="128" alt="Razer Control icon">
</p>

<h1 align="center">Razer Control</h1>

<p align="center">
  An unofficial native macOS app to configure the <b>Razer Naga Trinity</b> — no Razer Synapse required.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-000?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/device-RZ01--0241-44d62c" alt="RZ01-0241">
  <img src="https://img.shields.io/badge/languages-7-blue" alt="7 languages">
</p>

<p align="center">
  <b>English</b> · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="docs/buttons.png" width="820" alt="Button remapping">
</p>

## Why

Razer Synapse doesn't support the Naga Trinity on macOS. Razer Control speaks the mouse's own protocol directly, so you can remap buttons, tune DPI and set up lighting on a Mac. Every setting is written to the mouse's **onboard memory**, so it keeps working on any computer, even when the app isn't running.

## Features

**🖱 Button remapping**
- Remap any button: mouse clicks, keyboard shortcuts (recorded with one key press), DPI up/down
- One-click presets: browser back/forward, copy/paste/cut, Mission Control, switch Spaces, tabs
- Wheel tilt left/right, both top DPI buttons, and all three side plates (2, 7 and 12 buttons)
- Two layers: normal and **Hypershift**
- Restore any button to its factory action

**🎯 DPI & polling rate**
- Up to 5 DPI stages from 100 to 16,000, with optional separate X/Y
- Live readout of the current DPI, which updates when you press the DPI buttons
- Polling rate: 125 / 500 / 1000 Hz

**🌈 Lighting**
- Three zones: scroll wheel, logo and side panel. Set them together or one by one
- Static, breathing (single, dual or random colors), spectrum and reactive effects
- Per-zone brightness

**🌍 Localized** into English, Русский, Українська, Deutsch, Español, Français and 简体中文

<table>
  <tr>
    <td><img src="docs/dpi.png" alt="DPI and polling rate"></td>
    <td><img src="docs/lighting.png" alt="Lighting"></td>
  </tr>
</table>

## Install

There's no prebuilt release yet. Building takes about a minute.

**Requirements:** macOS 14 Sonoma or later and Xcode 15+ (or the Command Line Tools with Swift 5.10+).

```sh
git clone git@github.com:metlnt/razer-macos.git
cd razer-macos
./build-app.sh
open build/RazerControl.app
```

Then drag `build/RazerControl.app` into `/Applications` if you want to keep it.

The app talks to the mouse through USB control requests (`IOUSBHost`), so it **doesn't need** Input Monitoring or Accessibility permissions.

## FAQ

<details>
<summary><b>Do I have to keep the app running?</b></summary>

No. Changes are saved on the mouse itself. Open the app only when you want to change something.
</details>

<details>
<summary><b>Does it work with other Razer mice?</b></summary>

Not yet. It only supports the Naga Trinity (USB `1532:0067`). Other Razer mice use a similar protocol, but button IDs and lighting zones differ. PRs are welcome, and <a href="CAPABILITIES.md">CAPABILITIES.md</a> is a good place to start.
</details>

<details>
<summary><b>How do I get back to factory settings?</b></summary>

For one button, click <b>Restore factory</b>. For all of them, go to <b>Device → Reset all buttons to factory defaults</b>. The original factory mapping is also stored in <a href="backup-original.json">backup-original.json</a>.
</details>

<details>
<summary><b>How do I change the app's language?</b></summary>

The app follows your system language. To pick a different one for this app only, go to <b>System Settings → General → Language & Region → Applications</b>.
</details>

<details>
<summary><b>What is Hypershift?</b></summary>

It's a second layer of bindings, like an Fn key. While the Hypershift button is held, every other button performs its alternate action.
</details>

## How it works

The Naga Trinity takes 90-byte HID feature reports on interface 0: a command class, a command ID, arguments and an XOR checksum. The app sends them as HID `SET_REPORT`/`GET_REPORT` class requests on the default control pipe.

| Path | What's inside |
|---|---|
| `NagaControl/Sources/NagaKit` | Protocol: report framing, DPI, lighting and button commands, HID key table |
| `NagaControl/Sources/NagaControl` | SwiftUI app |
| `NagaControl/Localization` | `translations.py`, the single source of truth for all translations |
| `CAPABILITIES.md` | Reverse-engineered command reference |
| `razer_proto.py` | Python version of the protocol, for experiments (`pip install hidapi`) |

### Adding a translation

1. Add a column to `T` in `NagaControl/Localization/translations.py` and put the language code in `LANGS`.
2. Run `python3 NagaControl/Localization/translations.py`.
3. Add the code to `CFBundleLocalizations` in `build-app.sh`.

> [!WARNING]
> The firmware accepts any command in class `0x06`, and `06:8D` hangs the mouse's control interface until you replug it. The app never sends these commands. Keep that in mind if you experiment with `razer_proto.py`.

## Disclaimer

This is an unofficial project and is not affiliated with or endorsed by Razer Inc. "Razer" and "Naga" are trademarks of Razer Inc. Use it at your own risk.
