# rook

A fast, native window manager for macOS that sits between Rectangle and a tiling WM: keyboard snapping, drag-to-snap zones, and saved layouts, with no tiling tree and no SIP changes.

## Status

- [x] Phase 0: app scaffold, menu bar item, Accessibility onboarding, stable signing
- [x] Phase 1: keyboard snapping (halves, thirds, quarters, maximize, center, grow/shrink), size cycling, restore, move between displays
- [ ] Phase 2: `~/.config/rook/config.toml` with live reload
- [ ] Phase 3: drag-to-snap overlay, modifier-drag move/resize
- [ ] Phase 4: named layouts and auto-placement rules
- [ ] Phase 5: launch at login, app-compat pass, Homebrew cask

## Build and run

```sh
make run      # build, bundle into build/Rook.app, sign, launch
make test     # unit tests for the pure core
make install  # copy to /Applications
```

On first launch rook asks for Accessibility access and starts working as soon as you turn it on. The Makefile signs with your first "Apple Development" identity so the grant survives rebuilds. Override with `SIGN_IDENTITY=...`.

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
