import Foundation
import Metal
import CryptoKit

struct Generator {
    var state: UInt64 = 0x9e3779b97f4a7c15
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
    mutating func span(_ width: UInt64) -> Int32 { Int32(next() % width) }
    mutating func snapshot() -> HMMovementInput {
        var c = [Int32](repeating: 0, count: 24)
        for i in 0...12 { c[i] = span(2) }
        c[13] = span(513) - 256
        c[14] = span(16385) - 8192
        for i in 15...17 { c[i] = span(2) }
        for i in 18...20 { c[i] = span(3) - 1 }
        c[21] = span(16_777_213)
        c[22] = span(4) + 1
        return CircuitRuntime.input(c)
    }
    mutating func remainderSnapshot(_ movement: HMMovementInput) -> HMTicRemainderInput {
        let m = CircuitRuntime.cells(movement)
        var c = [Int32](repeating: 0, count: RemainderGraph.inputCount)
        for i in 4...18 { c[i] = span(2) }
        c[19] = span(3) - 1
        c[20] = span(9)
        c[21] = span(10); if c[21] == 9 { c[21] = 10 }
        for i in 22...34 { c[i] = span(2) }
        if c[33] == 1 { c[32] = 1 }
        c[35] = span(2)
        c[36] = span(50)
        c[37] = span(2)
        c[38] = span(3)
        c[39] = span(50)
        c[40] = span(2)
        c[41] = span(3)
        c[42] = span(2); c[43] = span(2)
        c[44] = span(8)
        c[45] = span(2)
        c[46] = span(256) - 128
        c[47] = span(256)
        c[48] = span(256)
        c[49] = span(8193)
        c[50] = m[13]
        c[51] = m[9]; c[52] = m[8]; c[53] = m[15]; c[54] = m[22]
        return RemainderRuntime.input(c)
    }
}
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func same(_ a: HMMovementOutput, _ b: HMMovementOutput) -> Bool {
    a.forwardmove == b.forwardmove && a.sidemove == b.sidemove && a.angleturn == b.angleturn && a.turnheld == b.turnheld
}
func percentile(_ xs: [UInt64], _ p: Double) -> Double {
    let ordered = xs.sorted()
    return Double(ordered[min(ordered.count-1, Int(Double(ordered.count-1)*p))]) / 1_000_000
}
if CommandLine.arguments.contains("--data-directory-compatibility") {
    let support = URL(fileURLWithPath: "/test/Application Support", isDirectory: true)
    let legacy = support.appendingPathComponent("HandwiredDoom", isDirectory: true)
    let current = support.appendingPathComponent("NeuralDoom", isDirectory: true)
    require(defaultDoomDataDirectory(
        environment: ["HANDWIRED_DOOM_DATA_DIR": "/explicit/profile"],
        applicationSupportDirectory: support,
        directoryExists: { _ in true }
    ) == nil, "explicit data directory was overridden")
    require(defaultDoomDataDirectory(
        environment: [:],
        applicationSupportDirectory: support,
        directoryExists: { $0 == legacy.path }
    ) == legacy, "legacy data directory was not reused")
    require(defaultDoomDataDirectory(
        environment: [:],
        applicationSupportDirectory: support,
        directoryExists: { _ in false }
    ) == current, "fresh install did not select NeuralDoom data directory")
    print("data directory: explicit override preserved, legacy profile reused, fresh profile renamed")
    exit(0)
}
runSeamChild(CommandLine.arguments)
let graph = CircuitGraph()
if let at = CommandLine.arguments.firstIndex(of: "--app-bundle"), at + 1 < CommandLine.arguments.count {
    let app = URL(fileURLWithPath: CommandLine.arguments[at+1], isDirectory: true)
    guard let bundle = Bundle(url: app),
          let wad = bundle.url(forResource: "freedoom1", withExtension: "wad"),
          let notice = bundle.url(forResource: "FREEDOOM-COPYING", withExtension: "txt"),
          let credits = bundle.url(forResource: "FREEDOOM-CREDITS", withExtension: "txt"),
          bundle.url(forResource: "Locomotion", withExtension: "msl") != nil,
          bundle.url(forResource: "TicRemainder", withExtension: "msl") != nil,
          bundle.url(forResource: "CircuitExactV1", withExtension: "msl") != nil,
          bundle.url(forResource: "Present", withExtension: "msl") != nil else {
        fputs("FAIL: clean app is missing a bundled IWAD, attribution, or circuit shader\n", stderr); exit(1)
    }
    require(!wad.path.contains("/Sources/"), "IWAD resolved from source tree")
    require(IWADValidator.error(for: wad) == nil, "bundled IWAD failed readability/header/directory validation")
    let data = try Data(contentsOf: wad)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    require(digest == "7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d", "bundled IWAD checksum changed")
    let licenseText = try String(contentsOf: notice)
    let creditsText = try String(contentsOf: credits)
    require(licenseText.contains("Redistribution and use"), "Freedoom license missing")
    require(creditsText.contains("Freedoom"), "Freedoom credits missing")
    guard case .success(let bundledTables) = IWADValidator.mapTables(for: wad),
          (try? Data(contentsOf: mapManifestURL)) == bundledTables.manifestJSON() else {
        fputs("FAIL: bundled Freedoom did not load through MapTablesV1 or its manifest is stale\n", stderr); exit(1)
    }
    require(IWADValidator.redactedDescription(of: wad, tables: bundledTables) == "freedoom1.wad [sha256 7323bcc168c5]"
            && !IWADValidator.redactedDescription(of: wad, tables: bundledTables).contains("/"),
            "WAD description is not redacted to basename and fingerprint")
    print("clean app bundle: bundled Freedoom E1M1 loaded through MapTablesV1 (source hash \(String(format: "0x%016llx", bundledTables.sourceHash)))")
    print("clean app bundle: IWAD resolves outside source tree, header/directory readable, SHA-256 \(digest), license and credits present")
    exit(0)
}
if CommandLine.arguments.contains("--emit-manifest") {
    let path = CommandLine.arguments.last!
    try graph.manifestJSON().write(to: URL(fileURLWithPath: path))
    print("manifest: \(graph.operationCount) operations, \(graph.layerCount) layers")
    exit(0)
}
let remainderGraph = RemainderGraph()
if CommandLine.arguments.contains("--emit-remainder-manifest") {
    let path = CommandLine.arguments.last!
    try remainderGraph.manifestJSON().write(to: URL(fileURLWithPath: path))
    print("remainder manifest: \(remainderGraph.operationCount) operations, \(remainderGraph.layerCount) layers")
    exit(0)
}
let committedManifest = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Docs/locomotion-graph.json")
require((try? Data(contentsOf: committedManifest)) == graph.manifestJSON(), "generated graph manifest is stale")
let committedRemainderManifest = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Docs/tic-remainder-graph.json")
require((try? Data(contentsOf: committedRemainderManifest)) == remainderGraph.manifestJSON(),
        "generated remainder graph manifest is stale")
require(remainderGraph.liveOperationCount == remainderGraph.operationCount, "remainder graph has dead operations")
require(graph.operationCount <= 232, "frozen graph exceeds 256-cell Metal scratch bound")
require(graph.liveOperationCount == graph.operationCount, "manifest counts dead builder allocations")
require(MemoryLayout<CircuitOp>.stride == 32, "operation ABI is not 32 bytes")
runCircuitContractTests()
runMapTablesTests()
runSchedulerTests()
runSeamTests(CommandLine.arguments)
if CommandLine.arguments.contains("--contracts") { exit(0) }
guard MTLCreateSystemDefaultDevice() != nil else { fputs("FAIL: Apple Silicon Metal device unavailable\n", stderr); exit(1) }
let circuit = CircuitRuntime(deadlineNs: 1_000_000_000)
var generator = Generator()
var cpuMismatch = 0, metalMismatch = 0, extractionMismatch = 0
let total = CommandLine.arguments.contains("--micro") ? 20 : (CommandLine.arguments.contains("--smoke") ? 200 : (CommandLine.arguments.contains("--quick") ? 1000 : 100_000))
let start = DispatchTime.now().uptimeNanoseconds
for i in 0..<total {
    let input = generator.snapshot()
    var copy = input
    require(HM_InputInDomain(&copy) == 1, "generated input outside domain")
    let reference = HM_TestOriginalMovement(&copy)
    let extraction = HM_ReferenceMovement(&copy)
    if !same(reference, extraction) {
        extractionMismatch += 1
        if extractionMismatch < 4 { print("C extraction mismatch at \(i): \(reference) vs \(extraction)") }
    }
    let (cpu, _) = circuit.cpu(input)
    if !same(reference, cpu) {
        cpuMismatch += 1
        if cpuMismatch < 4 { print("CPU mismatch at \(i): \(reference) vs \(cpu)") }
    }
    guard let (gpu, _) = circuit.metal(input) else { fputs("FAIL: Metal command failed at \(i)\n", stderr); exit(1) }
    if !same(reference, gpu) {
        metalMismatch += 1
        if metalMismatch < 4 { print("Metal mismatch at \(i): \(reference) vs \(gpu)") }
    }
}
require(cpuMismatch == 0 && metalMismatch == 0 && extractionMismatch == 0, "locomotion parity")
let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000

// Domain boundary rejects every invalid category before GPU submission.
var domainChecks = 0
for (at, value) in [(0,2), (13,257), (13,-257), (14,8193), (14,-8193),
                    (18,2), (21,-1), (21,16_777_213), (22,0), (22,5)] {
    var c = [Int32](repeating: 0, count: 24); c[22] = 1; c[at] = Int32(value)
    var input = CircuitRuntime.input(c)
    require(HM_InputInDomain(&input) == 0, "domain accepted cell \(at)=\(value)")
    domainChecks += 1
}

let ring = TraceRing(capacity: 128)
let dummy = HMMovementOutput(forwardmove: 0, sidemove: 0, angleturn: 0, turnheld: 0)
for i in 0..<1000 {
    ring.append(CircuitTrace(tick: i, sourceHash: 0, capturedNs: 0, circuit: dummy,
                             reference: dummy, latencyNs: 0, fallback: nil, layers: [],
                             values: [], changedTurnheld: false))
}
require(ring.items.count == 128 && ring.dropped == 872 && ring.items.first?.tick == 872, "ring bounds/drops")

var scheduler = TicScheduler()
let period = scheduler.periodNs
require(scheduler.due(now: 0) == 0, "scheduler initial tick")
require(scheduler.due(now: period * 3) == 3, "three tics in one presented frame")
scheduler.pause(now: period * 3)
require(scheduler.due(now: period * 200) == 0, "paused engine advanced")
require(scheduler.step() == 1 && scheduler.step() == 1, "step did not yield one tic per invocation")
scheduler.resume(now: period * 200)
require(scheduler.due(now: period * 200) == 0, "resume caught up paused wall time")
require(scheduler.due(now: period * 201) == 1, "resume did not yield next tic")
require(scheduler.step() == 0, "step ran when not paused")

// Visualization samples are a replay of the already committed values.
var vizChecks = 0
for _ in 0..<1000 {
    let input = generator.snapshot()
    let (off, offTrace) = circuit.cpu(input, trace: false)
    let (on, onTrace) = circuit.cpu(input, trace: true)
    require(same(off, on) && offTrace.isEmpty && onTrace.count == 24 + graph.operationCount,
            "visualization changed outputs or wrote off-mode trace")
    vizChecks += 1
}
let live = CircuitRuntime(deadlineNs: 1_000_000_000)
for _ in 0..<8 {
    var input = generator.snapshot()
    let reference = HM_TestOriginalMovement(&input)
    require(live.evaluate(input, reference: reference) != nil, "off-mode circuit did not own command")
}
require(live.traces.items.isEmpty, "visualization-off wrote operation trace")
live.visualizationEnabled = true
for _ in 0..<16 {
    var input = generator.snapshot()
    let reference = HM_TestOriginalMovement(&input)
    require(live.evaluate(input, reference: reference) != nil, "on-mode circuit changed result")
}
require(live.traces.items.count == 4, "sample rate is not one trace in four tics")
for trace in live.traces.items {
    require(!trace.mismatch && trace.layers.count == graph.layerCount, "live layer/compare telemetry")
    require(trace.values.count == 24 + graph.operationCount, "live sampled values missing")
    for root in 0..<4 { require(live.neighborhood(root: root, trace: trace).count <= 64, "drill-down exceeded 64 operations") }
}
var invalid = [Int32](repeating: 0, count: 24); invalid[22] = 1; invalid[13] = 257
let rejected = CircuitRuntime.input(invalid)
let previousCircuitTics = live.circuitTics
require(live.evaluate(rejected, reference: dummy) == nil && live.domainFallbacks == 1
        && live.circuitTics == previousCircuitTics, "live domain fallback dispatched circuit")
let failedMetal = CircuitRuntime(device: nil)
var valid = CircuitRuntime.input([Int32](repeating: 0, count: 22) + [1, 0])
let fallbackReference = HM_TestOriginalMovement(&valid)
require(failedMetal.evaluate(valid, reference: fallbackReference) == nil && failedMetal.metalFallbacks == 1,
        "Metal failure did not select reference fallback")
let expiredDeadline = CircuitRuntime(deadlineNs: 0)
require(expiredDeadline.evaluate(valid, reference: fallbackReference) == nil
        && expiredDeadline.metalFallbacks == 1 && expiredDeadline.lastFallback == "metal-timeout",
        "expired Metal deadline did not select reference fallback")
let stalledWorker = CircuitRuntime(deadlineNs: 2_000_000, workerDelayNs: 50_000_000)
require(stalledWorker.evaluate(valid, reference: fallbackReference) == nil
        && stalledWorker.metalFallbacks == 1 && stalledWorker.lastFallback == "metal-timeout"
        && stalledWorker.circuitTics == 0,
        "stalled Metal encoding did not select same-tic reference fallback")
print("parity: \(total) generated snapshots versus original G_BuildTiccmd, C extraction mismatches \(extractionMismatch), CPU mismatches \(cpuMismatch), Metal mismatches \(metalMismatch)")
print("domain: \(domainChecks) rejected invalid snapshots + live domain/Metal fallbacks; ring: 1000 appends, capacity 128, drops \(ring.dropped); pause/step: 7 assertions; visualization: \(vizChecks) invariant checks + 24 live tics / 4 sampled traces")
print(String(format: "batch %.2f s; graph %d ops, %d layers", elapsed, graph.operationCount, graph.layerCount))

// Warm, isolated synchronous submit/wait distribution; in-game pacing is
// reported by the run trace separately, never inferred from this probe.
var ns: [UInt64] = []
let sample = generator.snapshot()
for _ in 0..<100 { _ = circuit.metal(sample) }
for _ in 0..<1000 { if let (_, t) = circuit.metal(sample) { ns.append(t) } }
require(ns.count == 1000, "latency sample count")
print(String(format: "Metal sync latency (1000 warm samples, ms): median %.3f p95 %.3f p99 %.3f", percentile(ns, 0.5), percentile(ns, 0.95), percentile(ns, 0.99)))

let remainder = RemainderRuntime(deadlineNs: 1_000_000_000)
require(MemoryLayout<HMTicRemainderOutput>.stride == RemainderGraph.outputCount * 4, "remainder output ABI")
var remainderCMismatch = 0, remainderCPUMismatch = 0, remainderMetalMismatch = 0
var remainderNs: [UInt64] = []
for i in 0..<total {
    let movement = generator.snapshot()
    var before = generator.remainderSnapshot(movement)
    var captured = HMTicRemainderInput()
    var movementCopy = movement
    let original = HM_TestOriginalRemainder(&movementCopy, &before, &captured)
    require(HM_RemainderInputInDomain(&captured) == 1, "captured remainder input outside domain at \(i)")
    let pure = HM_ReferenceRemainder(&captured)
    let (cpu, _, _) = remainder.cpu(captured)
    guard let (gpu, gpuNs) = remainder.metal(captured) else { fputs("FAIL: remainder Metal command failed at \(i)\n", stderr); exit(1) }
    remainderNs.append(gpuNs)
    if RemainderRuntime.cells(pure) != RemainderRuntime.cells(original) {
        remainderCMismatch += 1
        if remainderCMismatch < 4 { print("remainder C mismatch at \(i): \(RemainderRuntime.cells(pure)) vs \(RemainderRuntime.cells(original)); input \(RemainderRuntime.cells(captured))") }
    }
    if RemainderRuntime.cells(cpu) != RemainderRuntime.cells(original) {
        remainderCPUMismatch += 1
        if remainderCPUMismatch < 4 { print("remainder CPU mismatch at \(i): \(RemainderRuntime.cells(cpu)) vs \(RemainderRuntime.cells(original))") }
    }
    if RemainderRuntime.cells(gpu) != RemainderRuntime.cells(original) {
        remainderMetalMismatch += 1
        if remainderMetalMismatch < 4 { print("remainder Metal mismatch at \(i): \(RemainderRuntime.cells(gpu)) vs \(RemainderRuntime.cells(original))") }
    }
}
require(remainderCMismatch == 0 && remainderCPUMismatch == 0 && remainderMetalMismatch == 0, "full ticcmd remainder parity")
print("remainder parity: \(total) generated full-ticcmd snapshots, C extraction \(remainderCMismatch), CPU \(remainderCPUMismatch), Metal \(remainderMetalMismatch) mismatches; \(remainderGraph.operationCount) ops, \(remainderGraph.layerCount) layers")
print(String(format: "remainder Metal sync latency (ms): median %.3f p95 %.3f p99 %.3f", percentile(remainderNs, 0.5), percentile(remainderNs, 0.95), percentile(remainderNs, 0.99)))

// Stateful edge cases run through the original G_BuildTiccmd each tic, then
// compare every output and carried cell with the two exact evaluators.
var adversarialChecks = 0
func adversarial(_ m: [Int32], _ r: [Int32], _ label: String) -> HMTicRemainderOutput {
    var movement = CircuitRuntime.input(m)
    var before = RemainderRuntime.input(r)
    var captured = HMTicRemainderInput()
    let original = HM_TestOriginalRemainder(&movement, &before, &captured)
    require(HM_RemainderInputInDomain(&captured) == 1, "adversarial domain \(label)")
    require(RemainderRuntime.cells(HM_ReferenceRemainder(&captured)) == RemainderRuntime.cells(original), "adversarial C \(label)")
    require(RemainderRuntime.cells(remainder.cpu(captured).0) == RemainderRuntime.cells(original), "adversarial CPU \(label)")
    guard let gpu = remainder.metal(captured)?.0 else { fputs("FAIL: adversarial Metal \(label)\n", stderr); exit(1) }
    require(RemainderRuntime.cells(gpu) == RemainderRuntime.cells(original), "adversarial Metal \(label)")
    adversarialChecks += 1
    return original
}
var motion = [Int32](repeating: 0, count: 24); motion[22] = 1
var state = [Int32](repeating: 0, count: RemainderGraph.inputCount)
state[18] = 1; state[20] = 1; state[21] = 10; state[22] = 1; state[23] = 1; state[32] = 1; state[33] = 1; state[54] = 1
func carryState(_ result: HMTicRemainderOutput, _ cells: inout [Int32]) {
    cells[36] = result.dclicktime; cells[37] = result.dclickstate; cells[38] = result.dclicks
    cells[39] = result.dclicktime2; cells[40] = result.dclickstate2; cells[41] = result.dclicks2
    cells[46] = result.lowres_carry
}
state[35] = 1; state[36] = 2; state[39] = 2
for tick in 0..<12 {
    motion[9] = (3...5).contains(tick) || tick == 9 ? 1 : 0
    let result = adversarial(motion, state, "forward double-click tic \(tick)")
    if tick == 9 { require(result.buttons & 2 != 0, "second forward click did not use") }
    carryState(result, &state)
}
state[36] = 2; state[37] = 0; state[38] = 0
state[39] = 2; state[40] = 0; state[41] = 0
motion[9] = 0
for tick in 0..<12 {
    motion[8] = (3...5).contains(tick) || tick == 9 ? 1 : 0
    let result = adversarial(motion, state, "strafe double-click tic \(tick)")
    if tick == 9 { require(result.buttons & 2 != 0, "second strafe click did not use") }
    carryState(result, &state)
}
motion[8] = 0
state[35] = 0
state[24] = 1; state[25] = 1; state[28] = 1
for direction in [-1, 1] {
    state[19] = Int32(direction)
    let result = adversarial(motion, state, "weapon cycle \(direction)")
    require(result.buttons & 4 != 0, "weapon cycle did not set change")
}
state[19] = 0; state[4] = 1; state[7] = 1; state[10] = 1
let held = adversarial(motion, state, "held attack/use/weapon")
require(held.buttons & 7 == 7, "held buttons absent")
state[42] = 1; state[43] = 1; state[44] = 5
let special = adversarial(motion, state, "save overrides pause")
require(special.buttons == 150 && special.sendpause == 0 && special.sendsave == 0, "special precedence or state reset")
state[42] = 0; state[43] = 0; state[45] = 1; motion[2] = 1
for tick in 0..<32 {
    let result = adversarial(motion, state, "lowres carry tic \(tick)")
    require(result.angleturn & 255 == 0, "lowres angle not quantized")
    carryState(result, &state)
}
state[45] = 0; state[47] = 65; state[48] = 234
_ = adversarial(motion, state, "chat and consistency passthrough")

var invalidRemainder = state; invalidRemainder[21] = 9
var invalidInput = RemainderRuntime.input(invalidRemainder)
require(HM_RemainderInputInDomain(&invalidInput) == 0, "invalid pending weapon accepted")
let remainderFallback = RemainderRuntime(device: nil)
var validRemainder = RemainderRuntime.input(state)
let remainderFallbackReference = HM_ReferenceRemainder(&validRemainder)
require(remainderFallback.evaluate(validRemainder, reference: remainderFallbackReference) == nil
        && remainderFallback.metalFallbacks == 1, "remainder Metal fallback failed")
let expiredRemainder = RemainderRuntime(deadlineNs: 0)
require(expiredRemainder.evaluate(validRemainder, reference: remainderFallbackReference) == nil
        && expiredRemainder.lastFallback == "metal-timeout", "remainder deadline fallback failed")
let visualRemainder = RemainderRuntime(deadlineNs: 1_000_000_000)
for i in 0..<24 {
    var input = RemainderRuntime.input(state)
    let reference = HM_ReferenceRemainder(&input)
    if i == 8 { visualRemainder.visualizationEnabled = true }
    require(visualRemainder.evaluate(input, reference: reference) != nil, "remainder visualization changed result")
}
require(visualRemainder.traces.items.count == 2, "remainder visualization sampling")
for trace in visualRemainder.traces.items {
    require(trace.layers.count == remainderGraph.layerCount, "remainder layer telemetry")
    for root in 0..<RemainderGraph.outputCount {
        require(visualRemainder.neighborhood(root: root, trace: trace).count <= 64, "remainder drill-down bound")
    }
}
let remainderRing = RemainderRing(capacity: 128)
for _ in 0..<1000 { remainderRing.append(visualRemainder.traces.items[0]) }
require(remainderRing.items.count == 128 && remainderRing.dropped == 872, "remainder ring bounds/drops")
var remainderVizChecks = 0
for _ in 0..<1000 {
    let input = RemainderRuntime.input(state)
    let (off, offTrace, _) = remainder.cpu(input, trace: false)
    let (on, onTrace, _) = remainder.cpu(input, trace: true)
    require(RemainderRuntime.cells(off) == RemainderRuntime.cells(on)
            && offTrace.isEmpty && onTrace.count == RemainderGraph.inputCount + remainderGraph.operationCount,
            "remainder visualization-on/off invariant")
    remainderVizChecks += 1
}
runLegacyThroughSchedulerTests(circuit: circuit, remainder: remainder, snapshots: total)
print("remainder adversarial: \(adversarialChecks) stateful/edge snapshots; invalid-domain, Metal/deadline fallback, ring 1000/128/872, visualization \(remainderVizChecks) invariant checks + 24 live tics / 2 traces")
