# Neural Doom

## What is Neural Doom?

Neural Doom is a native macOS Doom port being rebuilt one subsystem at a time so **deterministic neural circuits** own gameplay and rendering. These are exact, frozen circuit graphs—not a trained probabilistic bot. DoomGeneric currently supplies the unported game engine and software renderer while each replacement is proved against the original behavior.

In the current public milestone, two Metal circuit modules own the complete `G_BuildTiccmd` command and its carried state on supported tics: player locomotion and the remaining command behavior. The authoritative [coverage ledger](Docs/circuit-coverage.json) tracks that boundary as 2 of 10 planned core modules. DoomGeneric leaves the runtime only after every gameplay and rendering module is circuit-owned; the replacement contract is documented in [Docs/architecture.md](Docs/architecture.md).

The app includes bundled **Freedoom Phase 1** for immediate play and a live circuit inspector toggled with **⌘⇧N**.

## Build and play

Requires Apple Silicon, macOS 14+, and Xcode. The project compiles its small Metal shaders from bundled source at runtime, so Xcode's optional offline Metal Toolchain component is not required.

```sh
xcodebuild -project NeuralDoom.xcodeproj -scheme NeuralDoom \
  -configuration Debug -derivedDataPath DerivedData \
  -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
open DerivedData/Build/Products/Debug/NeuralDoom.app
```

Arrow keys move/turn; Shift runs; Option strafes; Space uses; Control or left click fires. **⌘⇧N** toggles the live circuit inspector; its buttons Pause, Step one tic, and Resume control simulation at tic boundaries. The menu's **File → Open IWAD…** accepts a user-owned commercial IWAD or another local Freedoom IWAD as an optional override. It relaunches the app with the selected path because DoomGeneric's current loader is single-boot. For development, `--iwad /absolute/path/to/freedoom2.wad` or `FREEDOOM_IWAD=/absolute/path/to/freedoom2.wad` overrides the bundled default. Fresh installs keep config and saves under `~/Library/Application Support/NeuralDoom`; upgrades continue using an existing `~/Library/Application Support/HandwiredDoom` directory without moving or overwriting it. `HANDWIRED_DOOM_DATA_DIR` remains the explicit development override.

The included `Assets/freedoom1.wad` is **official Freedoom 0.13.0**, release archive SHA-256 `3f9b264f3e3ce503b4fb7f6bdcb1f419d93c7b546f4df3e874dd878db9688f59`, WAD SHA-256 `7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d`. Its BSD-style notice and credits are in `Assets/` and copied into the app. To keep local development data ignored, `.local/` is excluded from Git. No commercial WAD is copied or packaged.

## Test

```sh
xcodebuild -project NeuralDoom.xcodeproj -scheme CircuitTests \
  -configuration Debug -derivedDataPath DerivedData \
  -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
DerivedData/Build/Products/Debug/CircuitTests
DerivedData/Build/Products/Debug/CircuitTests --data-directory-compatibility
DerivedData/Build/Products/Debug/CircuitTests --app-bundle \
  "$PWD/DerivedData/Build/Products/Debug/NeuralDoom.app"
```

The parity executable compares 100,000 seeded locomotion snapshots and 100,000 full-command snapshots against **the actual upstream `G_BuildTiccmd`**, the pure C extraction, the CPU graphs, and the Metal graphs. It also tests 61 adversarial command/state snapshots, domain rejection, ring bounds/drops, pause/step scheduling, visualization invariance, and warm submit/wait latency. `--quick` runs 1,000 snapshots per module. `--emit-manifest Docs/locomotion-graph.json` and `--emit-remainder-manifest Docs/tic-remainder-graph.json` regenerate the graph manifests, which tests compare byte-for-byte to the committed versions. `--map-tables` runs only the WAD checks: `MapTablesV1` snapshots for synthetic micro-WADs, capacity+1 and adversarial rejections, bundled Freedoom E1M1 against `Docs/map-tables-e1m1.json`, CPU/Metal indexed reads, and parity with DoomGeneric's loaded structures (run in a child process). `--emit-map-manifest Docs/map-tables-e1m1.json` regenerates the manifest. `--parity` runs the module-neutral parity harness (oracle vs CPU vs Metal over canonical fixtures, with manifest freshness, latency, and visualization checks); see [Docs/testing/parity-harness.md](Docs/testing/parity-harness.md). For WAD-backed evidence and performance limits, see [Docs/stage2-validation.md](Docs/stage2-validation.md); [stage-one evidence](Docs/validation.md) remains as a checkpoint.

For a repeatable local WAD trace, launch the app with `HANDWIRED_DOOM_AUTOPLAY=1`, `HANDWIRED_DOOM_TICCMD_SCRIPT=1`, `HANDWIRED_DOOM_VISUALIZE=1`, and `HANDWIRED_DOOM_TRACE_PATH="$PWD/.local/stage2.csv"`. This development-only script sends native queued key/mouse events and injects otherwise hard-to-automate pause, save, chat, weapon-cycle, and low-resolution-turn inputs at fixed tics. Leave these flags unset for normal play. Trace files and optional alternate IWADs stay under ignored `.local/`.

## Sources

`Sources/DoomCore` contains only the 80 C translation units required by the native application plus upstream headers and GPL license. It is copied from DoomGeneric commit `e257a09527062bfb986b6e5e0780839b6cbd5b71`; only `g_game.c` carries the circuit adapter and test hooks. Handwired's execution model at commit `4ea7fcb27ebe93acf49b9f29a93e162b975bad46` informed the small affine/ReGLU/index-read IR. No TypeScript/browser code was embedded; its MIT license is included in `Docs/HANDWIRED-LICENSE.txt`. The canonical public repository is `https://github.com/suvojit-0x55aa/neural-doom`; publication and merges are separately gated by the captain. This worktree is a local development branch.
