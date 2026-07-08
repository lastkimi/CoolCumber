import Foundation

let delegate = DaemonDelegate()
let listener = NSXPCListener(machServiceName: "com.coolcumber.helper")
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
