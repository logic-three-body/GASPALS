# Environment Matrix

## Host Runtime Inventory

| Runtime | Detected Version | Path | Selected Usage |
| --- | --- | --- | --- |
| Unreal Engine | 5.3.2 | `D:\Program Files\Epic Games\UE_5.3` | `Learned_Motion_Matching_UE5` companion |
| Unreal Engine | 5.4.x | `D:\Program Files\Epic Games\UE_5.4` | `Unreal-3rd-Person-Parkour` primary target |
| Unreal Engine | 5.5.x | `D:\Program Files\Epic Games\UE_5.5` | `Unreal-3rd-Person-Parkour` fallback target |
| Unreal Engine | 5.7.x | `D:\Program Files\Epic Games\UE_5.7` | `GASPALS` host engine |
| Unity | 2021.1.22f1c1 | `D:\Program Files\Unity 2021.1.22f1c1\Editor\Unity.exe` | `Learned-Motion-Matching` sample |
| Conda | available | system | shared Python baseline `gaspals_ref_py311` |
| uv | available | system | `ControlOperators` |
| Git LFS | available | system | `Learned_Motion_Matching_Training`, `Parkour` assets |

## Reference Matrix

| Case | Repo | Runtime | Automation Entry | Current Status |
| --- | --- | --- | --- | --- |
| `10` | `References/Learned_Motion_Matching_Training` | `conda gaspals_ref_py311` + repo-local `.venvs/case-*` | `Tools/reference/cases/Case-10-11-LMM.ps1` | PASS |
| `11` | `References/Learned_Motion_Matching_Training/Learned_Motion_Matching_UE5` | `UE 5.3.2` | `Tools/reference/cases/Case-10-11-LMM.ps1` | PASS |
| `20` | `References/ControlOperators` | `uv` on Python 3.11 | `Tools/reference/cases/Case-20-ControlOperators.ps1` | PASS |
| `30` | `References/Motion-Matching` | Python 3.11 + raylib + g++/make | `Tools/reference/cases/Case-30-MotionMatching.ps1` | PASS |
| `31` | `References/Learned-Motion-Matching` | Python 3.11 + Unity 2021.1.22f1c1 | `Tools/reference/cases/Case-31-LearnedMotionMatching.ps1` | MANUAL |
| `40` | `References/Unreal-3rd-Person-Parkour` | `UE 5.4`, fallback `UE 5.5` | `Tools/reference/cases/Case-40-Parkour.ps1` | PASS |

## Startup Matrix

| Case | Primary Startup Method |
| --- | --- |
| `10` | `powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases 10 -Smoke` |
| `11` | `powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases 11 -Smoke` or open `Learned_Motion_Matching_UE5\Testing.uproject` with `UE_5.3` |
| `20` | `powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases 20 -Smoke` or run `References\ControlOperators\.venv\Scripts\python.exe controller.py` |
| `30` | `powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases 30 -Smoke` or launch `References\Motion-Matching\controller.exe --lmm-enabled` after build |
| `31` | `powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases 31 -Smoke`, then use `Lafan` as the recommended learning path and `Bunny` as the advanced diagnostic path in `Saved\_l31\Learned Motion Matching` |
| `40` | `powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases 40 -Smoke` or open `Saved\ReferenceCases\<timestamp>\case-40\ParkourSidecar\GameAnimationSample.uproject` with UE 5.4 |

## External Dependencies

| Dependency | Preferred Source | Used By | Notes |
| --- | --- | --- | --- |
| Autodesk FBX SDK 2020.3.2 | Autodesk APS FBX SDK page | `10` | script-first install attempt, fallback to manual if needed |
| raylib 5.5 win64 mingw-w64 | GitHub release zip | `30` | copied into `C:\raylib` |
| Ubisoft La Forge animation dataset | GitHub mirror / release asset | `30` | only the needed BVH subset is downloaded |
| `lmm-v0.3.0.zip` | GitHub release asset | `31` | release sample for Unity/PyTorch flow |
| Barracuda package | Unity manifest / local sample config | `31` | Unity sample requires single-file ONNX export plus compatibility handling |

## Policy

1. All orchestration goes through `Tools/reference/Setup-ReferenceWalkthroughCases.ps1` and `Tools/reference/Test-ReferenceWalkthroughCases.ps1`.
2. All logs, reports, downloads, and sidecar projects live under `Saved/ReferenceCases/`.
3. `Motion-Matching` and `Learned-Motion-Matching` are validated as full train-to-inference pipelines, not as static repo snapshots.
4. `PASS`, `MANUAL`, and `BLOCKED` must be recorded in the walkthrough docs and the generated reports.
