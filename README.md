# rook

A fast, native window manager for macOS that sits between Rectangle and a tiling WM: keyboard snapping, drag-to-snap zones, and saved layouts, with no tiling tree and no SIP changes.

## Status

- [x] Phase 0: app scaffold, menu bar item, Accessibility onboarding, stable signing
- [x] Phase 1: keyboard snapping (halves, thirds, quarters, maximize, center, grow/shrink), size cycling, restore, move between displays
- [x] Phase 2: `~/.config/rook/config.toml` with live reload
- [x] Phase 3: drag-to-snap overlay, modifier-drag move/resize
- [x] Phase 4: named layouts and auto-placement rules
- [ ] Phase 5: launch at login and compatibility fixes implemented; signed universal packaging verified; login UI verification, notarization and Homebrew publication pending

## Build and run

```sh
make run      # build, bundle into build/Rook.app, sign, launch
make test     # unit tests for the pure core
make install  # copy to /Applications
```

On first launch rook asks for Accessibility access and starts working as soon as you turn it on. The Makefile signs with your first "Apple Development" identity so the grant survives rebuilds. Override with `SIGN_IDENTITY=...`.

Choose **Launch at Login** in the menu to enable or disable automatic startup. Install rook in `/Applications` first (`make install`), since macOS registers the app at its current path. If approval is needed, rook opens Login Items settings and shows a reminder in its menu.

## Config

On first launch rook writes a commented `~/.config/rook/config.toml` (or `$XDG_CONFIG_HOME/rook/config.toml`). Changes apply as soon as you save. Editors that save atomically and symlinked dotfiles (stow, chezmoi) both work. If the file has an error, rook keeps the last working config, turns the menu bar icon into a ⚠︎, and shows the line and the problem in the menu.

```toml
gaps = { outer = 8, inner = 8 }   # or: gaps = 8
almost_maximize = 0.9
resize_step = 40

[keys]                             # replaces the defaults entirely
"ctrl+alt+left"  = "left-half"
"ctrl+alt+r"     = "reload-config"
"ctrl+alt+up"    = "none"          # disable

[drag]                             # mouse features: all off by default
enabled = false                    # true: snap by dragging to screen edges
bottom_edge = "thirds"             # "thirds" | "half" | "none"
restore_size = true                # dragging a snapped window away restores its size
modifier = "none"                  # e.g. "ctrl+cmd": hold + drag to move, + right-drag to resize
```

## Mouse (opt-in)

Off by default. With `[drag]` left alone rook never installs a mouse event tap at all. Turn on either part in `[drag]`:

- **Drag to snap:** drag a window by its title bar to a screen edge. Left/right = half, corners = quarter, top = maximize, bottom = thirds by cursor position. A preview shows where it will land; let go to snap it. Edges shared with another monitor are ignored, so moving a window between monitors doesn't trigger a snap.
- **Unsnap:** dragging a snapped window away gives it back its earlier size, still under the cursor.
- **Modifier-drag:** hold `ctrl+cmd` and drag anywhere in a window to move it, or right-drag to resize from the nearest corner. Screen edges snap here too.
- macOS 15+ has its own edge tiling. The two fight each other, so rook notes it in the menu with a link to the setting.

## Layouts and rules

A **layout** is a named arrangement of apps, like "coding" = editor on the left two-thirds and terminal on the right third. To make one, arrange your windows and choose **Layouts ▸ Save Current Layout…**. That writes `~/.config/rook/layouts/<name>.toml`, which you can edit. You can also define layouts in `config.toml`:

```toml
[keys]
"ctrl+alt+1" = "layout:coding"

[[layouts.coding]]
app = "com.microsoft.VSCode"        # bundle id
rect = "left-two-thirds"            # placement action or { x, y, w, h } fractions
display = "main"                    # "main" | "secondary" | 1,2,3 (left→right) | display name

[[layouts.coding]]
app = "com.mitchellh.ghostty"
rect = "right-third"
```

Applying a layout opens any missing apps in the background, waits for their windows, places them, and brings the first app to the front. Displays fall back to the main one, so a two-monitor layout still works on the laptop alone. Snapped windows are saved by action name, so they pick up gap changes later. `title = "…"` picks a specific window when an app has several.

A **rule** places an app's new windows as they open. Windows that already exist are left alone:

```toml
[[rules]]
app = "com.apple.Terminal"
rect = "right-half"
```

Things macOS gets in the way of, which rook reports in the menu after applying a layout:

- Accessibility only lists windows on the current Space, so windows on another desktop are skipped.
- A window sent to a display that's showing a native-fullscreen app lands on that display's desktop, hidden behind the fullscreen app.

## Scripting

`rook://` URLs run commands from a terminal, Raycast, Shortcuts, etc. (`-g` keeps focus where it is):

```sh
open -g rook://layout/coding          # apply a layout
open -g rook://snap/left-half         # snap the focused window
open -g rook://save-layout/coding     # save current windows (won't overwrite an existing file)
open -g rook://reload                 # reload the config
```

To see what rook is doing: `log stream --predicate 'subsystem == "dev.maskedsyntax.rook"'`.

## Releasing

`make release` builds a universal app signed with Developer ID into `build/Rook-<version>.zip`. `make notarize` also notarizes and staples it, and prints the sha256 for `packaging/rook.rb` (the Homebrew cask). Before the first notarization, run `xcrun notarytool store-credentials rook --apple-id <you> --team-id <TEAM>` once.

After notarization, upload the ZIP to a GitHub release tagged `v<version>`, update the cask version and checksum, and copy `packaging/rook.rb` to `Casks/rook.rb` in your Homebrew tap. The checked-in cask is a template until its checksum is replaced and the release URL exists.

## Default shortcuts

These match Rectangle's defaults (`⌃⌥` = ctrl+alt):

| Shortcut | Action |
|---|---|
| ⌃⌥ ← / → / ↑ / ↓ | left / right / top / bottom half (press ← or → again to cycle ½ → ⅔ → ⅓) |
| ⌃⌥ U / I / J / K | top-left / top-right / bottom-left / bottom-right quarter |
| ⌃⌥ D / F / G | left / center / right third |
| ⌃⌥ E / T | left / right two-thirds |
| ⌃⌥ ↩ | maximize · ⌃⌥⇧ ↩ almost-maximize |
| ⌃⌥ C | center |
| ⌃⌥ = / - | larger / smaller |
| ⌃⌥ ⌫ | restore the frame from before rook touched the window |
| ⌃⌥⌘ ← / → | move to previous / next display |

## Layout

```
Sources/
  RookCore/   pure logic: geometry, snap math, window memory, shortcut parsing (unit-tested)
  RookAX/     Accessibility wrappers (AXWindow, WindowObserver) and display enumeration
  RookInput/  global hotkeys (Carbon)
  RookUI/     menu bar item, permission onboarding
  Rook/       app entry, WindowController (single dispatch point), DragController, LayoutRunner
```

Internally rook works in AX coordinates (top-left origin of the primary display). AppKit rects are converted once, in `Coordinates.flip`.

## What macOS doesn't allow (by design, rook won't try)

- Creating, switching or moving windows between Spaces (needs SIP disabled)
- Resizing native fullscreen windows
- Animating other apps' windows smoothly (placement is instant)
