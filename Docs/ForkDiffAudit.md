# Fork Diff Audit

## Remote Map

| Repo | Origin | Public Upstream | Origin HEAD | Upstream HEAD | Status |
| --- | --- | --- | --- | --- | --- |
| `GASPALS` | `logic-three-body/GASPALS` | `PolygonHive/GASPALS` | `a6d3812545063f0954b4b80d632848f2eb8032e2` | `a6d3812545063f0954b4b80d632848f2eb8032e2` | Exact match |
| `ControlOperators` | `logic-three-body/ControlOperators` | `gouruiyu/ControlOperators` | `f4f9f2e19ff54180a3df7aaa168d3c92dcc7442b` | `950c203f21c1c9dc73ecea1179d4808582ac07c3` | Diverged |
| `Motion-Matching` | `logic-three-body/Motion-Matching` | `orangeduck/Motion-Matching` | `57b7250e0d34a4e456a34d47e24c2f05fdcc711e` | `57b7250e0d34a4e456a34d47e24c2f05fdcc711e` | Exact match |
| `Learned-Motion-Matching` | `logic-three-body/Learned-Motion-Matching` | `pau1o-hs/Learned-Motion-Matching` | `6853000f7d3443592c13161bdeaa4f071bebe488` | `6853000f7d3443592c13161bdeaa4f071bebe488` | Exact match |
| `Unreal-3rd-Person-Parkour` | `logic-three-body/Unreal-3rd-Person-Parkour` | `CoffeeVampir3/Unreal-3rd-Person-Parkour` | `aba88f8e5dac03db2e538b6e78dabbcce001cb4d` | `aba88f8e5dac03db2e538b6e78dabbcce001cb4d` | Exact match |
| `Learned_Motion_Matching_Training` | `logic-three-body/Learned_Motion_Matching_Training` | `E1P3/Learned_Motion_Matching_Training` | `5976e108f7d5a947f6af46e44face6d3697ef7ac` | `e0506dfe76111215a9b8d28ad58ae2e25fe5a1b4` | Diverged |
| `Learned_Motion_Matching_UE5` | `logic-three-body/Learned_Motion_Matching_UE5` | `E1P3/Learned_Motion_Matching_UE5` | `40f8b9329b7253d387f4b0bab662d09c990c86c4` | `40f8b9329b7253d387f4b0bab662d09c990c86c4` | Exact match |

## Exact-Match Repos

The following forks currently match their public upstream at the audited HEAD, so no additional fork-specific file divergence was detected:

- `GASPALS`
- `Motion-Matching`
- `Learned-Motion-Matching`
- `Unreal-3rd-Person-Parkour`
- `Learned_Motion_Matching_UE5`

For `GASPALS`, both `PolygonHive/GASPALS` and `PolygonHive/GASP-ALS` resolve to the same public HEAD. The audit uses `PolygonHive/GASPALS` as the canonical upstream label.

## Diverged Repo: `ControlOperators`

Diff summary against `upstream/main`:

- `2 files changed, 10 insertions(+), 4 deletions(-)`
- Modified files: `.gitignore`, `controller.py`

Functional divergence:

- `.gitignore` adds `*.zip` and `*.part`, which is an operational convenience for downloaded artifacts and partial transfers.
- `controller.py` changes model loading to `map_location=torch.device('cpu')`, reducing device-assumption risk on machines without the same CUDA path as upstream.
- `controller.py` also guards the non-flow-matching path by zeroing local velocities/angular velocities instead of calling the flow-matching decoder, which changes demo/runtime behavior but does not alter the published control schema.

Audit conclusion:

- The fork remains close to upstream and keeps the same public interface surface.
- The changes are operational/runtime-safety tweaks, not a schema rewrite.

## Diverged Repo: `Learned_Motion_Matching_Training`

Diff summary against `upstream/main`:

- `26 files changed, 1125 insertions(+), 74 deletions(-)`
- Structural additions: `.gitmodules`, `Learned_Motion_Matching_UE5` companion repo, `docs/*`, `scripts/*`, `ModelTraining/validate_onnx_models.py`
- Modified training files: `generate_database.py`, `train_decompressor.py`, `train_projector.py`, `train_stepper.py`, `DataProcessing/ThesisStuff.vcxproj`

Functional divergence:

- Adds a UE runtime companion via `Learned_Motion_Matching_UE5`.
- Adds Windows-first orchestration for six explicit cases: preprocess, database generation, decompressor, projector, stepper, inference validation.
- Adds ONNX validation and benchmark reporting that do not exist in the upstream baseline.
- Adds hardware-tuned operational knowledge for the current machine profile.

Audit conclusion:

- This fork is best treated as a custom operational training branch derived from the Holden-style pipeline, not as a passive mirror.
- The core lineage still tracks the upstream LMM training flow, but the execution model and validation surface are materially expanded.

## Audit Implications

- Exact-match forks can be treated as stable upstream mirrors for Phase 0-1 reference use.
- `ControlOperators` should be referenced with awareness that its runtime demo path is already patched for broader device compatibility.
- `Learned_Motion_Matching_Training` is the only repo that should be treated as a user-specific pipeline first and an upstream mirror second.
