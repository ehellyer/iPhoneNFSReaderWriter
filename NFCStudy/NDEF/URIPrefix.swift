import Foundation

/// NFC Forum URI Record Type Definition prefix abbreviation table.
/// The first payload byte of a well-known "U" record is an index into this table.
enum URIPrefix {
    static let table: [String] = [
        "",                         // 0x00
        "http://www.",              // 0x01
        "https://www.",             // 0x02
        "http://",                  // 0x03
        "https://",                 // 0x04
        "tel:",                     // 0x05
        "mailto:",                  // 0x06
        "ftp://anonymous:anonymous@", // 0x07
        "ftp://ftp.",               // 0x08
        "ftps://",                  // 0x09
        "sftp://",                  // 0x0A
        "smb://",                   // 0x0B
        "nfs://",                   // 0x0C
        "ftp://",                   // 0x0D
        "dav://",                   // 0x0E
        "news:",                    // 0x0F
        "telnet://",                // 0x10
        "imap:",                    // 0x11
        "rtsp://",                  // 0x12
        "urn:",                     // 0x13
        "pop:",                     // 0x14
        "sip:",                     // 0x15
        "sips:",                    // 0x16
        "tftp:",                    // 0x17
        "btspp://",                 // 0x18
        "btl2cap://",               // 0x19
        "btgoep://",                // 0x1A
        "tcpobex://",               // 0x1B
        "irdaobex://",              // 0x1C
        "file://",                  // 0x1D
        "urn:epc:id:",              // 0x1E
        "urn:epc:tag:",             // 0x1F
        "urn:epc:pat:",             // 0x20
        "urn:epc:raw:",             // 0x21
        "urn:epc:",                 // 0x22
        "urn:nfc:"                  // 0x23
    ]
    
    /// Encode a URI string as (prefix code, remainder), using the longest matching prefix.
    static func encode(_ uri: String) -> (code: UInt8, remainder: String) {
        var best = 0
        for (index, prefix) in table.enumerated() where index > 0 {
            if uri.hasPrefix(prefix) && prefix.count > table[best].count {
                best = index
            }
        }
        return (UInt8(best), String(uri.dropFirst(table[best].count)))
    }
    
    /// Decode (prefix code, remainder bytes) back to the full URI string.
    static func decode(code: UInt8, remainder: Data) -> String {
        let prefix = Int(code) < table.count ? table[Int(code)] : ""
        return prefix + (String(data: remainder, encoding: .utf8) ?? "")
    }
}
