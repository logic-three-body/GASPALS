# 40. Unreal-3rd-Person-Parkour

## Scope

This case covers `References/Unreal-3rd-Person-Parkour` and is validated through a sidecar project instead of modifying the original project file.

## Automation Entry

- `Tools/reference/cases/Case-40-Parkour.ps1`
- `Tools/reference/Setup-ReferenceWalkthroughCases.ps1 -Cases 40 -Smoke`
- `Tools/reference/Test-ReferenceWalkthroughCases.ps1 -Cases 40 -Smoke`

## Startup

Primary startup:

```powershell
powershell -ExecutionPolicy Bypass -File .\Tools\reference\Test-ReferenceWalkthroughCases.ps1 -Cases 40 -Smoke
```

Manual editor startup uses the generated sidecar project, not the upstream `.uproject`:

```powershell
"D:\Program Files\Epic Games\UE_5.4\Engine\Binaries\Win64\UnrealEditor.exe" "D:\UE\COLMM\GASPALS\Saved\ReferenceCases\<timestamp>\case-40\ParkourSidecar\GameAnimationSample.uproject"
```

## Sidecar Policy

1. Create a sidecar project under `Saved/ReferenceCases/<timestamp>/case-40/`
2. Copy the upstream `.uproject`
3. Remove `DazToUnreal`
4. Junction `Config` and `Content`
5. Copy `Source` into the sidecar and apply compatibility patches there

## Engine Strategy

- Primary target: `UE 5.4`
- Fallback target: `UE 5.5`

## Automated Validation

- Generate project files
- Run `Build.bat`
- Launch a bounded editor probe

## Verified Result

- `PASS`
- Latest verified report: `Saved/ReferenceCases/20260322-101538/reports/test-summary.md`
