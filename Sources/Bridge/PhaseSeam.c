#include "PhaseSeamABI.h"

static HMPhaseSeamHook hm_hook;
static uint32_t hm_sequence;

void HM_SetPhaseSeamHook(HMPhaseSeamHook hook) { hm_hook = hook; }
void HM_ResetPhaseSeams(void) { hm_sequence = 0; }
uint32_t HM_PhaseSeamCount(void) { return hm_sequence; }
void HM_PhaseSeam(uint32_t phase, uint32_t edge) {
    uint32_t sequence = hm_sequence++;
    if (hm_hook) hm_hook(phase, edge, sequence);
}
