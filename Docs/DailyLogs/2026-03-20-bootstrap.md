# Daily Log - 2026-03-20

## Focus

- bootstrap the `GASPALS` shadow-mode workspace
- clone host + reference repos
- resolve versions and upstream relationships

## Facts Collected

- `GASPALS` cloned to `C:\Users\PC\Documents\COLMM\GASPALS` on `main` at `a6d3812545063f0954b4b80d632848f2eb8032e2`
- reference repos cloned under `References/`
- host engines confirmed:
  - Epic `UE 5.7.2`
  - Epic `UE 5.5.4`
  - Epic `UE 5.3.2`
  - source `UE 5.5.3`
- Unity confirmed at `2021.1.22f1c1`
- `GASPALS` is an exact upstream match to `PolygonHive/GASPALS`
- `ControlOperators` and `Learned_Motion_Matching_Training` are the only materially diverged forks in the current reference set
- `Learned_Motion_Matching_Training` includes a UE companion repo pinned to `Learned_Motion_Matching_UE5` commit `40f8b9329b7253d387f4b0bab662d09c990c86c4`

## Changes Made

- attached public `upstream` remotes for all cloned `logic-three-body/*` repos
- created Phase 0 audit docs under `Docs/`
- created `Plugins/GASPALSShadow` as a read-only observer/logging scaffold
- added local ignore rule for `References/`

## Risks / Blockers

- `Unreal-3rd-Person-Parkour` does not expose a semantic engine version in repo metadata; remain audit-only until actual editor/build validation
- `Learned-Motion-Matching` clone does not include a Unity project, only the training/export side of that pipeline
- training repo submodule expansion required a manual SSH clone because Git submodule materialization did not populate the worktree in this environment

## Next Actions

1. build the project with `UE 5.7.2` and confirm the new plugin compiles cleanly
2. attach `UGASPALSShadowObserverComponent` to the controlled sandbox character path
3. capture a first shadow log and validate the `control_to_lmm/v1` transform
