/// Built-in shortcuts (Rectangle-compatible, so muscle memory carries over).
/// In phase 2 these become the commented template written to config.toml.
public enum DefaultBindings {
    public static let all: [(shortcut: String, action: SnapAction)] = [
        ("ctrl+alt+left", .leftHalf),
        ("ctrl+alt+right", .rightHalf),
        ("ctrl+alt+up", .topHalf),
        ("ctrl+alt+down", .bottomHalf),

        ("ctrl+alt+u", .topLeft),
        ("ctrl+alt+i", .topRight),
        ("ctrl+alt+j", .bottomLeft),
        ("ctrl+alt+k", .bottomRight),

        ("ctrl+alt+d", .leftThird),
        ("ctrl+alt+f", .centerThird),
        ("ctrl+alt+g", .rightThird),
        ("ctrl+alt+e", .leftTwoThirds),
        ("ctrl+alt+t", .rightTwoThirds),

        ("ctrl+alt+return", .maximize),
        ("ctrl+alt+shift+return", .almostMaximize),
        ("ctrl+alt+c", .center),
        ("ctrl+alt+equal", .larger),
        ("ctrl+alt+minus", .smaller),
        ("ctrl+alt+delete", .restore),

        ("ctrl+alt+cmd+right", .nextDisplay),
        ("ctrl+alt+cmd+left", .previousDisplay),
    ]
}
