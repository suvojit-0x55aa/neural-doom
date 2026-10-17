#ifndef HM_MAP_TABLES_ABI_H
#define HM_MAP_TABLES_ABI_H

#include <stdint.h>

// MapTablesV1: bounded, pointer-free decode of a legal WAD map plus the WAD's
// render data into HMTableViewV1 cells (table IDs live in CircuitIDs.h and are
// not reinterpreted here). Every cell is a raw 32-bit word read as int32.
//
// Record layouts (cells per record). Indices replace every C pointer; -1 means
// "none". Fixed-point values are 16.16 exactly as Vanilla stores them.
//   VERTICES      x, y
//   LINEDEFS      v1, v2, flags, special, tag, front side, back side
//   SIDEDEFS      x offset, y offset, top tex, bottom tex, mid tex, sector
//   SECTORS       floor, ceiling, floor flat, ceiling flat, light, special, tag
//   NODES         x, y, dx, dy, bbox[2][4], child[2] (0x8000 marks a subsector)
//   SUBSECTORS    seg count, first seg, sector
//   SEGS          v1, v2, angle (BAM bits), linedef, side, offset, front, back
//   THINGS        x, y, angle, type, options
//   BLOCKMAP      the lump's int16 words, sign-extended (header, offsets, lists)
// Self-describing tables begin with counts (see MapTables.swift for layouts):
//   TEXTURES, PATCH_COLUMNS, FLATS, SPRITES.
// Byte tables (REJECT, PLAYPAL, COLORMAP) are [byte count, bytes packed four
// per cell, little-endian].

#define HM_MAP_TABLES_SCHEMA_VERSION 1u

#define HM_MAP_VERTEX_CELLS 2u
#define HM_MAP_LINEDEF_CELLS 7u
#define HM_MAP_SIDEDEF_CELLS 6u
#define HM_MAP_SECTOR_CELLS 7u
#define HM_MAP_NODE_CELLS 14u
#define HM_MAP_SUBSECTOR_CELLS 3u
#define HM_MAP_SEG_CELLS 8u
#define HM_MAP_THING_CELLS 5u

// Default per-table capacities, in cells (literals so Swift imports them).
// TEXTURES 2+4096*4+32768*3, FLATS 1+1024*2+1024*1024, SPRITES 1+16384*4,
// PLAYPAL 1+64*192, COLORMAP 1+64*64. A map or WAD that needs more fails
// with HM_MAP_TABLES_CAPACITY_EXCEEDED; nothing is truncated.
#define HM_MAP_CAP_VERTICES (65536u * HM_MAP_VERTEX_CELLS)
#define HM_MAP_CAP_LINEDEFS (65536u * HM_MAP_LINEDEF_CELLS)
#define HM_MAP_CAP_SIDEDEFS (65536u * HM_MAP_SIDEDEF_CELLS)
#define HM_MAP_CAP_SECTORS (65536u * HM_MAP_SECTOR_CELLS)
#define HM_MAP_CAP_NODES (32768u * HM_MAP_NODE_CELLS)
#define HM_MAP_CAP_SUBSECTORS (32768u * HM_MAP_SUBSECTOR_CELLS)
#define HM_MAP_CAP_SEGS (65536u * HM_MAP_SEG_CELLS)
#define HM_MAP_CAP_THINGS (65536u * HM_MAP_THING_CELLS)
#define HM_MAP_CAP_BLOCKMAP 262144u
#define HM_MAP_CAP_REJECT 1048576u
#define HM_MAP_CAP_TEXTURES 114690u
#define HM_MAP_CAP_PATCH_COLUMNS 8388608u
#define HM_MAP_CAP_FLATS 1050625u
#define HM_MAP_CAP_SPRITES 65537u
#define HM_MAP_CAP_PLAYPAL 12289u
#define HM_MAP_CAP_COLORMAP 4097u

// Failure classes are distinct on purpose: capacity-exceeded content is legal
// but too large for this version; malformed content is damaged; unsupported
// content is a valid format this version does not decode.
typedef uint32_t HMMapTablesFailureV1;
enum {
    HM_MAP_TABLES_OK = 0,
    HM_MAP_TABLES_MALFORMED = 1,
    HM_MAP_TABLES_UNSUPPORTED = 2,
    HM_MAP_TABLES_CAPACITY_EXCEEDED = 3
};

#endif
