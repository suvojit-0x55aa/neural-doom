#include "MovementABI.h"
#include "TicRemainderABI.h"
#include "doomgeneric.h"
#include <stdint.h>
int HM_EvaluateMovement(const HMMovementInput *in, const HMMovementOutput *reference, HMMovementOutput *committed) {
    (void)in; (void)reference; (void)committed; return 0;
}
int HM_EvaluateRemainder(const HMTicRemainderInput *in, const HMTicRemainderOutput *reference, HMTicRemainderOutput *committed) {
    (void)in; (void)reference; (void)committed; return 0;
}
void DG_Init(void) {}
void DG_DrawFrame(void) {}
void DG_SleepMs(uint32_t ms) { (void)ms; }
// Advances on every query so engine waits (screen wipe, tic pacing) terminate.
uint32_t DG_GetTicksMs(void) { static uint32_t now; return now += 3; }
int DG_GetKey(int *pressed, unsigned char *key) { (void)pressed; (void)key; return 0; }
void DG_SetWindowTitle(const char *title) { (void)title; }
