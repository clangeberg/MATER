#!/usr/bin/env swift

import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icns.swift INPUT.iconset OUTPUT.icns\n".utf8))
    exit(64)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let entries: [(type: String, file: String)] = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var encoded = value.bigEndian
    withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
}

var chunks = Data()
for entry in entries {
    let fileURL = iconset.appendingPathComponent(entry.file)
    let png = try Data(contentsOf: fileURL)
    guard let type = entry.type.data(using: .ascii), type.count == 4 else {
        throw CocoaError(.fileWriteUnknown)
    }
    chunks.append(type)
    appendBigEndian(UInt32(png.count + 8), to: &chunks)
    chunks.append(png)
}

var icns = Data("icns".utf8)
appendBigEndian(UInt32(chunks.count + 8), to: &icns)
icns.append(chunks)
try icns.write(to: outputURL, options: .atomic)
