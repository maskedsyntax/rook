import Foundation

/// Calls `onChange` when the config file's contents change.
///
/// Editors save in different ways, and each needs a different signal:
/// - in-place write (vim with backupcopy=yes, nano): the file itself changes
/// - atomic save (VS Code, Zed, most GUI editors): a new file is renamed over
///   the old one, so the directory changes and the old file handle goes stale
/// - dotfile managers (stow, chezmoi symlinks): edits happen to the symlink's
///   target in another directory
///
/// So we watch the file, its directory, and (if it's a symlink) the resolved
/// file and directory, plus any extra directories (saved layouts) and the
/// `.toml` files in them. Every event re-arms the watchers, because the watched
/// inode may have been replaced. Bursts are debounced, and a reload only fires
/// if the bytes actually changed.
@MainActor
final class ConfigWatcher {
    let url: URL
    let directories: [URL]
    var onChange: () -> Void = {}

    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private var lastContents: Data?

    init(url: URL, directories: [URL] = []) {
        self.url = url
        self.directories = directories
    }

    func start() {
        lastContents = fingerprint()
        arm()
    }

    /// Records what's on disk now, so the next event isn't treated as a change.
    func markCurrent() {
        lastContents = fingerprint()
    }

    /// The `.toml` files in the watched directories, sorted.
    nonisolated static func tomlFiles(in directory: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "toml" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Everything that affects the config, in one comparable blob. nil if the
    /// main file is missing (mid-save).
    private func fingerprint() -> Data? {
        guard var data = try? Data(contentsOf: url) else { return nil }
        for dir in directories {
            for file in Self.tomlFiles(in: dir) {
                data.append(Data(file.lastPathComponent.utf8))
                data.append(0)
                data.append((try? Data(contentsOf: file)) ?? Data())
                data.append(0)
            }
        }
        return data
    }

    private func arm() {
        for source in sources { source.cancel() }
        sources.removeAll()

        let resolved = url.resolvingSymlinksInPath()
        var paths: Set<String> = [
            url.path,
            url.deletingLastPathComponent().path,
            resolved.path,
            resolved.deletingLastPathComponent().path,
        ]
        for dir in directories {
            paths.insert(dir.path)
            for file in Self.tomlFiles(in: dir) {
                paths.insert(file.path)
                paths.insert(file.resolvingSymlinksInPath().path)
            }
        }
        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .delete, .rename, .attrib],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleCheck() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    private func scheduleCheck() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: item)
    }

    private func check() {
        arm()
        let contents = fingerprint()
        // Mid-save the file can briefly be missing; wait for the next event.
        guard let contents, contents != lastContents else { return }
        lastContents = contents
        onChange()
    }
}
