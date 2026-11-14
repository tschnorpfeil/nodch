// Adapted from Pippa: app/Sources/Pippa/App/DropReader.swift
import AppKit
import NodchCore

/// Reads files dragged onto the island: file URLs, and file promises (a mail from Mail, a photo from Photos), which
/// the other app writes into a fresh folder in nodch's caches first.
enum DropReader {
    static let types: [NSPasteboard.PasteboardType] =
        [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    static func carriesFiles(_ board: NSPasteboard) -> Bool { board.availableType(from: types) != nil }

    @MainActor
    static func read(_ board: NSPasteboard, completion: @escaping @MainActor ([DroppedFile]) -> Void) {
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let files = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !files.isEmpty { return completion(files.map(describe)) }
        }
        guard let receivers = board.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
              !receivers.isEmpty, let folder = try? freshFolder() else { return completion([]) }
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        // A promise may stand for several files; their names are known only after receiving starts. Hold the
        // callbacks until every receiver has said how many it brings.
        queue.isSuspended = true
        let collector = PromiseCollector()
        let reader = promiseReader(collector) { urls in completion(urls.map(describe)) }
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue, reader: reader)
            collector.expect(max(1, receiver.fileNames.count))
        }
        queue.isSuspended = false
    }

    static func describe(_ url: URL) -> DroppedFile {
        let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return DroppedFile(url: url, isDirectory: directory)
    }

    /// A fresh folder per drop in ~/Library/Caches/nodch/Drops, so nothing collides. `PromiseDrops` deletes it again.
    private static func freshFolder() throws -> URL {
        let url = PromiseDrops.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// AppKit calls the reader on `queue`, not on the main thread: built outside the main actor, or Swift 6 traps.
    private nonisolated static func promiseReader(_ collector: PromiseCollector,
                                                  completion: @escaping @MainActor ([URL]) -> Void) -> @Sendable (URL, Error?) -> Void {
        { url, error in
            collector.add(error == nil ? url : nil) { urls in
                DispatchQueue.main.async { MainActor.assumeIsolated { completion(urls) } }
            }
        }
    }
}

/// Collects the files of several promises until all have arrived.
private final class PromiseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining = 0
    private var urls: [URL] = []

    func expect(_ count: Int) { lock.withLock { remaining += count } }

    func add(_ url: URL?, whenDone: ([URL]) -> Void) {
        let finished: [URL]? = lock.withLock {
            if let url { urls.append(url) }
            remaining -= 1
            return remaining == 0 ? urls : nil
        }
        if let finished { whenDone(finished) }
    }
}
