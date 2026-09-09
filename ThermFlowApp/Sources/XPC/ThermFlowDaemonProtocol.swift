import Foundation

/// The complete v2 privileged API. Keep this interface deliberately tiny:
/// local CPU, memory, network, disk, battery, process and thermal-pressure
/// data are collected without root privileges by the app.
@objc protocol CoolCumberMonitorV2Protocol {
    func readTemperatures(reply: @escaping ([String: Double]) -> Void)
    func readFanSpeeds(reply: @escaping ([Int]) -> Void)
}
