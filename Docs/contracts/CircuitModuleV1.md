# CircuitModuleV1 contract

`CircuitModuleV1` is the frozen envelope for all modules added after the two command graphs. The C declarations in `Sources/Bridge/CircuitModuleABI.h`, `CircuitIDs.h`, `WorldStateABI.h`, and `RenderStreamABI.h` are normative. `registry-v1.json` is the machine-readable numeric registry.

## Memory ownership and capacities

The caller owns every pointer and allocation. A callee may read `inputs`, `state_before`, `tables`, and `input_events`; it may write only the result spans. Counts are live elements and capacities are allocated elements. Input/state/table/prior-event and required-output spans carry count/capacity pairs. State-delta and output-event spans are variable length and carry caller capacities. Each `HMTableViewV1` also carries its own length/capacity.

The caller initializes the result identity, pointers, and capacities. A successful callee returns `exact`, the required output count, and bounded delta/event counts. `HM_FinalizeModuleResultV1` accepts data only when:

- ABI/program/encoding versions, module ID, tic ID, and source hash match;
- every count is within capacity and every nonzero-capacity span has a pointer;
- table IDs are known, strictly increasing, and each length is within capacity;
- deltas are strictly increasing by `(array_id, element_index, cell_id)`;
- events are strictly increasing by `(phase, emitter_slot, local_sequence)`;
- all array/cell/event IDs and payload lengths are valid; and
- an exact result contains the complete required output span.

Every validation or evaluation failure is transactional: `output_count`, `state_delta_count`, and `event_count` become zero. This includes unsupported domains, capacity errors, execution errors, parity mismatches, unknown versions/IDs, stale hashes, malformed spans, duplicate/out-of-order records, table overreads, integer overflow, and partial results. Buffer bytes are not a commit signal; counts plus `exact` are.

Capacities are intentionally caller- and manifest-supplied rather than global constants. A later module manifest must freeze its maxima and test full and capacity+1 cases. Changing a maximum or accepted domain changes the manifest/program version and source hash.

## Canonical records

`HMWorldSnapshotV1` is a pointer-free header for a little-endian word blob. Array directory and data locations are 32-bit word offsets from the header. Canonical blobs pack the 14-word header, six-word array records, then four-word cell records without gaps. An array's `cell_count` is its total number of cell records, and its `data_offset` identifies the first one. Array IDs are strictly increasing; cells are strictly ordered by array ID, element index, then cell ID. The whole-snapshot validator rejects unknown IDs, count/capacity errors, null runtime spans, nonzero reserved fields, bad offsets, duplicate/out-of-order cells, and element indices outside the live element count. Runtime bridges may expose bounded pointers, but pointers never enter a snapshot, fixture, event, primitive, serialization, or hash.

`HMModuleEventV1` is 48 bytes. It carries a stable phase/event ID, emitter slot, local sequence, source/target handles, flags, and up to four signed payload words. Event order is total and independent of worker completion order.

`HMDrawPrimitiveV1` is 72 bytes. It carries a stable primitive ID, sequence/source slot, clip rectangle, table handle/resource index, and eight signed arguments. Primitive-specific argument meanings are versioned; it never carries a framebuffer or resource pointer.

On arm64 the other frozen layouts are: `HMTableViewV1` 24 bytes/alignment 8, `HMModuleInputV1` 112/8, `HMStateDeltaV1` 20/4, `HMModuleResultV1` 80/8, `HMExactOpV1` 32/4, `HMExactProgramV1` 56/8, and `HMWorldSnapshotV1` 56/8. C and Swift tests assert sizes, alignments, offsets, unsigned status width, and every published enum boundary.

## Exact encodings

The existing locomotion and stage-2 command manifests stay at ABI 1 and are defined as `fp32-exact-v1`. Their existing domain validators are the checked proof that every input and intermediate integer is exactly representable in binary32. Their graph meanings, operation/layer IDs, roots, tables, and accepted domains are unchanged.

Future programs use `exact-i32-u32-v1` (`HM_EXACT_INTEGER_ENCODING_V1`). Registers and table cells are raw 32-bit words. Opcode semantics are:

| Opcode | Semantics |
|---|---|
| move / constant | Copy raw bits or the immediate's raw bits. |
| add-i32 / sub-i32 | Signed arithmetic in 64 bits; reject outside `INT32_MIN...INT32_MAX`. |
| fixed-mul-16.16 | Signed 64-bit product divided by 65536 with arithmetic-floor semantics; reject an unrepresentable result. |
| fixed-div-16.16 | Signed `(a * 65536) / b`, truncating toward zero; reject zero divisor or unrepresentable result. |
| angle-add-u32 | Modulo-2^32 unsigned addition, including immediate bits. |
| compare-lt-i32 / compare-equal-bits | Produce exactly 0 or 1. |
| gate | Return the first operand's bits when the second is nonzero, otherwise zero. |
| table-read-i32 | Load raw table-cell bits; reject unknown table IDs as `unknown-id`, and known but absent tables or out-of-range indices as `table-bounds`. |

Operations write consecutive registers after immutable inputs, may read only earlier registers, and carry zero flags/reserved words in version 1. CPU and Metal execute the same record without Float conversion. `CircuitExactV1.msl` returns a status and output count; it zeros the count before evaluation so overflow, table bounds, invalid opcode/order, division failure, or incomplete roots cannot partly commit.

The Metal dispatch carries live counts and caller capacities for inputs, operations, table descriptors, flattened table cells, output-register roots, scratch registers, outputs, and status words. Before encoding, the host rejects a status span shorter than the fixed two-word result and initializes those words to `execution-error, 0`; the shader validates every remaining span and every table descriptor before reading inputs, operations, roots, or cells, or writing scratch and outputs.

## Serialization and hashing

Canonical integers are unsigned little-endian words; signed values contribute the same 32 raw bits. Struct padding, pointer values, unused capacity contents, stored contents of inactive event payload slots, and host endianness never contribute; inactive payload slots serialize as zero. Tables and events must already be in canonical order. A structurally invalid result has no canonical serialization, even when all live counts are zero.

- Module input begins with ASCII `HMI1`, the fixed envelope fields, live input/state words, each table header plus live cells, then prior events.
- Module result begins with ASCII `HMR1`, the fixed result envelope, live output words, deltas, then events.
- Exact program hashing begins with `HMP1`, program versions/counts, every 32-byte operation, then output-register IDs. Its `source_hash` field and runtime pointers/capacities are excluded.
- Whole world snapshots, events, and draw primitives have field-wise serializers with no native padding.

FNV-1a-64 uses offset basis `14695981039346656037` and prime `1099511628211`. `Tests/Contracts/circuit-module-v1-fixture.json` freezes canonical input/result bytes and hashes. Any serialization change requires a new serialization/ABI version rather than replacing that fixture.

## Versioning

- Never renumber, alias, or reinterpret an assigned ID. Reserved range values remain invalid until a new registry version assigns them.
- Meaning/layout/order/hash changes require a new ABI, world/render schema, or serialization version.
- Opcode or integer semantic changes require a new exact-encoding/program ABI.
- Graph/root/table/domain/capacity changes require a new module manifest/program version and source hash even when the envelope ABI is unchanged.
- Readers reject unknown versions, IDs, encodings, status values, and nonzero reserved fields. There is no best-effort downgrade.
