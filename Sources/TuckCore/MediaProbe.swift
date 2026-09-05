import Foundation

public struct AudioStreamInfo: Equatable, Sendable {
    public let index: Int
    public let codecName: String
}

public struct SubtitleStreamInfo: Equatable, Sendable {
    public let index: Int
    public let codecName: String

    public var canTranscodeToMP4Text: Bool {
        Self.mp4TextCompatibleCodecs.contains(codecName.lowercased())
    }

    private static let mp4TextCompatibleCodecs: Set<String> = [
        "ass",
        "mov_text",
        "ssa",
        "subrip",
        "text",
        "webvtt"
    ]
}

public struct MediaInfo: Equatable, Sendable {
    public let videoCodec: String
    public let width: Int
    public let height: Int
    public let frameRate: Double?
    public let duration: TimeInterval?
    public let audioStreams: [AudioStreamInfo]
    public let subtitleStreams: [SubtitleStreamInfo]
    public let fileSize: Int64

    public var hasAudio: Bool {
        !audioStreams.isEmpty
    }

    public var hasSubtitles: Bool {
        !subtitleStreams.isEmpty
    }

    public var mp4CompatibleSubtitleStreams: [SubtitleStreamInfo] {
        subtitleStreams.filter(\.canTranscodeToMP4Text)
    }

    public var isFourKOrLarger: Bool {
        width >= 3_840 || height >= 2_160 || width * height >= 8_294_400
    }

    public init(
        videoCodec: String,
        width: Int,
        height: Int,
        frameRate: Double?,
        duration: TimeInterval?,
        audioStreams: [AudioStreamInfo],
        subtitleStreams: [SubtitleStreamInfo],
        fileSize: Int64
    ) {
        self.videoCodec = videoCodec
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.duration = duration
        self.audioStreams = audioStreams
        self.subtitleStreams = subtitleStreams
        self.fileSize = fileSize
    }
}

public enum MediaProbeError: LocalizedError, Sendable {
    case noVideoStream(URL)
    case unreadableOutput(URL)

    public var errorDescription: String? {
        switch self {
        case .noVideoStream(let url):
            return "\(url.lastPathComponent) does not contain a readable video stream."
        case .unreadableOutput(let url):
            return "FFprobe returned unreadable metadata for \(url.lastPathComponent)."
        }
    }
}

public final class MediaProbe {
    private let tools: MediaTools
    private let fileManager: FileManager

    public init(tools: MediaTools, fileManager: FileManager = .default) {
        self.tools = tools
        self.fileManager = fileManager
    }

    public func inspect(_ sourceURL: URL) async throws -> MediaInfo {
        let arguments = [
            "-v", "error",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            sourceURL.path
        ]
        let output = try await ProcessRunner.run(tools.ffprobe, arguments: arguments)
        guard output.terminationStatus == 0 else {
            throw ProcessExecutionError(
                executablePath: tools.ffprobe.path,
                arguments: arguments,
                terminationStatus: output.terminationStatus,
                standardError: String(decoding: output.standardError, as: UTF8.self)
            )
        }

        let response: FFProbeResponse
        do {
            response = try JSONDecoder().decode(FFProbeResponse.self, from: output.standardOutput)
        } catch {
            throw MediaProbeError.unreadableOutput(sourceURL)
        }

        guard let video = response.streams.first(where: {
            $0.codecType == "video" && ($0.width ?? 0) > 0 && ($0.height ?? 0) > 0
        }) else {
            throw MediaProbeError.noVideoStream(sourceURL)
        }

        let audioStreams = response.streams
            .filter { $0.codecType == "audio" }
            .map { AudioStreamInfo(index: $0.index, codecName: $0.codecName ?? "unknown") }

        let subtitleStreams = response.streams
            .filter { $0.codecType == "subtitle" }
            .map { SubtitleStreamInfo(index: $0.index, codecName: $0.codecName ?? "unknown") }

        return MediaInfo(
            videoCodec: video.codecName ?? "unknown",
            width: video.width ?? 0,
            height: video.height ?? 0,
            frameRate: Self.parseFrameRate(video.avgFrameRate) ?? Self.parseFrameRate(video.rFrameRate),
            duration: Self.parseDuration(video.duration) ?? Self.parseDuration(response.format?.duration),
            audioStreams: audioStreams,
            subtitleStreams: subtitleStreams,
            fileSize: try sourceFileSize(sourceURL, response: response)
        )
    }

    private func sourceFileSize(_ sourceURL: URL, response: FFProbeResponse) throws -> Int64 {
        if let formatSize = response.format?.size, let size = Int64(formatSize) {
            return size
        }

        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private static func parseDuration(_ rawValue: String?) -> TimeInterval? {
        guard let rawValue, let value = Double(rawValue), value.isFinite else {
            return nil
        }
        return value
    }

    private static func parseFrameRate(_ rawValue: String?) -> Double? {
        guard let rawValue, !rawValue.isEmpty, rawValue != "0/0" else {
            return nil
        }

        if rawValue.contains("/") {
            let pieces = rawValue.split(separator: "/", maxSplits: 1)
            guard pieces.count == 2,
                  let numerator = Double(pieces[0]),
                  let denominator = Double(pieces[1]),
                  denominator != 0 else {
                return nil
            }
            return numerator / denominator
        }

        return Double(rawValue)
    }
}

private struct FFProbeResponse: Decodable {
    let streams: [FFProbeStream]
    let format: FFProbeFormat?
}

private struct FFProbeFormat: Decodable {
    let duration: String?
    let size: String?
}

private struct FFProbeStream: Decodable {
    let index: Int
    let codecName: String?
    let codecType: String?
    let width: Int?
    let height: Int?
    let avgFrameRate: String?
    let rFrameRate: String?
    let duration: String?

    enum CodingKeys: String, CodingKey {
        case index
        case codecName = "codec_name"
        case codecType = "codec_type"
        case width
        case height
        case avgFrameRate = "avg_frame_rate"
        case rFrameRate = "r_frame_rate"
        case duration
    }
}
