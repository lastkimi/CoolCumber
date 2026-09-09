import Foundation
import OSLog

final class DaemonDelegate: NSObject, NSXPCListenerDelegate {
    private let logger = Logger(subsystem: "com.slmcamp.CoolCumber.helper.v2", category: "xpc")

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard let consoleUID = activeConsoleUserUID() else {
            logger.error("Rejected XPC connection because no non-root console user is active")
            return false
        }

        guard newConnection.effectiveUserIdentifier == consoleUID else {
            logger.error(
                "Rejected XPC connection from uid \(newConnection.effectiveUserIdentifier, privacy: .public); active console uid is \(consoleUID, privacy: .public)"
            )
            return false
        }

        let service = DaemonService()
        newConnection.exportedInterface = NSXPCInterface(with: CoolCumberMonitorV2Protocol.self)
        newConnection.exportedObject = service
        newConnection.invalidationHandler = { [logger] in
            service.connectionInvalidated()
            logger.info("Authorized XPC connection invalidated")
        }
        newConnection.activate()
        logger.info(
            "Accepted authorized XPC connection from pid \(newConnection.processIdentifier, privacy: .public), uid \(consoleUID, privacy: .public)"
        )
        return true
    }

    private func activeConsoleUserUID() -> uid_t? {
        var consoleInfo = stat()
        guard stat("/dev/console", &consoleInfo) == 0 else {
            return nil
        }

        let uid = consoleInfo.st_uid
        guard uid != 0, uid != uid_t.max else {
            return nil
        }
        return uid
    }
}
