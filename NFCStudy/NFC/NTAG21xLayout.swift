import SwiftUI

/// Thrown when a scanned tag cannot be positively identified as a
/// supported NTAG21x chip.
enum TagIdentificationError: LocalizedError {
    case getVersionFailed
    case unsupportedChip(storageByte: UInt8)

    var errorDescription: String? {
        switch self {
            case .getVersionFailed:
                return "The tag did not answer the GET_VERSION command, so its chip type could not be identified. It may not be an NTAG21x tag."
            case .unsupportedChip(let storageByte):
                return String(format: "Unsupported chip: GET_VERSION reported storage-size byte 0x%02X, which is not an NTAG213, NTAG215, or NTAG216.", storageByte)
        }
    }
}

/// Memory-map knowledge for the NTAG21x family (NTAG213 / NTAG215 / NTAG216).
/// Each page is 4 bytes and the layout is identical across the family:
/// UID and lock bytes, then the Capability Container, then user memory,
/// then five trailing configuration pages. Only the amount of user memory
/// in the middle differs by model.
enum NTAG21xLayout {

    enum Region: String {

        case uid = "UID / manufacturer"
        case lock = "Lock bytes"
        case capability = "Capability Container"
        case user = "User memory"
        case config = "Configuration"

        var color: Color {
            switch self {
                case .uid: return .blue
                case .lock: return .orange
                case .capability: return .purple
                case .user: return .green
                case .config: return .red
            }
        }
    }

    static func region(forPage page: Int, totalPages: Int) -> Region {
        switch page {
            case 0, 1: return .uid
            case 2: return .lock
            case 3: return .capability
            case totalPages - 5: return .lock
            case (totalPages - 4)...: return .config
            default: return .user
        }
    }

    static func annotation(forPage page: Int, totalPages: Int) -> String {
        switch page {
            case 0: return "UID bytes 0–2 + check byte 0"
            case 1: return "UID bytes 3–6"
            case 2: return "UID check byte 1, internal, static lock bytes"
            case 3: return "Capability Container (E1 = NDEF magic, version, data size ÷ 8, access)"
            case totalPages - 5: return "Dynamic lock bytes + RFUI"
            case totalPages - 4: return "CFG0 — mirror config, auth start page (AUTH0)"
            case totalPages - 3: return "CFG1 — access config, auth attempt limit"
            case totalPages - 2: return "PWD — 32-bit password (always reads as 00)"
            case totalPages - 1: return "PACK — password acknowledge (always reads as 00)"
            default: return "User memory (NDEF TLVs live here)"
        }
    }

    /// Map the GET_VERSION storage-size byte to a model name and page count.
    /// Throws `TagIdentificationError` if the byte is missing or unrecognized.
    static func model(forStorageByte byte: UInt8?) throws -> (name: String, pages: Int) {
        guard let byte else { throw TagIdentificationError.getVersionFailed }
        switch byte {
            case 0x0F: return ("NTAG213", 45)
            case 0x11: return ("NTAG215", 135)
            case 0x13: return ("NTAG216", 231)
            default: throw TagIdentificationError.unsupportedChip(storageByte: byte)
        }
    }
}
