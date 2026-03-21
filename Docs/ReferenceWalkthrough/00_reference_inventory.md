# GASPALS Reference Inventory

## Baseline

- Inventory capture date: `2026-03-21`
- Baseline command executed:

```powershell
git submodule update --init --recursive
git submodule status --recursive
```

- Captured status:

```text
f4f9f2e19ff54180a3df7aaa168d3c92dcc7442b References/ControlOperators
6853000f7d3443592c13161bdeaa4f071bebe488 References/Learned-Motion-Matching
5976e108f7d5a947f6af46e44face6d3697ef7ac References/Learned_Motion_Matching_Training
40f8b9329b7253d387f4b0bab662d09c990c86c4 References/Learned_Motion_Matching_Training/Learned_Motion_Matching_UE5
57b7250e0d34a4e456a34d47e24c2f05fdcc711e References/Motion-Matching
aba88f8e5dac03db2e538b6e78dabbcce001cb4d References/Unreal-3rd-Person-Parkour
```

## Inventory Table

| Project | Commit Hash | Guidance Source | Source Tag | Tech Stack | Minimal Run Goal | Can Directly Serve GASPALS? | Current Blockers |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `References/Learned_Motion_Matching_Training` | `5976e108f7d5a947f6af46e44face6d3697ef7ac` | `README.md`, `docs/RUNBOOK.md`, `docs/LESSONS_LEARNED.md` | `README_DRIVEN` | C++, Autodesk FBX SDK, PowerShell, Python, PyTorch, ONNX | Walk through `FbxToBinConverter.cpp -> generate_database.py -> train_decompressor.py -> train_projector.py -> train_stepper.py`; prefer `case-02`/`case-06` before full retrain | Yes, as offline LMM training and artifact vocabulary source | `FBXSDK_ROOT` is empty in current shell, so `case-01` cannot run yet; local base Python currently lacks `torch` and `onnxruntime`; note `actual dominant source = docs/` |
| `References/Learned_Motion_Matching_Training/Learned_Motion_Matching_UE5` | `40f8b9329b7253d387f4b0bab662d09c990c86c4` | `thesis.pdf`, `README.md` | `THESIS_DRIVEN` | UE5 C++, NNE, ONNX, PoseSearch, MotionTrajectory | Complete thesis-to-code mapping; do not port into GASPALS yet | Yes, as UE runtime comparison target for future LMM shadow node | No compile attempted in this phase; `Plugins/FeatureExtraction` is only an editor shell, not a finished extractor |
| `References/ControlOperators` | `f4f9f2e19ff54180a3df7aaa168d3c92dcc7442b` | `README.md`, paper page `https://theorangeduck.com/page/control-operators-interactive-character-animation`, article `https://theorangeduck.com/page/implementing-control-operators` | `PAPER_DRIVEN` | Python, Torch, raylib, cffi, `uv` | Lock a minimal `trajectory` control case using `UberControlEncoder`; runtime demo is secondary | Yes, as future control schema and encoder reference | `uv` exists locally, but current base Python lacks `torch`, `raylib`, `pyray`; `data/lafan1_resolved/` and pretrained controller files are absent |
| `References/Motion-Matching` | `57b7250e0d34a4e456a34d47e24c2f05fdcc711e` | `README.md`, article `https://theorangeduck.com/page/code-vs-data-driven-displacement`, LMM background `https://theorangeduck.com/page/learned-motion-matching` | `BLOG_DRIVEN` | C++, raylib, raygui, Python helpers, custom `.bin` network format | Treat as algorithm intuition sample; compile `controller.cpp` only if local raylib toolchain exists | Yes, for feature/query/search/inference intuition; no, for direct UE reuse | `C:\raylib` does not exist and `make` is not on PATH, so desktop/web build is blocked in the current shell |
| `References/Learned-Motion-Matching` | `6853000f7d3443592c13161bdeaa4f071bebe488` | `README.md`, Ubisoft La Forge paper `https://dl.acm.org/doi/10.1145/3386569.3392440` | `PAPER_DRIVEN` | Unity, PyTorch, ONNX, Barracuda | Walk through shipped `database/*.txt` and `onnx/*.onnx`; do not reconstruct the missing Unity sample project | Partially, as alternate LMM artifact vocabulary reference | Workspace contains only the PyTorch side and exported artifacts; Unity sample project is not included; current base Python lacks `torch` |
| `References/Unreal-3rd-Person-Parkour` | `aba88f8e5dac03db2e538b6e78dabbcce001cb4d` | `README.md`, `Source/`, `Config/` | `CODE_DRIVEN` | UE5 C++, Enhanced Input, PoseSearch, MotionWarping, Chooser | Static map of input/movement/animation/traversal boundaries; no need to compile in this phase | Yes, as future C++ structure and subsystem boundary reference | README is intentionally thin; meaningful understanding must come from source inspection rather than setup docs |

## Notes

- `git-lfs.exe` is available locally, and `References/Learned_Motion_Matching_Training/Animations/LAFAN1BVH/` already contains BVH files, so the training repo can be documented without first repairing asset fetch.
- `References/Learned_Motion_Matching_Training/ModelTraining/Data/` already contains:
  - `walk1_subject5.bin`
  - `run1_subject5.bin`
  - `pushAndStumble1_subject5.bin`
  - `boneParentInfo.bin`
- That fallback matters because `scripts/cases/case-02-generate-db.ps1` will automatically use `ModelTraining/Data/` when `Animations/LAFAN1BIN/` is incomplete.
- All GASPALS-facing judgments in the walkthrough set are constrained by:
  - `Docs/RepoRoleMap.md`
  - `Docs/RuntimeInsertionPoints.md`
  - `Docs/DataContract_Control_to_LMM.md`
