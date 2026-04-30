# 31. Learned-Motion-Matching Unity Reference

## Scope

This case covers `References/Learned-Motion-Matching` and targets the full release-sample pipeline:

1. Download the upstream `v0.3.0` release sample
2. Prepare Unity and Barracuda
3. Run the parameterized PyTorch training scripts
4. Copy the generated ONNX and database text files back into the sample

## Automation Entry

- `Tools/reference/cases/Case-31-LearnedMotionMatching.ps1`
- `Tools/reference/Setup-ReferenceWalkthroughCases.ps1 -Cases 31 -Smoke`
- `Tools/reference/Test-ReferenceWalkthroughCases.ps1 -Cases 31 -Smoke`

## Startup

Primary startup:

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases 31 -Smoke
```

Manual sample startup:

```powershell
"D:\Program Files\Unity 2021.1.22f1c1\Editor\Unity.exe" -projectPath "D:\UE\COLMM\GASPALS\Saved\_l31\Learned Motion Matching"
```

Current status: `MANUAL / KNOWN ISSUE`.

## Added Script Surface

- `decompressor.py`
- `projector.py`
- `stepper.py`
- `misc/CustomFunctions.py`

## Recommended Paths

- `Lafan`
  Recommended learning path. Use this first to understand sample extraction, PyTorch training, ONNX sync, and Barracuda-side inference without the current Bunny runtime retargeting risk.
- `Bunny`
  Advanced diagnostic path. This uses the same sample and assets, but it is still gated by runtime pose-application and visual-stability checks. Treat it as an experiment path until the dual gate returns `PASS`.

## Automated Portion

- Release sample download and extraction
- Barracuda dependency injection when the manifest allows it
- Python dependency bootstrap
- Training script execution
- ONNX and text artifact synchronization
- Unity extraction for `Lafan + Bunny`
- Unity inference validation with dual gate:
  - `Lafan`: stable inference gate
  - `Bunny`: runtime plus visual-stability gate

## Toggle Meanings

- `Projector`
  Maps the current user query into the learned motion-matching state. Use this to test whether the query-to-state stage is stable.
- `Stepper`
  Rolls the learned state forward over time. Use this to isolate temporal drift from the projector and decompressor.
- `Decompressor`
  Decodes the learned state into the final pose. Turn this off first when isolating whether a Bunny issue lives in the decoder/presentation path or earlier in the state pipeline.

Recommended debug order:

1. `Lafan` with all three toggles enabled.
2. `Bunny` with `Decompressor` disabled.
3. `Bunny` with all three toggles enabled.

## Latest Verified Run

- `MANUAL / KNOWN ISSUE`
- Latest stable learning-path evidence remains the Lafan-side Unity extraction, training, ONNX sync, and Barracuda inference path.
- Case automation now targets `Gameplay=Lafan` and `Gameplay=Bunny` separately and will only restore `PASS` when both pass.
- Until then, the walkthrough should be interpreted as:
  - `Lafan`: recommended learner path
  - `Bunny`: diagnostic path under active runtime pose investigation

## Current Artifacts

- `Saved/ReferenceCases/externals/l31/`
- `Saved/_l31/Learned Motion Matching/`
- `References/Learned-Motion-Matching/onnx/`
- `References/Learned-Motion-Matching/database/`

## Notes

- Unity 2021.1.22f1c1 + Barracuda on this machine does not accept the PyTorch exporter's default external-data ONNX layout.
- The case automation now forces single-file ONNX export for `compressor`, `decompressor`, `projector`, and `stepper`.
- The sample compatibility layer also patches bone-path resolution and reimports the `NNModel` assets before validation.
- Previous automated validation primarily proved the Lafan path. Bunny still has a known runtime pose / visual-stability issue, so the case stays `MANUAL` until both gates pass.
