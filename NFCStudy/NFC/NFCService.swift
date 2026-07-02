import CoreNFC
import Foundation

/// What (if anything) to do to a tag's protection bits after writing its NDEF
/// message. Both options are off by default and set on the Write screen.
enum TagProtection: Equatable {
    /// Leave the tag freely rewritable.
    case none
    /// Set a 4-byte (32-bit) password. Rewriting later requires PWD_AUTH with
    /// this password. Reversible if you know the password. NOTE: the password
    /// crosses the RF link in plaintext — this deters casual rewrites, it is
    /// not real security.
    case password(Data)
    /// Permanently set the tag read-only via the one-time-programmable lock
    /// bits. This CANNOT be undone.
    case permanentLock
}

/// Thrown when applying protection to a tag fails.
enum ProtectionError: LocalizedError {
    case passwordNotFourBytes

    var errorDescription: String? {
        switch self {
            case .passwordNotFourBytes:
                return "The password must be exactly 4 bytes (8 hex digits)."
        }
    }
}

/// Drives NFC tag sessions for both reading and writing NTAG21x-family tags.
/// Uses `NFCTagReaderSession` so we can combine NDEF-level access with
/// raw MIFARE Ultralight commands (GET_VERSION, FAST_READ).
final class NFCService: NSObject, ObservableObject {
    
    @Published var lastScan: ScanResult?
    @Published var statusMessage: String?
    @Published var lastWriteSucceeded = false
    /// A read/identification failure to surface as an alert dialog.
    @Published var errorMessage: String?
    
    var isAvailable: Bool { NFCTagReaderSession.readingAvailable }
    
    private var session: NFCTagReaderSession?
    private var pendingWrite: NFCNDEFMessage?
    private var pendingProtection: TagProtection = .none

    private enum Mode { case read, write }
    private var mode: Mode = .read
    
    // MARK: Public API
    
    func beginRead() {
        mode = .read
        start(alert: "Hold your iPhone near the tag to read it.")
    }
    
    func beginWrite(_ message: NFCNDEFMessage, protection: TagProtection = .none) {
        mode = .write
        pendingWrite = message
        pendingProtection = protection
        let suffix: String
        switch protection {
            case .none: suffix = ""
            case .password: suffix = " and password-protect it"
            case .permanentLock: suffix = " and permanently lock it"
        }
        start(alert: "Hold your iPhone near the tag to write \(message.length) bytes\(suffix).")
    }
    
    private func start(alert: String) {
        errorMessage = nil
        guard isAvailable else {
            statusMessage = "NFC is not available on this device (requires a physical iPhone 7 or later)."
            return
        }
        session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: nil)
        session?.alertMessage = alert
        session?.begin()
    }
    
    // MARK: Tag handling
    
    private func handle(tag: NFCMiFareTag, session: NFCTagReaderSession) async {
        guard tag.mifareFamily == .ultralight else {
            session.invalidate(errorMessage: "This is not an NTAG21x / MIFARE Ultralight tag.")
            return
        }
        do {
            switch mode {
                case .read:
                    let result = try await readEverything(from: tag)
                    session.alertMessage = "Read complete ✓"
                    session.invalidate()
                    await MainActor.run {
                        self.lastScan = result
                        self.statusMessage = nil
                    }
                case .write:
                    try await write(to: tag, session: session)
            }
        } catch {
            session.invalidate(errorMessage: error.localizedDescription)
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }
    
    // MARK: Reading
    
    private func readEverything(from tag: NFCMiFareTag) async throws -> ScanResult {
        // 1. GET_VERSION (0x60) identifies the exact chip and memory size.
        let versionByte: UInt8?
        if let version = try? await tag.sendMiFareCommand(commandPacket: Data([0x60])),
           version.count >= 7 {
            versionByte = version[6]
        } else {
            versionByte = nil
        }
        let model = try NTAG21xLayout.model(forStorageByte: versionByte)
        
        // 2. NDEF status + records.
        let (status, capacity) = try await tag.queryNDEFStatus()
        var records: [ParsedRecord] = []
        var statusDescription: String
        switch status {
            case .notSupported:
                statusDescription = "Not NDEF formatted"
            case .readOnly:
                statusDescription = "NDEF, read-only (permanently locked)"
            case .readWrite:
                statusDescription = "NDEF, read/write"
            @unknown default:
                statusDescription = "Unknown"
        }
        if status != .notSupported {
            if let message = try? await tag.readNDEF() {
                records = PayloadParser.parse(message)
            } else {
                statusDescription += " (empty — no NDEF message)"
            }
        }
        
        // 3. Raw memory dump via FAST_READ (0x3A), in 32-page chunks.
        let pages = await readAllPages(from: tag, totalPages: model.pages)
        
        let info = TagInfo(uidHex: tag.identifier.map { String(format: "%02X", $0) }.joined(separator: ":"),
                           model: model.name,
                           totalPages: model.pages,
                           ndefCapacity: capacity,
                           statusDescription: statusDescription,
                           isWritable: status == .readWrite)
        return ScanResult(info: info, records: records, pages: pages)
    }
    
    private func readAllPages(from tag: NFCMiFareTag, totalPages: Int) async -> [Data] {
        var bytes = Data()
        var page = 0
        let chunkSize = 32
        while page < totalPages {
            let last = min(page + chunkSize, totalPages) - 1
            let command = Data([0x3A, UInt8(page), UInt8(last)]) // FAST_READ start..end
            let expected = (last - page + 1) * 4
            if let response = try? await tag.sendMiFareCommand(commandPacket: command),
               response.count == expected {
                bytes.append(response)
            } else {
                // Password-protected or unreadable region — show as zeros.
                bytes.append(Data(count: expected))
            }
            page = last + 1
        }
        return stride(from: 0, to: bytes.count, by: 4).map {
            bytes.subdata(in: $0..<Swift.min($0 + 4, bytes.count))
        }
    }
    
    // MARK: Writing
    
    private func write(to tag: NFCMiFareTag, session: NFCTagReaderSession) async throws {
        guard let message = pendingWrite else {
            session.invalidate(errorMessage: "Nothing queued to write.")
            return
        }
        let (status, capacity) = try await tag.queryNDEFStatus()
        switch status {
            case .notSupported:
                session.invalidate(errorMessage: "Tag is not NDEF formatted. Factory-fresh NTAG21x cards ship formatted; this one may be damaged or a different chip.")
                return
            case .readOnly:
                session.invalidate(errorMessage: "Tag is permanently locked (read-only).")
                return
            default:
                break
        }
        guard message.length <= capacity else {
            session.invalidate(errorMessage: "Message is \(message.length) bytes but the tag holds only \(capacity) bytes.")
            return
        }
        try await tag.writeNDEF(message)

        // Apply protection (if any) after the NDEF message is safely written.
        var protectionNote = ""
        switch pendingProtection {
            case .none:
                break
            case .password(let password):
                let pages = try await chipPageCount(of: tag)
                try await applyPassword(password, to: tag, totalPages: pages)
                protectionNote = " · password set"
            case .permanentLock:
                try await tag.writeLock()
                protectionNote = " · permanently locked"
        }

        session.alertMessage = "Write complete ✓ (\(message.length) of \(capacity) bytes)\(protectionNote)"
        session.invalidate()
        await MainActor.run {
            self.pendingWrite = nil
            self.pendingProtection = .none
            self.lastWriteSucceeded = true
            self.statusMessage = nil
        }
    }

    // MARK: Protection

    /// Re-runs GET_VERSION to learn the tag's page count, needed to locate the
    /// configuration pages (which sit at the very end of memory).
    private func chipPageCount(of tag: NFCMiFareTag) async throws -> Int {
        let versionByte: UInt8?
        if let version = try? await tag.sendMiFareCommand(commandPacket: Data([0x60])),
           version.count >= 7 {
            versionByte = version[6]
        } else {
            versionByte = nil
        }
        return try NTAG21xLayout.model(forStorageByte: versionByte).pages
    }

    /// Set a 32-bit password on the tag and require authentication for writes
    /// from page 4 upward. Pages are read-modify-written so we don't clobber
    /// the mirror/config bytes we aren't changing. AUTH0 is written LAST,
    /// because once it takes effect the config pages themselves become
    /// password-protected.
    private func applyPassword(_ password: Data, to tag: NFCMiFareTag, totalPages n: Int) async throws {
        guard password.count == 4 else { throw ProtectionError.passwordNotFourBytes }
        let cfg0 = UInt8(n - 4)   // MIRROR / … / AUTH0 (byte 3)
        let pwdPage = UInt8(n - 2)
        let packPage = UInt8(n - 1)

        // 1. PWD — the 4-byte password.
        _ = try await tag.sendMiFareCommand(commandPacket: Data([0xA2, pwdPage]) + password)
        // 2. PACK — password acknowledge (0x0000) + RFUI.
        _ = try await tag.sendMiFareCommand(commandPacket: Data([0xA2, packPage, 0x00, 0x00, 0x00, 0x00]))
        // 3. CFG0 — read current 4 bytes, then set AUTH0 (byte 3) = 0x04 so
        //    pages 4+ require authentication for writes. PROT bit in CFG1 is
        //    left at its default 0 = protect writes only (reads stay open).
        let cfg0Read = try await tag.sendMiFareCommand(commandPacket: Data([0x30, cfg0])) // READ returns 16 bytes
        guard cfg0Read.count >= 4 else { throw ProtectionError.passwordNotFourBytes }
        _ = try await tag.sendMiFareCommand(commandPacket: Data([0xA2, cfg0, cfg0Read[0], cfg0Read[1], cfg0Read[2], 0x04]))
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension NFCService: NFCTagReaderSessionDelegate {
    
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let nfcError = error as? NFCReaderError
        let userCancelled = nfcError?.code == .readerSessionInvalidationErrorUserCanceled
        let successful = nfcError?.code == .readerSessionInvalidationErrorFirstNDEFTagRead
        DispatchQueue.main.async {
            if !userCancelled && !successful,
               (error as NSError).localizedDescription.contains("Session invalidated") == false {
                self.statusMessage = error.localizedDescription
            }
            self.session = nil
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let first = tags.first, case let .miFare(tag) = first else {
            session.invalidate(errorMessage: "Unsupported tag type — expected an NTAG21x (MIFARE Ultralight family) tag.")
            return
        }
        Task {
            do {
                try await session.connect(to: first)
                await self.handle(tag: tag, session: session)
            } catch {
                session.invalidate(errorMessage: "Connection failed: \(error.localizedDescription)")
            }
        }
    }
}
