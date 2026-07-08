import Foundation

class DaemonDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Enforce code signing requirements for security
        // In a real production app, you MUST verify the code signing requirement here.
        // For development, we allow the connection.
        
        newConnection.exportedInterface = NSXPCInterface(with: CoolCumberDaemonProtocol.self)
        newConnection.exportedObject = DaemonService()
        newConnection.resume()
        return true
    }
}
