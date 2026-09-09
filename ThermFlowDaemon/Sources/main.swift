import Foundation

// The listener validates the caller before DaemonDelegate considers the
// console-user boundary. Release/Beta helpers accept only the notarized
// Developer ID app; Debug accepts the same bundle/team signed for development.
#if DEBUG
private let authorizedClientRequirement = #"identifier "com.slmcamp.CoolCumber" and anchor apple generic and certificate leaf[subject.OU] = "BSKR6CQ765""#
#else
private let authorizedClientRequirement = #"identifier "com.slmcamp.CoolCumber" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "BSKR6CQ765""#
#endif

let delegate = DaemonDelegate()
let listener = NSXPCListener(machServiceName: "com.slmcamp.CoolCumber.helper.v2")
listener.setConnectionCodeSigningRequirement(authorizedClientRequirement)
listener.delegate = delegate
listener.activate()

RunLoop.main.run()
