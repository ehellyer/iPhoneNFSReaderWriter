import CoreNFC
import SwiftUI

struct WriteView: View {
    @EnvironmentObject private var nfc: NFCService
    @State private var selected: RecordCategory = .text
    @State private var queued: [NFCNDEFPayload] = []
    @State private var showWriteSuccess = false
    
    /// NTAG215 NDEF capacity (from its Capability Container: 0x3E × 8 = 496 bytes).
    private let ntag215Capacity = 496
    
    private var estimatedBytes: Int { PayloadBuilder.estimatedSize(of: queued) }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Record type") {
                    Picker("Type", selection: $selected) {
                        ForEach(RecordCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                
                formSection
                
                queueSection
                
                Section {
                    Button {
                        nfc.beginWrite(NFCNDEFMessage(records: queued))
                    } label: {
                        Label("Write \(queued.count) record\(queued.count == 1 ? "" : "s") to tag",
                              systemImage: "wave.3.forward.circle.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                    }
                    .disabled(queued.isEmpty || estimatedBytes > ntag215Capacity)
                } footer: {
                    if let message = nfc.statusMessage {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Write Tag")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                        .font(.body.weight(.semibold))
                }
            }
            .onChange(of: nfc.lastWriteSucceeded) { _, success in
                if success {
                    queued.removeAll()
                    showWriteSuccess = true
                    nfc.lastWriteSucceeded = false
                }
            }
            .alert("Tag written successfully", isPresented: $showWriteSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Switch to the Read tab and scan the tag to see your records on the card.")
            }
        }
    }
    
    @ViewBuilder
    private var formSection: some View {
        switch selected {
            case .text: TextForm(onAdd: add)
            case .url: URLForm(onAdd: add)
            case .wifi: WiFiForm(onAdd: add)
            case .contact: ContactForm(onAdd: add)
            case .sms: SMSForm(onAdd: add)
            case .location: LocationForm(onAdd: add)
            case .bluetooth: BluetoothForm(onAdd: add)
            case .phone: PhoneForm(onAdd: add)
            case .email: EmailForm(onAdd: add)
            case .freeform: FreeformForm(onAdd: add)
        }
    }
    
    private var queueSection: some View {
        Section {
            if queued.isEmpty {
                Text("No records queued yet. Fill in the form above and tap “Add record”.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(queued.enumerated()), id: \.offset) { _, payload in
                    let parsed = PayloadParser.parse(payload)
                    NavigationLink {
                        RecordDetailView(record: parsed)
                    } label: {
                        RecordRow(record: parsed)
                    }
                }
                .onDelete { queued.remove(atOffsets: $0) }
            }
        } header: {
            Text("Message to write (\(queued.count))")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Gauge(value: Double(min(estimatedBytes, ntag215Capacity)), in: 0...Double(ntag215Capacity)) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinear)
                .tint(estimatedBytes > ntag215Capacity ? .red : .green)
                Text("≈ \(estimatedBytes) of \(ntag215Capacity) bytes (NTAG215 NDEF capacity)")
                    .font(.caption2)
                    .foregroundStyle(estimatedBytes > ntag215Capacity ? .red : .secondary)
            }
            .padding(.top, 4)
        }
    }
    
    private func add(_ payload: NFCNDEFPayload) {
        queued.append(payload)
    }
}
