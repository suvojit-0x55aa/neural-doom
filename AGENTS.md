# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Build and test commands, bundled Freedoom provenance, and the current publication boundary are in `README.md`. Do not add proprietary WADs.
- `Tools/generate_project.py` is the source list for `NeuralDoom.xcodeproj`; rerun it after adding or removing target files.
- Keep DoomGeneric gameplay globals inside `Sources/DoomCore/g_game.c` and `Sources/Bridge/EngineBridge.c`. New circuit modules use the versioned boundaries in `Docs/architecture.md` and update `Docs/circuit-coverage.json`.
- `CircuitGraph` and `RemainderGraph` generate `Docs/locomotion-graph.json` and `Docs/tic-remainder-graph.json`; regenerate with `CircuitTests --emit-manifest ...` or `--emit-remainder-manifest ...`. The test executable rejects stale manifests.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
