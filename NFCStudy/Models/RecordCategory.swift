import SwiftUI

/// The record "categories" the app understands, used by both the read
/// breakdown and the write composer so the two sides mirror each other.
enum RecordCategory: String, CaseIterable, Identifiable {
    case text, url, wifi, contact, sms, location, bluetooth, phone, email, freeform
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
            case .text: return "Text"
            case .url: return "URL"
            case .wifi: return "WiFi"
            case .contact: return "Contact"
            case .sms: return "SMS"
            case .location: return "Location"
            case .bluetooth: return "Bluetooth"
            case .phone: return "Phone"
            case .email: return "Email"
            case .freeform: return "Freeform"
        }
    }
    
    var systemImage: String {
        switch self {
            case .text: return "textformat"
            case .url: return "link"
            case .wifi: return "wifi"
            case .contact: return "person.text.rectangle"
            case .sms: return "message"
            case .location: return "mappin.and.ellipse"
            case .bluetooth: return "dot.radiowaves.left.and.right"
            case .phone: return "phone"
            case .email: return "envelope"
            case .freeform: return "chevron.left.forwardslash.chevron.right"
        }
    }
    
    var tint: Color {
        switch self {
            case .text: return .primary
            case .url: return .blue
            case .wifi: return .teal
            case .contact: return .indigo
            case .sms: return .green
            case .location: return .red
            case .bluetooth: return .blue
            case .phone: return .green
            case .email: return .orange
            case .freeform: return .purple
        }
    }
}
