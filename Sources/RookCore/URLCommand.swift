import Foundation

/// `rook://` URLs, for scripts, Raycast, Shortcuts or a terminal:
///
///     open -g rook://layout/coding        apply a layout
///     open -g rook://snap/left-half       snap the focused window
///     open -g rook://save-layout/coding   save the current windows (never overwrites)
///     open -g rook://reload               reload the config
public enum URLCommand: Equatable, Sendable {
    case run(Command)
    case saveLayout(String)

    public static let scheme = "rook"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let verb = url.host?.lowercased() else { return nil }
        let argument = url.pathComponents.filter { $0 != "/" }.joined(separator: "/")

        switch verb {
        case "reload", "reload-config":
            self = .run(.reloadConfig)
        case "layout":
            guard !argument.isEmpty else { return nil }
            self = .run(.layout(argument))
        case "snap":
            guard let action = SnapAction(rawValue: argument) else { return nil }
            self = .run(.snap(action))
        case "save-layout":
            guard let name = LayoutCapture.sanitizedName(argument) else { return nil }
            self = .saveLayout(name)
        default:
            return nil
        }
    }
}
