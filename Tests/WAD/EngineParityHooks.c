// Test-only: boots DoomGeneric on a WAD and re-expresses its loaded C structures
// in MapTablesV1 cell layouts (pointers become indices) so Swift can compare.
#include "CircuitIDs.h"
#include "doomgeneric.h"
#include "doomstat.h"
#include "doomdata.h"
#include "i_swap.h"
#include "p_local.h"
#include "r_data.h"
#include "r_defs.h"
#include "r_state.h"
#include "v_patch.h"
#include "w_wad.h"
#include "z_zone.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

extern int numflats;
extern int numtextures;
extern int *texturewidthmask;
extern void doomgeneric_Tick(void);

static char loaded_map[9];

int HM_TestBootEngine(const char *iwad, const char *map) {
    strncpy(loaded_map, map, 8);
    static char *argv[8];
    argv[0] = "test"; argv[1] = "-iwad"; argv[2] = (char *)iwad; argv[3] = "-warp";
    argv[4] = "1"; argv[5] = "-skill"; argv[6] = "3"; argv[7] = "-nosound";
    singletics = 1;
    doomgeneric_Create(8, argv);
    for (int i = 0; i < 4 && gamestate != GS_LEVEL; ++i) doomgeneric_Tick();
    return gamestate == GS_LEVEL;
}

// The embedded zone is tiny; read lumps into malloc'd memory instead.
static uint8_t *read_lump(int lump) {
    uint8_t *b = malloc((size_t)W_LumpLength(lump) + 1);
    W_ReadLump(lump, b);
    return b;
}

#define PUT(v) do { if (n >= cap) return -1; out[n++] = (int32_t)(v); } while (0)

// Returns the cell count, or -1 if the buffer is too small / the table is unknown.
int HM_TestLoadedTable(uint32_t id, int32_t *out, int cap) {
    int n = 0;
    switch (id) {
    case HM_TABLE_VERTICES:
        for (int i = 0; i < numvertexes; ++i) { PUT(vertexes[i].x); PUT(vertexes[i].y); }
        return n;
    case HM_TABLE_LINEDEFS:
        for (int i = 0; i < numlines; ++i) {
            line_t *l = &lines[i];
            PUT(l->v1 - vertexes); PUT(l->v2 - vertexes); PUT(l->flags); PUT(l->special);
            PUT(l->tag); PUT(l->sidenum[0]); PUT(l->sidenum[1]);
        }
        return n;
    case HM_TABLE_SIDEDEFS:
        for (int i = 0; i < numsides; ++i) {
            side_t *s = &sides[i];
            PUT(s->textureoffset); PUT(s->rowoffset); PUT(s->toptexture);
            PUT(s->bottomtexture); PUT(s->midtexture); PUT(s->sector - sectors);
        }
        return n;
    case HM_TABLE_SECTORS:
        for (int i = 0; i < numsectors; ++i) {
            sector_t *s = &sectors[i];
            PUT(s->floorheight); PUT(s->ceilingheight); PUT(s->floorpic); PUT(s->ceilingpic);
            PUT(s->lightlevel); PUT(s->special); PUT(s->tag);
        }
        return n;
    case HM_TABLE_NODES:
        for (int i = 0; i < numnodes; ++i) {
            node_t *d = &nodes[i];
            PUT(d->x); PUT(d->y); PUT(d->dx); PUT(d->dy);
            for (int j = 0; j < 2; ++j) for (int k = 0; k < 4; ++k) PUT(d->bbox[j][k]);
            PUT(d->children[0]); PUT(d->children[1]);
        }
        return n;
    case HM_TABLE_SUBSECTORS:
        for (int i = 0; i < numsubsectors; ++i) {
            PUT(subsectors[i].numlines); PUT(subsectors[i].firstline);
            PUT(subsectors[i].sector - sectors);
        }
        return n;
    case HM_TABLE_SEGS:
        for (int i = 0; i < numsegs; ++i) {
            seg_t *s = &segs[i];
            int sideIndex = (int)(s->sidedef - sides);
            PUT(s->v1 - vertexes); PUT(s->v2 - vertexes); PUT(s->angle);
            PUT(s->linedef - lines); PUT(s->linedef->sidenum[0] == sideIndex ? 0 : 1);
            PUT(s->offset); PUT(s->frontsector - sectors);
            PUT(s->backsector ? s->backsector - sectors : -1);
        }
        return n;
    case HM_TABLE_BLOCKMAP: {
        int words = W_LumpLength(W_GetNumForName(loaded_map) + ML_BLOCKMAP) / 2;
        for (int i = 0; i < words; ++i) PUT(blockmaplump[i]);
        return n;
    }
    case HM_TABLE_REJECT: {
        int bytes = W_LumpLength(W_GetNumForName(loaded_map) + ML_REJECT);
        PUT(bytes);
        for (int i = 0; i < bytes; i += 4) {
            uint32_t w = 0;
            for (int j = 0; j < 4 && i + j < bytes; ++j) w |= (uint32_t)rejectmatrix[i + j] << (8 * j);
            PUT(w);
        }
        return n;
    }
    case HM_TABLE_THINGS: {
        int lump = W_GetNumForName(loaded_map) + ML_THINGS;
        const mapthing_t *t = (const mapthing_t *)read_lump(lump);
        for (int i = 0; i < W_LumpLength(lump) / (int)sizeof(mapthing_t); ++i) {
            PUT(SHORT(t[i].x)); PUT(SHORT(t[i].y)); PUT(SHORT(t[i].angle));
            PUT(SHORT(t[i].type)); PUT(SHORT(t[i].options));
        }
        free((void *)t);
        return n;
    }
    case HM_TABLE_TEXTURES:   // [count] then each texture's height from the loaded table
        PUT(numtextures);
        for (int i = 0; i < numtextures; ++i) PUT(textureheight[i] >> FRACBITS);
        return n;
    case HM_TABLE_FLATS:      // [count, firstflat] then each flat lump's bytes as 4096 ints
        PUT(numflats); PUT(firstflat);
        for (int i = 0; i < numflats; ++i) {
            int size = W_LumpLength(firstflat + i);
            const uint8_t *b = read_lump(firstflat + i);
            PUT(size);
            for (int j = 0; j < size; ++j) PUT(b[j]);
            free((void *)b);
        }
        return n;
    case HM_TABLE_SPRITES:
        PUT(numspritelumps); PUT(firstspritelump);
        for (int i = 0; i < numspritelumps; ++i) {
            PUT(spritewidth[i]); PUT(spriteoffset[i]); PUT(spritetopoffset[i]);
        }
        return n;
    case HM_TABLE_PLAYPAL: {
        int lump = W_GetNumForName("PLAYPAL");
        const uint8_t *b = read_lump(lump);
        for (int i = 0; i < W_LumpLength(lump); ++i) PUT(b[i]);
        free((void *)b);
        return n;
    }
    case HM_TABLE_COLORMAP:   // the engine's resident light tables
        for (int i = 0; i < 34 * 256; ++i) PUT(colormaps[i]);
        return n;
    }
    return -1;
}

// Normalized patch walk over the engine's cached lump: [w, h, left, top], then for
// every column each post as (topdelta, length, pixels...) and -1 at column end.
int HM_TestPatchColumns(const char *lump_name, int32_t *out, int cap) {
    int lump = W_CheckNumForName((char *)lump_name), n = 0;
    if (lump < 0) return -1;
    const patch_t *p = (const patch_t *)read_lump(lump);
    PUT(SHORT(p->width)); PUT(SHORT(p->height)); PUT(SHORT(p->leftoffset)); PUT(SHORT(p->topoffset));
    for (int c = 0; c < SHORT(p->width); ++c) {
        const uint8_t *col = (const uint8_t *)p + LONG(p->columnofs[c]);
        while (*col != 0xFF) {
            PUT(col[0]); PUT(col[1]);
            for (int i = 0; i < col[1]; ++i) PUT(col[3 + i]);
            col += col[1] + 4;
        }
        PUT(-1);
    }
    free((void *)p);
    return n;
}
