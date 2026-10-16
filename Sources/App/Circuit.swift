import Foundation
import Metal

// Mirrors the 32-byte instruction consumed by Locomotion.metal. IDs are array
// positions after the 24 source cells; the builder's fixed traversal freezes them.
struct CircuitOp {
    var kind: UInt32            // 1 affine, 2 ReGLU, 3 index read
    var a: UInt32
    var b: UInt32
    var table: UInt32
    var wa: Float
    var wb: Float
    var bias: Float
    var reserved: Float = 0
}

struct OpInfo {
    let id: Int
    let label: String
    let kind: String
    let layer: Int
    let parents: [Int]
    let boolean: Bool
}

struct CircuitGraph {
    let ops: [CircuitOp]
    let infos: [OpInfo]
    let roots: [Int]
    let tables: [Float] = [25, 50, 24, 40, 640, 1280, 320]
    let inputNames = ["key.strafe", "speed", "key.right", "key.left", "key.up", "key.down",
                      "key.strafeLeft", "key.strafeRight", "mouse.strafe", "mouse.forward",
                      "mouse.backward", "mouse.strafeLeft", "mouse.strafeRight", "mouse.x",
                      "mouse.y", "joy.strafe", "joy.strafeLeft", "joy.strafeRight", "joy.x",
                      "joy.y", "joy.side", "state.turnheld", "ticdup", "reserved"]
    var operationCount: Int { ops.count }
    var layerCount: Int { infos.map(\.layer).max() ?? 0 }
    var liveOperationCount: Int {
        var seen = Set<Int>(), pending = roots
        while let id = pending.popLast() {
            guard id >= 24, seen.insert(id).inserted else { continue }
            pending.append(contentsOf: infos[id - 24].parents)
        }
        return seen.count
    }
    var graphHash: String {
        var h: UInt64 = 14695981039346656037
        for op in ops { for byte in withUnsafeBytes(of: op, Array.init) { h = (h ^ UInt64(byte)) &* 1099511628211 } }
        for root in roots { for byte in withUnsafeBytes(of: UInt32(root).littleEndian, Array.init) { h = (h ^ UInt64(byte)) &* 1099511628211 } }
        return String(format: "%016llx", h)
    }

    init() {
        let b = GraphBuilder()
        let speed = 1, right = 2, left = 3, up = 4, down = 5
        let mx = 13, my = 14, jx = 18, jy = 19, js = 20, held = 21, ticdup = 22
        let strafe = b.any([0, 8, 15], "strafe.active")
        let jxPos = b.positive(jx, "joy.x.positive")
        let jxNeg = b.positive(b.neg(jx, "joy.x.negated"), "joy.x.negative")
        let jyPos = b.positive(jy, "joy.y.positive")
        let jyNeg = b.positive(b.neg(jy, "joy.y.negated"), "joy.y.negative")
        let jsPos = b.positive(js, "joy.side.positive")
        let jsNeg = b.positive(b.neg(js, "joy.side.negated"), "joy.side.negative")
        let turnActive = b.any([right, left, jxPos, jxNeg], "turn.active")
        let heldNext = b.gate(b.add(held, ticdup, "turnheld.increment"), turnActive, "turnheld.next")
        let slow = b.positive(b.add(b.constant(6, "constant.six"), b.neg(heldNext, "turnheld.negative"), "slow.threshold"), "slow.active")
        let turnSpeedIndex = b.add(b.gate(b.constant(2, "constant.two"), slow, "slow.index"),
                                   b.gate(speed, b.not(slow, "fast.active"), "fast.index"), "turn.speedIndex")
        let forwardSpeed = b.index(speed, table: 0, "forward.speed")
        let sideSpeed = b.index(speed, table: 2, "side.speed")
        let angleSpeed = b.index(turnSpeedIndex, table: 4, "angle.speed")

        let turnDirection = b.sum([left, jxNeg, b.neg(right, "right.turnSign"), b.neg(jxPos, "joyRight.turnSign")], "turn.direction")
        let angleKeyboard = b.gate(b.multiplyPositive(angleSpeed, turnDirection, "angle.keyboard"), b.not(strafe, "turn.mode"), "angle.nonStrafe")
        let sideTurn = b.gate(b.multiplyPositive(sideSpeed, b.neg(turnDirection, "strafe.turnDirection"), "side.turn"), strafe, "side.strafeTurn")
        let forwardDirection = b.sum([up, jyNeg, 9, b.neg(down, "down.sign"), b.neg(jyPos, "joyDown.sign"), b.neg(10, "mouseBack.sign")], "forward.direction")
        let forwardBase = b.multiplyPositive(forwardSpeed, forwardDirection, "forward.base")
        let strafeLeft = b.any([6, 11, 16, jsNeg], "strafe.left")
        let strafeRight = b.any([7, 12, 17, jsPos], "strafe.right")
        let sideDirection = b.add(strafeRight, b.neg(strafeLeft, "strafeLeft.sign"), "side.direction")
        let sideBase = b.multiplyPositive(sideSpeed, sideDirection, "side.base")
        let forwardRaw = b.add(forwardBase, my, "forward.mouse")
        let sideRaw = b.sum([sideTurn, sideBase, b.gate(b.scale(mx, 2, "mouse.sideScale"), strafe, "mouse.side")], "side.raw")
        let angleMouse = b.gate(b.scale(mx, -8, "mouse.angleScale"), b.not(strafe, "mouse.turnMode"), "mouse.angle")
        let angleRaw = b.add(angleKeyboard, angleMouse, "angle.raw")
        let forwardOut = b.clamp50(forwardRaw, "forward")
        let sideOut = b.clamp50(sideRaw, "side")
        self.ops = b.ops
        self.infos = b.infos
        self.roots = [forwardOut, sideOut, angleRaw, heldNext]
        precondition(liveOperationCount == operationCount, "Graph contains unused operations")
    }

    func manifestJSON() -> Data {
        let body: [String: Any] = [
            "abi": 1, "inputNames": inputNames, "tables": tables,
            "roots": roots, "operationCount": operationCount, "compiledLiveOperations": liveOperationCount,
            "layerCount": layerCount, "graphHash": graphHash,
            "operations": infos.map { ["id": $0.id, "label": $0.label, "kind": $0.kind,
                                        "layer": $0.layer, "parents": $0.parents, "boolean": $0.boolean] as [String: Any] }
        ]
        return try! JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
    }
}

private final class GraphBuilder {
    var ops: [CircuitOp] = []
    var infos: [OpInfo] = []
    private var depths = Array(repeating: 0, count: 24)
    func emit(_ kind: UInt32, _ a: Int, _ b: Int, _ table: Int, _ wa: Float, _ wb: Float, _ bias: Float,
              _ label: String, boolean: Bool = false) -> Int {
        let id = 24 + ops.count
        let parents: [Int]
        if kind == 3 { parents = [a] }
        else if kind == 2 { parents = [a, b] }
        else if wa == 0 && wb == 0 { parents = [] }
        else if wa == 0 { parents = [b] }
        else if wb == 0 { parents = [a] }
        else { parents = [a, b] }
        let layer = 1 + (parents.map { depths[$0] }.max() ?? 0)
        ops.append(CircuitOp(kind: kind, a: UInt32(a), b: UInt32(b), table: UInt32(table), wa: wa, wb: wb, bias: bias))
        infos.append(OpInfo(id: id, label: label, kind: kind == 1 ? "affine" : kind == 2 ? "reglu" : "index",
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
    func sum(_ xs: [Int], _ label: String) -> Int { xs.dropFirst().reduce(xs[0]) { add($0, $1, label + ".sum") } }
    func any(_ xs: [Int], _ label: String) -> Int { positive(sum(xs, label), label) }
    func gate(_ value: Int, _ bit: Int, _ label: String) -> Int {
        let positivePart = emit(2, value, bit, 0, 0, 0, 0, label + ".positive")
        let negativePart = emit(2, neg(value, label + ".negativeInput"), bit, 0, 0, 0, 0, label + ".negative")
        return emit(1, positivePart, negativePart, 0, 1, -1, 0, label)
    }
    func multiplyPositive(_ value: Int, _ count: Int, _ label: String) -> Int { gate(count, value, label) }
    func index(_ at: Int, table: Int, _ label: String) -> Int { emit(3, at, 0, table, 0, 0, 0, label) }
    func clamp50(_ x: Int, _ label: String) -> Int {
        let high = relu(offset(x, -50, label + ".above50"), label + ".high")
        let low = relu(neg(offset(x, 50, label + ".plus50"), label + ".belowMinus50"), label + ".low")
        return sum([x, neg(high, label + ".highSubtract"), low], label + ".clamped")
    }
}

struct LayerTelemetry {
    let id: Int
    let affine: Int
    let reglu: Int
    let index: Int
    let nonzero: Int
    let gateOpen: Int
    let gateClosed: Int
    let booleanCount: Int
    let booleanActive: Int
    let heat: [Int]
    let minValue: Float
    let maxValue: Float
    let cpuReplayNs: UInt64
}

struct CircuitTrace {
    let tick: Int
    let sourceHash: UInt64
    let capturedNs: UInt64
    let circuit: HMMovementOutput
    let reference: HMMovementOutput
    let latencyNs: UInt64
    let fallback: String?
    let layers: [LayerTelemetry]
    let values: [Float] // sampled only, bounded by frozen graph size
    let changedTurnheld: Bool
    var mismatch: Bool { circuit.forwardmove != reference.forwardmove || circuit.sidemove != reference.sidemove || circuit.angleturn != reference.angleturn || circuit.turnheld != reference.turnheld }
}

final class TraceRing {
    private(set) var items: [CircuitTrace] = []
    private(set) var dropped = 0
    let capacity: Int
    init(capacity: Int = 128) { self.capacity = capacity }
    func append(_ item: CircuitTrace) {
        guard capacity > 0 else { dropped += 1; return }
        if items.count == capacity { items.removeFirst(); dropped += 1 }
        items.append(item)
    }
}

// The engine queue owns this clock. One returned slot means one BuildNewTic /
// RunTic pair because the DoomGeneric adapter enables singletics.
struct TicScheduler {
    let periodNs: UInt64 = 1_000_000_000 / 35
    private(set) var paused = false
    private(set) var lateTics = 0
    private var lastNs: UInt64?
    private var accumulatedNs: UInt64 = 0
    mutating func due(now: UInt64) -> Int {
        guard let lastNs else { self.lastNs = now; return 0 }
        self.lastNs = now
        if paused { return 0 }
        accumulatedNs += now - lastNs
        let available = Int(accumulatedNs / periodNs)
        let count = min(available, 4)
        accumulatedNs -= UInt64(count) * periodNs
        if accumulatedNs >= 4 * periodNs {
            lateTics += Int(accumulatedNs / periodNs)
            accumulatedNs %= periodNs
        }
        return count
    }
    mutating func pause(now: UInt64) { paused = true; lastNs = now; accumulatedNs = 0 }
    mutating func resume(now: UInt64) { paused = false; lastNs = now; accumulatedNs = 0 }
    mutating func step() -> Int { paused ? 1 : 0 }
}

private final class MetalSlot {
    let input: MTLBuffer
    let output: MTLBuffer
    var busy = false
    init?(device: MTLDevice) {
        guard let input = device.makeBuffer(length: 24 * 4, options: .storageModeShared),
              let output = device.makeBuffer(length: 4 * 4, options: .storageModeShared) else { return nil }
        self.input = input
        self.output = output
    }
}

private final class BoundedMetalResult {
    let done = DispatchSemaphore(value: 0)
    var output: HMMovementOutput?
    var timedOut = false
}

final class CircuitRuntime {
    let graph = CircuitGraph()
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?
    private let opBuffer: MTLBuffer?
    private let tableBuffer: MTLBuffer?
    private var slots: [MetalSlot] = []
    private let slotLock = NSLock()
    private let workerLock = NSLock()
    private let metalWorker = DispatchQueue(label: "handwired.doom.metal-attempt", qos: .userInteractive)
    private var workerBusy = false
    private var metalTimedOut = false
    private var metalLastAttemptNs: UInt64 = 0
    private let deadlineNs: UInt64
    private let workerDelayNs: UInt64 // injected only by the bounded-wait regression test
    private(set) var circuitTics = 0
    private(set) var domainFallbacks = 0
    private(set) var metalFallbacks = 0
    private(set) var mismatches = 0
    private(set) var latencies: [UInt64] = []
    private(set) var lastResult: HMMovementOutput?
    private(set) var lastReference: HMMovementOutput?
    private(set) var lastLatencyNs: UInt64 = 0
    private(set) var lastFallback: String = "none"
    let traces = TraceRing()
    var visualizationEnabled = false
    var traceHandler: ((CircuitTrace, Int) -> Void)?
    var countersHandler: (() -> Void)?
    private var tick = 0

    init(device: MTLDevice? = MTLCreateSystemDefaultDevice(), deadlineNs: UInt64 = 2_000_000,
         workerDelayNs: UInt64 = 0) {
        self.deadlineNs = deadlineNs
        self.workerDelayNs = workerDelayNs
        self.device = device
        self.queue = device?.makeCommandQueue()
        let shaderURL = Bundle.main.url(forResource: "Locomotion", withExtension: "msl")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Locomotion.msl")
        if let device, let source = try? String(contentsOf: shaderURL, encoding: .utf8) {
            let options = MTLCompileOptions()
            if #available(macOS 15.0, *) { options.mathMode = .safe }
            else { options.fastMathEnabled = false }
            if let library = try? device.makeLibrary(source: source, options: options),
               let function = library.makeFunction(name: "evaluateLocomotion") {
                self.pipeline = try? device.makeComputePipelineState(function: function)
            } else { self.pipeline = nil }
        } else { self.pipeline = nil }
        self.opBuffer = device?.makeBuffer(bytes: graph.ops, length: graph.ops.count * MemoryLayout<CircuitOp>.stride, options: .storageModeShared)
        self.tableBuffer = device?.makeBuffer(bytes: graph.tables, length: graph.tables.count * 4, options: .storageModeShared)
        if let device { self.slots = (0..<8).compactMap { _ in MetalSlot(device: device) } }
    }

    static func cells(_ input: HMMovementInput) -> [Int32] {
        withUnsafeBytes(of: input.cell) { Array($0.bindMemory(to: Int32.self)) }
    }
    static func input(_ cells: [Int32]) -> HMMovementInput {
        precondition(cells.count == 24)
        var result = HMMovementInput()
        withUnsafeMutableBytes(of: &result.cell) { bytes in
            cells.withUnsafeBytes { source in bytes.copyMemory(from: source) }
        }
        return result
    }
    static func hash(_ cells: [Int32]) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for value in cells { for byte in withUnsafeBytes(of: value.littleEndian, Array.init) { hash = (hash ^ UInt64(byte)) &* 1099511628211 } }
        return hash
    }

    func cpu(_ input: HMMovementInput, trace: Bool = false) -> (HMMovementOutput, [Float]) {
        let (result, values, _) = cpuReplay(input, trace: trace, measure: false)
        return (result, values)
    }
    private func cpuReplay(_ input: HMMovementInput, trace: Bool, measure: Bool) -> (HMMovementOutput, [Float], [UInt64]) {
        let ints = Self.cells(input)
        var values = Array(repeating: Float(0), count: 24 + graph.ops.count)
        var layerTimes = Array(repeating: UInt64(0), count: graph.layerCount)
        for i in 0..<24 { values[i] = Float(ints[i]) }
        for (i, op) in graph.ops.enumerated() {
            let begin = measure ? DispatchTime.now().uptimeNanoseconds : 0
            let a = values[Int(op.a)], b = values[Int(op.b)]
            switch op.kind {
            case 1: values[24+i] = (op.wa * a + op.wb * b) + op.bias
            case 2: values[24+i] = max(0, a) * max(0, b)
            default: values[24+i] = graph.tables[Int(op.table) + Int(a)]
            }
            if measure { layerTimes[graph.infos[i].layer - 1] += DispatchTime.now().uptimeNanoseconds - begin }
        }
        let r = graph.roots.map { Int32(values[$0]) }
        return (HMMovementOutput(forwardmove: r[0], sidemove: r[1], angleturn: r[2], turnheld: r[3]), trace ? values : [], layerTimes)
    }

    func metal(_ input: HMMovementInput) -> (HMMovementOutput, UInt64)? {
        metalTimedOut = false
        metalLastAttemptNs = 0
        if deadlineNs == 0 { metalTimedOut = true; return nil }
        guard let queue, let pipeline, let opBuffer, let tableBuffer else { return nil }
        slotLock.lock()
        let slot = slots.first { !$0.busy }
        slot?.busy = true
        slotLock.unlock()
        guard let slot else { return nil }
        let cells = Self.cells(input)
        let floats = cells.map(Float.init)
        floats.withUnsafeBytes { slot.input.contents().copyMemory(from: $0.baseAddress!, byteCount: 24*4) }
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            slotLock.lock(); slot.busy = false; slotLock.unlock()
            return nil
        }
        let roots = graph.roots.map(UInt32.init)
        let start = DispatchTime.now().uptimeNanoseconds
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(slot.input, offset: 0, index: 0)
        encoder.setBuffer(opBuffer, offset: 0, index: 1)
        encoder.setBuffer(tableBuffer, offset: 0, index: 2)
        encoder.setBuffer(slot.output, offset: 0, index: 3)
        var count = UInt32(graph.ops.count)
        encoder.setBytes(&count, length: 4, index: 4)
        roots.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: 16, index: 5) }
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        let encodedNs = DispatchTime.now().uptimeNanoseconds - start
        if encodedNs >= deadlineNs {
            metalLastAttemptNs = encodedNs
            metalTimedOut = true
            slotLock.lock(); slot.busy = false; slotLock.unlock()
            return nil
        }
        let completed = DispatchSemaphore(value: 0)
        command.addCompletedHandler { [self] _ in
            slotLock.lock(); slot.busy = false; slotLock.unlock()
            completed.signal()
        }
        command.commit()
        // A delayed GPU command must not hold the 35 Hz simulation hostage.
        // Its slot stays busy until completion; C owns this tic on timeout.
        if completed.wait(timeout: DispatchTime(uptimeNanoseconds: start + deadlineNs)) == .timedOut {
            metalLastAttemptNs = DispatchTime.now().uptimeNanoseconds - start
            metalTimedOut = true
            return nil
        }
        guard command.status == .completed else { return nil }
        let ns = DispatchTime.now().uptimeNanoseconds - start
        metalLastAttemptNs = ns
        if ns >= deadlineNs { metalTimedOut = true; return nil }
        let output = slot.output.contents().bindMemory(to: Int32.self, capacity: 4)
        return (HMMovementOutput(forwardmove: output[0], sidemove: output[1], angleturn: output[2], turnheld: output[3]), ns)
    }

    // Keep command-buffer creation and encoding off the engine queue as well as
    // GPU completion. Metal APIs can stall before commit, so a deadline around
    // only command.waitUntilCompleted() does not protect a 35 Hz tic.
    private func boundedMetal(_ input: HMMovementInput) -> (HMMovementOutput?, UInt64, String) {
        let start = DispatchTime.now().uptimeNanoseconds
        guard deadlineNs > 0 else { return (nil, 0, "metal-timeout") }
        workerLock.lock()
        guard !workerBusy else { workerLock.unlock(); return (nil, 0, "metal-busy") }
        workerBusy = true
        workerLock.unlock()
        let work = BoundedMetalResult()
        metalWorker.async { [self] in
            if workerDelayNs > 0 { Thread.sleep(forTimeInterval: Double(workerDelayNs) / 1_000_000_000) }
            work.output = metal(input)?.0
            work.timedOut = metalTimedOut
            workerLock.lock(); workerBusy = false; workerLock.unlock()
            work.done.signal()
        }
        // Poll only within the short tic budget. A timed semaphore wake was
        // observed tens of milliseconds late under GPU load on macOS.
        while work.done.wait(timeout: .now()) == .timedOut {
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            if elapsed >= deadlineNs { return (nil, elapsed, "metal-timeout") }
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        guard elapsed < deadlineNs else { return (nil, elapsed, "metal-timeout") }
        guard let output = work.output else { return (nil, elapsed, work.timedOut ? "metal-timeout" : "metal") }
        return (output, elapsed, "none")
    }

    func evaluate(_ input: HMMovementInput, reference: HMMovementOutput) -> HMMovementOutput? {
        tick += 1
        lastReference = reference
        var validatedInput = input
        guard HM_InputInDomain(&validatedInput) != 0 else {
            domainFallbacks += 1; lastResult = reference; lastFallback = "domain"; lastLatencyNs = 0
            if visualizationEnabled { countersHandler?() }
            return nil
        }
        let (candidate, ns, reason) = boundedMetal(input)
        guard let result = candidate else {
            metalFallbacks += 1; lastResult = reference; lastFallback = reason; lastLatencyNs = ns
            if visualizationEnabled { countersHandler?() }
            return nil
        }
        lastResult = result; lastFallback = "none"; lastLatencyNs = ns
        if result.forwardmove != reference.forwardmove || result.sidemove != reference.sidemove || result.angleturn != reference.angleturn || result.turnheld != reference.turnheld {
            mismatches += 1; lastResult = reference; lastFallback = "mismatch"
            if visualizationEnabled { countersHandler?() }
            return nil
        }
        circuitTics += 1
        latencies.append(ns)
        if latencies.count > 4096 { latencies.removeFirst() }
        if visualizationEnabled && tick % 4 == 0 {
            let (_, values, layerTimes) = cpuReplay(input, trace: true, measure: true)
            let trace = CircuitTrace(tick: tick, sourceHash: Self.hash(Self.cells(input)), capturedNs: DispatchTime.now().uptimeNanoseconds,
                                     circuit: result, reference: reference, latencyNs: ns, fallback: nil,
                                     layers: summarize(values, layerTimes: layerTimes), values: values, changedTurnheld: Self.cells(input)[21] != result.turnheld)
            traces.append(trace)
            traceHandler?(trace, traces.dropped)
        }
        return result
    }

    private func summarize(_ values: [Float], layerTimes: [UInt64]) -> [LayerTelemetry] {
        (1...graph.layerCount).map { layer in
            let selected = graph.infos.filter { $0.layer == layer }
            let sample = selected.map { values[$0.id] }
            let gates = selected.filter { $0.kind == "reglu" }
            let booleans = selected.filter { $0.boolean }
            let open = gates.filter { values[$0.id] != 0 }.count
            var heat = Array(repeating: 0, count: 8)
            for value in sample {
                let bucket = min(7, max(0, Int(log2(Double(abs(value)) + 1))))
                heat[bucket] += 1
            }
            return LayerTelemetry(id: layer, affine: selected.filter { $0.kind == "affine" }.count,
                                  reglu: gates.count, index: selected.filter { $0.kind == "index" }.count,
                                  nonzero: sample.filter { $0 != 0 }.count, gateOpen: open, gateClosed: gates.count-open,
                                  booleanCount: booleans.count,
                                  booleanActive: booleans.filter { values[$0.id] != 0 }.count,
                                  heat: heat, minValue: sample.min() ?? 0, maxValue: sample.max() ?? 0,
                                  cpuReplayNs: layerTimes[layer - 1])
        }
    }

    func neighborhood(root: Int, trace: CircuitTrace, limit: Int = 64) -> [(OpInfo, Float)] {
        var seen = Set<Int>(), work = [graph.roots[root]], result: [(OpInfo, Float)] = []
        while let id = work.popLast(), result.count < min(limit, 64) {
            guard id >= 24, seen.insert(id).inserted else { continue }
            let info = graph.infos[id-24]
            result.append((info, trace.values[id]))
            work.append(contentsOf: info.parents.reversed())
        }
        return result
    }
}
