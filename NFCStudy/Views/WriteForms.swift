import CoreNFC
import SwiftUI

// Every form ends with an "Add record" button that hands a built
// NFCNDEFPayload back to WriteView's queue. Field labels intentionally
// match the labels shown when reading, so read and write mirror each other.

private struct AddButton: View {
    let enabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label("Add record to message", systemImage: "plus.circle.fill")
        }
        .disabled(!enabled)
    }
}

struct TextForm: View {
    let onAdd: (NFCNDEFPayload) -> Void
    @State private var text = ""
    @State private var language = "en"
    
    var body: some View {
        Section("Text record") {
            TextField("Text", text: $text, axis: .vertical).lineLimit(1...5)
            TextField("Language code (e.g. en)", text: $language)
                .textInputAutocapitalization(.never)
            AddButton(enabled: !text.isEmpty) {
                onAdd(PayloadBuilder.text(text, languageCode: language.isEmpty ? "en" : language))
                text = ""
            }
        }
    }
}

struct URLForm: View {
    let onAdd: (NFCNDEFPayload) -> Void
    @State private var url = ""
    
    var body: some View {
        Section("URL record") {
            TextField("URL (e.g. https://example.com)", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            AddButton(enabled: !url.isEmpty) {
                onAdd(PayloadBuilder.url(url))
                url = ""
            }
        }
    }
}

struct WiFiForm: View {
    let onAdd: (NFCNDEFPayload) -> Void
    @State private var ssid = ""
    @State private var password = ""
    @State private var security: WiFiSecurity = .wpa2
    
    var body: some View {
        Section("WiFi record") {
            TextField("Network name (SSID)", text: $ssid)
                .autocorrectionDisabled()
            Picker("Security", selection: $security) {
                ForEach(WiFiSecurity.allCases) { Text($0.rawValue).tag($0) }
            }
            if security == .wpa2 {
                SecureField("Password", text: $password)
            }
            AddButton(enabled: !ssid.isEmpty && (security == .open || !password.isEmpty)) {
                onAdd(PayloadBuilder.wifi(ssid: ssid, password: security == .open ? "" : password, security: security))
                ssid = ""; password = ""
            }
        }
    }
}

struct ContactForm: View {
    let onAdd: (NFCNDEFPayload) -> Void
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var organization = ""
    @State private var phone = ""
    @State private var email = ""
    
    var body: some View {
        Section("Contact record (vCard)") {
            TextField("First name", text: $firstName)
            TextField("Last name", text: $lastName)
            TextField("Organization", text: $organization)
            TextField("Phone", text: $phone).keyboardType(.phonePad)
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            AddButton(enabled: !firstName.isEmpty || !lastName.isEmpty) {
                onAdd(PayloadBuilder.contact(firstName: firstName, lastName: lastName,
                                             organization: organization, phone: phone, email: email))
                firstName = ""; lastName = ""; organization = ""; phone = ""; email = ""
            }
        }
    }
}

struct SMSForm: View {
    let onAdd: (NFCNDEFPayload) -> Void
    @State private var number = ""
    @State private var message = ""
    
    var body: some View {
        Section("SMS record") {
            TextField("Phone number", text: $number).keyboardType(.phonePad)
            TextField("Message", text: $message, axis: .vertical).lineLimit(1...4)
            AddButton(enabled: !number.isEmpty) {
                onAdd(PayloadBuilder.sms(number: number, body: message))
                number = ""; message = ""
            }
        }
    }
}

struct LocationForm: View {
    let onAdd: (NFCNDEFPayload) -> Void
    @State private var latitude = ""
    @State private var longitude = ""
    
    private var lat: Double? { Double(latitude) }
    private var lon: Double? { Double(longitude) }
    private var valid: Bool {
        guard let lat, let lon else { return false }
        return (-90...90).contains(lat) && (-180...180).contains(lon)
    }
    
    var body: some View {
        Section("Location record") {
            TextField("Latitude (e.g. 51.5074)", text: $latitude)
                .keyboardType(.numbersAndPunctuation)
            TextField("Longitude (e.g. -0.1278)", text: $longitude)
                .keyboardType(.numbersAndPunctuation)
            AddButton(enabled: valid) {
                if let lat, let lon {
                    onAdd(PayloadBuilder.location(latitude: lat, longitude: lon))
                    latitude = ""; longitude = ""
                }
            }
        }
    }
}

struct BluetoothForm: View {
    let onAdd: (NFCNDEFPayload) -> Void
    @State private var macAddress = ""
    @State private var deviceName = ""
    
    private var valid: Bool {
        PayloadBuilder.bluetooth(macAddress: macAddress, deviceName: deviceName) != nil
    }
    
    var body: some View {
        Section {
            TextField("MAC address (AA:BB:CC:DD:EE:FF)", text: $macAddress)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Device name (optional)", text: $deviceName)
            AddButton(enabled: valid) {
                if let payload = PayloadBuilder.bluetooth(macAddress: macAddress, deviceName: deviceName) {
                    onAdd(payload)
                    macAddress = ""; deviceName = ""
                }
            }
        }
        header: {
            Text("Bluetooth pairing record")
        }
        footer: {
            Text("Writes an out-of-band pairing record. Tapping the tag offers to pair with the Bluetooth device at this address.")
        }
    }
}

struct PhoneForm: View {
    let onAdd: (NFCNDEFPayload) -> Void
    @State private var number = ""
    
    var body: some View {
        Section("Phone record") {
            TextField("Phone number", text: $number).keyboardType(.phonePad)
            AddButton(enabled: !number.isEmpty) {
                onAdd(PayloadBuilder.phone(number: number))
                number = ""
            }
        }
    }
}

struct EmailForm: View {
    let onAdd: (NFCNDEFPayload) -> Void
    @State private var to = ""
    @State private var subject = ""
    @State private var bodyText = ""
    
    var body: some View {
        Section("Email record") {
            TextField("To", text: $to)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            TextField("Subject", text: $subject)
            TextField("Body", text: $bodyText, axis: .vertical).lineLimit(1...4)
            AddButton(enabled: to.contains("@")) {
                onAdd(PayloadBuilder.email(to: to, subject: subject, body: bodyText))
                to = ""; subject = ""; bodyText = ""
            }
        }
    }
}

struct FreeformForm: View {
    let onAdd: (NFCNDEFPayload) -> Void
    
    private enum TNFChoice: String, CaseIterable, Identifiable {
        case wellKnown = "NFC Well Known"
        case media = "MIME Media"
        case absoluteURI = "Absolute URI"
        case external = "NFC External"
        case unknown = "Unknown"
        var id: String { rawValue }
        
        var format: NFCTypeNameFormat {
            switch self {
                case .wellKnown: return .nfcWellKnown
                case .media: return .media
                case .absoluteURI: return .absoluteURI
                case .external: return .nfcExternal
                case .unknown: return .unknown
            }
        }
    }
    
    @State private var tnf: TNFChoice = .external
    @State private var typeString = ""
    @State private var payloadText = ""
    @State private var payloadIsHex = false
    
    private var payloadData: Data? {
        payloadIsHex ? Data(hexString: payloadText) : Data(payloadText.utf8)
    }
    
    var body: some View {
        Section {
            Picker("Type Name Format", selection: $tnf) {
                ForEach(TNFChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            TextField("Type (e.g. example.com:mytype)", text: $typeString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Toggle("Payload is hex bytes", isOn: $payloadIsHex)
            TextField(payloadIsHex ? "Payload (e.g. DE AD BE EF)" : "Payload text", text: $payloadText, axis: .vertical)
                .lineLimit(1...4)
                .font(payloadIsHex ? .system(.body, design: .monospaced) : .body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            AddButton(enabled: payloadData != nil && !payloadText.isEmpty) {
                if let data = payloadData {
                    onAdd(PayloadBuilder.freeform(format: tnf.format, type: typeString, payload: data))
                    payloadText = ""
                }
            }
        }
        header: {
            Text("Freeform record")
        }
        footer: {
            Text("Build any NDEF record byte-for-byte — useful for experimenting with custom types.")
        }
    }
}
