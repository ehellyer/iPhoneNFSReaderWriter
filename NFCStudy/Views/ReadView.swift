import SwiftUI

struct ReadView: View {
    @EnvironmentObject private var nfc: NFCService
    
    var body: some View {
        NavigationStack {
            Group {
                if let scan = nfc.lastScan {
                    scanResultList(scan)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Read Tag")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        nfc.beginRead()
                    } label: {
                        Label("Scan", systemImage: "wave.3.forward.circle.fill")
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Scan an NTAG215 tag")
                .font(.title2.weight(.semibold))
            Text("You'll see the tag's identity, every NDEF record broken down by category, and a raw dump of all 135 memory pages.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                nfc.beginRead()
            } label: {
                Label("Scan Tag", systemImage: "wave.3.forward.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            if let message = nfc.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
    
    private func scanResultList(_ scan: ScanResult) -> some View {
        List {
            Section("Tag") {
                FieldRow(label: "UID", value: scan.info.uidHex)
                FieldRow(label: "Model", value: scan.info.model)
                FieldRow(label: "Memory", value: "\(scan.info.totalBytes) bytes total · \(scan.info.totalPages) pages of 4 bytes")
                FieldRow(label: "NDEF capacity", value: "\(scan.info.ndefCapacity) bytes")
                FieldRow(label: "Status", value: scan.info.statusDescription)
            }
            
            Section("NDEF records (\(scan.records.count))") {
                if scan.records.isEmpty {
                    Text("No records — the tag is blank or not NDEF formatted.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scan.records) { record in
                        NavigationLink {
                            RecordDetailView(record: record)
                        } label: {
                            RecordRow(record: record)
                        }
                    }
                }
            }
            
            Section("Memory") {
                NavigationLink {
                    RawMemoryView(pages: scan.pages, totalPages: scan.info.totalPages)
                } label: {
                    Label("Raw page dump", systemImage: "memorychip")
                }
            }
        }
    }
}

struct RecordRow: View {
    let record: ParsedRecord
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.category.systemImage)
                .font(.title3)
                .foregroundStyle(record.category.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.summary)
                    .lineLimit(2)
            }
        }
    }
}
