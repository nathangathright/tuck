import Foundation

public typealias CompressionProgressHandler = (Double) -> Void

public struct CompressionPlan: Equatable, Sendable {
    public let mediaInfo: MediaInfo
    public let motionSummary: MotionSummary?
    public let profile: CompressionProfile
}

public struct CompressionResult: Equatable, Sendable {
    public let sourceURL: URL
    public let outputURL: URL
    public let plan: CompressionPlan
}

public final class CompressionService {
    private let tools: MediaTools
    private let fileManager: FileManager

    public init(tools: MediaTools, fileManager: FileManager = .default) {
        self.tools = tools
        self.fileManager = fileManager
    }

    public func planCompression(for sourceURL: URL) async throws -> CompressionPlan {
        let probe = MediaProbe(tools: tools, fileManager: fileManager)
        let mediaInfo = try await probe.inspect(sourceURL)
        let motionSummary = try? await MotionSampler(tools: tools).sample(sourceURL: sourceURL)
        let profile = CompressionProfileSelector.choose(for: mediaInfo, motion: motionSummary)

        return CompressionPlan(
            mediaInfo: mediaInfo,
            motionSummary: motionSummary,
            profile: profile
        )
    }

    public func compress(
        sourceURL: URL,
        progress: @escaping CompressionProgressHandler = { _ in }
    ) async throws -> CompressionResult {
        let plan = try await planCompression(for: sourceURL)
        let outputURL = try OutputNamer.compressedOutputURL(for: sourceURL, fileManager: fileManager)
        let tempURL = temporaryOutputURL(for: outputURL)

        defer {
            try? fileManager.removeItem(at: tempURL)
        }

        let arguments = ffmpegArguments(
            sourceURL: sourceURL,
            tempURL: tempURL,
            plan: plan
        )

        try await runFFmpeg(
            arguments: arguments,
            duration: plan.mediaInfo.duration,
            progress: progress
        )

        _ = try await MediaProbe(tools: tools, fileManager: fileManager).inspect(tempURL)
        try fileManager.moveItem(at: tempURL, to: outputURL)
        progress(1)

        return CompressionResult(
            sourceURL: sourceURL,
            outputURL: outputURL,
            plan: plan
        )
    }

    private func temporaryOutputURL(for outputURL: URL) -> URL {
        let directory = outputURL.deletingLastPathComponent()
        let stem = outputURL.deletingPathExtension().lastPathComponent
        return directory
            .appendingPathComponent(".\(stem).\(UUID().uuidString).tmp")
            .appendingPathExtension("mp4")
    }

    private func ffmpegArguments(
        sourceURL: URL,
        tempURL: URL,
        plan: CompressionPlan
    ) -> [String] {
        var arguments = [
            "-hide_banner",
            "-nostdin",
            "-y",
            "-i", sourceURL.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-map_metadata", "0",
            "-map_chapters", "0",
            "-max_muxing_queue_size", "1024"
        ]

        for subtitle in plan.mediaInfo.mp4CompatibleSubtitleStreams {
            arguments.append(contentsOf: ["-map", "0:\(subtitle.index)"])
        }

        switch plan.profile.videoEncoder {
        case .h264:
            arguments.append(contentsOf: [
                "-c:v", "libx264",
                "-crf", "\(plan.profile.crf)",
                "-preset", plan.profile.preset,
                "-pix_fmt", "yuv420p",
                "-profile:v", "high"
            ])
        case .hevc:
            arguments.append(contentsOf: [
                "-c:v", "libx265",
                "-tag:v", "hvc1",
                "-crf", "\(plan.profile.crf)",
                "-preset", plan.profile.preset,
                "-pix_fmt", "yuv420p",
                "-x265-params", "log-level=warning"
            ])
        }

        arguments.append(contentsOf: [
            "-c:a", "aac",
            "-b:a", plan.profile.audioBitrate
        ])

        if !plan.mediaInfo.mp4CompatibleSubtitleStreams.isEmpty {
            arguments.append(contentsOf: ["-c:s", "mov_text"])
        }

        arguments.append(contentsOf: [
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-stats_period", "0.5",
            tempURL.path
        ])

        return arguments
    }

    private func runFFmpeg(
        arguments: [String],
        duration: TimeInterval?,
        progress: @escaping CompressionProgressHandler
    ) async throws {
        let ffmpegURL = tools.ffmpeg

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = ffmpegURL
            process.arguments = arguments

            let progressPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = progressPipe
            process.standardError = errorPipe

            try process.run()

            let progressTask = Task {
                for try await line in progressPipe.fileHandleForReading.bytes.lines {
                    guard let duration, duration > 0,
                          let seconds = Self.progressSeconds(from: line) else {
                        continue
                    }

                    progress(min(0.99, max(0, seconds / duration)))
                }
            }

            let stderrTask = Task.detached {
                errorPipe.fileHandleForReading.readDataToEndOfFile()
            }

            process.waitUntilExit()
            _ = await progressTask.result

            let stderr = String(decoding: await stderrTask.value, as: UTF8.self)
            guard process.terminationStatus == 0 else {
                throw ProcessExecutionError(
                    executablePath: ffmpegURL.path,
                    arguments: arguments,
                    terminationStatus: process.terminationStatus,
                    standardError: stderr
                )
            }
        }.value
    }

    private static func progressSeconds(from line: String) -> TimeInterval? {
        let pieces = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else { return nil }

        switch pieces[0] {
        case "out_time_us", "out_time_ms":
            guard let microseconds = Double(pieces[1]) else { return nil }
            return microseconds / 1_000_000
        case "out_time":
            return seconds(fromTimestamp: pieces[1])
        default:
            return nil
        }
    }

    private static func seconds(fromTimestamp timestamp: String) -> TimeInterval? {
        let pieces = timestamp.split(separator: ":").map(String.init)
        guard pieces.count == 3,
              let hours = Double(pieces[0]),
              let minutes = Double(pieces[1]),
              let seconds = Double(pieces[2]) else {
            return nil
        }

        return (hours * 3_600) + (minutes * 60) + seconds
    }
}
