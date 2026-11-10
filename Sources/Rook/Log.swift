import os

/// `log stream --predicate 'subsystem == "dev.maskedsyntax.rook"'` to watch.
enum Log {
    static let app = Logger(subsystem: "dev.maskedsyntax.rook", category: "app")
    static let layout = Logger(subsystem: "dev.maskedsyntax.rook", category: "layout")
}
