import Foundation
import Metal

// Fake modules prove the generic runtime without any gameplay rule: every
// status, no partial commit, late-slot isolation, commit order independent of
// completion order, the whole-tic budget, and visualization-off behavior.

private enum Behavior {
    case exact, status(UInt32), mismatch, outputOverCapacity, outOfOrderEvents, partialOutputs
}

private final class FakeModule: CircuitModule {
    let descriptor: CircuitModuleDescriptor
    var behavior: Behavior = .exact
    var delayNs: UInt64 = 0
    private let lock = NSLock()
    private var calls = 0
    private var started: UInt64 = 0, ended: UInt64 = 0
    var evaluateCalls: Int { lock.lock(); defer { lock.unlock() }; return calls }
    var window: (start: UInt64, end: UInt64) { lock.lock(); defer { lock.unlock() }; return (started, ended) }

    init(id: UInt32, phase: UInt32, deadlineNs: UInt64 = 50_000_000, slots: Int = 8) {
        descriptor = CircuitModuleDescriptor(
            id: id, name: "fake.\(id)", phase: phase, sourceHash: 0xfa4e_0000 | UInt64(id),
            requiredOutputs: 2, inputCapacity: 2, stateCapacity: 1, outputCapacity: 2,
            deltaCapacity: 1, eventCapacity: 2, deadlineNs: deadlineNs, slotCount: slots)
    }

    func reference(_ inv: ModuleInvocation) -> StagedResult {
        let out = [inv.inputs[0] &+ 1, inv.inputs[1] ^ 5]
        var r = StagedResult(outputs: out)
        if inv.state[0] != out[0] {
            r.deltas = [ModuleDelta(array: UInt32(HM_WORLD_ARRAY_PLAYERS), element: 0, cell: 1,
                                    before: inv.state[0], after: out[0])]
        }
        r.events = [ModuleEventRecord(phase: descriptor.phase, eventID: UInt32(HM_EVENT_SOUND), emitter: 0,
                                      sequence: 0, source: 1, target: 2, flags: 0, payload: [out[1]])]
        return r
    }

    func evaluate(_ inv: ModuleInvocation) -> StagedResult {
        lock.lock(); calls += 1; started = DispatchTime.now().uptimeNanoseconds; lock.unlock()
        defer { lock.lock(); ended = DispatchTime.now().uptimeNanoseconds; lock.unlock() }
        if delayNs > 0 { Thread.sleep(forTimeInterval: Double(delayNs) / 1e9) }
        var r = reference(inv)
        switch behavior {
        case .exact: break
        case .status(let s): r = StagedResult(status: s)
        case .mismatch: r.outputs[0] ^= 1
        case .outputOverCapacity: r.outputs.append(7)
        case .outOfOrderEvents:
            var second = r.events[0]; second.sequence = 0; second.emitter = 0
            var first = r.events[0]; first.sequence = 1
            r.events = [first, second]
        case .partialOutputs: r.outputs.removeLast()
        }
        return r
    }
}

private func invocation(_ tic: UInt64) -> ModuleInvocation {
    ModuleInvocation(ticID: tic, inputs: [Int32(truncatingIfNeeded: tic) &* 3, Int32(truncatingIfNeeded: tic) &+ 11],
                     state: [Int32(truncatingIfNeeded: tic) &* 7])
}

private final class CommitLog {
    private(set) var entries: [(id: UInt32, tic: UInt64, result: StagedResult)] = []
    func sink(_ id: UInt32, _ tic: UInt64, _ r: StagedResult) { entries.append((id, tic, r)) }
}

func runSchedulerTests() {
    let phase = UInt32(HM_PHASE_MOVEMENT_COLLISION)

    // Every non-exact outcome commits exactly the captured same-phase reference.
    let expectations: [(String, Behavior, UInt32)] = [
        ("unsupported-domain", .status(UInt32(HM_MODULE_UNSUPPORTED_DOMAIN)), UInt32(HM_MODULE_UNSUPPORTED_DOMAIN)),
        ("capacity (evaluator)", .status(UInt32(HM_MODULE_CAPACITY_EXCEEDED)), UInt32(HM_MODULE_CAPACITY_EXCEEDED)),
        ("execution-error", .status(UInt32(HM_MODULE_EXECUTION_ERROR)), UInt32(HM_MODULE_EXECUTION_ERROR)),
        ("table-bounds", .status(UInt32(HM_MODULE_TABLE_BOUNDS)), UInt32(HM_MODULE_TABLE_BOUNDS)),
        ("integer-overflow", .status(UInt32(HM_MODULE_INTEGER_OVERFLOW)), UInt32(HM_MODULE_INTEGER_OVERFLOW)),
        ("parity-mismatch", .mismatch, UInt32(HM_MODULE_PARITY_MISMATCH)),
        ("output span over capacity", .outputOverCapacity, UInt32(HM_MODULE_CAPACITY_EXCEEDED)),
        ("event order", .outOfOrderEvents, UInt32(HM_MODULE_INVALID_ORDER)),
        ("partial result", .partialOutputs, UInt32(HM_MODULE_PARTIAL_RESULT)),
    ]
    for (label, behavior, code) in expectations {
        let m = FakeModule(id: UInt32(HM_MODULE_MOVEMENT_COLLISION), phase: phase)
        m.behavior = behavior
        let log = CommitLog()
        let scheduler = CircuitScheduler(modules: [m], sink: log.sink)
        scheduler.runTic(ticID: 5, invocation: { _ in invocation(5) })
        require(log.entries.count == 1 && log.entries[0].result == m.reference(invocation(5)),
                "scheduler \(label): committed something other than the captured reference")
        let t = scheduler.telemetry(for: m.descriptor.id)!
        require(t.fallbackCounts == [code: 1] && t.circuitTics == 0, "scheduler \(label): fallback reason \(t.fallbackCounts)")
    }
    // Late work: timeout falls back, the late result is never committed, the next tic is unaffected.
    do {
        let m = FakeModule(id: UInt32(HM_MODULE_MOVEMENT_COLLISION), phase: phase, deadlineNs: 25_000_000)
        m.delayNs = 300_000_000
        let log = CommitLog()
        let scheduler = CircuitScheduler(modules: [m], budget: TicBudget(totalNs: 2_000_000_000), sink: log.sink)
        scheduler.runTic(ticID: 1, invocation: { _ in invocation(1) })
        m.delayNs = 0
        scheduler.runTic(ticID: 2, invocation: { _ in invocation(2) })
        require(log.entries[0].result == m.reference(invocation(1)) && log.entries[1].result == m.reference(invocation(2)),
                "late slot: tic results crossed")
        Thread.sleep(forTimeInterval: 0.5)
        require(log.entries.count == 2, "late completion committed after its tic")
        require(m.descriptor.slotCount == 8 && scheduler.runtime(for: m.descriptor.id)!.busySlots == 0, "late slot never released")
        let t = scheduler.telemetry(for: m.descriptor.id)!
        require(t.fallbackCounts == [FallbackCode.deadline: 1] && t.circuitTics == 1, "late slot telemetry")
    }
    // All slots owned by late workers: the next tic falls back with slots-busy, never overwrites.
    do {
        let m = FakeModule(id: UInt32(HM_MODULE_MOVEMENT_COLLISION), phase: phase, deadlineNs: 20_000_000, slots: 2)
        m.delayNs = 400_000_000
        let log = CommitLog()
        let scheduler = CircuitScheduler(modules: [m], budget: TicBudget(totalNs: 2_000_000_000), sink: log.sink)
        for tic in 1...3 { scheduler.runTic(ticID: UInt64(tic), invocation: { _ in invocation(UInt64(tic)) }) }
        let t = scheduler.telemetry(for: m.descriptor.id)!
        require(t.fallbackCounts == [FallbackCode.deadline: 2, FallbackCode.busy: 1], "slot exhaustion: \(t.fallbackCounts)")
        require(log.entries.allSatisfy { $0.result == m.reference(invocation($0.tic)) }, "slot exhaustion committed a candidate")
        Thread.sleep(forTimeInterval: 0.8)
        m.delayNs = 0
        scheduler.runTic(ticID: 4, invocation: { _ in invocation(4) })
        require(t.circuitTics == 1, "slots were not reusable after late workers finished")
    }

    // Commit order is (phase, module ID), never completion order.
    do {
        let ids = [UInt32(HM_MODULE_MOVEMENT_COLLISION), UInt32(HM_MODULE_INTERACTIONS_COMBAT), UInt32(HM_MODULE_THINKERS_AI)]
        let a = FakeModule(id: ids[0], phase: 2), b = FakeModule(id: ids[1], phase: 2), c = FakeModule(id: ids[2], phase: 2)
        let d = FakeModule(id: UInt32(HM_MODULE_WORLD_STATE), phase: 1)          // later ID, earlier phase
        a.delayNs = 15_000_000; b.delayNs = 8_000_000; c.delayNs = 0
        let log = CommitLog()
        let scheduler = CircuitScheduler(modules: [c, a, d, b], budget: TicBudget(totalNs: 200_000_000), sink: log.sink)
        scheduler.runTic(ticID: 9, invocation: { _ in invocation(9) })
        require(log.entries.map(\.id) == [d.descriptor.id] + ids && scheduler.commitOrder == log.entries.map(\.id),
                "commit order followed completion: \(log.entries.map(\.id))")
        require(log.entries.allSatisfy { $0.tic == 9 }, "commit tic tag")
    }

    // Whole-tic budget: a slow early phase leaves later phases at their C reference without dispatch.
    do {
        let slow = FakeModule(id: UInt32(HM_MODULE_MOVEMENT_COLLISION), phase: 2, deadlineNs: 50_000_000)
        slow.delayNs = 30_000_000
        let later = FakeModule(id: UInt32(HM_MODULE_INTERACTIONS_COMBAT), phase: 3, deadlineNs: 50_000_000)
        let log = CommitLog()
        let scheduler = CircuitScheduler(modules: [slow, later], budget: TicBudget(totalNs: 3_000_000), sink: log.sink)
        scheduler.runTic(ticID: 3, invocation: { _ in invocation(3) })
        require(scheduler.telemetry(for: slow.descriptor.id)!.fallbackCounts == [FallbackCode.deadline: 1], "budget: slow module")
        require(scheduler.telemetry(for: later.descriptor.id)!.fallbackCounts == [FallbackCode.budget: 1]
                && later.evaluateCalls == 0, "budget: later phase was dispatched past the whole-tic budget")
        require(log.entries.count == 2 && log.entries[0].result == slow.reference(invocation(3))
                && log.entries[1].result == later.reference(invocation(3)), "budget fallback did not commit references")
        Thread.sleep(forTimeInterval: 0.1)
    }

    // Phases run concurrently: N modules of 6 ms in one phase cost about 6 ms, not N x 6 ms.
    do {
        let mods = (0..<4).map { FakeModule(id: UInt32(HM_MODULE_MOVEMENT_COLLISION) + UInt32($0) * 0x10000, phase: 2, deadlineNs: 1_000_000_000) }
        let log = CommitLog()
        mods.forEach { $0.delayNs = 150_000_000 }
        let scheduler = CircuitScheduler(modules: mods, budget: TicBudget(totalNs: 2_000_000_000), sink: log.sink)
        scheduler.runTic(ticID: 1, invocation: { _ in invocation(1) })
        // Structural, not wall-clock: every module started before any module finished.
        let windows = mods.map(\.window)
        require(windows.map(\.start).max()! < windows.map(\.end).min()!
                && mods.allSatisfy { scheduler.telemetry(for: $0.descriptor.id)!.circuitTics == 1 },
                "same-phase modules were serialized")
    }

    // Telemetry: high-water marks, latency, queue wait, commit time, bounded sampled traces.
    do {
        let m = FakeModule(id: UInt32(HM_MODULE_MOVEMENT_COLLISION), phase: phase)
        let log = CommitLog()
        let scheduler = CircuitScheduler(modules: [m], budget: TicBudget(totalNs: 2_000_000_000), sink: log.sink)
        for tic in 1...64 { scheduler.runTic(ticID: UInt64(tic), invocation: { _ in invocation(UInt64(tic)) }) }
        let t = scheduler.telemetry(for: m.descriptor.id)!
        require(t.circuitTics == 64 && t.fallbackCounts.isEmpty, "valid candidates were not accepted")
        require(t.traceBuilds == 0 && t.traces.isEmpty, "visualization-off built or stored a trace")
        let snap = t.snapshot()
        require(snap.highWater.outputs == 2 && snap.highWater.deltas == 1 && snap.highWater.events == 1
                && snap.acceptedP50Ns > 0 && snap.attemptP99Ns >= snap.attemptP50Ns, "telemetry fields")
        scheduler.setVisualization(true)
        for tic in 65...128 { scheduler.runTic(ticID: UInt64(tic), invocation: { _ in invocation(UInt64(tic)) }) }
        require(t.traceBuilds == 8 && t.traces.count == 8, "sampled traces: one tic in eight")
        t.sampleEvery = 1
        for tic in 129...400 { scheduler.runTic(ticID: UInt64(tic), invocation: { _ in invocation(UInt64(tic)) }) }
        require(t.traces.count == 128 && t.traceDrops == 280 - 128, "trace ring bound / drop-oldest")
        require(scheduler.snapshots().count == 1, "one telemetry row per module")
    }

    // Registry discovery is deterministic: the committed generated file matches the generator.
    do {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [parityRoot().appendingPathComponent("Tools/generate_project.py").path, "--check"]
        p.standardError = FileHandle.nullDevice
        try! p.run(); p.waitUntilExit()
        require(p.terminationStatus == 0, "GeneratedRegistry.swift is stale: rerun Tools/generate_project.py")
    }
    print("scheduler: 9 failure statuses commit the reference only; late-slot isolation and slot exhaustion; commit order by (phase, ID); whole-tic budget; bounded traces; generated registry fresh")
}

private func parityRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

/// The two merged command circuits run through the same budget/telemetry policy, results unchanged.
func runLegacyThroughSchedulerTests(circuit: CircuitRuntime, remainder: RemainderRuntime, snapshots: Int) {
    let locomotion = LegacyCommandModule(id: UInt32(HM_MODULE_TIC_LOCOMOTION), name: "tic.locomotion", requiredOutputs: 4,
                                         inputCells: 24, stateCells: 1, sourceHash: 1, deadlineNs: 1_000_000_000)
    let rem = LegacyCommandModule(id: UInt32(HM_MODULE_TIC_REMAINDER), name: "tic.remainder", requiredOutputs: 21,
                                  inputCells: 55, stateCells: 55, sourceHash: 2, deadlineNs: 1_000_000_000)
    let scheduler = CircuitScheduler(modules: [], legacy: [locomotion.asLegacy, rem.asLegacy],
                                     budget: TicBudget(totalNs: 10_000_000_000)) { _, _, _ in }
    locomotion.scheduler = scheduler; rem.scheduler = scheduler
    var generator = Generator()
    var mismatches = 0, remainderMismatches = 0
    for i in 0..<snapshots {
        scheduler.beginTic(UInt64(i + 1))
        let movement = generator.snapshot()
        var copy = movement
        let reference = HM_TestOriginalMovement(&copy)
        let scheduledMove = locomotion.run(setDeadline: { circuit.deadlineNs = $0 },
                                           call: { circuit.evaluate(movement, reference: reference) },
                                           lastFallback: { circuit.lastFallback })
        if scheduledMove.map({ !same($0, reference) }) ?? true { mismatches += 1 }
        // The full-command remainder runs through the same scheduler against the original C oracle.
        var before = generator.remainderSnapshot(movement)
        var captured = HMTicRemainderInput()
        var movementCopy = movement
        let original = HM_TestOriginalRemainder(&movementCopy, &before, &captured)
        let scheduledRemainder = rem.run(setDeadline: { remainder.deadlineNs = $0 },
                                         call: { remainder.evaluate(captured, reference: original) },
                                         lastFallback: { remainder.lastFallback })
        if scheduledRemainder.map({ RemainderRuntime.cells($0) != RemainderRuntime.cells(original) }) ?? true {
            remainderMismatches += 1
        }
    }
    circuit.deadlineNs = 1_000_000_000; remainder.deadlineNs = 1_000_000_000
    let rows = scheduler.snapshots()
    require(mismatches == 0, "scheduled locomotion differed from the original C oracle")
    require(remainderMismatches == 0, "scheduled remainder differed from the original C oracle")
    require(rows.count == 2 && rows[0].name == "tic.locomotion" && rows[1].name == "tic.remainder"
            && rows[0].attempts == snapshots && rows[1].attempts == snapshots && rows[1].circuitTics == snapshots
            && rows[0].circuitTics == snapshots && scheduler.orderViolations == 0,
            "legacy rows / tic-command order")
    // Reversed call order is reported, and an exhausted whole-tic budget stops waiting.
    scheduler.beginTic(0)
    _ = scheduler.legacyDeadline(for: rem.descriptor); _ = scheduler.legacyDeadline(for: locomotion.descriptor)
    require(scheduler.orderViolations == 1, "tic-command order violation not detected")
    scheduler.beginTic(1)
    scheduler.legacyFinished(elapsedNs: scheduler.budget.totalNs)
    require(scheduler.legacyDeadline(for: locomotion.descriptor) == 0, "exhausted budget still allowed a wait")
    print("scheduler: \(snapshots) locomotion and \(snapshots) full-command remainder snapshots identical to the original C oracle through the generic scheduler; generic rows and tic-command order verified")
}
