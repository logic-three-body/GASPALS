# 20. ControlOperators

## Scope

This case covers `References/ControlOperators` and now requires the full flow:

1. `uv sync`
2. `train.py` smoke training
3. `controller.py` demo launch

## Automation Entry

- `Tools/reference/cases/Case-20-ControlOperators.ps1`
- `Tools/reference/Setup-ReferenceWalkthroughCases.ps1 -Cases 20 -Smoke`
- `Tools/reference/Test-ReferenceWalkthroughCases.ps1 -Cases 20 -Smoke`

## Startup

Primary startup:

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases 20 -Smoke
```

Manual demo startup after setup:

```powershell
.\References\ControlOperators\.venv\Scripts\python.exe .\References\ControlOperators\controller.py
```

## Smoke Profile

```powershell
uv run train.py --niterations 1000 --batch_size 64 --device <cuda|cpu> --expr_name smoke
```

## Required Outputs

- `data/lafan1_resolved/database.npz`
- `data/lafan1_resolved/X.npz`
- `data/lafan1_resolved/Z.npz`
- `data/lafan1_resolved/autoencoder.ptz`
- `data/lafan1_resolved/UberControlEncoder/controller.ptz`

## Demo Rule

- Training success alone is not enough.
- `controller.py` must start and reach neural mode.
- If hardware input is missing, the result may be `MANUAL-HARDWARE`, but it must not fall back to bind pose.

## Verified Result

- `PASS`
- Latest verified report: `Saved/ReferenceCases/20260321-221742/reports/test-summary.md`
