#include "TicRemainderABI.h"
#include <string.h>

static int bit(const int32_t *v, int i) { return v[i] != 0; }
static int in(int32_t x, int32_t lo, int32_t hi) { return x >= lo && x <= hi; }

int HM_RemainderInputInDomain(const HMTicRemainderInput *input) {
    const int32_t *v = input->cell;
    if (!in(v[HM_R_FORWARD], -50, 50) || !in(v[HM_R_SIDE], -50, 50)
        || !in(v[HM_R_ANGLE_RAW], -8192, 8192)
        || !in(v[HM_R_TURNHELD], 0, 16777216)) return 0;
    for (int i = HM_R_FIRE_KEY; i <= HM_R_USE_JOY; ++i) if (!in(v[i], 0, 1)) return 0;
    for (int i = HM_R_WEAPON_KEY_1; i <= HM_R_WEAPON_KEY_8; ++i) if (!in(v[i], 0, 1)) return 0;
    if (!in(v[HM_R_IN_LEVEL], 0, 1) || !in(v[HM_R_NEXT_WEAPON], -1, 1)
        || !in(v[HM_R_READY_WEAPON], 0, 8)
        || !(in(v[HM_R_PENDING_WEAPON], 0, 8) || v[HM_R_PENDING_WEAPON] == 10)) return 0;
    for (int i = HM_R_OWNED_FIST; i <= HM_R_OWNED_SUPERSHOTGUN; ++i) if (!in(v[i], 0, 1)) return 0;
    for (int i = HM_R_STRENGTH; i <= HM_R_DCLICK_USE; ++i) if (!in(v[i], 0, 1)) return 0;
    if (!in(v[HM_R_DCLICK_TIME], 0, 1000000) || !in(v[HM_R_DCLICK_STATE], 0, 1)
        || !in(v[HM_R_DCLICKS], 0, 2) || !in(v[HM_R_DCLICK_TIME2], 0, 1000000)
        || !in(v[HM_R_DCLICK_STATE2], 0, 1) || !in(v[HM_R_DCLICKS2], 0, 2)) return 0;
    if (!in(v[HM_R_SEND_PAUSE], 0, 1) || !in(v[HM_R_SEND_SAVE], 0, 1)
        || !in(v[HM_R_SAVE_SLOT], 0, 7) || !in(v[HM_R_LOWRES_TURN], 0, 1)
        || !in(v[HM_R_LOWRES_CARRY], -128, 127)
        || !in(v[HM_R_CHAT_CHAR], 0, 255) || !in(v[HM_R_CONSISTENCY], 0, 255)
        || !in(v[HM_R_TEST_MOUSE_SPEED], 0, 8192)
        || !in(v[HM_R_MOUSE_X], -256, 256)
        || !in(v[HM_R_MOUSE_FORWARD], 0, 1)
        || !in(v[HM_R_MOUSE_STRAFE], 0, 1)
        || !in(v[HM_R_JOY_STRAFE], 0, 1)
        || !in(v[HM_R_TICDUP], 1, 4)) return 0;
    return 1;
}

static int selectable(const int32_t *v, int weapon) {
    if (!v[HM_R_OWNED_FIST + weapon]) return 0;
    if (weapon == 8 && bit(v, HM_R_LOGICAL_DOOM)) return 0;
    if ((weapon == 5 || weapon == 6) && bit(v, HM_R_MISSION_DOOM) && bit(v, HM_R_SHAREWARE)) return 0;
    if (weapon == 0 && bit(v, HM_R_OWNED_CHAINSAW) && !bit(v, HM_R_STRENGTH)) return 0;
    return 1;
}

static void doubleclick(int enabled, int button, int ticdup,
                        int *time, int *state, int *clicks, int *use) {
    if (!enabled) return;
    if (button != *state && *time > 1) {
        *state = button;
        if (*state) ++*clicks;
        if (*clicks == 2) { *use = 1; *clicks = 0; }
        else *time = 0;
    } else {
        *time += ticdup;
        if (*time > 20) { *clicks = 0; *state = 0; }
    }
}

HMTicRemainderOutput HM_ReferenceRemainder(const HMTicRemainderInput *input) {
    const int32_t *v = input->cell;
    HMTicRemainderOutput out = {0};
    out.angleturn = v[HM_R_ANGLE_RAW];
    out.chatchar = v[HM_R_CHAT_CHAR];
    out.consistancy = v[HM_R_CONSISTENCY];
    out.dclicktime = v[HM_R_DCLICK_TIME];
    out.dclickstate = v[HM_R_DCLICK_STATE];
    out.dclicks = v[HM_R_DCLICKS];
    out.dclicktime2 = v[HM_R_DCLICK_TIME2];
    out.dclickstate2 = v[HM_R_DCLICK_STATE2];
    out.dclicks2 = v[HM_R_DCLICKS2];
    out.lowres_carry = v[HM_R_LOWRES_CARRY];
    out.testcontrols_mousespeed = v[HM_R_MOUSE_X] == 0 ? 0 : v[HM_R_TEST_MOUSE_SPEED];
    int attack = bit(v, HM_R_FIRE_KEY) || bit(v, HM_R_FIRE_MOUSE) || bit(v, HM_R_FIRE_JOY);
    int use = bit(v, HM_R_USE_KEY) || bit(v, HM_R_USE_MOUSE) || bit(v, HM_R_USE_JOY);
    if (use) out.dclicks = 0;
    int weapon = 0, change = 0;
    if (bit(v, HM_R_IN_LEVEL) && v[HM_R_NEXT_WEAPON] != 0) {
        static const int order[] = {0,7,1,2,8,3,4,5,6};
        static const int number[] = {0,0,1,2,2,3,4,5,6};
        int current = v[HM_R_PENDING_WEAPON] == 10 ? v[HM_R_READY_WEAPON] : v[HM_R_PENDING_WEAPON];
        int start = 0;
        while (order[start] != current) ++start;
        int i = start;
        do {
            i = (i + v[HM_R_NEXT_WEAPON] + 9) % 9;
        } while (i != start && !selectable(v, order[i]));
        weapon = number[i]; change = 1;
    } else {
        for (int i = 0; i < 8; ++i) if (v[HM_R_WEAPON_KEY_1 + i]) {
            weapon = i; change = 1; break;
        }
    }
    if (bit(v, HM_R_DCLICK_USE)) {
        doubleclick(1, bit(v, HM_R_MOUSE_FORWARD), v[HM_R_TICDUP],
                    &out.dclicktime, &out.dclickstate, &out.dclicks, &use);
        doubleclick(1, bit(v, HM_R_MOUSE_STRAFE) || bit(v, HM_R_JOY_STRAFE), v[HM_R_TICDUP],
                    &out.dclicktime2, &out.dclickstate2, &out.dclicks2, &use);
    }
    out.buttons = attack + 2 * use + 4 * change + 8 * weapon;
    if (bit(v, HM_R_SEND_PAUSE)) out.buttons = 129;
    if (bit(v, HM_R_SEND_SAVE)) out.buttons = 130 + 4 * v[HM_R_SAVE_SLOT];
    if (bit(v, HM_R_LOWRES_TURN)) {
        int16_t desired = (int16_t)(out.angleturn + out.lowres_carry);
        out.angleturn = (int16_t)((desired + 128) & 0xff00);
        out.lowres_carry = (int16_t)(desired - out.angleturn);
    }
    return out;
}
