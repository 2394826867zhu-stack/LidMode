import Foundation

let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
let delegate = PrivilegedHelperListener()
listener.delegate = delegate
listener.resume()
dispatchMain()
