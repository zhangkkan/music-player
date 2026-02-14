import Foundation

struct SimpleZipEntry {
    let path: String
    let data: Data
    let crc32: UInt32
}

final class SimpleZipWriter {
    private var entries: [SimpleZipEntry] = []

    func addFile(path: String, data: Data) {
        let crc = CRC32.checksum(data)
        entries.append(SimpleZipEntry(path: path, data: data, crc32: crc))
    }

    func finalize() -> Data {
        var fileData = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let fileNameData = entry.path.data(using: .utf8) ?? Data()

            // Local file header
            fileData.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // signature
            fileData.append(le16(20)) // version needed
            fileData.append(le16(0)) // flags
            fileData.append(le16(0)) // compression method (store)
            fileData.append(le16(0)) // mod time
            fileData.append(le16(0)) // mod date
            fileData.append(le32(entry.crc32))
            fileData.append(le32(UInt32(entry.data.count)))
            fileData.append(le32(UInt32(entry.data.count)))
            fileData.append(le16(UInt16(fileNameData.count)))
            fileData.append(le16(0)) // extra length
            fileData.append(fileNameData)
            fileData.append(entry.data)

            // Central directory header
            centralDirectory.append(contentsOf: [0x50, 0x4B, 0x01, 0x02]) // signature
            centralDirectory.append(le16(20)) // version made by
            centralDirectory.append(le16(20)) // version needed
            centralDirectory.append(le16(0)) // flags
            centralDirectory.append(le16(0)) // compression method
            centralDirectory.append(le16(0)) // mod time
            centralDirectory.append(le16(0)) // mod date
            centralDirectory.append(le32(entry.crc32))
            centralDirectory.append(le32(UInt32(entry.data.count)))
            centralDirectory.append(le32(UInt32(entry.data.count)))
            centralDirectory.append(le16(UInt16(fileNameData.count)))
            centralDirectory.append(le16(0)) // extra length
            centralDirectory.append(le16(0)) // comment length
            centralDirectory.append(le16(0)) // disk number
            centralDirectory.append(le16(0)) // internal attrs
            centralDirectory.append(le32(0)) // external attrs
            centralDirectory.append(le32(offset))
            centralDirectory.append(fileNameData)

            offset = UInt32(fileData.count)
        }

        let centralDirectoryOffset = UInt32(fileData.count)
        fileData.append(centralDirectory)

        // End of central directory
        fileData.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        fileData.append(le16(0)) // disk number
        fileData.append(le16(0)) // start disk
        fileData.append(le16(UInt16(entries.count)))
        fileData.append(le16(UInt16(entries.count)))
        fileData.append(le32(UInt32(centralDirectory.count)))
        fileData.append(le32(centralDirectoryOffset))
        fileData.append(le16(0)) // comment length

        return fileData
    }

    private func le16(_ value: UInt16) -> Data {
        var v = value
        return Data(bytes: &v, count: 2)
    }

    private func le32(_ value: UInt32) -> Data {
        var v = value
        return Data(bytes: &v, count: 4)
    }
}

final class SimpleZipReader {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func extractAll() -> [String: Data] {
        guard let eocdRange = findEndOfCentralDirectory() else { return [:] }
        let eocdOffset = eocdRange.lowerBound
        let centralDirOffset = readUInt32(at: eocdOffset + 16)
        let centralDirSize = readUInt32(at: eocdOffset + 12)
        if centralDirOffset + centralDirSize > data.count { return [:] }

        var results: [String: Data] = [:]
        var cursor = Int(centralDirOffset)
        let end = Int(centralDirOffset + centralDirSize)

        while cursor + 46 <= end {
            if data[cursor] != 0x50 || data[cursor + 1] != 0x4B || data[cursor + 2] != 0x01 || data[cursor + 3] != 0x02 {
                break
            }
            let nameLen = Int(readUInt16(at: cursor + 28))
            let extraLen = Int(readUInt16(at: cursor + 30))
            let commentLen = Int(readUInt16(at: cursor + 32))
            let localOffset = Int(readUInt32(at: cursor + 42))
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLen
            guard nameEnd <= end else { break }
            let nameData = data.subdata(in: nameStart..<nameEnd)
            let name = String(data: nameData, encoding: .utf8) ?? ""

            if let fileData = readLocalFile(at: localOffset) {
                results[name] = fileData
            }
            cursor = nameEnd + extraLen + commentLen
        }

        return results
    }

    private func readLocalFile(at offset: Int) -> Data? {
        if offset + 30 > data.count { return nil }
        if data[offset] != 0x50 || data[offset + 1] != 0x4B || data[offset + 2] != 0x03 || data[offset + 3] != 0x04 {
            return nil
        }
        let nameLen = Int(readUInt16(at: offset + 26))
        let extraLen = Int(readUInt16(at: offset + 28))
        let compSize = Int(readUInt32(at: offset + 18))
        let start = offset + 30 + nameLen + extraLen
        let end = start + compSize
        if end > data.count { return nil }
        return data.subdata(in: start..<end)
    }

    private func findEndOfCentralDirectory() -> Range<Int>? {
        let signature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        let maxScan = max(0, data.count - 22 - 1024)
        var i = data.count - 4
        while i >= maxScan {
            if data[i] == signature[0],
               data[i + 1] == signature[1],
               data[i + 2] == signature[2],
               data[i + 3] == signature[3] {
                return i..<(i + 22)
            }
            i -= 1
        }
        return nil
    }

    private func readUInt16(at index: Int) -> UInt16 {
        let slice = data.subdata(in: index..<(index + 2))
        return slice.withUnsafeBytes { $0.load(as: UInt16.self) }
    }

    private func readUInt32(at index: Int) -> UInt32 {
        let slice = data.subdata(in: index..<(index + 4))
        return slice.withUnsafeBytes { $0.load(as: UInt32.self) }
    }
}

enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in data {
            let idx = Int((crc ^ UInt32(b)) & 0xFF)
            crc = table[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
