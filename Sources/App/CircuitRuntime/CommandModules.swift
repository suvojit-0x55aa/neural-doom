import Foundation

/// Registers the two merged tic-command circuits as descriptors so they run
/// under the same budget, ordering, and telemetry policy as every later module.
/// Graphs, ABIs, domains, and 2 ms deadlines are unchanged; the C adapter still
/// calls them from inside G_BuildTiccmd, so this wrapper does not own dispatch.
final class LegacyCommandModule {
    let descriptor: CircuitModuleDescriptor
    let telemetry: ModuleTelemetry
    weak var scheduler: CircuitScheduler?

    init(id: UInt32, name: String, requiredOutputs: Int, inputCells: Int, stateCells: Int, sourceHash: UInt64,
         deadlineNs: UInt64 = 2_000_000) {
        descriptor = CircuitModuleDescriptor(
            id: id, name: name, phase: UInt32(HM_PHASE_TIC_COMMANDS), sourceHash: sourceHash,
            requiredOutputs: requiredOutputs, inputCapacity: UInt32(inputCells), stateCapacity: UInt32(stateCells),
            outputCapacity: UInt32(requiredOutputs), deltaCapacity: UInt32(stateCells), eventCapacity: 0, deadlineNs: deadlineNs)
        telemetry = ModuleTelemetry(descriptor: descriptor)
    }

    var asLegacy: LegacyModule { LegacyModule(descriptor: descriptor, snapshot: { [telemetry] in telemetry.snapshot() }) }

    static func code(for reason: String) -> UInt32 {
        switch reason {
        case "domain": return UInt32(HM_MODULE_UNSUPPORTED_DOMAIN)
        case "mismatch": return UInt32(HM_MODULE_PARITY_MISMATCH)
        case "metal-timeout": return FallbackCode.deadline
        case "metal-busy": return FallbackCode.busy
        default: return UInt32(HM_MODULE_EXECUTION_ERROR)
        }
    }

    /// Runs one existing evaluate call under the scheduler's whole-tic budget.
    func run<T>(setDeadline: (UInt64) -> Void, call: () -> T?, lastFallback: () -> String) -> T? {
        let allowed = scheduler?.legacyDeadline(for: descriptor) ?? descriptor.deadlineNs
        setDeadline(allowed)
        let begin = DispatchTime.now().uptimeNanoseconds
        let result = call()
        let ns = DispatchTime.now().uptimeNanoseconds - begin
        scheduler?.legacyFinished(elapsedNs: ns)
        if result != nil {
            telemetry.recordAccepted(attemptNs: ns, queueWaitNs: 0)
        } else if allowed == 0 && descriptor.deadlineNs > 0 {
            telemetry.recordFallback(FallbackCode.budget, attemptNs: ns)
        } else {
            telemetry.recordFallback(Self.code(for: lastFallback()), attemptNs: ns)
        }
        return result
    }
}
