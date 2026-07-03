//
//  PayloadBuilder.swift
//  NFCStudy
//
//  Created by Ed Hellyer on 7/3/26.
//

import CoreNFC
import Foundation

enum WiFiSecurity: String, CaseIterable, Identifiable {
    case open = "Open (no password)"
    case wpa2 = "WPA/WPA2 Personal"
    var id: String { rawValue }
    
    /// WiFi Simple Configuration authentication type (big-endian UInt16).
    var authBytes: Data { self == .open ? Data([0x00, 0x01]) : Data([0x00, 0x20]) }
    /// WSC encryption type (big-endian UInt16).
    var encryptionBytes: Data { self == .open ? Data([0x00, 0x01]) : Data([0x00, 0x08]) }
}

/// Builds `NFCNDEFPayload`s for every record category the app can write.
enum PayloadBuilder {
    
    // MARK: Well-known types
    
    static func text(_ string: String, languageCode: String = "en") -> NFCNDEFPayload {
        let lang = Data(languageCode.utf8)
        var payload = Data([UInt8(lang.count & 0x3F)]) // UTF-8, language code length
        payload.append(lang)
        payload.append(Data(string.utf8))
        return NFCNDEFPayload(format: .nfcWellKnown, type: Data("T".utf8), identifier: Data(), payload: payload)
    }
    
    static func uri(_ uriString: String) -> NFCNDEFPayload {
        let (code, remainder) = URIPrefix.encode(uriString)
        var payload = Data([code])
        payload.append(Data(remainder.utf8))
        return NFCNDEFPayload(format: .nfcWellKnown, type: Data("U".utf8), identifier: Data(), payload: payload)
    }
    
    // MARK: URI-based categories
    
    static func url(_ urlString: String) -> NFCNDEFPayload {
        var s = urlString
        if !s.contains("://") && !s.hasPrefix("mailto:") { s = "https://" + s }
        return uri(s)
    }
    
    static func phone(number: String) -> NFCNDEFPayload {
        uri("tel:" + number.replacingOccurrences(of: " ", with: ""))
    }
    
    static func sms(number: String, body: String) -> NFCNDEFPayload {
        var s = "sms:" + number.replacingOccurrences(of: " ", with: "")
        if !body.isEmpty {
            let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
            s += "?body=" + encoded
        }
        return uri(s)
    }
    
    static func location(latitude: Double, longitude: Double) -> NFCNDEFPayload {
        uri(String(format: "geo:%.6f,%.6f", latitude, longitude))
    }
    
    static func email(to: String, subject: String, body: String) -> NFCNDEFPayload {
        var s = "mailto:" + to
        var query: [String] = []
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?"))
        if !subject.isEmpty { query.append("subject=" + (subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? subject)) }
        if !body.isEmpty { query.append("body=" + (body.addingPercentEncoding(withAllowedCharacters: allowed) ?? body)) }
        if !query.isEmpty { s += "?" + query.joined(separator: "&") }
        return uri(s)
    }
    
    // MARK: WiFi (WiFi Simple Configuration MIME record)
    
    static func wifi(ssid: String, password: String, security: WiFiSecurity) -> NFCNDEFPayload {
        var credential = Data()
        credential.append(wscTLV(0x1026, Data([0x01])))            // network index
        credential.append(wscTLV(0x1045, Data(ssid.utf8)))         // SSID
        credential.append(wscTLV(0x1003, security.authBytes))      // auth type
        credential.append(wscTLV(0x100F, security.encryptionBytes)) // encryption type
        credential.append(wscTLV(0x1027, Data(password.utf8)))     // network key
        credential.append(wscTLV(0x1020, Data(repeating: 0xFF, count: 6))) // MAC (broadcast)
        let payload = wscTLV(0x100E, credential)                   // credential wrapper
        return NFCNDEFPayload(format: .media,
                              type: Data("application/vnd.wfa.wsc".utf8),
                              identifier: Data(),
                              payload: payload)
    }
    
    private static func wscTLV(_ type: UInt16, _ value: Data) -> Data {
        var d = Data()
        d.append(UInt8(type >> 8)); d.append(UInt8(type & 0xFF))
        d.append(UInt8(value.count >> 8)); d.append(UInt8(value.count & 0xFF))
        d.append(value)
        return d
    }
    
    // MARK: Contact (vCard MIME record)
    
    static func contact(firstName: String, lastName: String, organization: String,
                        phone: String, email: String) -> NFCNDEFPayload {
        var lines = ["BEGIN:VCARD", "VERSION:3.0"]
        lines.append("N:\(lastName);\(firstName);;;")
        lines.append("FN:\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces))
        if !organization.isEmpty { lines.append("ORG:\(organization)") }
        if !phone.isEmpty { lines.append("TEL;TYPE=CELL:\(phone)") }
        if !email.isEmpty { lines.append("EMAIL:\(email)") }
        lines.append("END:VCARD")
        let vcard = lines.joined(separator: "\r\n") + "\r\n"
        return NFCNDEFPayload(format: .media,
                              type: Data("text/vcard".utf8),
                              identifier: Data(),
                              payload: Data(vcard.utf8))
    }
    
    // MARK: Bluetooth (out-of-band pairing MIME record)
    
    /// `macAddress` in "AA:BB:CC:DD:EE:FF" form. Returns nil if the address is invalid.
    static func bluetooth(macAddress: String, deviceName: String) -> NFCNDEFPayload? {
        let parts = macAddress.split(separator: ":")
        guard parts.count == 6 else { return nil }
        var addr = Data()
        for part in parts.reversed() { // BD_ADDR is little-endian on the wire
            guard let byte = UInt8(part, radix: 16) else { return nil }
            addr.append(byte)
        }
        var eir = Data()
        if !deviceName.isEmpty {
            let name = Data(deviceName.utf8)
            eir.append(UInt8(name.count + 1)) // EIR length (type byte + data)
            eir.append(0x09)                  // Complete Local Name
            eir.append(name)
        }
        let total = 2 + 6 + eir.count
        var payload = Data([UInt8(total & 0xFF), UInt8(total >> 8)]) // OOB length, little-endian
        payload.append(addr)
        payload.append(eir)
        return NFCNDEFPayload(format: .media,
                              type: Data("application/vnd.bluetooth.ep.oob".utf8),
                              identifier: Data(),
                              payload: payload)
    }
    
    // MARK: Freeform
    
    static func freeform(format: NFCTypeNameFormat, type: String, payload: Data) -> NFCNDEFPayload {
        NFCNDEFPayload(format: format, type: Data(type.utf8), identifier: Data(), payload: payload)
    }
    
    // MARK: Size estimation
    
    /// Approximate bytes each record occupies inside the NDEF message.
    static func estimatedSize(of payloads: [NFCNDEFPayload]) -> Int {
        payloads.reduce(0) { total, p in
            let header = 2                                  // flags + type length
            let payloadLength = p.payload.count < 256 ? 1 : 4
            return total + header + payloadLength + p.type.count + p.payload.count
        }
    }
}
