import Foundation

public enum OutputNamer {
    public static func compressedOutputURL(
        for sourceURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let baseName = "\(stem) - compressed"

        var candidate = directory
            .appendingPathComponent(baseName)
            .appendingPathExtension("mp4")

        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension("mp4")
            suffix += 1
        }

        return candidate
    }
}
