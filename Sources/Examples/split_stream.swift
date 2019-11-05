//
//  split_stream.swift
//  SwiftFFmpegExamples
//
//  Created by sunlubo on 2019/1/19.
//

import SwiftFFmpeg

private func makeMuxer(stream: Stream) throws -> (FormatContext, Stream) {
    let input = CommandLine.arguments[2]
    let output = "\(input[..<(input.firstIndex(of: ".") ?? input.endIndex)])_\(stream.index).\(stream.codecParameters.codecId.name)"
    print(output)
    
    let muxer = try FormatContext(format: nil, filename: String(output))
    guard let ostream = muxer.addStream() else {
        fatalError("Failed allocating output stream.")
    }
    ostream.codecParameters.copy(from: stream.codecParameters)
    ostream.codecParameters.codecTag = 0
    if !muxer.outputFormat!.flags.contains(.noFile) {
        try muxer.openOutput(url: output, flags: .write)
    }
    return (muxer, ostream)
}

func split_stream() throws {
    if CommandLine.argc < 3 {
        print("Usage: \(CommandLine.arguments[0]) \(CommandLine.arguments[1]) input_file")
        return
    }
    
    let fmtCtx = try FormatContext(url: CommandLine.arguments[2])
    try fmtCtx.findStreamInfo()
    fmtCtx.dumpFormat(isOutput: false)
    
    var streamMapping = [Int: (FormatContext, Stream)]()
    for istream in fmtCtx.streams where istream.mediaType == .audio || istream.mediaType == .video {
        streamMapping[istream.index] = try makeMuxer(stream: istream)
    }
    
    for (_, (muxer, _)) in streamMapping {
        try muxer.writeHeader()
    }
    
    let pkt = Packet()
    while let _ = try? fmtCtx.readFrame(into: pkt) {
        if let (muxer, ostream) = streamMapping[pkt.streamIndex] {
            let istream = fmtCtx.streams[pkt.streamIndex]
            pkt.pts = AVMath.rescale(pkt.pts, istream.timebase, ostream.timebase, Rounding.nearInf.union(.passMinMax))
            pkt.dts = AVMath.rescale(pkt.dts, istream.timebase, ostream.timebase, Rounding.nearInf.union(.passMinMax))
            pkt.duration = AVMath.rescale(pkt.duration, istream.timebase, ostream.timebase)
            pkt.position = -1
            pkt.streamIndex = ostream.index
            try muxer.interleavedWriteFrame(pkt)
        }
        pkt.unref()
    }
    
    for (_, (muxer, _)) in streamMapping {
        try muxer.writeTrailer()
    }
}
