import Foundation

// This is the designated requirement of the notarized Developer ID build of
// com.slmcamp.CoolCumber. Keep this in sync with the release signing identity.
private let authorizedClientRequirement = #"identifier "com.slmcamp.CoolCumber" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "BSKR6CQ765""#

let delegate = DaemonDelegate()
let listener = NSXPCListener(machServiceName: "com.coolcumber.helper")
listener.setConnectionCodeSigningRequirement(authorizedClientRequirement)
listener.delegate = delegate
listener.activate()

RunLoop.main.run()
