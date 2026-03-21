# Training Scaffold

Primary training reference:

- `References/Learned_Motion_Matching_Training`

Current operational shape:

- case-based PowerShell orchestration under `scripts/cases`
- preprocessing via FBX SDK-backed C++ extractor
- Holden-style database generation and decompressor/projector/stepper training
- ONNX validation via `ModelTraining/validate_onnx_models.py`
- UE runtime handoff via `References/Learned_Motion_Matching_Training/Learned_Motion_Matching_UE5`

Phase 0-2 expectations:

- keep training environments isolated from the UE host
- treat generated artifacts as sidecar outputs
- use this folder for wrappers that call the training repo, not for forking the full pipeline into `GASPALS`
