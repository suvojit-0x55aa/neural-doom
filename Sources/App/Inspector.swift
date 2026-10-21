import AppKit
import SwiftUI

final class InspectorModel: ObservableObject {
    @Published var trace: CircuitTrace?
    @Published var graph: CircuitGraph?
    @Published var dropped = 0
    @Published var circuitTics = 0
    @Published var domainFallbacks = 0
    @Published var metalFallbacks = 0
    @Published var mismatches = 0
    @Published var fallbackReason = "none"
    @Published var remainderTrace: RemainderTrace?
    @Published var remainderGraph: RemainderGraph?
    @Published var remainderDropped = 0
    @Published var remainderCircuitTics = 0
    @Published var remainderDomainFallbacks = 0
    @Published var remainderMetalFallbacks = 0
    @Published var remainderMismatches = 0
    @Published var remainderFallbackReason = "none"
    @Published var isPaused = false
    @Published var moduleRows: [ModuleTelemetrySnapshot] = []
    weak var engine: EngineCoordinator?
    func publish(trace: CircuitTrace, graph: CircuitGraph, dropped: Int,
                 circuitTics: Int, domainFallbacks: Int, metalFallbacks: Int, mismatches: Int,
                 fallbackReason: String) {
        self.trace = trace; self.graph = graph; self.dropped = dropped
        self.circuitTics = circuitTics; self.domainFallbacks = domainFallbacks
        self.metalFallbacks = metalFallbacks; self.mismatches = mismatches
        self.fallbackReason = fallbackReason
    }
    func refreshCounts(circuitTics: Int, domainFallbacks: Int, metalFallbacks: Int, mismatches: Int,
                       fallbackReason: String) {
        self.circuitTics = circuitTics; self.domainFallbacks = domainFallbacks
        self.metalFallbacks = metalFallbacks; self.mismatches = mismatches
        self.fallbackReason = fallbackReason
    }
    func publishRemainder(trace: RemainderTrace, graph: RemainderGraph, dropped: Int,
                          circuitTics: Int, domainFallbacks: Int, metalFallbacks: Int, mismatches: Int,
                          fallbackReason: String) {
        self.remainderTrace = trace; self.remainderGraph = graph; self.remainderDropped = dropped
        refreshRemainderCounts(circuitTics: circuitTics, domainFallbacks: domainFallbacks,
                               metalFallbacks: metalFallbacks, mismatches: mismatches,
                               fallbackReason: fallbackReason)
    }
    func refreshRemainderCounts(circuitTics: Int, domainFallbacks: Int, metalFallbacks: Int,
                                mismatches: Int, fallbackReason: String) {
        self.remainderCircuitTics = circuitTics
        self.remainderDomainFallbacks = domainFallbacks
        self.remainderMetalFallbacks = metalFallbacks
        self.remainderMismatches = mismatches
        self.remainderFallbackReason = fallbackReason
    }
    func pause() { isPaused = true; engine?.pause() }
    func resume() { isPaused = false; engine?.resume() }
    func step() { engine?.step() }
}

struct InspectorView: View {
    @ObservedObject var model: InspectorModel
    @State private var selectedOutput = 0
    @State private var selectedRemainderOutput = 1
    private let outputs = ["forwardmove", "sidemove", "angleturn", "turnheld"]
    private let remainderOutputs = ["angleturn", "buttons", "chat", "consistency", "buttons2", "inventory",
                                    "lookfly", "arti", "dclick time", "dclick state", "dclick count",
                                    "strafe time", "strafe state", "strafe count", "lowres carry",
                                    "mouse speed", "next weapon", "pause", "save", "mouse X", "mouse Y"]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CIRCUIT INSPECTOR").font(.system(.headline, design: .monospaced))
            if let trace = model.trace, let graph = model.graph {
                HStack {
                    Text("tic \(trace.tick)")
                    Spacer()
                    Text("\(graph.operationCount) ops · \(graph.layerCount) layers")
                }.font(.system(.caption, design: .monospaced))
                Text(String(format: "Circuit attempt %.3f ms · sampled CPU replay", Double(trace.latencyNs) / 1_000_000))
                    .font(.caption)
                Text("Circuit \(model.circuitTics) · domain fallback \(model.domainFallbacks) · Metal fallback \(model.metalFallbacks) · mismatch \(model.mismatches) · dropped \(model.dropped)")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Text("Latest fallback: \(model.fallbackReason)").font(.caption)
                moduleRowsView
                HStack {
                    Button("Pause") { model.pause() }.disabled(model.isPaused)
                    Button("Step one tic") { model.step() }.disabled(!model.isPaused)
                    Button("Resume") { model.resume() }.disabled(!model.isPaused)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("LAYERS · heat: log₂ |activation|").font(.system(.caption, design: .monospaced)).bold()
                        ForEach(trace.layers, id: \.id) { layer in
                            HStack(spacing: 5) {
                                Text(String(format: "%02d", layer.id)).frame(width: 24, alignment: .leading)
                                Text("A\(layer.affine) G\(layer.reglu) I\(layer.index)").frame(width: 90, alignment: .leading)
                                HStack(spacing: 1) {
                                    ForEach(0..<8, id: \.self) { bin in
                                        Rectangle().fill(Color.orange.opacity(layer.heat[bin] == 0 ? 0.08 : min(1, Double(layer.heat[bin]) / 5 + 0.2)))
                                            .frame(width: 12, height: 13)
                                    }
                                }
                                Text(String(format: "%d active · G %d/%d · B %d/%d · %.1f µs CPU", layer.nonzero,
                                            layer.gateOpen, layer.reglu, layer.booleanActive, layer.booleanCount,
                                            Double(layer.cpuReplayNs)/1000))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }.font(.system(size: 10, design: .monospaced))
                        }
                        Divider()
                        Text("REFERENCE C  /  CIRCUIT").font(.system(.caption, design: .monospaced)).bold()
                        comparison("forward", trace.reference.forwardmove, trace.circuit.forwardmove)
                        comparison("side", trace.reference.sidemove, trace.circuit.sidemove)
                        comparison("angle", trace.reference.angleturn, trace.circuit.angleturn)
                        comparison("turnheld", trace.reference.turnheld, trace.circuit.turnheld)
                        Text(trace.changedTurnheld ? "state cell turnheld changed" : "state cell turnheld unchanged").font(.caption)
                        Text("Source FNV64 \(String(trace.sourceHash, radix: 16))").font(.system(size: 10, design: .monospaced))
                        Divider()
                        Picker("Output neighborhood", selection: $selectedOutput) {
                            ForEach(0..<4, id: \.self) { Text(outputs[$0]).tag($0) }
                        }
                        let nodes = model.engine?.circuit.neighborhood(root: selectedOutput, trace: trace) ?? []
                        Text("\(nodes.count) of at most 64 upstream operations · stable IDs").font(.caption)
                        ForEach(nodes, id: \.0.id) { node in
                            Text("#\(node.0.id) L\(node.0.layer) \(node.0.kind) \(node.0.label) = \(Int(node.1))")
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider()
                        Text("TIC REMAINDER · COMPLETE COMMAND").font(.system(.caption, design: .monospaced)).bold()
                        if let remainder = model.remainderTrace, let remainderGraph = model.remainderGraph {
                            Text("\(remainderGraph.operationCount) ops · \(remainderGraph.layerCount) layers · circuit \(model.remainderCircuitTics) · domain \(model.remainderDomainFallbacks) · Metal \(model.remainderMetalFallbacks) · mismatch \(model.remainderMismatches) · dropped \(model.remainderDropped)")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                            Text(String(format: "Circuit attempt %.3f ms · latest fallback %@", Double(remainder.latencyNs) / 1_000_000, model.remainderFallbackReason))
                                .font(.caption)
                            comparison("angle final", remainder.reference.angleturn, remainder.circuit.angleturn)
                            comparison("buttons", remainder.reference.buttons, remainder.circuit.buttons)
                            comparison("chat", remainder.reference.chatchar, remainder.circuit.chatchar)
                            comparison("lowres carry", remainder.reference.lowres_carry, remainder.circuit.lowres_carry)
                            Text("Changed state cells: " + (remainder.changedStateCells.isEmpty ? "none" : remainder.changedStateCells.joined(separator: ", ")))
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                            DisclosureGroup("Remainder layers · activation heat and gate activity") {
                                ForEach(remainder.layers, id: \.id) { layer in
                                    HStack(spacing: 5) {
                                        Text(String(format: "%02d", layer.id)).frame(width: 24, alignment: .leading)
                                        Text("A\(layer.affine) G\(layer.reglu) I\(layer.index)").frame(width: 90, alignment: .leading)
                                        HStack(spacing: 1) {
                                            ForEach(0..<8, id: \.self) { bin in
                                                Rectangle().fill(Color.cyan.opacity(layer.heat[bin] == 0 ? 0.08 : min(1, Double(layer.heat[bin]) / 5 + 0.2)))
                                                    .frame(width: 12, height: 13)
                                            }
                                        }
                                        Text("\(layer.nonzero) active · G \(layer.gateOpen)/\(layer.reglu) · B \(layer.booleanActive) · \(String(format: "%.1f", Double(layer.cpuReplayNs)/1000)) µs CPU")
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                    }.font(.system(size: 10, design: .monospaced))
                                }
                            }
                            Picker("Remainder output neighborhood", selection: $selectedRemainderOutput) {
                                ForEach(0..<remainderOutputs.count, id: \.self) { Text(remainderOutputs[$0]).tag($0) }
                            }
                            let remainderNodes = model.engine?.remainder.neighborhood(root: selectedRemainderOutput, trace: remainder) ?? []
                            Text("\(remainderNodes.count) of at most 64 upstream operations · stable IDs").font(.caption)
                            ForEach(remainderNodes, id: \.0.id) { node in
                                Text("#\(node.0.id) L\(node.0.layer) \(node.0.kind) \(node.0.label) = \(Int(node.1))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Text("Waiting for the first sampled remainder tic.").font(.caption)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Waiting for the first sampled game tic. Move to see circuit activity.")
                HStack {
                    Button("Pause") { model.pause() }
                    Button("Step one tic") { model.step() }.disabled(!model.isPaused)
                    Button("Resume") { model.resume() }
                }
            }
        }.padding(14).frame(minWidth: 530, minHeight: 600)
    }
    /// One generic row per scheduled module; later modules appear here with no inspector edits.
    private var moduleRowsView: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.moduleRows, id: \.id) { row in
                Text(String(format: "%@ · phase %d · circuit %d/%d · accepted p50 %.3f p99 %.3f ms · wait p99 %.3f · commit p99 %.3f · high-water in %d out %d Δ %d ev %d · fallbacks %@",
                            row.name, row.phase, row.circuitTics, row.attempts,
                            Double(row.acceptedP50Ns) / 1e6, Double(row.acceptedP99Ns) / 1e6,
                            Double(row.queueWaitP99Ns) / 1e6, Double(row.commitP99Ns) / 1e6,
                            row.highWater.inputs, row.highWater.outputs, row.highWater.deltas, row.highWater.events,
                            row.fallbacks.isEmpty ? "none" : row.fallbacks.map { "\($0.reason) \($0.count)" }.joined(separator: ", ")))
                    .font(.system(size: 10, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func comparison(_ name: String, _ c: Int32, _ circuit: Int32) -> some View {
        HStack {
            Text(name).frame(width: 90, alignment: .leading)
            Text("\(c)").frame(width: 80, alignment: .trailing)
            Text("→")
            Text("\(circuit)").frame(width: 80, alignment: .trailing)
            Text(c == circuit ? "MATCH" : "MISMATCH").foregroundStyle(c == circuit ? .green : .red)
        }.font(.system(.caption, design: .monospaced))
    }
}

final class InspectorPanel: NSPanel {
    init(model: InspectorModel) {
        super.init(contentRect: NSRect(x: 100, y: 100, width: 580, height: 690),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        title = "Neural Doom — Circuit Inspector"
        contentView = NSHostingView(rootView: InspectorView(model: model))
        isReleasedWhenClosed = false
    }
}
