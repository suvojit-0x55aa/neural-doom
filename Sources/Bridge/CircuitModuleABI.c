#include "CircuitModuleABI.h"
#include "RenderStreamABI.h"

#include <limits.h>
#include <string.h>

enum {
    HM_EVENT_SERIALIZED_SIZE_V1 = 48,
    HM_DELTA_SERIALIZED_SIZE_V1 = 20,
    HM_DRAW_SERIALIZED_SIZE_V1 = 72,
    HM_WORLD_HEADER_SERIALIZED_SIZE_V1 = 56
};

static void hm_put_u32(uint8_t **at, uint32_t value) {
    (*at)[0] = (uint8_t)value;
    (*at)[1] = (uint8_t)(value >> 8);
    (*at)[2] = (uint8_t)(value >> 16);
    (*at)[3] = (uint8_t)(value >> 24);
    *at += 4;
}

static void hm_put_u64(uint8_t **at, uint64_t value) {
    hm_put_u32(at, (uint32_t)value);
    hm_put_u32(at, (uint32_t)(value >> 32));
}

static int hm_add_size(size_t *total, size_t count, size_t width) {
    if (count > (SIZE_MAX - *total) / width) return 0;
    *total += count * width;
    return 1;
}

int HM_IsKnownModuleIDV1(uint32_t value) {
    switch (value) {
        case HM_MODULE_TIC_LOCOMOTION:
        case HM_MODULE_TIC_REMAINDER:
        case HM_MODULE_MOVEMENT_COLLISION:
        case HM_MODULE_INTERACTIONS_COMBAT:
        case HM_MODULE_THINKERS_AI:
        case HM_MODULE_WORLD_STATE:
        case HM_MODULE_HUD_AUTOMAP:
        case HM_MODULE_BSP_TRAVERSAL:
        case HM_MODULE_RASTERIZATION:
        case HM_MODULE_FRAME_COMPOSITION:
        case HM_MODULE_GAME_LOOP: return 1;
        default: return 0;
    }
}

int HM_IsKnownTableIDV1(uint32_t value) {
    switch (value) {
        case HM_TABLE_VERTICES:
        case HM_TABLE_LINEDEFS:
        case HM_TABLE_SIDEDEFS:
        case HM_TABLE_SECTORS:
        case HM_TABLE_NODES:
        case HM_TABLE_SUBSECTORS:
        case HM_TABLE_SEGS:
        case HM_TABLE_THINGS:
        case HM_TABLE_BLOCKMAP:
        case HM_TABLE_REJECT:
        case HM_TABLE_TEXTURES:
        case HM_TABLE_PATCH_COLUMNS:
        case HM_TABLE_FLATS:
        case HM_TABLE_SPRITES:
        case HM_TABLE_PLAYPAL:
        case HM_TABLE_COLORMAP:
        case HM_TABLE_TRANSLATIONS:
        case HM_TABLE_STATE_DEFINITIONS:
        case HM_TABLE_MOBJ_INFO:
        case HM_TABLE_WEAPON_INFO:
        case HM_TABLE_GAMEPLAY_RNG:
        case HM_TABLE_FONT_METADATA:
        case HM_TABLE_RENDER_TEXTURE_METADATA:
        case HM_TABLE_RENDER_SPRITE_METADATA: return 1;
        default: return 0;
    }
}

int HM_IsKnownEventIDV1(uint32_t value) {
    switch (value) {
        case HM_EVENT_LINE_CROSSED:
        case HM_EVENT_THING_CONTACT:
        case HM_EVENT_MOVEMENT_BLOCKED:
        case HM_EVENT_SOUND:
        case HM_EVENT_MUSIC:
        case HM_EVENT_SPAWN:
        case HM_EVENT_REMOVE:
        case HM_EVENT_DAMAGE:
        case HM_EVENT_PICKUP:
        case HM_EVENT_MESSAGE:
        case HM_EVENT_EXIT:
        case HM_EVENT_SECTOR_CHANGE:
        case HM_EVENT_COLLISION_INTENT:
        case HM_EVENT_ATTACK_INTENT:
        case HM_EVENT_SPAWN_INTENT:
        case HM_EVENT_REMOVE_INTENT:
        case HM_EVENT_SECTOR_ACTION_INTENT:
        case HM_EVENT_MAP_TRANSITION:
        case HM_EVENT_HOST_FILE_READ:
        case HM_EVENT_HOST_FILE_WRITE:
        case HM_EVENT_HOST_FILE_RENAME:
        case HM_EVENT_FRAME_READY:
        case HM_EVENT_RUNTIME_ERROR: return 1;
        default: return 0;
    }
}

int HM_IsKnownDrawPrimitiveIDV1(uint32_t value) {
    switch (value) {
        case HM_DRAW_PATCH:
        case HM_DRAW_TEXT_GLYPH:
        case HM_DRAW_LINE:
        case HM_DRAW_FILL:
        case HM_DRAW_WALL_COLUMN_RANGE:
        case HM_DRAW_PLANE_SPAN:
        case HM_DRAW_MASKED_SEG:
        case HM_DRAW_SPRITE:
        case HM_DRAW_SKY_SPAN:
        case HM_DRAW_CLEAR:
        case HM_DRAW_PAUSE_OVERLAY:
        case HM_DRAW_VIEW_BORDER:
        case HM_DRAW_MENU_OVERLAY:
        case HM_DRAW_INTERMISSION:
        case HM_DRAW_FINALE_PAGE:
        case HM_DRAW_WIPE: return 1;
        default: return 0;
    }
}

int HM_IsKnownWorldArrayIDV1(uint32_t value) {
    switch (value) {
        case HM_WORLD_ARRAY_SCALARS:
        case HM_WORLD_ARRAY_PLAYERS:
        case HM_WORLD_ARRAY_THINGS:
        case HM_WORLD_ARRAY_THINKERS:
        case HM_WORLD_ARRAY_SECTORS:
        case HM_WORLD_ARRAY_LINES:
        case HM_WORLD_ARRAY_PSPRITES:
        case HM_WORLD_ARRAY_BLOCK_LINKS:
        case HM_WORLD_ARRAY_PLAYER_AMMO:
        case HM_WORLD_ARRAY_PLAYER_MAX_AMMO:
        case HM_WORLD_ARRAY_PLAYER_WEAPONS:
        case HM_WORLD_ARRAY_PLAYER_POWERS:
        case HM_WORLD_ARRAY_PLAYER_CARDS:
        case HM_WORLD_ARRAY_PLAYER_FRAGS:
        case HM_WORLD_ARRAY_SECTOR_MOVERS:
        case HM_WORLD_ARRAY_RNG:
        case HM_WORLD_ARRAY_TRANSITIONS:
        case HM_WORLD_ARRAY_HUD:
        case HM_WORLD_ARRAY_AUTOMAP:
        case HM_WORLD_ARRAY_AUTOMAP_MARKS:
        case HM_WORLD_ARRAY_RENDERER:
        case HM_WORLD_ARRAY_RENDER_SOLIDSEGS:
        case HM_WORLD_ARRAY_RENDER_DRAWSEGS:
        case HM_WORLD_ARRAY_RENDER_VISPLANES:
        case HM_WORLD_ARRAY_RENDER_OPENINGS:
        case HM_WORLD_ARRAY_RENDER_VISSPRITES:
        case HM_WORLD_ARRAY_FRAMEBUFFER:
        case HM_WORLD_ARRAY_FRAMEBUFFER_TILES: return 1;
        default: return 0;
    }
}

int HM_IsKnownWorldCellIDV1(uint32_t array_id, uint32_t value) {
    if (value == 0) return 0;
    switch (array_id) {
        case HM_WORLD_ARRAY_SCALARS: return value <= HM_SCALAR_PAUSED;
        case HM_WORLD_ARRAY_PLAYERS: return value <= HM_PLAYER_BACKPACK;
        case HM_WORLD_ARRAY_THINGS: return value <= HM_THING_VALID_COUNT;
        case HM_WORLD_ARRAY_THINKERS: return value <= HM_THINKER_ORDER;
        case HM_WORLD_ARRAY_SECTORS: return value <= HM_SECTOR_LINE_COUNT;
        case HM_WORLD_ARRAY_LINES: return value <= HM_LINE_BOUND_TOP;
        case HM_WORLD_ARRAY_PSPRITES: return value <= HM_PSPRITE_SCREEN_Y;
        case HM_WORLD_ARRAY_BLOCK_LINKS: return value <= HM_BLOCK_LINK_GENERATION;
        case HM_WORLD_ARRAY_PLAYER_AMMO:
        case HM_WORLD_ARRAY_PLAYER_MAX_AMMO:
        case HM_WORLD_ARRAY_PLAYER_WEAPONS:
        case HM_WORLD_ARRAY_PLAYER_POWERS:
        case HM_WORLD_ARRAY_PLAYER_CARDS:
        case HM_WORLD_ARRAY_PLAYER_FRAGS: return value <= HM_VALUE_TICS;
        case HM_WORLD_ARRAY_SECTOR_MOVERS: return value <= HM_SECTOR_MOVER_SOURCE_LINE;
        case HM_WORLD_ARRAY_RNG: return value <= HM_RNG_STREAM;
        case HM_WORLD_ARRAY_TRANSITIONS: return value <= HM_TRANSITION_SAVE_SLOT;
        case HM_WORLD_ARRAY_HUD: return value <= HM_HUD_CROSSHAIR;
        case HM_WORLD_ARRAY_AUTOMAP: return value <= HM_AUTOMAP_MARK_COUNT;
        case HM_WORLD_ARRAY_AUTOMAP_MARKS: return value <= HM_AUTOMAP_MARK_ACTIVE;
        case HM_WORLD_ARRAY_RENDERER: return value <= HM_RENDER_FIXED_COLORMAP;
        case HM_WORLD_ARRAY_RENDER_SOLIDSEGS:
        case HM_WORLD_ARRAY_RENDER_DRAWSEGS:
        case HM_WORLD_ARRAY_RENDER_VISPLANES:
        case HM_WORLD_ARRAY_RENDER_OPENINGS:
        case HM_WORLD_ARRAY_RENDER_VISSPRITES: return value <= HM_RENDER_RECORD_VALUE_7;
        case HM_WORLD_ARRAY_FRAMEBUFFER:
        case HM_WORLD_ARRAY_FRAMEBUFFER_TILES: return value <= HM_FRAMEBUFFER_GENERATION;
        default: return 0;
    }
}

static int hm_event_before(const HMModuleEventV1 *a,
                           const HMModuleEventV1 *b) {
    if (a->phase != b->phase) return a->phase < b->phase;
    if (a->emitter_slot != b->emitter_slot)
        return a->emitter_slot < b->emitter_slot;
    return a->local_sequence < b->local_sequence;
}

static int hm_delta_before(const HMStateDeltaV1 *a,
                           const HMStateDeltaV1 *b) {
    if (a->array_id != b->array_id) return a->array_id < b->array_id;
    if (a->element_index != b->element_index)
        return a->element_index < b->element_index;
    return a->cell_id < b->cell_id;
}

static HMModuleStatus hm_validate_events(const HMModuleEventV1 *events,
                                         uint32_t count) {
    for (uint32_t i = 0; i < count; ++i) {
        const HMModuleEventV1 *event = &events[i];
        if (event->phase >= HM_PHASE_COUNT ||
            !HM_IsKnownEventIDV1(event->event_id))
            return HM_MODULE_UNKNOWN_ID;
        if (event->payload_count > 4) return HM_MODULE_MALFORMED_SPAN;
        if (i && !hm_event_before(&events[i - 1], event))
            return HM_MODULE_INVALID_ORDER;
    }
    return HM_MODULE_EXACT;
}

static HMModuleStatus hm_validate_result_record(const HMModuleResultV1 *result) {
    if (!result) return HM_MODULE_MALFORMED_SPAN;
    if (result->abi_version != HM_CIRCUIT_MODULE_ABI_VERSION)
        return HM_MODULE_INVALID_ABI;
    if (!HM_IsKnownModuleIDV1(result->module_id)) return HM_MODULE_UNKNOWN_ID;
    if (!result->source_hash) return HM_MODULE_SOURCE_HASH_MISMATCH;
    if (result->reserved) return HM_MODULE_MALFORMED_SPAN;
    if (result->status > HM_MODULE_PARTIAL_RESULT) return HM_MODULE_UNKNOWN_ID;
    if ((result->output_capacity && !result->outputs) ||
        (result->state_delta_capacity && !result->state_deltas) ||
        (result->event_capacity && !result->events))
        return HM_MODULE_MALFORMED_SPAN;
    if (result->output_count > result->output_capacity ||
        result->state_delta_count > result->state_delta_capacity ||
        result->event_count > result->event_capacity)
        return HM_MODULE_CAPACITY_EXCEEDED;
    if (result->status != HM_MODULE_EXACT &&
        (result->output_count || result->state_delta_count || result->event_count))
        return HM_MODULE_PARTIAL_RESULT;
    for (uint32_t i = 0; i < result->state_delta_count; ++i) {
        const HMStateDeltaV1 *delta = &result->state_deltas[i];
        if (!HM_IsKnownWorldArrayIDV1(delta->array_id) ||
            !HM_IsKnownWorldCellIDV1(delta->array_id, delta->cell_id))
            return HM_MODULE_UNKNOWN_ID;
        if (i && !hm_delta_before(&result->state_deltas[i - 1], delta))
            return HM_MODULE_INVALID_ORDER;
    }
    return hm_validate_events(result->events, result->event_count);
}

HMModuleStatus HM_ValidateModuleInputV1(const HMModuleInputV1 *input,
                                        uint32_t expected_module_id,
                                        uint64_t expected_source_hash) {
    if (!input) return HM_MODULE_MALFORMED_SPAN;
    if (input->abi_version != HM_CIRCUIT_MODULE_ABI_VERSION ||
        input->program_version != 1 ||
        (input->integer_encoding != HM_EXACT_INTEGER_ENCODING_V1 &&
         input->integer_encoding != HM_FP32_EXACT_ENCODING_V1))
        return HM_MODULE_INVALID_ABI;
    if (!HM_IsKnownModuleIDV1(input->module_id) ||
        !HM_IsKnownModuleIDV1(expected_module_id) ||
        input->module_id != expected_module_id)
        return HM_MODULE_UNKNOWN_ID;
    if (!input->source_hash || !expected_source_hash ||
        input->source_hash != expected_source_hash)
        return HM_MODULE_SOURCE_HASH_MISMATCH;
    if (input->input_count > input->input_capacity ||
        input->state_count > input->state_capacity ||
        input->table_count > input->table_capacity ||
        input->input_event_count > input->input_event_capacity ||
        input->output_count > input->output_capacity)
        return HM_MODULE_CAPACITY_EXCEEDED;
    if ((input->input_capacity && !input->inputs) ||
        (input->state_capacity && !input->state_before) ||
        (input->table_capacity && !input->tables) ||
        (input->input_event_capacity && !input->input_events))
        return HM_MODULE_MALFORMED_SPAN;
    for (uint32_t i = 0; i < input->table_count; ++i) {
        const HMTableViewV1 *table = &input->tables[i];
        if (!HM_IsKnownTableIDV1(table->table_id)) return HM_MODULE_UNKNOWN_ID;
        if (i && input->tables[i - 1].table_id >= table->table_id)
            return HM_MODULE_INVALID_ORDER;
        if (table->length > table->capacity) return HM_MODULE_CAPACITY_EXCEEDED;
        if ((table->capacity && !table->cells) || table->reserved)
            return HM_MODULE_MALFORMED_SPAN;
    }
    return hm_validate_events(input->input_events, input->input_event_count);
}

void HM_RejectModuleResultV1(HMModuleResultV1 *result,
                             HMModuleStatus status) {
    if (!result) return;
    result->status = status == HM_MODULE_EXACT ? HM_MODULE_EXECUTION_ERROR : status;
    result->output_count = 0;
    result->state_delta_count = 0;
    result->event_count = 0;
}

HMModuleStatus HM_FinalizeModuleResultV1(const HMModuleInputV1 *input,
                                         HMModuleResultV1 *result,
                                         uint32_t expected_module_id,
                                         uint64_t expected_source_hash) {
    HMModuleStatus status = HM_ValidateModuleInputV1(
        input, expected_module_id, expected_source_hash);
    if (!result) return status == HM_MODULE_EXACT ? HM_MODULE_MALFORMED_SPAN : status;
    if (status != HM_MODULE_EXACT) {
        HM_RejectModuleResultV1(result, status);
        return status;
    }
    status = hm_validate_result_record(result);
    if (status == HM_MODULE_EXACT && result->abi_version != input->abi_version)
        status = HM_MODULE_INVALID_ABI;
    else if (status == HM_MODULE_EXACT && result->module_id != input->module_id)
        status = HM_MODULE_UNKNOWN_ID;
    else if (status == HM_MODULE_EXACT && (result->tic_id != input->tic_id ||
             result->source_hash != input->source_hash))
        status = HM_MODULE_SOURCE_HASH_MISMATCH;
    else if (status == HM_MODULE_EXACT &&
             (result->output_capacity != input->output_capacity ||
             result->state_delta_capacity != input->state_delta_capacity ||
             result->event_capacity != input->event_capacity))
        status = HM_MODULE_MALFORMED_SPAN;
    else if (status == HM_MODULE_EXACT && result->status != HM_MODULE_EXACT)
        status = result->status;
    else if (status == HM_MODULE_EXACT && result->output_count != input->output_count) {
        status = HM_MODULE_PARTIAL_RESULT;
    }
    if (status != HM_MODULE_EXACT) HM_RejectModuleResultV1(result, status);
    return status;
}

uint64_t HM_HashBytesV1(const uint8_t *bytes, size_t count) {
    if (!bytes && count) return 0;
    uint64_t hash = UINT64_C(14695981039346656037);
    for (size_t i = 0; i < count; ++i) {
        hash ^= bytes[i];
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

size_t HM_SerializeModuleEventV1(const HMModuleEventV1 *event,
                                 uint8_t *destination,
                                 size_t capacity) {
    if (!event || !destination || capacity < HM_EVENT_SERIALIZED_SIZE_V1)
        return 0;
    if (event->phase >= HM_PHASE_COUNT ||
        !HM_IsKnownEventIDV1(event->event_id) || event->payload_count > 4)
        return 0;
    uint8_t *at = destination;
    hm_put_u32(&at, event->phase);
    hm_put_u32(&at, event->event_id);
    hm_put_u32(&at, event->emitter_slot);
    hm_put_u32(&at, event->local_sequence);
    hm_put_u32(&at, event->source_id);
    hm_put_u32(&at, event->target_id);
    hm_put_u32(&at, event->payload_count);
    hm_put_u32(&at, event->flags);
    for (uint32_t i = 0; i < 4; ++i)
        hm_put_u32(&at, i < event->payload_count ? (uint32_t)event->payload[i] : 0);
    return HM_EVENT_SERIALIZED_SIZE_V1;
}

size_t HM_CanonicalModuleInputSizeV1(const HMModuleInputV1 *input) {
    if (!input || HM_ValidateModuleInputV1(
                      input, input->module_id, input->source_hash) != HM_MODULE_EXACT)
        return 0;
    size_t total = 84;
    if (!hm_add_size(&total, input->input_count, 4) ||
        !hm_add_size(&total, input->state_count, 4))
        return 0;
    for (uint32_t i = 0; i < input->table_count; ++i) {
        if (!hm_add_size(&total, 1, 16) ||
            !hm_add_size(&total, input->tables[i].length, 4))
            return 0;
    }
    if (!hm_add_size(&total, input->input_event_count,
                     HM_EVENT_SERIALIZED_SIZE_V1))
        return 0;
    return total;
}

size_t HM_SerializeModuleInputV1(const HMModuleInputV1 *input,
                                 uint8_t *destination,
                                 size_t capacity) {
    size_t needed = HM_CanonicalModuleInputSizeV1(input);
    if (!needed || !destination || capacity < needed) return 0;
    uint8_t *at = destination;
    *at++ = 'H'; *at++ = 'M'; *at++ = 'I'; *at++ = '1';
    hm_put_u32(&at, input->abi_version);
    hm_put_u32(&at, input->program_version);
    hm_put_u32(&at, input->integer_encoding);
    hm_put_u32(&at, input->module_id);
    hm_put_u64(&at, input->tic_id);
    hm_put_u64(&at, input->source_hash);
    hm_put_u32(&at, input->input_count);
    hm_put_u32(&at, input->input_capacity);
    hm_put_u32(&at, input->state_count);
    hm_put_u32(&at, input->state_capacity);
    hm_put_u32(&at, input->table_count);
    hm_put_u32(&at, input->table_capacity);
    hm_put_u32(&at, input->input_event_count);
    hm_put_u32(&at, input->input_event_capacity);
    hm_put_u32(&at, input->output_count);
    hm_put_u32(&at, input->output_capacity);
    hm_put_u32(&at, input->state_delta_capacity);
    hm_put_u32(&at, input->event_capacity);
    for (uint32_t i = 0; i < input->input_count; ++i)
        hm_put_u32(&at, (uint32_t)input->inputs[i]);
    for (uint32_t i = 0; i < input->state_count; ++i)
        hm_put_u32(&at, (uint32_t)input->state_before[i]);
    for (uint32_t i = 0; i < input->table_count; ++i) {
        const HMTableViewV1 *table = &input->tables[i];
        hm_put_u32(&at, table->table_id);
        hm_put_u32(&at, table->length);
        hm_put_u32(&at, table->capacity);
        hm_put_u32(&at, table->reserved);
        for (uint32_t j = 0; j < table->length; ++j)
            hm_put_u32(&at, (uint32_t)table->cells[j]);
    }
    for (uint32_t i = 0; i < input->input_event_count; ++i) {
        HM_SerializeModuleEventV1(&input->input_events[i], at,
                                  HM_EVENT_SERIALIZED_SIZE_V1);
        at += HM_EVENT_SERIALIZED_SIZE_V1;
    }
    return needed;
}

size_t HM_CanonicalModuleResultSizeV1(const HMModuleResultV1 *result) {
    if (hm_validate_result_record(result) != HM_MODULE_EXACT)
        return 0;
    size_t total = 60;
    if (!hm_add_size(&total, result->output_count, 4) ||
        !hm_add_size(&total, result->state_delta_count,
                     HM_DELTA_SERIALIZED_SIZE_V1) ||
        !hm_add_size(&total, result->event_count,
                     HM_EVENT_SERIALIZED_SIZE_V1))
        return 0;
    return total;
}

size_t HM_SerializeModuleResultV1(const HMModuleResultV1 *result,
                                  uint8_t *destination,
                                  size_t capacity) {
    size_t needed = HM_CanonicalModuleResultSizeV1(result);
    if (!needed || !destination || capacity < needed) return 0;
    uint8_t *at = destination;
    *at++ = 'H'; *at++ = 'M'; *at++ = 'R'; *at++ = '1';
    hm_put_u32(&at, result->abi_version);
    hm_put_u32(&at, result->module_id);
    hm_put_u64(&at, result->tic_id);
    hm_put_u64(&at, result->source_hash);
    hm_put_u32(&at, result->status);
    hm_put_u32(&at, result->reserved);
    hm_put_u32(&at, result->output_count);
    hm_put_u32(&at, result->output_capacity);
    hm_put_u32(&at, result->state_delta_count);
    hm_put_u32(&at, result->state_delta_capacity);
    hm_put_u32(&at, result->event_count);
    hm_put_u32(&at, result->event_capacity);
    for (uint32_t i = 0; i < result->output_count; ++i)
        hm_put_u32(&at, (uint32_t)result->outputs[i]);
    for (uint32_t i = 0; i < result->state_delta_count; ++i) {
        const HMStateDeltaV1 *delta = &result->state_deltas[i];
        hm_put_u32(&at, delta->array_id);
        hm_put_u32(&at, delta->element_index);
        hm_put_u32(&at, delta->cell_id);
        hm_put_u32(&at, (uint32_t)delta->before);
        hm_put_u32(&at, (uint32_t)delta->after);
    }
    for (uint32_t i = 0; i < result->event_count; ++i) {
        HM_SerializeModuleEventV1(&result->events[i], at,
                                  HM_EVENT_SERIALIZED_SIZE_V1);
        at += HM_EVENT_SERIALIZED_SIZE_V1;
    }
    return needed;
}

size_t HM_SerializeWorldSnapshotHeaderV1(const HMWorldSnapshotV1 *snapshot,
                                         uint8_t *destination,
                                         size_t capacity) {
    if (!snapshot || !destination || capacity < HM_WORLD_HEADER_SERIALIZED_SIZE_V1 ||
        snapshot->abi_version != HM_WORLD_SNAPSHOT_ABI_VERSION ||
        snapshot->schema_version != HM_WORLD_SCHEMA_VERSION || !snapshot->source_hash ||
        snapshot->reserved || snapshot->array_directory_offset < 14u ||
        (uint64_t)snapshot->data_offset <
            (uint64_t)snapshot->array_directory_offset +
                (uint64_t)snapshot->array_count * 6u ||
        snapshot->word_count < snapshot->data_offset)
        return 0;
    uint8_t *at = destination;
    hm_put_u32(&at, snapshot->abi_version);
    hm_put_u32(&at, snapshot->schema_version);
    hm_put_u64(&at, snapshot->tic_id);
    hm_put_u64(&at, snapshot->source_hash);
    hm_put_u64(&at, snapshot->map_fingerprint);
    hm_put_u32(&at, snapshot->scalar_count);
    hm_put_u32(&at, snapshot->array_count);
    hm_put_u32(&at, snapshot->array_directory_offset);
    hm_put_u32(&at, snapshot->data_offset);
    hm_put_u32(&at, snapshot->word_count);
    hm_put_u32(&at, snapshot->reserved);
    return HM_WORLD_HEADER_SERIALIZED_SIZE_V1;
}

static int hm_world_cell_before(const HMWorldCellV1 *a,
                                const HMWorldCellV1 *b) {
    if (a->array_id != b->array_id) return a->array_id < b->array_id;
    if (a->element_index != b->element_index)
        return a->element_index < b->element_index;
    return a->cell_id < b->cell_id;
}

int HM_ValidateWorldSnapshotV1(const HMWorldSnapshotV1 *snapshot,
                              const HMWorldArrayV1 *arrays,
                              uint32_t array_capacity,
                              const HMWorldCellV1 *cells,
                              uint32_t cell_count,
                              uint32_t cell_capacity) {
    if (!snapshot || snapshot->abi_version != HM_WORLD_SNAPSHOT_ABI_VERSION ||
        snapshot->schema_version != HM_WORLD_SCHEMA_VERSION ||
        !snapshot->source_hash || snapshot->reserved ||
        snapshot->array_count > array_capacity || cell_count > cell_capacity ||
        (array_capacity && !arrays) || (cell_capacity && !cells))
        return 0;
    uint64_t directory_end = UINT64_C(14) + (uint64_t)snapshot->array_count * 6u;
    uint64_t data_end = directory_end + (uint64_t)cell_count * 4u;
    if (snapshot->array_directory_offset != 14u ||
        snapshot->data_offset != directory_end || snapshot->word_count != data_end)
        return 0;
    uint32_t cell_at = 0;
    uint32_t scalar_count = 0;
    uint64_t expected_data_offset = snapshot->data_offset;
    for (uint32_t i = 0; i < snapshot->array_count; ++i) {
        const HMWorldArrayV1 *array = &arrays[i];
        if (!HM_IsKnownWorldArrayIDV1(array->array_id) || array->reserved ||
            array->element_count > array->element_capacity ||
            (i && arrays[i - 1].array_id >= array->array_id) ||
            array->data_offset != expected_data_offset ||
            array->cell_count > cell_count - cell_at)
            return 0;
        for (uint32_t j = 0; j < array->cell_count; ++j) {
            const HMWorldCellV1 *cell = &cells[cell_at + j];
            if (cell->array_id != array->array_id ||
                cell->element_index >= array->element_count ||
                !HM_IsKnownWorldCellIDV1(cell->array_id, cell->cell_id) ||
                ((cell_at + j) && !hm_world_cell_before(&cells[cell_at + j - 1], cell)))
                return 0;
        }
        if (array->array_id == HM_WORLD_ARRAY_SCALARS)
            scalar_count = array->cell_count;
        cell_at += array->cell_count;
        expected_data_offset += (uint64_t)array->cell_count * 4u;
    }
    return cell_at == cell_count && scalar_count == snapshot->scalar_count &&
           expected_data_offset == snapshot->word_count;
}

size_t HM_CanonicalWorldSnapshotSizeV1(const HMWorldSnapshotV1 *snapshot,
                                       const HMWorldArrayV1 *arrays,
                                       uint32_t array_capacity,
                                       const HMWorldCellV1 *cells,
                                       uint32_t cell_count,
                                       uint32_t cell_capacity) {
    if (!HM_ValidateWorldSnapshotV1(snapshot, arrays, array_capacity, cells,
                                    cell_count, cell_capacity))
        return 0;
    size_t needed = (size_t)snapshot->word_count * 4u;
    return needed / 4u == snapshot->word_count ? needed : 0;
}

size_t HM_SerializeWorldSnapshotV1(const HMWorldSnapshotV1 *snapshot,
                                   const HMWorldArrayV1 *arrays,
                                   uint32_t array_capacity,
                                   const HMWorldCellV1 *cells,
                                   uint32_t cell_count,
                                   uint32_t cell_capacity,
                                   uint8_t *destination,
                                   size_t capacity) {
    size_t needed = HM_CanonicalWorldSnapshotSizeV1(
        snapshot, arrays, array_capacity, cells, cell_count, cell_capacity);
    if (!needed || !destination || capacity < needed) return 0;
    memset(destination, 0, needed);
    if (!HM_SerializeWorldSnapshotHeaderV1(snapshot, destination, needed)) return 0;
    uint8_t *at = destination + (size_t)snapshot->array_directory_offset * 4u;
    for (uint32_t i = 0; i < snapshot->array_count; ++i) {
        hm_put_u32(&at, arrays[i].array_id);
        hm_put_u32(&at, arrays[i].element_count);
        hm_put_u32(&at, arrays[i].element_capacity);
        hm_put_u32(&at, arrays[i].cell_count);
        hm_put_u32(&at, arrays[i].data_offset);
        hm_put_u32(&at, arrays[i].reserved);
    }
    uint32_t cell_at = 0;
    for (uint32_t i = 0; i < snapshot->array_count; ++i) {
        at = destination + (size_t)arrays[i].data_offset * 4u;
        for (uint32_t j = 0; j < arrays[i].cell_count; ++j) {
            const HMWorldCellV1 *cell = &cells[cell_at++];
            hm_put_u32(&at, cell->array_id);
            hm_put_u32(&at, cell->element_index);
            hm_put_u32(&at, cell->cell_id);
            hm_put_u32(&at, (uint32_t)cell->value);
        }
    }
    return needed;
}

size_t HM_SerializeDrawPrimitiveV1(const HMDrawPrimitiveV1 *primitive,
                                   uint8_t *destination,
                                   size_t capacity) {
    if (!primitive || !destination || capacity < HM_DRAW_SERIALIZED_SIZE_V1 ||
        !HM_IsKnownDrawPrimitiveIDV1(primitive->primitive_id) ||
        (primitive->resource_table_id &&
         !HM_IsKnownTableIDV1(primitive->resource_table_id)))
        return 0;
    uint8_t *at = destination;
    hm_put_u32(&at, primitive->primitive_id);
    hm_put_u32(&at, primitive->flags);
    hm_put_u32(&at, primitive->sequence);
    hm_put_u32(&at, primitive->source_slot);
    hm_put_u32(&at, (uint32_t)primitive->clip_left);
    hm_put_u32(&at, (uint32_t)primitive->clip_top);
    hm_put_u32(&at, (uint32_t)primitive->clip_right);
    hm_put_u32(&at, (uint32_t)primitive->clip_bottom);
    hm_put_u32(&at, primitive->resource_table_id);
    hm_put_u32(&at, primitive->resource_index);
    for (uint32_t i = 0; i < 8; ++i)
        hm_put_u32(&at, (uint32_t)primitive->argument[i]);
    return HM_DRAW_SERIALIZED_SIZE_V1;
}

static uint64_t hm_hash_u32(uint64_t hash, uint32_t value) {
    for (uint32_t shift = 0; shift < 32; shift += 8) {
        hash ^= (uint8_t)(value >> shift);
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

uint64_t HM_ExactProgramHashV1(const HMExactProgramV1 *program) {
    if (!program || program->operation_count > program->operation_capacity ||
        program->output_count > program->output_capacity ||
        (program->operation_count && !program->operations) ||
        (program->output_count && !program->output_registers))
        return 0;
    uint64_t hash = UINT64_C(14695981039346656037);
    hash = hm_hash_u32(hash, UINT32_C(0x31504d48)); // "HMP1"
    hash = hm_hash_u32(hash, program->abi_version);
    hash = hm_hash_u32(hash, program->integer_encoding);
    hash = hm_hash_u32(hash, program->input_count);
    hash = hm_hash_u32(hash, program->register_count);
    hash = hm_hash_u32(hash, program->operation_count);
    hash = hm_hash_u32(hash, program->output_count);
    for (uint32_t i = 0; i < program->operation_count; ++i) {
        const HMExactOpV1 *op = &program->operations[i];
        hash = hm_hash_u32(hash, op->opcode);
        hash = hm_hash_u32(hash, op->destination);
        hash = hm_hash_u32(hash, op->lhs);
        hash = hm_hash_u32(hash, op->rhs);
        hash = hm_hash_u32(hash, (uint32_t)op->immediate);
        hash = hm_hash_u32(hash, op->table_id);
        hash = hm_hash_u32(hash, op->flags);
        hash = hm_hash_u32(hash, op->reserved);
    }
    for (uint32_t i = 0; i < program->output_count; ++i)
        hash = hm_hash_u32(hash, program->output_registers[i]);
    return hash;
}

static HMModuleStatus hm_store_signed(int64_t value, uint32_t *destination) {
    if (value < INT32_MIN || value > INT32_MAX) return HM_MODULE_INTEGER_OVERFLOW;
    *destination = (uint32_t)(int32_t)value;
    return HM_MODULE_EXACT;
}

static const HMTableViewV1 *hm_find_table(const HMTableViewV1 *tables,
                                          uint32_t count,
                                          uint32_t table_id) {
    for (uint32_t i = 0; i < count; ++i)
        if (tables[i].table_id == table_id) return &tables[i];
    return 0;
}

HMModuleStatus HM_PrepareExactDispatchV1(const HMExactDispatchV1 *dispatch,
                                         uint32_t *status,
                                         uint32_t status_capacity) {
    if (status_capacity < 2u) return HM_MODULE_CAPACITY_EXCEEDED;
    if (!status) return HM_MODULE_MALFORMED_SPAN;
    status[0] = HM_MODULE_EXECUTION_ERROR;
    status[1] = 0;
    if (!dispatch) {
        status[0] = HM_MODULE_MALFORMED_SPAN;
        return status[0];
    }
    if (dispatch->status_capacity < 2u ||
        dispatch->status_capacity > status_capacity) {
        status[0] = HM_MODULE_CAPACITY_EXCEEDED;
        return status[0];
    }
    return HM_MODULE_EXACT;
}

HMModuleStatus HM_EvaluateExactProgramV1(const HMExactProgramV1 *program,
                                         const uint32_t *inputs,
                                         uint32_t input_count,
                                         const HMTableViewV1 *tables,
                                         uint32_t table_count,
                                         uint32_t *scratch,
                                         uint32_t scratch_capacity,
                                         uint32_t *outputs,
                                         uint32_t output_capacity,
                                         uint32_t *output_count) {
    if (output_count) *output_count = 0;
    if (!program || !output_count) return HM_MODULE_MALFORMED_SPAN;
    if (program->abi_version != HM_EXACT_PROGRAM_ABI_VERSION ||
        program->integer_encoding != HM_EXACT_INTEGER_ENCODING_V1)
        return HM_MODULE_INVALID_ABI;
    if (program->input_count != input_count || input_count > program->register_count ||
        program->register_count > HM_EXACT_MAX_REGISTERS_V1 ||
        program->register_count > scratch_capacity ||
        program->operation_count > program->operation_capacity ||
        program->output_count > program->output_capacity ||
        program->output_count > output_capacity)
        return HM_MODULE_CAPACITY_EXCEEDED;
    if ((input_count && !inputs) || (program->register_count && !scratch) ||
        (program->operation_count && !program->operations) ||
        (program->output_count && (!program->output_registers || !outputs)) ||
        (table_count && !tables))
        return HM_MODULE_MALFORMED_SPAN;
    if (outputs) memset(outputs, 0, (size_t)output_capacity * sizeof(*outputs));
    if (!program->source_hash || program->source_hash != HM_ExactProgramHashV1(program))
        return HM_MODULE_SOURCE_HASH_MISMATCH;
    for (uint32_t i = 0; i < table_count; ++i) {
        if (!HM_IsKnownTableIDV1(tables[i].table_id)) return HM_MODULE_UNKNOWN_ID;
        if (i && tables[i - 1].table_id >= tables[i].table_id)
            return HM_MODULE_INVALID_ORDER;
        if (tables[i].length > tables[i].capacity)
            return HM_MODULE_CAPACITY_EXCEEDED;
        if ((tables[i].capacity && !tables[i].cells) || tables[i].reserved)
            return HM_MODULE_MALFORMED_SPAN;
    }
    if (input_count)
        memcpy(scratch, inputs, (size_t)input_count * sizeof(*scratch));
    for (uint32_t i = 0; i < program->operation_count; ++i) {
        const HMExactOpV1 *op = &program->operations[i];
        uint32_t expected_destination = program->input_count + i;
        if (op->destination != expected_destination ||
            op->destination >= program->register_count || op->flags || op->reserved)
            return HM_MODULE_INVALID_ORDER;
        if (op->opcode != HM_EXACT_OP_CONSTANT && op->lhs >= op->destination)
            return HM_MODULE_INVALID_ORDER;
        if (op->opcode != HM_EXACT_OP_CONSTANT &&
            op->opcode != HM_EXACT_OP_MOVE &&
            op->opcode != HM_EXACT_OP_TABLE_READ_I32 &&
            op->rhs >= op->destination)
            return HM_MODULE_INVALID_ORDER;
        uint32_t a = op->opcode == HM_EXACT_OP_CONSTANT ? 0 : scratch[op->lhs];
        uint32_t b = (op->opcode == HM_EXACT_OP_CONSTANT ||
                      op->opcode == HM_EXACT_OP_MOVE ||
                      op->opcode == HM_EXACT_OP_TABLE_READ_I32)
                         ? 0 : scratch[op->rhs];
        HMModuleStatus status = HM_MODULE_EXACT;
        switch (op->opcode) {
            case HM_EXACT_OP_MOVE:
                scratch[op->destination] = a;
                break;
            case HM_EXACT_OP_CONSTANT:
                scratch[op->destination] = (uint32_t)op->immediate;
                break;
            case HM_EXACT_OP_ADD_I32:
                status = hm_store_signed((int64_t)(int32_t)a + (int64_t)(int32_t)b +
                                             (int64_t)op->immediate,
                                         &scratch[op->destination]);
                break;
            case HM_EXACT_OP_SUB_I32:
                status = hm_store_signed((int64_t)(int32_t)a - (int64_t)(int32_t)b +
                                             (int64_t)op->immediate,
                                         &scratch[op->destination]);
                break;
            case HM_EXACT_OP_FIXED_MUL_16_16: {
                int64_t product = (int64_t)(int32_t)a * (int64_t)(int32_t)b;
                int64_t value = product / INT64_C(65536);
                if (product < 0 && product % INT64_C(65536)) --value;
                status = hm_store_signed(value, &scratch[op->destination]);
                break;
            }
            case HM_EXACT_OP_FIXED_DIV_16_16: {
                int32_t divisor = (int32_t)b;
                if (!divisor) return HM_MODULE_EXECUTION_ERROR;
                int64_t value = ((int64_t)(int32_t)a * INT64_C(65536)) / divisor;
                status = hm_store_signed(value, &scratch[op->destination]);
                break;
            }
            case HM_EXACT_OP_ANGLE_ADD_U32:
                scratch[op->destination] = a + b + (uint32_t)op->immediate;
                break;
            case HM_EXACT_OP_COMPARE_LT_I32:
                scratch[op->destination] = (int32_t)a < (int32_t)b ? 1u : 0u;
                break;
            case HM_EXACT_OP_COMPARE_EQUAL_BITS:
                scratch[op->destination] = a == b ? 1u : 0u;
                break;
            case HM_EXACT_OP_GATE:
                scratch[op->destination] = b ? a : 0;
                break;
            case HM_EXACT_OP_TABLE_READ_I32: {
                if (!HM_IsKnownTableIDV1(op->table_id)) return HM_MODULE_UNKNOWN_ID;
                const HMTableViewV1 *table = hm_find_table(tables, table_count,
                                                          op->table_id);
                if (!table || a >= table->length) return HM_MODULE_TABLE_BOUNDS;
                scratch[op->destination] = (uint32_t)table->cells[a];
                break;
            }
            default: return HM_MODULE_UNKNOWN_ID;
        }
        if (status != HM_MODULE_EXACT) return status;
    }
    if (program->input_count + program->operation_count != program->register_count)
        return HM_MODULE_PARTIAL_RESULT;
    for (uint32_t i = 0; i < program->output_count; ++i) {
        uint32_t root = program->output_registers[i];
        if (root >= program->register_count) return HM_MODULE_INVALID_ORDER;
        outputs[i] = scratch[root];
    }
    *output_count = program->output_count;
    return HM_MODULE_EXACT;
}
