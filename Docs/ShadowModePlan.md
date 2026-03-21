# Shadow Mode Plan

## Phase Ladder

| Phase | Goal | Deliverables | Gate to Exit |
| --- | --- | --- | --- |
| 0. Bootstrap | Clone host/reference repos, resolve versions, map upstreams | `EnvironmentMatrix`, `RepoRoleMap`, `ForkDiffAudit` | All repos present, public upstreams recorded, host/runtime version policy fixed |
| 1. Host Observation | Add read-only shadow logging without changing formal locomotion output | `GASPALSShadow` plugin scaffold, `RuntimeInsertionPoints`, daily log | Plugin can write host snapshots into `Saved/Logs/GASPALSShadow` without gameplay-side takeovers |
| 2. Contract Stabilization | Freeze control-to-LMM payload contract | `DataContract_Control_to_LMM`, exporter/training scaffolds | Raw logs can be deterministically transformed into canonical control payloads |
| 3. Offline Comparison | Compare baseline host behavior against offline LMM/control reference outputs | compare/export tools, replay notebooks or scripts | Shadow outputs can be scored without touching the runtime path |
| 4. Live Shadow Inference | Run inference in parallel with host runtime, still read-only | shadow inference sidecar / plugin hooks, perf traces | No frame-critical regressions; host output remains baseline |
| 5. Local Takeover | Opt-in takeover of a narrowly scoped decision point | feature-flagged runtime experiment | Clear rollback path and measurable quality/perf gain |

## Current Phase Outcome

The workspace is now at the end of Phase 0 and the start of Phase 1:

- all requested repos are cloned locally
- upstream remotes are attached and audited
- the initial `GASPALSShadow` plugin exists as a read-only observer/logging scaffold
- no formal locomotion logic has been replaced

## Non-Negotiable Guardrails

- `GASPALS` remains the production runtime baseline.
- Shadow work is additive until performance and correctness are proven.
- No direct Pose Search database replacement during Phase 0-2.
- No AnimBP mainline replacement during Phase 0-2.
- No overlay selection takeover during Phase 0-2.

## Acceptance Gates for Future Takeover

Before any local takeover is allowed, all of the following must be true:

- baseline runtime remains reproducible on the same branch
- shadow logs capture enough state to replay or compare decisions
- control-to-LMM payload transform is versioned and deterministic
- inference cost is measured on target hardware
- rollback is one feature flag or one plugin disable away

## Rollback Strategy

- disable `GASPALSShadow` in the project plugin list to return to pure baseline
- keep all runtime observations in `Saved/Logs`, not in content assets
- keep reference repos under `References/` and out of the host repo history

## Immediate Next Steps

1. Verify the new plugin compiles in the UE 5.7 project context.
2. Add blueprint-side attachment for `UGASPALSShadowObserverComponent` to the possessed sandbox character.
3. Export one short host movement session and validate the `control_to_lmm/v1` transform on real data.
