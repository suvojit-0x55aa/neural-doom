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
// Scripted key queue so tests can drive a fixed play script.
static int key_head, key_tail;
static struct { int pressed; unsigned char key; } key_queue[512];
void HM_TestPushKey(int pressed, unsigned char key) {
    if (key_tail < 512) { key_queue[key_tail].pressed = pressed; key_queue[key_tail].key = key; ++key_tail; }
}
int DG_GetKey(int *pressed, unsigned char *key) {
    if (key_head == key_tail) return 0;
    *pressed = key_queue[key_head].pressed; *key = key_queue[key_head].key; ++key_head;
    return 1;
}
void DG_SetWindowTitle(const char *title) { (void)title; }
