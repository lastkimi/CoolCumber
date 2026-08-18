import Foundation
import IOKit

public struct SMCKeyInfoData_vers_t {
    public var major: CChar = 0
    public var minor: CChar = 0
    public var build: CChar = 0
    public var reserved: CChar = 0
    public var release: UInt16 = 0
}

public struct SMCKeyInfoData_pLimitData_t {
    public var version: UInt16 = 0
    public var length: UInt16 = 0
    public var cpuPLimit: UInt32 = 0
    public var gpuPLimit: UInt32 = 0
    public var memPLimit: UInt32 = 0
}

public struct SMCKeyInfoData_keyInfo_t {
    public var dataSize: UInt32 = 0
    public var dataType: UInt32 = 0
    public var dataAttributes: UInt8 = 0
}

public struct SMCParamStruct {
    public var key: UInt32 = 0
    public var vers = SMCKeyInfoData_vers_t()
    public var pLimitData = SMCKeyInfoData_pLimitData_t()
    public var keyInfo = SMCKeyInfoData_keyInfo_t()
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

public class SMCWrapper {
    public static let shared = SMCWrapper()
    
    private var conn: io_connect_t = 0
    private let lock = NSLock()
    
    private init() {
        open()
    }
    
    deinit {
        close()
    }
    
    private func open() {
        lock.lock()
        defer { lock.unlock() }
        
        if conn != 0 { return }
        
        // Try AppleSMCClient first (Apple Silicon M1/M2/M3/M4), then AppleSMC
        let serviceNames = ["AppleSMCClient", "AppleSMC"]
        for name in serviceNames {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
            if service != 0 {
                let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
                IOObjectRelease(service)
                if result == kIOReturnSuccess && conn != 0 {
                    return
                }
            }
        }
    }
    
    private func close() {
        lock.lock()
        defer { lock.unlock() }
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
        }
    }
    
    private func callSMC(index: UInt8, inputStruct: inout SMCParamStruct, outputStruct: inout SMCParamStruct) -> kern_return_t {
        if conn == 0 { open() }
        guard conn != 0 else { return kIOReturnNotOpen }
        
        let inputStructSize = MemoryLayout<SMCParamStruct>.stride
        var outputStructSize = MemoryLayout<SMCParamStruct>.stride
        
        return IOConnectCallStructMethod(conn, UInt32(index), &inputStruct, inputStructSize, &outputStruct, &outputStructSize)
    }
    
    public func getKeyInfo(key: UInt32) -> SMCKeyInfoData_keyInfo_t? {
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        
        input.key = key
        input.data8 = 9 // kSMCGetKeyInfo
        
        let result = callSMC(index: 2, inputStruct: &input, outputStruct: &output)
        if result == kIOReturnSuccess {
            return output.keyInfo
        }
        return nil
    }
    
    public func readValue(key: String) -> [UInt8]? {
        let keyCode = stringToUInt32(key)
        guard let info = getKeyInfo(key: keyCode) else { return nil }
        
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        
        input.key = keyCode
        input.data8 = 5 // kSMCReadKey
        input.keyInfo = info
        
        let result = callSMC(index: 2, inputStruct: &input, outputStruct: &output)
        if result == kIOReturnSuccess {
            var rawBytes = [UInt8](repeating: 0, count: 32)
            withUnsafeBytes(of: output.bytes) { ptr in
                for i in 0..<min(32, ptr.count) {
                    rawBytes[i] = ptr[i]
                }
            }
            let validCount = min(Int(info.dataSize), 32)
            return Array(rawBytes.prefix(validCount))
        }
        return nil
    }
    
    public func writeValue(key: String, bytes: [UInt8]) -> Bool {
        let keyCode = stringToUInt32(key)
        guard let info = getKeyInfo(key: keyCode) else { return false }
        
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        
        input.key = keyCode
        input.data8 = 6 // kSMCWriteKey
        input.keyInfo = info
        
        withUnsafeMutableBytes(of: &input.bytes) { ptr in
            for i in 0..<min(bytes.count, ptr.count) {
                ptr[i] = bytes[i]
            }
        }
        
        let result = callSMC(index: 2, inputStruct: &input, outputStruct: &output)
        return result == kIOReturnSuccess
    }
    
    public func stringToUInt32(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        let data = str.data(using: .ascii) ?? Data()
        for i in 0..<min(4, data.count) {
            result = (result << 8) | UInt32(data[i])
        }
        return result
    }
    
    public func uint32ToString(_ val: UInt32) -> String {
        let bytes = [UInt8((val >> 24) & 0xFF), UInt8((val >> 16) & 0xFF), UInt8((val >> 8) & 0xFF), UInt8(val & 0xFF)]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
    
    // MARK: - Fan & Temperature Helpers
    
    public func readFanCount() -> Int {
        if let bytes = readValue(key: "FNum"), !bytes.isEmpty {
            return Int(bytes[0])
        }
        return 1
    }
    
    public func readFanSpeed(key: String) -> Double? {
        let keyCode = stringToUInt32(key)
        guard let info = getKeyInfo(key: keyCode) else { return nil }
        guard let bytes = readValue(key: key), !bytes.isEmpty else { return nil }
        
        let typeStr = uint32ToString(info.dataType)
        
        if typeStr == "flt " && bytes.count >= 4 {
            var f: Float32 = 0
            let data = Data(bytes)
            _ = withUnsafeMutableBytes(of: &f) { data.copyBytes(to: $0) }
            return Double(f)
        } else if (typeStr == "fpe2" || typeStr == "sp78") && bytes.count >= 2 {
            let val = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(val) / 4.0
        } else if typeStr == "ui16" && bytes.count >= 2 {
            let val = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(val)
        }
        return nil
    }
    
    public func writeFanSpeed(key: String, rpm: Double) -> Bool {
        let keyCode = stringToUInt32(key)
        guard let info = getKeyInfo(key: keyCode) else { return false }
        
        let typeStr = uint32ToString(info.dataType)
        var bytes: [UInt8] = []
        
        if typeStr == "flt " {
            var f = Float32(rpm)
            bytes = withUnsafeBytes(of: &f) { Array($0) }
        } else if typeStr == "fpe2" {
            let intVal = UInt16(rpm * 4.0)
            bytes = [UInt8(intVal >> 8), UInt8(intVal & 0xFF)]
        } else if typeStr == "ui16" {
            let intVal = UInt16(rpm)
            bytes = [UInt8(intVal >> 8), UInt8(intVal & 0xFF)]
        } else {
            var f = Float32(rpm)
            bytes = withUnsafeBytes(of: &f) { Array($0) }
        }
        
        return writeValue(key: key, bytes: bytes)
    }
    
    public func readTemperature(key: String) -> Double? {
        let keyCode = stringToUInt32(key)
        guard let info = getKeyInfo(key: keyCode) else { return nil }
        guard let bytes = readValue(key: key), !bytes.isEmpty else { return nil }
        
        let typeStr = uint32ToString(info.dataType)
        if typeStr == "sp78" && bytes.count >= 2 {
            let val = Int16((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(val) / 256.0
        } else if typeStr == "flt " && bytes.count >= 4 {
            var f: Float32 = 0
            let data = Data(bytes)
            _ = withUnsafeMutableBytes(of: &f) { data.copyBytes(to: $0) }
            return Double(f)
        } else if typeStr == "fpe2" && bytes.count >= 2 {
            let val = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(val) / 4.0
        } else if typeStr == "ui8 " || typeStr == "ui8" && !bytes.isEmpty {
            return Double(bytes[0])
        }
        return nil
    }
}
