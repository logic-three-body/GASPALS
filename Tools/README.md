# Tools Scaffold

- `audit/`
  - workspace and repo metadata collection
  - version and SHA snapshot scripts
- `compare/`
  - upstream diff summaries
  - future baseline-vs-shadow replay comparators
- `export/`
  - future transforms from raw shadow logs to canonical training/inference payloads
- `training/`
  - references and wrappers for `Learned_Motion_Matching_Training`

These tools are intentionally read-only or sidecar-focused in Phase 0-2. They should not mutate the formal `GASPALS` locomotion path.
