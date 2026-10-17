import CryptoKit
import Foundation

// Decodes one map plus the WAD's render data into immutable MapTablesV1 cells.
// Layouts and capacities are frozen in Sources/Bridge/MapTablesABI.h; table IDs
// come from CircuitIDs.h. Reference decoding order follows p_setup.c / r_data.c.

enum MapTablesFailure: Error, Equatable, CustomStringConvertible {
    case malformed(String)
    case unsupported(String)
    case capacityExceeded(table: String, required: Int, capacity: Int)

    var kind: UInt32 {
        switch self {
        case .malformed: return UInt32(HM_MAP_TABLES_MALFORMED)
        case .unsupported: return UInt32(HM_MAP_TABLES_UNSUPPORTED)
        case .capacityExceeded: return UInt32(HM_MAP_TABLES_CAPACITY_EXCEEDED)
        }
    }
    var description: String {
        switch self {
        case .malformed(let why): return "malformed: \(why)"
        case .unsupported(let why): return "unsupported: \(why)"
        case .capacityExceeded(let table, let required, let capacity):
            return "capacity-exceeded: \(table) needs \(required) cells, capacity \(capacity)"
        }
    }
}

struct MapTableSpec {
    let id: UInt32
    let name: String
    let capacity: Int
}

// Sorted by table ID, which is also the order CircuitModuleV1 requires.
let mapTableSpecs: [MapTableSpec] = [
    MapTableSpec(id: UInt32(HM_TABLE_VERTICES), name: "vertices", capacity: Int(HM_MAP_CAP_VERTICES)),
    MapTableSpec(id: UInt32(HM_TABLE_LINEDEFS), name: "linedefs", capacity: Int(HM_MAP_CAP_LINEDEFS)),
    MapTableSpec(id: UInt32(HM_TABLE_SIDEDEFS), name: "sidedefs", capacity: Int(HM_MAP_CAP_SIDEDEFS)),
    MapTableSpec(id: UInt32(HM_TABLE_SECTORS), name: "sectors", capacity: Int(HM_MAP_CAP_SECTORS)),
    MapTableSpec(id: UInt32(HM_TABLE_NODES), name: "nodes", capacity: Int(HM_MAP_CAP_NODES)),
    MapTableSpec(id: UInt32(HM_TABLE_SUBSECTORS), name: "subsectors", capacity: Int(HM_MAP_CAP_SUBSECTORS)),
    MapTableSpec(id: UInt32(HM_TABLE_SEGS), name: "segs", capacity: Int(HM_MAP_CAP_SEGS)),
    MapTableSpec(id: UInt32(HM_TABLE_THINGS), name: "things", capacity: Int(HM_MAP_CAP_THINGS)),
    MapTableSpec(id: UInt32(HM_TABLE_BLOCKMAP), name: "blockmap", capacity: Int(HM_MAP_CAP_BLOCKMAP)),
    MapTableSpec(id: UInt32(HM_TABLE_REJECT), name: "reject", capacity: Int(HM_MAP_CAP_REJECT)),
    MapTableSpec(id: UInt32(HM_TABLE_TEXTURES), name: "textures", capacity: Int(HM_MAP_CAP_TEXTURES)),
    MapTableSpec(id: UInt32(HM_TABLE_PATCH_COLUMNS), name: "patch-columns", capacity: Int(HM_MAP_CAP_PATCH_COLUMNS)),
    MapTableSpec(id: UInt32(HM_TABLE_FLATS), name: "flats", capacity: Int(HM_MAP_CAP_FLATS)),
    MapTableSpec(id: UInt32(HM_TABLE_SPRITES), name: "sprites", capacity: Int(HM_MAP_CAP_SPRITES)),
    MapTableSpec(id: UInt32(HM_TABLE_PLAYPAL), name: "playpal", capacity: Int(HM_MAP_CAP_PLAYPAL)),
    MapTableSpec(id: UInt32(HM_TABLE_COLORMAP), name: "colormap", capacity: Int(HM_MAP_CAP_COLORMAP))
]

struct MapTable {
    let id: UInt32
    let name: String
    let capacity: Int
    let cells: [Int32]
}

struct MapTablesV1 {
    let schemaVersion = UInt32(HM_MAP_TABLES_SCHEMA_VERSION)
    let mapName: String
    let wadSHA256: String
    let mapSHA256: String
    let sourceHash: UInt64
    let tables: [MapTable]   // sorted by table ID

    func table(_ id: Int) -> MapTable? { tables.first { $0.id == UInt32(id) } }

    // Pointer-free views for CircuitModuleV1; capacity is the allocated length.
    func withViews<R>(_ body: ([HMTableViewV1]) -> R) -> R {
        func go(_ i: Int, _ views: [HMTableViewV1]) -> R {
            if i == tables.count { return body(views) }
            return tables[i].cells.withUnsafeBufferPointer {
                go(i + 1, views + [HMTableViewV1(
                    table_id: tables[i].id, length: UInt32(tables[i].cells.count),
                    capacity: UInt32(tables[i].cells.count), reserved: 0,
                    cells: $0.baseAddress)])
            }
        }
        return go(0, [])
    }

    // Stable byte-for-byte: fixed key order, no timestamps or paths.
    func manifestJSON() -> Data {
        var lines = ["{", "  \"schema\": \(schemaVersion),", "  \"map\": \"\(mapName)\",",
                     "  \"wadSha256\": \"\(wadSHA256)\",", "  \"mapSha256\": \"\(mapSHA256)\",",
                     "  \"sourceHash\": \"\(String(format: "0x%016llx", sourceHash))\",",
                     "  \"tables\": ["]
        for (i, t) in tables.enumerated() {
            var bytes = [UInt8](); bytes.reserveCapacity(t.cells.count * 4)
            for c in t.cells { withUnsafeBytes(of: c.littleEndian) { bytes += $0 } }
            let hash = bytes.withUnsafeBufferPointer { HM_HashBytesV1($0.baseAddress, $0.count) }
            lines.append("    {\"id\": \"\(String(format: "0x%08x", t.id))\", \"name\": \"\(t.name)\", "
                + "\"length\": \(t.cells.count), \"capacity\": \(t.capacity), "
                + "\"cellsHash\": \"\(String(format: "0x%016llx", hash))\"}"
                + (i + 1 < tables.count ? "," : ""))
        }
        lines += ["  ]", "}", ""]
        return Data(lines.joined(separator: "\n").utf8)
    }

    static func containsLump(_ name: String, in wad: Data) throws -> Bool {
        try MapDecoder(wad: wad, map: name, limits: [:]).find(name) != nil
    }

    // limits: table ID -> capacity in cells; missing entries use the ABI default.
    static func decode(wad data: Data, map: String, limits: [UInt32: Int] = [:]) throws -> MapTablesV1 {
        try MapDecoder(wad: data, map: map, limits: limits).run()
    }
}

private func fail(_ why: String) -> MapTablesFailure { .malformed(why) }

private struct Lump { let name: String; let pos: Int; let size: Int }

private struct MapDecoder {
    let data: [UInt8]
    let wadData: Data
    let map: String
    let limits: [UInt32: Int]
    var lumps: [Lump] = []

    init(wad: Data, map: String, limits: [UInt32: Int]) throws {
        wadData = wad; data = [UInt8](wad); self.map = map.uppercased(); self.limits = limits
        guard data.count >= 12 else { throw fail("WAD shorter than its header") }
        let magic = String(decoding: data[0..<4], as: UTF8.self)
        guard magic == "IWAD" || magic == "PWAD" else { throw fail("not an IWAD or PWAD") }
        let count = Int(i32(data, 4)), table = Int(i32(data, 8))
        guard count >= 0, table >= 12, table + count * 16 <= data.count else {
            throw fail("WAD directory is truncated or out of range")
        }
        for i in 0..<count {
            let at = table + i * 16
            let pos = Int(i32(data, at)), size = Int(i32(data, at + 4))
            guard pos >= 0, size >= 0, pos + size <= data.count else {
                throw fail("lump \(i) has an offset or length outside the file")
            }
            lumps.append(Lump(name: nameField(data, at + 8), pos: pos, size: size))
        }
    }

    func capacity(_ id: UInt32) -> Int {
        limits[id] ?? mapTableSpecs.first { $0.id == id }!.capacity
    }
    func spec(_ id: Int) -> MapTableSpec { mapTableSpecs.first { $0.id == UInt32(id) }! }
    // W_CheckNumForName scans backwards, so the last lump of a name wins.
    func find(_ name: String) -> Int? { lumps.lastIndex { $0.name == name } }
    func need(_ name: String) throws -> Int {
        guard let i = find(name) else { throw fail("missing \(name) lump") }
        return i
    }
    func bytes(_ i: Int) -> ArraySlice<UInt8> { data[lumps[i].pos ..< lumps[i].pos + lumps[i].size] }

    // Rejects before building when the final length is already known.
    func check(_ id: Int, cells: Int) throws {
        let cap = capacity(UInt32(id))
        if cells > cap { throw MapTablesFailure.capacityExceeded(table: spec(id).name, required: cells, capacity: cap) }
    }
    // Incremental check for tables whose length depends on decoded content.
    func grow(_ id: Int, _ cells: [Int32], adding n: Int) throws {
        try check(id, cells: cells.count + n)
    }

    func records(_ lump: Int, size: Int, _ what: String) throws -> Int {
        guard lumps[lump].size % size == 0 else { throw fail("\(what) lump size is not a multiple of \(size)") }
        return lumps[lump].size / size
    }

    func run() throws -> MapTablesV1 {
        // Map marker and Vanilla lump order.
        let c = Array(map.utf8)
        func digit(_ b: UInt8) -> Bool { b >= 48 && b <= 57 }
        let isEpisode = c.count == 4 && c[0] == 69 && digit(c[1]) && c[2] == 77 && digit(c[3])   // ExMy
        let isMAP = c.count == 5 && map.hasPrefix("MAP") && digit(c[3]) && digit(c[4])
        guard isEpisode || isMAP else { throw fail("\(map) is not an ExMy or MAPxx map name") }
        guard let marker = find(map) else { throw fail("map marker \(map) not found") }
        let order = ["THINGS", "LINEDEFS", "SIDEDEFS", "VERTEXES", "SEGS", "SSECTORS", "NODES",
                     "SECTORS", "REJECT", "BLOCKMAP"]
        guard marker + order.count < lumps.count else { throw fail("map \(map) lump sequence is truncated") }
        for (k, name) in order.enumerated() where lumps[marker + 1 + k].name != name {
            throw fail("map \(map) lump \(k + 1) is \(lumps[marker + 1 + k].name), expected \(name)")
        }
        if marker + order.count + 1 < lumps.count, lumps[marker + order.count + 1].name == "BEHAVIOR" {
            throw MapTablesFailure.unsupported("Hexen-format map \(map) (BEHAVIOR lump)")
        }
        let L = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, marker + 1 + $0) })

        var out: [Int: [Int32]] = [:]

        // ---- render data (needed to resolve sidedef/sector names)
        let texNames = try decodeTextures(&out)
        let flatBase = try decodeFlats(&out)
        try decodeSprites(&out)
        try decodePalette(&out)

        func texture(_ field: ArraySlice<UInt8>) throws -> Int32 {
            let name = nameField(Array(field), 0)
            if field.first == UInt8(ascii: "-") { return 0 }
            guard let i = texNames[name] else { throw fail("sidedef texture \(name) not found") }
            return Int32(i)
        }
        func flat(_ field: ArraySlice<UInt8>) throws -> Int32 {
            let name = nameField(Array(field), 0)
            guard let lump = find(name), lump >= flatBase.first, lump <= flatBase.last else {
                throw fail("sector flat \(name) is not between F_START and F_END")
            }
            return Int32(lump - flatBase.first)
        }

        // ---- vertices
        let nv = try records(L["VERTEXES"]!, size: 4, "VERTEXES")
        try check(HM_TABLE_VERTICES, cells: nv * 2)
        var v = [Int32](); v.reserveCapacity(nv * 2)
        for k in 0..<nv { let b = lumps[L["VERTEXES"]!].pos + k * 4
            v += [fixed(i16(data, b)), fixed(i16(data, b + 2))] }
        out[HM_TABLE_VERTICES] = v

        // ---- sectors
        let ns = try records(L["SECTORS"]!, size: 26, "SECTORS")
        try check(HM_TABLE_SECTORS, cells: ns * 7)
        var sec = [Int32]()
        for k in 0..<ns {
            let b = lumps[L["SECTORS"]!].pos + k * 26
            sec += [fixed(i16(data, b)), fixed(i16(data, b + 2)),
                    try flat(data[b + 4 ..< b + 12]), try flat(data[b + 12 ..< b + 20]),
                    Int32(i16(data, b + 20)), Int32(i16(data, b + 22)), Int32(i16(data, b + 24))]
        }
        out[HM_TABLE_SECTORS] = sec

        // ---- sidedefs
        let nsd = try records(L["SIDEDEFS"]!, size: 30, "SIDEDEFS")
        try check(HM_TABLE_SIDEDEFS, cells: nsd * 6)
        var sides = [Int32]()
        for k in 0..<nsd {
            let b = lumps[L["SIDEDEFS"]!].pos + k * 30
            let sector = Int(i16(data, b + 28))
            guard sector >= 0, sector < ns else { throw fail("sidedef \(k) references sector \(sector)") }
            sides += [fixed(i16(data, b)), fixed(i16(data, b + 2)),
                      try texture(data[b + 4 ..< b + 12]), try texture(data[b + 12 ..< b + 20]),
                      try texture(data[b + 20 ..< b + 28]), Int32(sector)]
        }
        out[HM_TABLE_SIDEDEFS] = sides

        // ---- linedefs
        let nl = try records(L["LINEDEFS"]!, size: 14, "LINEDEFS")
        try check(HM_TABLE_LINEDEFS, cells: nl * 7)
        var lines = [Int32]()
        for k in 0..<nl {
            let b = lumps[L["LINEDEFS"]!].pos + k * 14
            let v1 = Int(u16(data, b)), v2 = Int(u16(data, b + 2))
            guard v1 < nv, v2 < nv else { throw fail("linedef \(k) references a missing vertex") }
            var side: [Int32] = []
            for s in 0..<2 {
                let raw = u16(data, b + 10 + 2 * s)
                if raw == 0xFFFF { side.append(-1); continue }
                guard Int(raw) < nsd else { throw fail("linedef \(k) references sidedef \(raw)") }
                side.append(Int32(raw))
            }
            lines += [Int32(v1), Int32(v2), Int32(i16(data, b + 4)), Int32(i16(data, b + 6)),
                      Int32(i16(data, b + 8)), side[0], side[1]]
        }
        out[HM_TABLE_LINEDEFS] = lines

        // ---- segs
        let nseg = try records(L["SEGS"]!, size: 12, "SEGS")
        try check(HM_TABLE_SEGS, cells: nseg * 8)
        var segs = [Int32]()
        for k in 0..<nseg {
            let b = lumps[L["SEGS"]!].pos + k * 12
            let v1 = Int(u16(data, b)), v2 = Int(u16(data, b + 2))
            let line = Int(u16(data, b + 6)), side = Int(u16(data, b + 8))
            guard v1 < nv, v2 < nv else { throw fail("seg \(k) references a missing vertex") }
            guard line < nl, side < 2 else { throw fail("seg \(k) references linedef \(line) side \(side)") }
            let l = line * 7
            let front = lines[l + 5 + side]
            guard front >= 0 else { throw fail("seg \(k) uses a missing sidedef") }
            var back: Int32 = -1
            if lines[l + 2] & 4 != 0 {
                let other = lines[l + 5 + (side ^ 1)]
                guard other >= 0 else { throw fail("two-sided seg \(k) lacks its back sidedef") }
                back = sides[Int(other) * 6 + 5]
            }
            segs += [Int32(v1), Int32(v2), Int32(bitPattern: UInt32(u16(data, b + 4)) << 16),
                     Int32(line), Int32(side), fixed(i16(data, b + 10)),
                     sides[Int(front) * 6 + 5], back]
        }
        out[HM_TABLE_SEGS] = segs

        // ---- subsectors
        let nss = try records(L["SSECTORS"]!, size: 4, "SSECTORS")
        guard nss > 0, nseg > 0 else { throw fail("map has no subsectors or segs") }
        try check(HM_TABLE_SUBSECTORS, cells: nss * 3)
        var subs = [Int32]()
        for k in 0..<nss {
            let b = lumps[L["SSECTORS"]!].pos + k * 4
            let count = Int(i16(data, b)), first = Int(i16(data, b + 2))
            guard count > 0, first >= 0, first + count <= nseg else {
                throw fail("subsector \(k) has seg range \(first)+\(count) outside 0..<\(nseg)")
            }
            subs += [Int32(count), Int32(first), segs[first * 8 + 6]]
        }
        out[HM_TABLE_SUBSECTORS] = subs

        // ---- nodes (zero nodes is legal for a single-subsector map)
        let nn = try records(L["NODES"]!, size: 28, "NODES")
        guard nn > 0 || nss == 1 else { throw fail("map has \(nss) subsectors but no BSP nodes") }
        try check(HM_TABLE_NODES, cells: nn * 14)
        var nodes = [Int32]()
        for k in 0..<nn {
            let b = lumps[L["NODES"]!].pos + k * 28
            for j in 0..<12 { nodes.append(fixed(i16(data, b + 2 * j))) }   // x y dx dy bbox[2][4]
            for j in 0..<2 {
                let child = Int(u16(data, b + 24 + 2 * j))
                if child & 0x8000 != 0 {
                    guard child & 0x7FFF < nss else { throw fail("node \(k) child names subsector \(child & 0x7FFF)") }
                } else {
                    guard child < nn else { throw fail("node \(k) child names node \(child)") }
                }
                nodes.append(Int32(child))
            }
        }
        out[HM_TABLE_NODES] = nodes

        // ---- things
        let nt = try records(L["THINGS"]!, size: 10, "THINGS")
        try check(HM_TABLE_THINGS, cells: nt * 5)
        var things = [Int32]()
        for k in 0..<nt {
            let b = lumps[L["THINGS"]!].pos + k * 10
            for j in 0..<5 { things.append(Int32(i16(data, b + 2 * j))) }
        }
        out[HM_TABLE_THINGS] = things

        // ---- blockmap
        let bm = lumps[L["BLOCKMAP"]!]
        guard bm.size >= 8, bm.size % 2 == 0 else { throw fail("BLOCKMAP is missing its header or has odd length") }
        try check(HM_TABLE_BLOCKMAP, cells: bm.size / 2)
        let words = (0..<bm.size / 2).map { Int32(i16(data, bm.pos + 2 * $0)) }
        let bw = Int(words[2]), bh = Int(words[3])
        guard bw > 0, bh > 0, 4 + bw * bh <= words.count else { throw fail("BLOCKMAP dimensions \(bw)x\(bh) exceed the lump") }
        for cell in 0..<bw * bh {
            var at = Int(words[4 + cell])
            guard at >= 4 + bw * bh, at < words.count else { throw fail("BLOCKMAP block \(cell) offset is out of range") }
            while words[at] != -1 {
                guard words[at] >= 0, Int(words[at]) < nl else { throw fail("BLOCKMAP block \(cell) names linedef \(words[at])") }
                at += 1
                guard at < words.count else { throw fail("BLOCKMAP block \(cell) list is unterminated") }
            }
        }
        out[HM_TABLE_BLOCKMAP] = words

        // ---- reject: n*n bits, row-major
        let rj = lumps[L["REJECT"]!]
        guard rj.size >= (ns * ns + 7) / 8, rj.size > 0 else { throw fail("REJECT is shorter than \(ns) sectors require") }
        try check(HM_TABLE_REJECT, cells: 1 + (rj.size + 3) / 4)
        out[HM_TABLE_REJECT] = [Int32(rj.size)] + pack(bytes(L["REJECT"]!))

        // ---- fingerprints and canonical hash
        var mapBytes = [UInt8]()
        for name in [map] + order {
            let lump = lumps[name == map ? marker : L[name]!]
            var field = Array(name.utf8); field += [UInt8](repeating: 0, count: 8 - field.count)
            mapBytes += field
            withUnsafeBytes(of: UInt32(lump.size).littleEndian) { mapBytes += $0 }
            mapBytes += bytes(name == map ? marker : L[name]!)
        }
        let tables = mapTableSpecs.map { s in
            MapTable(id: s.id, name: s.name, capacity: capacity(s.id), cells: out[Int(s.id)]!)
        }
        var canonical = [UInt8]()
        withUnsafeBytes(of: UInt32(HM_MAP_TABLES_SCHEMA_VERSION).littleEndian) { canonical += $0 }
        for t in tables {
            for word in [t.id, UInt32(t.cells.count), UInt32(t.capacity)] {
                withUnsafeBytes(of: word.littleEndian) { canonical += $0 }
            }
            for c in t.cells { withUnsafeBytes(of: c.littleEndian) { canonical += $0 } }
        }
        return MapTablesV1(
            mapName: map, wadSHA256: hex(SHA256.hash(data: wadData)),
            mapSHA256: hex(SHA256.hash(data: mapBytes)),
            sourceHash: canonical.withUnsafeBufferPointer { HM_HashBytesV1($0.baseAddress, $0.count) },
            tables: tables)
    }

    // TEXTURES: [count, patchRefCount, count x (w, h, firstRef, refCount), refs x (ox, oy, patch)]
    // PATCH_COLUMNS: [patchCount, patchCount x (present, w, h, left, top, columnStart),
    //   per present patch: w column starts, then each column's posts
    //   (topdelta, length, packed pixels...) ended by -1]
    func decodeTextures(_ out: inout [Int: [Int32]]) throws -> [String: Int] {
        let pn = lumps[try need("PNAMES")]
        guard pn.size >= 4 else { throw fail("PNAMES is truncated") }
        let patchCount = Int(i32(data, pn.pos))
        guard patchCount >= 0, 4 + patchCount * 8 <= pn.size else { throw fail("PNAMES count exceeds its lump") }
        let patchLump: [Int?] = (0..<patchCount).map { find(nameField(data, pn.pos + 4 + 8 * $0)) }

        var defs: [(w: Int, h: Int, patches: [(Int, Int, Int)])] = []
        var names: [String: Int] = [:]
        var refs = 0
        var sources = [try need("TEXTURE1")]
        if let t2 = find("TEXTURE2") { sources.append(t2) }
        for src in sources {
            let lump = lumps[src]
            guard lump.size >= 4 else { throw fail("texture lump is truncated") }
            let count = Int(i32(data, lump.pos))
            guard count >= 0, 4 + count * 4 <= lump.size else { throw fail("texture directory exceeds its lump") }
            for k in 0..<count {
                let off = Int(i32(data, lump.pos + 4 + 4 * k))
                guard off >= 4 + count * 4, off + 22 <= lump.size else {
                    throw fail("texture directory entry \(k) points outside its definition area")
                }
                let b = lump.pos + off
                let w = Int(i16(data, b + 12)), h = Int(i16(data, b + 14)), pc = Int(i16(data, b + 20))
                guard w > 0, h > 0, pc >= 0, off + 22 + pc * 10 <= lump.size else {
                    throw fail("texture \(nameField(data, b)) has invalid size or patch count")
                }
                var patches: [(Int, Int, Int)] = []
                for j in 0..<pc {
                    let p = b + 22 + 10 * j
                    let idx = Int(i16(data, p + 4))
                    guard idx >= 0, idx < patchCount else { throw fail("texture \(nameField(data, b)) uses patch index \(idx)") }
                    guard patchLump[idx] != nil else { throw fail("missing patch in texture \(nameField(data, b))") }
                    patches.append((Int(i16(data, p)), Int(i16(data, p + 2)), idx))
                }
                let name = nameField(data, b)
                if names[name] == nil { names[name] = defs.count }   // earlier entry wins
                defs.append((w, h, patches)); refs += pc
            }
        }
        let texCells = 2 + defs.count * 4 + refs * 3
        try check(HM_TABLE_TEXTURES, cells: texCells)
        var tex: [Int32] = [Int32(defs.count), Int32(refs)]
        var firstRef = 0
        for d in defs { tex += [Int32(d.w), Int32(d.h), Int32(firstRef), Int32(d.patches.count)]; firstRef += d.patches.count }
        for d in defs { for p in d.patches { tex += [Int32(p.0), Int32(p.1), Int32(p.2)] } }
        out[HM_TABLE_TEXTURES] = tex

        let used = Set(defs.flatMap { $0.patches.map { $0.2 } })
        let headerCells = 1 + patchCount * 6
        try check(HM_TABLE_PATCH_COLUMNS, cells: headerCells)
        var cols = [Int32](repeating: 0, count: headerCells)
        cols[0] = Int32(patchCount)
        for idx in 0..<patchCount where used.contains(idx) {
            let lump = lumps[patchLump[idx]!]
            let b = lump.pos
            guard lump.size >= 8 else { throw fail("patch \(idx) is shorter than its header") }
            let w = Int(u16(data, b)), h = Int(u16(data, b + 2))
            let tableEnd = 8 + 4 * w
            guard w > 0, tableEnd <= lump.size else { throw fail("patch \(idx) column table exceeds its lump") }
            let at = 1 + idx * 6
            cols[at] = 1; cols[at + 1] = Int32(w); cols[at + 2] = Int32(h)
            cols[at + 3] = Int32(i16(data, b + 4)); cols[at + 4] = Int32(i16(data, b + 6))
            cols[at + 5] = Int32(cols.count)
            try grow(HM_TABLE_PATCH_COLUMNS, cols, adding: w)
            let startsAt = cols.count
            cols += [Int32](repeating: 0, count: w)
            var memo: [Int: Int32] = [:]
            for c in 0..<w {
                let ofs = Int(u32(data, b + 8 + 4 * c))
                if let done = memo[ofs] { cols[startsAt + c] = done; continue }
                guard ofs >= tableEnd, ofs < lump.size else { throw fail("patch \(idx) column \(c) offset is out of range") }
                cols[startsAt + c] = Int32(cols.count); memo[ofs] = Int32(cols.count)
                var p = ofs
                while true {
                    guard p < lump.size else { throw fail("patch \(idx) column \(c) is unterminated") }
                    let top = Int(data[b + p])
                    if top == 0xFF { break }
                    guard p + 3 <= lump.size else { throw fail("patch \(idx) column \(c) post header is truncated") }
                    let len = Int(data[b + p + 1])
                    guard p + 4 + len <= lump.size else { throw fail("patch \(idx) column \(c) post exceeds its lump") }
                    try grow(HM_TABLE_PATCH_COLUMNS, cols, adding: 2 + (len + 3) / 4 + 1)
                    cols += [Int32(top), Int32(len)] + pack(data[b + p + 3 ..< b + p + 3 + len])
                    p += len + 4
                }
                cols.append(-1)
            }
        }
        out[HM_TABLE_PATCH_COLUMNS] = cols
        return names
    }

    // FLATS: [count, count x (byteLength, firstCell), packed 64x64 data].
    // Every lump between F_START and F_END keeps its Vanilla index, markers included.
    func decodeFlats(_ out: inout [Int: [Int32]]) throws -> (first: Int, last: Int) {
        let first = try need("F_START") + 1, last = try need("F_END") - 1
        guard last >= first else { throw fail("F_END precedes F_START") }
        let count = last - first + 1
        try check(HM_TABLE_FLATS, cells: 1 + count * 2)
        var flats: [Int32] = [Int32(count)]
        var body: [Int32] = []
        for i in first...last {
            let size = lumps[i].size
            guard size == 0 || size == 4096 else { throw fail("flat \(lumps[i].name) is \(size) bytes, expected 4096") }
            try check(HM_TABLE_FLATS, cells: 1 + count * 2 + body.count + size / 4)
            flats += [Int32(size), Int32(1 + count * 2 + body.count)]
            body += pack(bytes(i))
        }
        out[HM_TABLE_FLATS] = flats + body
        return (first, last)
    }

    // SPRITES: [count, count x (width, leftoffset, topoffset fixed 16.16, height)].
    func decodeSprites(_ out: inout [Int: [Int32]]) throws {
        let first = try need("S_START") + 1, last = try need("S_END") - 1
        guard last >= first else { throw fail("S_END precedes S_START") }
        try check(HM_TABLE_SPRITES, cells: 1 + (last - first + 1) * 4)
        var cells: [Int32] = [Int32(last - first + 1)]
        for i in first...last {
            guard lumps[i].size >= 8 else { throw fail("sprite lump \(lumps[i].name) is shorter than a patch header") }
            let b = lumps[i].pos
            cells += [fixed(i16(data, b)), fixed(i16(data, b + 4)), fixed(i16(data, b + 6)), Int32(i16(data, b + 2))]
        }
        out[HM_TABLE_SPRITES] = cells
    }

    func decodePalette(_ out: inout [Int: [Int32]]) throws {
        let pal = try need("PLAYPAL"), cmap = try need("COLORMAP")
        guard lumps[pal].size >= 768, lumps[pal].size % 768 == 0 else { throw fail("PLAYPAL is not whole 768-byte palettes") }
        guard lumps[cmap].size >= 34 * 256, lumps[cmap].size % 256 == 0 else { throw fail("COLORMAP is not whole 256-byte maps (34 required)") }
        try check(HM_TABLE_PLAYPAL, cells: 1 + lumps[pal].size / 4)
        try check(HM_TABLE_COLORMAP, cells: 1 + lumps[cmap].size / 4)
        out[HM_TABLE_PLAYPAL] = [Int32(lumps[pal].size)] + pack(bytes(pal))
        out[HM_TABLE_COLORMAP] = [Int32(lumps[cmap].size)] + pack(bytes(cmap))
    }
}

// MARK: little-endian readers and helpers
private func u16(_ d: [UInt8], _ at: Int) -> Int { Int(d[at]) | Int(d[at + 1]) << 8 }
private func i16(_ d: [UInt8], _ at: Int) -> Int { Int(Int16(truncatingIfNeeded: u16(d, at))) }
private func u32(_ d: [UInt8], _ at: Int) -> UInt32 {
    UInt32(d[at]) | UInt32(d[at + 1]) << 8 | UInt32(d[at + 2]) << 16 | UInt32(d[at + 3]) << 24
}
private func i32(_ d: [UInt8], _ at: Int) -> Int32 { Int32(bitPattern: u32(d, at)) }
private func fixed(_ v: Int) -> Int32 { Int32(v) << 16 }
private func nameField(_ d: [UInt8], _ at: Int) -> String {
    var s = [UInt8]()
    for i in 0..<8 { let c = d[at + i]; if c == 0 { break }; s.append(c >= 97 && c <= 122 ? c - 32 : c) }
    return String(decoding: s, as: UTF8.self)
}
private func pack(_ b: ArraySlice<UInt8>) -> [Int32] {
    let a = Array(b)
    return stride(from: 0, to: a.count, by: 4).map { i in
        var w: UInt32 = 0
        for j in 0..<min(4, a.count - i) { w |= UInt32(a[i + j]) << (8 * UInt32(j)) }
        return Int32(bitPattern: w)
    }
}
private func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
    digest.map { String(format: "%02x", $0) }.joined()
}
