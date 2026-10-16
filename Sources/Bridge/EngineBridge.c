#include "EngineBridge.h"
#include "doomgeneric.h"
#include "d_event.h"
#include "doomstat.h"
#include "p_mobj.h"
#include <time.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <stdio.h>

extern int gametic;
extern int HM_HostGetKey(int *pressed, unsigned char *key);
extern void HM_HostFrameReady(void);
extern void HM_HostSetTitle(const char *title);

void HM_EngineStart(const char *iwad_path) {
    static char *argv[9];
    setvbuf(stdout, NULL, _IONBF, 0);
    const char *data_dir = getenv("HANDWIRED_DOOM_DATA_DIR");
    if (data_dir) { mkdir(data_dir, 0700); chdir(data_dir); }
    argv[0] = "Neural Doom"; argv[1] = "-iwad";
    argv[2] = strdup(iwad_path); argv[3] = "-warp"; argv[4] = "1";
    argv[5] = "-skill"; argv[6] = "3"; argv[7] = "-nosound";
    argv[8] = NULL;
    // The host's monotonic scheduler calls exactly one engine tic per call.
    // Multiple calls may be made before a single MTKView presentation.
    singletics = 1;
    doomgeneric_Create(8, argv);
}
void HM_EngineFrame(void) { doomgeneric_Tick(); }
void HM_EnginePostMouse(int buttons, int dx, int dy) {
    event_t event = {0};
    event.type = ev_mouse;
    event.data1 = buttons;
    event.data2 = dx;
    event.data3 = dy;
    D_PostEvent(&event);
}
int HM_EngineGametic(void) { return gametic; }
const uint32_t *HM_EnginePixels(void) { return DG_ScreenBuffer; }
HMPlayerState HM_EnginePlayerState(void) {
    HMPlayerState state = {0};
    state.gametic = gametic;
    if (gamestate == GS_LEVEL && players[consoleplayer].mo != NULL) {
        state.in_level = 1;
        state.x = players[consoleplayer].mo->x;
        state.y = players[consoleplayer].mo->y;
        state.angle = players[consoleplayer].mo->angle;
    }
    return state;
}

void DG_Init(void) {}
void DG_DrawFrame(void) { HM_HostFrameReady(); }
void DG_SleepMs(uint32_t ms) { usleep((useconds_t)ms * 1000); }
uint32_t DG_GetTicksMs(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)((uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}
int DG_GetKey(int *pressed, unsigned char *key) { return HM_HostGetKey(pressed, key); }
void DG_SetWindowTitle(const char *title) { HM_HostSetTitle(title); }
