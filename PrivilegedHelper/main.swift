import Foundation
import CleanCore

// Entry point for the `com.nextlabs.sosmac.privilegedhelper` daemon,
// registered via `SMAppService.daemon(plistName:)` (never the deprecated
// `SMJobBless`). Binds to the Mach service name declared in this daemon's
// own bundled launchd plist and runs for the lifetime of the process —
// launchd starts/stops it, this loop just keeps the process alive to serve
// connections.
let delegate = HelperXPCListenerDelegate()
let listener = NSXPCListener(machServiceName: PrivilegedHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

RunLoop.current.run()
