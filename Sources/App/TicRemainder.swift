import Foundation
import Metal

// A second frozen module keeps the v1 locomotion IDs intact. Its inputs are
// normalized C-ABI cells, never DoomGeneric globals. All decisions below are
// expressed through affine, ReGLU/boolean, and bounded index reads.
struct RemainderGraph {
    static let inputCount = 55
    static let outputCount = 21
    let ops: [CircuitOp]
    let infos: [OpInfo]
    let roots: [Int]
    let tables: [Float]
    let tableDescriptions: [[String: Any]]
    let layerIndices: [[Int]]
    var layerCount: Int { infos.map(\.layer).max() ?? 0 }
    var operationCount: Int { ops.count }
    var liveOperationIDs: Set<Int> {
        var seen = Set<Int>(), pending = roots
        while let id = pending.popLast() {
            guard id >= Self.inputCount, seen.insert(id).inserted else { continue }
            pending.append(contentsOf: infos[id - Self.inputCount].parents)
        }
        return seen
    }
    var liveOperationCount: Int { liveOperationIDs.count }
    var graphHash: String {
        var h: UInt64 = 14695981039346656037
        for op in ops { for byte in withUnsafeBytes(of: op, Array.init) { h = (h ^ UInt64(byte)) &* 1099511628211 } }
        for value in tables { for byte in withUnsafeBytes(of: value, Array.init) { h = (h ^ UInt64(byte)) &* 1099511628211 } }
        for root in roots { for byte in withUnsafeBytes(of: UInt32(root).littleEndian, Array.init) { h = (h ^ UInt64(byte)) &* 1099511628211 } }
        return String(format: "%016llx", h)
    }
    init() {
        let b = RBuilder()
        let zero = b.constant(0, "constant.zero")
        let one = b.constant(1, "constant.one")
        let attack = b.any([4, 5, 6], "buttons.attack")
        let directUse = b.any([7, 8, 9], "buttons.directUse")

        // First pressed weapon key wins. Cycling has priority while in level.
        var manualFound = zero, manualWeapon = zero
        for i in 0..<8 {
            let first = b.and(10 + i, b.not(manualFound, "weapon.key\(i).notFound"), "weapon.key\(i).first")
            manualWeapon = b.add(manualWeapon, b.scale(first, Float(i), "weapon.key\(i).number"), "weapon.manualNumber")
            manualFound = b.any([manualFound, first], "weapon.manualFound")
        }
        let cyclePositive = b.positive(19, "weapon.nextPositive")
        let cycleNegative = b.positive(b.neg(19, "weapon.nextNegativeSign"), "weapon.nextNegative")
        let cycleActive = b.and(18, b.any([cyclePositive, cycleNegative], "weapon.nextAny"), "weapon.cycleActive")
        let pendingNoChange = b.eq(21, b.constant(10, "weapon.noChange"), "weapon.pendingNoChange")
        let current = b.selectPositive(pendingNoChange, 20, 21, "weapon.current")
        let startMap = b.table([0, 2, 3, 5, 6, 7, 8, 1, 4], "weapon.startMap")
        let orderWeapons = b.table([0, 7, 1, 2, 8, 3, 4, 5, 6], "weapon.orderWeapons")
        let orderNumbers = b.table([0, 0, 1, 2, 2, 3, 4, 5, 6], "weapon.orderNumbers")
        let start = b.index(current, table: startMap, "weapon.start")
        let fistBlocked = b.and(29, b.not(31, "weapon.noStrength"), "weapon.fistBlocked")
        let fistAvailable = b.and(22, b.not(fistBlocked, "weapon.fistAllowed"), "weapon.fistSelectable")
        let sharewareBlocked = b.and(33, 34, "weapon.sharewareBlocked")
        let superAvailable = b.and(30, b.not(32, "weapon.superAllowed"), "weapon.superSelectable")
        var selectables = [Int]()
        for weapon in 0..<9 {
            let value: Int
            switch weapon {
            case 0: value = fistAvailable
            case 5, 6: value = b.and(22 + weapon, b.not(sharewareBlocked, "weapon.ammoAllowed\(weapon)"), "weapon.selectable\(weapon)")
            case 8: value = superAvailable
            default: value = 22 + weapon
            }
            selectables.append(value)
        }
        let selectableCells = b.table(selectables.map(Float.init), "weapon.selectableCellIds")
        let forwardCandidates = b.table((0..<9).flatMap { start in (1...9).map { Float((start + $0) % 9) } }, "weapon.forwardCandidates")
        let reverseCandidates = b.table((0..<9).flatMap { start in (1...9).map { Float((start - $0 + 9) % 9) } }, "weapon.reverseCandidates")
        var found = zero, chosenOrder = zero
        for step in 0..<9 {
            let address = b.offset(b.scale(start, 9, "weapon.candidateAddressScale"), Float(step), "weapon.candidateAddress\(step)")
            let fwd = b.index(address, table: forwardCandidates, "weapon.forward\(step)")
            let rev = b.index(address, table: reverseCandidates, "weapon.reverse\(step)")
            let candidate = b.selectPositive(cyclePositive, fwd, rev, "weapon.candidate\(step)")
            let valid: Int
            if step == 8 { valid = one } // original search always accepts the start slot
            else {
                let weaponEnum = b.index(candidate, table: orderWeapons, "weapon.enum\(step)")
                valid = b.indexCell(weaponEnum, table: selectableCells, targets: selectables, "weapon.eligible\(step)")
            }
            let take = b.and(valid, b.not(found, "weapon.notFound\(step)"), "weapon.take\(step)")
            chosenOrder = b.add(chosenOrder, b.and(candidate, take, "weapon.chosen\(step)"), "weapon.selectedOrder")
            if step < 8 { found = b.any([found, take], "weapon.found") }
        }
        let cycleWeapon = b.index(chosenOrder, table: orderNumbers, "weapon.cycleNumber")
        let weapon = b.selectPositive(cycleActive, cycleWeapon, manualWeapon, "weapon.number")
        let change = b.any([cycleActive, manualFound], "buttons.change")

        let clearedClicks = b.selectPositive(directUse, zero, 38, "dclick.directUseReset")
        let first = b.doubleClick(enabled: 35, button: 51, time: 36, state: 37,
                                  clicks: clearedClicks, ticdup: 54, prefix: "dclick.forward")
        let strafeButton = b.any([52, 53], "dclick.strafeButton")
        let second = b.doubleClick(enabled: 35, button: strafeButton, time: 39, state: 40,
                                   clicks: 41, ticdup: 54, prefix: "dclick.strafe")
        let use = b.any([directUse, first.use, second.use], "buttons.use")
        let normal = b.sum([attack, b.scale(use, 2, "buttons.useBit"),
                            b.scale(change, 4, "buttons.changeBit"),
                            b.scale(weapon, 8, "buttons.weaponBits")], "buttons.normal")
        let pause = b.selectPositive(42, b.constant(129, "buttons.pauseCode"), normal, "buttons.pause")
        let save = b.add(b.constant(130, "buttons.saveCode"), b.scale(44, 4, "buttons.saveSlot"), "buttons.saveValue")
        let buttons = b.selectPositive(43, save, pause, "buttons.final")

        let desired = b.add(2, 46, "lowres.desired")
        let roundTable = b.table((-8320...8320).map { Float(($0 + 128) & ~255) }, "lowres.round256[-8320,8320]")
        let rounded = b.index(b.offset(desired, 8320, "lowres.tableAddress"), table: roundTable, "lowres.rounded")
        let finalAngle = b.select(45, rounded, 2, "angleturn.final")
        let lowresCarry = b.select(45, b.add(desired, b.neg(rounded, "lowres.negativeRounded"), "lowres.error"), 46, "lowres.carry")
        let testMouseSpeed = b.and(49, b.not(b.eq(50, zero, "mouse.xZero"), "mouse.xMoved"), "mouse.testSpeed")
        self.roots = [finalAngle, buttons, 47, 48, zero, zero, zero, zero,
                      first.time, first.state, first.clicks, second.time, second.state, second.clicks,
                      lowresCarry, testMouseSpeed, zero, zero, zero, zero, zero]
        self.ops = b.ops
        self.infos = b.infos
        self.tables = b.tables
        self.tableDescriptions = b.tableDescriptions
        var grouped = Array(repeating: [Int](), count: b.infos.map(\.layer).max() ?? 0)
        for (index, info) in b.infos.enumerated() { grouped[info.layer - 1].append(index) }
        self.layerIndices = grouped
        precondition(roots.count == Self.outputCount)
        precondition(Self.inputCount + ops.count <= 1024, "remainder graph exceeds bounded scratch")
        precondition(liveOperationCount == operationCount,
                     "remainder graph contains unused operations: \(infos.filter { !liveOperationIDs.contains($0.id) }.map(\.label))")
    }
    func manifestJSON() -> Data {
        let body: [String: Any] = [
            "abi": 1, "module": "tic.remainder", "inputABI": "Sources/Bridge/TicRemainderABI.h",
            "inputCount": Self.inputCount,
            "outputCount": Self.outputCount, "roots": roots, "operationCount": operationCount,
            "compiledLiveOperations": liveOperationCount, "layerCount": layerCount,
            "graphHash": graphHash, "tables": tableDescriptions,
            "outputNames": ["angleturn", "buttons", "chatchar", "consistancy", "buttons2", "inventory",
                            "lookfly", "arti", "dclicktime", "dclickstate", "dclicks", "dclicktime2",
                            "dclickstate2", "dclicks2", "lowres_carry", "testcontrols_mousespeed",
                            "next_weapon", "sendpause", "sendsave", "mousex", "mousey"],
            "operations": infos.map { ["id": $0.id, "label": $0.label, "kind": $0.kind,
                                        "layer": $0.layer, "parents": $0.parents,
                                        "boolean": $0.boolean] as [String: Any] }
        ]
        return try! JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
    }
}

private final class RBuilder {
    var ops: [CircuitOp] = []
    var infos: [OpInfo] = []
    var tables: [Float] = []
    var tableDescriptions: [[String: Any]] = []
    private var depths = Array(repeating: 0, count: RemainderGraph.inputCount)
    func table(_ values: [Float], _ label: String) -> Int {
        let base = tables.count
        tables.append(contentsOf: values)
        tableDescriptions.append(["id": tableDescriptions.count, "label": label, "base": base, "length": values.count])
        return base
    }
    func emit(_ kind: UInt32, _ a: Int, _ b: Int = 0, _ table: Int = 0,
              _ wa: Float = 0, _ wb: Float = 0, _ bias: Float = 0,
              _ label: String, boolean: Bool = false, targets: [Int] = []) -> Int {
        let id = RemainderGraph.inputCount + ops.count
        let parents: [Int]
        if kind == 4 { parents = [a] + targets }
        else if kind == 3 { parents = [a] }
        else if kind == 2 { parents = [a, b] }
        else if wa == 0 && wb == 0 { parents = [] }
        else if wa == 0 { parents = [b] }
        else if wb == 0 { parents = [a] }
        else { parents = [a, b] }
        let layer = 1 + (parents.map { depths[$0] }.max() ?? 0)
        ops.append(CircuitOp(kind: kind, a: UInt32(a), b: UInt32(b), table: UInt32(table), wa: wa, wb: wb, bias: bias))
        infos.append(OpInfo(id: id, label: label, kind: kind == 1 ? "affine" : kind == 2 ? "reglu" : "index-read",
                            layer: layer, parents: parents, boolean: boolean))
        depths.append(layer)
        return id
    }
    func constant(_ n: Float, _ label: String) -> Int { emit(1, 0, 0, 0, 0, 0, n, label) }
    func add(_ a: Int, _ b: Int, _ label: String) -> Int { emit(1, a, b, 0, 1, 1, 0, label) }
    func neg(_ a: Int, _ label: String) -> Int { emit(1, a, 0, 0, -1, 0, 0, label) }
    func scale(_ a: Int, _ n: Float, _ label: String) -> Int { emit(1, a, 0, 0, n, 0, 0, label) }
    func offset(_ a: Int, _ n: Float, _ label: String) -> Int { emit(1, a, 0, 0, 1, 0, n, label) }
    func relu(_ a: Int, _ label: String) -> Int { emit(2, a, constant(1, label + ".one"), 0, 0, 0, 0, label) }
    func positive(_ a: Int, _ label: String) -> Int {
        let hi = relu(a, label + ".hi")
        let lo = relu(offset(a, -1, label + ".minusOne"), label + ".lo")
        return emit(1, hi, lo, 0, 1, -1, 0, label, boolean: true)
    }
    func not(_ a: Int, _ label: String) -> Int { emit(1, a, 0, 0, -1, 0, 1, label, boolean: true) }
    func and(_ a: Int, _ b: Int, _ label: String) -> Int { emit(2, a, b, 0, 0, 0, 0, label, boolean: true) }
    func sum(_ xs: [Int], _ label: String) -> Int { xs.dropFirst().reduce(xs[0]) { add($0, $1, label + ".sum") } }
    func any(_ xs: [Int], _ label: String) -> Int { positive(sum(xs, label), label) }
    func gate(_ value: Int, _ bit: Int, _ label: String) -> Int {
        let pos = emit(2, value, bit, 0, 0, 0, 0, label + ".positive")
        let negative = emit(2, neg(value, label + ".negativeInput"), bit, 0, 0, 0, 0, label + ".negative")
        return emit(1, pos, negative, 0, 1, -1, 0, label)
    }
    func select(_ condition: Int, _ yes: Int, _ no: Int, _ label: String) -> Int {
        add(gate(yes, condition, label + ".yes"), gate(no, not(condition, label + ".not"), label + ".no"), label)
    }
    func selectPositive(_ condition: Int, _ yes: Int, _ no: Int, _ label: String) -> Int {
        add(and(yes, condition, label + ".yes"), and(no, not(condition, label + ".not"), label + ".no"), label)
    }
    func eq(_ a: Int, _ b: Int, _ label: String) -> Int {
        let diff = add(a, neg(b, label + ".negativeB"), label + ".difference")
        return not(any([positive(diff, label + ".greater"), positive(neg(diff, label + ".reverse"), label + ".less")], label + ".different"), label)
    }
    func index(_ at: Int, table: Int, _ label: String) -> Int { emit(3, at, 0, table, 0, 0, 0, label) }
    func indexCell(_ at: Int, table: Int, targets: [Int], _ label: String) -> Int {
        emit(4, at, 0, table, 0, 0, 0, label, targets: targets)
    }
    func doubleClick(enabled: Int, button: Int, time: Int, state: Int, clicks: Int,
                     ticdup: Int, prefix: String) -> (time: Int, state: Int, clicks: Int, use: Int) {
        let edge = and(not(eq(button, state, prefix + ".same"), prefix + ".changed"),
                       positive(add(time, constant(-1, prefix + ".oneNegative"), prefix + ".afterOne"), prefix + ".timeReady"), prefix + ".edge")
        let edgeState = button
        let edgeClicks = add(clicks, and(edge, button, prefix + ".press"), prefix + ".edgeClicks")
        let double = and(edge, eq(edgeClicks, constant(2, prefix + ".two"), prefix + ".twoClicks"), prefix + ".double")
        let edgeClicksFinal = selectPositive(double, constant(0, prefix + ".zero"), edgeClicks, prefix + ".edgeClicksFinal")
        let edgeTime = selectPositive(double, time, constant(0, prefix + ".resetTime"), prefix + ".edgeTime")
        let elapsed = add(time, ticdup, prefix + ".elapsed")
        let expired = positive(add(elapsed, constant(-20, prefix + ".negativeTwenty"), prefix + ".afterTwenty"), prefix + ".expired")
        let idleState = selectPositive(expired, constant(0, prefix + ".clearState"), state, prefix + ".idleState")
        let idleClicks = selectPositive(expired, constant(0, prefix + ".clearClicks"), clicks, prefix + ".idleClicks")
        return (selectPositive(enabled, selectPositive(edge, edgeTime, elapsed, prefix + ".timeActive"), time, prefix + ".time"),
                selectPositive(enabled, selectPositive(edge, edgeState, idleState, prefix + ".stateActive"), state, prefix + ".state"),
                selectPositive(enabled, selectPositive(edge, edgeClicksFinal, idleClicks, prefix + ".clicksActive"), clicks, prefix + ".clicks"),
                and(enabled, double, prefix + ".use"))
    }
}

struct RemainderLayer {
    let id: Int
    let affine: Int
    let reglu: Int
    let index: Int
    let nonzero: Int
    let gateOpen: Int
    let booleanActive: Int
    let heat: [Int]
    let cpuReplayNs: UInt64
}
struct RemainderTrace {
    let tick: Int
    let circuit: HMTicRemainderOutput
    let reference: HMTicRemainderOutput
    let latencyNs: UInt64
    let layers: [RemainderLayer]
    let values: [Float]
    let changedStateCells: [String]
}
final class RemainderRing {
    private(set) var items: [RemainderTrace] = []
    private(set) var dropped = 0
    let capacity: Int
    init(capacity: Int = 128) { self.capacity = capacity }
    func append(_ trace: RemainderTrace) {
        guard capacity > 0 else { dropped += 1; return }
        if items.count == capacity { items.removeFirst(); dropped += 1 }
        items.append(trace)
    }
}
private final class RSlot {
    let input: MTLBuffer
    let output: MTLBuffer
    var busy = false
    init?(device: MTLDevice) {
        guard let input = device.makeBuffer(length: RemainderGraph.inputCount * 4, options: .storageModeShared),
              let output = device.makeBuffer(length: RemainderGraph.outputCount * 4, options: .storageModeShared) else { return nil }
        self.input = input; self.output = output
    }
}
private final class RWork {
    let done = DispatchSemaphore(value: 0)
    var result: HMTicRemainderOutput?
    var timedOut = false
}

final class RemainderRuntime {
    let graph = RemainderGraph()
    private let queue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?
    private let opBuffer: MTLBuffer?
    private let tableBuffer: MTLBuffer?
    private var slots: [RSlot] = []
    private let slotLock = NSLock()
    private let workerLock = NSLock()
    private let worker = DispatchQueue(label: "handwired.doom.tic-remainder", qos: .userInteractive)
    private var workerBusy = false
    private let deadlineNs: UInt64
    private var metalTimedOut = false
    private(set) var circuitTics = 0
    private(set) var domainFallbacks = 0
    private(set) var metalFallbacks = 0
    private(set) var mismatches = 0
    private(set) var lastResult: HMTicRemainderOutput?
    private(set) var lastReference: HMTicRemainderOutput?
    private(set) var lastLatencyNs: UInt64 = 0
    private(set) var lastFallback = "none"
    let traces = RemainderRing()
    var visualizationEnabled = false
    var traceHandler: ((RemainderTrace, Int) -> Void)?
    var countersHandler: (() -> Void)?
    private var tick = 0

    init(device: MTLDevice? = MTLCreateSystemDefaultDevice(), deadlineNs: UInt64 = 2_000_000) {
        self.deadlineNs = deadlineNs
        self.queue = device?.makeCommandQueue()
        let sourceURL = Bundle.main.url(forResource: "TicRemainder", withExtension: "msl")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("TicRemainder.msl")
        if let device, let source = try? String(contentsOf: sourceURL, encoding: .utf8) {
            let options = MTLCompileOptions()
            if #available(macOS 15.0, *) { options.mathMode = .safe }
            else { options.fastMathEnabled = false }
            if let library = try? device.makeLibrary(source: source, options: options),
               let function = library.makeFunction(name: "evaluateTicRemainder") {
                self.pipeline = try? device.makeComputePipelineState(function: function)
            } else { self.pipeline = nil }
        } else { self.pipeline = nil }
        self.opBuffer = device?.makeBuffer(bytes: graph.ops, length: graph.ops.count * MemoryLayout<CircuitOp>.stride, options: .storageModeShared)
        self.tableBuffer = device?.makeBuffer(bytes: graph.tables, length: graph.tables.count * 4, options: .storageModeShared)
        if let device { slots = (0..<8).compactMap { _ in RSlot(device: device) } }
    }
    static func cells(_ input: HMTicRemainderInput) -> [Int32] {
        withUnsafeBytes(of: input.cell) { Array($0.bindMemory(to: Int32.self)) }
    }
    static func cells(_ output: HMTicRemainderOutput) -> [Int32] {
        withUnsafeBytes(of: output) { Array($0.bindMemory(to: Int32.self)) }
    }
    static func input(_ cells: [Int32]) -> HMTicRemainderInput {
        precondition(cells.count == RemainderGraph.inputCount)
        var result = HMTicRemainderInput()
        withUnsafeMutableBytes(of: &result.cell) { dest in cells.withUnsafeBytes { dest.copyMemory(from: $0) } }
        return result
    }
    private static func output(_ cells: [Int32]) -> HMTicRemainderOutput {
        precondition(cells.count == RemainderGraph.outputCount)
        var result = HMTicRemainderOutput()
        withUnsafeMutableBytes(of: &result) { dest in cells.withUnsafeBytes { dest.copyMemory(from: $0) } }
        return result
    }
    func cpu(_ input: HMTicRemainderInput, trace: Bool = false) -> (HMTicRemainderOutput, [Float], [UInt64]) {
        let ints = Self.cells(input)
        var values = Array(repeating: Float(0), count: RemainderGraph.inputCount + graph.ops.count)
        var layerTimes = Array(repeating: UInt64(0), count: graph.layerCount)
        for i in 0..<ints.count { values[i] = Float(ints[i]) }
        for (i, op) in graph.ops.enumerated() {
            let begin = trace ? DispatchTime.now().uptimeNanoseconds : 0
            let a = values[Int(op.a)], b = values[Int(op.b)]
            switch op.kind {
            case 1: values[RemainderGraph.inputCount+i] = (op.wa * a + op.wb * b) + op.bias
            case 2: values[RemainderGraph.inputCount+i] = max(0, a) * max(0, b)
            case 3: values[RemainderGraph.inputCount+i] = graph.tables[Int(op.table) + Int(a)]
            default: values[RemainderGraph.inputCount+i] = values[Int(graph.tables[Int(op.table) + Int(a)])]
            }
            if trace { layerTimes[graph.infos[i].layer - 1] += DispatchTime.now().uptimeNanoseconds - begin }
        }
        let result = Self.output(graph.roots.map { Int32(values[$0]) })
        return (result, trace ? values : [], layerTimes)
    }
    func metal(_ input: HMTicRemainderInput) -> (HMTicRemainderOutput, UInt64)? {
        metalTimedOut = false
        guard deadlineNs > 0, let queue, let pipeline, let opBuffer, let tableBuffer else {
            metalTimedOut = deadlineNs == 0; return nil
        }
        slotLock.lock()
        let slot = slots.first { !$0.busy }
        slot?.busy = true
        slotLock.unlock()
        guard let slot else { return nil }
        let floats = Self.cells(input).map(Float.init)
        floats.withUnsafeBytes { slot.input.contents().copyMemory(from: $0.baseAddress!, byteCount: RemainderGraph.inputCount * 4) }
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            slotLock.lock(); slot.busy = false; slotLock.unlock(); return nil
        }
        let start = DispatchTime.now().uptimeNanoseconds
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(slot.input, offset: 0, index: 0)
        encoder.setBuffer(opBuffer, offset: 0, index: 1)
        encoder.setBuffer(tableBuffer, offset: 0, index: 2)
        encoder.setBuffer(slot.output, offset: 0, index: 3)
        var count = UInt32(graph.ops.count)
        encoder.setBytes(&count, length: 4, index: 4)
        graph.roots.map(UInt32.init).withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: RemainderGraph.outputCount * 4, index: 5) }
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        if DispatchTime.now().uptimeNanoseconds - start >= deadlineNs {
            metalTimedOut = true; slotLock.lock(); slot.busy = false; slotLock.unlock(); return nil
        }
        let completed = DispatchSemaphore(value: 0)
        command.addCompletedHandler { [self] _ in
            slotLock.lock(); slot.busy = false; slotLock.unlock(); completed.signal()
        }
        command.commit()
        if completed.wait(timeout: DispatchTime(uptimeNanoseconds: start + deadlineNs)) == .timedOut {
            metalTimedOut = true; return nil
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        guard command.status == .completed, elapsed < deadlineNs else { metalTimedOut = true; return nil }
        let ints = slot.output.contents().bindMemory(to: Int32.self, capacity: RemainderGraph.outputCount)
        return (Self.output((0..<RemainderGraph.outputCount).map { ints[$0] }), elapsed)
    }
    private func boundedMetal(_ input: HMTicRemainderInput) -> (HMTicRemainderOutput?, UInt64, String) {
        let start = DispatchTime.now().uptimeNanoseconds
        guard deadlineNs > 0 else { return (nil, 0, "metal-timeout") }
        workerLock.lock()
        guard !workerBusy else { workerLock.unlock(); return (nil, 0, "metal-busy") }
        workerBusy = true; workerLock.unlock()
        let work = RWork()
        worker.async { [self] in
            work.result = metal(input)?.0
            work.timedOut = metalTimedOut
            workerLock.lock(); workerBusy = false; workerLock.unlock()
            work.done.signal()
        }
        while work.done.wait(timeout: .now()) == .timedOut {
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            if elapsed >= deadlineNs { return (nil, elapsed, "metal-timeout") }
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        guard elapsed < deadlineNs else { return (nil, elapsed, "metal-timeout") }
        guard let result = work.result else { return (nil, elapsed, work.timedOut ? "metal-timeout" : "metal") }
        return (result, elapsed, "none")
    }
    func evaluate(_ input: HMTicRemainderInput, reference: HMTicRemainderOutput) -> HMTicRemainderOutput? {
        tick += 1; lastReference = reference
        var copy = input
        guard HM_RemainderInputInDomain(&copy) != 0 else {
            domainFallbacks += 1; lastResult = reference; lastFallback = "domain"; lastLatencyNs = 0
            if visualizationEnabled { countersHandler?() }; return nil
        }
        let (candidate, latency, reason) = boundedMetal(input)
        guard let result = candidate else {
            metalFallbacks += 1; lastResult = reference; lastFallback = reason; lastLatencyNs = latency
            if visualizationEnabled { countersHandler?() }; return nil
        }
        lastLatencyNs = latency; lastResult = result; lastFallback = "none"
        guard Self.cells(result) == Self.cells(reference) else {
            mismatches += 1; lastResult = reference; lastFallback = "mismatch"
            if visualizationEnabled { countersHandler?() }; return nil
        }
        circuitTics += 1
        if visualizationEnabled && tick % 8 == 0 {
            let (_, values, times) = cpu(input, trace: true)
            let trace = RemainderTrace(tick: tick, circuit: result, reference: reference,
                                       latencyNs: latency, layers: summarize(values, times), values: values,
                                       changedStateCells: changedStates(input, result))
            traces.append(trace); traceHandler?(trace, traces.dropped)
        }
        return result
    }
    private func changedStates(_ input: HMTicRemainderInput, _ result: HMTicRemainderOutput) -> [String] {
        let c = Self.cells(input)
        return [("dclicktime", 36, result.dclicktime), ("dclickstate", 37, result.dclickstate),
                ("dclicks", 38, result.dclicks), ("dclicktime2", 39, result.dclicktime2),
                ("dclickstate2", 40, result.dclickstate2), ("dclicks2", 41, result.dclicks2),
                ("lowres carry", 46, result.lowres_carry), ("next weapon", 19, result.next_weapon),
                ("pause", 42, result.sendpause), ("save", 43, result.sendsave),
                ("mouse X", 50, result.mousex)].compactMap { name, at, after in c[at] == after ? nil : name }
    }
    private func summarize(_ values: [Float], _ times: [UInt64]) -> [RemainderLayer] {
        (1...graph.layerCount).map { layer in
            var heat = Array(repeating: 0, count: 8)
            var affine = 0, reglu = 0, index = 0, nonzero = 0, gateOpen = 0, booleanActive = 0
            for i in graph.layerIndices[layer - 1] {
                let info = graph.infos[i], value = values[info.id]
                if info.kind == "affine" { affine += 1 }
                else if info.kind == "reglu" { reglu += 1; if value != 0 { gateOpen += 1 } }
                else { index += 1 }
                if value != 0 { nonzero += 1; if info.boolean { booleanActive += 1 } }
                heat[min(7, max(0, Int(log2(Double(abs(value)) + 1))))] += 1
            }
            return RemainderLayer(id: layer, affine: affine, reglu: reglu, index: index,
                                  nonzero: nonzero, gateOpen: gateOpen, booleanActive: booleanActive,
                                  heat: heat, cpuReplayNs: times[layer-1])
        }
    }
    func neighborhood(root: Int, trace: RemainderTrace, limit: Int = 64) -> [(OpInfo, Float)] {
        var seen = Set<Int>(), work = [graph.roots[root]], result: [(OpInfo, Float)] = []
        while let id = work.popLast(), result.count < min(limit, 64) {
            guard id >= RemainderGraph.inputCount, seen.insert(id).inserted else { continue }
            let info = graph.infos[id-RemainderGraph.inputCount]
            result.append((info, trace.values[id]))
            work.append(contentsOf: info.parents.reversed())
        }
        return result
    }
}
