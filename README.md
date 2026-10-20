# Cursor Control

[![Release](https://img.shields.io/github/v/release/syedhy/Cursor-Control?label=release)](https://github.com/syedhy/Cursor-Control/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13%2B-lightgrey.svg)](#requirements)

Cursor Control is a native macOS menu bar app for moving the mouse cursor,
clicking, dragging, and scrolling with the keyboard. It is built with AppKit,
has no web runtime, and stays out of the Dock.

## Before You Install

Cursor Control is currently ad-hoc signed and not Apple-notarized because it is
distributed without an Apple Developer Program account.

On first launch, macOS may show a warning such as:

```text
Apple could not verify "Cursor Control.app" is free of malware that may harm your Mac or compromise your privacy.
```

Depending on your macOS version, the dialog may offer **Done**, **Cancel**, or
**Move to Trash**. Do not click **Move to Trash** if you want to use the app.

To open Cursor Control:

1. Click **Done** or **Cancel** on the warning.
2. Open **System Settings**.
3. Go to **Privacy & Security**.
4. Scroll to the message about `Cursor Control.app`.
5. Click **Open Anyway**.
6. Confirm **Open**.

Some macOS versions may also allow Control-clicking `Cursor Control.app` in
Applications and choosing **Open**, but **Privacy & Security > Open Anyway** is
the most reliable method.

Only install Cursor Control from this repository's GitHub Releases page or the
official Homebrew tap.

## Install

### Option 1: GitHub Release ZIP

1. Download `CursorControl-1.0.0-macOS.zip` from the [latest release](https://github.com/syedhy/Cursor-Control/releases/latest).
2. Unzip it.
3. Move `Cursor Control.app` to the Applications folder.
4. Open `Cursor Control.app`.
5. Follow the first-launch steps above if macOS blocks it.
6. Grant Accessibility access when prompted.

### Option 2: Homebrew

This option requires [Homebrew](https://brew.sh/) to be installed first.

```bash
brew tap syedhy/cursor-control
brew trust --cask syedhy/cursor-control/cursor-control
brew install --cask syedhy/cursor-control/cursor-control
```

If you have already installed Cursor Control via Homebrew and want to update to the latest version, simply run:
```bash
brew upgrade cursor-control
```

The cask installs the same GitHub Release ZIP and verifies it with the checksum
stored in the cask.

## What It Does

- Move the cursor with **H/J/K/L**
- Scroll smoothly anywhere on screen with **Control-H/J/K/L**
- Left-click, double-click, right-click, and **Shift-drag (click and drag)** from the keyboard
- **Middle-click**: Global shortcut to instantly middle-click at your current cursor position (great for opening links in new tabs)
- **Mouse Jiggler (Keep Awake)**: Prevent your Mac from falling asleep during long tasks. Toggle it on and it will gently nudge your cursor every 30 seconds if you're completely inactive.
- **Auto-Clicker**: Hold a shortcut to fire continuous clicks, and release to stop instantly
- Configure global shortcuts, movement keys, scroll behavior, auto-click speed, and cursor speed
- Run quietly from the menu bar with onboarding and a comprehensive settings window

## Requirements

- macOS 13 Ventura or later
- Accessibility permission, granted by the user after opening the app

Building from source also requires Xcode 15 or later, or matching Xcode Command
Line Tools with a Swift 6 compatible toolchain.

## Usage

Opening `Cursor Control.app` adds a cursor icon to the macOS menu bar. It does
not open a main window or appear in the Dock.

The menu bar menu contains:

- **Cursor Control Mode**: enter or exit keyboard cursor-control mode
- **How to Use Cursor Control...**: open the onboarding guide
- **Settings...**: configure shortcuts, scrolling, and cursor movement
- **Quit Cursor Control**: exit the app

### Cursor Control Mode

Press **Option-W** by default to enter or exit cursor mode. To use a modifier-only
shortcut, open Settings → Shortcuts, record Cursor control mode, and quickly tap
and release Left Option or Right Option. The sides are distinct. A tap must finish
within 250 ms; holding Option or combining it with another key or mouse click does
not toggle the mode. This requires Accessibility access. Existing shortcuts and the
Option-W default are unchanged.

While cursor mode is active:

- **H/J/K/L** move the real cursor left, down, up, and right
- Holding movement keys accelerates smoothly
- Holding two movement keys moves diagonally
- Hold **Shift** to hold the left mouse button down, move with **H/J/K/L**, then
  release **Shift** to drop or stop drawing
- **Return** left-clicks at the current cursor location
- Press **Return** twice quickly to double-click
- **Shift-Return** or **Control-Return** right-clicks

Cursor mode stays active after clicks. Toggle it off when you want normal
typing, then toggle it back on when you want keyboard mouse control again.

### Scrolling

Scrolling works globally without opening another window. Press
**Control-H/J/K/L** to scroll left, down, up, and right in the frontmost app.

Settings lets you tune scroll distance, scroll events per repeat, hold
acceleration, and acceleration cap.

## Accessibility Permission

Cursor Control needs Accessibility permission to send keyboard-requested input
events: cursor movement, clicks, dragging, and scrolling.

It uses this permission only for actions you explicitly request from the
keyboard. If access is missing, Cursor Control explains why it is needed and can
open the correct System Settings pane.

If Cursor Control remains untrusted after you enable it, remove the existing
Cursor Control entry in **System Settings > Privacy & Security > Accessibility**,
reopen the current app, and grant access again. This can happen when replacing an
older local build that used a different signing identity.

## Build From Source

Clone the repository, then run:

```bash
./script/build_and_run.sh
```

The script builds the Swift package, creates `dist/Cursor Control.app`, copies it
to Applications, and opens it.

You can also build without launching:

```bash
swift build
```

## Releasing

Maintainers can create and verify a release package with:

```bash
VERSION=1.0.0 ./script/package_release.sh
VERSION=1.0.0 ./script/verify_release_package.sh
VERSION=1.0.0 ./script/generate_homebrew_cask.sh
```

See [RELEASING.md](RELEASING.md) for the full release checklist.

## Project Structure

```text
Sources/CursorControl/
├── Accessibility/ Accessibility permission guidance
├── Application/   App lifecycle
├── CursorControl/ Keyboard cursor movement
├── Keyboard/      Global shortcuts and key capture
├── MenuBar/       Status item and menu ownership
├── Mouse/         Native mouse clicking
├── Onboarding/    Built-in quick-start guide
├── Scroll/        Universal scroll event targeting and posting
├── Settings/      Settings window
└── Support/       Shared application constants
script/            Build and release tooling
packaging/         Homebrew cask output
```

## Contributing

Issues and pull requests are welcome. Please keep changes focused, native to
macOS, and free from unnecessary dependencies

## License

Cursor Control is available under the [MIT License](LICENSE).
