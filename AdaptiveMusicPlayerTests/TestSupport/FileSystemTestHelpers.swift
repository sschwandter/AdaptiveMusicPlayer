import Foundation
@testable import AdaptiveMusicPlayerCore
@testable import AdaptiveMusicPlayer

func canonicalTestFileURL(_ url: URL) -> URL {
    url.standardizedFileURL.resolvingSymlinksInPath()
}

struct StubDirectoryTreeEnumerator: DirectoryTreeEnumerating {
    let urls: [URL]

    func recursivelyEnumerateFiles(in folderURL: URL) async throws -> [URL] {
        urls
    }
}

struct StubPlayableAudioFileClassifier: PlayableAudioFileClassifying {
    let playableURLs: Set<URL>

    func isPlayableFile(at url: URL) -> Bool {
        playableURLs.contains(canonicalTestFileURL(url))
    }
}

enum TemporaryFolder {
    static func make() throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }

    static func createSubfolder(named relativePath: String, in rootFolder: URL) throws {
        let folderURL = rootFolder.appending(path: relativePath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    static func writeFile(at url: URL, contents: Data = Data("test".utf8)) throws {
        let parentURL = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try contents.write(to: url)
    }

    static func writeWaveFile(at url: URL) throws {
        try writeFile(at: url, contents: WaveData.make())
    }

    static func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }
}

enum WaveData {
    static func make() -> Data {
        let sampleRate: UInt32 = 44_100
        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 1
        let frameCount: UInt32 = 44
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let dataSize = frameCount * UInt32(channels) * bytesPerSample
        let byteRate = sampleRate * UInt32(channels) * bytesPerSample
        let blockAlign = channels * bitsPerSample / 8

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.appendLE(UInt32(36 + dataSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(channels)
        data.appendLE(sampleRate)
        data.appendLE(byteRate)
        data.appendLE(blockAlign)
        data.appendLE(bitsPerSample)
        data.append("data".data(using: .ascii)!)
        data.appendLE(dataSize)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }
}
