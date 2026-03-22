# Tools

`Tools/` contains sidecar utilities. It does not change the official `GASPALS` runtime paths.

## Directories

- `audit/`
  - workspace snapshots and repository comparison helpers
- `compare/`
  - upstream diff and post-check import helpers
- `export/`
  - payload export tools
- `training/`
  - packaging and notes for `Learned_Motion_Matching_Training`
- `reference/`
  - unified automation entry for the six `Docs/ReferenceWalkthrough` cases
  - handles preflight, downloads, environment setup, case orchestration, and markdown reporting

## Reference Automation

### Entrypoints

- `reference/Setup-ReferenceWalkthroughCases.ps1`
- `reference/Test-ReferenceWalkthroughCases.ps1`

### Shared Infrastructure

- `reference/common.ps1`
- `reference/cases/Case-10-11-LMM.ps1`
- `reference/cases/Case-20-ControlOperators.ps1`
- `reference/cases/Case-30-MotionMatching.ps1`
- `reference/cases/Case-31-LearnedMotionMatching.ps1`
- `reference/cases/Case-40-Parkour.ps1`

### Output Layout

- `Saved/ReferenceCases/<timestamp>/logs`
- `Saved/ReferenceCases/<timestamp>/reports`
- `Saved/ReferenceCases/externals/`
- `Saved/ReferenceCases/datasets/`

### Typical Usage

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\reference\Setup-ReferenceWalkthroughCases.ps1 -Cases all -Smoke
powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases all -Smoke
```

## Guardrails

- All downloads, logs, reports, and temporary sidecar projects stay under `Saved/ReferenceCases/`.
- Training script edits inside reference repos are allowed only when they are parameterization or automation shims.
- If an external dependency cannot be scripted, the wrapper must report `PASS`, `MANUAL`, or `BLOCKED` instead of silently skipping the case.
