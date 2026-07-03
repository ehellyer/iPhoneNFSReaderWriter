//
//  ParsedRecord.swift
//  NFCStudy
//
//  Created by Ed Hellyer on 7/3/26.
//

import Foundation

/// A fully decoded NDEF record, broken into human-readable fields.
struct ParsedRecord: Identifiable {
    struct Field: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }
    
    let id = UUID()
    let category: RecordCategory
    /// Short one-line summary shown in lists.
    let summary: String
    /// Category-specific field breakdown (mirrors the write form fields).
    let fields: [Field]
    /// NDEF plumbing, for the educational detail view.
    let tnfDescription: String
    let typeDescription: String
    let payload: Data
}

/// Basic identity + NDEF status of a scanned tag.
struct TagInfo {
    var uidHex: String
    var model: String
    var totalPages: Int
    var totalBytes: Int { totalPages * 4 }
    var ndefCapacity: Int
    var statusDescription: String
    var isWritable: Bool
}

/// Everything gathered in one scan.
struct ScanResult {
    var info: TagInfo
    var records: [ParsedRecord]
    /// Raw memory, one 4-byte page per element.
    var pages: [Data]
}
