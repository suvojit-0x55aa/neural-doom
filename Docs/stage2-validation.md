# Stage-two validation — complete tic command

Machine: MacBook Pro, Apple M5, 16 GB RAM; macOS 26.2; Xcode 26.5; arm64 Debug. Stage-one evidence is in [validation.md](validation.md). DoomGeneric is still the reference oracle and explicit fallback for both command modules; the eligible command and carried state are committed from the circuits before the ticker.

## Build and deterministic checks

Build both `NeuralDoom` and `CircuitTests` with the commands in `README.md`. The test executable checks the committed 178-operation/26-layer locomotion graph and 674-operation/83-layer remainder graph manifests. A full run compares **100,000 seeded in-domain snapshots per module** against the actual adapted upstream `G_BuildTiccmd`, the pure C extraction, the CPU evaluator, and Metal. All four locomotion outputs and all 21 remainder outputs/state cells had **zero C, CPU, or Metal mismatches**. The second suite also runs 61 adversarial stateful snapshots covering held/edge buttons, both double-click paths, weapon cycles, save overriding pause, low-resolution turn carry, chat, and consistency.

The tests reject 10 invalid locomotion input categories and an invalid remainder weapon enum, exercise explicit missing-Metal and deadline fallbacks, verify 1,000 inserts into each capacity-128 inspector ring leave 128 entries and count 872 drops, check seven pause/step assertions, compare 1,000 visualization-on/off evaluations per module, and bound every sampled output drill-down to 64 operations. With visualization off, no per-operation values are recorded. Visualization-on live tests produce four locomotion traces and two remainder traces over 24 tics. The final 1,000-warm-command standalone samples were locomotion median **0.368 ms**, p95 **0.523 ms**, p99 **0.916 ms** and remainder median **0.485 ms**, p95 **0.791 ms**, p99 **1.387 ms**. `--quick` provides a smaller smoke check.

## WAD-backed circuit ownership and pacing

The development trace used the bundled legal Freedoom Phase 1 IWAD and these opt-in flags:

```sh
HANDWIRED_DOOM_VISUALIZE=1 HANDWIRED_DOOM_AUTOPLAY=1 \
HANDWIRED_DOOM_TICCMD_SCRIPT=1 \
HANDWIRED_DOOM_TRACE_PATH="$PWD/.local/stage2.csv" \
HANDWIRED_DOOM_DATA_DIR="$PWD/.local" \
DerivedData/Build/Products/Debug/NeuralDoom.app/Contents/MacOS/NeuralDoom
```

In a 1,079-tic in-level run, both modules accepted **1,023 tics together**. Locomotion accepted 1,062 and fell back 16 times for its Metal deadline plus one startup-domain tic. Remainder accepted 1,027 and fell back 51 times for its Metal deadline plus the same startup-domain tic. There were **zero recorded comparison mismatches**. The trace changed player position 131 times and angle 100 times. Circuit-owned commands included attack, direct use, double-click use, weapon selection/cycling, two pause specials, a save special, chat byte `H`, and low-resolution turn carry. The inspector retained 128 samples for each module and dropped 136 locomotion and three remainder samples.

Before the product rename, the stage-two app was copied to `.local/clean-stage2/HandwiredDoom.app`. The bundle test verified its IWAD and both Metal shader resources. A direct launch of that copy with no IWAD flag or environment override logged `Freedoom: Phase 1` and `I_InitGraphics: DOOM screen size: w x h: 320 x 200`; it stayed live for five seconds. A second clean-copy scripted run recorded 372 in-level tics, 316 distinct positions, 102 angles, zero displayed-field mismatches, 362 tics accepted by both modules, 11 deadline fallback events across them, zero late tics, and zero catch-up tics. Both modules owned the pause, save, chat, and double-click commands in that run. Its accepted combined latency was median **1.349 ms**, p95 **2.111 ms**, p99 **2.651 ms**. These two WAD traces are separate samples, not pooled measurements.

| Accepted synchronous attempt | Median | p95 | p99 |
| --- | ---: | ---: | ---: |
| Locomotion, 1,062 tics | 0.559 ms | 1.207 ms | 1.471 ms |
| Remainder, 1,027 tics | 0.808 ms | 1.468 ms | 1.787 ms |
| Both accepted, 1,023 tics, summed | 1.384 ms | **2.465 ms** | 2.841 ms |
| Whole engine tic, 1,079 tics | 2.980 ms | 5.076 ms | 6.757 ms |

The **combined `<2 ms p95` gate remains open** even though each module individually met it in this sample. There was one late 35 Hz tic and zero catch-up tics. That late tic took 28.599 ms of engine work; its two circuit attempts totaled 1.425 ms, so the trace does not attribute it to a circuit deadline. It also cannot establish a universal no-missed-tics claim. A prior timed-semaphore wait caused many overshoots; the current short spin-poll reduced the observed late count to one at the cost of CPU during each wait. Frame interval data come from the host scheduler, not physical display capture. A separate M1-class run and human-observed keyboard/display evidence remain unavailable.

The CSV records each module's committed and reference command values, fallback reason, accepted latency, engine tic time, scheduling counters, and inspector counts. The runtime compares the full 21-cell remainder result even though the compact CSV prints only selected fields. Development logs and CSVs live under ignored `.local/`; no proprietary IWAD or trace is committed.
