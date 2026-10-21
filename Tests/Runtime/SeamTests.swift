import Foundation

// Reference-only phase seams must leave DoomGeneric byte-for-byte unchanged.
// Booting the engine is one-way, so each mode runs in a child of this executable.

private let freedoomPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets/freedoom1.wad").path

func runSeamChild(_ args: [String]) {
    guard let at = args.firstIndex(of: "--seam-child"), at + 1 < args.count else { return }
    var state: UInt64 = 0, sequence: UInt64 = 0
    var phases: UInt32 = 0, violations: UInt32 = 0, total: UInt32 = 0
    let mode = args[at + 1]
    // "bridge": the production route. Discovered modules are scheduled from the
    // real seams into a bounded commit ledger while the same script runs.
    let ledger = CommitLedger(capacity: 8)
    let scheduler = CircuitScheduler(modules: GeneratedModuleRegistry.factories.map { $0() }, sink: ledger.sink)
    if mode == "bridge" { PhaseSeamBridge.install(scheduler) }
    let status = HM_TestSeamScript(freedoomPath, mode == "on" ? 1 : (mode == "bridge" ? 2 : 0), 330, &state, &sequence,
                                   &phases, &violations, &total)
    let rows = scheduler.snapshots()
    print(String(format: "seam-result status=%d state=%016llx sequence=%016llx phases=%x violations=%u total=%u rows=%@ runs=%d commits=%d tic=%llu order=%d fallbacks=%d",
                 status, state, sequence, phases, violations, total, rows.map(\.name).joined(separator: ","),
                 rows.first?.attempts ?? 0, ledger.total, scheduler.ticID, scheduler.orderViolations,
                 rows.reduce(0) { $0 + $1.fallbacks.reduce(0) { $0 + $1.count } }))
    exit(status == 0 ? 0 : 1)
}

func runSeamTests(_ args: [String]) {
    let exe = URL(fileURLWithPath: args[0].hasPrefix("/") ? args[0] : FileManager.default.currentDirectoryPath + "/" + args[0])
    func run(_ mode: String) -> [String: String] {
        let child = Process(), pipe = Pipe()
        child.executableURL = exe; child.arguments = ["--seam-child", mode]; child.standardOutput = pipe
        try! child.run()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        child.waitUntilExit()
        require(child.terminationStatus == 0, "seam child (\(mode)) failed")
        let line = text.split(separator: "\n").last { $0.hasPrefix("seam-result") } ?? ""
        return Dictionary(uniqueKeysWithValues: line.split(separator: " ").dropFirst().compactMap {
            let kv = $0.split(separator: "="); return kv.count == 2 ? (String(kv[0]), String(kv[1])) : nil
        })
    }
    let off = run("off"), on = run("on"), bridge = run("bridge")
    require(off["state"] != nil && off["state"] == on["state"],
            "phase seams changed C state/RNG/framebuffer hash (off \(off["state"] ?? "?") vs on \(on["state"] ?? "?"))")
    require(on["violations"] == "0", "seam order violated: \(on["violations"] ?? "?")")
    // Phases 1 (commands) through 8 (rasterization) must all be seen in a play script.
    require((UInt32(on["phases"] ?? "0", radix: 16) ?? 0) & 0b1_1111_1110 == 0b1_1111_1110,
            "not every phase seam fired: mask \(on["phases"] ?? "?")")
    require((Int(on["total"] ?? "0") ?? 0) == 330 * 16, "seam count is not 16 per tic (12 simulation + 4 render)")
    // Production route: the discovered no-op module runs once per tic at its phase, commits through the
    // bounded sink, appears as a generic telemetry row, and the engine state is still byte-identical.
    require(bridge["state"] == off["state"], "scheduler bridge changed C state/RNG/framebuffer hash")
    let tics = Int(bridge["tic"] ?? "0") ?? 0
    require(tics >= 330 && bridge["rows"] == "conformance.noop" && Int(bridge["runs"] ?? "") == tics
            && Int(bridge["commits"] ?? "") == tics,
            "discovered module did not run exactly once per tic through the seams: \(bridge)")
    print("phase seams: hooked and unhooked 330-tic Freedoom scripts produce identical C state, RNG indices, and framebuffer hash \(off["state"]!); phases 1-8 fired in order (\(on["total"]!) seams); discovered no-op module ran \(tics)/\(tics) tics through the scheduler bridge with unchanged state")
}
