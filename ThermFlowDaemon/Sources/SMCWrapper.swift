import Foundation
import IOKit

public struct SMCKeyInfoData_vers_t {
    public var major: CChar = 0; public var minor: CChar = 0; public var build: CChar = 0; public var reserved: CChar = 0; public var release: UInt16 = 0
}

public struct SMCKeyInfoData_pLimitData_t {
    public var version: UInt16 = 0; public var length: UInt16 = 0; public var cpuPLimit: UInt32 = 0; public var gpuPLimit: UInt32 = 0; public var memPLimit: UInt32 = 0
}

public struct SMCKeyInfoData_keyInfo_t {
    public var dataSize: UInt32 = 0; public var dataType: UInt32 = 0; public var dataAttributes: UInt8 = 0
    private var pad1: UInt8 = 0; private var pad2: UInt8 = 0; private var pad3: UInt8 = 0
}

public struct SMCParamStruct {
    public var key: UInt32 = 0
    public var vers = SMCKeyInfoData_vers_t()
    private var pad1: UInt16 = 0
    public var pLimitData = SMCKeyInfoData_pLimitData_t()
    public var keyInfo = SMCKeyInfoData_keyInfo_t()
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var data8: UInt8 = 0
    private var pad2: UInt8 = 0
    public var data32: UInt32 = 0
    public var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

public class SMCWrapper {
    public static let shared = SMCWrapper()
    
    private var conn: io_connect_t = 0
    
    public enum SMCError: Error {
        case openError
        case notFound
        case readError
        case writeError
    }
    
    private init() {
        open()
    }
    
    deinit {
        close()
    }
    
    private func open() {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSMC"))
        if service == 0 {
            print("ERROR: AppleSMC service not found")
            return
        }
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        if result != kIOReturnSuccess {
            print("ERROR: Failed to open AppleSMC")
        }
    }
    
    private func close() {
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
        }
    }
    
    private func callSMC(index: UInt8, inputStruct: inout SMCParamStruct, outputStruct: inout SMCParamStruct) -> kern_return_t {
        let inputStructSize = MemoryLayout<SMCParamStruct>.stride
        var outputStructSize = MemoryLayout<SMCParamStruct>.stride
        
        let result = IOConnectCallStructMethod(conn, UInt32(index), &inputStruct, inputStructSize, &outputStruct, &outputStructSize)
        return result
    }
    
    private func getKeyInfo(key: UInt32) -> SMCKeyInfoData_keyInfo_t? {
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
            let bytes = output.bytes
            // Convert tuple to array
            return [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7, bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15, bytes.16, bytes.17, bytes.18, bytes.19, bytes.20, bytes.21, bytes.22, bytes.23, bytes.24, bytes.25, bytes.26, bytes.27, bytes.28, bytes.29, bytes.30, bytes.31]
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
        
        var count = Int(info.dataSize)
        if count > 32 { count = 32 }
        
        // Manual assignment
        if count > 0 && bytes.count > 0 { input.bytes.0 = bytes[0] }
        if count > 1 && bytes.count > 1 { input.bytes.1 = bytes[1] }
        if count > 2 && bytes.count > 2 { input.bytes.2 = bytes[2] }
        if count > 3 && bytes.count > 3 { input.bytes.3 = bytes[3] }
        if count > 4 && bytes.count > 4 { input.bytes.4 = bytes[4] }
        
        let result = callSMC(index: 2, inputStruct: &input, outputStruct: &output)
        return result == kIOReturnSuccess
    }
    
    private func stringToUInt32(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        let data = str.data(using: .ascii) ?? Data()
        for i in 0..<min(4, data.count) {
            result = (result << 8) | UInt32(data[i])
        }
        return result
    }
    
    private func uint32ToString(_ val: UInt32) -> String {
        let bytes = [UInt8((val >> 24) & 0xFF), UInt8((val >> 16) & 0xFF), UInt8((val >> 8) & 0xFF), UInt8(val & 0xFF)]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
    
    // Convert fpe2 to Double (fan speeds are often fpe2)
    public func bytesToFpe2(_ bytes: [UInt8]) -> Double {
        if bytes.count >= 2 {
            let val = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(val) / 4.0
        }
        return 0
    }
    
    // Convert Double to fpe2 bytes
    public func fpe2ToBytes(_ val: Double) -> [UInt8] {
        let intVal = UInt16(val * 4.0)
        return [UInt8(intVal >> 8), UInt8(intVal & 0xFF)]
    }
    
    public func readFanSpeed(key: String) -> Double? {
        let keyCode = stringToUInt32(key)
        guard let info = getKeyInfo(key: keyCode) else { return nil }
        guard let bytes = readValue(key: key) else { return nil }
        
        let typeStr = uint32ToString(info.dataType)
        
        if typeStr == "fpe2" && bytes.count >= 2 {
            let val = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(val) / 4.0
        } else if typeStr == "flt " && bytes.count >= 4 {
            var f: Float32 = 0
            let data = Data(bytes)
            _ = withUnsafeMutableBytes(of: &f) { data.copyBytes(to: $0) }
            return Double(f)
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
        
        if typeStr == "fpe2" {
            let intVal = UInt16(rpm * 4.0)
            bytes = [UInt8(intVal >> 8), UInt8(intVal & 0xFF)]
        } else if typeStr == "flt " {
            var f = Float32(rpm)
            bytes = withUnsafeBytes(of: &f) { Array($0) }
        } else if typeStr == "ui16" {
            let intVal = UInt16(rpm)
            bytes = [UInt8(intVal >> 8), UInt8(intVal & 0xFF)]
        } else {
            // Fallback to fpe2
            let intVal = UInt16(rpm * 4.0)
            bytes = [UInt8(intVal >> 8), UInt8(intVal & 0xFF)]
        }
        
        return writeValue(key: key, bytes: bytes)
    }
}
