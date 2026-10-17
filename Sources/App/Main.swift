import AppKit
import MetalKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var overlay: NSVisualEffectView!
    private var status: NSTextField!
    private var engine: EngineCoordinator?
    private var inspectorModel = InspectorModel()
    private var inspectorPanel: InspectorPanel!
    private var selectedIWAD: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 650),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Neural Doom"
        window.center()
        window.minSize = NSSize(width: 640, height: 440)
        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        window.contentView = root
        if let device = MTLCreateSystemDefaultDevice() {
            let engine = EngineCoordinator(device: device)
            self.engine = engine
            inspectorModel.engine = engine
            engine.inspector = inspectorModel
            let game = GameView(device: device)
            game.engine = engine
            engine.gameView = game
            game.frame = root.bounds
            game.autoresizingMask = [.width, .height]
            root.addSubview(game)
            window.makeFirstResponder(game)
        }
        let overlay = NSVisualEffectView(frame: root.bounds)
        self.overlay = overlay
        overlay.material = .hudWindow
        overlay.blendingMode = .withinWindow
        overlay.autoresizingMask = [.width, .height]
        root.addSubview(overlay)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, constant: -40)
        ])
        let title = NSTextField(labelWithString: "NEURAL DOOM")
        title.font = .monospacedSystemFont(ofSize: 28, weight: .bold)
        stack.addArrangedSubview(title)
        let subtitle = NSTextField(wrappingLabelWithString: "Native macOS · DoomGeneric reference · Metal locomotion + command remainder circuits")
        subtitle.alignment = .center
        stack.addArrangedSubview(subtitle)
        status = NSTextField(wrappingLabelWithString: engine == nil ? "Metal device unavailable." : "Loading bundled Freedoom Phase 1…")
        status.alignment = .center
        status.maximumNumberOfLines = 3
        stack.addArrangedSubview(status)
        let controls = NSTextField(wrappingLabelWithString: "Arrow keys move · Shift runs · Option strafes · Space uses · Control or click fires · ⌘⇧N opens the circuit inspector")
        controls.alignment = .center
        stack.addArrangedSubview(controls)
        inspectorPanel = InspectorPanel(model: inspectorModel)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let path = argumentIWAD() ?? ProcessInfo.processInfo.environment["FREEDOOM_IWAD"] {
            openIWAD(URL(fileURLWithPath: path))
        } else if let bundled = Bundle.main.url(forResource: "freedoom1", withExtension: "wad") {
            openIWAD(bundled)
        } else {
            status.stringValue = "Bundled Freedoom IWAD is missing. Use File → Open IWAD to select a local copy."
        }
    }
    private func argumentIWAD() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--iwad"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    private func setupMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Neural Doom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem(); menu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File"); fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Open IWAD…", action: #selector(chooseIWAD), keyEquivalent: "o").target = self
        let viewItem = NSMenuItem(); menu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View"); viewItem.submenu = viewMenu
        let toggle = viewMenu.addItem(withTitle: "Toggle Circuit Inspector", action: #selector(toggleInspector), keyEquivalent: "N")
        toggle.keyEquivalentModifierMask = [.command, .shift]
        toggle.target = self
        NSApp.mainMenu = menu
    }
    @objc private func chooseIWAD() {
        let panel = NSOpenPanel()
        panel.message = "Choose a local Doom or Freedoom IWAD. The file stays on your Mac."
        panel.allowedContentTypes = [.data]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] result in
            if result == .OK, let url = panel.url { self?.openIWAD(url, allowRestart: true) }
        }
    }
    private func openIWAD(_ url: URL, allowRestart: Bool = false) {
        if let error = IWADValidator.error(for: url) {
            status.stringValue = error + " Use File → Open IWAD to choose another file."
            overlay.isHidden = false
            return
        }
        if selectedIWAD != nil {
            guard allowRestart else { return }
            let child = Process()
            child.executableURL = Bundle.main.executableURL
            child.arguments = ["--iwad", url.path]
            do { try child.run(); NSApp.terminate(nil) }
            catch { status.stringValue = "Could not reopen the selected IWAD: \(error.localizedDescription)"; overlay.isHidden = false }
            return
        }
        guard let engine else { status.stringValue = "Metal is unavailable on this Mac."; return }
        let fileManager = FileManager.default
        if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           let dataDirectory = defaultDoomDataDirectory(
               environment: ProcessInfo.processInfo.environment,
               applicationSupportDirectory: support,
               directoryExists: { path in
                   var isDirectory: ObjCBool = false
                   return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
                       && isDirectory.boolValue
               }
           ) {
            setenv("HANDWIRED_DOOM_DATA_DIR", dataDirectory.path, 0)
        }
        selectedIWAD = url
        status.stringValue = "Loading \(url.lastPathComponent)…"
        // The decoded tables are validated before the reference loader runs: damaged
        // content stops here with a precise reason; legal content too large for the
        // circuit tables (or unsupported) falls back to DoomGeneric with that reason logged.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = IWADValidator.mapTables(for: url)
            DispatchQueue.main.async { self?.startEngine(engine, url: url, mapTables: result) }
        }
    }
    private func startEngine(_ engine: EngineCoordinator, url: URL, mapTables: Result<MapTablesV1, MapTablesFailure>) {
        switch mapTables {
        case .success(let tables):
            print("MapTablesV1: \(IWADValidator.redactedDescription(of: url, tables: tables)) \(tables.mapName) source hash \(String(format: "0x%016llx", tables.sourceHash))")
        case .failure(.malformed(let why)):
            status.stringValue = "This WAD is damaged (\(why)). Use File → Open IWAD to choose another file."
            return
        case .failure(let failure):
            print("MapTablesV1: \(url.lastPathComponent) not table-backed, using DoomGeneric reference: \(failure)")
        }
        engine.start(iwad: url) { [weak self] error in
            guard let self else { return }
            if let error { self.status.stringValue = error }
            else {
                self.overlay.isHidden = true
                if let game = self.engine?.gameView { self.window.makeFirstResponder(game) }
            }
        }
    }
    @objc private func toggleInspector() {
        if inspectorPanel.isVisible {
            inspectorPanel.orderOut(nil)
            engine?.setVisualization(false)
        } else {
            inspectorPanel.makeKeyAndOrderFront(nil)
            engine?.setVisualization(true)
            if let game = engine?.gameView { window.makeFirstResponder(game) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
enum NativeEntryPoint {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
