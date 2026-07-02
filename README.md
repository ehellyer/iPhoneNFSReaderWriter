# NFC Study

An educational SwiftUI app for reading and writing NTAG21x-family NFC tags (NTAG213, NTAG215, NTAG216) with an iPhone. It exposes the full anatomy of a tag — from parsed NDEF records down to the raw memory pages — and lets you compose and write your own records using the same categorized interface.

## Requirements

- Xcode 16 or later
- A physical iPhone 7 or later (Core NFC does not work in the Simulator)
- An Apple ID signed into Xcode (a free personal team is sufficient for NFC tag reading)
- Blank or rewritable NTAG21x cards — the app identifies the exact chip via GET_VERSION and refuses tags it can't positively identify

## Getting started

1. Open `NFCStudy.xcodeproj` in Xcode.
2. Select the **NFCStudy** target → **Signing & Capabilities** → choose your **Team**. Xcode will register the bundle ID `com.hellyermultimedia.nfcstudy` and provision the *Near Field Communication Tag Reading* capability automatically.
3. Plug in your iPhone, select it as the run destination, and press **Run**.
4. On first launch on-device you may need to trust the developer certificate: Settings → General → VPN & Device Management.

## What the app does

**Read tab** — starts an `NFCTagReaderSession` and, once a tag is detected:

- Sends the MIFARE `GET_VERSION` (0x60) command to identify the chip and its memory size. Unrecognized chips raise an alert rather than being guessed at.
- Queries NDEF status (formatted? writable? capacity) and reads the NDEF message.
- Parses each record into a category — Text, URL, WiFi, Contact, SMS, Location, Bluetooth, Phone, Email, or Freeform — with a field-by-field breakdown plus the underlying TNF, type, and raw payload bytes.
- Dumps all memory pages with `FAST_READ` (0x3A) and annotates every page: UID, static/dynamic lock bytes, Capability Container, user memory, CFG0/CFG1, PWD and PACK.

**Write tab** — the mirror of the read side. Pick a record category, fill in the same fields you'd see when reading, and queue one or more records into a single NDEF message. A capacity gauge tracks the estimated size against the NDEF capacity reported by the last tag you scanned. Tapping *Write* verifies the tag is NDEF-formatted, writable, and large enough before writing.

## NTAG21x memory map (what the raw view shows)

The layout is the same across the family; only the size of the user-memory region differs. With N total pages (4 bytes each):

| Pages | Contents |
|---|---|
| 0–1 | 7-byte UID + check bytes |
| 2 | UID check byte, internal byte, static lock bytes |
| 3 | Capability Container (`E1` NDEF magic, version, data-area size ÷ 8, access) |
| 4 to N−6 | User memory — NDEF data stored as TLV blocks (`03 <len> <message> FE`) |
| N−5 | Dynamic lock bytes |
| N−4 to N−3 | CFG0 / CFG1 (UID mirroring, password protection settings) |
| N−2 to N−1 | PWD and PACK (write-only; always read back as zeros) |

Supported chips, identified by the GET_VERSION storage-size byte:

| Chip | Storage byte | Total pages | NDEF capacity |
|---|---|---|---|
| NTAG213 | 0x0F | 45 | 144 bytes |
| NTAG215 | 0x11 | 135 | 496 bytes |
| NTAG216 | 0x13 | 231 | 872 bytes |

## Project layout

- `NFC/NFCService.swift` — tag session handling, raw MIFARE commands, NDEF read/write
- `NFC/NTAG21xLayout.swift` — memory-map annotations and chip identification
- `NDEF/PayloadBuilder.swift` — builds NDEF payloads for every category (including WiFi WSC TLVs, vCards, and Bluetooth OOB records)
- `NDEF/PayloadParser.swift` — decodes payloads back into categorized fields
- `NDEF/URIPrefix.swift` — the NFC Forum URI prefix abbreviation table
- `Views/` — SwiftUI interface (read, raw memory, write composer and per-type forms)

## Notes and limitations

- Writing uses the standard NDEF path (`writeNDEF`), so it works on any NDEF-formatted NTAG21x tag. It does not send raw `WRITE` commands to configuration pages, so it cannot lock, password-protect, or brick a tag.
- Amiibo-style tags are password-protected; their protected pages appear as zeros in the raw dump.
- The Bluetooth and WiFi records follow the standard handover/WSC formats, but how a receiving phone acts on them varies by OS.
