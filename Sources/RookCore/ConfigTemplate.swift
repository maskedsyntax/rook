extension Config {
    /// Written to the config path on first launch. A test checks that it
    /// parses to exactly `Config.default`, so the two can't drift apart.
    public static let template = #"""
    # rook config. Changes apply as soon as you save.
    # If the file has an error, rook keeps the last working config and shows
    # the problem in the menu bar.

    # Space around and between snapped windows, in points.
    # A single number sets both: gaps = 8
    gaps = { outer = 8, inner = 8 }

    # Fraction of the screen that "almost-maximize" covers.
    almost_maximize = 0.9

    # Points added/removed on each side by "larger" / "smaller".
    resize_step = 40

    [drag]
    # Mouse features. Both are off by default; with both off rook never
    # watches the mouse at all.
    #
    # Drag a window to a screen edge to snap it: left/right edge = half,
    # corners = quarter, top edge = maximize. A preview shows where it'll land.
    enabled = false
    # Bottom edge: "thirds" (left/center/right by cursor position), "half", or "none".
    bottom_edge = "thirds"
    # Dragging a snapped window away restores the size it had before snapping.
    restore_size = true
    # Hold these and drag anywhere inside a window to move it; right-drag to
    # resize from the nearest corner. e.g. "ctrl+cmd", or "none" to disable.
    modifier = "none"

    # Shortcuts. This table replaces the built-in defaults entirely:
    # delete a line to drop that shortcut, or set it to "none".
    #
    # Modifiers: ctrl, alt (opt), shift, cmd
    # Keys: a-z, 0-9, left/right/up/down, return, space, tab, delete, escape,
    #       f1-f12, minus, equal, [ ] ; ' , . / \ `
    #
    # Actions:
    #   left-half right-half top-half bottom-half
    #   left-third center-third right-third left-two-thirds right-two-thirds
    #   top-left top-right bottom-left bottom-right
    #   maximize almost-maximize center larger smaller restore
    #   next-display previous-display reload-config
    #   layout:<name>   (apply a saved layout, see the end of this file)
    #
    # Pressing left-half / right-half again cycles ½ → ⅔ → ⅓.
    [keys]
    "ctrl+alt+left" = "left-half"
    "ctrl+alt+right" = "right-half"
    "ctrl+alt+up" = "top-half"
    "ctrl+alt+down" = "bottom-half"

    "ctrl+alt+u" = "top-left"
    "ctrl+alt+i" = "top-right"
    "ctrl+alt+j" = "bottom-left"
    "ctrl+alt+k" = "bottom-right"

    "ctrl+alt+d" = "left-third"
    "ctrl+alt+f" = "center-third"
    "ctrl+alt+g" = "right-third"
    "ctrl+alt+e" = "left-two-thirds"
    "ctrl+alt+t" = "right-two-thirds"

    "ctrl+alt+return" = "maximize"
    "ctrl+alt+shift+return" = "almost-maximize"
    "ctrl+alt+c" = "center"
    "ctrl+alt+equal" = "larger"
    "ctrl+alt+minus" = "smaller"
    "ctrl+alt+delete" = "restore"

    "ctrl+alt+cmd+right" = "next-display"
    "ctrl+alt+cmd+left" = "previous-display"
    # "ctrl+alt+1" = "layout:coding"

    # Layouts: named arrangements of apps you apply with a shortcut or from the
    # menu (Layouts ▸). Easiest: arrange your windows, then Layouts ▸ Save
    # Current Layout…, which writes ~/.config/rook/layouts/<name>.toml.
    # Or define them here, one [[layouts.<name>]] block per window:
    #
    # [[layouts.coding]]
    # app = "com.microsoft.VSCode"     # bundle id: osascript -e 'id of app "Visual Studio Code"'
    # rect = "left-two-thirds"         # any placement action, or { x = 0, y = 0, w = 0.6, h = 1 }
    # display = "main"                 # "main", "secondary", 1/2/3 (left to right), or a display name
    #
    # [[layouts.coding]]
    # app = "com.mitchellh.ghostty"
    # rect = "right-third"
    # launch = true                    # open the app if it isn't running (default)
    #
    # A title picks one of an app's windows: title = "Inbox"

    # Rules: place new windows of an app automatically when they open.
    #
    # [[rules]]
    # app = "com.apple.Terminal"
    # rect = "right-half"
    # display = "secondary"            # optional; default is wherever the window opened

    """#
}
