import SwiftUI

struct RecordDetailView: View {
    let record: ParsedRecord
    
    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: record.category.systemImage)
                        .font(.title)
                        .foregroundStyle(record.category.tint)
                    VStack(alignment: .leading) {
                        Text(record.category.displayName)
                            .font(.headline)
                        Text(record.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            }
            
            if !record.fields.isEmpty {
                Section("Fields") {
                    ForEach(record.fields) { field in
                        FieldRow(label: field.label, value: field.value)
                    }
                }
            }
            
            Section("NDEF structure") {
                FieldRow(label: "Type Name Format (TNF)", value: record.tnfDescription)
                FieldRow(label: "Type", value: record.typeDescription)
                FieldRow(label: "Payload length", value: "\(record.payload.count) bytes")
            }
            
            Section("Raw payload") {
                Text(record.payload.spacedHexString)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                Text(record.payload.asciiPreview)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
    }
}
