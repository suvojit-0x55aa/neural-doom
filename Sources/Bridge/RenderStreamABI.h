#ifndef HM_RENDER_STREAM_ABI_H
#define HM_RENDER_STREAM_ABI_H

#include <stddef.h>
#include <stdint.h>
#include "CircuitIDs.h"

#define HM_RENDER_STREAM_ABI_VERSION 1u

// A pointer-free, fixed-size primitive. All resources are stable table handles
// plus indices. argument meaning is selected only by primitive_id/version.
typedef struct {
    uint32_t primitive_id;
    uint32_t flags;
    uint32_t sequence;
    uint32_t source_slot;
    int32_t clip_left;
    int32_t clip_top;
    int32_t clip_right;
    int32_t clip_bottom;
    uint32_t resource_table_id;
    uint32_t resource_index;
    int32_t argument[8];
} HMDrawPrimitiveV1;

size_t HM_SerializeDrawPrimitiveV1(const HMDrawPrimitiveV1 *primitive,
                                   uint8_t *destination,
                                   size_t capacity);

#endif
