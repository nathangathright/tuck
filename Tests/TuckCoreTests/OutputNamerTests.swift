import XCTest
@testable import TuckCore

final class OutputNamerTests: XCTestCase {
    func testUsesCompressedNameBesideSource() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("Product demo.mov")
        FileManager.default.createFile(atPath: source.path, contents: Data())

        let output = try OutputNamer.compressedOutputURL(for: source)

        XCTAssertEqual(output.deletingLastPathComponent(), directory)
        XCTAssertEqual(output.lastPathComponent, "Product demo - compressed.mp4")
    }

    func testAppendsNumberWithoutOverwriting() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("Clip.mp4")
        let firstOutput = directory.appendingPathComponent("Clip - compressed.mp4")
        FileManager.default.createFile(atPath: source.path, contents: Data())
        FileManager.default.createFile(atPath: firstOutput.path, contents: Data())

        let output = try OutputNamer.compressedOutputURL(for: source)

        XCTAssertEqual(output.lastPathComponent, "Clip - compressed 2.mp4")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TuckTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
