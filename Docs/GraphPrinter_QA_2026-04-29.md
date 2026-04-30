# GraphPrinter QA Summary - 2026-04-29

Generated: 2026-04-29 20:04:44

## Counts
- Assets: total=86 ok=57 skip=20 fail=9
- Modules: ok=628 skip=27 fail=11

## Validation Commands
- Build: `D:\UE\UnrealEngine_Animation_Tech\Engine\Build\BatchFiles\Build.bat GASPALSEditor Win64 Development -Project="D:\UE\COLMM\GASPALS\GASPALS.uproject" -WaitMutex`
- Targeted: `$env:GPBATCH_FILTER='ABP_SandboxCharacter'; .\Tools\setup_and_launch.ps1`
- Targeted: `$env:GPBATCH_FILTER='ABP_OverlayPose_Base'; .\Tools\setup_and_launch.ps1`
- Targeted: `$env:GPBATCH_FILTER='ALI_Overlay'; .\Tools\setup_and_launch.ps1`
- Full: clear `GPBATCH_FILTER`, set `GPBATCH_QUIT_ON_FINISH=1`, then run `UnrealEditor.exe "D:\UE\COLMM\GASPALS\GASPALS.uproject" -ExecCmds="py D:\UE\COLMM\GASPALS\Tools\ue_open_assets.py" -log -abslog="D:\UE\COLMM\GASPALS\Saved\Logs\graphprinter_full_20260429.log" -unattended`
- Active graph smoke: `python Tools\ws_controller.py --timeout 120`

## Verified Conclusions
- Build succeeded; GraphPrinter targets were up to date with no compile errors.
- Full batch exited with code 0; log: `Saved\Logs\graphprinter_full_20260429.log`.
- No `Fatal error`, `Traceback`, or legacy `Failed to write widget information` in the full batch log.
- Every `OK` module PNG in `Saved\Screenshots\Blueprints\_index.json` exists and contains the `GraphEditor` text chunk.
- Every `FAIL` module has `Diagnostics.FailureStage=CanImportNodesFromTextFalse` and `Recovery.FailureReason=NoRecoverableContainerNode`.
- `Tools\asset_list.json` remains untouched; generated list is `Saved\Screenshots\Blueprints\_asset_list.json`.
- `Saved\Screenshots\_staging` has no residual PNG files after smoke cleanup.
- Active graph smoke passed with no `PackageName` request: `ABP_OverlayPose_Default`, 2 OK modules, `chunk=True`. The smoke launcher opened `ABP_OverlayPose_Base`; the restored active graph tab resolved to `ABP_OverlayPose_Default`, which still validates the active-graph path.

## Known Unrecoverable Modules
- 01_Core | ABP_SandboxCharacter | AnimGraph | AnimGraph_M025 | Fallback_006 | NoRecoverableContainerNode
- 01_Core | ABP_SandboxCharacter | OverlayBase | OverlayBase_M001 | Fallback_001 | NoRecoverableContainerNode
- 01_Core | ABP_SandboxCharacter | OverlayPose | OverlayPose_M001 | Fallback_001 | NoRecoverableContainerNode
- 06_Characters_Rigs | ABP_Manny_PostProcess | AnimGraph | AnimGraph_M006 | Fallback_002 | NoRecoverableContainerNode
- 06_Characters_Rigs | ABP_Quinn_PostProcess | AnimGraph | AnimGraph_M006 | Fallback_002 | NoRecoverableContainerNode
- 05_MetaHumans | Face_AnimBP | AnimGraph | AnimGraph_M008 | Fallback_004 | NoRecoverableContainerNode
- 05_MetaHumans | Face_PostProcess_AnimBP | AnimGraph | AnimGraph_M006 | Fallback_001 | NoRecoverableContainerNode
- 05_MetaHumans | m_med_nrw_animbp | AnimGraph | AnimGraph_M010 | Fallback_003 | NoRecoverableContainerNode
- 04_OverlaySystem | ABP_LayerBlending | AnimGraph | AnimGraph_M015 | Fallback_002 | NoRecoverableContainerNode
- 04_OverlaySystem | ALI_OverlayBase | OverlayBase | OverlayBase_M001 | Fallback_001 | NoRecoverableContainerNode
- 04_OverlaySystem | ALI_OverlayPose | OverlayPose | OverlayPose_M001 | Fallback_001 | NoRecoverableContainerNode

## Assets With Failures
- 01_Core | ABP_SandboxCharacter | NoRecoverableContainerNode; NoRecoverableContainerNode; NoRecoverableContainerNode
- 06_Characters_Rigs | ABP_Manny_PostProcess | NoRecoverableContainerNode
- 06_Characters_Rigs | ABP_Quinn_PostProcess | NoRecoverableContainerNode
- 05_MetaHumans | Face_AnimBP | NoRecoverableContainerNode
- 05_MetaHumans | Face_PostProcess_AnimBP | NoRecoverableContainerNode
- 05_MetaHumans | m_med_nrw_animbp | NoRecoverableContainerNode
- 04_OverlaySystem | ABP_LayerBlending | NoRecoverableContainerNode
- 04_OverlaySystem | ALI_OverlayBase | NoRecoverableContainerNode
- 04_OverlaySystem | ALI_OverlayPose | NoRecoverableContainerNode
