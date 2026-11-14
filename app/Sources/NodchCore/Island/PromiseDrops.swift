import Foundation

/// File promises (a mail from Mail, a photo from Photos) are written into a fresh folder per drop under
/// ~/Library/Caches/nodch/Drops. Those copies exist only to be uploaded, so nodch deletes them afterwards; a file
/// dragged from Finder is the person's own and is never touched.
public enum PromiseDrops {
    public static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nodch/Drops", isDirectory: true)
    }

    /// A file directly inside one drop's folder under `root`.
    public static func isCopy(_ file: URL, root: URL = root) -> Bool {
        let file = file.standardizedFileURL
        guard file.pathComponents.count > 2 else { return false }
        return file.deletingLastPathComponent().deletingLastPathComponent().path == root.standardizedFileURL.path
    }

    /// After its upload ended, either way: deletes one copy, and its drop's folder once that is empty.
    public static func discard(_ file: URL, root: URL = root) {
        guard isCopy(file, root: root) else { return }
        let manager = FileManager.default
        try? manager.removeItem(at: file)
        let folder = file.deletingLastPathComponent()
        if (try? manager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true { try? manager.removeItem(at: folder) }
    }

    /// At launch: whatever an earlier run left was uploaded, or failed, long ago.
    public static func clearAll(root: URL = root) { try? FileManager.default.removeItem(at: root) }
}
