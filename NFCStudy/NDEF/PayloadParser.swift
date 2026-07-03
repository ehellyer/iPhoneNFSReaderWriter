//
//  PayloadParser.swift
//  NFCStudy
//
//  Created by Ed Hellyer on 7/3/26.
//

import CoreNFC
import Foundation

/// Decodes `NFCNDEFPayload`s into `ParsedRecord`s with a per-category field
/// breakdown that mirrors the write forms.
enum PayloadParser {
    
    static func parse(_ message: NFCNDEFMessage) -> [ParsedRecord] {
        message.records.map { parse($0) }
    }
    
    static func parse(_ p: NFCNDEFPayload) -> ParsedRecord {
        let typeString = String(data: p.type, encoding: .utf8) ?? p.type.hexString
        
        switch p.typeNameFormat {
            case .nfcWellKnown where typeString == "T":
                return parseText(p, typeString: typeString)
            case .nfcWellKnown where typeString == "U":
                return parseURI(p, typeString: typeString)
            case .media:
                return parseMedia(p, typeString: typeString)
            case .empty:
                return record(p, category: .freeform, summary: "Empty record", fields: [], typeString: typeString)
            default:
                return fallback(p, typeString: typeString)
        }
    }
    
    // MARK: Well-known Text
    
    private static func parseText(_ p: NFCNDEFPayload, typeString: String) -> ParsedRecord {
        guard let status = p.payload.first else {
            return fallback(p, typeString: typeString)
        }
        let isUTF16 = status & 0x80 != 0
        let langLength = Int(status & 0x3F)
        guard p.payload.count >= 1 + langLength else { return fallback(p, typeString: typeString) }
        let lang = String(data: p.payload.subdata(in: 1..<(1 + langLength)), encoding: .utf8) ?? "?"
        let textData = p.payload.subdata(in: (1 + langLength)..<p.payload.count)
        let text = String(data: textData, encoding: isUTF16 ? .utf16 : .utf8) ?? ""
        return record(p, category: .text, summary: text, fields: [
            .init(label: "Text", value: text),
            .init(label: "Language", value: lang),
            .init(label: "Encoding", value: isUTF16 ? "UTF-16" : "UTF-8")
        ], typeString: typeString)
    }
    
    // MARK: Well-known URI (also covers phone / SMS / email / location)
    
    private static func parseURI(_ p: NFCNDEFPayload, typeString: String) -> ParsedRecord {
        guard let code = p.payload.first else { return fallback(p, typeString: typeString) }
        let uri = URIPrefix.decode(code: code, remainder: p.payload.dropFirst())
        var fields: [ParsedRecord.Field] = []
        var category: RecordCategory = .url
        var summary = uri
        
        if uri.hasPrefix("tel:") {
            category = .phone
            let number = String(uri.dropFirst(4))
            summary = number
            fields.append(.init(label: "Phone number", value: number))
        } else if uri.hasPrefix("sms:") {
            category = .sms
            let rest = String(uri.dropFirst(4))
            let parts = rest.split(separator: "?", maxSplits: 1)
            let number = String(parts.first ?? "")
            summary = number
            fields.append(.init(label: "Phone number", value: number))
            if parts.count > 1, let body = queryValue("body", in: String(parts[1])) {
                fields.append(.init(label: "Message", value: body))
            }
        } else if uri.hasPrefix("mailto:") {
            category = .email
            let rest = String(uri.dropFirst(7))
            let parts = rest.split(separator: "?", maxSplits: 1)
            let address = String(parts.first ?? "")
            summary = address
            fields.append(.init(label: "To", value: address))
            if parts.count > 1 {
                if let subject = queryValue("subject", in: String(parts[1])) {
                    fields.append(.init(label: "Subject", value: subject))
                }
                if let body = queryValue("body", in: String(parts[1])) {
                    fields.append(.init(label: "Body", value: body))
                }
            }
        } else if uri.hasPrefix("geo:") {
            category = .location
            let coords = String(uri.dropFirst(4)).split(separator: ",")
            if coords.count >= 2 {
                fields.append(.init(label: "Latitude", value: String(coords[0])))
                fields.append(.init(label: "Longitude", value: String(coords[1])))
                summary = "\(coords[0]), \(coords[1])"
            }
        } else {
            fields.append(.init(label: "URL", value: uri))
        }
        
        fields.append(.init(label: "URI prefix code", value: String(format: "0x%02X (\"%@\")", code,
                                                                    Int(code) < URIPrefix.table.count ? URIPrefix.table[Int(code)] : "?")))
        fields.append(.init(label: "Full URI", value: uri))
        return record(p, category: category, summary: summary, fields: fields, typeString: typeString)
    }
    
    // MARK: MIME records (WiFi / vCard / Bluetooth)
    
    private static func parseMedia(_ p: NFCNDEFPayload, typeString: String) -> ParsedRecord {
        let mime = typeString.lowercased()
        if mime == "application/vnd.wfa.wsc" { return parseWiFi(p, typeString: typeString) }
        if mime.contains("vcard") { return parseVCard(p, typeString: typeString) }
        if mime == "application/vnd.bluetooth.ep.oob" { return parseBluetooth(p, typeString: typeString) }
        return fallback(p, typeString: typeString)
    }
    
    private static func parseWiFi(_ p: NFCNDEFPayload, typeString: String) -> ParsedRecord {
        var ssid = "", key = "", auth = ""
        parseWSC(p.payload, ssid: &ssid, key: &key, auth: &auth)
        var fields: [ParsedRecord.Field] = [
            .init(label: "Network name (SSID)", value: ssid),
            .init(label: "Security", value: auth)
        ]
        if !key.isEmpty { fields.append(.init(label: "Password", value: key)) }
        return record(p, category: .wifi, summary: ssid.isEmpty ? "WiFi credential" : ssid,
                      fields: fields, typeString: typeString)
    }
    
    private static func parseWSC(_ data: Data, ssid: inout String, key: inout String, auth: inout String) {
        var i = data.startIndex
        while i + 4 <= data.endIndex {
            let type = UInt16(data[i]) << 8 | UInt16(data[i + 1])
            let length = Int(UInt16(data[i + 2]) << 8 | UInt16(data[i + 3]))
            let valueStart = i + 4
            guard valueStart + length <= data.endIndex else { break }
            let value = data.subdata(in: valueStart..<(valueStart + length))
            switch type {
                case 0x100E: parseWSC(value, ssid: &ssid, key: &key, auth: &auth) // credential — recurse
                case 0x1045: ssid = String(data: value, encoding: .utf8) ?? ""
                case 0x1027: key = String(data: value, encoding: .utf8) ?? ""
                case 0x1003:
                    let v = value.count == 2 ? UInt16(value[value.startIndex]) << 8 | UInt16(value[value.startIndex + 1]) : 0
                    switch v {
                        case 0x0001: auth = "Open"
                        case 0x0002: auth = "WPA Personal"
                        case 0x0020: auth = "WPA2 Personal"
                        case 0x0022: auth = "WPA/WPA2 Personal"
                        default: auth = String(format: "0x%04X", v)
                    }
                default: break
            }
            i = valueStart + length
        }
    }
    
    private static func parseVCard(_ p: NFCNDEFPayload, typeString: String) -> ParsedRecord {
        let raw = String(data: p.payload, encoding: .utf8) ?? ""
        var fields: [ParsedRecord.Field] = []
        var name = "Contact"
        for line in raw.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.hasPrefix("FN:") {
                name = String(text.dropFirst(3))
                fields.append(.init(label: "Name", value: name))
            } else if text.hasPrefix("ORG:") {
                fields.append(.init(label: "Organization", value: String(text.dropFirst(4))))
            } else if text.hasPrefix("TEL") {
                fields.append(.init(label: "Phone", value: String(text.split(separator: ":").last ?? "")))
            } else if text.hasPrefix("EMAIL") {
                fields.append(.init(label: "Email", value: String(text.split(separator: ":").last ?? "")))
            }
        }
        fields.append(.init(label: "Raw vCard", value: raw))
        return record(p, category: .contact, summary: name, fields: fields, typeString: typeString)
    }
    
    private static func parseBluetooth(_ p: NFCNDEFPayload, typeString: String) -> ParsedRecord {
        let data = p.payload
        guard data.count >= 8 else { return fallback(p, typeString: typeString) }
        let mac = data.subdata(in: 2..<8).reversed()
            .map { String(format: "%02X", $0) }.joined(separator: ":")
        var fields: [ParsedRecord.Field] = [.init(label: "MAC address", value: mac)]
        var name = ""
        var i = 8
        while i + 1 < data.count { // walk EIR structures
            let length = Int(data[i])
            guard length > 0, i + 1 + length <= data.count else { break }
            let eirType = data[i + 1]
            let value = data.subdata(in: (i + 2)..<(i + 1 + length))
            if eirType == 0x09 || eirType == 0x08 {
                name = String(data: value, encoding: .utf8) ?? ""
                fields.append(.init(label: "Device name", value: name))
            }
            i += 1 + length
        }
        return record(p, category: .bluetooth, summary: name.isEmpty ? mac : name,
                      fields: fields, typeString: typeString)
    }
    
    // MARK: Helpers
    
    private static func fallback(_ p: NFCNDEFPayload, typeString: String) -> ParsedRecord {
        var fields: [ParsedRecord.Field] = []
        if let text = String(data: p.payload, encoding: .utf8), !text.isEmpty {
            fields.append(.init(label: "Payload (as text)", value: text))
        }
        return record(p, category: .freeform,
                      summary: typeString.isEmpty ? "Unknown record" : typeString,
                      fields: fields, typeString: typeString)
    }
    
    private static func record(_ p: NFCNDEFPayload, category: RecordCategory, summary: String,
                               fields: [ParsedRecord.Field], typeString: String) -> ParsedRecord {
        ParsedRecord(category: category,
                     summary: summary.isEmpty ? category.displayName : summary,
                     fields: fields,
                     tnfDescription: describe(p.typeNameFormat),
                     typeDescription: typeString,
                     payload: p.payload)
    }
    
    private static func queryValue(_ key: String, in query: String) -> String? {
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2, kv[0] == Substring(key) {
                return String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        return nil
    }
    
    private static func describe(_ tnf: NFCTypeNameFormat) -> String {
        switch tnf {
            case .empty: return "Empty (0x00)"
            case .nfcWellKnown: return "NFC Well Known (0x01)"
            case .media: return "MIME Media (0x02)"
            case .absoluteURI: return "Absolute URI (0x03)"
            case .nfcExternal: return "NFC External (0x04)"
            case .unknown: return "Unknown (0x05)"
            case .unchanged: return "Unchanged (0x06)"
            @unknown default: return "Unrecognized"
        }
    }
}
