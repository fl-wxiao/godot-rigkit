# Changelog

## 0.1.0 — 2026-11-16

First public drop: the runtime half only.

- `FootLock` state machine (FK / LIFT / PRE_CONTACT / LOCKED / RELEASE) with dual landing conditions,
  hysteresis, monotonic weight ramps and probe-loss degradation.
- `TwoBoneIK` analytic solver: length preserving, pole-axis knee side, IK/FK blending.
- Two lock modes: `WORLD` (true no-slide) and `ROOT_RELATIVE` (in-place cycle compatibility).
- `GroundProbe` + `PhysicsProbeSampler`: heel/toe `ShapeCast2D` scans, moving-average filtering,
  slope angle with a ±20° tilt clamp.
- Safety: leg-clamp fade, root-step guard, double-support guard, global on/off switch.
- `Node2DBoneSource`, `DictBoneSource`, optional `SpineBoneSource` adapter.
- Debug gizmo, procedural demo (flat + 15° ramp), 50-assertion headless acceptance suite.

Planned: aim / transform constraints, root-motion stride audit (P1); chain IK, lightweight Verlet (P2).
