# 10. LMM Training Pipeline

## Scope

This case covers `References/Learned_Motion_Matching_Training` and validates the full offline training chain:

```text
FBX/BVH -> BIN -> database.bin -> features.bin -> latent.bin -> 3x ONNX
```

## Automation Entry

- `Tools/reference/cases/Case-10-11-LMM.ps1`
- `Tools/reference/Setup-ReferenceWalkthroughCases.ps1 -Cases 10 -Smoke`
- `Tools/reference/Test-ReferenceWalkthroughCases.ps1 -Cases 10 -Smoke`

## Startup

Primary startup:

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases 10 -Smoke
```

Direct upstream path:

```powershell
powershell -ExecutionPolicy Bypass -File .\References\Learned_Motion_Matching_Training\scripts\cases\case-01-dataprocess.ps1
```

Then continue with `case-02` through `case-06` in the same folder.

## Execution Path

The wrapper runs the upstream case scripts in order:

1. `case-01-dataprocess.ps1`
2. `case-02-generate-db.ps1`
3. `case-03-train-decompressor.ps1`
4. `case-04-train-projector.ps1`
5. `case-05-train-stepper.ps1`
6. `case-06-validate-inference.ps1`

`Smoke` mode reduces the iteration counts but still produces the training artifacts and ONNX validation report.

## Inputs

- `Animations/LAFAN1BVH/*.bvh`
- Autodesk FBX SDK 2020.3.2 or a compatible Houdini FBX SDK path
- Visual Studio / MSBuild
- Git LFS payloads

## Outputs

- `ModelTraining/Database/database.bin`
- `ModelTraining/Database/features.bin`
- `ModelTraining/Database/latent.bin`
- `ModelTraining/Models/decompressor.onnx`
- `ModelTraining/Models/projector.onnx`
- `ModelTraining/Models/stepper.onnx`
- `ModelTraining/Misc/onnx_validation_report.md`

## Verified Result

- `PASS`
- Latest verified report: `Saved/ReferenceCases/20260321-223621/reports/test-summary.md`
- The generated artifacts were also synced into `Learned_Motion_Matching_UE5/Import/LMM`
