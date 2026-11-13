import Foundation
import NodchCore

check(Nodch.name == "nodch", "package links")
check(IslandStore().state == .offline(reason: "Not connected"), "store starts offline")
await ClientChecks.run()
await IslandChecks.run()

print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
