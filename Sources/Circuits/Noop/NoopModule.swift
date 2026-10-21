import Foundation

/// Directory-only conformance module: discovered through module.json, scheduled
/// at its phase every tic, commits an empty result, and shows up as a generic
/// telemetry row. It proves the discovery-to-production route without owning any
/// gameplay. Retire it when a real module takes this ID (frame composition).
final class NoopModule: CircuitModule {
    let descriptor = CircuitModuleDescriptor(
        id: UInt32(HM_MODULE_FRAME_COMPOSITION), name: "conformance.noop", phase: UInt32(HM_PHASE_WORLD_COMMIT),
        sourceHash: 0x6e6f_6f70_0001, requiredOutputs: 0, inputCapacity: 0, stateCapacity: 0,
        outputCapacity: 0, deltaCapacity: 0, eventCapacity: 0)
    func reference(_ invocation: ModuleInvocation) -> StagedResult { StagedResult() }
    func evaluate(_ invocation: ModuleInvocation) -> StagedResult { StagedResult() }
}
