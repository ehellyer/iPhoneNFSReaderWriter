//
//  ContentView.swift
//  NFCStudy
//
//  Created by Ed Hellyer on 7/3/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var nfc = NFCService()
    
    var body: some View {
        TabView {
            ReadView()
                .tabItem { Label("Read", systemImage: "wave.3.forward.circle") }
            WriteView()
                .tabItem { Label("Write", systemImage: "square.and.pencil.circle") }
        }
        .environmentObject(nfc)
    }
}

/// Shared label/value row used by both the record detail view (read side)
/// and the record previews (write side), so both sides look the same.
struct FieldRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ContentView()
}
