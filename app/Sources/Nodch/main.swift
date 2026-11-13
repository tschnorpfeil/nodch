import AppKit
import NodchCore

let app = NSApplication.shared
let arguments = CommandLine.arguments

// `Nodch --snapshot <folder>`: every island state at a synthetic notch and below a menu bar, as PNGs, then exit.
if let index = arguments.firstIndex(of: "--snapshot") {
    guard arguments.count > index + 1 else {
        FileHandle.standardError.write(Data("usage: Nodch --snapshot <folder>\n".utf8))
        exit(2)
    }
    let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    app.setActivationPolicy(.accessory)
    Task { @MainActor in exit(await IslandSnapshots.run(into: folder)) }
    app.run()
}

// `Nodch --demo`: cycles through every state with fake actions that only log.
setvbuf(stdout, nil, _IOLBF, 0)
let delegate = AppDelegate(demo: arguments.contains("--demo"))
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
