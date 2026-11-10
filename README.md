# rook

A fast, native window manager for macOS that sits between Rectangle and a tiling WM: keyboard snapping, drag-to-snap zones, and saved layouts, with no tiling tree and no SIP changes.

## Status

- [x] Phase 0: app scaffold, menu bar item, Accessibility onboarding, stable signing
- [x] Phase 1: keyboard snapping (halves, thirds, quarters, maximize, center, grow/shrink), size cycling, restore, move between displays
- [x] Phase 2: `~/.config/rook/config.toml` with live reload
- [x] Phase 3: drag-to-snap overlay, modifier-drag move/resize
- [ ] Phase 4: named layouts and auto-placement rules
- [ ] Phase 5: launch at login, app-compat pass, Homebrew cask

## Build and run

```sh
make run      # build, bundle into build/Rook.app, sign, launch
make test     # unit tests for the pure core
make install  # copy to /Applications
```

On first launch rook asks for Accessibility access and starts working as soon as you turn it on. The Makefile signs with your first "Apple Development" identity so the grant survives rebuilds. Override with `SIGN_IDENTITY=...`.

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

[drag]
enabled = true                     # snap by dragging to screen edges
bottom_edge = "thirds"             # "thirds" | "half" | "none"
restore_size = true                # dragging a snapped window away restores its size
modifier = "ctrl+cmd"              # hold + drag to move, + right-drag to resize; "none" to disable
```

## Mouse

- **Drag to snap:** drag a window by its title bar to a screen edge. Left/right = half, corners = quarter, top = maximize, bottom = thirds by cursor position. A preview shows where it will land; let go to snap it. Edges shared with another monitor are ignored, so moving a window between monitors doesn't trigger a snap.
- **Unsnap:** dragging a snapped window away gives it back its earlier size, still under the cursor.
- **Modifier-drag:** hold `ctrl+cmd` and drag anywhere in a window to move it, or right-drag to resize from the nearest corner. Screen edges snap here too.
- macOS 15+ has its own edge tiling. The two fight each other, so rook notes it in the menu with a link to the setting.

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
  RookAX/     Accessibility wrappers (AXWindow) and display enumeration
  RookInput/  global hotkeys (Carbon)
  RookUI/     menu bar item, permission onboarding
  Rook/       app entry, WindowController (single dispatch point for all actions)
```

Internally rook works in AX coordinates (top-left origin of the primary display). AppKit rects are converted once, in `Coordinates.flip`.

## What macOS doesn't allow (by design, rook won't try)

- Creating, switching or moving windows between Spaces (needs SIP disabled)
- Resizing native fullscreen windows
- Animating other apps' windows smoothly (placement is instant)
