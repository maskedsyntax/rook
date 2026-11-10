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

    /// Saved layouts live next to the config: `~/.config/rook/layouts/<name>.toml`.
    static var layoutsDirectory: URL {
        url.deletingLastPathComponent().appendingPathComponent("layouts", isDirectory: true)
    }

    static func layoutFiles() -> [LayoutFile] {
        ConfigWatcher.tomlFiles(in: layoutsDirectory).compactMap { file in
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            return LayoutFile(
                name: file.deletingPathExtension().lastPathComponent,
                path: "layouts/\(file.lastPathComponent)",
                source: source
            )
        }
    }

    /// Writes the commented template if there's no config yet. Never overwrites.
    static func createIfMissing() throws {
        try FileManager.default.createDirectory(at: layoutsDirectory, withIntermediateDirectories: true)
        let url = Self.url
        // fileExists follows symlinks; a dangling symlink is left alone too.
        let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
        guard !isLink, !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Config.template.write(to: url, atomically: true, encoding: .utf8)
    }
}
