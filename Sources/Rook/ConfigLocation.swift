import Foundation
import RookCore

enum ConfigLocation {
    /// `$XDG_CONFIG_HOME/rook/config.toml`, else `~/.config/rook/config.toml`.
    static var url: URL {
        let base: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        }
        return base.appendingPathComponent("rook/config.toml")
    }

    /// Writes the commented template if there's no config yet. Never overwrites.
    static func createIfMissing() throws {
        let url = Self.url
        // fileExists follows symlinks; a dangling symlink is left alone too.
        let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
        guard !isLink, !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Config.template.write(to: url, atomically: true, encoding: .utf8)
    }
}
