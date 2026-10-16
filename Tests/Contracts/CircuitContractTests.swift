import Foundation
import Metal

private let fixtureModule = UInt32(HM_MODULE_MOVEMENT_COLLISION)
private let fixtureSourceHash: UInt64 = 0x0123_4567_89ab_cdef

private func makeEvent(phase: UInt32, id: UInt32, emitter: UInt32,
                       sequence: UInt32, firstPayload: Int32) -> HMModuleEventV1 {
    var event = HMModuleEventV1()
    event.phase = phase
    event.event_id = id
    event.emitter_slot = emitter
    event.local_sequence = sequence
    event.source_id = 7
    event.target_id = 11
    event.payload_count = 1
    event.flags = 0
    event.payload.0 = firstPayload
    return event
}

private func makeDelta(array: UInt32, element: UInt32, cell: UInt32,
                       before: Int32, after: Int32) -> HMStateDeltaV1 {
    var delta = HMStateDeltaV1()
    delta.array_id = array
    delta.element_index = element
    delta.cell_id = cell
    delta.before = before
    delta.after = after
    return delta
}

private func withContractFixture(
    _ body: (inout HMModuleInputV1, inout HMModuleResultV1) -> Void
) {
    var inputs: [Int32] = [.min, .max, 0]
    var state: [Int32] = [0x1234_5678, 0]
    var tableCells: [Int32] = [7, -9]
    var inputEvents = [
        makeEvent(phase: UInt32(HM_PHASE_MOVEMENT_COLLISION),
                  id: UInt32(HM_EVENT_LINE_CROSSED), emitter: 3,
                  sequence: 4, firstPayload: -5),
        HMModuleEventV1()
    ]
    var outputs: [Int32] = [.min, .max, 0]
    var deltas = [
        makeDelta(array: UInt32(HM_WORLD_ARRAY_PLAYERS), element: 0,
                  cell: UInt32(HM_PLAYER_X), before: 10, after: 12),
        makeDelta(array: UInt32(HM_WORLD_ARRAY_PLAYERS), element: 0,
                  cell: UInt32(HM_PLAYER_Y), before: 20, after: 21)
    ]
    var outputEvents = [
        makeEvent(phase: UInt32(HM_PHASE_INTERACTIONS_COMBAT),
                  id: UInt32(HM_EVENT_SOUND), emitter: 9,
                  sequence: 0, firstPayload: 3),
        makeEvent(phase: UInt32(HM_PHASE_INTERACTIONS_COMBAT),
                  id: UInt32(HM_EVENT_MESSAGE), emitter: 9,
                  sequence: 1, firstPayload: 4)
    ]
    let inputCapacity = UInt32(inputs.count)
    let stateCapacity = UInt32(state.count)
    let tableCapacity: UInt32 = 1
    let inputEventCapacity = UInt32(inputEvents.count)
    let outputCapacity = UInt32(outputs.count)
    let deltaCapacity = UInt32(deltas.count)
    let eventCapacity = UInt32(outputEvents.count)
    inputs.withUnsafeMutableBufferPointer { inputBuffer in
        state.withUnsafeMutableBufferPointer { stateBuffer in
            tableCells.withUnsafeMutableBufferPointer { cellBuffer in
                var tables = [HMTableViewV1(
                    table_id: UInt32(HM_TABLE_VERTICES), length: 2, capacity: 2,
                    reserved: 0, cells: UnsafePointer(cellBuffer.baseAddress!)
                )]
                tables.withUnsafeMutableBufferPointer { tableBuffer in
                    inputEvents.withUnsafeMutableBufferPointer { inputEventBuffer in
                        outputs.withUnsafeMutableBufferPointer { outputBuffer in
                            deltas.withUnsafeMutableBufferPointer { deltaBuffer in
                                outputEvents.withUnsafeMutableBufferPointer { outputEventBuffer in
                                    var input = HMModuleInputV1()
                                    input.abi_version = UInt32(HM_CIRCUIT_MODULE_ABI_VERSION)
                                    input.program_version = 1
                                    input.integer_encoding = UInt32(HM_EXACT_INTEGER_ENCODING_V1)
                                    input.module_id = fixtureModule
                                    input.tic_id = 0x0102_0304_0506_0708
                                    input.source_hash = fixtureSourceHash
                                    input.input_count = 2
                                    input.input_capacity = inputCapacity
                                    input.state_count = 1
                                    input.state_capacity = stateCapacity
                                    input.table_count = 1
                                    input.table_capacity = tableCapacity
                                    input.input_event_count = 1
                                    input.input_event_capacity = inputEventCapacity
                                    input.output_count = 2
                                    input.output_capacity = outputCapacity
                                    input.state_delta_capacity = deltaCapacity
                                    input.event_capacity = eventCapacity
                                    input.inputs = UnsafePointer(inputBuffer.baseAddress!)
                                    input.state_before = UnsafePointer(stateBuffer.baseAddress!)
                                    input.tables = UnsafePointer(tableBuffer.baseAddress!)
                                    input.input_events = UnsafePointer(inputEventBuffer.baseAddress!)

                                    var result = HMModuleResultV1()
                                    result.abi_version = input.abi_version
                                    result.module_id = input.module_id
                                    result.tic_id = input.tic_id
                                    result.source_hash = input.source_hash
                                    result.status = UInt32(HM_MODULE_EXACT)
                                    result.output_count = 2
                                    result.output_capacity = input.output_capacity
                                    result.state_delta_count = deltaCapacity
                                    result.state_delta_capacity = input.state_delta_capacity
                                    result.event_count = eventCapacity
                                    result.event_capacity = input.event_capacity
                                    result.outputs = outputBuffer.baseAddress
                                    result.state_deltas = deltaBuffer.baseAddress
                                    result.events = outputEventBuffer.baseAddress
                                    body(&input, &result)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private func expectInputRejection(
    _ label: String, _ expected: UInt32,
    _ mutate: (inout HMModuleInputV1) -> Void
) {
    withContractFixture { input, _ in
        mutate(&input)
        require(HM_ValidateModuleInputV1(&input, fixtureModule, fixtureSourceHash) == expected,
                "contract input rejection: \(label)")
    }
}

private func expectResultRejection(
    _ label: String, _ expected: UInt32,
    _ mutate: (inout HMModuleResultV1) -> Void
) {
    withContractFixture { input, result in
        mutate(&result)
        let status = HM_FinalizeModuleResultV1(
            &input, &result, fixtureModule, fixtureSourceHash)
        require(status == expected, "contract result rejection: \(label)")
        require(result.status == expected && result.output_count == 0 &&
                result.state_delta_count == 0 && result.event_count == 0,
                "contract rejection was not an empty commit: \(label)")
    }
}

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

private func canonicalFixture() {
    let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("circuit-module-v1-fixture.json")
    guard let data = try? Data(contentsOf: fixtureURL),
          let fixture = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let expectedInputHex = fixture["inputHex"] as? String,
          let expectedInputHash = fixture["inputFNV1a64"] as? String,
          let expectedResultHex = fixture["resultHex"] as? String,
          let expectedResultHash = fixture["resultFNV1a64"] as? String else {
        require(false, "canonical CircuitModuleV1 fixture missing")
        return
    }
    withContractFixture { input, result in
        require(HM_ValidateModuleInputV1(
            &input, fixtureModule, fixtureSourceHash) == UInt32(HM_MODULE_EXACT),
            "canonical input did not validate")
        require(HM_FinalizeModuleResultV1(
            &input, &result, fixtureModule, fixtureSourceHash) == UInt32(HM_MODULE_EXACT),
            "canonical result did not validate")

        let inputSize = HM_CanonicalModuleInputSizeV1(&input)
        var inputBytes = [UInt8](repeating: 0, count: inputSize)
        let inputWritten = inputBytes.withUnsafeMutableBufferPointer {
            HM_SerializeModuleInputV1(&input, $0.baseAddress, $0.count)
        }
        require(inputWritten == inputBytes.count && hex(inputBytes) == expectedInputHex,
                "canonical input serialization changed")
        require(String(format: "%016llx", HM_HashBytesV1(inputBytes, inputBytes.count)) == expectedInputHash,
                "canonical input hash changed")

        let resultSize = HM_CanonicalModuleResultSizeV1(&result)
        var resultBytes = [UInt8](repeating: 0, count: resultSize)
        let resultWritten = resultBytes.withUnsafeMutableBufferPointer {
            HM_SerializeModuleResultV1(&result, $0.baseAddress, $0.count)
        }
        require(resultWritten == resultBytes.count && hex(resultBytes) == expectedResultHex,
                "canonical result serialization changed")
        require(String(format: "%016llx", HM_HashBytesV1(resultBytes, resultBytes.count)) == expectedResultHash,
                "canonical result hash changed")
    }
}

private func numericRegistryFixture() {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Docs/contracts/registry-v1.json")
    let data = try! Data(contentsOf: url)
    let root = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    func check(_ section: String, _ expected: [String: UInt32]) {
        let actual = root[section] as! [String: Any]
        require(actual.count == expected.count, "registry section count: \(section)")
        for (name, value) in expected {
            require((actual[name] as? NSNumber)?.uint32Value == value,
                    "registry value: \(section).\(name)")
        }
    }
    check("statuses", [
        "exact": UInt32(HM_MODULE_EXACT),
        "unsupported-domain": UInt32(HM_MODULE_UNSUPPORTED_DOMAIN),
        "capacity-exceeded": UInt32(HM_MODULE_CAPACITY_EXCEEDED),
        "execution-error": UInt32(HM_MODULE_EXECUTION_ERROR),
        "parity-mismatch": UInt32(HM_MODULE_PARITY_MISMATCH),
        "invalid-abi": UInt32(HM_MODULE_INVALID_ABI),
        "unknown-id": UInt32(HM_MODULE_UNKNOWN_ID),
        "source-hash-mismatch": UInt32(HM_MODULE_SOURCE_HASH_MISMATCH),
        "malformed-span": UInt32(HM_MODULE_MALFORMED_SPAN),
        "invalid-order": UInt32(HM_MODULE_INVALID_ORDER),
        "table-bounds": UInt32(HM_MODULE_TABLE_BOUNDS),
        "integer-overflow": UInt32(HM_MODULE_INTEGER_OVERFLOW),
        "partial-result": UInt32(HM_MODULE_PARTIAL_RESULT)
    ])
    check("modules", [
        "tic.locomotion": UInt32(HM_MODULE_TIC_LOCOMOTION),
        "tic.remainder": UInt32(HM_MODULE_TIC_REMAINDER),
        "movement.collision": UInt32(HM_MODULE_MOVEMENT_COLLISION),
        "interactions.combat": UInt32(HM_MODULE_INTERACTIONS_COMBAT),
        "thinkers.ai": UInt32(HM_MODULE_THINKERS_AI),
        "world.state": UInt32(HM_MODULE_WORLD_STATE),
        "hud.automap": UInt32(HM_MODULE_HUD_AUTOMAP),
        "bsp.traversal": UInt32(HM_MODULE_BSP_TRAVERSAL),
        "rasterization": UInt32(HM_MODULE_RASTERIZATION),
        "frame.composition": UInt32(HM_MODULE_FRAME_COMPOSITION),
        "game.loop": UInt32(HM_MODULE_GAME_LOOP)
    ])
    check("phases", [
        "input-normalization": UInt32(HM_PHASE_INPUT_NORMALIZATION),
        "tic-commands": UInt32(HM_PHASE_TIC_COMMANDS),
        "movement-collision": UInt32(HM_PHASE_MOVEMENT_COLLISION),
        "interactions-combat": UInt32(HM_PHASE_INTERACTIONS_COMBAT),
        "thinkers-ai": UInt32(HM_PHASE_THINKERS_AI),
        "world-commit": UInt32(HM_PHASE_WORLD_COMMIT),
        "hud-automap": UInt32(HM_PHASE_HUD_AUTOMAP),
        "bsp-traversal": UInt32(HM_PHASE_BSP_TRAVERSAL),
        "rasterization": UInt32(HM_PHASE_RASTERIZATION),
        "presentation": UInt32(HM_PHASE_PRESENTATION)
    ])
    check("tables", [
        "vertices": UInt32(HM_TABLE_VERTICES), "linedefs": UInt32(HM_TABLE_LINEDEFS),
        "sidedefs": UInt32(HM_TABLE_SIDEDEFS), "sectors": UInt32(HM_TABLE_SECTORS),
        "nodes": UInt32(HM_TABLE_NODES), "subsectors": UInt32(HM_TABLE_SUBSECTORS),
        "segs": UInt32(HM_TABLE_SEGS), "things": UInt32(HM_TABLE_THINGS),
        "blockmap": UInt32(HM_TABLE_BLOCKMAP), "reject": UInt32(HM_TABLE_REJECT),
        "textures": UInt32(HM_TABLE_TEXTURES), "patch-columns": UInt32(HM_TABLE_PATCH_COLUMNS),
        "flats": UInt32(HM_TABLE_FLATS), "sprites": UInt32(HM_TABLE_SPRITES),
        "playpal": UInt32(HM_TABLE_PLAYPAL), "colormap": UInt32(HM_TABLE_COLORMAP),
        "translations": UInt32(HM_TABLE_TRANSLATIONS),
        "state-definitions": UInt32(HM_TABLE_STATE_DEFINITIONS),
        "mobj-info": UInt32(HM_TABLE_MOBJ_INFO), "weapon-info": UInt32(HM_TABLE_WEAPON_INFO),
        "gameplay-rng": UInt32(HM_TABLE_GAMEPLAY_RNG),
        "font-metadata": UInt32(HM_TABLE_FONT_METADATA),
        "render-texture-metadata": UInt32(HM_TABLE_RENDER_TEXTURE_METADATA),
        "render-sprite-metadata": UInt32(HM_TABLE_RENDER_SPRITE_METADATA)
    ])
    check("events", [
        "line-crossed": UInt32(HM_EVENT_LINE_CROSSED),
        "thing-contact": UInt32(HM_EVENT_THING_CONTACT),
        "movement-blocked": UInt32(HM_EVENT_MOVEMENT_BLOCKED),
        "sound": UInt32(HM_EVENT_SOUND), "music": UInt32(HM_EVENT_MUSIC),
        "spawn": UInt32(HM_EVENT_SPAWN), "remove": UInt32(HM_EVENT_REMOVE),
        "damage": UInt32(HM_EVENT_DAMAGE), "pickup": UInt32(HM_EVENT_PICKUP),
        "message": UInt32(HM_EVENT_MESSAGE), "exit": UInt32(HM_EVENT_EXIT),
        "sector-change": UInt32(HM_EVENT_SECTOR_CHANGE),
        "collision-intent": UInt32(HM_EVENT_COLLISION_INTENT),
        "attack-intent": UInt32(HM_EVENT_ATTACK_INTENT),
        "spawn-intent": UInt32(HM_EVENT_SPAWN_INTENT),
        "remove-intent": UInt32(HM_EVENT_REMOVE_INTENT),
        "sector-action-intent": UInt32(HM_EVENT_SECTOR_ACTION_INTENT),
        "map-transition": UInt32(HM_EVENT_MAP_TRANSITION),
        "host-file-read": UInt32(HM_EVENT_HOST_FILE_READ),
        "host-file-write": UInt32(HM_EVENT_HOST_FILE_WRITE),
        "host-file-rename": UInt32(HM_EVENT_HOST_FILE_RENAME),
        "frame-ready": UInt32(HM_EVENT_FRAME_READY),
        "runtime-error": UInt32(HM_EVENT_RUNTIME_ERROR)
    ])
    check("drawPrimitives", [
        "patch": UInt32(HM_DRAW_PATCH), "text-glyph": UInt32(HM_DRAW_TEXT_GLYPH),
        "line": UInt32(HM_DRAW_LINE), "fill": UInt32(HM_DRAW_FILL),
        "wall-column-range": UInt32(HM_DRAW_WALL_COLUMN_RANGE),
        "plane-span": UInt32(HM_DRAW_PLANE_SPAN), "masked-seg": UInt32(HM_DRAW_MASKED_SEG),
        "sprite": UInt32(HM_DRAW_SPRITE), "sky-span": UInt32(HM_DRAW_SKY_SPAN),
        "clear": UInt32(HM_DRAW_CLEAR), "pause-overlay": UInt32(HM_DRAW_PAUSE_OVERLAY),
        "view-border": UInt32(HM_DRAW_VIEW_BORDER), "menu-overlay": UInt32(HM_DRAW_MENU_OVERLAY),
        "intermission": UInt32(HM_DRAW_INTERMISSION), "finale-page": UInt32(HM_DRAW_FINALE_PAGE),
        "wipe": UInt32(HM_DRAW_WIPE)
    ])
    check("worldArrays", [
        "scalars": UInt32(HM_WORLD_ARRAY_SCALARS), "players": UInt32(HM_WORLD_ARRAY_PLAYERS),
        "things": UInt32(HM_WORLD_ARRAY_THINGS), "thinkers": UInt32(HM_WORLD_ARRAY_THINKERS),
        "sectors": UInt32(HM_WORLD_ARRAY_SECTORS), "lines": UInt32(HM_WORLD_ARRAY_LINES),
        "psprites": UInt32(HM_WORLD_ARRAY_PSPRITES),
        "block-links": UInt32(HM_WORLD_ARRAY_BLOCK_LINKS),
        "player-ammo": UInt32(HM_WORLD_ARRAY_PLAYER_AMMO),
        "player-max-ammo": UInt32(HM_WORLD_ARRAY_PLAYER_MAX_AMMO),
        "player-weapons": UInt32(HM_WORLD_ARRAY_PLAYER_WEAPONS),
        "player-powers": UInt32(HM_WORLD_ARRAY_PLAYER_POWERS),
        "player-cards": UInt32(HM_WORLD_ARRAY_PLAYER_CARDS),
        "player-frags": UInt32(HM_WORLD_ARRAY_PLAYER_FRAGS),
        "sector-movers": UInt32(HM_WORLD_ARRAY_SECTOR_MOVERS),
        "rng": UInt32(HM_WORLD_ARRAY_RNG),
        "transitions": UInt32(HM_WORLD_ARRAY_TRANSITIONS),
        "hud": UInt32(HM_WORLD_ARRAY_HUD),
        "automap": UInt32(HM_WORLD_ARRAY_AUTOMAP),
        "automap-marks": UInt32(HM_WORLD_ARRAY_AUTOMAP_MARKS),
        "renderer": UInt32(HM_WORLD_ARRAY_RENDERER),
        "render-solidsegs": UInt32(HM_WORLD_ARRAY_RENDER_SOLIDSEGS),
        "render-drawsegs": UInt32(HM_WORLD_ARRAY_RENDER_DRAWSEGS),
        "render-visplanes": UInt32(HM_WORLD_ARRAY_RENDER_VISPLANES),
        "render-openings": UInt32(HM_WORLD_ARRAY_RENDER_OPENINGS),
        "render-vissprites": UInt32(HM_WORLD_ARRAY_RENDER_VISSPRITES),
        "framebuffer": UInt32(HM_WORLD_ARRAY_FRAMEBUFFER),
        "framebuffer-tiles": UInt32(HM_WORLD_ARRAY_FRAMEBUFFER_TILES)
    ])
    check("exactOpcodes", [
        "move": UInt32(HM_EXACT_OP_MOVE), "constant": UInt32(HM_EXACT_OP_CONSTANT),
        "add-i32": UInt32(HM_EXACT_OP_ADD_I32), "sub-i32": UInt32(HM_EXACT_OP_SUB_I32),
        "fixed-mul-16.16": UInt32(HM_EXACT_OP_FIXED_MUL_16_16),
        "fixed-div-16.16": UInt32(HM_EXACT_OP_FIXED_DIV_16_16),
        "angle-add-u32": UInt32(HM_EXACT_OP_ANGLE_ADD_U32),
        "compare-lt-i32": UInt32(HM_EXACT_OP_COMPARE_LT_I32),
        "compare-equal-bits": UInt32(HM_EXACT_OP_COMPARE_EQUAL_BITS),
        "gate": UInt32(HM_EXACT_OP_GATE),
        "table-read-i32": UInt32(HM_EXACT_OP_TABLE_READ_I32)
    ])
}

private func canonicalAuxiliaryRecords() {
    var world = HMWorldSnapshotV1()
    world.abi_version = UInt32(HM_WORLD_SNAPSHOT_ABI_VERSION)
    world.schema_version = UInt32(HM_WORLD_SCHEMA_VERSION)
    world.tic_id = 42
    world.source_hash = fixtureSourceHash
    world.map_fingerprint = 0xfedc_ba98_7654_3210
    world.scalar_count = 1
    world.array_count = 2
    world.array_directory_offset = 14
    world.data_offset = 26
    world.word_count = 38
    let baseArrays = [
        HMWorldArrayV1(array_id: UInt32(HM_WORLD_ARRAY_SCALARS), element_count: 1,
                       element_capacity: 1, cell_count: 1, data_offset: 26, reserved: 0),
        HMWorldArrayV1(array_id: UInt32(HM_WORLD_ARRAY_PLAYERS), element_count: 1,
                       element_capacity: 2, cell_count: 2, data_offset: 30, reserved: 0)
    ]
    let baseCells = [
        HMWorldCellV1(array_id: UInt32(HM_WORLD_ARRAY_SCALARS), element_index: 0,
                      cell_id: UInt32(HM_SCALAR_GAME_SKILL), value: 2),
        HMWorldCellV1(array_id: UInt32(HM_WORLD_ARRAY_PLAYERS), element_index: 0,
                      cell_id: UInt32(HM_PLAYER_X), value: 10),
        HMWorldCellV1(array_id: UInt32(HM_WORLD_ARRAY_PLAYERS), element_index: 0,
                      cell_id: UInt32(HM_PLAYER_Y), value: -20)
    ]
    var worldArrays = baseArrays
    var worldCells = baseCells
    var worldBytes = [UInt8](repeating: 0xff, count: 152)
    let worldWritten = worldArrays.withUnsafeMutableBufferPointer { arrayBuffer in
        worldCells.withUnsafeMutableBufferPointer { cellBuffer in
            worldBytes.withUnsafeMutableBufferPointer { byteBuffer in
                HM_SerializeWorldSnapshotV1(
                    &world, arrayBuffer.baseAddress, UInt32(arrayBuffer.count),
                    cellBuffer.baseAddress, UInt32(cellBuffer.count), UInt32(cellBuffer.count),
                    byteBuffer.baseAddress, byteBuffer.count)
            }
        }
    }
    require(worldWritten == worldBytes.count &&
            HM_HashBytesV1(worldBytes, worldBytes.count) != 0,
            "canonical whole-world serialization")

    func expectWorldRejection(
        _ label: String,
        _ mutate: (inout HMWorldSnapshotV1, inout [HMWorldArrayV1],
                   inout [HMWorldCellV1], inout UInt32, inout UInt32, inout UInt32) -> Void
    ) {
        var rejectedWorld = world
        var rejectedArrays = baseArrays
        var rejectedCells = baseCells
        var arrayCapacity = UInt32(rejectedArrays.count)
        var cellCount = UInt32(rejectedCells.count)
        var cellCapacity = cellCount
        mutate(&rejectedWorld, &rejectedArrays, &rejectedCells,
               &arrayCapacity, &cellCount, &cellCapacity)
        var bytes = [UInt8](repeating: 0, count: 152)
        rejectedArrays.withUnsafeMutableBufferPointer { arrayBuffer in
            rejectedCells.withUnsafeMutableBufferPointer { cellBuffer in
                require(HM_ValidateWorldSnapshotV1(
                    &rejectedWorld, arrayBuffer.baseAddress, arrayCapacity,
                    cellBuffer.baseAddress, cellCount, cellCapacity) == 0 &&
                    HM_CanonicalWorldSnapshotSizeV1(
                        &rejectedWorld, arrayBuffer.baseAddress, arrayCapacity,
                        cellBuffer.baseAddress, cellCount, cellCapacity) == 0 &&
                    bytes.withUnsafeMutableBufferPointer { byteBuffer in
                        HM_SerializeWorldSnapshotV1(
                            &rejectedWorld, arrayBuffer.baseAddress, arrayCapacity,
                            cellBuffer.baseAddress, cellCount, cellCapacity,
                            byteBuffer.baseAddress, byteBuffer.count)
                    } == 0,
                    "invalid world snapshot accepted: \(label)")
            }
        }
    }
    expectWorldRejection("array capacity") { _, _, _, arrayCapacity, _, _ in
        arrayCapacity = 1
    }
    expectWorldRejection("cell capacity") { _, _, _, _, _, cellCapacity in
        cellCapacity = 2
    }
    expectWorldRejection("ABI version") { snapshot, _, _, _, _, _ in
        snapshot.abi_version += 1
    }
    expectWorldRejection("schema version") { snapshot, _, _, _, _, _ in
        snapshot.schema_version += 1
    }
    expectWorldRejection("source hash") { snapshot, _, _, _, _, _ in
        snapshot.source_hash = 0
    }
    expectWorldRejection("directory offset") { snapshot, _, _, _, _, _ in
        snapshot.array_directory_offset += 1
    }
    expectWorldRejection("scalar count") { snapshot, _, _, _, _, _ in
        snapshot.scalar_count += 1
    }
    expectWorldRejection("element capacity") { _, arrays, _, _, _, _ in
        arrays[1].element_count = arrays[1].element_capacity + 1
    }
    expectWorldRejection("unknown array") { _, arrays, _, _, _, _ in
        arrays[1].array_id = 0xffff_ffff
    }
    expectWorldRejection("array reserved") { _, arrays, _, _, _, _ in
        arrays[1].reserved = 1
    }
    expectWorldRejection("array offset") { _, arrays, _, _, _, _ in
        arrays[1].data_offset += 1
    }
    expectWorldRejection("array cell count") { _, arrays, _, _, _, _ in
        arrays[1].cell_count += 1
    }
    expectWorldRejection("cell order") { _, _, cells, _, _, _ in
        cells.swapAt(1, 2)
    }
    expectWorldRejection("unknown cell") { _, _, cells, _, _, _ in
        cells[1].cell_id = 0xffff_ffff
    }
    expectWorldRejection("element bounds") { _, _, cells, _, _, _ in
        cells[1].element_index = 1
    }
    expectWorldRejection("word count") { snapshot, _, _, _, _, _ in
        snapshot.word_count += 1
    }
    var nullWorld = world
    worldCells = baseCells
    worldCells.withUnsafeMutableBufferPointer { cellBuffer in
        require(HM_ValidateWorldSnapshotV1(
            &nullWorld, nil, UInt32(baseArrays.count), cellBuffer.baseAddress,
            UInt32(cellBuffer.count), UInt32(cellBuffer.count)) == 0,
            "null world-array span accepted")
    }
    worldArrays = baseArrays
    worldArrays.withUnsafeMutableBufferPointer { arrayBuffer in
        require(HM_ValidateWorldSnapshotV1(
            &nullWorld, arrayBuffer.baseAddress, UInt32(arrayBuffer.count), nil,
            UInt32(baseCells.count), UInt32(baseCells.count)) == 0,
            "null world-cell span accepted")
    }

    var event = makeEvent(phase: UInt32(HM_PHASE_INTERACTIONS_COMBAT),
                          id: UInt32(HM_EVENT_SOUND), emitter: 1,
                          sequence: 2, firstPayload: -3)
    var eventBytes = [UInt8](repeating: 0, count: 48)
    require(eventBytes.withUnsafeMutableBufferPointer {
        HM_SerializeModuleEventV1(&event, $0.baseAddress, $0.count)
    } == 48, "canonical event serialization")
    var staleEvent = event
    staleEvent.payload.1 = 17
    staleEvent.payload.2 = -21
    staleEvent.payload.3 = 33
    var staleEventBytes = [UInt8](repeating: 0xff, count: 48)
    require(staleEventBytes.withUnsafeMutableBufferPointer {
        HM_SerializeModuleEventV1(&staleEvent, $0.baseAddress, $0.count)
    } == 48 && staleEventBytes == eventBytes,
    "inactive event payload changed canonical serialization")
    event.event_id = 0xffff_ffff
    require(eventBytes.withUnsafeMutableBufferPointer {
        HM_SerializeModuleEventV1(&event, $0.baseAddress, $0.count)
    } == 0, "unknown event serialized")

    var primitive = HMDrawPrimitiveV1()
    primitive.primitive_id = UInt32(HM_DRAW_PATCH)
    primitive.sequence = 7
    primitive.clip_right = 319
    primitive.clip_bottom = 199
    primitive.resource_table_id = UInt32(HM_TABLE_PATCH_COLUMNS)
    primitive.resource_index = 5
    primitive.argument.0 = -1
    var primitiveBytes = [UInt8](repeating: 0, count: 72)
    require(primitiveBytes.withUnsafeMutableBufferPointer {
        HM_SerializeDrawPrimitiveV1(&primitive, $0.baseAddress, $0.count)
    } == 72 && HM_HashBytesV1(primitiveBytes, primitiveBytes.count) != 0,
    "canonical draw primitive serialization")
    primitive.primitive_id = 0xffff_ffff
    require(primitiveBytes.withUnsafeMutableBufferPointer {
        HM_SerializeDrawPrimitiveV1(&primitive, $0.baseAddress, $0.count)
    } == 0, "unknown draw primitive serialized")

    func expectResultSerializationRejection(
        _ label: String, _ mutate: (inout HMModuleResultV1) -> Void
    ) {
        withContractFixture { _, result in
            mutate(&result)
            var bytes = [UInt8](repeating: 0, count: 256)
            require(HM_CanonicalModuleResultSizeV1(&result) == 0 &&
                    bytes.withUnsafeMutableBufferPointer {
                        HM_SerializeModuleResultV1(&result, $0.baseAddress, $0.count)
                    } == 0,
                    "invalid canonical result serialized: \(label)")
        }
    }
    expectResultSerializationRejection("ABI") { $0.abi_version += 1 }
    expectResultSerializationRejection("module") { $0.module_id = 0xffff_ffff }
    expectResultSerializationRejection("source hash") { $0.source_hash = 0 }
    expectResultSerializationRejection("reserved") { $0.reserved = 1 }
    expectResultSerializationRejection("null capacity") {
        $0.output_count = 0
        $0.outputs = nil
    }
}

private func exactOp(_ opcode: UInt32, _ destination: UInt32,
                     _ lhs: UInt32 = 0, _ rhs: UInt32 = 0,
                     immediate: Int32 = 0, table: UInt32 = 0) -> HMExactOpV1 {
    HMExactOpV1(opcode: opcode, destination: destination, lhs: lhs, rhs: rhs,
                immediate: immediate, table_id: table, flags: 0, reserved: 0)
}

private struct ExactRuntimeArgumentsV1 {
    var inputs: UnsafePointer<UInt32>?
    var inputCount: UInt32
    var tables: UnsafePointer<HMTableViewV1>?
    var tableCount: UInt32
    var scratch: UnsafeMutablePointer<UInt32>?
    var scratchCapacity: UInt32
    var outputs: UnsafeMutablePointer<UInt32>?
    var outputCapacity: UInt32
}

private func exactCPU(inputs: [UInt32], operations: [HMExactOpV1], roots: [UInt32],
                      tableCells: [Int32] = [7, -9], badHash: Bool = false,
                      mutateProgram: ((inout HMExactProgramV1) -> Void)? = nil,
                      mutateRuntime: ((inout ExactRuntimeArgumentsV1) -> Void)? = nil)
    -> (UInt32, [UInt32], UInt32) {
    var mutableInputs = inputs
    var mutableOperations = operations
    var mutableRoots = roots
    var mutableTableCells = tableCells
    var scratch = [UInt32](repeating: 0, count: inputs.count + operations.count)
    var outputs = [UInt32](repeating: 0xaaaa_aaaa, count: roots.count)
    let tableCount: UInt32 = tableCells.isEmpty ? 0 : 1
    let scratchCount = UInt32(scratch.count)
    let outputCapacity = UInt32(outputs.count)
    var produced: UInt32 = 0
    var returnedStatus = UInt32(HM_MODULE_EXECUTION_ERROR)
    mutableInputs.withUnsafeMutableBufferPointer { inputBuffer in
        mutableOperations.withUnsafeMutableBufferPointer { operationBuffer in
            mutableRoots.withUnsafeMutableBufferPointer { rootBuffer in
                mutableTableCells.withUnsafeMutableBufferPointer { tableCellBuffer in
                    var tables: [HMTableViewV1] = tableCells.isEmpty ? [] : [
                        HMTableViewV1(table_id: UInt32(HM_TABLE_VERTICES),
                                      length: UInt32(tableCells.count),
                                      capacity: UInt32(tableCells.count), reserved: 0,
                                      cells: tableCellBuffer.baseAddress.map { UnsafePointer($0) })
                    ]
                    tables.withUnsafeMutableBufferPointer { tableBuffer in
                        scratch.withUnsafeMutableBufferPointer { scratchBuffer in
                            outputs.withUnsafeMutableBufferPointer { outputBuffer in
                                var program = HMExactProgramV1(
                                    abi_version: UInt32(HM_EXACT_PROGRAM_ABI_VERSION),
                                    integer_encoding: UInt32(HM_EXACT_INTEGER_ENCODING_V1),
                                    input_count: UInt32(inputs.count),
                                    register_count: UInt32(inputs.count + operations.count),
                                    operation_count: UInt32(operations.count),
                                    operation_capacity: UInt32(operations.count),
                                    output_count: UInt32(roots.count),
                                    output_capacity: UInt32(roots.count), source_hash: 0,
                                    operations: operationBuffer.baseAddress.map { UnsafePointer($0) },
                                    output_registers: rootBuffer.baseAddress.map { UnsafePointer($0) })
                                program.source_hash = HM_ExactProgramHashV1(&program)
                                mutateProgram?(&program)
                                if badHash { program.source_hash ^= 1 }
                                var runtime = ExactRuntimeArgumentsV1(
                                    inputs: inputBuffer.baseAddress.map { UnsafePointer($0) },
                                    inputCount: UInt32(inputs.count),
                                    tables: tableBuffer.baseAddress.map { UnsafePointer($0) },
                                    tableCount: tableCount,
                                    scratch: scratchBuffer.baseAddress,
                                    scratchCapacity: scratchCount,
                                    outputs: outputBuffer.baseAddress,
                                    outputCapacity: outputCapacity)
                                mutateRuntime?(&runtime)
                                returnedStatus = HM_EvaluateExactProgramV1(
                                    &program, runtime.inputs, runtime.inputCount,
                                    runtime.tables, runtime.tableCount,
                                    runtime.scratch, runtime.scratchCapacity,
                                    runtime.outputs, runtime.outputCapacity, &produced)
                            }
                        }
                    }
                }
            }
        }
    }
    return (returnedStatus, outputs, produced)
}

private func exactMetal(device: MTLDevice, pipeline: MTLComputePipelineState,
                        inputs: [UInt32], operations: [HMExactOpV1], roots: [UInt32],
                        tableCells: [Int32] = [7, -9],
                        mutateDescriptors: ((inout [HMExactTableDescriptorV1]) -> Void)? = nil,
                        mutateDispatch: ((inout HMExactDispatchV1) -> Void)? = nil,
                        reusableStatusBuffer: MTLBuffer? = nil)
    -> (UInt32, [UInt32], UInt32) {
    var descriptors: [HMExactTableDescriptorV1] = tableCells.isEmpty ? [] : [
        HMExactTableDescriptorV1(table_id: UInt32(HM_TABLE_VERTICES),
                                 length: UInt32(tableCells.count),
                                 capacity: UInt32(tableCells.count), offset: 0, reserved: 0)
    ]
    mutateDescriptors?(&descriptors)
    var dispatch = HMExactDispatchV1()
    dispatch.abi_version = UInt32(HM_EXACT_PROGRAM_ABI_VERSION)
    dispatch.integer_encoding = UInt32(HM_EXACT_INTEGER_ENCODING_V1)
    dispatch.input_count = UInt32(inputs.count)
    dispatch.input_capacity = UInt32(inputs.count)
    dispatch.register_count = UInt32(inputs.count + operations.count)
    dispatch.scratch_capacity = dispatch.register_count
    dispatch.operation_count = UInt32(operations.count)
    dispatch.operation_capacity = dispatch.operation_count
    dispatch.output_count = UInt32(roots.count)
    dispatch.output_capacity = dispatch.output_count
    dispatch.table_count = UInt32(descriptors.count)
    dispatch.table_capacity = dispatch.table_count
    dispatch.table_cell_count = UInt32(tableCells.count)
    dispatch.table_cell_capacity = dispatch.table_cell_count
    dispatch.output_register_capacity = dispatch.output_count
    dispatch.status_capacity = 2
    mutateDispatch?(&dispatch)
    func buffer<T>(_ values: [T]) -> MTLBuffer {
        if values.isEmpty { return device.makeBuffer(length: 4, options: .storageModeShared)! }
        return values.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count,
                              options: .storageModeShared)!
        }
    }
    let inputBuffer = buffer(inputs)
    let operationBuffer = buffer(operations)
    let tableBuffer = buffer(descriptors)
    let tableCellBuffer = buffer(tableCells)
    let rootBuffer = buffer(roots)
    let scratchBuffer = device.makeBuffer(
        length: max(4, (inputs.count + operations.count) * 4), options: .storageModeShared)!
    let outputBuffer = device.makeBuffer(length: max(4, roots.count * 4),
                                         options: .storageModeShared)!
    let statusBuffer = reusableStatusBuffer ??
        device.makeBuffer(length: 8, options: .storageModeShared)!
    let actualStatusCapacity = UInt32(statusBuffer.length / MemoryLayout<UInt32>.stride)
    let statusWords = statusBuffer.contents().bindMemory(
        to: UInt32.self, capacity: max(1, Int(actualStatusCapacity)))
    let prepareStatus = HM_PrepareExactDispatchV1(
        &dispatch, statusWords, actualStatusCapacity)
    guard prepareStatus == UInt32(HM_MODULE_EXACT) else {
        return (prepareStatus, [UInt32](repeating: 0, count: roots.count), 0)
    }
    let dispatchBuffer = withUnsafeBytes(of: &dispatch) {
        device.makeBuffer(bytes: $0.baseAddress!, length: $0.count,
                          options: .storageModeShared)!
    }
    let queue = device.makeCommandQueue()!
    let command = queue.makeCommandBuffer()!
    let encoder = command.makeComputeCommandEncoder()!
    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(inputBuffer, offset: 0, index: 0)
    encoder.setBuffer(operationBuffer, offset: 0, index: 1)
    encoder.setBuffer(tableBuffer, offset: 0, index: 2)
    encoder.setBuffer(tableCellBuffer, offset: 0, index: 3)
    encoder.setBuffer(rootBuffer, offset: 0, index: 4)
    encoder.setBuffer(scratchBuffer, offset: 0, index: 5)
    encoder.setBuffer(outputBuffer, offset: 0, index: 6)
    encoder.setBuffer(statusBuffer, offset: 0, index: 7)
    encoder.setBuffer(dispatchBuffer, offset: 0, index: 8)
    encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    require(command.status == .completed, "exact integer Metal command failed")
    let outputWords = outputBuffer.contents().bindMemory(to: UInt32.self,
                                                        capacity: max(1, roots.count))
    return (statusWords[0], (0..<roots.count).map { outputWords[$0] }, statusWords[1])
}

private func exactIntegerConformance() {
    guard let device = MTLCreateSystemDefaultDevice() else {
        require(false, "Apple Silicon Metal device unavailable for exact integer ABI")
        return
    }
    let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Bridge/CircuitExactV1.msl")
    let source = try! String(contentsOf: sourceURL, encoding: .utf8)
    let options = MTLCompileOptions()
    if #available(macOS 15.0, *) { options.mathMode = .safe }
    else { options.fastMathEnabled = false }
    let library = try! device.makeLibrary(source: source, options: options)
    let pipeline = try! device.makeComputePipelineState(
        function: library.makeFunction(name: "evaluateExactCircuitV1")!)

    let inputs: [UInt32] = [
        UInt32(bitPattern: Int32.min), UInt32(bitPattern: Int32.max),
        UInt32.max, 65_536, 98_304, UInt32(bitPattern: -65_536), 1, 1, 0
    ]
    let operations = [
        exactOp(UInt32(HM_EXACT_OP_MOVE), 9, 0),
        exactOp(UInt32(HM_EXACT_OP_MOVE), 10, 1),
        exactOp(UInt32(HM_EXACT_OP_ANGLE_ADD_U32), 11, 2, 7),
        exactOp(UInt32(HM_EXACT_OP_FIXED_MUL_16_16), 12, 4, 5),
        exactOp(UInt32(HM_EXACT_OP_FIXED_DIV_16_16), 13, 4, 5),
        exactOp(UInt32(HM_EXACT_OP_COMPARE_LT_I32), 14, 0, 1),
        exactOp(UInt32(HM_EXACT_OP_GATE), 15, 1, 7),
        exactOp(UInt32(HM_EXACT_OP_TABLE_READ_I32), 16, 6,
                table: UInt32(HM_TABLE_VERTICES)),
        exactOp(UInt32(HM_EXACT_OP_ADD_I32), 17, 0, 1),
        exactOp(UInt32(HM_EXACT_OP_FIXED_MUL_16_16), 18, 0, 3),
        exactOp(UInt32(HM_EXACT_OP_FIXED_MUL_16_16), 19, 1, 3),
        exactOp(UInt32(HM_EXACT_OP_FIXED_DIV_16_16), 20, 0, 3),
        exactOp(UInt32(HM_EXACT_OP_FIXED_DIV_16_16), 21, 1, 3),
        exactOp(UInt32(HM_EXACT_OP_COMPARE_EQUAL_BITS), 22, 6, 7),
        exactOp(UInt32(HM_EXACT_OP_GATE), 23, 1, 8)
    ]
    let roots = Array(UInt32(9)...UInt32(23))
    let expected: [UInt32] = [
        UInt32(bitPattern: Int32.min), UInt32(bitPattern: Int32.max), 0,
        UInt32(bitPattern: -98_304), UInt32(bitPattern: -98_304), 1,
        UInt32(bitPattern: Int32.max), UInt32(bitPattern: -9), UInt32.max,
        UInt32(bitPattern: Int32.min), UInt32(bitPattern: Int32.max),
        UInt32(bitPattern: Int32.min), UInt32(bitPattern: Int32.max), 1, 0
    ]
    let cpu = exactCPU(inputs: inputs, operations: operations, roots: roots)
    require(cpu.0 == UInt32(HM_MODULE_EXACT) && cpu.2 == UInt32(expected.count) &&
            cpu.1 == expected, "exact integer CPU edge vectors")
    let metal = exactMetal(device: device, pipeline: pipeline, inputs: inputs,
                           operations: operations, roots: roots)
    require(metal.0 == UInt32(HM_MODULE_EXACT) && metal.2 == UInt32(expected.count) &&
            metal.1 == expected, "exact integer Metal edge vectors")

    let repeatedRootsCPU = exactCPU(inputs: [42], operations: [], roots: [0, 0],
                                    tableCells: [])
    let repeatedRootsMetal = exactMetal(device: device, pipeline: pipeline,
                                        inputs: [42], operations: [], roots: [0, 0],
                                        tableCells: [])
    require(repeatedRootsCPU.0 == UInt32(HM_MODULE_EXACT) &&
            repeatedRootsCPU.1 == [42, 42] && repeatedRootsCPU.2 == 2 &&
            repeatedRootsMetal.0 == UInt32(HM_MODULE_EXACT) &&
            repeatedRootsMetal.1 == [42, 42] && repeatedRootsMetal.2 == 2,
            "repeated output roots diverged between CPU and Metal")

    let emptyCPU = exactCPU(inputs: [], operations: [], roots: [], tableCells: [])
    let emptyMetal = exactMetal(device: device, pipeline: pipeline,
                                inputs: [], operations: [], roots: [], tableCells: [])
    require(emptyCPU.0 == UInt32(HM_MODULE_EXACT) && emptyCPU.2 == 0 &&
            emptyMetal.0 == UInt32(HM_MODULE_EXACT) && emptyMetal.2 == 0,
            "empty exact program was not deterministic")

    let spanInputs = [UInt32(1)]
    let spanOperations = [exactOp(UInt32(HM_EXACT_OP_MOVE), 1, 0)]
    let spanRoots = [UInt32(1)]
    func expectCPUProgramRejection(
        _ label: String, _ expectedStatus: UInt32,
        _ mutate: @escaping (inout HMExactProgramV1) -> Void
    ) {
        let result = exactCPU(inputs: spanInputs, operations: spanOperations,
                              roots: spanRoots, tableCells: [], mutateProgram: mutate)
        require(result.0 == expectedStatus && result.2 == 0,
                "exact CPU program span accepted: \(label)")
    }
    expectCPUProgramRejection("operation count", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.operation_capacity = 0
    }
    expectCPUProgramRejection("output-register count", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.output_capacity = 0
    }
    expectCPUProgramRejection("null operations", UInt32(HM_MODULE_MALFORMED_SPAN)) {
        $0.operations = nil
    }
    expectCPUProgramRejection("null output registers", UInt32(HM_MODULE_MALFORMED_SPAN)) {
        $0.output_registers = nil
    }

    func expectCPURuntimeRejection(
        _ label: String, _ expectedStatus: UInt32,
        _ mutate: @escaping (inout ExactRuntimeArgumentsV1) -> Void
    ) {
        let result = exactCPU(inputs: spanInputs, operations: spanOperations,
                              roots: spanRoots, tableCells: [7], mutateRuntime: mutate)
        require(result.0 == expectedStatus && result.2 == 0,
                "exact CPU runtime span accepted: \(label)")
    }
    expectCPURuntimeRejection("scratch capacity", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.scratchCapacity = 1
    }
    expectCPURuntimeRejection("output capacity", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.outputCapacity = 0
    }
    expectCPURuntimeRejection("null inputs", UInt32(HM_MODULE_MALFORMED_SPAN)) {
        $0.inputs = nil
    }
    expectCPURuntimeRejection("null tables", UInt32(HM_MODULE_MALFORMED_SPAN)) {
        $0.tables = nil
    }
    expectCPURuntimeRejection("null scratch", UInt32(HM_MODULE_MALFORMED_SPAN)) {
        $0.scratch = nil
    }
    expectCPURuntimeRejection("null outputs", UInt32(HM_MODULE_MALFORMED_SPAN)) {
        $0.outputs = nil
    }

    func expectMetalDispatchRejection(
        _ label: String, _ expectedStatus: UInt32,
        _ mutate: @escaping (inout HMExactDispatchV1) -> Void
    ) {
        let result = exactMetal(device: device, pipeline: pipeline, inputs: spanInputs,
                                operations: spanOperations, roots: spanRoots,
                                tableCells: [], mutateDispatch: mutate)
        require(result.0 == expectedStatus && result.2 == 0,
                "exact Metal dispatch span accepted: \(label)")
    }
    expectMetalDispatchRejection("inputs", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.input_capacity = 0
    }
    expectMetalDispatchRejection("scratch", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.scratch_capacity = 1
    }
    expectMetalDispatchRejection("operations", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.operation_capacity = 0
    }
    expectMetalDispatchRejection("outputs", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.output_capacity = 0
    }
    expectMetalDispatchRejection("output registers", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.output_register_capacity = 0
    }
    expectMetalDispatchRejection("tables", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.table_count = 1
    }
    expectMetalDispatchRejection("table cells", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.table_cell_count = 1
    }
    let reusedStatusBuffer = device.makeBuffer(length: 8, options: .storageModeShared)!
    let successfulStatus = exactMetal(device: device, pipeline: pipeline,
                                      inputs: spanInputs, operations: spanOperations,
                                      roots: spanRoots, tableCells: [],
                                      reusableStatusBuffer: reusedStatusBuffer)
    require(successfulStatus.0 == UInt32(HM_MODULE_EXACT) && successfulStatus.2 == 1,
            "exact Metal status-buffer setup did not succeed")
    let shortStatus = exactMetal(device: device, pipeline: pipeline,
                                 inputs: spanInputs, operations: spanOperations,
                                 roots: spanRoots, tableCells: [],
                                 mutateDispatch: { $0.status_capacity = 1 },
                                 reusableStatusBuffer: reusedStatusBuffer)
    require(shortStatus.0 == UInt32(HM_MODULE_CAPACITY_EXCEEDED) && shortStatus.2 == 0,
            "short Metal status span committed stale success")
    let physicalShortStatus = exactMetal(
        device: device, pipeline: pipeline, inputs: spanInputs,
        operations: spanOperations, roots: spanRoots, tableCells: [],
        reusableStatusBuffer: device.makeBuffer(length: 4, options: .storageModeShared)!)
    require(physicalShortStatus.0 == UInt32(HM_MODULE_CAPACITY_EXCEEDED) &&
            physicalShortStatus.2 == 0,
            "physically short Metal status span reached dispatch")

    let descriptorInputs = [UInt32(0)]
    let descriptorOperations = [exactOp(UInt32(HM_EXACT_OP_TABLE_READ_I32), 1, 0,
                                        table: UInt32(HM_TABLE_VERTICES))]
    func expectMetalDescriptorRejection(
        _ label: String, _ expectedStatus: UInt32,
        _ mutate: @escaping (inout [HMExactTableDescriptorV1]) -> Void
    ) {
        let result = exactMetal(device: device, pipeline: pipeline,
                                inputs: descriptorInputs, operations: descriptorOperations,
                                roots: [1], mutateDescriptors: mutate)
        require(result.0 == expectedStatus && result.2 == 0,
                "exact Metal table descriptor accepted: \(label)")
    }
    expectMetalDescriptorRejection("unknown ID", UInt32(HM_MODULE_UNKNOWN_ID)) {
        $0[0].table_id = 0xffff_ffff
    }
    expectMetalDescriptorRejection("reserved", UInt32(HM_MODULE_MALFORMED_SPAN)) {
        $0[0].reserved = 1
    }
    expectMetalDescriptorRejection("length capacity", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0[0].capacity = 1
    }
    expectMetalDescriptorRejection("flattened range", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0[0].offset = UInt32.max
    }
    expectMetalDescriptorRejection("ordering", UInt32(HM_MODULE_INVALID_ORDER)) {
        $0.append($0[0])
    }

    let overflowInputs = [UInt32(bitPattern: Int32.max), UInt32(1)]
    let overflowOps = [exactOp(UInt32(HM_EXACT_OP_ADD_I32), 2, 0, 1)]
    let overflowCPU = exactCPU(inputs: overflowInputs, operations: overflowOps, roots: [2],
                               tableCells: [])
    let overflowMetal = exactMetal(device: device, pipeline: pipeline,
                                   inputs: overflowInputs, operations: overflowOps,
                                   roots: [2], tableCells: [])
    require(overflowCPU.0 == UInt32(HM_MODULE_INTEGER_OVERFLOW) && overflowCPU.2 == 0 &&
            overflowMetal.0 == UInt32(HM_MODULE_INTEGER_OVERFLOW) && overflowMetal.2 == 0,
            "integer overflow was not an empty CPU/Metal result")

    let divideOverflowOps = [exactOp(UInt32(HM_EXACT_OP_FIXED_DIV_16_16), 2, 0, 1)]
    let divideOverflowCPU = exactCPU(inputs: overflowInputs, operations: divideOverflowOps,
                                     roots: [2], tableCells: [])
    let divideOverflowMetal = exactMetal(device: device, pipeline: pipeline,
                                         inputs: overflowInputs, operations: divideOverflowOps,
                                         roots: [2], tableCells: [])
    require(divideOverflowCPU.0 == UInt32(HM_MODULE_INTEGER_OVERFLOW) &&
            divideOverflowMetal.0 == UInt32(HM_MODULE_INTEGER_OVERFLOW),
            "fixed divide overflow was not rejected by CPU/Metal")

    let divideZeroInputs = [UInt32(65_536), UInt32(0)]
    let divideZeroCPU = exactCPU(inputs: divideZeroInputs, operations: divideOverflowOps,
                                 roots: [2], tableCells: [])
    let divideZeroMetal = exactMetal(device: device, pipeline: pipeline,
                                     inputs: divideZeroInputs, operations: divideOverflowOps,
                                     roots: [2], tableCells: [])
    require(divideZeroCPU.0 == UInt32(HM_MODULE_EXECUTION_ERROR) && divideZeroCPU.2 == 0 &&
            divideZeroMetal.0 == UInt32(HM_MODULE_EXECUTION_ERROR) && divideZeroMetal.2 == 0,
            "fixed divide by zero was not an empty CPU/Metal result")

    let readInputs = [UInt32(2)]
    let readOps = [exactOp(UInt32(HM_EXACT_OP_TABLE_READ_I32), 1, 0,
                           table: UInt32(HM_TABLE_VERTICES))]
    let overreadCPU = exactCPU(inputs: readInputs, operations: readOps, roots: [1])
    let overreadMetal = exactMetal(device: device, pipeline: pipeline,
                                   inputs: readInputs, operations: readOps, roots: [1])
    require(overreadCPU.0 == UInt32(HM_MODULE_TABLE_BOUNDS) && overreadCPU.2 == 0 &&
            overreadMetal.0 == UInt32(HM_MODULE_TABLE_BOUNDS) && overreadMetal.2 == 0,
            "table overread was not rejected by CPU/Metal")

    let missingTableInputs = [UInt32(0)]
    let missingTableOps = [exactOp(UInt32(HM_EXACT_OP_TABLE_READ_I32), 1, 0,
                                   table: UInt32(HM_TABLE_VERTICES))]
    let missingTableCPU = exactCPU(inputs: missingTableInputs, operations: missingTableOps,
                                   roots: [1], tableCells: [])
    let missingTableMetal = exactMetal(device: device, pipeline: pipeline,
                                       inputs: missingTableInputs, operations: missingTableOps,
                                       roots: [1], tableCells: [])
    require(missingTableCPU.0 == UInt32(HM_MODULE_TABLE_BOUNDS) &&
            missingTableCPU.2 == 0 &&
            missingTableMetal.0 == UInt32(HM_MODULE_TABLE_BOUNDS) &&
            missingTableMetal.2 == 0,
            "missing known table diverged between CPU and Metal")

    let unknownTableOps = [exactOp(UInt32(HM_EXACT_OP_TABLE_READ_I32), 1, 0,
                                   table: 0xffff_ffff)]
    let unknownTableCPU = exactCPU(inputs: missingTableInputs, operations: unknownTableOps,
                                   roots: [1], tableCells: [])
    let unknownTableMetal = exactMetal(device: device, pipeline: pipeline,
                                       inputs: missingTableInputs, operations: unknownTableOps,
                                       roots: [1], tableCells: [])
    require(unknownTableCPU.0 == UInt32(HM_MODULE_UNKNOWN_ID) && unknownTableCPU.2 == 0 &&
            unknownTableMetal.0 == UInt32(HM_MODULE_UNKNOWN_ID) &&
            unknownTableMetal.2 == 0,
            "unknown table ID diverged between CPU and Metal")

    let badHash = exactCPU(inputs: overflowInputs,
                           operations: [exactOp(UInt32(HM_EXACT_OP_MOVE), 2, 0)],
                           roots: [2], tableCells: [], badHash: true)
    require(badHash.0 == UInt32(HM_MODULE_SOURCE_HASH_MISMATCH) && badHash.2 == 0,
            "bad exact-program source hash accepted")

    let unknownOps = [exactOp(0xffff_ffff, 2, 0)]
    let unknownCPU = exactCPU(inputs: overflowInputs, operations: unknownOps,
                              roots: [2], tableCells: [])
    let unknownMetal = exactMetal(device: device, pipeline: pipeline,
                                  inputs: overflowInputs, operations: unknownOps,
                                  roots: [2], tableCells: [])
    require(unknownCPU.0 == UInt32(HM_MODULE_UNKNOWN_ID) && unknownCPU.2 == 0 &&
            unknownMetal.0 == UInt32(HM_MODULE_UNKNOWN_ID) && unknownMetal.2 == 0,
            "unknown exact opcode accepted")
}

func runCircuitContractTests() {
    require(HM_RunCContractLayoutTests() == 0, "C arm64 ABI layout/constants")
    require(MemoryLayout<HMModuleStatus>.size == 4 &&
            MemoryLayout<HMModuleStatus>.alignment == 4,
            "Swift status width/signedness")
    require(MemoryLayout<HMTableViewV1>.size == 24 &&
            MemoryLayout<HMTableViewV1>.alignment == 8 &&
            MemoryLayout<HMTableViewV1>.offset(of: \HMTableViewV1.cells) == 16,
            "Swift HMTableViewV1 layout")
    require(MemoryLayout<HMModuleEventV1>.size == 48 &&
            MemoryLayout<HMModuleEventV1>.offset(of: \HMModuleEventV1.payload) == 32,
            "Swift HMModuleEventV1 layout")
    require(MemoryLayout<HMModuleInputV1>.size == 112 &&
            MemoryLayout<HMModuleInputV1>.alignment == 8 &&
            MemoryLayout<HMModuleInputV1>.offset(of: \HMModuleInputV1.inputs) == 80 &&
            MemoryLayout<HMModuleInputV1>.offset(of: \HMModuleInputV1.input_events) == 104,
            "Swift HMModuleInputV1 layout")
    require(MemoryLayout<HMStateDeltaV1>.size == 20 &&
            MemoryLayout<HMModuleResultV1>.size == 80 &&
            MemoryLayout<HMModuleResultV1>.offset(of: \HMModuleResultV1.outputs) == 56,
            "Swift result/delta layout")
    require(MemoryLayout<HMExactOpV1>.size == 32 &&
            MemoryLayout<HMExactProgramV1>.size == 56 &&
            MemoryLayout<HMExactTableDescriptorV1>.size == 20 &&
            MemoryLayout<HMExactDispatchV1>.size == 72,
            "Swift exact-program layout")
    require(MemoryLayout<HMWorldSnapshotV1>.size == 56 &&
            MemoryLayout<HMDrawPrimitiveV1>.size == 72,
            "Swift world/render layout")
    require(UInt32(HM_MODULE_EXACT) == 0 && UInt32(HM_MODULE_PARTIAL_RESULT) == 12 &&
            UInt32(HM_EXACT_OP_TABLE_READ_I32) == 11,
            "Swift numeric registry values")

    expectInputRejection("input count", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.input_count = $0.input_capacity + 1
    }
    expectInputRejection("state count", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.state_count = $0.state_capacity + 1
    }
    expectInputRejection("table count", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.table_count = $0.table_capacity + 1
    }
    expectInputRejection("input-event count", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.input_event_count = $0.input_event_capacity + 1
    }
    expectInputRejection("requested output count", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.output_count = $0.output_capacity + 1
    }
    expectInputRejection("table length", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        let table = UnsafeMutablePointer(mutating: $0.tables)!
        table.pointee.length = table.pointee.capacity + 1
    }
    expectInputRejection("null inputs", UInt32(HM_MODULE_MALFORMED_SPAN)) { $0.inputs = nil }
    expectInputRejection("null state", UInt32(HM_MODULE_MALFORMED_SPAN)) { $0.state_before = nil }
    expectInputRejection("null tables", UInt32(HM_MODULE_MALFORMED_SPAN)) { $0.tables = nil }
    expectInputRejection("null input events", UInt32(HM_MODULE_MALFORMED_SPAN)) { $0.input_events = nil }
    expectInputRejection("null table cells", UInt32(HM_MODULE_MALFORMED_SPAN)) {
        UnsafeMutablePointer(mutating: $0.tables)!.pointee.cells = nil
    }
    expectInputRejection("ABI version", UInt32(HM_MODULE_INVALID_ABI)) { $0.abi_version += 1 }
    expectInputRejection("program version", UInt32(HM_MODULE_INVALID_ABI)) { $0.program_version += 1 }
    expectInputRejection("unknown module", UInt32(HM_MODULE_UNKNOWN_ID)) { $0.module_id = 0xffff_ffff }
    expectInputRejection("bad source hash", UInt32(HM_MODULE_SOURCE_HASH_MISMATCH)) { $0.source_hash ^= 1 }
    expectInputRejection("unknown table", UInt32(HM_MODULE_UNKNOWN_ID)) {
        UnsafeMutablePointer(mutating: $0.tables)!.pointee.table_id = 0xffff_ffff
    }
    expectInputRejection("unknown input event", UInt32(HM_MODULE_UNKNOWN_ID)) {
        UnsafeMutablePointer(mutating: $0.input_events)!.pointee.event_id = 0xffff_ffff
    }
    expectInputRejection("oversized event payload", UInt32(HM_MODULE_MALFORMED_SPAN)) {
        UnsafeMutablePointer(mutating: $0.input_events)!.pointee.payload_count = 5
    }

    expectResultRejection("output count", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.output_count = $0.output_capacity + 1
    }
    expectResultRejection("delta count", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.state_delta_count = $0.state_delta_capacity + 1
    }
    expectResultRejection("event count", UInt32(HM_MODULE_CAPACITY_EXCEEDED)) {
        $0.event_count = $0.event_capacity + 1
    }
    expectResultRejection("null outputs", UInt32(HM_MODULE_MALFORMED_SPAN)) { $0.outputs = nil }
    expectResultRejection("null deltas", UInt32(HM_MODULE_MALFORMED_SPAN)) { $0.state_deltas = nil }
    expectResultRejection("null events", UInt32(HM_MODULE_MALFORMED_SPAN)) { $0.events = nil }
    expectResultRejection("partial exact output", UInt32(HM_MODULE_PARTIAL_RESULT)) { $0.output_count = 1 }
    expectResultRejection("partial error output", UInt32(HM_MODULE_PARTIAL_RESULT)) {
        $0.status = UInt32(HM_MODULE_EXECUTION_ERROR)
    }
    expectResultRejection("duplicate delta", UInt32(HM_MODULE_INVALID_ORDER)) {
        $0.state_deltas![1] = $0.state_deltas![0]
    }
    expectResultRejection("out-of-order delta", UInt32(HM_MODULE_INVALID_ORDER)) {
        swap(&$0.state_deltas![0], &$0.state_deltas![1])
    }
    expectResultRejection("out-of-order event", UInt32(HM_MODULE_INVALID_ORDER)) {
        swap(&$0.events![0], &$0.events![1])
    }
    expectResultRejection("unknown world cell", UInt32(HM_MODULE_UNKNOWN_ID)) {
        $0.state_deltas![0].cell_id = 0xffff_ffff
    }
    expectResultRejection("unknown event", UInt32(HM_MODULE_UNKNOWN_ID)) {
        $0.events![0].event_id = 0xffff_ffff
    }
    expectResultRejection("stale result hash", UInt32(HM_MODULE_SOURCE_HASH_MISMATCH)) {
        $0.source_hash ^= 1
    }

    canonicalFixture()
    numericRegistryFixture()
    canonicalAuxiliaryRecords()
    exactIntegerConformance()
    print("CircuitModuleV1 contracts: C/Swift arm64 layouts, canonical fixtures, all named adversarial rejections, exact CPU/Metal edge vectors")
}
