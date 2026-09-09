import Foundation

/// The v2 helper is a read-only SMC monitor. Do not add mutation, process,
/// path, launchd, maintenance or shell-command APIs to this protocol.
@objc protocol CoolCumberMonitorV2Protocol {
    func readTemperatures(reply: @escaping ([String: Double]) -> Void)
    func readFanSpeeds(reply: @escaping ([Int]) -> Void)
}
