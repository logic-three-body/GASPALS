# 30. Motion-Matching

## Scope

This case covers `References/Motion-Matching` and validates the full train-to-inference loop:

```text
BVH dataset -> generate_database.py -> controller.exe --rebuild-features-only -> train_decompressor.py -> train_projector.py -> train_stepper.py -> controller.exe --lmm-enabled
```

## Automation Entry

- `Tools/reference/cases/Case-30-MotionMatching.ps1`
- `Tools/reference/Setup-ReferenceWalkthroughCases.ps1 -Cases 30 -Smoke`
- `Tools/reference/Test-ReferenceWalkthroughCases.ps1 -Cases 30 -Smoke`

## Startup

Primary startup:

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases 30 -Smoke
```

Manual runtime startup after build:

```powershell
.\References\Motion-Matching\controller.exe --lmm-enabled
```

## External Dependencies

- Ubisoft La Forge animation dataset subset
- raylib 5.5 win64 mingw-w64
- `g++`
- `make` or `mingw32-make`

## Required Outputs

- `resources/database.bin`
- `resources/features.bin`
- `resources/latent.bin`
- `resources/decompressor.bin`
- `resources/projector.bin`
- `resources/stepper.bin`
- `controller.exe`

## Verified Result

- `PASS`
- Latest verified report: `Saved/ReferenceCases/20260321-222237/reports/test-summary.md`
- The smoke run used `BUILD_MODE=DEBUG` on this Windows toolchain because the release path is unstable
