import Foundation
import NodchCore

var failures = 0
@MainActor func check(_ condition: Bool, _ name: String) {
    print(condition ? "ok   \(name)" : "FAIL \(name)")
    if !condition { failures += 1 }
}

check(Nodch.name == "nodch", "package links")

print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
