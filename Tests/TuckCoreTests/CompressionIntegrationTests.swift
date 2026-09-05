import XCTest
@testable import TuckCore

final class CompressionIntegrationTests: XCTestCase {
    func testCompressionCreatesDecodableOutputAndLeavesOriginalUnchanged() async throws {
        let tools: MediaTools
        do {
            tools = try MediaToolDiscovery.discover()
        } catch {
            throw XCTSkip("FFmpeg and FFprobe are unavailable on this machine.")
        }

        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("Sample.mov")
        try await makeSampleVideo(at: source, tools: tools)

        let originalData = try Data(contentsOf: source)
        let service = CompressionService(tools: tools)
        let result = try await service.compress(sourceURL: source)

        XCTAssertEqual(result.outputURL.lastPathComponent, "Sample - compressed.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        XCTAssertEqual(try Data(contentsOf: source), originalData)

        let outputInfo = try await MediaProbe(tools: tools).inspect(result.outputURL)
        XCTAssertEqual(outputInfo.width, 320)
        XCTAssertEqual(outputInfo.height, 180)
        XCTAssertTrue(outputInfo.hasAudio)
    }

    private func makeSampleVideo(at url: URL, tools: MediaTools) async throws {
        let arguments = [
            "-hide_banner",
            "-nostdin",
            "-y",
            "-f", "lavfi",
            "-i", "testsrc2=size=320x180:rate=12:duration=1.5",
            "-f", "lavfi",
            "-i", "sine=frequency=880:sample_rate=44100:duration=1.5",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-shortest",
            url.path
        ]

        let output = try await ProcessRunner.run(tools.ffmpeg, arguments: arguments)
        guard output.terminationStatus == 0 else {
            throw ProcessExecutionError(
                executablePath: tools.ffmpeg.path,
                arguments: arguments,
                terminationStatus: output.terminationStatus,
                standardError: String(decoding: output.standardError, as: UTF8.self)
            )
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TuckIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
