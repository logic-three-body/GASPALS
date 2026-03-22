# Reference Inventory

## Scope

This inventory covers the six walkthrough cases under `Docs/ReferenceWalkthrough`:

- `10` `Learned_Motion_Matching_Training`
- `11` `Learned_Motion_Matching_UE5`
- `20` `ControlOperators`
- `30` `Motion-Matching`
- `31` `Learned-Motion-Matching`
- `40` `Unreal-3rd-Person-Parkour`

## Source Baseline

```powershell
git submodule update --init --recursive
git submodule status --recursive
```

## Current Status

| Case | Repo | Primary Guidance | Automation State |
| --- | --- | --- | --- |
| `10` | `References/Learned_Motion_Matching_Training` | repo README + runbook + case scripts | PASS |
| `11` | `References/Learned_Motion_Matching_Training/Learned_Motion_Matching_UE5` | thesis + README + UE source | PASS |
| `20` | `References/ControlOperators` | README + upstream articles | PASS |
| `30` | `References/Motion-Matching` | README + upstream articles | PASS |
| `31` | `References/Learned-Motion-Matching` | README + release sample | PASS |
| `40` | `References/Unreal-3rd-Person-Parkour` | source-first | PASS |

## Automation Entry

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\reference\Setup-ReferenceWalkthroughCases.ps1 -Cases all -Smoke
powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases all -Smoke
```

## Project Startup

- `10`: start the training pipeline with `powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases 10 -Smoke`
- `11`: start the UE companion with `powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases 11 -Smoke` or open `References\Learned_Motion_Matching_Training\Learned_Motion_Matching_UE5\Testing.uproject` in `UE_5.3`
- `20`: start the demo with `References\ControlOperators\.venv\Scripts\python.exe controller.py` after setup, or use `-Cases 20 -Smoke`
- `30`: start the desktop runtime with `References\Motion-Matching\controller.exe --lmm-enabled` after build, or use `-Cases 30 -Smoke`
- `31`: open `Saved\_l31\Learned Motion Matching` with Unity 2021.1.22f1c1, or use `-Cases 31 -Smoke` for the scripted path
- `40`: open `Saved\ReferenceCases\<timestamp>\case-40\ParkourSidecar\GameAnimationSample.uproject` with UE 5.4, or use `-Cases 40 -Smoke`

## Output Layout

- `Saved/ReferenceCases/<timestamp>/logs`
- `Saved/ReferenceCases/<timestamp>/reports`
- `Saved/ReferenceCases/externals/`
- `Saved/ReferenceCases/datasets/`

## Interpretation

- `10` and `11` are now validated as a linked training pipeline plus UE5 companion consumption path.
- `20` is validated through training plus a live `controller.py` demo launch.
- `30` is validated as a full data preparation, training, and runtime inference loop.
- `31` is now validated through Unity extraction, parameterized PyTorch training, ONNX sync, and Barracuda-side validation.
- `40` is validated through sidecar project generation, build, and editor probe.
