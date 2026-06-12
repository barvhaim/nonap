# NoNap ☕

[![Build](https://github.com/barvhaim/nonap/actions/workflows/build.yml/badge.svg)](https://github.com/barvhaim/nonap/actions/workflows/build.yml)

A tiny macOS menu bar app that keeps your Mac awake while the long jobs run —
**AI coding agents** (Claude Code, Cursor, Codex), local model inference, and
overnight runs, plus the builds, backups, and SSH sessions you already trust it
for. The GUI for `caffeinate`. Start a long agent run, walk away, and let it
finish — without your Mac sleeping and killing the session. Or point NoNap at the
run itself and let it stay awake **until the job is actually done**, then stop on
its own.

**[→ nonap website](https://barvhaim.github.io/nonap/)** · **[Download](https://github.com/barvhaim/nonap/releases)**

<p align="center">
  <img src="docs/screenshot.png" alt="NoNap menu" width="210">
</p>

- ☕ Lives in the menu bar — green dot when awake, faint ring when off
- ⏱ One click to keep awake, or a timed session — presets (15 m … 8 h) or a typed **custom** duration — with a live countdown
- 🎯 Or keep awake **until your job finishes** — pick a running process (Claude Code, Cursor, Codex, `node`, `python`, `ollama`…) or a PID, and NoNap stops itself the moment it exits. No more guessing a timer
- 🎛 Three modes: prevent **system** sleep (default), **display** sleep, or **both**
- 🔔 Notifies you when a timer ends, and can **launch at login**
- 🪶 Uses native IOKit power assertions — no daemons, no polling. Remembers your mode.

## Install

Download `NoNap.dmg` from the
[**Releases**](https://github.com/barvhaim/nonap/releases) page, open it, and drag
**NoNap** into Applications. (A `NoNap.zip` is also attached if you prefer.)
Apple Silicon (arm64) only.

**First launch.** The build is ad-hoc signed (not notarized), so macOS blocks it
once. Double-click `NoNap.app`, dismiss the warning, then open **System Settings
→ Privacy & Security**, scroll to the bottom, and click **Open Anyway**. After
that it launches normally.

Or skip the prompt entirely from Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/NoNap.app
```

## Modes

| Mode | Keeps awake | Like |
|------|-------------|------|
| **Prevent system sleep** *(default)* | System; display may sleep | `caffeinate` |
| **Prevent display sleep** | System **and** screen | `caffeinate -d` |
| **Prevent both** | System **and** screen | — |

## Build from source

Requires Xcode 16+ / Swift 6.

```bash
git clone https://github.com/barvhaim/nonap.git
cd nonap

swift run                 # run directly (menu-bar accessory, no Dock icon)
./Scripts/make_app.sh     # build a NoNap.app bundle
./Scripts/make_dmg.sh     # build a drag-to-install NoNap.dmg
./Scripts/package_zip.sh  # build + zip to NoNap.zip for sharing
```

To confirm it's holding a power assertion while active:

```bash
pmset -g assertions | grep NoNap
```

## Contributing

Issues and PRs welcome — the whole app is four small Swift files under
`Sources/NoNap/`. See [RELEASING.md](RELEASING.md) for how releases are cut.

## License

[MIT](LICENSE) © barvhaim
