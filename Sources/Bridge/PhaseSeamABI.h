#ifndef HM_PHASE_SEAM_ABI_H
#define HM_PHASE_SEAM_ABI_H
#include <stdint.h>
#include "CircuitIDs.h"

// Versioned reference-C phase seams. A seam marks where a phase's reference
// code begins or ends; it reads and writes no game state. With no hook
// installed it only counts, so the original call order is unchanged.
#define HM_PHASE_SEAM_ABI_VERSION 1u

enum { HM_SEAM_BEGIN = 0, HM_SEAM_END = 1 };

// `sequence` counts seams since the last reset, independent of the hook.
typedef void (*HMPhaseSeamHook)(uint32_t phase, uint32_t edge, uint32_t sequence);

void HM_SetPhaseSeamHook(HMPhaseSeamHook hook);
void HM_ResetPhaseSeams(void);
uint32_t HM_PhaseSeamCount(void);
void HM_PhaseSeam(uint32_t phase, uint32_t edge);

#ifdef HM_TEST
int HM_TestSeamScript(const char *iwad, int hooked, int tics,
                      uint64_t *state_hash, uint64_t *seam_sequence_hash,
                      uint32_t *phases_seen, uint32_t *violation_count, uint32_t *seam_total);
#endif
#endif
