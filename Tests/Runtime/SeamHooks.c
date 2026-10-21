// Test-only: plays a fixed script on bundled Freedoom and hashes the resulting
// C state, with phase seams either unhooked or recording.
#include "PhaseSeamABI.h"
#include "doomgeneric.h"
#include "doomstat.h"
#include "d_player.h"
#include "p_mobj.h"
#include <stdint.h>
#include <string.h>

extern int rndindex, prndindex, leveltime;
extern void doomgeneric_Tick(void);
extern void HM_TestPushKey(int pressed, unsigned char key);
int HM_TestBootEngine(const char *iwad, const char *map);

static uint64_t seam_hash = 14695981039346656037ull;
static uint32_t phase_count[HM_PHASE_COUNT];
static uint32_t violations, last_phase, last_edge;

static void recording_hook(uint32_t phase, uint32_t edge, uint32_t sequence) {
    seam_hash = (seam_hash ^ (phase * 2u + edge)) * 1099511628211ull;
    (void)sequence;
    if (phase < HM_PHASE_COUNT) ++phase_count[phase];
    // Within one tic phases never go backwards; a new tic starts at tic-commands.
    if (phase < last_phase && phase != HM_PHASE_TIC_COMMANDS) ++violations;
    if (edge == HM_SEAM_END && !(phase == last_phase && last_edge == HM_SEAM_BEGIN)) ++violations;
    last_phase = phase; last_edge = edge;
}

static uint64_t fnv(uint64_t h, const void *bytes, size_t n) {
    const uint8_t *p = bytes;
    for (size_t i = 0; i < n; ++i) h = (h ^ p[i]) * 1099511628211ull;
    return h;
}

// Returns 0 on success. `state_hash` covers gameplay globals, RNG indices and the framebuffer.
int HM_TestSeamScript(const char *iwad, int hooked, int tics,
                      uint64_t *state_hash, uint64_t *seam_sequence_hash,
                      uint32_t *phases_seen, uint32_t *violation_count, uint32_t *seam_total) {
    if (!HM_TestBootEngine(iwad, "E1M1")) return 1;
    HM_ResetPhaseSeams();
    if (hooked == 1) HM_SetPhaseSeamHook(recording_hook);   // 2 = leave an externally installed hook alone
    uint64_t h = 14695981039346656037ull;
    int guard = 0, start = gametic;
    while (gametic - start < tics && guard++ < tics * 8) {
        int t = gametic - start;
        if (t == 0) HM_TestPushKey(1, 0xad);
        if (t == 140) { HM_TestPushKey(0, 0xad); HM_TestPushKey(1, 0xae); }
        if (t == 210) HM_TestPushKey(0, 0xae);
        if (t == 220) HM_TestPushKey(1, 0xa3);
        if (t == 230) HM_TestPushKey(0, 0xa3);
        if (t == 234) HM_TestPushKey(1, 0xa2);
        if (t == 239) HM_TestPushKey(0, 0xa2);
        if (t == 244) HM_TestPushKey(1, 0x32);
        if (t == 249) HM_TestPushKey(0, 0x32);
        doomgeneric_Tick();
        mobj_t *mo = players[consoleplayer].mo;
        int32_t cells[12] = { gametic, leveltime, rndindex, prndindex,
            mo ? mo->x : 0, mo ? mo->y : 0, mo ? mo->z : 0, mo ? (int32_t)mo->angle : 0,
            mo ? mo->momx : 0, mo ? mo->momy : 0, players[consoleplayer].health, players[consoleplayer].readyweapon };
        h = fnv(h, cells, sizeof cells);
        h = fnv(h, DG_ScreenBuffer, (size_t)DOOMGENERIC_RESX * DOOMGENERIC_RESY * sizeof(*DG_ScreenBuffer));
    }
    if (hooked == 1) HM_SetPhaseSeamHook(0);
    *state_hash = h; *seam_sequence_hash = seam_hash;
    uint32_t seen = 0;
    for (int i = 0; i < HM_PHASE_COUNT; ++i) if (phase_count[i]) seen |= 1u << i;
    *phases_seen = seen; *violation_count = violations; *seam_total = HM_PhaseSeamCount();
    return gametic - start >= tics ? 0 : 2;
}
