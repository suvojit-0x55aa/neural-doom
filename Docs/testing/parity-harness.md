# Parity harness

A module-neutral acceptance harness proves that a claimed circuit commits exactly the outputs, state deltas, and ordered events of its adapted C oracle. Later modules add fixtures and a manifest, not another test loop. Coverage stays 2 of 10; the harness implements no subsystem rule.

Files: `Tests/Parity/ParityFixture.swift` (fixture format), `ParityHarness.swift` (runner, validation, CPU/Metal exact evaluators, manifests, reporting), `SyntheticModule.swift` (conformance module and the `ParityRegistry`), `Tools/trace/hmf_inspect.py` (fixture/capture inspector).

## Adding a module

Implement `ParityModule` in your module's own directory and add it to `ParityRegistry.modules`. Supply:

| Piece | Purpose |
|---|---|
| `makeCase(seed:index:)` | Deterministic generator. The harness derives `seed` from the fixed base seed and `index`. |
| `adversarial()` | Named vectors with an expected status; a `Tamper` exercises envelope-validator statuses. |
| `oracle` | The adapted C reference result (the synthetic module uses an independent scalar model). |
| `cpu` / `metal` | CPU and Metal evaluators. `ExactProgramSpec` and `ExactMetalRunner` run `exact-i32-u32-v1` programs for both. |
| `manifestPath` | Committed manifest, regenerated with `--emit-parity-manifest`. |

Evaluators return a `RawResult`. The harness alone runs `HM_FinalizeModuleResultV1`, so every module gets the same ordering, capacity, hash, and no-partial-commit checks, and the canonical `HMR1` bytes are compared byte for byte. `TODO(T02)`: registration moves to descriptor discovery once `CircuitScheduler` lands; the registry array is the only line to change.

## Commands

```sh
CircuitTests --parity [--quick|--smoke|--micro]          # generic suite only
CircuitTests --parity-module conformance.synthetic       # one module
CircuitTests --emit-parity-manifest conformance.synthetic Docs/manifests/conformance-synthetic.json
CircuitTests --parity-capture conformance.synthetic .local/capture.hmfs 1000
CircuitTests --parity-replay .local/capture.hmfs         # oracle capture -> CPU + Metal
```

The default full run (`CircuitTests` with no flag) also runs the suite after the existing contract and map-table checks, before the stage-1/stage-2 command loops, which keep their own 100,000-snapshot and adversarial coverage unchanged. Case count follows the existing flags: 100,000 by default, 1,000 with `--quick`.

## Fixture format `HMF1` (version 1)

Little-endian 32-bit words: magic `HMF1`, fixture version, `CircuitModuleV1` ABI version, program version, module ID, tic ID, seed, source hash, map fingerprint (64-bit values as low/high words), expected status, output/delta/event capacities, then counted input, state, table (`id`, `capacity`, cells), output, delta (5 words), and event (12 words) sections, and finally the FNV-1a-64 of every preceding byte. That trailing hash is the content address. Parsing fails closed on any wrong magic or version, impossible count, trailing byte, short buffer, or hash mismatch. Captures are length-prefixed concatenations; only synthetic or Freedoom-licensed data may be captured into the repository.

## Manifest

`Docs/manifests/<module>.json` records the module ID, program version, source hash, base seed, the digest of the first 1,000 generated fixtures, and each adversarial vector's expected status and fixture hash. Tests regenerate it and require byte equality; a one-byte change is rejected.

## Evidence fields reported per module

- exact snapshot count and per-status tallies across oracle, CPU, and Metal;
- adversarial coverage of all 13 statuses, late completion, and mismatch localization (first differing field; the oracle result is the one committed on `parity-mismatch`);
- malformed fixture variants rejected, manifest freshness, regeneration determinism;
- visualization on/off result invariance; off mode records zero operation values and on mode samples one tic in four, at most 64 values each;
- latency p50/p95/p99/max separated into oracle, CPU evaluation, Metal dispatch encoding, Metal submit/wait, and validation/commit (accepted and rejected separately), plus a count of whole-tic budgets (1/35 s) exceeded. These are reports; no universal hardware gate is asserted.

## Synthetic conformance module

`conformance.synthetic` reuses an assigned module ID, claims no coverage, and runs one program touching every exact opcode with a 16-cell table, 8 inputs, 10 outputs, deltas against 8 state cells, and sound/message events. Named vectors cover integer extremes, angle wrap, zero/full delta spans, zero-length and capacity+1 spans, absent/negative/past-end table reads, add/divide overflow, divide by zero, and each envelope-validator rejection.
