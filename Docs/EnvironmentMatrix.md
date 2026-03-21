# Environment Matrix

## Host Runtime Inventory

| Runtime | Installed Version | Path | Notes |
| --- | --- | --- | --- |
| Unreal Engine | 5.7.2 | `D:\Program Files\Epic Games\UE_5.7` | Preferred exact-match host for `GASPALS` and any repo that declares UE 5.7. |
| Unreal Engine | 5.5.4 | `D:\Program Files\Epic Games\UE_5.5` | Preferred exact-match host for UE 5.5 repos when source build is not required. |
| Unreal Engine | 5.3.2 | `D:\Program Files\Epic Games\UE_5.3` | Preferred exact-match host for `Learned_Motion_Matching_UE5`. |
| Unreal Engine (source) | 5.5.3 | `D:\UE\UnrealEngine` | Only use when a repo explicitly needs source-level customization or engine patching. |
| Unity | 2021.1.22f1c1 | `D:\Program Files\Unity 2021.1.22f1c1` | Matches the user-reported Unity installation; no cloned repo currently includes a full Unity project. |
| Git | 2.46.0.windows.1 | system | SSH clone flow verified against GitHub. |
| Conda | 25.7.0 | system | Use isolated envs for Python/ML repos. |

## Repository Matrix

| Repo Name | Repo Type | Detected Version | Candidate Installed Engines | Installed Matching Version? | Selected Runtime Version | Selected Runtime Rationale | Risk Notes | Divergence From Upstream |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `GASPALS` | UE project + content plugin | `EngineAssociation = 5.7` from `GASPALS.uproject` | `UE 5.7.2`, `UE 5.5.4`, `UE 5.3.2`, source `UE 5.5.3` | Yes, `UE 5.7.2` | Epic `UE 5.7.2` | Exact semantic match on installed Epic build; no source-only requirement discovered in Phase 0. | Blueprint/content-heavy project; runtime insertion must stay additive. | Exact match to `PolygonHive/GASPALS` at audited HEAD `a6d3812545063f0954b4b80d632848f2eb8032e2`. |
| `ControlOperators` | Python / ML | `requires-python >= 3.11`; `torch`, `torchvision`, `raylib`, `clip` from `pyproject.toml` | N/A | N/A | Isolated conda env with Python 3.11+ | Repo publishes explicit Python floor and Windows/Linux support; keep separate from host UE env. | No lockstep conda env file; depends on CLIP git source and external demo data. | Diverged from `gouruiyu/ControlOperators`; 2 modified files. |
| `Motion-Matching` | Native C++ / algorithm reference | No explicit engine metadata; README documents `raylib`/`raygui` C++ demo and Python training scripts in `resources/` | N/A | N/A | Standalone native toolchain only | This repo is algorithm/training reference, not an engine runtime. | External Ubisoft dataset required to regenerate database/training inputs. | Exact match to `orangeduck/Motion-Matching` at audited HEAD `57b7250e0d34a4e456a34d47e24c2f05fdcc711e`. |
| `Learned-Motion-Matching` | Python training reference with external Unity runtime path | No `ProjectVersion.txt` in repo; README describes PyTorch training and ONNX export back into a Unity/Barracuda sample | Unity 2021.1.22f1c1 is available, but no Unity project files are present in this clone | No local project metadata to match against | Isolated Python env for training only | The cloned repo is the training/export half; Unity runtime remains a reference concept from the README. | Unity sample project is not part of this checkout. | Exact match to `pau1o-hs/Learned-Motion-Matching` at audited HEAD `6853000f7d3443592c13161bdeaa4f071bebe488`. |
| `Unreal-3rd-Person-Parkour` | UE C++ runtime reference | No explicit semantic version; `.uproject` stores machine-local GUID `EngineAssociation = {B243EBF4-67BF-403D-859A-041946B8C4DA}` | `UE 5.7.2`, `UE 5.5.4`, `UE 5.3.2`, source `UE 5.5.3` | Unknown | Defer until editor open/build metadata confirms exact engine | Hard rule is no version guessing; keep audit-only until engine compatibility is proven from project metadata or a successful open/build. | Project depends on UE-only sample assets and Git LFS. | Exact match to `CoffeeVampir3/Unreal-3rd-Person-Parkour` at audited HEAD `aba88f8e5dac03db2e538b6e78dabbcce001cb4d`. |
| `Learned_Motion_Matching_Training` | Mixed C++ preprocessing + Python training + UE companion submodule | README/runbook require Python 3.10+, VS C++ tooling, Autodesk FBX SDK, Git LFS | `UE 5.3.2` via companion submodule; other host engines available | Yes, for companion UE project only | Isolated Python env plus Epic `UE 5.3.2` for companion runtime | Root repo is training pipeline; runtime handoff is through the bundled UE submodule that declares UE 5.3. | No root env file; operational scripts and benchmark docs are fork-only additions. | Diverged heavily from `E1P3/Learned_Motion_Matching_Training`; 26 changed files plus submodule wiring. |
| `Learned_Motion_Matching_UE5` | UE runtime submodule | `EngineAssociation = 5.3` from `Testing.uproject` | `UE 5.3.2`, `UE 5.5.4`, `UE 5.7.2`, source `UE 5.5.3` | Yes, `UE 5.3.2` | Epic `UE 5.3.2` | Exact semantic match on installed Epic build; plugin set depends on NNE runtime availability. | Nested under training repo; currently audited as a companion runtime, not a host replacement. | Exact match to `E1P3/Learned_Motion_Matching_UE5` at audited HEAD `40f8b9329b7253d387f4b0bab662d09c990c86c4`. |

## Selection Policy Applied

1. Prefer exact-match Epic Launcher engines.
2. Fall back to exact-match source build only when the repo or task needs source-level changes.
3. If no semantic version is discoverable, do not guess; keep the repo audit-only and record the mismatch.
4. Keep Python/ML repos in isolated conda environments rather than relying on the missing default `py` launcher.
