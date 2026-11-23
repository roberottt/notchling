<div align="center">

# Notchling

**Your Claude Code sessions, living in the MacBook notch.**

Stop alt-tabbing to check whether Claude is done, stuck, or waiting for you.
Notchling turns the notch into a tiny status island that tells you at a glance — and taps you on the shoulder when a session needs you.

![Notchling expanding when a session asks for permission](docs/demo.gif)

</div>

## Why

You start a long task in Claude Code, switch to something else, and come back ten minutes later to find it has been waiting for a permission prompt the whole time. Notchling fixes that:

- **See everything at a glance.** The most urgent session sits next to the notch; every other one gets its own colored dot.
- **Never miss a prompt.** When Claude asks for permission, has a question, or wants you to review a plan, the island expands by itself.
- **Jump straight there.** Click a session and the terminal or editor that hosts it comes to the front.
- **Zero setup.** No hooks, no config changes, no network. Install it and it just finds your sessions.

<p align="center">
  <img src="docs/collapsed.png" width="620" alt="Collapsed island showing the Working, Permission and Question states">
</p>

## Install

Requires macOS 14 or later and the Command Line Tools (`xcode-select --install`). Xcode is not needed.

```sh
git clone https://github.com/roberottt/notchling.git
cd notchling
scripts/build.sh --install   # builds the app, copies it to ~/Applications and opens it
```

To start it with your Mac: menu bar icon → **Open at login**.

## What it shows

<p align="center">
  <img src="docs/expanded.png" width="620" alt="Expanded island listing three Claude Code sessions">
</p>

| State | Meaning | Animation |
| --- | --- | --- |
| 🔒 **Permission** | Waiting for you to approve an action | Shaking padlock, pulsing border |
| 💬 **Question** | Waiting for an answer | Bouncing bubble, pulsing border |
| 📋 **Review plan** | A plan is ready for your approval | Beating clipboard, pulsing border |
| ❗ **Needs you** | Waiting for some other reason | Bouncing alert, pulsing border |
| ⚠️ **Error** | The turn ended with an API error | Red triangle |
| 🗂️ **Menu open** | A dialog is open inside the session | Static icon |
| ✅ **Done** | Just finished (for 5 min or until you click) | Check mark drawing itself |
| 🔄 **Working** | Thinking or using tools | Spinning ring, shimmering text |
| ⏳ **Background** | A background command is still running | Slow ring |
| 💤 **Idle** | Doing nothing | Shrinks to the minimum |
| ❔ **Detected** | Session found, but it doesn't publish its state | Static icon |

With several sessions, the most urgent one wins the spot next to the notch.

## Using it

- **Hover** to expand the list. With more than six sessions, scroll.
- **Click a row** to bring the app hosting that session to the front.
- **Drag** the island anywhere, on any screen. Near a notch it snaps in; pull it away to undock it.
- **Menu bar:** move the pointer to the menu bar outside the notch and the island tucks its wings away so you can reach your app's menus. Toggle it with **Make way for app menus**.
- **Right-click** or use the menu bar icon for position, compact mode, language (English / Español) and more.

Automatic placement: in the notch when you only use the laptop screen, top center of the external display when there is one. Each monitor setup remembers its own position.

## How it works

Notchling is read-only and fully local. It doesn't install hooks, doesn't touch `~/.claude`, and never uses the network. Every 0.4 s it reads:

1. `~/.claude/sessions/<pid>.json`, where Claude Code publishes the state of each session.
2. The process table, to drop dead sessions and find ones using a different `CLAUDE_CONFIG_DIR`.
3. The new lines of each transcript, for the title and the current action.

It's a native app written in Swift with AppKit and Core Animation: no Electron, no web views.

## Limitations

- The session registry is an **internal format** of Claude Code (verified on 2.1.325–2.1.330) and may change. If it does, `Sources/NotchCore/StateResolver.swift` is the place to look.
- Without that registry (older versions), state is inferred from the transcript and **permission prompts can't be detected**. This path has only been tested with simulated data.
- It can't see sessions running in the cloud, over SSH, in containers or VMs, or under other macOS users.
- Clicking activates the app, not the exact tab. `--bg` sessions and sessions inside tmux have no app to activate.
- Next to the notch it covers any menu that reaches that far while the pointer isn't on the menu bar.
- Builds are signed locally. Distributing a prebuilt app needs a Developer ID and notarization.

## Development

```sh
swift test
scripts/build.sh
build/Notchling.app/Contents/MacOS/Notchling --demo   # cycles through every state with fake sessions
build/Notchling.app/Contents/MacOS/Notchling --dump   # prints what the detector sees, as JSON
```

`Sources/NotchCore` holds detection and geometry; `Sources/Notchling` holds the interface.

## Contributing

Issues and pull requests are welcome. Every PR is reviewed and approved by the maintainer before it's merged.

---

<sub>Notchling is an independent project and is not affiliated with or endorsed by Anthropic.</sub>
