// Adapted from Pippa: app/Sources/Pippa/App/IslandSnapshots.swift
import AppKit
import NodchCore

/// `Nodch --snapshot <folder>`: renders the island in each state at a synthetic notch (a 185 × 32 pt housing) and as
/// the pill below a menu bar, in front of a neutral desktop, at 2x. Uses the real views, geometry and wing measures
/// with made-up states; nothing talks to Nod.
@MainActor
enum IslandSnapshots {
    struct Scene {
        var name: String
        var state: IslandState
        var open = false
        var prompt: PromptDraft?
        var hovering = false
        var level: Float = 0
        var drop = IslandDropZone.none
    }

    static let scenes: [Scene] = [
        Scene(name: "offline", state: IslandSamples.offline),
        Scene(name: "offline-hover", state: IslandSamples.offline, hovering: true),
        Scene(name: "offline-open", state: IslandSamples.offline, open: true),
        Scene(name: "rest", state: .rest),
        Scene(name: "rest-hover", state: .rest, hovering: true),
        Scene(name: "working", state: IslandSamples.working()),
        Scene(name: "working-open", state: IslandSamples.working()),
        Scene(name: "needs-you", state: .needsYou(IslandSamples.email, more: 0), open: true),
        Scene(name: "needs-you-compact", state: .needsYou(IslandSamples.email, more: 2)),
        Scene(name: "needs-you-long", state: .needsYou(IslandSamples.longPost, more: 2), open: true),
        Scene(name: "needs-you-tall", state: .needsYou(IslandSamples.tall, more: 0), open: true),
        Scene(name: "needs-you-cut", state: .needsYou(IslandSamples.cutNote, more: 2), open: true),
        Scene(name: "done", state: IslandSamples.done),
        Scene(name: "failed", state: IslandSamples.failed),
        Scene(name: "failed-open", state: IslandSamples.failed, open: true),
        Scene(name: "prompt", state: .rest, open: true, prompt: PromptDraft()),
        Scene(name: "prompt-error", state: IslandSamples.working(), open: true, prompt: IslandSamples.failedSend),
        Scene(name: "prompt-listening", state: .rest, open: true, prompt: IslandSamples.listening, level: 0.6),
        Scene(name: "prompt-voice-unavailable", state: .rest, open: true, prompt: IslandSamples.voiceDenied),
        Scene(name: "prompt-attachments", state: .rest, open: true, prompt: IslandSamples.attachments),
        Scene(name: "drop-near", state: .rest, drop: .near),
        Scene(name: "drop-over", state: IslandSamples.working(), drop: .over),
        Scene(name: "drop-open", state: .rest, open: true, prompt: IslandSamples.attachments, drop: .over),
    ].map { scene in
        var scene = scene
        if scene.name == "working-open" { scene.open = true }
        return scene
    }

    static func run(into folder: URL) async -> Int32 {
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
            FileHandle.standardError.write(Data("nodch: cannot create \(folder.path): \(error.localizedDescription)\n".utf8))
            return 1
        }
        var written = 0
        for scene in scenes {
            for notch in [true, false] {
                let file = folder.appendingPathComponent("\(scene.name)-\(notch ? "notch" : "pill").png")
                if await render(scene, notch: notch, to: file) { written += 1 } else {
                    FileHandle.standardError.write(Data("nodch: could not write \(file.lastPathComponent)\n".utf8))
                }
            }
        }
        print("\(written) snapshots in \(folder.path)")
        return written == scenes.count * 2 ? 0 : 1
    }

    private static func render(_ scene: Scene, notch: Bool, to file: URL) async -> Bool {
        let size = NSSize(width: 900, height: scene.open ? 560 : 110)
        let barHeight: CGFloat = notch ? 32 : 24
        let canvas = Canvas(frame: NSRect(origin: .zero, size: size))
        canvas.barHeight = barHeight
        let placement: IslandPlacement
        if notch {
            let housing = CGRect(x: ((size.width - 185) / 2).rounded(), y: size.height - barHeight, width: 185, height: barHeight)
            canvas.housing = housing
            placement = .notch(housing: housing, screen: canvas.bounds)
        } else {
            let visible = CGRect(x: 0, y: 0, width: size.width, height: size.height - barHeight)
            placement = IslandGeometry.placement(screen: canvas.bounds, visible: visible, leftArea: nil, rightArea: nil, topInset: 0)
        }
        let window = SnapshotWindow(contentRect: canvas.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = canvas

        let store = IslandStore(state: scene.state)
        let model = IslandModel(store: store)
        model.hovering = scene.hovering
        model.isOpen = scene.open
        if let prompt = scene.prompt {
            model.showsPrompt = true
            model.draft = prompt
        }
        model.voiceLevel = scene.level
        model.dropZone = scene.drop
        var height: CGFloat = 200
        var view: IslandView?
        func layout() {
            guard let view else { return }
            let compact = IslandController.compact(model, placement)
            IslandController.apply(compact, to: model, placement: placement)
            let rect = compact.map { IslandGeometry.compact(placement, leading: $0.leading, trailing: $0.trailing) } ?? IslandGeometry.rest(placement)
            let openRect = IslandGeometry.open(placement, contentHeight: ceil(height))
            let frame = IslandGeometry.windowFrame(placement, covering: [rect] + (scene.open ? [openRect] : []))
            view.frame = frame
            view.show(placement, compactShape: rect, compactTarget: rect, compactAlpha: compact == nil ? 0 : 1,
                      open: scene.open ? 1 : 0, openRect: openRect, origin: frame.origin)
        }
        view = IslandView(model: model) { measured in
            guard abs(measured - height) > 0.5 else { return }
            height = measured
            layout()
        }
        if let view { canvas.addSubview(view) }
        layout()
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderFrontRegardless()
        // Let SwiftUI lay out and report the card's height before drawing.
        for _ in 0..<7 { try? await Task.sleep(for: .milliseconds(120)); canvas.layoutSubtreeIfNeeded(); layout() }
        // Twice the points, like a Retina display.
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        rep.size = size
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        window.orderOut(nil)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: file) } catch { return false }
        return true
    }

    /// A desktop with a menu bar and, for a MacBook, the camera housing.
    private final class Canvas: NSView {
        var barHeight: CGFloat = 24
        var housing: CGRect?
        override func draw(_ dirtyRect: NSRect) {
            NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.20, blue: 0.35, alpha: 1),
                       ending: NSColor(srgbRed: 0.34, green: 0.40, blue: 0.53, alpha: 1))?.draw(in: bounds, angle: -65)
            NSColor.white.withAlphaComponent(0.06).setFill()
            NSRect(x: 0, y: bounds.maxY - barHeight, width: bounds.width, height: barHeight).fill()
            // A few menu bar words, so the island is judged against a real bar.
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                             .foregroundColor: NSColor.white.withAlphaComponent(0.9)]
            ("Finder" as NSString).draw(at: NSPoint(x: 40, y: bounds.maxY - barHeight + (barHeight - 16) / 2), withAttributes: attributes)
            ("Fri 13 Nov  10:42" as NSString).draw(at: NSPoint(x: bounds.maxX - 140, y: bounds.maxY - barHeight + (barHeight - 16) / 2),
                                                   withAttributes: attributes)
            guard let housing else { return }
            NSColor.black.setFill()
            let path = NSBezierPath(roundedRect: housing, xRadius: 10, yRadius: 10)
            path.appendRect(NSRect(x: housing.minX, y: housing.midY, width: housing.width, height: housing.height / 2))
            path.fill()
        }
    }

    private final class SnapshotWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }
}
