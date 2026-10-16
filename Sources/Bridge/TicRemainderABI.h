#ifndef HM_TIC_REMAINDER_ABI_H
#define HM_TIC_REMAINDER_ABI_H
#include <stdint.h>
#include "MovementABI.h"

// Version 1. The first four cells are the already committed locomotion
// command; all other cells are an immutable pre-G_BuildTiccmd snapshot.
enum { HM_REMAINDER_INPUT_COUNT = 55 };
enum HMRemainderCell {
    HM_R_FORWARD, HM_R_SIDE, HM_R_ANGLE_RAW, HM_R_TURNHELD,
    HM_R_FIRE_KEY, HM_R_FIRE_MOUSE, HM_R_FIRE_JOY,
    HM_R_USE_KEY, HM_R_USE_MOUSE, HM_R_USE_JOY,
    HM_R_WEAPON_KEY_1, HM_R_WEAPON_KEY_2, HM_R_WEAPON_KEY_3, HM_R_WEAPON_KEY_4,
    HM_R_WEAPON_KEY_5, HM_R_WEAPON_KEY_6, HM_R_WEAPON_KEY_7, HM_R_WEAPON_KEY_8,
    HM_R_IN_LEVEL, HM_R_NEXT_WEAPON, HM_R_READY_WEAPON, HM_R_PENDING_WEAPON,
    HM_R_OWNED_FIST, HM_R_OWNED_PISTOL, HM_R_OWNED_SHOTGUN,
    HM_R_OWNED_CHAINGUN, HM_R_OWNED_MISSILE, HM_R_OWNED_PLASMA,
    HM_R_OWNED_BFG, HM_R_OWNED_CHAINSAW, HM_R_OWNED_SUPERSHOTGUN,
    HM_R_STRENGTH, HM_R_LOGICAL_DOOM, HM_R_MISSION_DOOM, HM_R_SHAREWARE,
    HM_R_DCLICK_USE, HM_R_DCLICK_TIME, HM_R_DCLICK_STATE, HM_R_DCLICKS,
    HM_R_DCLICK_TIME2, HM_R_DCLICK_STATE2, HM_R_DCLICKS2,
    HM_R_SEND_PAUSE, HM_R_SEND_SAVE, HM_R_SAVE_SLOT, HM_R_LOWRES_TURN,
    HM_R_LOWRES_CARRY, HM_R_CHAT_CHAR, HM_R_CONSISTENCY, HM_R_TEST_MOUSE_SPEED,
    HM_R_MOUSE_X, HM_R_MOUSE_FORWARD, HM_R_MOUSE_STRAFE, HM_R_JOY_STRAFE,
    HM_R_TICDUP
};
typedef struct { int32_t cell[HM_REMAINDER_INPUT_COUNT]; } HMTicRemainderInput;

// Every field changed or written by the remainder of G_BuildTiccmd is staged
// here. All fields are int32 to keep the Metal output ABI explicit.
typedef struct {
    int32_t angleturn, buttons, chatchar, consistancy;
    int32_t buttons2, inventory, lookfly, arti;
    int32_t dclicktime, dclickstate, dclicks;
    int32_t dclicktime2, dclickstate2, dclicks2;
    int32_t lowres_carry, testcontrols_mousespeed;
    int32_t next_weapon, sendpause, sendsave, mousex, mousey;
} HMTicRemainderOutput;
enum { HM_REMAINDER_OUTPUT_COUNT = 21 };

int HM_RemainderInputInDomain(const HMTicRemainderInput *input);
HMTicRemainderOutput HM_ReferenceRemainder(const HMTicRemainderInput *input);
int HM_EvaluateRemainder(const HMTicRemainderInput *input,
                         const HMTicRemainderOutput *reference,
                         HMTicRemainderOutput *committed);

#ifdef HM_TEST
// Executes the real adapted upstream function with generated state. The
// callback is disabled; captured receives the exact circuit input snapshot.
HMTicRemainderOutput HM_TestOriginalRemainder(const HMMovementInput *movement,
                                                const HMTicRemainderInput *before,
                                                HMTicRemainderInput *captured);
#endif
#endif
