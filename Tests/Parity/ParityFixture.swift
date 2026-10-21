import Foundation

// Value types shared by every parity module. Nothing here knows a module name.

struct ParityTable: Equatable {
    var id: UInt32
    var cells: [Int32]
    var capacity: UInt32
}

struct ParityDelta: Equatable {
    var array: UInt32, element: UInt32, cell: UInt32
    var before: Int32, after: Int32
}

struct ParityEvent: Equatable {
    var phase: UInt32, eventID: UInt32, emitter: UInt32, sequence: UInt32
    var source: UInt32, target: UInt32, flags: UInt32
    var payload: [Int32]   // 0...4 live words; inactive slots are never compared
}

struct ParityCase {
    var ticID: UInt64
    var seed: UInt64
    var mapFingerprint: UInt64 = 0
    var inputs: [Int32]
    var state: [Int32]
    var tables: [ParityTable]
    var outputCapacity: UInt32
    var deltaCapacity: UInt32
    var eventCapacity: UInt32
}

/// What one evaluator produced before the shared envelope validator ran.
struct RawResult {
    var status: UInt32
    var outputs: [UInt32] = []
    var deltas: [ParityDelta] = []
    var events: [ParityEvent] = []
    var registers: [UInt32] = []   // operation values; only recorded when visualization samples
}

/// A validated, committed result. `bytes` is the canonical HMR1 serialization
/// (empty for any non-exact status, which has no committed data).
struct ParityResult: Equatable {
    var status: UInt32
    var outputs: [UInt32] = []
    var deltas: [ParityDelta] = []
    var events: [ParityEvent] = []
    var bytes: [UInt8] = []
}

// MARK: - Canonical little-endian fixture (HMF1)

let parityFixtureMagic: UInt32 = 0x3146_4d48          // "HMF1"
let parityFixtureVersion: UInt32 = 1

struct WordWriter {
    var bytes: [UInt8] = []
    mutating func u32(_ v: UInt32) { for s in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8((v >> UInt32(s)) & 255)) } }
    mutating func u64(_ v: UInt64) { u32(UInt32(truncatingIfNeeded: v)); u32(UInt32(truncatingIfNeeded: v >> 32)) }
    mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
}

struct WordReader {
    let bytes: [UInt8]
    var at = 0
    var remainingWords: Int { (bytes.count - at) / 4 }
    mutating func u32() -> UInt32? {
        guard at + 4 <= bytes.count else { return nil }
        defer { at += 4 }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[at + $1]) << UInt32(8 * $1) }
    }
    mutating func u64() -> UInt64? {
        guard let lo = u32(), let hi = u32() else { return nil }
        return UInt64(hi) << 32 | UInt64(lo)
    }
    mutating func i32() -> Int32? { u32().map { Int32(bitPattern: $0) } }
    /// A count is only believable if that many words can still follow.
    mutating func count(wordsEach: Int = 1) -> Int? {
        guard let n = u32(), Int(n) <= remainingWords / max(1, wordsEach) else { return nil }
        return Int(n)
    }
}

func fnv1a64(_ bytes: [UInt8]) -> UInt64 { HM_HashBytesV1(bytes, bytes.count) }

struct ParityFixture: Equatable {
    var moduleID: UInt32
    var programVersion: UInt32
    var sourceHash: UInt64
    var testCase: ParityCase
    var expected: ParityResult

    // Equatable on ParityCase is by serialization, so derive it.
    static func == (a: ParityFixture, b: ParityFixture) -> Bool { a.serialized() == b.serialized() }

    /// Trailing FNV-1a-64 of every preceding byte is the content address.
    func serialized() -> [UInt8] {
        var w = WordWriter()
        let c = testCase
        w.u32(parityFixtureMagic); w.u32(parityFixtureVersion)
        w.u32(UInt32(HM_CIRCUIT_MODULE_ABI_VERSION)); w.u32(programVersion); w.u32(moduleID)
        w.u64(c.ticID); w.u64(c.seed); w.u64(sourceHash); w.u64(c.mapFingerprint)
        w.u32(expected.status)
        w.u32(c.outputCapacity); w.u32(c.deltaCapacity); w.u32(c.eventCapacity)
        w.u32(UInt32(c.inputs.count)); c.inputs.forEach { w.i32($0) }
        w.u32(UInt32(c.state.count)); c.state.forEach { w.i32($0) }
        w.u32(UInt32(c.tables.count))
        for t in c.tables {
            w.u32(t.id); w.u32(t.capacity); w.u32(UInt32(t.cells.count)); t.cells.forEach { w.i32($0) }
        }
        w.u32(UInt32(expected.outputs.count)); expected.outputs.forEach { w.u32($0) }
        w.u32(UInt32(expected.deltas.count))
        for d in expected.deltas { w.u32(d.array); w.u32(d.element); w.u32(d.cell); w.i32(d.before); w.i32(d.after) }
        w.u32(UInt32(expected.events.count))
        for e in expected.events {
            [e.phase, e.eventID, e.emitter, e.sequence, e.source, e.target, UInt32(e.payload.count), e.flags].forEach { w.u32($0) }
            for i in 0..<4 { w.i32(i < e.payload.count ? e.payload[i] : 0) }
        }
        w.u64(fnv1a64(w.bytes))
        return w.bytes
    }

    var contentHash: UInt64 { fnv1a64(Array(serialized().dropLast(8))) }

    /// Fails closed: wrong magic/version/length/hash or any overlong count is nil.
    static func parse(_ bytes: [UInt8]) -> ParityFixture? {
        guard bytes.count >= 8 + 8, bytes.count % 4 == 0 else { return nil }
        var r = WordReader(bytes: bytes)
        guard r.u32() == parityFixtureMagic, r.u32() == parityFixtureVersion,
              r.u32() == UInt32(HM_CIRCUIT_MODULE_ABI_VERSION),
              let program = r.u32(), let module = r.u32(),
              let tic = r.u64(), let seed = r.u64(), let hash = r.u64(), let map = r.u64(),
              let status = r.u32(), let oc = r.u32(), let dc = r.u32(), let ec = r.u32(),
              let nIn = r.count() else { return nil }
        var inputs: [Int32] = []
        for _ in 0..<nIn { guard let v = r.i32() else { return nil }; inputs.append(v) }
        guard let nState = r.count() else { return nil }
        var state: [Int32] = []
        for _ in 0..<nState { guard let v = r.i32() else { return nil }; state.append(v) }
        guard let nTables = r.count(wordsEach: 3) else { return nil }
        var tables: [ParityTable] = []
        for _ in 0..<nTables {
            guard let id = r.u32(), let cap = r.u32(), let n = r.count() else { return nil }
            var cells: [Int32] = []
            for _ in 0..<n { guard let v = r.i32() else { return nil }; cells.append(v) }
            tables.append(ParityTable(id: id, cells: cells, capacity: cap))
        }
        guard let nOut = r.count() else { return nil }
        var outputs: [UInt32] = []
        for _ in 0..<nOut { guard let v = r.u32() else { return nil }; outputs.append(v) }
        guard let nDelta = r.count(wordsEach: 5) else { return nil }
        var deltas: [ParityDelta] = []
        for _ in 0..<nDelta {
            guard let a = r.u32(), let e = r.u32(), let c = r.u32(), let b = r.i32(), let f = r.i32() else { return nil }
            deltas.append(ParityDelta(array: a, element: e, cell: c, before: b, after: f))
        }
        guard let nEvents = r.count(wordsEach: 12) else { return nil }
        var events: [ParityEvent] = []
        for _ in 0..<nEvents {
            var f: [UInt32] = []
            for _ in 0..<8 { guard let v = r.u32() else { return nil }; f.append(v) }
            var p: [Int32] = []
            for _ in 0..<4 { guard let v = r.i32() else { return nil }; p.append(v) }
            guard f[6] <= 4 else { return nil }
            events.append(ParityEvent(phase: f[0], eventID: f[1], emitter: f[2], sequence: f[3],
                                      source: f[4], target: f[5], flags: f[7],
                                      payload: Array(p.prefix(Int(f[6])))))
        }
        let end = r.at
        guard let stored = r.u64(), r.at == bytes.count,
              stored == fnv1a64(Array(bytes[0..<end])) else { return nil }
        var c = ParityCase(ticID: tic, seed: seed, mapFingerprint: map, inputs: inputs, state: state,
                           tables: tables, outputCapacity: oc, deltaCapacity: dc, eventCapacity: ec)
        c.mapFingerprint = map
        return ParityFixture(moduleID: module, programVersion: program, sourceHash: hash,
                             testCase: c, expected: ParityResult(status: status, outputs: outputs,
                                                                  deltas: deltas, events: events))
    }
}
