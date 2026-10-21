import Foundation
import Metal

// Module-neutral acceptance harness. A module registers generators, an oracle,
// a CPU evaluator, and a Metal evaluator in ParityRegistry.swift; this file
// owns validation, comparison, fixtures, manifests, and latency reporting.

enum Tamper { case none, badABI, staleHash, unknownEvent, malformedSpan, outOfOrderDeltas, partial }

struct ParityVector {
    var name: String
    var testCase: ParityCase
    var tamper: Tamper = .none
    var expected: UInt32
}

protocol ParityModule {
    var name: String { get }
    var moduleID: UInt32 { get }
    var programVersion: UInt32 { get }
    var sourceHash: UInt64 { get }
    var requiredOutputs: Int { get }
    /// Repository-relative path of this module's committed fixture manifest.
    var manifestPath: String { get }
    func makeCase(seed: UInt64, index: Int) -> ParityCase
    func adversarial() -> [ParityVector]
    func oracle(_ c: ParityCase) -> RawResult
    func cpu(_ c: ParityCase) -> RawResult
    /// A completion after `deadlineNs` is late: it must return execution-error and commit nothing.
    func metal(_ c: ParityCase, _ runner: ExactMetalRunner, deadlineNs: UInt64) -> RawResult
}

// MARK: - Deterministic randomness

struct ParityRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
    mutating func span(_ width: UInt64) -> UInt64 { next() % width }
    mutating func range(_ lo: Int32, _ hi: Int32) -> Int32 {
        Int32(Int64(lo) + Int64(span(UInt64(Int64(hi) - Int64(lo) + 1))))
    }
}

let parityBaseSeed: UInt64 = 0x4e44_5f50_4152_4954   // fixed so fixtures are reproducible
func parityCaseSeed(_ index: Int) -> UInt64 {
    var r = ParityRNG(seed: parityBaseSeed ^ UInt64(index)); return r.next()
}

// MARK: - Exact-program evaluators (CPU + Metal) shared by exact modules

final class ParityArena {
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

struct ExactProgramSpec {
    let inputCount: Int
    let operations: [HMExactOpV1]
    let roots: [UInt32]
    let hash: UInt64

    init(inputCount: Int, operations: [HMExactOpV1], roots: [UInt32]) {
        self.inputCount = inputCount; self.operations = operations; self.roots = roots
        let arena = ParityArena()
        var program = ExactProgramSpec.program(inputCount, operations, roots, arena, hash: 0)
        hash = HM_ExactProgramHashV1(&program)
    }

    static func program(_ inputCount: Int, _ ops: [HMExactOpV1], _ roots: [UInt32],
                        _ arena: ParityArena, hash: UInt64) -> HMExactProgramV1 {
        HMExactProgramV1(abi_version: UInt32(HM_EXACT_PROGRAM_ABI_VERSION),
                         integer_encoding: UInt32(HM_EXACT_INTEGER_ENCODING_V1),
                         input_count: UInt32(inputCount), register_count: UInt32(inputCount + ops.count),
                         operation_count: UInt32(ops.count), operation_capacity: UInt32(ops.count),
                         output_count: UInt32(roots.count), output_capacity: UInt32(roots.count),
                         source_hash: hash, operations: UnsafePointer(arena.make(ops)),
                         output_registers: UnsafePointer(arena.make(roots)))
    }

    static func op(_ opcode: Int, _ destination: Int, _ lhs: Int = 0, _ rhs: Int = 0,
                   immediate: Int32 = 0, table: UInt32 = 0) -> HMExactOpV1 {
        HMExactOpV1(opcode: UInt32(opcode), destination: UInt32(destination), lhs: UInt32(lhs),
                    rhs: UInt32(rhs), immediate: immediate, table_id: table, flags: 0, reserved: 0)
    }

    func evaluateCPU(inputs: [Int32], tables: [ParityTable]) -> RawResult {
        let arena = ParityArena()
        var program = ExactProgramSpec.program(inputCount, operations, roots, arena, hash: hash)
        let words = inputs.map { UInt32(bitPattern: $0) }
        let views = tables.map {
            HMTableViewV1(table_id: $0.id, length: UInt32($0.cells.count), capacity: $0.capacity,
                          reserved: 0, cells: UnsafePointer(arena.make($0.cells)))
        }
        let scratch = arena.make([UInt32](), minimum: inputs.count + operations.count)
        let out = arena.make([UInt32](), minimum: roots.count)
        var produced: UInt32 = 0
        let status = HM_EvaluateExactProgramV1(&program, UnsafePointer(arena.make(words)), UInt32(words.count),
                                               UnsafePointer(arena.make(views)), UInt32(views.count),
                                               scratch, UInt32(inputs.count + operations.count),
                                               out, UInt32(roots.count), &produced)
        guard status == UInt32(HM_MODULE_EXACT) else { return RawResult(status: status) }
        return RawResult(status: status,
                         outputs: (0..<Int(produced)).map { out[$0] },
                         registers: (0..<inputs.count + operations.count).map { scratch[$0] })
    }
}

final class ExactMetalRunner {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private(set) var encodeNs: UInt64 = 0
    private(set) var waitNs: UInt64 = 0

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Bridge/CircuitExactV1.msl")
        guard let text = try? String(contentsOf: source, encoding: .utf8) else { return nil }
        let options = MTLCompileOptions()
        if #available(macOS 15.0, *) { options.mathMode = .safe } else { options.fastMathEnabled = false }
        guard let library = try? device.makeLibrary(source: text, options: options),
              let function = library.makeFunction(name: "evaluateExactCircuitV1"),
              let pipeline = try? device.makeComputePipelineState(function: function) else { return nil }
        self.device = device; self.queue = queue; self.pipeline = pipeline
    }

    func evaluate(_ spec: ExactProgramSpec, inputs: [Int32], tables: [ParityTable],
                  deadlineNs: UInt64 = .max) -> RawResult {
        let t0 = DispatchTime.now().uptimeNanoseconds
        var descriptors: [HMExactTableDescriptorV1] = []
        var cells: [Int32] = []
        for t in tables {
            descriptors.append(HMExactTableDescriptorV1(table_id: t.id, length: UInt32(t.cells.count),
                                                        capacity: t.capacity, offset: UInt32(cells.count), reserved: 0))
            cells += t.cells
        }
        var d = HMExactDispatchV1()
        d.abi_version = UInt32(HM_EXACT_PROGRAM_ABI_VERSION)
        d.integer_encoding = UInt32(HM_EXACT_INTEGER_ENCODING_V1)
        d.input_count = UInt32(inputs.count); d.input_capacity = d.input_count
        d.register_count = UInt32(inputs.count + spec.operations.count); d.scratch_capacity = d.register_count
        d.operation_count = UInt32(spec.operations.count); d.operation_capacity = d.operation_count
        d.output_count = UInt32(spec.roots.count); d.output_capacity = d.output_count
        d.table_count = UInt32(descriptors.count); d.table_capacity = d.table_count
        d.table_cell_count = UInt32(cells.count); d.table_cell_capacity = d.table_cell_count
        d.output_register_capacity = d.output_count; d.status_capacity = 2
        func buffer<T>(_ v: [T]) -> MTLBuffer {
            v.isEmpty ? device.makeBuffer(length: 4, options: .storageModeShared)!
                : v.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)! }
        }
        let status = device.makeBuffer(length: 8, options: .storageModeShared)!
        let words = status.contents().bindMemory(to: UInt32.self, capacity: 2)
        let prepared = HM_PrepareExactDispatchV1(&d, words, 2)
        guard prepared == UInt32(HM_MODULE_EXACT) else { return RawResult(status: prepared) }
        let scratch = device.makeBuffer(length: max(4, Int(d.register_count) * 4), options: .storageModeShared)!
        let out = device.makeBuffer(length: max(4, spec.roots.count * 4), options: .storageModeShared)!
        let buffers = [buffer(inputs.map { UInt32(bitPattern: $0) }), buffer(spec.operations), buffer(descriptors),
                       buffer(cells), buffer(spec.roots), scratch, out, status,
                       withUnsafeBytes(of: &d) { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)! }]
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            return RawResult(status: UInt32(HM_MODULE_EXECUTION_ERROR))
        }
        encoder.setComputePipelineState(pipeline)
        for (i, b) in buffers.enumerated() { encoder.setBuffer(b, offset: 0, index: i) }
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        let t1 = DispatchTime.now().uptimeNanoseconds
        command.commit(); command.waitUntilCompleted()
        let t2 = DispatchTime.now().uptimeNanoseconds
        encodeNs = t1 - t0; waitNs = t2 - t1
        // A late completion owns only this call's buffers; it can never reach a later tic.
        guard command.status == .completed, t2 - t0 <= deadlineNs else {
            return RawResult(status: UInt32(HM_MODULE_EXECUTION_ERROR))
        }
        guard words[0] == UInt32(HM_MODULE_EXACT) else { return RawResult(status: words[0]) }
        let o = out.contents().bindMemory(to: UInt32.self, capacity: max(1, spec.roots.count))
        let r = scratch.contents().bindMemory(to: UInt32.self, capacity: max(1, Int(d.register_count)))
        return RawResult(status: words[0], outputs: (0..<Int(words[1])).map { o[$0] },
                         registers: (0..<Int(d.register_count)).map { r[$0] })
    }
}

// MARK: - Envelope validation and canonical commit

private func toC(_ e: ParityEvent) -> HMModuleEventV1 {
    var c = HMModuleEventV1()
    c.phase = e.phase; c.event_id = e.eventID; c.emitter_slot = e.emitter; c.local_sequence = e.sequence
    c.source_id = e.source; c.target_id = e.target; c.payload_count = UInt32(e.payload.count); c.flags = e.flags
    withUnsafeMutableBytes(of: &c.payload) { raw in
        let p = raw.bindMemory(to: Int32.self)
        for (i, v) in e.payload.prefix(4).enumerated() { p[i] = v }
    }
    return c
}

private func fromC(_ c: HMModuleEventV1) -> ParityEvent {
    var payload: [Int32] = []
    withUnsafeBytes(of: c.payload) { raw in
        let p = raw.bindMemory(to: Int32.self)
        payload = (0..<Int(min(c.payload_count, 4))).map { p[$0] }
    }
    return ParityEvent(phase: c.phase, eventID: c.event_id, emitter: c.emitter_slot, sequence: c.local_sequence,
                       source: c.source_id, target: c.target_id, flags: c.flags, payload: payload)
}

/// Runs the frozen CircuitModuleV1 validator. Any non-exact outcome commits nothing.
func finalizeParity(_ m: ParityModule, _ c: ParityCase, _ raw: RawResult, tamper: Tamper = .none) -> ParityResult {
    func rejected(_ s: UInt32) -> ParityResult { ParityResult(status: s) }
    guard raw.status == UInt32(HM_MODULE_EXACT) else { return rejected(raw.status) }
    let arena = ParityArena()
    let tables = c.tables.map {
        HMTableViewV1(table_id: $0.id, length: UInt32($0.cells.count), capacity: $0.capacity,
                      reserved: 0, cells: UnsafePointer(arena.make($0.cells)))
    }
    var input = HMModuleInputV1()
    input.abi_version = UInt32(HM_CIRCUIT_MODULE_ABI_VERSION)
    input.program_version = m.programVersion
    input.integer_encoding = UInt32(HM_EXACT_INTEGER_ENCODING_V1)
    input.module_id = m.moduleID; input.tic_id = c.ticID; input.source_hash = m.sourceHash
    input.input_count = UInt32(c.inputs.count); input.input_capacity = input.input_count
    input.state_count = UInt32(c.state.count); input.state_capacity = input.state_count
    input.table_count = UInt32(tables.count); input.table_capacity = input.table_count
    input.output_count = UInt32(m.requiredOutputs); input.output_capacity = c.outputCapacity
    input.state_delta_capacity = c.deltaCapacity; input.event_capacity = c.eventCapacity
    input.inputs = UnsafePointer(arena.make(c.inputs)); input.state_before = UnsafePointer(arena.make(c.state))
    input.tables = UnsafePointer(arena.make(tables))

    var result = HMModuleResultV1()
    result.abi_version = input.abi_version; result.module_id = input.module_id
    result.tic_id = input.tic_id; result.source_hash = input.source_hash
    result.status = UInt32(HM_MODULE_EXACT)
    result.output_count = UInt32(raw.outputs.count); result.output_capacity = c.outputCapacity
    result.state_delta_count = UInt32(raw.deltas.count); result.state_delta_capacity = c.deltaCapacity
    result.event_count = UInt32(raw.events.count); result.event_capacity = c.eventCapacity
    result.outputs = arena.make(raw.outputs.map { Int32(bitPattern: $0) }, minimum: Int(c.outputCapacity) + 1)
    var deltas = raw.deltas.map { HMStateDeltaV1(array_id: $0.array, element_index: $0.element, cell_id: $0.cell,
                                                 before: $0.before, after: $0.after) }
    var events = raw.events.map(toC)
    switch tamper {
    case .none: break
    case .badABI: result.abi_version = 2
    case .staleHash: result.source_hash ^= 1
    case .unknownEvent: if !events.isEmpty { events[0].event_id = 0x7777_7777 }
    case .malformedSpan: result.output_count = result.output_capacity + 1
    case .outOfOrderDeltas: if deltas.count > 1 { deltas.swapAt(0, 1) }
    case .partial: result.output_count = UInt32(max(0, m.requiredOutputs - 1))
    }
    result.state_deltas = arena.make(deltas, minimum: Int(c.deltaCapacity) + 1)
    result.events = arena.make(events, minimum: Int(c.eventCapacity) + 1)
    let status = HM_FinalizeModuleResultV1(&input, &result, m.moduleID, m.sourceHash)
    guard status == UInt32(HM_MODULE_EXACT) else {
        require(result.output_count == 0 && result.state_delta_count == 0 && result.event_count == 0,
                "\(m.name): rejected result kept a partial commit")
        return rejected(status)
    }
    var bytes = [UInt8](repeating: 0, count: HM_CanonicalModuleResultSizeV1(&result))
    require(HM_SerializeModuleResultV1(&result, &bytes, bytes.count) == bytes.count, "\(m.name): result serialization")
    return ParityResult(
        status: status,
        outputs: (0..<Int(result.output_count)).map { UInt32(bitPattern: result.outputs[$0]) },
        deltas: (0..<Int(result.state_delta_count)).map {
            let d = result.state_deltas[$0]
            return ParityDelta(array: d.array_id, element: d.element_index, cell: d.cell_id, before: d.before, after: d.after)
        },
        events: (0..<Int(result.event_count)).map { fromC(result.events[$0]) },
        bytes: bytes)
}

/// First differing field, or nil when two committed results are identical.
func localizeMismatch(_ a: ParityResult, _ b: ParityResult) -> String? {
    if a.status != b.status { return "status \(a.status) vs \(b.status)" }
    if a.outputs.count != b.outputs.count { return "output count \(a.outputs.count) vs \(b.outputs.count)" }
    for i in a.outputs.indices where a.outputs[i] != b.outputs[i] {
        return String(format: "outputs[%d] 0x%08x vs 0x%08x", i, a.outputs[i], b.outputs[i])
    }
    if a.deltas.count != b.deltas.count { return "delta count \(a.deltas.count) vs \(b.deltas.count)" }
    for i in a.deltas.indices where a.deltas[i] != b.deltas[i] { return "deltas[\(i)] \(a.deltas[i]) vs \(b.deltas[i])" }
    if a.events.count != b.events.count { return "event count \(a.events.count) vs \(b.events.count)" }
    for i in a.events.indices where a.events[i] != b.events[i] { return "events[\(i)] \(a.events[i]) vs \(b.events[i])" }
    return a.bytes == b.bytes ? nil : "canonical bytes differ"
}

/// A disagreement commits nothing: the same-phase oracle result stays authoritative.
func paritySelect(oracle: ParityResult, candidate: ParityResult) -> (committed: ParityResult, status: UInt32, detail: String?) {
    if let detail = localizeMismatch(oracle, candidate) {
        return (oracle, UInt32(HM_MODULE_PARITY_MISMATCH), detail)
    }
    return (candidate, UInt32(HM_MODULE_EXACT), nil)
}

// MARK: - Reporting

final class ParityStats {
    private var samples: [String: [UInt64]] = [:]
    var lateTics = 0, tics = 0
    func add(_ key: String, _ ns: UInt64) { samples[key, default: []].append(ns) }
    static let ticNs: UInt64 = 1_000_000_000 / 35
    func lines(for module: String) -> [String] {
        func p(_ xs: [UInt64], _ q: Double) -> Double {
            let s = xs.sorted(); return Double(s[min(s.count - 1, Int(Double(s.count - 1) * q))]) / 1_000_000
        }
        var out = ["\(module) latency (ms)          p50      p95      p99      max   n"]
        for key in samples.keys.sorted() {
            let xs = samples[key]!
            out.append(String(format: "  %-24@ %8.4f %8.4f %8.4f %8.4f %d", key as NSString, p(xs, 0.5), p(xs, 0.95), p(xs, 0.99), p(xs, 1), xs.count))
        }
        out.append("  whole-tic pacing: \(lateTics) of \(tics) tics exceeded the \(ParityStats.ticNs / 1000) us tic period (report only, no hardware gate)")
        return out
    }
}

final class ParityTrace {
    let enabled: Bool
    private(set) var samples: [[UInt32]] = []
    init(enabled: Bool) { self.enabled = enabled }
    /// One sample in four; off mode never stores an operation value.
    func record(index: Int, registers: [UInt32]) {
        if enabled && index % 4 == 0 { samples.append(Array(registers.prefix(64))) }
    }
}

// MARK: - Manifest (content-addressed fixture digest per module)

func parityManifest(_ m: ParityModule, cases: Int = 1000) -> Data {
    var digest = WordWriter()
    for i in 0..<cases {
        let c = m.makeCase(seed: parityCaseSeed(i), index: i)
        digest.u64(ParityFixture(moduleID: m.moduleID, programVersion: m.programVersion, sourceHash: m.sourceHash,
                                 testCase: c, expected: finalizeParity(m, c, m.oracle(c))).contentHash)
    }
    let vectors: [[String: Any]] = m.adversarial().map { v in
        let expected = finalizeParity(m, v.testCase, m.oracle(v.testCase), tamper: v.tamper)
        return ["name": v.name, "expectedStatus": v.expected,
                "fixture": String(format: "%016llx", ParityFixture(moduleID: m.moduleID, programVersion: m.programVersion,
                    sourceHash: m.sourceHash, testCase: v.testCase, expected: expected).contentHash)]
    }
    let manifest: [String: Any] = [
        "schema": 1, "fixtureFormat": parityFixtureVersion, "module": m.name,
        "moduleID": m.moduleID, "programVersion": m.programVersion,
        "sourceHash": String(format: "0x%016llx", m.sourceHash),
        "baseSeed": String(format: "0x%016llx", parityBaseSeed),
        "generatedCases": cases, "generatedCasesDigest": String(format: "%016llx", fnv1a64(digest.bytes)),
        "adversarial": vectors,
    ]
    return try! JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8)
}

func parityRepoRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

// MARK: - Suite

func parityCaseCount(_ args: [String]) -> Int {
    args.contains("--micro") ? 20 : (args.contains("--smoke") ? 200 : (args.contains("--quick") ? 1000 : 100_000))
}

func runParityModule(_ m: ParityModule, count: Int, runner: ExactMetalRunner, stats: ParityStats) {
    var statuses: [UInt32: Int] = [:]
    var reported = 0, mismatches = 0
    func compare(_ label: String, _ i: Int, _ oracle: ParityResult, _ other: ParityResult) {
        let verdict = paritySelect(oracle: oracle, candidate: other)
        if verdict.status != UInt32(HM_MODULE_EXACT) {
            mismatches += 1
            if reported < 4 { reported += 1; print("\(m.name) \(label) mismatch at case \(i): \(verdict.detail ?? "")") }
        }
    }
    for i in 0..<count {
        let c = m.makeCase(seed: parityCaseSeed(i), index: i)
        var t = DispatchTime.now().uptimeNanoseconds
        let rawOracle = m.oracle(c)
        stats.add("oracle", DispatchTime.now().uptimeNanoseconds - t)
        t = DispatchTime.now().uptimeNanoseconds
        let rawCPU = m.cpu(c)
        stats.add("cpu-evaluation", DispatchTime.now().uptimeNanoseconds - t)
        let rawMetal = m.metal(c, runner, deadlineNs: .max)
        stats.add("metal-dispatch-encode", runner.encodeNs)
        stats.add("metal-submit-wait", runner.waitNs)
        t = DispatchTime.now().uptimeNanoseconds
        let oracle = finalizeParity(m, c, rawOracle)
        let cpu = finalizeParity(m, c, rawCPU)
        let metal = finalizeParity(m, c, rawMetal)
        let validate = DispatchTime.now().uptimeNanoseconds - t
        stats.add(oracle.status == UInt32(HM_MODULE_EXACT) ? "validate-commit-accepted" : "validate-commit-rejected", validate / 3)
        stats.tics += 1
        if runner.encodeNs + runner.waitNs + validate / 3 > ParityStats.ticNs { stats.lateTics += 1 }
        statuses[oracle.status, default: 0] += 1
        compare("CPU", i, oracle, cpu); compare("Metal", i, oracle, metal)
    }
    require(mismatches == 0, "\(m.name): \(mismatches) parity mismatches")
    let mix = statuses.keys.sorted().map { "status \($0): \(statuses[$0]!)" }.joined(separator: ", ")
    print("\(m.name): \(count) seeded snapshots exact across oracle, CPU, Metal (\(mix))")
}

func runParityAdversarial(_ m: ParityModule, runner: ExactMetalRunner) {
    var seen = Set<UInt32>()
    for v in m.adversarial() {
        let oracle = finalizeParity(m, v.testCase, m.oracle(v.testCase), tamper: v.tamper)
        let cpu = finalizeParity(m, v.testCase, m.cpu(v.testCase), tamper: v.tamper)
        let metal = finalizeParity(m, v.testCase, m.metal(v.testCase, runner, deadlineNs: .max), tamper: v.tamper)
        require(oracle.status == v.expected, "\(m.name) \(v.name): oracle status \(oracle.status), expected \(v.expected)")
        require(localizeMismatch(oracle, cpu) == nil, "\(m.name) \(v.name): CPU \(localizeMismatch(oracle, cpu) ?? "")")
        require(localizeMismatch(oracle, metal) == nil, "\(m.name) \(v.name): Metal \(localizeMismatch(oracle, metal) ?? "")")
        require(oracle.status == UInt32(HM_MODULE_EXACT) || (oracle.outputs.isEmpty && oracle.deltas.isEmpty && oracle.events.isEmpty),
                "\(m.name) \(v.name): rejection committed data")
        seen.insert(oracle.status)
    }
    // Late completion: committed nothing, and the very next tic is unaffected.
    let probe = m.makeCase(seed: parityCaseSeed(0), index: 0)
    let late = finalizeParity(m, probe, m.metal(probe, runner, deadlineNs: 0))
    require(late.status == UInt32(HM_MODULE_EXECUTION_ERROR) && late.outputs.isEmpty && late.bytes.isEmpty,
            "\(m.name): late Metal completion committed")
    require(localizeMismatch(finalizeParity(m, probe, m.oracle(probe)),
                             finalizeParity(m, probe, m.metal(probe, runner, deadlineNs: .max))) == nil,
            "\(m.name): late completion leaked into the next tic")
    seen.insert(late.status)
    // Mismatch localization names the first differing field and commits the oracle.
    let good = finalizeParity(m, probe, m.oracle(probe))
    if good.status == UInt32(HM_MODULE_EXACT), !good.outputs.isEmpty {
        var bad = good; bad.outputs[good.outputs.count - 1] ^= 1
        let verdict = paritySelect(oracle: good, candidate: bad)
        require(verdict.status == UInt32(HM_MODULE_PARITY_MISMATCH) && verdict.committed == good
                && verdict.detail?.hasPrefix("outputs[\(good.outputs.count - 1)]") == true,
                "\(m.name): mismatch localization")
        seen.insert(verdict.status)
    }
    let missing = (0...12).filter { !seen.contains(UInt32($0)) }
    require(missing.isEmpty, "\(m.name): adversarial vectors never produced statuses \(missing)")
    print("\(m.name): adversarial vectors covered all 13 statuses; late completion and mismatch localization verified")
}

func runParityFixtures(_ m: ParityModule, runner: ExactMetalRunner) {
    func fixture(_ i: Int) -> ParityFixture {
        let c = m.makeCase(seed: parityCaseSeed(i), index: i)
        return ParityFixture(moduleID: m.moduleID, programVersion: m.programVersion, sourceHash: m.sourceHash,
                             testCase: c, expected: finalizeParity(m, c, m.oracle(c)))
    }
    // Deterministic regeneration and parse round-trip.
    let a = fixture(7).serialized(), b = fixture(7).serialized()
    require(a == b, "\(m.name): fixture regeneration is not byte-identical")
    require(ParityFixture.parse(a)?.serialized() == a, "\(m.name): fixture round-trip")
    // Malformed length/version/hash/count fail closed.
    var variants: [[UInt8]] = [Array(a.dropLast(4)), Array(a.dropLast()), a + [0, 0, 0, 0], []]
    var v = a; v[4] ^= 1; variants.append(v)                 // unknown fixture version
    v = a; v[0] ^= 1; variants.append(v)                     // wrong magic
    v = a; v[a.count - 1] ^= 1; variants.append(v)           // stale content hash
    v = a; v[a.count / 2] ^= 1; variants.append(v)           // payload changed, hash kept
    v = a; v[84] = 0xff; v[85] = 0xff; variants.append(v)    // oversized input count
    for (n, bad) in variants.enumerated() { require(ParityFixture.parse(bad) == nil, "\(m.name): malformed fixture variant \(n) parsed") }
    // Replay: the stored oracle result must match fresh CPU and Metal evaluation.
    for i in [0, 1, 7, 99] {
        let f = ParityFixture.parse(fixture(i).serialized())!
        let cpu = finalizeParity(m, f.testCase, m.cpu(f.testCase))
        let metal = finalizeParity(m, f.testCase, m.metal(f.testCase, runner, deadlineNs: .max))
        for other in [cpu, metal] {
            require(other.status == f.expected.status && other.outputs == f.expected.outputs
                    && other.deltas == f.expected.deltas && other.events == f.expected.events,
                    "\(m.name): fixture replay disagrees")
        }
    }
    // Manifest freshness: regenerated bytes equal the committed copy; one flipped byte is rejected.
    let fresh = parityManifest(m)
    require(fresh == parityManifest(m), "\(m.name): manifest generation is not deterministic")
    let committed = try? Data(contentsOf: parityRepoRoot().appendingPathComponent(m.manifestPath))
    require(committed == fresh, "\(m.name): committed manifest \(m.manifestPath) is stale")
    var stale = committed!; stale[stale.count / 2] ^= 1
    require(stale != fresh, "\(m.name): one-byte manifest change was accepted")
    print("\(m.name): fixtures byte-identical on regeneration; \(variants.count) malformed variants rejected; manifest fresh and one-byte change rejected")
}

func runParityVisualization(_ m: ParityModule) {
    let off = ParityTrace(enabled: false), on = ParityTrace(enabled: true)
    for i in 0..<1000 {
        let c = m.makeCase(seed: parityCaseSeed(i), index: i)
        let raw = m.cpu(c)
        off.record(index: i, registers: raw.registers); on.record(index: i, registers: raw.registers)
        require(localizeMismatch(finalizeParity(m, c, raw), finalizeParity(m, c, m.cpu(c))) == nil,
                "\(m.name): visualization changed a result")
    }
    require(off.samples.isEmpty, "\(m.name): visualization-off recorded operation values")
    require(on.samples.count == 250 && on.samples.allSatisfy { $0.count <= 64 }, "\(m.name): sampled trace bounds")
    print("\(m.name): visualization off recorded 0 values; on sampled \(on.samples.count) traces of <= 64 values")
}

/// Handles the generic CLI. Returns after the default suite unless a subcommand exits.
func runParity(_ args: [String]) {
    func value(after flag: String, _ n: Int = 1) -> [String]? {
        guard let at = args.firstIndex(of: flag), at + n < args.count else { return nil }
        return Array(args[(at + 1)...(at + n)])
    }
    func module(_ name: String) -> ParityModule {
        guard let m = ParityRegistry.modules.first(where: { $0.name == name }) else {
            fputs("FAIL: unknown parity module \(name)\n", stderr); exit(1)
        }
        return m
    }
    if let v = value(after: "--emit-parity-manifest", 2) {
        try! parityManifest(module(v[0])).write(to: URL(fileURLWithPath: v[1]))
        print("parity manifest: \(v[0]) -> \(v[1])"); exit(0)
    }
    guard let runner = ExactMetalRunner() else { fputs("FAIL: Apple Silicon Metal device unavailable\n", stderr); exit(1) }
    if let v = value(after: "--parity-capture", 3) {
        let m = module(v[0]); var blob = WordWriter()
        for i in 0..<(Int(v[2]) ?? 0) {
            let c = m.makeCase(seed: parityCaseSeed(i), index: i)
            let bytes = ParityFixture(moduleID: m.moduleID, programVersion: m.programVersion, sourceHash: m.sourceHash,
                                      testCase: c, expected: finalizeParity(m, c, m.oracle(c))).serialized()
            blob.u32(UInt32(bytes.count)); blob.bytes += bytes
        }
        try! Data(blob.bytes).write(to: URL(fileURLWithPath: v[1])); print("captured \(v[2]) fixtures"); exit(0)
    }
    if let v = value(after: "--parity-replay") {   // length-prefixed fixture stream, e.g. a WAD-trace capture
        var r = WordReader(bytes: [UInt8](try! Data(contentsOf: URL(fileURLWithPath: v[0]))))
        var n = 0
        while r.remainingWords > 0 {
            guard let len = r.u32(), Int(len) <= r.bytes.count - r.at,
                  let f = ParityFixture.parse(Array(r.bytes[r.at..<r.at + Int(len)])),
                  let m = ParityRegistry.modules.first(where: { $0.moduleID == f.moduleID }) else {
                fputs("FAIL: malformed or unregistered fixture \(n) in \(v[0])\n", stderr); exit(1)
            }
            r.at += Int(len)
            for other in [finalizeParity(m, f.testCase, m.cpu(f.testCase)),
                          finalizeParity(m, f.testCase, m.metal(f.testCase, runner, deadlineNs: .max))] {
                require(other.status == f.expected.status && other.outputs == f.expected.outputs
                        && other.deltas == f.expected.deltas && other.events == f.expected.events,
                        "replay \(n): disagrees with captured oracle")
            }
            n += 1
        }
        print("replayed \(n) captured fixtures exactly on CPU and Metal"); exit(0)
    }
    let only = value(after: "--parity-module")?.first
    let count = parityCaseCount(args)
    for m in ParityRegistry.modules where only == nil || only == m.name {
        let stats = ParityStats()
        runParityModule(m, count: count, runner: runner, stats: stats)
        runParityAdversarial(m, runner: runner)
        runParityFixtures(m, runner: runner)
        runParityVisualization(m)
        stats.lines(for: m.name).forEach { print($0) }
    }
    if args.contains("--parity") { exit(0) }
}
