# Repo Role Map

## Host Baseline

| Repo | Identity | Shadow-Mode Role | What We Use | What We Do Not Do |
| --- | --- | --- | --- | --- |
| `GASPALS` | Main UE runtime host | Production baseline and shadow host | Existing input stack, character blueprints, AnimBP, Pose Search, ALS overlays, logging surfaces | No Big Bang rewrite, no early AnimBP replacement, no early asset-layer migration |

## Runtime / Training References

| Repo | Upstream | Role | What We Use | What We Do Not Do |
| --- | --- | --- | --- | --- |
| `Unreal-3rd-Person-Parkour` | `CoffeeVampir3/Unreal-3rd-Person-Parkour` | UE C++ organization reference | C++ structure ideas for future component/plugin/runtime refactors | Not a host replacement for `GASPALS` |
| `Motion-Matching` | `orangeduck/Motion-Matching` | Core algorithm and Holden-style training reference | Database/features/latent/decompressor/projector/stepper flow; minimal non-UE validation logic | Not a UE runtime drop-in |
| `Learned-Motion-Matching` | `pau1o-hs/Learned-Motion-Matching` | Alternate Unity extraction + ONNX deployment reference | Unity-to-PyTorch-to-ONNX mental model; exported artifact vocabulary | Not a current runtime implementation inside `GASPALS` |
| `ControlOperators` | `gouruiyu/ControlOperators` | Control schema and encoder reference | Control contract design, raw gameplay input semantics, encoder schema shape | Not a finished Unreal runtime |
| `Learned_Motion_Matching_Training` | `E1P3/Learned_Motion_Matching_Training` | User-custom training pipeline | Windows-oriented preprocessing/training orchestration, ONNX validation, benchmark scripts | Not a direct replacement for the host runtime |
| `Learned_Motion_Matching_UE5` | `E1P3/Learned_Motion_Matching_UE5` | Training companion runtime | UE 5.3 deployment shape for NNE + ONNX model consumption | Not the host project; only a compatibility reference |

## Current Working Assumptions

- `GASPALS` remains the only formal runtime baseline.
- `References/*` are local independent working trees and are ignored by the host repo.
- Public upstreams are recorded for every `logic-three-body/*` repository currently present in the workspace.
- Any future takeover work must enter through additive, reversible hooks under `Plugins/GASPALSShadow`.
