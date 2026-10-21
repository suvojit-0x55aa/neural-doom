import Foundation

// Synthetic conformance module: exercises every exact opcode, every status, and
// delta/event emission without implementing any Doom subsystem. Later modules
// copy this shape in their own directory and register in ParityRegistry.swift.

enum ParityRegistry {
    static let modules: [ParityModule] = [SyntheticConformance()]
}

struct SyntheticConformance: ParityModule {
    let name = "conformance.synthetic"
    // Reuses an assigned registry ID; the synthetic module claims no coverage.
    let moduleID = UInt32(HM_MODULE_FRAME_COMPOSITION)
    let programVersion: UInt32 = 1
    let requiredOutputs = 10
    let manifestPath = "Docs/manifests/conformance-synthetic.json"
    static let tableID = UInt32(HM_TABLE_VERTICES)
    static let tableLength = 16

    // Registers: 0-7 inputs, 8-17 operations. Roots are registers 8...17.
    static let spec: ExactProgramSpec = {
        func op(_ code: Int, _ dst: Int, _ lhs: Int = 0, _ rhs: Int = 0, immediate: Int32 = 0, table: UInt32 = 0) -> HMExactOpV1 {
            ExactProgramSpec.op(code, dst, lhs, rhs, immediate: immediate, table: table)
        }
        return ExactProgramSpec(inputCount: 8, operations: [
            op(Int(HM_EXACT_OP_TABLE_READ_I32), 8, 0, table: tableID),
            op(Int(HM_EXACT_OP_ADD_I32), 9, 1, 2),
            op(Int(HM_EXACT_OP_FIXED_MUL_16_16), 10, 3, 4),
            op(Int(HM_EXACT_OP_FIXED_DIV_16_16), 11, 3, 5),
            op(Int(HM_EXACT_OP_ANGLE_ADD_U32), 12, 6, 7, immediate: 0x4000_0000),
            op(Int(HM_EXACT_OP_COMPARE_LT_I32), 13, 1, 2),
            op(Int(HM_EXACT_OP_COMPARE_EQUAL_BITS), 14, 6, 7),
            op(Int(HM_EXACT_OP_GATE), 15, 1, 13),
            op(Int(HM_EXACT_OP_SUB_I32), 16, 1, 2),
            op(Int(HM_EXACT_OP_CONSTANT), 17, immediate: 12_345),
        ], roots: Array(8...17))
    }()
    var sourceHash: UInt64 { Self.spec.hash }

    private func makeBase(_ r: inout ParityRNG, index: Int) -> ParityCase {
        var inputs: [Int32] = [r.range(0, 15), r.range(-(1 << 30), 1 << 30), r.range(-(1 << 30), 1 << 30),
                               r.range(-(1 << 23), 1 << 23), r.range(-(1 << 23), 1 << 23),
                               r.span(32) == 0 ? 0 : r.range(-(1 << 20), 1 << 20),
                               r.range(.min, .max), r.range(.min + 1, .max)]
        if r.span(8) == 0 { inputs[7] = inputs[6] }
        if r.span(64) == 0 { inputs[7] = .min }                           // unsupported-domain sentinel
        let state = (0..<8).map { _ in r.range(-1000, 1000) }
        let table = (0..<Self.tableLength).map { _ in r.range(.min, .max) }
        return ParityCase(ticID: UInt64(index), seed: 0, inputs: inputs, state: state,
                          tables: [ParityTable(id: Self.tableID, cells: table, capacity: UInt32(Self.tableLength))],
                          outputCapacity: 10, deltaCapacity: 8, eventCapacity: 2)
    }

    func makeCase(seed: UInt64, index: Int) -> ParityCase {
        var r = ParityRNG(seed: seed)
        var c = makeBase(&r, index: index)
        c.seed = seed
        return c
    }

    // MARK: Module-level gate and emission (shared by all three evaluators)

    private func gate(_ c: ParityCase) -> UInt32? {
        if c.inputs.count > 8 || c.state.count > 8 || (c.tables.first?.cells.count ?? 0) > Self.tableLength {
            return UInt32(HM_MODULE_CAPACITY_EXCEEDED)
        }
        if c.inputs.count < 8 || c.state.count < 8 { return UInt32(HM_MODULE_MALFORMED_SPAN) }
        if c.inputs[7] == .min { return UInt32(HM_MODULE_UNSUPPORTED_DOMAIN) }
        return nil
    }

    /// Deterministic deltas/events derived from committed outputs and prior state.
    private func emit(_ c: ParityCase, _ outputs: [UInt32]) -> ([ParityDelta], [ParityEvent]) {
        var deltas: [ParityDelta] = []
        for i in 0..<8 where outputs[i] != UInt32(bitPattern: c.state[i]) {
            deltas.append(ParityDelta(array: UInt32(HM_WORLD_ARRAY_PLAYERS), element: 0, cell: UInt32(1 + i),
                                      before: c.state[i], after: Int32(bitPattern: outputs[i])))
        }
        var events: [ParityEvent] = []
        func event(_ id: Int, _ seq: UInt32) -> ParityEvent {
            ParityEvent(phase: UInt32(HM_PHASE_TIC_COMMANDS), eventID: UInt32(id), emitter: 0, sequence: seq,
                        source: 1, target: 2, flags: 0, payload: [Int32(bitPattern: outputs[8])])
        }
        if outputs[5] == 1 { events.append(event(Int(HM_EVENT_SOUND), 0)) }
        if outputs[6] == 1 { events.append(event(Int(HM_EVENT_MESSAGE), 1)) }
        return (deltas, events)
    }

    private func finish(_ c: ParityCase, _ eval: RawResult) -> RawResult {
        guard eval.status == UInt32(HM_MODULE_EXACT) else { return eval }
        let (d, e) = emit(c, eval.outputs)
        var out = eval; out.deltas = d; out.events = e
        return out
    }

    // MARK: Evaluators

    /// Independent scalar oracle in Int64; never touches the exact evaluator.
    func oracle(_ c: ParityCase) -> RawResult {
        if let g = gate(c) { return RawResult(status: g) }
        let i = c.inputs
        func fits(_ v: Int64) -> Bool { v >= Int64(Int32.min) && v <= Int64(Int32.max) }
        func word(_ v: Int64) -> UInt32 { UInt32(bitPattern: Int32(v)) }
        var out = [UInt32](repeating: 0, count: 10)
        guard let table = c.tables.first(where: { $0.id == Self.tableID }),
              i[0] >= 0, Int(i[0]) < table.cells.count else { return RawResult(status: UInt32(HM_MODULE_TABLE_BOUNDS)) }
        out[0] = UInt32(bitPattern: table.cells[Int(i[0])])
        let sum = Int64(i[1]) + Int64(i[2])
        guard fits(sum) else { return RawResult(status: UInt32(HM_MODULE_INTEGER_OVERFLOW)) }
        out[1] = word(sum)
        let product = Int64(i[3]) * Int64(i[4])
        var mul = product / 65536
        if product < 0 && product % 65536 != 0 { mul -= 1 }
        guard fits(mul) else { return RawResult(status: UInt32(HM_MODULE_INTEGER_OVERFLOW)) }
        out[2] = word(mul)
        guard i[5] != 0 else { return RawResult(status: UInt32(HM_MODULE_EXECUTION_ERROR)) }
        let quotient = Int64(i[3]) * 65536 / Int64(i[5])
        guard fits(quotient) else { return RawResult(status: UInt32(HM_MODULE_INTEGER_OVERFLOW)) }
        out[3] = word(quotient)
        out[4] = UInt32(bitPattern: i[6]) &+ UInt32(bitPattern: i[7]) &+ 0x4000_0000
        out[5] = i[1] < i[2] ? 1 : 0
        out[6] = i[6] == i[7] ? 1 : 0
        out[7] = out[5] != 0 ? UInt32(bitPattern: i[1]) : 0
        let diff = Int64(i[1]) - Int64(i[2])
        guard fits(diff) else { return RawResult(status: UInt32(HM_MODULE_INTEGER_OVERFLOW)) }
        out[8] = word(diff)
        out[9] = 12_345
        return finish(c, RawResult(status: UInt32(HM_MODULE_EXACT), outputs: out))
    }

    func cpu(_ c: ParityCase) -> RawResult {
        if let g = gate(c) { return RawResult(status: g) }
        return finish(c, Self.spec.evaluateCPU(inputs: c.inputs, tables: c.tables))
    }

    func metal(_ c: ParityCase, _ runner: ExactMetalRunner, deadlineNs: UInt64) -> RawResult {
        if let g = gate(c) { return RawResult(status: g) }
        return finish(c, runner.evaluate(Self.spec, inputs: c.inputs, tables: c.tables, deadlineNs: deadlineNs))
    }

    // MARK: Named adversarial vectors

    func adversarial() -> [ParityVector] {
        func base(_ edit: (inout ParityCase) -> Void = { _ in }) -> ParityCase {
            var c = ParityCase(ticID: 1, seed: 0, inputs: [3, 100, 200, 65_536, 98_304, 65_536, 5, 5],
                               state: Array(repeating: 0, count: 8),
                               tables: [ParityTable(id: Self.tableID, cells: (0..<16).map { Int32($0 * 7 - 40) },
                                                    capacity: 16)],
                               outputCapacity: 10, deltaCapacity: 8, eventCapacity: 2)
            edit(&c); return c
        }
        let ok = UInt32(HM_MODULE_EXACT)
        func v(_ n: String, _ expected: Int, _ tamper: Tamper = .none, _ edit: (inout ParityCase) -> Void = { _ in }) -> ParityVector {
            ParityVector(name: n, testCase: base(edit), tamper: tamper, expected: UInt32(expected))
        }
        return [
            ParityVector(name: "nominal", testCase: base(), expected: ok),
            v("integer extremes", Int(ok)) { $0.inputs = [15, .max - 1, 1, 1 << 20, -(1 << 20), 65_536, .min + 1, .max] },
            v("angle wrap and equal bits", Int(ok)) { $0.inputs[6] = -1; $0.inputs[7] = -1 },
            v("full delta span", Int(ok)) { $0.state = [9, 9, 9, 9, 9, 9, 9, 9] },
            v("zero deltas", Int(ok)) {
                // State already equals the outputs, so nothing may be committed as a delta.
                let raw = SyntheticConformance().oracle(base())
                $0.state = (0..<8).map { Int32(bitPattern: raw.outputs[$0]) }
            },
            v("unsupported domain", Int(HM_MODULE_UNSUPPORTED_DOMAIN)) { $0.inputs[7] = .min },
            v("capacity+1 inputs", Int(HM_MODULE_CAPACITY_EXCEEDED)) { $0.inputs.append(0) },
            v("capacity+1 table", Int(HM_MODULE_CAPACITY_EXCEEDED)) { $0.tables[0].cells.append(0); $0.tables[0].capacity = 17 },
            v("zero-length inputs", Int(HM_MODULE_MALFORMED_SPAN)) { $0.inputs = [] },
            v("short state", Int(HM_MODULE_MALFORMED_SPAN)) { $0.state.removeLast() },
            v("absent table", Int(HM_MODULE_TABLE_BOUNDS)) { $0.tables = [] },
            v("table index at length", Int(HM_MODULE_TABLE_BOUNDS)) { $0.inputs[0] = 16 },
            v("negative table index", Int(HM_MODULE_TABLE_BOUNDS)) { $0.inputs[0] = -1 },
            v("add overflow", Int(HM_MODULE_INTEGER_OVERFLOW)) { $0.inputs[1] = .max; $0.inputs[2] = 1 },
            v("div overflow", Int(HM_MODULE_INTEGER_OVERFLOW)) { $0.inputs[3] = .max; $0.inputs[5] = 1 },
            v("divide by zero", Int(HM_MODULE_EXECUTION_ERROR)) { $0.inputs[5] = 0 },
            v("invalid ABI", Int(HM_MODULE_INVALID_ABI), .badABI),
            v("unknown event id", Int(HM_MODULE_UNKNOWN_ID), .unknownEvent) { $0.inputs[1] = 1; $0.inputs[2] = 2 },
            v("stale source hash", Int(HM_MODULE_SOURCE_HASH_MISMATCH), .staleHash),
            v("output count over capacity", Int(HM_MODULE_CAPACITY_EXCEEDED), .malformedSpan),
            v("out-of-order deltas", Int(HM_MODULE_INVALID_ORDER), .outOfOrderDeltas) { $0.state = [9, 9, 9, 9, 9, 9, 9, 9] },
            v("partial output span", Int(HM_MODULE_PARTIAL_RESULT), .partial),
        ]
    }
}
