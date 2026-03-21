# Export Scaffold

Phase 0-2 export work stays outside the formal locomotion runtime.

Planned responsibilities:

- read `Saved/Logs/GASPALSShadow/*/frames.jsonl`
- convert raw UE-space host samples into `control_to_lmm/v1`
- emit deterministic sidecar artifacts for:
  - offline comparison
  - training-data assembly
  - future shadow inference replay

Not allowed in this phase:

- writing back into Pose Search assets
- mutating AnimBP state
- replacing the live locomotion output path
