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

Current status: `PASS`.

## Added Script Surface

- `decompressor.py`
- `projector.py`
- `stepper.py`
- `misc/CustomFunctions.py`

## Automated Portion

- Release sample download and extraction
- Barracuda dependency injection when the manifest allows it
- Python dependency bootstrap
- Training script execution
- ONNX and text artifact synchronization
- Unity extraction and Barracuda inference validation against the Lafan sample

## Latest Verified Run

- `PASS`
- Latest verified report: `Saved/ReferenceCases/20260322-121814/reports/test-summary.md`
- Unity extraction passed for `Gameplay=Lafan`
- Unity validation passed after rebinding the sample's `NNModel` assets and exporting PyTorch models as single-file ONNX

## Current Artifacts

- `Saved/ReferenceCases/externals/l31/`
- `Saved/_l31/Learned Motion Matching/`
- `References/Learned-Motion-Matching/onnx/`
- `References/Learned-Motion-Matching/database/`

## Notes

- Unity 2021.1.22f1c1 + Barracuda on this machine does not accept the PyTorch exporter's default external-data ONNX layout.
- The case automation now forces single-file ONNX export for `compressor`, `decompressor`, `projector`, and `stepper`.
- The sample compatibility layer also patches Lafan bone-path resolution and reimports the `NNModel` assets before validation.
