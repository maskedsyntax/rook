# rook

A window manager for macOS with keyboard shortcuts, drag-to-snap, saved layouts, and rules for new windows. Runs in the menu bar. Configured in TOML.

## Install

Requires macOS 14 or later. To build, install Xcode with Swift 6 or later, then run:

```sh
git clone https://github.com/maskedsyntax/rook.git
cd rook
make install
```

This builds rook, copies it to `/Applications`, and launches it. Allow rook in **System Settings > Privacy & Security > Accessibility** when prompted.

To start rook automatically, choose **Launch at Login** from its menu. If macOS requires approval, rook opens Login Items settings.

The Homebrew cask is not ready for installation yet.

## Keyboard shortcuts

Shortcuts act on the focused window. The defaults follow Rectangle's bindings.

| Shortcut | Action |
| --- | --- |
| Ctrl + Option + Left / Right | Left / right half |
| Ctrl + Option + Up / Down | Top / bottom half |
| Ctrl + Option + U / I / J / K | Top-left / top-right / bottom-left / bottom-right quarter |
| Ctrl + Option + D / F / G | Left / center / right third |
| Ctrl + Option + E / T | Left / right two-thirds |
| Ctrl + Option + Return | Maximize |
| Ctrl + Option + Shift + Return | Almost maximize |
| Ctrl + Option + C | Center |
| Ctrl + Option + = / - | Grow / shrink |
| Ctrl + Option + Delete | Restore previous frame |
| Ctrl + Option + Command + Left / Right | Move to previous / next display |

Repeat left or right half to cycle through half, two-thirds, and one-third width.

## Configuration

Choose **Open Config** from the menu to edit `~/.config/rook/config.toml`. If `XDG_CONFIG_HOME` is set, rook uses `$XDG_CONFIG_HOME/rook/config.toml` instead.

rook creates a config with the defaults on first launch. Edits apply when you save. If the file has an error, rook keeps the last working config and shows the problem in its menu.

```toml
gaps = { outer = 8, inner = 8 }
almost_maximize = 0.9
resize_step = 40
```

Gaps and resize steps are in points. `almost_maximize` is the fraction of the screen to fill. Use `gaps = 8` to set both gaps to the same value.

The `[keys]` table replaces all default bindings. Edit the generated table to keep the shortcuts you want, or start with a smaller set:

```toml
[keys]
"ctrl+alt+left" = "left-half"
"ctrl+alt+right" = "right-half"
"ctrl+alt+return" = "maximize"
"ctrl+alt+delete" = "restore"
"ctrl+alt+r" = "reload-config"
"ctrl+alt+1" = "layout:coding"
```

Use `"none"` as the action to disable a binding. Layout shortcuts need a layout with the matching name.

### Mouse controls

Mouse controls are off by default. To enable edge snapping and modifier-drag:

```toml
[drag]
enabled = true
bottom_edge = "thirds"
restore_size = true
modifier = "ctrl+cmd"
```

Drag a window by its title bar to a screen edge, then release when the preview appears:

| Edge | Placement |
| --- | --- |
| Left / right | Half |
| Corner | Quarter |
| Top | Maximize |
| Bottom | Left, center, or right third, depending on cursor position |

Shared edges between displays do not trigger snapping. Dragging a snapped window away restores its earlier size.

Hold the configured modifier and drag anywhere in a window to move it. Right-drag resizes from the nearest corner. Set `modifier = "none"` to disable this independently of edge snapping. `bottom_edge` also accepts `"half"` or `"none"`.

On macOS 15 or later, turn off macOS edge tiling if you use rook's edge snapping. rook shows a link to that setting in its menu when it detects a conflict.

### Saved layouts

Arrange your windows, then choose **Layouts > Save Current Layout…**. Saved layouts live in `~/.config/rook/layouts/` and appear in the menu. You can also define them in `config.toml`:

```toml
[[layouts.coding]]
app = "com.microsoft.VSCode"
rect = "left-two-thirds"
display = "main"

[[layouts.coding]]
app = "com.mitchellh.ghostty"
rect = "right-third"
```

Applying a layout launches missing apps, waits for their windows, and brings the first app to the front. It does not create extra windows in apps that are already running. Set `launch = false` on an entry to skip launching that app.

`app` is the app's bundle identifier. Add `title = "Inbox"` to match a window by part of its title, ignoring case. `rect` accepts a placement action such as `"left-half"`, or screen fractions such as `{ x = 0, y = 0, w = 0.6, h = 1 }`.

`display` accepts `"main"`, `"secondary"`, a display name, or a number starting at `1`, ordered left to right. If the display is disconnected, rook uses the main display.

### Window rules

Rules place new windows as they open. Existing windows are left where they are.

```toml
[[rules]]
app = "com.apple.Terminal"
rect = "right-half"
```

Rules accept the same `title`, `rect`, and `display` options as layout entries. Without `display`, the window stays on the display where it opened.

## Scripting

Use `rook://` URLs from a terminal, Shortcuts, or Raycast:

```sh
open -g rook://layout/coding
open -g rook://snap/left-half
open -g rook://save-layout/coding
open -g rook://reload
```

`save-layout` saves the current arrangement and refuses to overwrite an existing file. `-g` opens the URL in the background; applying a layout still brings its first app to the front.

## Limitations

- rook cannot create or switch Spaces, or move windows between them. Layouts only see windows on the current Space.
- Native fullscreen windows cannot be resized. A window placed on a display with a fullscreen app may be hidden behind it on that display's desktop.
- Some apps enforce minimum window sizes or resize in fixed increments, so exact placement is not always possible.

If a layout cannot place an app, check rook's menu for the reason. For logs:

```sh
log stream --predicate 'subsystem == "dev.maskedsyntax.rook"'
```

## Building

Use `make run` to build and launch without installing, and `make test` to run the tests.

Local builds use the first Apple Development signing identity in your keychain, or ad-hoc signing if none is available. Override it with `SIGN_IDENTITY="…"`. Ad-hoc builds may need Accessibility permission again after rebuilding.

`make release` builds a universal Intel and Apple Silicon ZIP signed with Developer ID. `make notarize` submits it to Apple, staples the ticket, and prints the checksum for the Homebrew cask. Before the first notarization, store credentials locally:

```sh
xcrun notarytool store-credentials rook --apple-id <you> --team-id <TEAM>
```
