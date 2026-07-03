//
//  RawMemoryView.swift
//  NFCStudy
//
//  Created by Ed Hellyer on 7/3/26.
//

import SwiftUI

struct RawMemoryView: View {
    let pages: [Data]
    let totalPages: Int
    
    var body: some View {
        List {
            Section {
                legend
            }
            Section("Pages") {
                ForEach(pages.indices, id: \.self) { index in
                    pageRow(index)
                }
            }
        }
        .navigationTitle("Raw Memory")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow(.uid)
            legendRow(.lock)
            legendRow(.capability)
            legendRow(.user)
            legendRow(.config)
        }
        .font(.caption)
        .padding(.vertical, 4)
    }
    
    private func legendRow(_ region: NTAG21xLayout.Region) -> some View {
        HStack(spacing: 8) {
            Circle().fill(region.color).frame(width: 8, height: 8)
            Text(region.rawValue)
        }
    }
    
    private func pageRow(_ index: Int) -> some View {
        let region = NTAG21xLayout.region(forPage: index, totalPages: totalPages)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Circle().fill(region.color).frame(width: 8, height: 8)
                Text(String(format: "%3d  0x%02X", index, index))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(pages[index].spacedHexString)
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                Spacer()
                Text(pages[index].asciiPreview)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(NTAG21xLayout.annotation(forPage: index, totalPages: totalPages))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 18)
        }
        .padding(.vertical, 1)
    }
}
