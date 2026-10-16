#ifndef HM_CIRCUIT_MODULE_ABI_H
#define HM_CIRCUIT_MODULE_ABI_H
#include <stddef.h>
#include <stdint.h>
#include "CircuitIDs.h"
#include "WorldStateABI.h"

#define HM_CIRCUIT_MODULE_ABI_VERSION 1u
#define HM_EXACT_PROGRAM_ABI_VERSION 1u
#define HM_EXACT_INTEGER_ENCODING_V1 1u
#define HM_FP32_EXACT_ENCODING_V1 2u
#define HM_CANONICAL_SERIALIZATION_VERSION 1u
#define HM_EXACT_MAX_REGISTERS_V1 4096u

// Numeric values are part of the ABI and are unsigned on both C and Swift.
typedef uint32_t HMModuleStatus;
enum {
    HM_MODULE_EXACT = 0,
    HM_MODULE_UNSUPPORTED_DOMAIN = 1,
    HM_MODULE_CAPACITY_EXCEEDED = 2,
    HM_MODULE_EXECUTION_ERROR = 3,
    HM_MODULE_PARITY_MISMATCH = 4,
    HM_MODULE_INVALID_ABI = 5,
    HM_MODULE_UNKNOWN_ID = 6,
    HM_MODULE_SOURCE_HASH_MISMATCH = 7,
    HM_MODULE_MALFORMED_SPAN = 8,
    HM_MODULE_INVALID_ORDER = 9,
    HM_MODULE_TABLE_BOUNDS = 10,
    HM_MODULE_INTEGER_OVERFLOW = 11,
    HM_MODULE_PARTIAL_RESULT = 12
};

typedef struct {
    uint32_t table_id;
    uint32_t length;
    uint32_t capacity;
    uint32_t reserved;
    const int32_t *cells;
} HMTableViewV1;

// Events are canonical only in strict (phase, emitter_slot, local_sequence)
// order. source_id and target_id are handles/indices, never addresses.
typedef struct {
    uint32_t phase;
    uint32_t event_id;
    uint32_t emitter_slot;
    uint32_t local_sequence;
    uint32_t source_id;
    uint32_t target_id;
    uint32_t payload_count;
    uint32_t flags;
    int32_t payload[4];
} HMModuleEventV1;

typedef struct {
    uint32_t abi_version;
    uint32_t program_version;
    uint32_t integer_encoding;
    uint32_t module_id;
    uint64_t tic_id;
    uint64_t source_hash;
    uint32_t input_count;
    uint32_t input_capacity;
    uint32_t state_count;
    uint32_t state_capacity;
    uint32_t table_count;
    uint32_t table_capacity;
    uint32_t input_event_count;
    uint32_t input_event_capacity;
    uint32_t output_count;
    uint32_t output_capacity;
    uint32_t state_delta_capacity;
    uint32_t event_capacity;
    const int32_t *inputs;
    const int32_t *state_before;
    const HMTableViewV1 *tables;
    const HMModuleEventV1 *input_events;
} HMModuleInputV1;

typedef struct {
    uint32_t array_id;
    uint32_t element_index;
    uint32_t cell_id;
    int32_t before;
    int32_t after;
} HMStateDeltaV1;

typedef struct {
    uint32_t abi_version;
    uint32_t module_id;
    uint64_t tic_id;
    uint64_t source_hash;
    HMModuleStatus status;
    uint32_t reserved;
    uint32_t output_count;
    uint32_t output_capacity;
    uint32_t state_delta_count;
    uint32_t state_delta_capacity;
    uint32_t event_count;
    uint32_t event_capacity;
    int32_t *outputs;
    HMStateDeltaV1 *state_deltas;
    HMModuleEventV1 *events;
} HMModuleResultV1;

// The exact integer program never converts through Float. Registers and table
// values are raw 32-bit words; individual opcodes select signed or unsigned
// interpretation. Every operation is 32 bytes in C, Swift, and Metal.
typedef uint32_t HMExactOpcodeV1;
enum {
    HM_EXACT_OP_MOVE = 1,
    HM_EXACT_OP_CONSTANT = 2,
    HM_EXACT_OP_ADD_I32 = 3,
    HM_EXACT_OP_SUB_I32 = 4,
    HM_EXACT_OP_FIXED_MUL_16_16 = 5,
    HM_EXACT_OP_FIXED_DIV_16_16 = 6,
    HM_EXACT_OP_ANGLE_ADD_U32 = 7,
    HM_EXACT_OP_COMPARE_LT_I32 = 8,
    HM_EXACT_OP_COMPARE_EQUAL_BITS = 9,
    HM_EXACT_OP_GATE = 10,
    HM_EXACT_OP_TABLE_READ_I32 = 11
};

typedef struct {
    uint32_t opcode;
    uint32_t destination;
    uint32_t lhs;
    uint32_t rhs;
    int32_t immediate;
    uint32_t table_id;
    uint32_t flags;
    uint32_t reserved;
} HMExactOpV1;

typedef struct {
    uint32_t abi_version;
    uint32_t integer_encoding;
    uint32_t input_count;
    uint32_t register_count;
    uint32_t operation_count;
    uint32_t operation_capacity;
    uint32_t output_count;
    uint32_t output_capacity;
    uint64_t source_hash;
    const HMExactOpV1 *operations;
    const uint32_t *output_registers;
} HMExactProgramV1;

// Pointer-free Metal table and dispatch records.
typedef struct {
    uint32_t table_id;
    uint32_t length;
    uint32_t capacity;
    uint32_t offset;
    uint32_t reserved;
} HMExactTableDescriptorV1;

typedef struct {
    uint32_t abi_version;
    uint32_t integer_encoding;
    uint32_t input_count;
    uint32_t input_capacity;
    uint32_t register_count;
    uint32_t scratch_capacity;
    uint32_t operation_count;
    uint32_t operation_capacity;
    uint32_t output_count;
    uint32_t output_capacity;
    uint32_t table_count;
    uint32_t table_capacity;
    uint32_t table_cell_count;
    uint32_t table_cell_capacity;
    uint32_t output_register_capacity;
    uint32_t status_capacity;
    uint32_t reserved[2];
} HMExactDispatchV1;

HMModuleStatus HM_PrepareExactDispatchV1(const HMExactDispatchV1 *dispatch,
                                         uint32_t *status,
                                         uint32_t status_capacity);

HMModuleStatus HM_ValidateModuleInputV1(const HMModuleInputV1 *input,
                                        uint32_t expected_module_id,
                                        uint64_t expected_source_hash);
HMModuleStatus HM_FinalizeModuleResultV1(const HMModuleInputV1 *input,
                                         HMModuleResultV1 *result,
                                         uint32_t expected_module_id,
                                         uint64_t expected_source_hash);
void HM_RejectModuleResultV1(HMModuleResultV1 *result, HMModuleStatus status);

uint64_t HM_HashBytesV1(const uint8_t *bytes, size_t count);
size_t HM_CanonicalModuleInputSizeV1(const HMModuleInputV1 *input);
size_t HM_SerializeModuleInputV1(const HMModuleInputV1 *input,
                                 uint8_t *destination,
                                 size_t capacity);
size_t HM_CanonicalModuleResultSizeV1(const HMModuleResultV1 *result);
size_t HM_SerializeModuleResultV1(const HMModuleResultV1 *result,
                                  uint8_t *destination,
                                  size_t capacity);
size_t HM_SerializeModuleEventV1(const HMModuleEventV1 *event,
                                 uint8_t *destination,
                                 size_t capacity);
uint64_t HM_ExactProgramHashV1(const HMExactProgramV1 *program);

HMModuleStatus HM_EvaluateExactProgramV1(const HMExactProgramV1 *program,
                                         const uint32_t *inputs,
                                         uint32_t input_count,
                                         const HMTableViewV1 *tables,
                                         uint32_t table_count,
                                         uint32_t *scratch,
                                         uint32_t scratch_capacity,
                                         uint32_t *outputs,
                                         uint32_t output_capacity,
                                         uint32_t *output_count);

#ifdef HM_TEST
int HM_RunCContractLayoutTests(void);
#endif

#endif
