Cursor Control Installation

Why macOS may block it:

This release is ad-hoc signed and not Apple-notarized because it is distributed
without an Apple Developer Program account. Only install it from the official
GitHub release or Homebrew tap.

On first launch, macOS may warn that Apple could not verify Cursor Control and
may show a Move to Trash button. Do not click Move to Trash if you want to use
the app.

1. Move Cursor Control.app into your Applications folder.
2. Open Cursor Control from Applications.
3. If macOS blocks the app, click Done or Cancel.
4. Open System Settings > Privacy & Security, find the message for Cursor
   Control, click Open Anyway, then confirm Open.
5. Some macOS versions may also allow Control-clicking Cursor Control.app and
   choosing Open.
6. Grant Accessibility access when Cursor Control asks for it.

After it opens:

Cursor Control opens Settings and appears in the Dock and menu bar. Reopen
it from Applications or your launcher to show Settings again. Use the menu bar icon to open the guide, settings, or quit the app.

Homebrew install:

brew tap syedhy/cursor-control
brew trust --cask syedhy/cursor-control/cursor-control
brew install --cask syedhy/cursor-control/cursor-control
