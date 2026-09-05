import Foundation

public struct MotionSummary: Equatable, Sendable {
    public let sampledFrameCount: Int
    public let averagePixelDelta: Double
    public let p90PixelDelta: Double
    public let movingFrameRatio: Double

    public init(
        sampledFrameCount: Int,
        averagePixelDelta: Double,
        p90PixelDelta: Double,
        movingFrameRatio: Double
    ) {
        self.sampledFrameCount = sampledFrameCount
        self.averagePixelDelta = averagePixelDelta
        self.p90PixelDelta = p90PixelDelta
        self.movingFrameRatio = movingFrameRatio
    }
}

public final class MotionSampler {
    private let tools: MediaTools

    private static let sampleWidth = 160
    private static let sampleHeight = 90

    public init(tools: MediaTools) {
        self.tools = tools
    }

    public func sample(sourceURL: URL, maxFrames: Int = 18) async throws -> MotionSummary {
        let frameSize = Self.sampleWidth * Self.sampleHeight
        let arguments = [
            "-hide_banner",
            "-nostdin",
            "-v", "error",
            "-i", sourceURL.path,
            "-an",
            "-sn",
            "-dn",
            "-vf", "fps=2,scale=\(Self.sampleWidth):\(Self.sampleHeight):force_original_aspect_ratio=decrease,pad=\(Self.sampleWidth):\(Self.sampleHeight):(ow-iw)/2:(oh-ih)/2,format=gray",
            "-frames:v", "\(maxFrames)",
            "-f", "rawvideo",
            "pipe:1"
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

        let frameCount = output.standardOutput.count / frameSize
        guard frameCount > 1 else {
            return MotionSummary(
                sampledFrameCount: frameCount,
                averagePixelDelta: 0,
                p90PixelDelta: 0,
                movingFrameRatio: 0
            )
        }

        let bytes = [UInt8](output.standardOutput.prefix(frameCount * frameSize))
        var deltas: [Double] = []
        deltas.reserveCapacity(frameCount - 1)

        for frameIndex in 1..<frameCount {
            let previousStart = (frameIndex - 1) * frameSize
            let currentStart = frameIndex * frameSize
            var totalDifference = 0

            for offset in 0..<frameSize {
                totalDifference += abs(Int(bytes[currentStart + offset]) - Int(bytes[previousStart + offset]))
            }

            deltas.append(Double(totalDifference) / Double(frameSize * 255))
        }

        let average = deltas.reduce(0, +) / Double(deltas.count)
        let movingFrames = deltas.filter { $0 >= 0.025 }.count
        let sortedDeltas = deltas.sorted()
        let p90Index = min(sortedDeltas.count - 1, max(0, Int(ceil(Double(sortedDeltas.count) * 0.9)) - 1))

        return MotionSummary(
            sampledFrameCount: frameCount,
            averagePixelDelta: average,
            p90PixelDelta: sortedDeltas[p90Index],
            movingFrameRatio: Double(movingFrames) / Double(deltas.count)
        )
    }
}
