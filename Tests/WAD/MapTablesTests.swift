import CryptoKit
import Foundation
import Metal

// MapTablesV1 conformance: synthetic micro-WAD snapshots, capacity boundaries,
// an adversarial corpus, the Freedoom E1M1 manifest, CPU/Metal indexed reads, and
// (in a child process, because booting DoomGeneric is one-way) C-structure parity.

@_silgen_name("HM_TestBootEngine")
private func hmTestBootEngine(_ iwad: UnsafePointer<CChar>, _ map: UnsafePointer<CChar>) -> Int32
@_silgen_name("HM_TestLoadedTable")
private func hmTestLoadedTable(_ id: UInt32, _ out: UnsafeMutablePointer<Int32>?, _ cap: Int32) -> Int32
@_silgen_name("HM_TestPatchColumns")
private func hmTestPatchColumns(_ name: UnsafePointer<CChar>, _ out: UnsafeMutablePointer<Int32>?, _ cap: Int32) -> Int32

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let freedoomURL = repoRoot.appendingPathComponent("Assets/freedoom1.wad")
let mapManifestURL = repoRoot.appendingPathComponent("Docs/map-tables-e1m1.json")

// MARK: synthetic WAD construction
private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255)] }
private func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16((v >> 16) & 0xFFFF) }
private func name8(_ s: String) -> [UInt8] { let b = Array(s.utf8); return b + [UInt8](repeating: 0, count: 8 - b.count) }

private struct MicroWAD {
    var lumps: [(name: String, bytes: [UInt8])]
    func index(_ name: String) -> Int { lumps.firstIndex { $0.name == name }! }
    mutating func set(_ name: String, _ bytes: [UInt8]) { lumps[index(name)].bytes = bytes }
    func data(magic: String = "IWAD") -> Data {
        var body = [UInt8](), dir = [UInt8]()
        for l in lumps { dir += le32(12 + body.count) + le32(l.bytes.count) + name8(l.name); body += l.bytes }
        return Data(Array(magic.utf8) + le32(lumps.count) + le32(12 + body.count) + body + dir)
    }

    // withBSP: two single-seg subsectors split by one node; otherwise zero nodes.
    static func make(withBSP: Bool) -> MicroWAD {
        let patch = le16(2) + le16(2) + le16(1) + le16(2) + le32(16) + le32(23)
            + [0, 2, 0, 0xA1, 0xA2, 0, 0xFF] + [1, 1, 0, 0xB1, 0, 0xFF]
        func texture(_ n: String) -> [UInt8] {
            name8(n) + le32(0) + le16(2) + le16(2) + le32(0) + le16(1) + le16(0) + le16(0) + le16(0) + le16(1) + le16(0)
        }
        let textures = le32(2) + le32(12) + le32(12 + 32) + texture("WALL1") + texture("WALL2")
        let sector = le16(0) + le16(128) + name8("FLAT1") + name8("FLAT1") + le16(160) + le16(9) + le16(3)
        let seg = le16(0) + le16(1) + le16(0x4000) + le16(0) + le16(0) + le16(4)
        let side = le16(2) + le16(-3 & 0xFFFF) + name8("WALL2") + name8("-") + name8("wall2") + le16(0)
        var m = MicroWAD(lumps: [
            ("PLAYPAL", (0..<768).map { UInt8(($0 * 7) & 255) }),
            ("COLORMAP", (0..<34 * 256).map { UInt8($0 & 255) }),
            ("PNAMES", le32(1) + name8("PATCH1")),
            ("TEXTURE1", textures),
            ("PATCH1", patch),
            ("S_START", []), ("SPRT", le16(3) + le16(5) + le16(1) + le16(4)), ("S_END", []),
            ("F_START", []), ("FLAT1", (0..<4096).map { UInt8($0 & 255) }), ("F_END", []),
            ("E1M1", []),
            ("THINGS", le16(32) + le16(-16 & 0xFFFF) + le16(90) + le16(1) + le16(7)),
            ("LINEDEFS", le16(0) + le16(1) + le16(1) + le16(0) + le16(0) + le16(0) + le16(0xFFFF)),
            ("SIDEDEFS", side),
            ("VERTEXES", le16(-32 & 0xFFFF) + le16(16) + le16(64) + le16(-8 & 0xFFFF)),
            ("SEGS", seg),
            ("SSECTORS", le16(1) + le16(0)),
            ("NODES", []),
            ("SECTORS", sector),
            ("REJECT", [1]),
            ("BLOCKMAP", le16(0) + le16(0) + le16(1) + le16(1) + le16(5) + le16(0) + le16(0xFFFF))
        ])
        if withBSP {
            m.set("SEGS", seg + seg)
            m.set("SSECTORS", le16(1) + le16(0) + le16(1) + le16(1))
            m.set("NODES", le16(0) + le16(0) + le16(64) + le16(0)
                + le16(10) + le16(-10 & 0xFFFF) + le16(0) + le16(64) + le16(0) + le16(-10 & 0xFFFF) + le16(-1 & 0xFFFF) + le16(64)
                + le16(0x8000) + le16(0x8001))
        }
        return m
    }
}

private func packed(_ bytes: [UInt8]) -> [Int32] {
    stride(from: 0, to: bytes.count, by: 4).map { i in
        var w: UInt32 = 0
        for j in 0..<min(4, bytes.count - i) { w |= UInt32(bytes[i + j]) << (8 * UInt32(j)) }
        return Int32(bitPattern: w)
    }
}
private func unpack(_ cells: ArraySlice<Int32>, count: Int) -> [UInt8] {
    (0..<count).map { UInt8((UInt32(bitPattern: cells[cells.startIndex + $0 / 4]) >> (8 * UInt32($0 % 4))) & 255) }
}
private func f(_ v: Int) -> Int32 { Int32(v) << 16 }

// MARK: decode helpers
private func decode(_ wad: Data, limits: [UInt32: Int] = [:]) -> Result<MapTablesV1, MapTablesFailure> {
    do { return .success(try MapTablesV1.decode(wad: wad, map: "E1M1", limits: limits)) }
    catch let error as MapTablesFailure { return .failure(error) }
    catch { fatalError("unexpected \(error)") }
}
private func tableCells(_ t: MapTablesV1, _ id: Int) -> [Int32] { t.table(id)!.cells }

// MARK: micro-WAD snapshots
private func snapshotTests() {
    let flat = packed((0..<4096).map { UInt8($0 & 255) })
    for withBSP in [false, true] {
        guard case .success(let t) = decode(MicroWAD.make(withBSP: withBSP).data()) else {
            require(false, "micro WAD (bsp \(withBSP)) failed to decode"); return
        }
        require(t.tables.map(\.id) == t.tables.map(\.id).sorted() && t.tables.count == 16, "tables sorted and complete")
        require(tableCells(t, HM_TABLE_VERTICES) == [f(-32), f(16), f(64), f(-8)], "vertices snapshot")
        require(tableCells(t, HM_TABLE_LINEDEFS) == [0, 1, 1, 0, 0, 0, -1], "linedefs snapshot")
        require(tableCells(t, HM_TABLE_SIDEDEFS) == [f(2), f(-3), 1, 0, 1, 0], "sidedefs snapshot (name case, '-', first-wins index)")
        require(tableCells(t, HM_TABLE_SECTORS) == [0, f(128), 0, 0, 160, 9, 3], "sectors snapshot")
        let seg: [Int32] = [0, 1, 0x4000_0000, 0, 0, f(4), 0, -1]
        require(tableCells(t, HM_TABLE_SEGS) == (withBSP ? seg + seg : seg), "segs snapshot")
        require(tableCells(t, HM_TABLE_SUBSECTORS) == (withBSP ? [1, 0, 0, 1, 1, 0] : [1, 0, 0]), "subsectors snapshot")
        require(tableCells(t, HM_TABLE_NODES) == (withBSP
            ? [0, 0, f(64), 0, f(10), f(-10), 0, f(64), 0, f(-10), f(-1), f(64), 0x8000, 0x8001] : []), "nodes snapshot")
        require(tableCells(t, HM_TABLE_THINGS) == [32, -16, 90, 1, 7], "things snapshot")
        require(tableCells(t, HM_TABLE_BLOCKMAP) == [0, 0, 1, 1, 5, 0, -1], "blockmap snapshot")
        require(tableCells(t, HM_TABLE_REJECT) == [1, 1], "reject snapshot")
        require(tableCells(t, HM_TABLE_TEXTURES) == [2, 2, 2, 2, 0, 1, 2, 2, 1, 1, 0, 0, 0, 0, 0, 0],
                "textures snapshot")
        require(tableCells(t, HM_TABLE_PATCH_COLUMNS) ==
                [1, 1, 2, 2, 1, 2, 7, 9, 13, 0, 2, 0xA2A1, -1, 1, 1, 0xB1, -1], "patch-column snapshot")
        require(tableCells(t, HM_TABLE_FLATS) == [1, 4096, 3] + flat, "flats snapshot")
        require(tableCells(t, HM_TABLE_SPRITES) == [1, f(3), f(1), f(4), 5], "sprites snapshot")
        require(tableCells(t, HM_TABLE_PLAYPAL) == [768] + packed((0..<768).map { UInt8(($0 * 7) & 255) }), "playpal snapshot")
        require(tableCells(t, HM_TABLE_COLORMAP) == [34 * 256] + packed((0..<34 * 256).map { UInt8($0 & 255) }), "colormap snapshot")
        require(decode(MicroWAD.make(withBSP: withBSP).data(), limits: [:]).map { $0.manifestJSON() } == .success(t.manifestJSON()),
                "micro manifest is not byte-stable")
    }
    print("map tables: 16-table snapshots for zero-node and BSP micro-WADs, manifests byte-stable")
}

// MARK: capacity boundaries
private func capacityTests() {
    var checked = 0
    for withBSP in [false, true] {
        let wad = MicroWAD.make(withBSP: withBSP).data()
        guard case .success(let base) = decode(wad) else { require(false, "base decode"); return }
        for t in base.tables where !t.cells.isEmpty {
            guard case .success(let exact) = decode(wad, limits: [t.id: t.cells.count]) else {
                require(false, "\(t.name) at capacity must load"); continue
            }
            require(exact.sourceHash != 0 && exact.table(Int(t.id))!.capacity == t.cells.count, "\(t.name) boundary")
            switch decode(wad, limits: [t.id: t.cells.count - 1]) {
            case .failure(.capacityExceeded(let name, _, let capacity)):
                require(name == t.name && capacity == t.cells.count - 1, "\(t.name) capacity report")
            default: require(false, "\(t.name) capacity+1 was not rejected as capacity-exceeded")
            }
            checked += 1
        }
    }
    print("map tables: \(checked) exact-capacity loads and capacity+1 rejections, no partial publication")
}

// MARK: adversarial corpus
private enum Expect { case malformed, unsupported }
private func adversarialTests() {
    func corrupt(_ label: String, _ expect: Expect, withBSP: Bool = false, magic: String = "IWAD",
                 _ edit: (inout MicroWAD) -> Void) {
        var wad = MicroWAD.make(withBSP: withBSP); edit(&wad)
        check(label, expect, wad.data(magic: magic))
    }
    func check(_ label: String, _ expect: Expect, _ data: Data) {
        let outcome = decode(data)
        if ProcessInfo.processInfo.environment["MAP_TABLES_VERBOSE"] != nil, case .failure(let e) = outcome { print("  \(label): \(e)") }
        switch (outcome, expect) {
        case (.failure(.malformed), .malformed), (.failure(.unsupported), .unsupported): break
        case (.failure(let e), _): require(false, "\(label): wrong failure class \(e)")
        case (.success, _): require(false, "\(label): corrupt WAD was published")
        }
    }
    let good = MicroWAD.make(withBSP: true)
    var corpus = 0
    func run(_ label: String, _ expect: Expect = .malformed, withBSP: Bool = true,
             magic: String = "IWAD", _ edit: @escaping (inout MicroWAD) -> Void) {
        corrupt(label, expect, withBSP: withBSP, magic: magic, edit); corpus += 1
    }
    // Container damage.
    run("bad magic", magic: "JWAD") { _ in }
    check("truncated header", .malformed, Data([0x49, 0x57, 0x41, 0x44])); corpus += 1
    let whole = good.data()
    check("truncated directory", .malformed, whole.prefix(whole.count - 9)); corpus += 1
    var bad = Array(whole)   // first directory entry starts at the end of the body
    let dirStart = Int(bad[8]) | Int(bad[9]) << 8 | Int(bad[10]) << 16 | Int(bad[11]) << 24
    for (label, pos, size) in [("lump past EOF", 12, 0x7FFF_FFF0), ("negative length", 12, -1),
                               ("offset+length overflow", 0x7FFF_FFF0, 0x20), ("negative offset", -4, 4)] {
        var d = bad; let at = dirStart
        d.replaceSubrange(at..<at + 8, with: le32(pos & 0xFFFF_FFFF) + le32(size & 0xFFFF_FFFF))
        check(label, .malformed, Data(d)); corpus += 1
    }
    bad = []
    // Record sizes.
    for name in ["THINGS", "LINEDEFS", "SIDEDEFS", "VERTEXES", "SEGS", "SSECTORS", "NODES", "SECTORS"] {
        run("odd \(name) size") { $0.lumps[$0.index(name)].bytes.append(0) }
    }
    // Cross references.
    run("linedef vertex") { $0.lumps[$0.index("LINEDEFS")].bytes[0] = 9 }
    run("linedef sidedef") { $0.lumps[$0.index("LINEDEFS")].bytes[10] = 9 }
    run("sidedef sector") { $0.lumps[$0.index("SIDEDEFS")].bytes[28] = 9 }
    run("seg vertex") { $0.lumps[$0.index("SEGS")].bytes[2] = 9 }
    run("seg linedef") { $0.lumps[$0.index("SEGS")].bytes[6] = 9 }
    run("seg side") { $0.lumps[$0.index("SEGS")].bytes[8] = 2 }
    run("seg missing back side") { $0.lumps[$0.index("LINEDEFS")].bytes[4] = 4 }   // two-sided without side 1
    run("subsector range") { $0.lumps[$0.index("SSECTORS")].bytes[2] = 5 }
    run("subsector empty") { $0.lumps[$0.index("SSECTORS")].bytes[0] = 0 }
    run("node child node") { $0.lumps[$0.index("NODES")].bytes[24] = 7; $0.lumps[$0.index("NODES")].bytes[25] = 0 }
    run("node child subsector") { $0.lumps[$0.index("NODES")].bytes[24] = 9 }
    run("zero nodes, two subsectors") { $0.set("NODES", []) }
    // Blockmap and reject.
    run("blockmap empty") { $0.set("BLOCKMAP", []) }
    run("blockmap odd") { $0.lumps[$0.index("BLOCKMAP")].bytes.append(0) }
    run("blockmap dimensions") { $0.lumps[$0.index("BLOCKMAP")].bytes[6] = 9 }
    run("blockmap offset") { $0.lumps[$0.index("BLOCKMAP")].bytes[8] = 40 }
    run("blockmap unterminated") { $0.lumps[$0.index("BLOCKMAP")].bytes[12] = 0; $0.lumps[$0.index("BLOCKMAP")].bytes[13] = 0 }
    run("blockmap linedef") { $0.lumps[$0.index("BLOCKMAP")].bytes[10] = 9 }
    run("reject short") { $0.set("REJECT", []) }
    // Palette, colormap, patches, textures, flats, sprites.
    for name in ["PLAYPAL", "COLORMAP", "PNAMES", "TEXTURE1", "F_START", "F_END", "S_START", "S_END"] {
        run("missing \(name)") { $0.lumps.remove(at: $0.index(name)) }
    }
    run("playpal partial") { $0.lumps[$0.index("PLAYPAL")].bytes.append(0) }
    run("colormap short") { $0.set("COLORMAP", [UInt8](repeating: 0, count: 33 * 256)) }
    run("missing patch lump") { $0.set("PNAMES", le32(1) + name8("NOPATCH")) }
    run("patch index outside PNAMES") { $0.lumps[$0.index("TEXTURE1")].bytes[12 + 26] = 9 }
    run("texture offset into directory") { $0.lumps[$0.index("TEXTURE1")].bytes[4] = 4 }
    run("texture offset past lump") { $0.lumps[$0.index("TEXTURE1")].bytes[4] = 200 }
    run("texture patch count overrun") { $0.lumps[$0.index("TEXTURE1")].bytes[12 + 20] = 99 }
    run("texture zero width") { $0.lumps[$0.index("TEXTURE1")].bytes[12 + 12] = 0 }
    run("patch truncated") { $0.lumps[$0.index("PATCH1")].bytes.removeLast(9) }
    run("patch column offset") { $0.lumps[$0.index("PATCH1")].bytes[8] = 99 }
    run("patch tiny") { $0.set("PATCH1", [1, 0]) }
    run("sidedef missing texture") { $0.lumps[$0.index("SIDEDEFS")].bytes[4] = 0x51 }
    run("sector flat outside F_START..F_END") { $0.lumps[$0.index("SECTORS")].bytes[4] = 0x51 }
    run("flat size") { $0.set("FLAT1", [UInt8](repeating: 1, count: 100)) }
    run("sprite header") { $0.set("SPRT", [1, 2, 3]) }
    // Map-marker order and format.
    run("marker missing") { $0.lumps.remove(at: $0.index("E1M1")) }
    run("lump order") { $0.lumps[$0.index("SIDEDEFS")].name = "LINEDEFS"; $0.lumps[$0.index("LINEDEFS")].name = "SIDEDEFS" }
    run("truncated map sequence") { $0.lumps.removeLast() }
    run("Hexen BEHAVIOR", .unsupported) { $0.lumps.append(("BEHAVIOR", [0])) }
    for name in ["XYZ", "E1M", "MAP1", "E1M1X"] {
        do { _ = try MapTablesV1.decode(wad: good.data(), map: name); require(false, "map name \(name) accepted") }
        catch is MapTablesFailure { corpus += 1 } catch { require(false, "unexpected error") }
    }
    print("map tables: \(corpus) adversarial cases rejected with deterministic failure classes")
}

// MARK: Freedoom E1M1
func freedoomE1M1() -> MapTablesV1 {
    guard let wad = try? Data(contentsOf: freedoomURL) else { fputs("FAIL: bundled Freedoom missing\n", stderr); exit(1) }
    switch decode(wad) {
    case .success(let t): return t
    case .failure(let e): fputs("FAIL: Freedoom E1M1 did not decode: \(e)\n", stderr); exit(1)
    }
}

// MARK: CPU / Metal indexed reads
private func indexedReadConformance(_ tables: MapTablesV1) {
    guard let device = MTLCreateSystemDefaultDevice() else { require(false, "Metal device unavailable"); return }
    let source = try! String(contentsOf: repoRoot.appendingPathComponent("Sources/Bridge/CircuitExactV1.msl"), encoding: .utf8)
    let options = MTLCompileOptions()
    if #available(macOS 15.0, *) { options.mathMode = .safe } else { options.fastMathEnabled = false }
    let pipeline = try! device.makeComputePipelineState(
        function: try! device.makeLibrary(source: source, options: options).makeFunction(name: "evaluateExactCircuitV1")!)
    var descriptors = [HMExactTableDescriptorV1](), flat = [Int32]()
    for t in tables.tables {
        descriptors.append(HMExactTableDescriptorV1(table_id: t.id, length: UInt32(t.cells.count),
                                                    capacity: UInt32(t.cells.count), offset: UInt32(flat.count), reserved: 0))
        flat += t.cells
    }
    func buffer<T>(_ v: [T]) -> MTLBuffer {
        v.isEmpty ? device.makeBuffer(length: 4, options: .storageModeShared)!
                  : v.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)! }
    }
    let descriptorBuffer = buffer(descriptors), cellBuffer = buffer(flat)
    let queue = device.makeCommandQueue()!

    var reads = 0
    tables.withViews { views in
        for (t, _) in zip(tables.tables, views) where !t.cells.isEmpty {
            let count = t.cells.count
            var indices: [UInt32] = count <= 1500 ? (0..<count).map(UInt32.init)
                : (0..<1500).map { UInt32($0 * (count - 1) / 1499) }
            indices.append(UInt32(count))   // one past the end must report table-bounds
            for pass in 0..<2 {
                let ix = pass == 0 ? Array(indices.dropLast()) : [indices.last!]
                let ops = ix.indices.map { i in
                    HMExactOpV1(opcode: UInt32(HM_EXACT_OP_TABLE_READ_I32), destination: UInt32(ix.count + i),
                                lhs: UInt32(i), rhs: 0, immediate: 0, table_id: t.id, flags: 0, reserved: 0)
                }
                let roots = (0..<ix.count).map { UInt32(ix.count + $0) }
                let expected = pass == 0 ? ix.map { UInt32(bitPattern: t.cells[Int($0)]) } : [UInt32](repeating: 0, count: 1)
                let status = UInt32(pass == 0 ? HM_MODULE_EXACT : HM_MODULE_TABLE_BOUNDS)

                // CPU evaluator.
                var cpuOut = [UInt32](repeating: 0, count: roots.count), produced: UInt32 = 0
                var scratch = [UInt32](repeating: 0, count: ix.count + ops.count)
                let cpuStatus: UInt32 = ops.withUnsafeBufferPointer { o in roots.withUnsafeBufferPointer { r in
                    var p = HMExactProgramV1(abi_version: UInt32(HM_EXACT_PROGRAM_ABI_VERSION),
                        integer_encoding: UInt32(HM_EXACT_INTEGER_ENCODING_V1), input_count: UInt32(ix.count),
                        register_count: UInt32(ix.count + ops.count), operation_count: UInt32(ops.count),
                        operation_capacity: UInt32(ops.count), output_count: UInt32(roots.count),
                        output_capacity: UInt32(roots.count), source_hash: 0,
                        operations: o.baseAddress, output_registers: r.baseAddress)
                    p.source_hash = HM_ExactProgramHashV1(&p)
                    return HM_EvaluateExactProgramV1(&p, ix, UInt32(ix.count), views, UInt32(views.count),
                                                     &scratch, UInt32(scratch.count), &cpuOut, UInt32(cpuOut.count), &produced)
                } }
                require(cpuStatus == status, "\(t.name) CPU indexed-read status \(cpuStatus)")
                if pass == 0 { require(cpuOut == expected, "\(t.name) CPU indexed reads differ from decoded cells") }

                // Metal evaluator.
                var d = HMExactDispatchV1()
                d.abi_version = UInt32(HM_EXACT_PROGRAM_ABI_VERSION); d.integer_encoding = UInt32(HM_EXACT_INTEGER_ENCODING_V1)
                d.input_count = UInt32(ix.count); d.input_capacity = d.input_count
                d.register_count = UInt32(ix.count + ops.count); d.scratch_capacity = d.register_count
                d.operation_count = UInt32(ops.count); d.operation_capacity = d.operation_count
                d.output_count = UInt32(roots.count); d.output_capacity = d.output_count
                d.table_count = UInt32(descriptors.count); d.table_capacity = d.table_count
                d.table_cell_count = UInt32(flat.count); d.table_cell_capacity = d.table_cell_count
                d.output_register_capacity = d.output_count; d.status_capacity = 2
                let statusBuffer = device.makeBuffer(length: 8, options: .storageModeShared)!
                let words = statusBuffer.contents().bindMemory(to: UInt32.self, capacity: 2)
                require(HM_PrepareExactDispatchV1(&d, words, 2) == UInt32(HM_MODULE_EXACT), "\(t.name) Metal dispatch rejected")
                let outBuffer = device.makeBuffer(length: max(4, roots.count * 4), options: .storageModeShared)!
                let command = queue.makeCommandBuffer()!, encoder = command.makeComputeCommandEncoder()!
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(buffer(ix), offset: 0, index: 0); encoder.setBuffer(buffer(ops), offset: 0, index: 1)
                encoder.setBuffer(descriptorBuffer, offset: 0, index: 2); encoder.setBuffer(cellBuffer, offset: 0, index: 3)
                encoder.setBuffer(buffer(roots), offset: 0, index: 4)
                encoder.setBuffer(device.makeBuffer(length: max(4, (ix.count + ops.count) * 4), options: .storageModeShared)!, offset: 0, index: 5)
                encoder.setBuffer(outBuffer, offset: 0, index: 6); encoder.setBuffer(statusBuffer, offset: 0, index: 7)
                encoder.setBuffer(buffer([d]), offset: 0, index: 8)
                encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
                encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
                require(command.status == .completed && words[0] == status, "\(t.name) Metal indexed-read status \(words[0])")
                if pass == 0 {
                    let out = outBuffer.contents().bindMemory(to: UInt32.self, capacity: roots.count)
                    require((0..<roots.count).allSatisfy { out[$0] == expected[$0] && out[$0] == cpuOut[$0] },
                            "\(t.name) Metal indexed reads differ from CPU/decoded cells")
                    reads += ix.count
                }
            }
        }
    }
    print("map tables: \(reads) sampled indexed reads bit-identical across decoded cells, CPU evaluator, and Metal evaluator; one-past-end reads report table-bounds")
}

// MARK: DoomGeneric parity (child process only)
private func engineParity(tables t: MapTablesV1) {
    let scratch = NSTemporaryDirectory() + "neural-doom-map-parity-\(getpid())"
    try? FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
    FileManager.default.changeCurrentDirectoryPath(scratch)
    setenv("HANDWIRED_DOOM_DATA_DIR", scratch, 1)
    require(hmTestBootEngine(freedoomURL.path, "E1M1") == 1, "DoomGeneric did not reach E1M1")
    let capacity = 1 << 23
    var loaded = [Int32](repeating: 0, count: capacity)
    func engine(_ id: Int) -> [Int32] {
        let n = hmTestLoadedTable(UInt32(id), &loaded, Int32(capacity))
        require(n >= 0, "engine table \(id) unavailable")
        return Array(loaded[0..<Int(n)])
    }
    var compared = 0
    for id in [HM_TABLE_VERTICES, HM_TABLE_LINEDEFS, HM_TABLE_SIDEDEFS, HM_TABLE_NODES, HM_TABLE_SUBSECTORS,
               HM_TABLE_SEGS, HM_TABLE_THINGS, HM_TABLE_BLOCKMAP, HM_TABLE_REJECT] {
        let mine = tableCells(t, id)
        var theirs = engine(id)
        if id == HM_TABLE_LINEDEFS {   // ML_MAPPED (0x100) is automap runtime state, not WAD content
            for i in stride(from: 2, to: theirs.count, by: 7) { theirs[i] &= ~0x100 }
        }
        let firstDiff = zip(mine, theirs).enumerated().first { $0.element.0 != $0.element.1 }
        require(mine == theirs, "table \(t.table(id)!.name) differs from DoomGeneric's loaded structures"
                + (firstDiff.map { " (cell \($0.offset): decoded \($0.element.0), engine \($0.element.1); lengths \(mine.count)/\(theirs.count))" } ?? " (lengths \(mine.count)/\(theirs.count))"))
        compared += mine.count
    }
    // Light thinkers (P_SpawnSpecials) clear a light sector's special and animate its level; every other cell must match.
    let lightSpecials: Set<Int32> = [1, 2, 3, 4, 8, 12, 13, 17]
    let mineSectors = tableCells(t, HM_TABLE_SECTORS), theirSectors = engine(HM_TABLE_SECTORS)
    require(mineSectors.count == theirSectors.count, "sector count differs")
    for i in 0..<mineSectors.count {
        let sectorSpecial = mineSectors[i / 7 * 7 + 5]
        let animated = lightSpecials.contains(sectorSpecial)   // light thinkers rewrite level and special
        require(mineSectors[i] == theirSectors[i] || (animated && (i % 7 == 4 || (i % 7 == 5 && theirSectors[i] == 0))),
                "sector cell \(i) differs from DoomGeneric")
    }
    compared += mineSectors.count

    let tex = engine(HM_TABLE_TEXTURES), mineTex = tableCells(t, HM_TABLE_TEXTURES)
    require(Int(tex[0]) == Int(mineTex[0]), "texture count differs")
    for i in 0..<Int(tex[0]) { require(tex[1 + i] == mineTex[2 + 4 * i + 1], "texture \(i) height differs") }

    let fl = engine(HM_TABLE_FLATS), mineFlats = tableCells(t, HM_TABLE_FLATS)
    require(fl[0] == mineFlats[0], "flat count differs")
    var at = 2
    for i in 0..<Int(fl[0]) {
        let size = Int(fl[at]); require(size == Int(mineFlats[1 + 2 * i]), "flat \(i) size differs")
        let first = Int(mineFlats[2 + 2 * i])
        let bytes = unpack(mineFlats[first...], count: size)
        require((0..<size).allSatisfy { Int32(bytes[$0]) == fl[at + 1 + $0] }, "flat \(i) bytes differ")
        at += size + 1
    }
    let sp = engine(HM_TABLE_SPRITES), mineSprites = tableCells(t, HM_TABLE_SPRITES)
    require(sp[0] == mineSprites[0], "sprite lump count differs")
    for i in 0..<Int(sp[0]) {
        require(sp[2 + 3 * i] == mineSprites[1 + 4 * i] && sp[3 + 3 * i] == mineSprites[2 + 4 * i]
                && sp[4 + 3 * i] == mineSprites[3 + 4 * i], "sprite lump \(i) metadata differs")
    }
    for (id, bytes) in [(HM_TABLE_PLAYPAL, 0), (HM_TABLE_COLORMAP, 0)] {
        let mine = tableCells(t, id), theirs = engine(id)
        let ours = unpack(mine[1...], count: theirs.count)
        require(theirs.count <= Int(mine[0]) && ours.map(Int32.init) == theirs, "\(t.table(id)!.name) bytes differ")
        _ = bytes
    }
    // Every patch referenced by a texture: header and every post, pixel for pixel.
    let cols = tableCells(t, HM_TABLE_PATCH_COLUMNS)
    let wad = try! Data(contentsOf: freedoomURL)
    let wadBytes = [UInt8](wad)
    func lumpAt(_ name: String) -> (Int, Int) {
        let dir = Int(wadBytes[8]) | Int(wadBytes[9]) << 8 | Int(wadBytes[10]) << 16 | Int(wadBytes[11]) << 24
        let n = Int(wadBytes[4]) | Int(wadBytes[5]) << 8 | Int(wadBytes[6]) << 16
        for i in stride(from: n - 1, through: 0, by: -1) {
            let e = dir + 16 * i
            let nm = String(decoding: wadBytes[e + 8 ..< e + 16].prefix { $0 != 0 }, as: UTF8.self).uppercased()
            if nm == name { return (Int(wadBytes[e]) | Int(wadBytes[e + 1]) << 8 | Int(wadBytes[e + 2]) << 16 | Int(wadBytes[e + 3]) << 24, i) }
        }
        fatalError("lump \(name)")
    }
    let (pn, _) = lumpAt("PNAMES")
    var patches = 0
    for idx in 0..<Int(cols[0]) where cols[1 + idx * 6] == 1 {
        let nameBytes = Array(wadBytes[pn + 4 + 8 * idx ..< pn + 12 + 8 * idx].prefix { $0 != 0 })
        let name = String(decoding: nameBytes, as: UTF8.self).uppercased()
        var expected = [Int32](repeating: 0, count: 1 << 22)
        let n = hmTestPatchColumns(name, &expected, Int32(expected.count))
        require(n > 0, "engine could not walk patch \(name)")
        let h = 1 + idx * 6
        var ours: [Int32] = [cols[h + 1], cols[h + 2], cols[h + 3], cols[h + 4]]
        for c in 0..<Int(cols[h + 1]) {
            var p = Int(cols[Int(cols[h + 5]) + c])
            while cols[p] != -1 {
                let len = Int(cols[p + 1])
                ours += [cols[p], cols[p + 1]] + unpack(cols[(p + 2)...], count: len).map(Int32.init)
                p += 2 + (len + 3) / 4
            }
            ours.append(-1)
        }
        require(ours == Array(expected[0..<Int(n)]), "patch \(name) columns differ from DoomGeneric")
        patches += 1
    }
    print("map tables: DoomGeneric parity — \(compared) map cells, \(tex[0]) texture heights, \(fl[0]) flats, \(sp[0]) sprite lumps, palette/colormap, \(patches) patches bit-identical")
}

// MARK: entry points
func runMapTablesTests() {
    let args = CommandLine.arguments
    if let at = args.firstIndex(of: "--emit-map-manifest"), at + 1 < args.count {
        try! freedoomE1M1().manifestJSON().write(to: URL(fileURLWithPath: args[at + 1]))
        print("map manifest written"); exit(0)
    }
    if args.contains("--map-tables-engine") {
        engineParity(tables: freedoomE1M1()); exit(0)
    }
    snapshotTests()
    capacityTests()
    adversarialTests()
    let started = DispatchTime.now().uptimeNanoseconds
    let tables = freedoomE1M1()
    let decodeMs = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6
    require((try? Data(contentsOf: mapManifestURL)) == tables.manifestJSON(), "Docs/map-tables-e1m1.json is stale")
    let wad = try! Data(contentsOf: freedoomURL)
    require(tables.wadSHA256 == SHA256.hash(data: wad).map { String(format: "%02x", $0) }.joined()
            && tables.wadSHA256 == "7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d",
            "Freedoom WAD fingerprint changed")
    print("map tables: Freedoom E1M1 decoded in \(String(format: "%.0f", decodeMs)) ms, manifest matches byte-for-byte, source hash \(String(format: "0x%016llx", tables.sourceHash))")
    indexedReadConformance(tables)
    // DoomGeneric boots once per process, so parity runs in a child of this executable.
    let child = Process()
    child.executableURL = URL(fileURLWithPath: args[0].hasPrefix("/") ? args[0] : FileManager.default.currentDirectoryPath + "/" + args[0])
    child.arguments = ["--map-tables-engine"]
    try! child.run(); child.waitUntilExit()
    require(child.terminationStatus == 0, "DoomGeneric parity child failed")
    if args.contains("--map-tables") { exit(0) }
}
