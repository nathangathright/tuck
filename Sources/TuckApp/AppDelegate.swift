import AppKit
import TuckCore
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = CompressionCoordinator()
    private var launchPickerWorkItem: DispatchWorkItem?
    private var receivedOpenEvent = false
    private var isPresentingOpenPanel = false
    private weak var currentOpenPanel: NSOpenPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        let isDefaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? NSNumber)?.boolValue ?? true
        if isDefaultLaunch {
            scheduleLaunchPicker()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard coordinator.isIdle else { return true }
        showOpenPanel()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handleOpen(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        handleOpen([URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        handleOpen(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc private func openFromMenu(_ sender: Any?) {
        guard coordinator.isIdle else { return }
        showOpenPanel()
    }

    private func scheduleLaunchPicker() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  !self.receivedOpenEvent,
                  self.coordinator.isIdle else {
                return
            }
            self.showOpenPanel()
        }
        launchPickerWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func handleOpen(_ urls: [URL]) {
        receivedOpenEvent = true
        launchPickerWorkItem?.cancel()

        let movies = urls.filter(Self.isMovieURL)
        if !movies.isEmpty {
            currentOpenPanel?.cancel(nil)
            coordinator.enqueue(movies)
        }
    }

    private func showOpenPanel() {
        guard !isPresentingOpenPanel else { return }

        coordinator.clearIdleBadge()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Choose Videos"
        panel.prompt = "Compress"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.movie]

        currentOpenPanel = panel
        isPresentingOpenPanel = true
        panel.begin { [weak self] response in
            guard let self else { return }
            self.isPresentingOpenPanel = false
            self.currentOpenPanel = nil

            if response == .OK {
                self.handleOpen(panel.urls)
            } else if self.coordinator.isIdle {
                self.coordinator.clearIdleBadge()
            }
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Tuck", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Tuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Open...", action: #selector(openFromMenu(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        NSApp.mainMenu = mainMenu
    }

    private static func isMovieURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }

        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = values.contentType {
            return contentType.conforms(to: .movie)
        }

        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.conforms(to: .movie)
        }

        let fallbackExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]
        return fallbackExtensions.contains(url.pathExtension.lowercased())
    }
}

@MainActor
private final class CompressionCoordinator {
    private struct JobFailure {
        let sourceURL: URL
        let error: Error
    }

    private var queuedURLs: [URL] = []
    private var isProcessingQueue = false
    private var cachedService: CompressionService?

    var isIdle: Bool {
        !isProcessingQueue && queuedURLs.isEmpty
    }

    func enqueue(_ urls: [URL]) {
        let existingFiles = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingFiles.isEmpty else { return }

        queuedURLs.append(contentsOf: existingFiles)
        processIfNeeded()
    }

    func clearIdleBadge() {
        guard isIdle else { return }
        setDockBadge(nil)
    }

    private func processIfNeeded() {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true

        Task {
            await drainQueue()
        }
    }

    private func drainQueue() async {
        var completedURLs: [URL] = []
        var failures: [JobFailure] = []

        while !queuedURLs.isEmpty {
            let sourceURL = queuedURLs.removeFirst()
            setDockBadge("...")

            let scopedAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if scopedAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let result = try await service().compress(sourceURL: sourceURL) { [weak self] fraction in
                    Task { @MainActor in
                        self?.setCompressionProgress(fraction)
                    }
                }
                completedURLs.append(result.outputURL)
            } catch {
                failures.append(JobFailure(sourceURL: sourceURL, error: error))

                if error is MediaToolDiscoveryError {
                    queuedURLs.removeAll()
                }
            }
        }

        isProcessingQueue = false

        if !completedURLs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(completedURLs)
        }

        if failures.isEmpty {
            setDockBadge("✓")
        } else {
            setDockBadge("!")
            presentFailures(failures)
        }
    }

    private func service() throws -> CompressionService {
        if let cachedService {
            return cachedService
        }

        let tools = try MediaToolDiscovery.discover()
        let service = CompressionService(tools: tools)
        cachedService = service
        return service
    }

    private func setCompressionProgress(_ fraction: Double) {
        guard isProcessingQueue else { return }

        let percent = min(99, max(0, Int((fraction * 100).rounded(.down))))
        setDockBadge("\(percent)%")
    }

    private func setDockBadge(_ label: String?) {
        NSApp.dockTile.badgeLabel = label
        NSApp.dockTile.display()
    }

    private func presentFailures(_ failures: [JobFailure]) {
        let alert = NSAlert()
        alert.alertStyle = .warning

        if failures.count == 1, let failure = failures.first {
            alert.messageText = "Tuck couldn't compress \(failure.sourceURL.lastPathComponent)"
            alert.informativeText = failure.error.localizedDescription
        } else {
            alert.messageText = "Tuck couldn't compress \(failures.count) videos"
            alert.informativeText = failures
                .map { "\($0.sourceURL.lastPathComponent): \($0.error.localizedDescription)" }
                .joined(separator: "\n\n")
        }

        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
