import CoreNFC
import Foundation

/// Drives NFC tag sessions for both reading and writing NTAG215 tags.
/// Uses `NFCTagReaderSession` so we can combine NDEF-level access with
/// raw MIFARE Ultralight commands (GET_VERSION, FAST_READ).
final class NFCService: NSObject, ObservableObject {
    
    @Published var lastScan: ScanResult?
    @Published var statusMessage: String?
    @Published var lastWriteSucceeded = false
    
    var isAvailable: Bool { NFCTagReaderSession.readingAvailable }
    
    private var session: NFCTagReaderSession?
    private var pendingWrite: NFCNDEFMessage?
    
    private enum Mode { case read, write }
    private var mode: Mode = .read
    
    // MARK: Public API
    
    func beginRead() {
        mode = .read
        start(alert: "Hold your iPhone near the tag to read it.")
    }
    
    func beginWrite(_ message: NFCNDEFMessage) {
        mode = .write
        pendingWrite = message
        start(alert: "Hold your iPhone near the tag to write \(message.length) bytes.")
    }
    
    private func start(alert: String) {
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
        let model = NTAG215Layout.model(forStorageByte: versionByte)
        
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
                session.invalidate(errorMessage: "Tag is not NDEF formatted. Factory-fresh NTAG215 cards ship formatted; this one may be damaged or a different chip.")
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
        session.alertMessage = "Write complete ✓ (\(message.length) of \(capacity) bytes used)"
        session.invalidate()
        await MainActor.run {
            self.pendingWrite = nil
            self.lastWriteSucceeded = true
            self.statusMessage = nil
        }
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
            session.invalidate(errorMessage: "Unsupported tag type — expected an NTAG215 (MIFARE Ultralight family).")
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
