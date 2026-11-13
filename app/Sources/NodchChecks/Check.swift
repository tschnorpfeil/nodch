import Foundation

@MainActor var failures = 0

@MainActor func check(_ condition: Bool, _ name: String) {
    print(condition ? "ok   \(name)" : "FAIL \(name)")
    if !condition { failures += 1 }
}
