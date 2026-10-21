import Foundation

/// Fixed-capacity sample ring: after init it never allocates, so recording a
/// latency on the engine queue cannot grow the heap while visualization is off.
struct SampleRing {
    private var values: [UInt64]
    private var head = 0
    private(set) var count = 0
    init(capacity: Int) { values = Array(repeating: 0, count: capacity) }
    mutating func add(_ v: UInt64) {
        values[head] = v
        head = (head + 1) % values.count
        count = min(count + 1, values.count)
    }
    func percentile(_ q: Double) -> UInt64 {
        guard count > 0 else { return 0 }
        let s = values.prefix(count).sorted()
        return s[min(count - 1, Int(Double(count - 1) * q))]
    }
}

struct ModuleTrace {
    var tic: UInt64
    var accepted: Bool
    var fallback: String
    var attemptNs: UInt64
    var outputs: [Int32]
}

struct ModuleTelemetrySnapshot {
    var id: UInt32
    var name: String
    var phase: UInt32
    var attempts: Int
    var circuitTics: Int
    var fallbacks: [(reason: String, count: Int)]
    var lastFallback: String
    var acceptedP50Ns: UInt64, acceptedP99Ns: UInt64
    var attemptP50Ns: UInt64, attemptP99Ns: UInt64
    var queueWaitP99Ns: UInt64
    var commitP99Ns: UInt64
    var highWater: (inputs: Int, outputs: Int, deltas: Int, events: Int)
    var traceCount: Int
    var traceDrops: Int
}

/// Per-module counters shared by the generic runtime. Mutated on the engine queue only.
final class ModuleTelemetry {
    let descriptor: CircuitModuleDescriptor
    private(set) var attempts = 0
    private(set) var circuitTics = 0
    private(set) var fallbackCounts: [UInt32: Int] = [:]
    private(set) var lastFallbackCode: UInt32 = 0
    private var accepted = SampleRing(capacity: 4096)
    private var attemptAll = SampleRing(capacity: 4096)
    private var queueWait = SampleRing(capacity: 4096)
    private var commit = SampleRing(capacity: 4096)
    private(set) var highWater = (inputs: 0, outputs: 0, deltas: 0, events: 0)
    private(set) var traces: [ModuleTrace] = []
    private(set) var traceDrops = 0
    let traceCapacity: Int
    /// Sampling is one tic in `sampleEvery`; off mode never builds or stores a trace.
    var visualizationEnabled = false
    var sampleEvery = 8
    private(set) var traceBuilds = 0

    init(descriptor: CircuitModuleDescriptor, traceCapacity: Int = 128) {
        self.descriptor = descriptor
        self.traceCapacity = traceCapacity
    }

    func recordHighWater(inputs: Int, outputs: Int, deltas: Int, events: Int) {
        highWater = (max(highWater.inputs, inputs), max(highWater.outputs, outputs),
                     max(highWater.deltas, deltas), max(highWater.events, events))
    }
    func recordAccepted(attemptNs: UInt64, queueWaitNs: UInt64) {
        attempts += 1; circuitTics += 1
        accepted.add(attemptNs); attemptAll.add(attemptNs); queueWait.add(queueWaitNs)
        lastFallbackCode = 0
    }
    func recordFallback(_ code: UInt32, attemptNs: UInt64) {
        attempts += 1
        fallbackCounts[code, default: 0] += 1
        lastFallbackCode = code
        attemptAll.add(attemptNs)
    }
    func recordCommit(ns: UInt64) { commit.add(ns) }

    /// `build` runs only when visualization is on and this tic is sampled.
    func sample(tic: UInt64, _ build: () -> ModuleTrace) {
        guard visualizationEnabled, sampleEvery > 0, tic % UInt64(sampleEvery) == 0 else { return }
        traceBuilds += 1
        if traces.count == traceCapacity { traces.removeFirst(); traceDrops += 1 }
        traces.append(build())
    }

    func snapshot() -> ModuleTelemetrySnapshot {
        ModuleTelemetrySnapshot(
            id: descriptor.id, name: descriptor.name, phase: descriptor.phase, attempts: attempts,
            circuitTics: circuitTics,
            fallbacks: fallbackCounts.keys.sorted().map { (FallbackCode.name($0), fallbackCounts[$0]!) },
            lastFallback: FallbackCode.name(lastFallbackCode),
            acceptedP50Ns: accepted.percentile(0.5), acceptedP99Ns: accepted.percentile(0.99),
            attemptP50Ns: attemptAll.percentile(0.5), attemptP99Ns: attemptAll.percentile(0.99),
            queueWaitP99Ns: queueWait.percentile(0.99), commitP99Ns: commit.percentile(0.99),
            highWater: highWater, traceCount: traces.count, traceDrops: traceDrops)
    }
}
