# Validation evidence — Apple M5 local run

This is the stage-one checkpoint. [Stage-two validation](stage2-validation.md) records complete tic-command circuit ownership and the current performance limit. The publication boundary changed after this stage-one run.

Machine: MacBook Pro, Apple M5, 16 GB RAM; macOS 26.2; Xcode 26.5; arm64 Debug builds. The app uses runtime MSL compilation because this Xcode installation lacks the optional offline Metal Toolchain. This is a local build and no remote or PR was used.

## Build, parity, and unit checks

Both `HandwiredDoom` and `CircuitTests` arm64 targets built with `xcodebuild` and `CODE_SIGNING_ALLOWED=NO`. The final full test run used the committed graph manifest (`178` compiled live operations, `26` layers, hash `05cb2b70f251c2fe`):

```text
parity: 100000 generated snapshots versus original G_BuildTiccmd,
        C extraction mismatches 0, CPU mismatches 0, Metal mismatches 0
```

The executable also rejects 10 invalid domain categories; checked 1,000 ring appends at capacity 128 with 872 drops; asserted pause/step/resume behavior across seven checks; compared 1,000 visualization-on/off CPU results; and verified 24 live circuit tics produce four sampled traces while off mode records none. It checks the 64-operation drill-down bound, same-tic comparison, explicit domain/Metal/deadline fallbacks (including an injected 50 ms worker stall), and that the generated graph manifest is current. The final 1,000-warm-command standalone sample was median **0.336 ms**, p95 **0.903 ms**, p99 **1.248 ms**. An earlier sample after a sustained 100,000-command run reached p95 **4.593 ms**, so the isolated synchronous gate is load-sensitive and cannot be declared universally passed. Reproduce with `README.md` commands.

## Bundled IWAD and first launch

Freedoom Phase 1 is from official release `v0.13.0`; the release ZIP SHA-256 is `3f9b264f3e3ce503b4fb7f6bdcb1f419d93c7b546f4df3e874dd878db9688f59`; the bundled IWAD SHA-256 is `7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d`. The test copied the final built app to `.local/clean-final/HandwiredDoom.app`, then checked its resource through `Bundle(url:)` outside `Sources/`, the 12-byte IWAD header and directory bounds, SHA-256, and bundled license/credits. A direct launch of that copy from `/tmp` with **no IWAD environment variable, no CLI flag, and no picker** logged:

```text
adding .../.local/clean-final/HandwiredDoom.app/Contents/Resources/freedoom1.wad
Freedoom: Phase 1
I_InitGraphics: DOOM screen size: w x h: 320 x 200
```

The process remained live after five seconds. An earlier process sample showed the engine serial queue and MTKView draw path active. The first-run regression and its earlier picker-only symptom are described in `first-run-regression.md`.

## WAD-backed movement and pacing

A development-only `HANDWIRED_DOOM_AUTOPLAY=1` run inserted real key events through the same native host input queue (forward for 140 tics, then right-turn for 70); `HANDWIRED_DOOM_TRACE_PATH` wrote one output-only record per engine tic. The default bundled IWAD was used. The final visualization-on run can be repeated with the command below; source data and logs stay ignored under `.local/`:

```sh
HANDWIRED_DOOM_VISUALIZE=1 HANDWIRED_DOOM_AUTOPLAY=1 \
HANDWIRED_DOOM_TRACE_PATH="$PWD/.local/visual-bounded.csv" \
HANDWIRED_DOOM_DATA_DIR="$PWD/.local" \
DerivedData/Build/Products/Debug/HandwiredDoom.app/Contents/MacOS/HandwiredDoom
```

Before any deadline, an inspector-on trace observed one 300.697 ms Metal submit/wait and nine late tics. A later bounded completion wait still allowed command *encoding* to stall for 34.3 ms, producing one circuit-attributable late tic in a 1,419-tic trace. The final runtime moves the whole Metal attempt onto a dedicated queue, uses eight preallocated slots, and selects C after a 2 ms engine-side deadline. The final 42-second trace recorded **1,392 in-level tics, 0 mismatches, 1,356 circuit-owned commands, 36 Metal deadline fallbacks, 435 distinct positions, 78 distinct angles, 128 retained inspector samples, 210 dropped samples, 0 late tics, and 1 recovered catch-up tic**. Accepted circuit latency, including worker dispatch, was median **0.642 ms**, p95 **1.351 ms**, p99 **1.802 ms**. The 36 rejected attempts had median **2.664 ms**, p95 **8.346 ms**, p99 **10.555 ms**; the worst took **11.733 ms** by the time the engine resumed. Engine tic work was median **2.338 ms**, p95 **5.491 ms**, p99 **8.115 ms**. Produced-frame interval p95 was **42.176 ms**, which is a host timing observation rather than a measured display presentation interval. The observed 35 Hz pacing gate passed in this final run, but the worker deadline cannot prevent an OS scheduling pause and the result is one M5 sample, not a general latency guarantee. A separate M1-class run and real display-capture frame pacing remain unavailable.

Desktop screenshots and human key presses could not be captured in this session: `screencapture` reported `could not create image from display` and System Events automation was denied. The WAD-backed position/angle changes demonstrate gameplay movement driven by the circuit from host-injected key events; they do not prove the physical keyboard or on-screen pixels were seen by a person. The AppKit input and MTKView presentation paths build and run, and the process sample showed their active threads.
