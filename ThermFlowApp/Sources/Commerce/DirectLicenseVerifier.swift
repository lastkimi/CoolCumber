import CryptoKit
import Foundation
import Security

struct DirectLicensePayload: Codable, Equatable, Sendable {
    let schemaVersion: UInt16
    let licenseID: String
    let tier: String
    let issuedAt: Date
    let expiresAt: Date?
    let seats: UInt8
}

enum DirectLicenseError: LocalizedError, Sendable {
    case commerceUnavailable(reason: String)
    case missingPublicKey
    case malformedToken
    case tokenTooLarge
    case invalidSignature
    case unsupportedSchema
    case invalidClaims
    case expired
    case storageFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .commerceUnavailable(let reason):
            return reason
        case .missingPublicKey:
            return "This build does not contain a Direct license verification key."
        case .malformedToken:
            return "The license token is malformed."
        case .tokenTooLarge:
            return "The license token is larger than the supported format."
        case .invalidSignature:
            return "The license signature could not be verified."
        case .unsupportedSchema:
            return "The license was issued for an unsupported format."
        case .invalidClaims:
            return "The license contains invalid claims."
        case .expired:
            return "The license has expired."
        case .storageFailure(let status):
            return "The license could not be stored securely (\(status))."
        }
    }
}

struct DirectLicenseVerifier {
    private let publicKey: P256.Signing.PublicKey?

    var isConfigured: Bool { publicKey != nil }

    init(bundle: Bundle = .main) {
        guard let configuredValue = bundle.object(forInfoDictionaryKey: "CoolCumberLicensePublicKey") as? String else {
            publicKey = nil
            return
        }

        let encoded = configuredValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !encoded.isEmpty,
              let representation = Data(base64Encoded: encoded) else {
            publicKey = nil
            return
        }
        publicKey = try? P256.Signing.PublicKey(x963Representation: representation)
    }

    func verify(token: String, now: Date = Date()) throws -> DirectLicensePayload {
        guard let publicKey else { throw DirectLicenseError.missingPublicKey }
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedToken.utf8.count <= 16_384 else {
            throw DirectLicenseError.tokenTooLarge
        }

        let parts = normalizedToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payloadData = Data(base64URL: String(parts[0])),
              let signatureData = Data(base64URL: String(parts[1])),
              payloadData.count <= 8_192,
              signatureData.count <= 128,
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureData),
              let payload = try? JSONDecoder.licenseDecoder.decode(DirectLicensePayload.self, from: payloadData) else {
            throw DirectLicenseError.malformedToken
        }
        guard publicKey.isValidSignature(signature, for: payloadData) else {
            throw DirectLicenseError.invalidSignature
        }
        guard payload.schemaVersion == 1 else { throw DirectLicenseError.unsupportedSchema }
        let normalizedLicenseID = payload.licenseID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLicenseID.isEmpty,
              normalizedLicenseID.count <= 128,
              payload.tier == "pro",
              (UInt8(1)...UInt8(3)).contains(payload.seats),
              payload.issuedAt <= now.addingTimeInterval(300) else {
            throw DirectLicenseError.invalidClaims
        }
        if let expiresAt = payload.expiresAt {
            guard expiresAt > payload.issuedAt else {
                throw DirectLicenseError.invalidClaims
            }
            guard expiresAt > now else {
                throw DirectLicenseError.expired
            }
        }
        return payload
    }
}

struct DirectLicenseStore {
    private let service = "com.slmcamp.CoolCumber.license"

    func save(_ token: String) throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = normalizedToken.data(using: .utf8), !data.isEmpty else {
            throw DirectLicenseError.malformedToken
        }
        let base = query()
        let deleteStatus = SecItemDelete(base as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw DirectLicenseError.storageFailure(deleteStatus)
        }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw DirectLicenseError.storageFailure(status) }
    }

    func read() throws -> String? {
        var item = query()
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw DirectLicenseError.storageFailure(status)
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw DirectLicenseError.malformedToken
        }
        return token
    }

    func delete() {
        SecItemDelete(query() as CFDictionary)
    }

    private func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: CommerceCatalog.directLicenseAccount
        ]
    }
}

private extension JSONDecoder {
    static var licenseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let standardFormatter = ISO8601DateFormatter()
            standardFormatter.formatOptions = [.withInternetDateTime]
            if let date = standardFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date."
            )
        }
        return decoder
    }
}

private extension Data {
    init?(base64URL string: String) {
        var value = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder != 0 {
            value.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: value)
    }
}
