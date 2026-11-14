import Foundation
import NodchCore

extension IslandChecks {
    /// Copies received from file promises are deleted after upload; the person's own files never are.
    static func promiseDrops() {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("nodch-checks-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: base) }
        let root = base.appendingPathComponent("Drops", isDirectory: true)
        let drop = root.appendingPathComponent("A", isDirectory: true)
        let finder = base.appendingPathComponent("Desktop", isDirectory: true)
        try? manager.createDirectory(at: drop, withIntermediateDirectories: true)
        try? manager.createDirectory(at: finder, withIntermediateDirectories: true)
        let mail = drop.appendingPathComponent("mail.eml"), photo = drop.appendingPathComponent("photo.heic")
        let own = finder.appendingPathComponent("q4.pdf")
        for file in [mail, photo, own] { manager.createFile(atPath: file.path, contents: Data("x".utf8)) }

        check(PromiseDrops.isCopy(mail, root: root) && !PromiseDrops.isCopy(own, root: root)
              && !PromiseDrops.isCopy(drop, root: root) && !PromiseDrops.isCopy(root, root: root),
              "drops: only files inside a drop's folder count as nodch's copies")
        PromiseDrops.discard(own, root: root)
        PromiseDrops.discard(mail, root: root)
        check(manager.fileExists(atPath: own.path) && !manager.fileExists(atPath: mail.path)
              && manager.fileExists(atPath: photo.path), "drops: an uploaded copy is deleted, its siblings and the person's file stay")
        PromiseDrops.discard(photo, root: root)
        check(!manager.fileExists(atPath: drop.path) && manager.fileExists(atPath: root.path), "drops: the empty drop folder goes too")
        PromiseDrops.clearAll(root: root)
        check(!manager.fileExists(atPath: root.path) && manager.fileExists(atPath: own.path), "drops: launch clears every copy left over")
    }
}
