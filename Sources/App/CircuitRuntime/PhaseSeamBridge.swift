import Foundation

/// Bounded stand-in for the future world-state store: remembers the most recent
/// committed results so the route is observable without owning any state.
final class CommitLedger {
    struct Entry { var moduleID: UInt32; var tic: UInt64; var outputs: Int; var deltas: Int; var events: Int }
    let capacity: Int
    private(set) var entries: [Entry] = []
    private(set) var total = 0
    init(capacity: Int = 256) { self.capacity = capacity; entries.reserveCapacity(capacity) }
    var sink: CommitSink {
        { [unowned self] id, tic, r in
            if entries.count == capacity { entries.removeFirst() }
            entries.append(Entry(moduleID: id, tic: tic, outputs: r.outputs.count, deltas: r.deltas.count, events: r.events.count))
            total += 1
        }
    }
}

/// Connects the reference-C phase seams to the scheduler. The tic-commands seam
/// opens a tic; the end of each phase runs that phase's generic modules, whose
/// results the scheduler stages, validates, and commits in order. With no
/// generic module registered this only counts tics and budget, so the C call
/// order and game state are untouched.
enum PhaseSeamBridge {
    private static var scheduler: CircuitScheduler?

    static func install(_ s: CircuitScheduler) {
        scheduler = s
        HM_SetPhaseSeamHook { phase, edge, _ in
            guard let s = PhaseSeamBridge.scheduler else { return }
            if phase == UInt32(HM_PHASE_TIC_COMMANDS) && edge == UInt32(HM_SEAM_BEGIN) {
                s.beginTic(s.ticID + 1)
            } else if edge == UInt32(HM_SEAM_END) {
                s.runPhase(phase)
            }
        }
    }
    static func uninstall() { HM_SetPhaseSeamHook(nil); scheduler = nil }
}
