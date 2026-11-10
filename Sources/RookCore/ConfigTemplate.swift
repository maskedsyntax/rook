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
    # Drag a window to a screen edge to snap it: left/right edge = half,
    # corners = quarter, top edge = maximize. A preview shows where it'll land.
    enabled = true
    # Bottom edge: "thirds" (left/center/right by cursor position), "half", or "none".
    bottom_edge = "thirds"
    # Dragging a snapped window away restores the size it had before snapping.
    restore_size = true
    # Hold these and drag anywhere inside a window to move it; right-drag to
    # resize from the nearest corner. "none" to disable.
    modifier = "ctrl+cmd"

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

    """#
}
