import Foundation

public struct ProcessOutput: Sendable {
    public let standardOutput: Data
    public let standardError: Data
    public let terminationStatus: Int32
}

public struct ProcessExecutionError: LocalizedError, Sendable {
    public let executablePath: String
    public let arguments: [String]
    public let terminationStatus: Int32
    public let standardError: String

    public init(
        executablePath: String,
        arguments: [String],
        terminationStatus: Int32,
        standardError: String
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.terminationStatus = terminationStatus
        self.standardError = standardError
    }

    public var errorDescription: String? {
        let command = ([executablePath] + arguments).joined(separator: " ")
        if standardError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(command) exited with status \(terminationStatus)."
        }
        return "\(command) exited with status \(terminationStatus):\n\(standardError)"
    }
}

public enum ProcessRunner {
    public static func run(
        _ executableURL: URL,
        arguments: [String],
        standardInput: Data? = nil
    ) async throws -> ProcessOutput {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let inputPipe: Pipe?
            if standardInput != nil {
                let pipe = Pipe()
                process.standardInput = pipe
                inputPipe = pipe
            } else {
                inputPipe = nil
            }

            try process.run()

            if let standardInput, let inputPipe {
                inputPipe.fileHandleForWriting.write(standardInput)
                try? inputPipe.fileHandleForWriting.close()
            }

            let stdoutTask = Task.detached {
                stdout.fileHandleForReading.readDataToEndOfFile()
            }
            let stderrTask = Task.detached {
                stderr.fileHandleForReading.readDataToEndOfFile()
            }

            process.waitUntilExit()

            return ProcessOutput(
                standardOutput: await stdoutTask.value,
                standardError: await stderrTask.value,
                terminationStatus: process.terminationStatus
            )
        }.value
    }
}
