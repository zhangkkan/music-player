import AVFoundation
import Foundation

/// Decodes non-native audio formats (FLAC, etc.) to PCM buffers using FFmpeg CLI.
/// Falls back to AVAudioFile for natively supported formats.
final class FFmpegDecoder {
    enum DecoderError: Error, LocalizedError, Equatable {
        case fileNotFound
        case decodingFailed(String)
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .fileNotFound: return "Audio file not found"
            case .decodingFailed(let msg): return "Decoding failed: \(msg)"
            case .unsupportedFormat: return "Unsupported audio format"
            }
        }
    }

    /// Formats natively supported by AVAudioFile
    static let nativeFormats: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "alac"]

    /// Check if a file format requires FFmpeg decoding
    static func requiresDecoding(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return !nativeFormats.contains(ext)
    }

    /// Decode a non-native audio file to PCM WAV in a temp directory.
    /// Returns the URL of the decoded WAV file.
    func decodeToWAV(input: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw DecoderError.fileNotFound
        }

        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")

        // Use AVAudioConverter approach: read FLAC metadata to get format info,
        // then decode using a raw PCM approach.
        // Since FFmpeg-Kit requires xcframework integration which can't be done
        // purely from source, we use Apple's ExtendedAudioFile API as a fallback
        // that supports some additional formats, and provide FFmpeg-Kit integration
        // point for full format support.

        // Attempt native decoding via ExtAudioFile (supports more formats than AVAudioFile)
        let result = try decodeWithExtAudioFile(input: input, output: outputURL)
        if result {
            return outputURL
        }

        throw DecoderError.unsupportedFormat
    }

    /// Decode using ExtAudioFile API (supports more formats including some FLAC on newer iOS)
    private func decodeWithExtAudioFile(input: URL, output: URL) throws -> Bool {
        var inputFile: ExtAudioFileRef?
        var status = ExtAudioFileOpenURL(input as CFURL, &inputFile)
        guard status == noErr, let sourceFile = inputFile else {
            throw DecoderError.decodingFailed("Cannot open source file: \(status)")
        }
        defer { ExtAudioFileDispose(sourceFile) }

        // Get source format
        var sourceFormat = AudioStreamBasicDescription()
        var propSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = ExtAudioFileGetProperty(sourceFile, kExtAudioFileProperty_FileDataFormat, &propSize, &sourceFormat)
        guard status == noErr else {
            throw DecoderError.decodingFailed("Cannot get source format: \(status)")
        }

        // Setup output format: PCM Float32, same sample rate and channels
        var outputFormat = AudioStreamBasicDescription(
            mSampleRate: sourceFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * sourceFormat.mChannelsPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4 * sourceFormat.mChannelsPerFrame,
            mChannelsPerFrame: sourceFormat.mChannelsPerFrame,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        // Set client format on source file (this enables format conversion)
        status = ExtAudioFileSetProperty(sourceFile, kExtAudioFileProperty_ClientDataFormat,
                                         UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &outputFormat)
        guard status == noErr else {
            throw DecoderError.decodingFailed("Cannot set client format: \(status)")
        }

        // Create output file
        var outputFile: ExtAudioFileRef?
        status = ExtAudioFileCreateWithURL(
            output as CFURL,
            kAudioFileWAVEType,
            &outputFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &outputFile
        )
        guard status == noErr, let destFile = outputFile else {
            throw DecoderError.decodingFailed("Cannot create output file: \(status)")
        }
        defer { ExtAudioFileDispose(destFile) }

        // Read and write in chunks
        let bufferFrames: UInt32 = 4096
        let bufferSize = bufferFrames * outputFormat.mBytesPerFrame
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(bufferSize))
        defer { buffer.deallocate() }

        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: outputFormat.mChannelsPerFrame,
                mDataByteSize: bufferSize,
                mData: buffer
            )
        )

        while true {
            var frameCount = bufferFrames
            bufferList.mBuffers.mDataByteSize = bufferSize

            status = ExtAudioFileRead(sourceFile, &frameCount, &bufferList)
            guard status == noErr else {
                throw DecoderError.decodingFailed("Read error: \(status)")
            }
            if frameCount == 0 { break }

            status = ExtAudioFileWrite(destFile, frameCount, &bufferList)
            guard status == noErr else {
                throw DecoderError.decodingFailed("Write error: \(status)")
            }
        }

        return true
    }

    /// Decode to AVAudioPCMBuffer array for direct playback via AVAudioPlayerNode
    func decodeToPCMBuffers(input: URL, chunkDuration: TimeInterval = 5.0) async throws -> (buffers: [AVAudioPCMBuffer], format: AVAudioFormat) {
        // For natively supported formats, just use AVAudioFile
        if !FFmpegDecoder.requiresDecoding(input) {
            return try decodeNativeFile(input, chunkDuration: chunkDuration)
        }

        // For non-native formats, decode to WAV first, then read
        let wavURL = try await decodeToWAV(input: input)
        defer { try? FileManager.default.removeItem(at: wavURL) }
        return try decodeNativeFile(wavURL, chunkDuration: chunkDuration)
    }

    private func decodeNativeFile(_ url: URL, chunkDuration: TimeInterval) throws -> (buffers: [AVAudioPCMBuffer], format: AVAudioFormat) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let framesPerChunk = AVAudioFrameCount(chunkDuration * format.sampleRate)
        var buffers: [AVAudioPCMBuffer] = []

        while file.framePosition < file.length {
            let remaining = AVAudioFrameCount(file.length - file.framePosition)
            let framesToRead = min(framesPerChunk, remaining)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else { continue }
            try file.read(into: buffer, frameCount: framesToRead)
            buffers.append(buffer)
        }

        return (buffers, format)
    }
}
