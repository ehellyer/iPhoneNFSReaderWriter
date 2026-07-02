import CoreNFC
import SwiftUI

struct WriteView: View {
    @EnvironmentObject private var nfc: NFCService
    @State private var selected: RecordCategory = .text
    @State private var queued: [NFCNDEFPayload] = []
    @State private var showWriteSuccess = false

    // Card protection — both off by default.
    @State private var protectionChoice: ProtectionChoice = .none
    @State private var passwordHex = ""
    @State private var showLockWarning = false

    enum ProtectionChoice: String, CaseIterable, Identifiable {
        case none = "None"
        case password = "Password"
        case permanentLock = "Permanent lock"
        var id: String { rawValue }
    }
    
    private var estimatedBytes: Int { PayloadBuilder.estimatedSize(of: queued) }

    /// NDEF capacity and model of the most recently scanned tag, if any.
    /// Capacity comes from the tag's own Capability Container, so it is
    /// correct for every NTAG21x model rather than assuming one chip.
    private var knownCapacity: Int? { nfc.lastScan?.info.ndefCapacity }
    private var knownModel: String? { nfc.lastScan?.info.model }

    private var overCapacity: Bool {
        guard let capacity = knownCapacity else { return false }
        return estimatedBytes > capacity
    }

    /// The 4-byte password, or nil if the hex field isn't exactly 8 hex digits.
    private var passwordData: Data? {
        guard let data = Data(hexString: passwordHex), data.count == 4 else { return nil }
        return data
    }

    /// Resolve the UI choice into the service's protection type.
    private var protection: TagProtection {
        switch protectionChoice {
            case .none: return .none
            case .password: return passwordData.map { .password($0) } ?? .none
            case .permanentLock: return .permanentLock
        }
    }

    /// Whether the write button should be blocked by an incomplete protection setup.
    private var protectionIncomplete: Bool {
        protectionChoice == .password && passwordData == nil
    }
    
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

                protectionSection

                Section {
                    Button {
                        nfc.beginWrite(NFCNDEFMessage(records: queued), protection: protection)
                    } label: {
                        Label("Write \(queued.count) record\(queued.count == 1 ? "" : "s") to tag",
                              systemImage: "wave.3.forward.circle.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                    }
                    .disabled(queued.isEmpty || overCapacity || protectionIncomplete)
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
                    protectionChoice = .none
                    passwordHex = ""
                    showWriteSuccess = true
                    nfc.lastWriteSucceeded = false
                }
            }
            .alert("Tag written successfully", isPresented: $showWriteSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Switch to the Read tab and scan the tag to see your records on the card.")
            }
            .alert("Make this tag permanently read-only?", isPresented: $showLockWarning) {
                Button("Cancel", role: .cancel) { protectionChoice = .none }
                Button("Enable permanent lock", role: .destructive) {}
            } message: {
                Text("Permanent locking sets the tag's one-time-programmable lock bits. Once you write with this enabled, the tag can NEVER be rewritten or unlocked — on any device. This is irreversible.")
            }
        }
    }

    private var protectionSection: some View {
        Section {
            Picker("After writing", selection: $protectionChoice) {
                ForEach(ProtectionChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            if protectionChoice == .password {
                TextField("Password (8 hex digits, e.g. FF00AA55)", text: $passwordHex)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                if !passwordHex.isEmpty && passwordData == nil {
                    Text("Enter exactly 8 hexadecimal digits (a 4-byte password).")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Card protection")
        } footer: {
            switch protectionChoice {
                case .none:
                    Text("The tag stays freely rewritable.")
                case .password:
                    Text("Sets a 32-bit password; rewriting later requires it. The password crosses the air gap in plaintext, so this deters casual rewrites rather than providing real security. Store the password — there's no recovery.")
                case .permanentLock:
                    Text("Writes the message, then permanently locks the tag to read-only. This cannot be undone.")
            }
        }
        .onChange(of: protectionChoice) { _, newValue in
            if newValue == .permanentLock { showLockWarning = true }
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
                if let capacity = knownCapacity {
                    Gauge(value: Double(min(estimatedBytes, capacity)), in: 0...Double(capacity)) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryLinear)
                    .tint(overCapacity ? .red : .green)
                    Text("≈ \(estimatedBytes) of \(capacity) bytes (\(knownModel ?? "scanned tag") NDEF capacity)")
                        .font(.caption2)
                        .foregroundStyle(overCapacity ? .red : .secondary)
                } else {
                    Text("≈ \(estimatedBytes) bytes. Scan a tag in the Read tab to see its capacity — the write step also verifies the message fits before writing.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }
    
    private func add(_ payload: NFCNDEFPayload) {
        queued.append(payload)
    }
}
