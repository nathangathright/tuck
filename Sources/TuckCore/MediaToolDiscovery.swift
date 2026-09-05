import Foundation

public struct MediaTools: Equatable, Sendable {
    public let ffmpeg: URL
    public let ffprobe: URL

    public init(ffmpeg: URL, ffprobe: URL) {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
    }
}

public struct MediaToolDiscoveryError: LocalizedError, Sendable {
    public let searchedLocations: [String]

    public var errorDescription: String? {
        """
        Tuck needs FFmpeg and FFprobe before it can inspect or compress videos.

        Install them with:
          brew install ffmpeg

        Tuck also looks for bundled binaries at:
          Tuck.app/Contents/Resources/bin/ffmpeg
          Tuck.app/Contents/Resources/bin/ffprobe
        """
    }

    public var failureReason: String? {
        "FFmpeg and FFprobe were not found in the app bundle, PATH, /opt/homebrew/bin, or /usr/local/bin."
    }
}

public enum MediaToolDiscovery {
    public static func discover(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> MediaTools {
        let pairs = candidatePairs(bundle: bundle, environment: environment)
        for pair in pairs {
            if fileManager.isExecutableFile(atPath: pair.ffmpeg.path),
               fileManager.isExecutableFile(atPath: pair.ffprobe.path) {
                return pair
            }
        }

        throw MediaToolDiscoveryError(
            searchedLocations: pairs.flatMap { [$0.ffmpeg.path, $0.ffprobe.path] }
        )
    }

    private static func candidatePairs(
        bundle: Bundle,
        environment: [String: String]
    ) -> [MediaTools] {
        var roots: [URL] = []

        if let resourceURL = bundle.resourceURL {
            roots.append(resourceURL)
            roots.append(resourceURL.appendingPathComponent("bin", isDirectory: true))
            roots.append(resourceURL.appendingPathComponent("ffmpeg", isDirectory: true))
        }

        roots.append(URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true))
        roots.append(URL(fileURLWithPath: "/usr/local/bin", isDirectory: true))

        if let path = environment["PATH"] {
            roots.append(contentsOf: path
                .split(separator: ":")
                .map { URL(fileURLWithPath: String($0), isDirectory: true) })
        }

        var seen = Set<String>()
        return roots.compactMap { root in
            let normalized = root.standardizedFileURL.path
            guard seen.insert(normalized).inserted else { return nil }
            return MediaTools(
                ffmpeg: root.appendingPathComponent("ffmpeg"),
                ffprobe: root.appendingPathComponent("ffprobe")
            )
        }
    }
}
