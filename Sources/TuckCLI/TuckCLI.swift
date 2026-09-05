import Darwin
import Foundation
import TuckCore

@main
struct TuckCLI {
    static func main() async {
        let runner = CommandRunner(
            arguments: Array(CommandLine.arguments.dropFirst()),
            currentDirectoryPath: FileManager.default.currentDirectoryPath
        )
        Darwin.exit(await runner.run().rawValue)
    }
}

private struct CommandRunner {
    let arguments: [String]
    let currentDirectoryPath: String

    func run() async -> ExitCode {
        let options: CommandLineOptions
        do {
            options = try CommandLineOptions.parse(arguments)
        } catch {
            Stdio.standardError.write("\(error.localizedDescription)\n\n\(Self.usage)")
            return .usage
        }

        if options.showsHelp {
            Stdio.standardOutput.write(Self.usage)
            return .success
        }

        if options.showsVersion {
            Stdio.standardOutput.write("Tuck \(TuckVersion.current)\n")
            return .success
        }

        guard !options.paths.isEmpty else {
            Stdio.standardError.write("No input videos were provided.\n\n\(Self.usage)")
            return .usage
        }

        let reporter = ProgressReporter(json: options.json)

        let tools: MediaTools
        do {
            tools = try MediaToolDiscovery.discover()
        } catch let error as MediaToolDiscoveryError {
            reporter.failed(sourceURL: nil, error: error)
            return .missingMediaTools
        } catch {
            reporter.failed(sourceURL: nil, error: error)
            return .processingFailure
        }

        let service = CompressionService(tools: tools)
        var hadFailure = false

        for path in options.paths {
            let sourceURL = fileURL(for: path)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                hadFailure = true
                reporter.failed(sourceURL: sourceURL, error: CLIError.pathDoesNotExist(path))
                continue
            }

            reporter.analyzing(sourceURL)

            do {
                let result = try await service.compress(sourceURL: sourceURL) { fraction in
                    reporter.compressing(sourceURL, fraction: fraction)
                }
                reporter.completed(result)
            } catch {
                hadFailure = true
                reporter.failed(sourceURL: sourceURL, error: error)
            }
        }

        return hadFailure ? .processingFailure : .success
    }

    private func fileURL(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }

        return URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(path)
            .standardizedFileURL
    }

    private static let usage = """
    Usage: tuck [options] <video> [video ...]

    Compress videos sequentially using Tuck's automatic profile selection.
    Outputs are written beside each source as "<name> - compressed.mp4".

    Options:
      --json       Emit newline-delimited JSON events to stdout
      -h, --help   Show this help text
      --version    Show the Tuck version

    Exit codes:
      0  All videos compressed
      1  One or more videos failed
      2  Usage error
      3  FFmpeg or FFprobe is unavailable

    """
}

private enum ExitCode: Int32 {
    case success = 0
    case processingFailure = 1
    case usage = 2
    case missingMediaTools = 3
}

private struct CommandLineOptions {
    let json: Bool
    let showsHelp: Bool
    let showsVersion: Bool
    let paths: [String]

    static func parse(_ arguments: [String]) throws -> CommandLineOptions {
        var json = false
        var showsHelp = false
        var showsVersion = false
        var paths: [String] = []
        var treatsRemainingValuesAsPaths = false

        for argument in arguments {
            if treatsRemainingValuesAsPaths {
                paths.append(argument)
                continue
            }

            switch argument {
            case "--":
                treatsRemainingValuesAsPaths = true
            case "--json":
                json = true
            case "-h", "--help":
                showsHelp = true
            case "--version":
                showsVersion = true
            default:
                if argument.hasPrefix("-") {
                    throw CLIError.unknownOption(argument)
                }
                paths.append(argument)
            }
        }

        return CommandLineOptions(
            json: json,
            showsHelp: showsHelp,
            showsVersion: showsVersion,
            paths: paths
        )
    }
}

private enum CLIError: LocalizedError {
    case unknownOption(String)
    case pathDoesNotExist(String)

    var errorDescription: String? {
        switch self {
        case .unknownOption(let option):
            return "Unknown option: \(option)"
        case .pathDoesNotExist(let path):
            return "The file does not exist: \(path)"
        }
    }
}

private final class ProgressReporter: @unchecked Sendable {
    private let json: Bool
    private let lock = NSLock()
    private var lastPercentByPath: [String: Int] = [:]

    init(json: Bool) {
        self.json = json
    }

    func analyzing(_ sourceURL: URL) {
        locked {
            if json {
                writeJSON([
                    "event": "analyzing",
                    "source": sourceURL.path
                ])
            } else {
                Stdio.standardError.write("Analyzing \(sourceURL.lastPathComponent)\n")
            }
        }
    }

    func compressing(_ sourceURL: URL, fraction: Double) {
        let percent = min(99, max(0, Int((fraction * 100).rounded(.down))))

        locked {
            guard lastPercentByPath[sourceURL.path] != percent else { return }
            lastPercentByPath[sourceURL.path] = percent

            if json {
                writeJSON([
                    "event": "compressing",
                    "progress": percent,
                    "source": sourceURL.path
                ])
            } else {
                Stdio.standardError.write("Compressing \(sourceURL.lastPathComponent) \(percent)%\n")
            }
        }
    }

    func completed(_ result: CompressionResult) {
        locked {
            if json {
                writeJSON([
                    "event": "completed",
                    "output": result.outputURL.path,
                    "profile": result.plan.profile.rawValue,
                    "source": result.sourceURL.path
                ])
            } else {
                Stdio.standardOutput.write("\(result.outputURL.path)\n")
                Stdio.standardError.write("Wrote \(result.outputURL.lastPathComponent)\n")
            }
        }
    }

    func failed(sourceURL: URL?, error: Error) {
        locked {
            if json {
                var event: [String: Any] = [
                    "error": error.localizedDescription,
                    "event": "failed"
                ]
                if let sourceURL {
                    event["source"] = sourceURL.path
                }
                writeJSON(event)
            } else if let sourceURL {
                Stdio.standardError.write("Failed \(sourceURL.lastPathComponent): \(error.localizedDescription)\n")
            } else {
                Stdio.standardError.write("\(error.localizedDescription)\n")
            }
        }
    }

    private func locked(_ work: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        work()
    }

    private func writeJSON(_ event: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(event),
              let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else {
            return
        }

        FileHandle.standardOutput.write(data)
        Stdio.standardOutput.write("\n")
    }
}

private enum Stdio {
    static let standardOutput = TextOutput(fileHandle: .standardOutput)
    static let standardError = TextOutput(fileHandle: .standardError)
}

private struct TextOutput {
    let fileHandle: FileHandle

    func write(_ text: String) {
        fileHandle.write(Data(text.utf8))
    }
}
