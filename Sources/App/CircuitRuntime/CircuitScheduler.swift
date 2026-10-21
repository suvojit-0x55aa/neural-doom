import Foundation

/// Whole-tic wait policy. Modules in one phase run concurrently, so a phase
/// costs the slowest module, not the sum; phases are serial, and the sum of
/// phase waits is capped here. A module never waits longer than the remaining
/// budget, and once it is spent later modules take their C reference at once.
struct TicBudget {
    /// Default equals the two existing 2 ms command deadlines, run serially.
    var totalNs: UInt64 = 4_000_000
}

/// Receives each accepted-or-reference result exactly once, in (phase, module ID) order.
typealias CommitSink = (_ moduleID: UInt32, _ ticID: UInt64, _ result: StagedResult) -> Void

struct LegacyModule {
    var descriptor: CircuitModuleDescriptor
    var snapshot: () -> ModuleTelemetrySnapshot
}

final class CircuitScheduler {
    private let runtimes: [CircuitModuleRuntime]       // sorted by (phase, id); never by completion
    private let legacy: [LegacyModule]
    private let sink: CommitSink
    var budget: TicBudget
    private(set) var ticID: UInt64 = 0
    private var remainingNs: UInt64 = 0
    private var legacyOrder: [UInt32] = []
    private(set) var orderViolations = 0
    private(set) var commitOrder: [UInt32] = []        // last tic, for inspection and tests

    init(modules: [CircuitModule], legacy: [LegacyModule] = [], budget: TicBudget = TicBudget(),
         sink: @escaping CommitSink) {
        runtimes = modules.map { CircuitModuleRuntime($0) }
            .sorted { ($0.descriptor.phase, $0.descriptor.id) < ($1.descriptor.phase, $1.descriptor.id) }
        for (a, b) in zip(runtimes, runtimes.dropFirst()) {
            precondition(a.descriptor.id != b.descriptor.id, "duplicate module ID \(a.descriptor.id)")
        }
        self.legacy = legacy.sorted { ($0.descriptor.phase, $0.descriptor.id) < ($1.descriptor.phase, $1.descriptor.id) }
        self.budget = budget
        self.sink = sink
    }

    var moduleNames: [String] { (legacy.map { $0.descriptor } + runtimes.map { $0.descriptor }).map(\.name) }
    func telemetry(for id: UInt32) -> ModuleTelemetry? { runtimes.first { $0.descriptor.id == id }?.telemetry }
    func runtime(for id: UInt32) -> CircuitModuleRuntime? { runtimes.first { $0.descriptor.id == id } }
    func setVisualization(_ on: Bool) { runtimes.forEach { $0.telemetry.visualizationEnabled = on } }

    /// One telemetry row per module, legacy and generic alike, in phase order.
    func snapshots() -> [ModuleTelemetrySnapshot] {
        (legacy.map { ($0.descriptor, $0.snapshot()) } + runtimes.map { ($0.descriptor, $0.telemetry.snapshot()) })
            .sorted { ($0.0.phase, $0.0.id) < ($1.0.phase, $1.0.id) }.map { $0.1 }
    }

    // MARK: Generic modules

    /// Runs every generic module for one tic. `invocation` supplies each module's
    /// immutable snapshot; modules never see each other's uncommitted output.
    func runTic(ticID: UInt64, invocation: (CircuitModuleDescriptor) -> ModuleInvocation) {
        beginTic(ticID)
        for phase in Set(runtimes.map { $0.descriptor.phase }).sorted() { runPhase(phase, invocation: invocation) }
    }

    /// Runs the generic modules of one phase, using each module's own snapshot builder.
    func runPhase(_ phase: UInt32) {
        runPhase(phase) { d in self.runtime(for: d.id)!.module.invocation(ticID: self.ticID) }
    }

    func runPhase(_ phase: UInt32, invocation: (CircuitModuleDescriptor) -> ModuleInvocation) {
        let group = runtimes.filter { $0.descriptor.phase == phase }.sorted { $0.descriptor.id < $1.descriptor.id }
        guard !group.isEmpty else { return }
        do {
            let start = DispatchTime.now().uptimeNanoseconds
            // Start every module, then poll them all from this one thread: the wait is the slowest
            // module, and no waiter thread can starve a worker on a few-core machine.
            let pendings = group.map { runtime -> CircuitModuleRuntime.Pending in
                let allowed = min(runtime.descriptor.deadlineNs, remainingNs)
                return runtime.begin(invocation(runtime.descriptor), deadlineNs: allowed,
                                     budgetLimited: allowed < runtime.descriptor.deadlineNs)
            }
            var outcomes = [ModuleOutcome?](repeating: nil, count: group.count)
            var unresolved = group.count
            while unresolved > 0 {
                for (i, runtime) in group.enumerated() where outcomes[i] == nil {
                    if let outcome = runtime.poll(pendings[i]) { outcomes[i] = outcome; unresolved -= 1 }
                }
                if unresolved > 0 { sched_yield() }
            }
            // Commit in module-ID order within the phase, whatever finished first.
            for (i, runtime) in group.enumerated() {
                let begin = DispatchTime.now().uptimeNanoseconds
                sink(runtime.descriptor.id, ticID, outcomes[i]!.committed)
                runtime.telemetry.recordCommit(ns: DispatchTime.now().uptimeNanoseconds - begin)
                commitOrder.append(runtime.descriptor.id)
                let outcome = outcomes[i]!
                runtime.telemetry.sample(tic: ticID) {
                    ModuleTrace(tic: ticID, accepted: outcome.accepted, fallback: FallbackCode.name(outcome.code),
                                attemptNs: outcome.attemptNs, outputs: outcome.committed.outputs)
                }
            }
            let spent = DispatchTime.now().uptimeNanoseconds - start
            remainingNs = spent >= remainingNs ? 0 : remainingNs - spent
        }
    }

    // MARK: Legacy command modules

    /// Called from the engine at the start of each simulation tic.
    func beginTic(_ id: UInt64) {
        ticID = id
        remainingNs = budget.totalNs
        legacyOrder = []
        commitOrder = []
    }

    /// The deadline a legacy module may use for this call under the whole-tic
    /// budget. Also checks that tic-command modules run in registry order.
    func legacyDeadline(for descriptor: CircuitModuleDescriptor) -> UInt64 {
        if let last = legacyOrder.last, (last >= descriptor.id) { orderViolations += 1 }
        legacyOrder.append(descriptor.id)
        return min(descriptor.deadlineNs, remainingNs)
    }

    /// Charges a legacy call's wall time against the whole-tic budget.
    func legacyFinished(elapsedNs: UInt64) {
        remainingNs = elapsedNs >= remainingNs ? 0 : remainingNs - elapsedNs
    }
}
