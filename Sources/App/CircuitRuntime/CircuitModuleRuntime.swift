import Foundation

// Generic CircuitModuleV1 runtime. A module supplies a descriptor, a same-phase
// reference (the captured C result) and a candidate evaluator. The runtime owns
// slots, deadlines, envelope validation, oracle comparison, and fallback; the
// scheduler owns ordering and atomic commit. Nothing here knows a module name.

struct ModuleDelta: Equatable {
    var array: UInt32, element: UInt32, cell: UInt32
    var before: Int32, after: Int32
}

struct ModuleEventRecord: Equatable {
    var phase: UInt32, eventID: UInt32, emitter: UInt32, sequence: UInt32
    var source: UInt32, target: UInt32, flags: UInt32
    var payload: [Int32]
}

struct ModuleTable: Equatable {
    var id: UInt32
    var cells: [Int32]
    var capacity: UInt32
}

/// A staged result: nothing in it is visible to the world until the scheduler commits it.
struct StagedResult: Equatable {
    var status: UInt32 = UInt32(HM_MODULE_EXACT)
    var outputs: [Int32] = []
    var deltas: [ModuleDelta] = []
    var events: [ModuleEventRecord] = []
}

/// Immutable snapshot `S_n` plus earlier accepted deltas/events for one module and tic.
struct ModuleInvocation {
    var ticID: UInt64
    var inputs: [Int32]
    var state: [Int32]
    var tables: [ModuleTable] = []
    var priorEvents: [ModuleEventRecord] = []
}

struct CircuitModuleDescriptor {
    var id: UInt32
    var name: String
    var phase: UInt32
    var programVersion: UInt32 = 1
    var sourceHash: UInt64
    var requiredOutputs: Int
    var inputCapacity: UInt32
    var stateCapacity: UInt32
    var outputCapacity: UInt32
    var deltaCapacity: UInt32
    var eventCapacity: UInt32
    /// Per-module attempt deadline. Existing command circuits keep 2 ms.
    var deadlineNs: UInt64 = 2_000_000
    var slotCount: Int = 8
}

protocol CircuitModule: AnyObject {
    var descriptor: CircuitModuleDescriptor { get }
    /// The captured same-phase C result; cheap, runs on the engine queue, always valid.
    func reference(_ invocation: ModuleInvocation) -> StagedResult
    /// The circuit candidate; runs on a worker and may be late.
    func evaluate(_ invocation: ModuleInvocation) -> StagedResult
    /// Immutable snapshot `S_n` for this tic, built through the module's versioned boundary.
    func invocation(ticID: UInt64) -> ModuleInvocation
}

extension CircuitModule {
    func invocation(ticID: UInt64) -> ModuleInvocation { ModuleInvocation(ticID: ticID, inputs: [], state: []) }
}

// Pseudo-statuses sit above the HMModuleStatus range and never reach an ABI field.
enum FallbackCode {
    static let deadline: UInt32 = 100
    static let busy: UInt32 = 101
    static let budget: UInt32 = 102
    static func name(_ code: UInt32) -> String {
        switch code {
        case 0: return "none"
        case UInt32(HM_MODULE_UNSUPPORTED_DOMAIN): return "unsupported-domain"
        case UInt32(HM_MODULE_CAPACITY_EXCEEDED): return "capacity-exceeded"
        case UInt32(HM_MODULE_EXECUTION_ERROR): return "execution-error"
        case UInt32(HM_MODULE_PARITY_MISMATCH): return "parity-mismatch"
        case UInt32(HM_MODULE_INVALID_ABI): return "invalid-abi"
        case UInt32(HM_MODULE_UNKNOWN_ID): return "unknown-id"
        case UInt32(HM_MODULE_SOURCE_HASH_MISMATCH): return "source-hash-mismatch"
        case UInt32(HM_MODULE_MALFORMED_SPAN): return "malformed-span"
        case UInt32(HM_MODULE_INVALID_ORDER): return "invalid-order"
        case UInt32(HM_MODULE_TABLE_BOUNDS): return "table-bounds"
        case UInt32(HM_MODULE_INTEGER_OVERFLOW): return "integer-overflow"
        case UInt32(HM_MODULE_PARTIAL_RESULT): return "partial-result"
        case deadline: return "deadline"
        case busy: return "slots-busy"
        case budget: return "tic-budget"
        default: return "status-\(code)"
        }
    }
}

struct ModuleOutcome {
    /// What the scheduler commits: the accepted candidate, or the captured reference.
    var committed: StagedResult
    var accepted: Bool
    /// 0 when accepted, otherwise the single recorded fallback reason.
    var code: UInt32
    var attemptNs: UInt64
    var queueWaitNs: UInt64
}

// MARK: - Envelope validation

private final class Arena {
    private var frees: [() -> Void] = []
    func make<T>(_ values: [T], minimum: Int = 1) -> UnsafeMutablePointer<T> {
        let n = max(minimum, values.count)
        let p = UnsafeMutablePointer<T>.allocate(capacity: n)
        UnsafeMutableRawPointer(p).initializeMemory(as: UInt8.self, repeating: 0, count: n * MemoryLayout<T>.stride)
        values.withUnsafeBufferPointer { if let b = $0.baseAddress { p.update(from: b, count: values.count) } }
        frees.append { p.deallocate() }
        return p
    }
    deinit { frees.forEach { $0() } }
}

enum ModuleEnvelope {
    /// Runs the frozen CircuitModuleV1 validator over a staged result. Non-exact means "commit nothing".
    static func validate(_ d: CircuitModuleDescriptor, _ inv: ModuleInvocation, _ staged: StagedResult) -> UInt32 {
        guard staged.status == UInt32(HM_MODULE_EXACT) else { return staged.status }
        let arena = Arena()
        let tables = inv.tables.map {
            HMTableViewV1(table_id: $0.id, length: UInt32($0.cells.count), capacity: $0.capacity,
                          reserved: 0, cells: UnsafePointer(arena.make($0.cells)))
        }
        var input = HMModuleInputV1()
        input.abi_version = UInt32(HM_CIRCUIT_MODULE_ABI_VERSION)
        input.program_version = d.programVersion
        input.integer_encoding = UInt32(HM_EXACT_INTEGER_ENCODING_V1)
        input.module_id = d.id; input.tic_id = inv.ticID; input.source_hash = d.sourceHash
        input.input_count = UInt32(inv.inputs.count); input.input_capacity = d.inputCapacity
        input.state_count = UInt32(inv.state.count); input.state_capacity = d.stateCapacity
        input.table_count = UInt32(tables.count); input.table_capacity = UInt32(tables.count)
        let prior = inv.priorEvents.map(toC)
        input.input_event_count = UInt32(prior.count); input.input_event_capacity = UInt32(prior.count)
        input.output_count = UInt32(d.requiredOutputs); input.output_capacity = d.outputCapacity
        input.state_delta_capacity = d.deltaCapacity; input.event_capacity = d.eventCapacity
        input.inputs = UnsafePointer(arena.make(inv.inputs)); input.state_before = UnsafePointer(arena.make(inv.state))
        input.tables = UnsafePointer(arena.make(tables)); input.input_events = UnsafePointer(arena.make(prior))

        var result = HMModuleResultV1()
        result.abi_version = input.abi_version; result.module_id = d.id
        result.tic_id = inv.ticID; result.source_hash = d.sourceHash
        result.status = UInt32(HM_MODULE_EXACT)
        result.output_count = UInt32(staged.outputs.count); result.output_capacity = d.outputCapacity
        result.state_delta_count = UInt32(staged.deltas.count); result.state_delta_capacity = d.deltaCapacity
        result.event_count = UInt32(staged.events.count); result.event_capacity = d.eventCapacity
        result.outputs = arena.make(staged.outputs, minimum: Int(d.outputCapacity) + 1)
        result.state_deltas = arena.make(staged.deltas.map {
            HMStateDeltaV1(array_id: $0.array, element_index: $0.element, cell_id: $0.cell, before: $0.before, after: $0.after)
        }, minimum: Int(d.deltaCapacity) + 1)
        result.events = arena.make(staged.events.map(toC), minimum: Int(d.eventCapacity) + 1)
        return HM_FinalizeModuleResultV1(&input, &result, d.id, d.sourceHash)
    }

    private static func toC(_ e: ModuleEventRecord) -> HMModuleEventV1 {
        var c = HMModuleEventV1()
        c.phase = e.phase; c.event_id = e.eventID; c.emitter_slot = e.emitter; c.local_sequence = e.sequence
        c.source_id = e.source; c.target_id = e.target; c.payload_count = UInt32(e.payload.count); c.flags = e.flags
        withUnsafeMutableBytes(of: &c.payload) { raw in
            let p = raw.bindMemory(to: Int32.self)
            for (i, v) in e.payload.prefix(4).enumerated() { p[i] = v }
        }
        return c
    }
}

// MARK: - Slots

/// An isolated evaluation slot. It stays owned by its worker until that worker
/// finishes, so a late result can never be read, committed, or overwritten later.
final class ModuleSlot {
    private let lock = NSLock()
    private var busy = false
    private var finished = false
    private var abandoned = false
    private var staged: StagedResult?
    private var startedNs: UInt64 = 0
    private(set) var lastWorkerStartNs: UInt64 = 0
    let done = DispatchSemaphore(value: 0)

    func acquire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !busy else { return false }
        busy = true; finished = false; abandoned = false; staged = nil
        while done.wait(timeout: .now()) == .success {}   // drain a stale signal
        return true
    }
    func workerStarted() { lock.lock(); lastWorkerStartNs = DispatchTime.now().uptimeNanoseconds; lock.unlock() }
    func complete(_ result: StagedResult) {
        lock.lock()
        if abandoned { staged = nil; busy = false } else { staged = result; finished = true }
        lock.unlock()
        done.signal()
    }
    /// The engine takes a finished result exactly once; otherwise it abandons the slot.
    func take() -> StagedResult? {
        lock.lock(); defer { lock.unlock() }
        if finished { busy = false; let r = staged; staged = nil; return r }
        abandoned = true
        return nil
    }
    var isBusy: Bool { lock.lock(); defer { lock.unlock() }; return busy }
}

// MARK: - Per-module runtime

final class CircuitModuleRuntime {
    let module: CircuitModule
    let telemetry: ModuleTelemetry
    private let slots: [ModuleSlot]
    private let worker = DispatchQueue(label: "handwired.doom.module-worker", qos: .userInteractive, attributes: .concurrent)

    init(_ module: CircuitModule, telemetry: ModuleTelemetry? = nil) {
        self.module = module
        self.slots = (0..<max(1, module.descriptor.slotCount)).map { _ in ModuleSlot() }
        self.telemetry = telemetry ?? ModuleTelemetry(descriptor: module.descriptor)
    }
    var descriptor: CircuitModuleDescriptor { module.descriptor }

    private func gate(_ inv: ModuleInvocation) -> UInt32? {
        let d = descriptor
        if inv.inputs.count > Int(d.inputCapacity) || inv.state.count > Int(d.stateCapacity) {
            return UInt32(HM_MODULE_CAPACITY_EXCEEDED)
        }
        return nil
    }

    /// One in-flight attempt. `begin` starts it; `poll` resolves it without blocking.
    struct Pending {
        fileprivate var inv: ModuleInvocation
        fileprivate var reference: StagedResult
        fileprivate var start: UInt64
        fileprivate var enqueued: UInt64
        fileprivate var deadlineNs: UInt64
        fileprivate var slot: ModuleSlot?
        fileprivate var immediate: UInt32?     // fallback decided before any dispatch
    }

    func begin(_ inv: ModuleInvocation, deadlineNs: UInt64, budgetLimited: Bool = false) -> Pending {
        let start = DispatchTime.now().uptimeNanoseconds
        let reference = module.reference(inv)
        telemetry.recordHighWater(inputs: inv.inputs.count, outputs: reference.outputs.count,
                                  deltas: reference.deltas.count, events: reference.events.count)
        var pending = Pending(inv: inv, reference: reference, start: start, enqueued: start,
                              deadlineNs: deadlineNs, slot: nil, immediate: nil)
        if let code = gate(inv) { pending.immediate = code; return pending }
        if deadlineNs == 0 { pending.immediate = budgetLimited ? FallbackCode.budget : FallbackCode.deadline; return pending }
        guard let slot = slots.first(where: { $0.acquire() }) else { pending.immediate = FallbackCode.busy; return pending }
        pending.slot = slot
        pending.enqueued = DispatchTime.now().uptimeNanoseconds
        let module = self.module
        worker.async {
            slot.workerStarted()
            slot.complete(module.evaluate(inv))
        }
        return pending
    }

    /// Returns the outcome once it is decided (result in, deadline passed, or rejected up front), else nil.
    func poll(_ p: Pending) -> ModuleOutcome? {
        func fallback(_ code: UInt32, queueWait: UInt64 = 0) -> ModuleOutcome {
            let ns = DispatchTime.now().uptimeNanoseconds - p.start
            telemetry.recordFallback(code, attemptNs: ns)
            return ModuleOutcome(committed: p.reference, accepted: false, code: code, attemptNs: ns, queueWaitNs: queueWait)
        }
        if let code = p.immediate { return fallback(code) }
        guard let slot = p.slot else { return fallback(FallbackCode.busy) }
        var staged: StagedResult?
        if slot.done.wait(timeout: .now()) == .success {
            staged = slot.take()
        } else if DispatchTime.now().uptimeNanoseconds - p.start >= p.deadlineNs {
            staged = slot.take()     // abandons the slot unless the result just landed
        } else {
            return nil
        }
        let wait = slot.lastWorkerStartNs > p.enqueued ? slot.lastWorkerStartNs - p.enqueued : 0
        let elapsed = DispatchTime.now().uptimeNanoseconds - p.start
        guard let candidate = staged, elapsed < p.deadlineNs else { return fallback(FallbackCode.deadline, queueWait: wait) }
        let status = ModuleEnvelope.validate(descriptor, p.inv, candidate)
        guard status == UInt32(HM_MODULE_EXACT) else { return fallback(status, queueWait: wait) }
        guard candidate == p.reference else { return fallback(UInt32(HM_MODULE_PARITY_MISMATCH), queueWait: wait) }
        let ns = DispatchTime.now().uptimeNanoseconds - p.start
        telemetry.recordAccepted(attemptNs: ns, queueWaitNs: wait)
        return ModuleOutcome(committed: candidate, accepted: true, code: 0, attemptNs: ns, queueWaitNs: wait)
    }

    /// Blocking convenience for a single module. Yields between polls so waiters never starve workers.
    func run(_ inv: ModuleInvocation, deadlineNs: UInt64, budgetLimited: Bool = false) -> ModuleOutcome {
        let pending = begin(inv, deadlineNs: deadlineNs, budgetLimited: budgetLimited)
        while true {
            if let outcome = poll(pending) { return outcome }
            sched_yield()
        }
    }

    var busySlots: Int { slots.filter { $0.isBusy }.count }
}
