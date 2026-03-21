# Data Contract: Control to LMM

## Status

This document is the contract source for any bridge from `ControlOperators` style inputs into future LMM shadow inference inside `GASPALS`.

Phase 0-2 rule:

- host runtime remains authoritative
- this contract governs shadow sampling and shadow feature construction only
- no code should invent a parallel schema outside this document

## Schema Version

- Contract id: `control_to_lmm/v1`
- Host log schema: `gaspals_shadow/v1`
- Canonical control encoder profile: current `UberControlEncoder` from `ControlOperators`

## Time Semantics

- Raw host samples store native UE frame timing:
  - `world_time_seconds`
  - `delta_seconds`
- Derived LMM features are resampled to a canonical `60 Hz` timeline.
- Canonical trajectory horizons are fixed to `20`, `40`, `60` frames at `60 Hz`.
  - `0.333333 s`
  - `0.666667 s`
  - `1.000000 s`
- Canonical velocity-facing lookahead is `0.25 s`, matching the current `UberControlEncoder`.

## Coordinate Semantics

### Raw Host Payload

- Raw samples remain in native Unreal world space:
  - forward = `+X`
  - right = `+Y`
  - up = `+Z`
- Raw control rotation is stored in UE-native rotator degrees.

### Derived LMM Payload

- Canonical LMM/control-operator frame is `X = right`, `Y = up`, `Z = forward`.
- Default axis remap from UE vectors is:
  - `LMM.x = UE.y`
  - `LMM.y = UE.z`
  - `LMM.z = UE.x`
- Default sign policy for Phase 0 is positive on all three remapped axes.
- Any later sign correction must be treated as a contract version bump, not an ad hoc runtime tweak.

## Raw Host Record Fields

| Field | Type | Meaning |
| --- | --- | --- |
| `frame_index` | int64 | Sequential shadow sample id. |
| `world_time_seconds` | double | UE world time of the sample. |
| `delta_seconds` | float | Host frame delta. |
| `actor_name` | string | Controlled pawn identity. |
| `input.move_stick` | `float2` | Normalized left-stick or equivalent move intent. |
| `input.look_stick` | `float2` | Normalized right-stick or equivalent facing/camera intent. |
| `input.left_trigger`, `input.right_trigger` | float | Analog trigger state. |
| `input.bDesiredStrafe`, `input.bDesiredWalk`, `input.bDesiredSprint`, `input.bJumpPressed`, `input.bCrouchRequested` | bool | Host locomotion intent flags. |
| `input.control_rotation` | rotator | Host control-space facing reference. |
| `movement.actor_location`, `movement.actor_rotation` | transform parts | Host actor transform. |
| `movement.velocity`, `movement.acceleration`, `movement.angular_velocity` | `float3` | Host motion state. |
| `movement.movement_mode`, `movement.custom_movement_mode` | enum/string + byte | Character movement state. |
| `trajectory[]` | array of `{local_position, local_direction, horizon_seconds}` | Future motion intent samples when available. |
| `animation.anim_instance_class`, `animation.active_montage`, `animation.overlay_base`, `animation.overlay_pose` | strings | Animation-side observation surface. |
| `traversal.*` | mixed | Traversal request / availability / chooser result shadow state. |
| `named_floats`, `named_strings` | maps | Escape hatch for blueprint-fed shadow metadata. |

## Canonical Control Payload

### Supported Modes

- `uncontrolled`
- `velocity_facing`
- `trajectory`

### Canonical Mode Shapes

#### `uncontrolled`

- payload: `null`

#### `velocity_facing`

- required:
  - `velocity : float3`
- optional:
  - `direction : float3`

Source rules:

- velocity comes from host velocity in canonical LMM axes
- direction is derived from control-facing intent when present
- if no explicit facing input is available, leave `direction = null`

#### `trajectory`

- payload: fixed array of 3 entries
- each entry contains:
  - `location : float3`
  - `direction : float3`
- entries are ordered by canonical horizon:
  - index `0` -> `0.333333 s`
  - index `1` -> `0.666667 s`
  - index `2` -> `1.000000 s`

## Encoder Output Contract

- Current `UberControlEncoder` emits `259` floats total:
  - `256` learned union-encoding channels
  - `3` one-hot control-type channels
- Shadow Mode stores raw payloads first.
- Any encoded control vectors produced later must be traceable back to the raw payload and schema version used to create them.

## Training / Runtime Hand-off

- `ControlOperators` contributes the control schema and canonical mode vocabulary.
- `Learned_Motion_Matching_Training` contributes the Holden-style database + `latent.bin` + `decompressor/projector/stepper` ONNX artifact vocabulary.
- `GASPALSShadow` writes raw shadow observations into `Saved/Logs/GASPALSShadow/.../frames.jsonl`.
- Future exporters under `Tools/export/` are responsible for transforming raw host logs into:
  - canonical control payloads
  - training-ready arrays or binaries
  - comparison-ready offline replay inputs

## Defaults Chosen in Phase 0

- canonical resample rate = `60 Hz`
- canonical trajectory horizons = `20/40/60` frames
- canonical velocity-facing lookahead = `0.25 s`
- raw host logs remain authoritative
- derived payloads are a deterministic transform of raw host logs
- no runtime takeover is allowed to bypass this contract during Shadow Mode
