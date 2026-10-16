#include "CircuitModuleABI.h"
#include "RenderStreamABI.h"

#include <stddef.h>

_Static_assert(sizeof(HMModuleStatus) == 4, "HMModuleStatus width");
_Static_assert((HMModuleStatus)-1 > 0, "HMModuleStatus signedness");

_Static_assert(sizeof(HMTableViewV1) == 24, "HMTableViewV1 size");
_Static_assert(_Alignof(HMTableViewV1) == 8, "HMTableViewV1 alignment");
_Static_assert(offsetof(HMTableViewV1, cells) == 16, "HMTableViewV1.cells");

_Static_assert(sizeof(HMModuleEventV1) == 48, "HMModuleEventV1 size");
_Static_assert(_Alignof(HMModuleEventV1) == 4, "HMModuleEventV1 alignment");
_Static_assert(offsetof(HMModuleEventV1, payload) == 32, "HMModuleEventV1.payload");

_Static_assert(sizeof(HMModuleInputV1) == 112, "HMModuleInputV1 size");
_Static_assert(_Alignof(HMModuleInputV1) == 8, "HMModuleInputV1 alignment");
_Static_assert(offsetof(HMModuleInputV1, tic_id) == 16, "HMModuleInputV1.tic_id");
_Static_assert(offsetof(HMModuleInputV1, input_count) == 32, "HMModuleInputV1.input_count");
_Static_assert(offsetof(HMModuleInputV1, inputs) == 80, "HMModuleInputV1.inputs");
_Static_assert(offsetof(HMModuleInputV1, input_events) == 104, "HMModuleInputV1.input_events");

_Static_assert(sizeof(HMStateDeltaV1) == 20, "HMStateDeltaV1 size");
_Static_assert(_Alignof(HMStateDeltaV1) == 4, "HMStateDeltaV1 alignment");
_Static_assert(offsetof(HMStateDeltaV1, before) == 12, "HMStateDeltaV1.before");

_Static_assert(sizeof(HMModuleResultV1) == 80, "HMModuleResultV1 size");
_Static_assert(_Alignof(HMModuleResultV1) == 8, "HMModuleResultV1 alignment");
_Static_assert(offsetof(HMModuleResultV1, status) == 24, "HMModuleResultV1.status");
_Static_assert(offsetof(HMModuleResultV1, outputs) == 56, "HMModuleResultV1.outputs");
_Static_assert(offsetof(HMModuleResultV1, events) == 72, "HMModuleResultV1.events");

_Static_assert(sizeof(HMExactOpV1) == 32, "HMExactOpV1 size");
_Static_assert(_Alignof(HMExactOpV1) == 4, "HMExactOpV1 alignment");
_Static_assert(offsetof(HMExactOpV1, immediate) == 16, "HMExactOpV1.immediate");
_Static_assert(sizeof(HMExactProgramV1) == 56, "HMExactProgramV1 size");
_Static_assert(_Alignof(HMExactProgramV1) == 8, "HMExactProgramV1 alignment");
_Static_assert(offsetof(HMExactProgramV1, source_hash) == 32, "HMExactProgramV1.source_hash");
_Static_assert(offsetof(HMExactProgramV1, operations) == 40, "HMExactProgramV1.operations");
_Static_assert(sizeof(HMExactTableDescriptorV1) == 20, "HMExactTableDescriptorV1 size");
_Static_assert(sizeof(HMExactDispatchV1) == 72, "HMExactDispatchV1 size");

_Static_assert(sizeof(HMWorldSnapshotV1) == 56, "HMWorldSnapshotV1 size");
_Static_assert(_Alignof(HMWorldSnapshotV1) == 8, "HMWorldSnapshotV1 alignment");
_Static_assert(offsetof(HMWorldSnapshotV1, array_directory_offset) == 40,
               "HMWorldSnapshotV1.array_directory_offset");
_Static_assert(sizeof(HMWorldArrayV1) == 24, "HMWorldArrayV1 size");
_Static_assert(sizeof(HMWorldCellV1) == 16, "HMWorldCellV1 size");
_Static_assert(sizeof(HMDrawPrimitiveV1) == 72, "HMDrawPrimitiveV1 size");
_Static_assert(_Alignof(HMDrawPrimitiveV1) == 4, "HMDrawPrimitiveV1 alignment");
_Static_assert(offsetof(HMDrawPrimitiveV1, argument) == 40, "HMDrawPrimitiveV1.argument");

int HM_RunCContractLayoutTests(void) {
    if (HM_MODULE_EXACT != 0 || HM_MODULE_PARTIAL_RESULT != 12) return 1;
    if (HM_MODULE_MOVEMENT_COLLISION != 0x00050001u ||
        HM_MODULE_GAME_LOOP != 0x000d0001u) return 2;
    if (HM_TABLE_VERTICES != 0x00030001u ||
        HM_EVENT_SOUND != 0x00060001u || HM_DRAW_PATCH != 0x00090001u)
        return 3;
    if (HM_EXACT_OP_MOVE != 1 || HM_EXACT_OP_TABLE_READ_I32 != 11) return 4;
    if (HM_T05_ID_FIRST != 0x00050000u || HM_T13_ID_LAST != 0x000dffffu ||
        HM_PHASE_COUNT != 10) return 5;
    if (!HM_IsKnownWorldCellIDV1(HM_WORLD_ARRAY_PLAYERS, HM_PLAYER_ANGLE) ||
        HM_IsKnownWorldCellIDV1(HM_WORLD_ARRAY_PLAYERS,
                                HM_PLAYER_BACKPACK + 1)) return 6;
    return 0;
}
