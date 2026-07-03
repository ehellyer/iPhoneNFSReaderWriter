//
//  Data+Hex.swift
//  NFCStudy
//
//  Created by Ed Hellyer on 7/3/26.
//

import Foundation

extension Data {
    /// "04A1B2C3" style, no separators.
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
    
    /// "04 A1 B2 C3" style.
    var spacedHexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    
    /// Printable ASCII preview; non-printable bytes shown as "·".
    var asciiPreview: String {
        map { (32...126).contains($0) ? String(UnicodeScalar($0)) : "·" }.joined()
    }
    
    /// Parse a hex string ("0x" prefixes, spaces, colons allowed). Nil if invalid.
    init?(hexString: String) {
        let cleaned = hexString
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard cleaned.count % 2 == 0, !cleaned.isEmpty else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
