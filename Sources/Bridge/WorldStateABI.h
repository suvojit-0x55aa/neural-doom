#ifndef HM_WORLD_STATE_ABI_H
#define HM_WORLD_STATE_ABI_H

#include <stddef.h>
#include <stdint.h>

#define HM_WORLD_SNAPSHOT_ABI_VERSION 1u
#define HM_WORLD_SCHEMA_VERSION 1u

typedef uint32_t HMWorldArrayID;
enum {
    HM_WORLD_ARRAY_INVALID = 0,
    HM_WORLD_ARRAY_SCALARS = 0x00080001u,
    HM_WORLD_ARRAY_PLAYERS = 0x00080002u,
    HM_WORLD_ARRAY_THINGS = 0x00080003u,
    HM_WORLD_ARRAY_THINKERS = 0x00080004u,
    HM_WORLD_ARRAY_SECTORS = 0x00080005u,
    HM_WORLD_ARRAY_LINES = 0x00080006u,
    HM_WORLD_ARRAY_PSPRITES = 0x00080007u,
    HM_WORLD_ARRAY_BLOCK_LINKS = 0x00080008u,
    HM_WORLD_ARRAY_PLAYER_AMMO = 0x00080009u,
    HM_WORLD_ARRAY_PLAYER_MAX_AMMO = 0x0008000au,
    HM_WORLD_ARRAY_PLAYER_WEAPONS = 0x0008000bu,
    HM_WORLD_ARRAY_PLAYER_POWERS = 0x0008000cu,
    HM_WORLD_ARRAY_PLAYER_CARDS = 0x0008000du,
    HM_WORLD_ARRAY_PLAYER_FRAGS = 0x0008000eu,
    HM_WORLD_ARRAY_SECTOR_MOVERS = 0x0008000fu,
    HM_WORLD_ARRAY_RNG = 0x00080010u,
    HM_WORLD_ARRAY_TRANSITIONS = 0x00080011u,
    HM_WORLD_ARRAY_HUD = 0x00090001u,
    HM_WORLD_ARRAY_AUTOMAP = 0x00090002u,
    HM_WORLD_ARRAY_AUTOMAP_MARKS = 0x00090003u,
    HM_WORLD_ARRAY_RENDERER = 0x000a0001u,
    HM_WORLD_ARRAY_RENDER_SOLIDSEGS = 0x000a0002u,
    HM_WORLD_ARRAY_RENDER_DRAWSEGS = 0x000a0003u,
    HM_WORLD_ARRAY_RENDER_VISPLANES = 0x000a0004u,
    HM_WORLD_ARRAY_RENDER_OPENINGS = 0x000a0005u,
    HM_WORLD_ARRAY_RENDER_VISSPRITES = 0x000a0006u,
    HM_WORLD_ARRAY_FRAMEBUFFER = 0x000b0001u,
    HM_WORLD_ARRAY_FRAMEBUFFER_TILES = 0x000b0002u
};

// Cell IDs are scoped by array ID. Adding meaning to a reserved value requires
// a world-schema version bump; aliases and discovery-order assignment are not
// permitted.
typedef uint32_t HMWorldCellID;
enum {
    HM_WORLD_CELL_INVALID = 0,

    HM_SCALAR_GAME_SKILL = 1,
    HM_SCALAR_EPISODE = 2,
    HM_SCALAR_MAP = 3,
    HM_SCALAR_GAME_STATE = 4,
    HM_SCALAR_GAME_ACTION = 5,
    HM_SCALAR_LEVEL_TIME = 6,
    HM_SCALAR_TOTAL_KILLS = 7,
    HM_SCALAR_TOTAL_ITEMS = 8,
    HM_SCALAR_TOTAL_SECRETS = 9,
    HM_SCALAR_RNG_INDEX = 10,
    HM_SCALAR_NEXT_THING_ID = 11,
    HM_SCALAR_PAUSED = 12,

    HM_PLAYER_X = 1,
    HM_PLAYER_Y = 2,
    HM_PLAYER_Z = 3,
    HM_PLAYER_ANGLE = 4,
    HM_PLAYER_MOM_X = 5,
    HM_PLAYER_MOM_Y = 6,
    HM_PLAYER_MOM_Z = 7,
    HM_PLAYER_FLOOR_Z = 8,
    HM_PLAYER_CEILING_Z = 9,
    HM_PLAYER_SUBSECTOR = 10,
    HM_PLAYER_HEALTH = 11,
    HM_PLAYER_ARMOR = 12,
    HM_PLAYER_READY_WEAPON = 13,
    HM_PLAYER_PENDING_WEAPON = 14,
    HM_PLAYER_REFIRE = 15,
    HM_PLAYER_FLAGS = 16,
    HM_PLAYER_ANIMATION_INTENT = 17,
    HM_PLAYER_STATE = 18,
    HM_PLAYER_VIEW_Z = 19,
    HM_PLAYER_VIEW_HEIGHT = 20,
    HM_PLAYER_DELTA_VIEW_HEIGHT = 21,
    HM_PLAYER_BOB = 22,
    HM_PLAYER_CHEATS = 23,
    HM_PLAYER_KILL_COUNT = 24,
    HM_PLAYER_ITEM_COUNT = 25,
    HM_PLAYER_SECRET_COUNT = 26,
    HM_PLAYER_DAMAGE_COUNT = 27,
    HM_PLAYER_BONUS_COUNT = 28,
    HM_PLAYER_ATTACKER_SLOT = 29,
    HM_PLAYER_EXTRA_LIGHT = 30,
    HM_PLAYER_FIXED_COLORMAP = 31,
    HM_PLAYER_COLORMAP = 32,
    HM_PLAYER_USE_DOWN = 33,
    HM_PLAYER_ATTACK_DOWN = 34,
    HM_PLAYER_MESSAGE_ID = 35,
    HM_PLAYER_DID_SECRET = 36,
    HM_PLAYER_BACKPACK = 37,

    HM_THING_STABLE_ID = 1,
    HM_THING_TYPE = 2,
    HM_THING_X = 3,
    HM_THING_Y = 4,
    HM_THING_Z = 5,
    HM_THING_ANGLE = 6,
    HM_THING_MOM_X = 7,
    HM_THING_MOM_Y = 8,
    HM_THING_MOM_Z = 9,
    HM_THING_RADIUS = 10,
    HM_THING_HEIGHT = 11,
    HM_THING_FLOOR_Z = 12,
    HM_THING_CEILING_Z = 13,
    HM_THING_HEALTH = 14,
    HM_THING_STATE = 15,
    HM_THING_TICS = 16,
    HM_THING_FLAGS = 17,
    HM_THING_TARGET_SLOT = 18,
    HM_THING_SUBSECTOR = 19,
    HM_THING_BLOCK_LINK = 20,
    HM_THING_SPRITE = 21,
    HM_THING_FRAME = 22,
    HM_THING_REACTION_TIME = 23,
    HM_THING_THRESHOLD = 24,
    HM_THING_LAST_LOOK = 25,
    HM_THING_MOVE_DIRECTION = 26,
    HM_THING_MOVE_COUNT = 27,
    HM_THING_SPECIAL = 28,
    HM_THING_PLAYER_SLOT = 29,
    HM_THING_SPAWN_X = 30,
    HM_THING_SPAWN_Y = 31,
    HM_THING_SPAWN_ANGLE = 32,
    HM_THING_SPAWN_TYPE = 33,
    HM_THING_SPAWN_OPTIONS = 34,
    HM_THING_VALID_COUNT = 35,

    HM_THINKER_KIND = 1,
    HM_THINKER_ACTIVE = 2,
    HM_THINKER_PREVIOUS_SLOT = 3,
    HM_THINKER_NEXT_SLOT = 4,
    HM_THINKER_OWNER_SLOT = 5,
    HM_THINKER_GENERATION = 6,
    HM_THINKER_FUNCTION = 7,
    HM_THINKER_LAZY_REMOVE = 8,
    HM_THINKER_ORDER = 9,

    HM_SECTOR_FLOOR_HEIGHT = 1,
    HM_SECTOR_CEILING_HEIGHT = 2,
    HM_SECTOR_LIGHT_LEVEL = 3,
    HM_SECTOR_SPECIAL = 4,
    HM_SECTOR_TAG = 5,
    HM_SECTOR_MOVER_SLOT = 6,
    HM_SECTOR_FLOOR_PIC = 7,
    HM_SECTOR_CEILING_PIC = 8,
    HM_SECTOR_SOUND_TARGET_SLOT = 9,
    HM_SECTOR_VALID_COUNT = 10,
    HM_SECTOR_THING_HEAD_SLOT = 11,
    HM_SECTOR_LINE_OFFSET = 12,
    HM_SECTOR_LINE_COUNT = 13,

    HM_LINE_FLAGS = 1,
    HM_LINE_SPECIAL = 2,
    HM_LINE_TAG = 3,
    HM_LINE_FRONT_SECTOR = 4,
    HM_LINE_BACK_SECTOR = 5,
    HM_LINE_VALID_COUNT = 6,
    HM_LINE_VERTEX_1 = 7,
    HM_LINE_VERTEX_2 = 8,
    HM_LINE_DELTA_X = 9,
    HM_LINE_DELTA_Y = 10,
    HM_LINE_SIDE_1 = 11,
    HM_LINE_SIDE_2 = 12,
    HM_LINE_BOUND_LEFT = 13,
    HM_LINE_BOUND_RIGHT = 14,
    HM_LINE_BOUND_BOTTOM = 15,
    HM_LINE_BOUND_TOP = 16,

    HM_PSPRITE_STATE = 1,
    HM_PSPRITE_TICS = 2,
    HM_PSPRITE_SCREEN_X = 3,
    HM_PSPRITE_SCREEN_Y = 4,

    HM_BLOCK_LINK_BLOCK_INDEX = 1,
    HM_BLOCK_LINK_PREVIOUS_SLOT = 2,
    HM_BLOCK_LINK_NEXT_SLOT = 3,
    HM_BLOCK_LINK_GENERATION = 4,

    HM_VALUE_CURRENT = 1,
    HM_VALUE_LIMIT = 2,
    HM_VALUE_OWNED = 3,
    HM_VALUE_TICS = 4,

    HM_SECTOR_MOVER_TYPE = 1,
    HM_SECTOR_MOVER_STATUS = 2,
    HM_SECTOR_MOVER_SECTOR = 3,
    HM_SECTOR_MOVER_DIRECTION = 4,
    HM_SECTOR_MOVER_SPEED = 5,
    HM_SECTOR_MOVER_DESTINATION = 6,
    HM_SECTOR_MOVER_CRUSH = 7,
    HM_SECTOR_MOVER_WAIT = 8,
    HM_SECTOR_MOVER_COUNT = 9,
    HM_SECTOR_MOVER_TEXTURE = 10,
    HM_SECTOR_MOVER_SPECIAL = 11,
    HM_SECTOR_MOVER_TAG = 12,
    HM_SECTOR_MOVER_SOURCE_LINE = 13,

    HM_RNG_INDEX = 1,
    HM_RNG_STREAM = 2,

    HM_TRANSITION_ACTION = 1,
    HM_TRANSITION_SKILL = 2,
    HM_TRANSITION_EPISODE = 3,
    HM_TRANSITION_MAP = 4,
    HM_TRANSITION_SECRET = 5,
    HM_TRANSITION_SAVE_SLOT = 6,

    HM_HUD_MESSAGE_TICS = 1,
    HM_HUD_PALETTE = 2,
    HM_HUD_FACE_STATE = 3,
    HM_HUD_REFRESH = 4,
    HM_HUD_CHAT_STATE = 5,
    HM_HUD_MESSAGE_ID = 6,
    HM_HUD_CROSSHAIR = 7,

    HM_AUTOMAP_ACTIVE = 1,
    HM_AUTOMAP_FOLLOW = 2,
    HM_AUTOMAP_CENTER_X = 3,
    HM_AUTOMAP_CENTER_Y = 4,
    HM_AUTOMAP_SCALE = 5,
    HM_AUTOMAP_PAN_X = 6,
    HM_AUTOMAP_PAN_Y = 7,
    HM_AUTOMAP_MARK_COUNT = 8,

    HM_AUTOMAP_MARK_X = 1,
    HM_AUTOMAP_MARK_Y = 2,
    HM_AUTOMAP_MARK_ACTIVE = 3,

    HM_RENDER_VIEW_X = 1,
    HM_RENDER_VIEW_Y = 2,
    HM_RENDER_VIEW_Z = 3,
    HM_RENDER_VIEW_ANGLE = 4,
    HM_RENDER_VALID_COUNT = 5,
    HM_RENDER_VIEW_COS = 6,
    HM_RENDER_VIEW_SIN = 7,
    HM_RENDER_CLIP_ANGLE = 8,
    HM_RENDER_DETAIL_SHIFT = 9,
    HM_RENDER_EXTRA_LIGHT = 10,
    HM_RENDER_FIXED_COLORMAP = 11,

    HM_RENDER_RECORD_VALUE_0 = 1,
    HM_RENDER_RECORD_VALUE_1 = 2,
    HM_RENDER_RECORD_VALUE_2 = 3,
    HM_RENDER_RECORD_VALUE_3 = 4,
    HM_RENDER_RECORD_VALUE_4 = 5,
    HM_RENDER_RECORD_VALUE_5 = 6,
    HM_RENDER_RECORD_VALUE_6 = 7,
    HM_RENDER_RECORD_VALUE_7 = 8,

    HM_FRAMEBUFFER_PALETTE_INDEX = 1,
    HM_FRAMEBUFFER_DIRTY = 2,
    HM_FRAMEBUFFER_GENERATION = 3
};

// Pointer-free header of a canonical little-endian snapshot blob. Offsets are
// 32-bit word offsets from the first byte of this header.
typedef struct {
    uint32_t abi_version;
    uint32_t schema_version;
    uint64_t tic_id;
    uint64_t source_hash;
    uint64_t map_fingerprint;
    uint32_t scalar_count;
    uint32_t array_count;
    uint32_t array_directory_offset;
    uint32_t data_offset;
    uint32_t word_count;
    uint32_t reserved;
} HMWorldSnapshotV1;

typedef struct {
    uint32_t array_id;
    uint32_t element_count;
    uint32_t element_capacity;
    uint32_t cell_count;
    uint32_t data_offset;
    uint32_t reserved;
} HMWorldArrayV1;

typedef struct {
    uint32_t array_id;
    uint32_t element_index;
    uint32_t cell_id;
    int32_t value;
} HMWorldCellV1;

int HM_IsKnownWorldArrayIDV1(uint32_t value);
int HM_IsKnownWorldCellIDV1(uint32_t array_id, uint32_t value);
int HM_ValidateWorldSnapshotV1(const HMWorldSnapshotV1 *snapshot,
                              const HMWorldArrayV1 *arrays,
                              uint32_t array_capacity,
                              const HMWorldCellV1 *cells,
                              uint32_t cell_count,
                              uint32_t cell_capacity);
size_t HM_CanonicalWorldSnapshotSizeV1(const HMWorldSnapshotV1 *snapshot,
                                       const HMWorldArrayV1 *arrays,
                                       uint32_t array_capacity,
                                       const HMWorldCellV1 *cells,
                                       uint32_t cell_count,
                                       uint32_t cell_capacity);
size_t HM_SerializeWorldSnapshotV1(const HMWorldSnapshotV1 *snapshot,
                                   const HMWorldArrayV1 *arrays,
                                   uint32_t array_capacity,
                                   const HMWorldCellV1 *cells,
                                   uint32_t cell_count,
                                   uint32_t cell_capacity,
                                   uint8_t *destination,
                                   size_t capacity);
size_t HM_SerializeWorldSnapshotHeaderV1(const HMWorldSnapshotV1 *snapshot,
                                         uint8_t *destination,
                                         size_t capacity);

#endif
