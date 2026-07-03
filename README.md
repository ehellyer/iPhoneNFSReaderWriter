# NFC Study

An educational SwiftUI app for reading and writing NTAG21x-family NFC tags (NTAG213, NTAG215, NTAG216) with an iPhone. It exposes the full anatomy of a tag — from parsed NDEF records down to the raw memory pages — lets you compose and write your own records using the same categorized interface, and demonstrates NTAG password protection and permanent locking.

> The Xcode project is named **NFCStudy** (it lives inside the `iPhoneNFSReaderWriter` repository folder).

## Requirements

- Xcode 16 or later
- A physical iPhone 7 or later (Core NFC does not work in the Simulator)
- An Apple ID signed into Xcode (a free personal team is sufficient for NFC tag reading)
- Blank or rewritable NTAG21x cards — the app identifies the exact chip via GET_VERSION and refuses tags it can't positively identify

## Getting started

1. Open `NFCStudy.xcodeproj` in Xcode.
2. Select the **NFCStudy** target → **Signing & Capabilities** → choose your **Team**. Set your bundle ID, you cannot use `com.hellyermultimedia.nfcstudy` and provision the *Near Field Communication Tag Reading* capability automatically.
3. Plug in your iPhone, select it as the run destination, and press **Run**.
4. On first launch on-device you may need to trust the developer certificate: Settings → General → VPN & Device Management.

## What the app does

**Read tab** — starts an `NFCTagReaderSession` and, once a tag is detected:

- Sends the MIFARE `GET_VERSION` (0x60) command to identify the chip and its memory size. Unrecognized chips raise a dismissible alert rather than being guessed at.
- Queries NDEF status (formatted? writable? capacity) and reads the NDEF message.
- Parses each record into a category — Text, URL, WiFi, Contact, SMS, Location, Bluetooth, Phone, Email, or Freeform — with a field-by-field breakdown plus the underlying TNF, type, and raw payload bytes.
- Dumps all memory pages with `FAST_READ` (0x3A) and annotates every page: UID, static/dynamic lock bytes, Capability Container, user memory, CFG0/CFG1, PWD and PACK.
- Detects password protection from the config pages (`AUTH0` in CFG0 and the ACCESS `PROT` bit in CFG1) and reports it — e.g. "NDEF, password-protected (write only, from page 4)". This is necessary because `queryNDEFStatus` reports read/write from the Capability Container, which password protection does not change.
- A **Done** button returns from the results back to the start screen.

**Write tab** — the mirror of the read side. Pick a record category, fill in the same fields you'd see when reading, and queue one or more records into a single NDEF message. A capacity gauge tracks the estimated size against the NDEF capacity reported by the last tag you scanned.

The Write tab also offers two independent controls:

- **Existing protection** — if the tag is already password-protected, turn this on and enter its password. The write authenticates first with `PWD_AUTH` before updating the tag.
- **Card protection** (applied after writing) — one of:
  - **None** — leave the tag freely rewritable. If you authenticated an already-protected tag and choose None, the existing protection is **removed** (PWD/PACK reset to factory defaults, `AUTH0` set back to `0xFF`).
  - **Password** — set a 32-bit (4-byte) password. Entered as text, up to 4 UTF-8 bytes, zero-padded if shorter. Rewriting later requires it via *Existing protection*.
  - **Permanent lock** — permanently set the tag read-only via the one-time-programmable lock bits. Guarded by a destructive confirmation alert; **this cannot be undone**.

## Reading vs. writing password-protected tags — implementation notes

Password protection on NTAG21x is enforced by the config pages (`PWD`, `PACK`, `AUTH0`, ACCESS), not by the Capability Container, which is why it takes deliberate handling:

- **Authentication** uses the raw `PWD_AUTH` (0x1B) command; the tag returns its 2-byte PACK on success and NAKs (throws) on a wrong password.
- **Writing to a protected tag stays entirely in the raw MIFARE channel.** After a raw `PWD_AUTH`, calling any high-level Core NFC NDEF method (`queryNDEFStatus` / `writeNDEF`) corrupts the session and the next transceive fails with "Tag connection lost". So on the authenticated path the app serializes the NDEF message itself, wraps it in a Type-2 TLV (`03 <len> … FE`), and writes it page-by-page with raw `WRITE` (0xA2) — no high-level calls in between. Unprotected writes still use the standard `writeNDEF` path.
- **The password is a 4-byte value.** A typeable string can only express passwords whose bytes form valid, typeable UTF-8, so it cannot represent, for example, the factory default `FF FF FF FF`. Cards set to such values can only be re-authenticated by editing the code.
- Passwords cross the RF link in plaintext during `PWD_AUTH`, so this deters casual rewrites — it is not real security.

## NTAG21x memory map (what the raw view shows)

The layout is the same across the family; only the size of the user-memory region differs. With N total pages (4 bytes each):

| Pages | Contents |
|---|---|
| 0–1 | 7-byte UID + check bytes |
| 2 | UID check byte, internal byte, static lock bytes |
| 3 | Capability Container (`E1` NDEF magic, version, data-area size ÷ 8, access) |
| 4 to N−6 | User memory — NDEF data stored as TLV blocks (`03 <len> <message> FE`) |
| N−5 | Dynamic lock bytes |
| N−4 | CFG0 — mirror config; byte 3 is `AUTH0` (first page requiring authentication) |
| N−3 | CFG1 — ACCESS byte (`PROT` = read+write vs. write-only protection), AUTHLIM |
| N−2 | PWD — 32-bit password (write-only; always reads back as zeros) |
| N−1 | PACK — password acknowledge (write-only; always reads back as zeros) |

Supported chips, identified by the GET_VERSION storage-size byte:

| Chip | Storage byte | Total pages | NDEF capacity |
|---|---|---|---|
| NTAG213 | 0x0F | 45 | 144 bytes |
| NTAG215 | 0x11 | 135 | 496 bytes |
| NTAG216 | 0x13 | 231 | 872 bytes |

## Project layout

- `NFC/NFCService.swift` — tag session handling; raw MIFARE commands (GET_VERSION, FAST_READ, READ, WRITE, PWD_AUTH); NDEF read; NDEF write via both the high-level and raw paths; protection set/clear; permanent lock; and NDEF message serialization.
- `NFC/NTAG21xLayout.swift` — memory-map annotations, region colors, and chip identification (throws for unidentifiable tags).
- `NDEF/PayloadBuilder.swift` — builds NDEF payloads for every category (including WiFi WSC TLVs, vCards, and Bluetooth OOB records).
- `NDEF/PayloadParser.swift` — decodes payloads back into categorized fields.
- `NDEF/URIPrefix.swift` — the NFC Forum URI prefix abbreviation table.
- `Models/` — `RecordCategory`, `ParsedRecord`, `TagInfo`, `ScanResult`.
- `Support/` — `Data+Hex` (hex helpers) and `View+Keyboard` (keyboard dismissal).
- `Views/` — SwiftUI interface (read, record detail, raw memory, write composer and per-type forms).

## Notes and limitations

- **Permanent locking is irreversible and can effectively brick a tag for writing** — use throwaway tags when experimenting with it.
- **Password protection has no recovery path in the app.** If you forget a password you set, or a card is set to a non-typeable value like `FF FF FF FF`, you cannot rewrite it without editing the code.
- Amiibo-style tags are password-protected; their protected pages appear as zeros in the raw dump.
- Password-protection detection assumes reads are open (the write-only protection this app sets). A tag configured for full *read* protection over the config region would report its config bytes as zeros, which can slightly skew the reported protection state — the app does not create that configuration.
- The Bluetooth and WiFi records follow the standard handover/WSC formats, but how a receiving phone acts on them varies by OS.
