//
//  WriteView.swift
//  NFCStudy
//
//  Created by Ed Hellyer on 7/3/26.
//

import CoreNFC
import SwiftUI

struct WriteView: View {
    @EnvironmentObject private var nfc: NFCService
    @State private var selected: RecordCategory = .text
    @State private var queued: [NFCNDEFPayload] = []
    @State private var showWriteSuccess = false

    // Card protection — both off by default.
    @State private var protectionChoice: ProtectionChoice = .none
    @State private var passwordText = ""
    @State private var showLockWarning = false

    // Authenticating to an already-protected tag before writing — off by default.
    @State private var useExistingPassword = false
    @State private var existingPasswordText = ""

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

    /// NTAG passwords are exactly 4 bytes. Convert a user string (already
    /// capped to ≤ 4 UTF-8 bytes) into that 4-byte value, padding short
    /// passwords with zero bytes. Setting and authenticating share this so
    /// the same typed text always maps to the same password.
    private func passwordBytes(_ text: String) -> Data {
        var data = Data(text.utf8.prefix(4))
        while data.count < 4 { data.append(0x00) }
        return data
    }

    /// Trim a string so its UTF-8 encoding never exceeds 4 bytes.
    private func cappedToFourBytes(_ text: String) -> String {
        var trimmed = text
        while Data(trimmed.utf8).count > 4 { trimmed.removeLast() }
        return trimmed
    }

    /// The 4-byte password to set, or nil if the field is empty.
    private var passwordData: Data? {
        passwordText.isEmpty ? nil : passwordBytes(passwordText)
    }

    /// The password to authenticate with before writing, if enabled.
    private var authPassword: Data? {
        (useExistingPassword && !existingPasswordText.isEmpty) ? passwordBytes(existingPasswordText) : nil
    }

    /// Resolve the UI choice into the service's protection type.
    private var protection: TagProtection {
        switch protectionChoice {
            case .none: return .none
            case .password: return passwordData.map { .password($0) } ?? .none
            case .permanentLock: return .permanentLock
        }
    }

    /// Whether the write button should be blocked by an incomplete setup:
    /// a chosen-but-empty new password, or "protected" toggled on with no password.
    private var protectionIncomplete: Bool {
        (protectionChoice == .password && passwordData == nil)
            || (useExistingPassword && existingPasswordText.isEmpty)
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

                authenticationSection

                protectionSection

                Section {
                    Button {
                        nfc.beginWrite(NFCNDEFMessage(records: queued),
                                       protection: protection,
                                       authPassword: authPassword)
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
                    passwordText = ""
                    useExistingPassword = false
                    existingPasswordText = ""
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
            .alert("NFC problem", isPresented: Binding(
                get: { nfc.errorMessage != nil },
                set: { if !$0 { nfc.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(nfc.errorMessage ?? "")
            }
        }
    }

    private var authenticationSection: some View {
        Section {
            Toggle("Tag is password-protected", isOn: $useExistingPassword)
            if useExistingPassword {
                TextField("Existing password (up to 4 characters)", text: $existingPasswordText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: existingPasswordText) { _, newValue in
                        existingPasswordText = cappedToFourBytes(newValue)
                    }
            }
        } header: {
            Text("Existing protection")
        } footer: {
            Text("If this tag was already password-protected, turn this on and enter its password. The write authenticates first (PWD_AUTH), then updates the tag. If you leave “Card protection” below on None, the existing password is removed after writing; choose Password there to set a new one instead.")
        }
    }

    private var protectionSection: some View {
        Section {
            Picker("After writing", selection: $protectionChoice) {
                ForEach(ProtectionChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            if protectionChoice == .password {
                TextField("Password (up to 4 characters)", text: $passwordText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: passwordText) { _, newValue in
                        passwordText = cappedToFourBytes(newValue)
                    }
            }
        } header: {
            Text("Card protection")
        } footer: {
            switch protectionChoice {
                case .none:
                    Text("The tag stays freely rewritable.")
                case .password:
                    Text("Sets a 32-bit (4-byte) password; up to 4 characters, padded with zeros if shorter. Rewriting later requires it via the “Existing protection” option above. The password crosses the air gap in plaintext, so this deters casual rewrites rather than providing real security — and there's no recovery, so store it.")
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
