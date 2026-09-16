import Foundation

let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
let lifecycle = PrivilegedHelperLifecycle()
let delegate = PrivilegedHelperListener(lifecycle: lifecycle)
listener.delegate = delegate
listener.resume()
dispatchMain()
