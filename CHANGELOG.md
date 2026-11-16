# Changelog

## 0.4.0 — 2026-11-16

- `PhysicsConstraint`: secondary motion driven by a damped spring offset, with the Spine 4.2
  parameter set (`inertia` / `strength` / `damping` / `mass` / `wind` / `gravity` / `limit` /
  `fps` / `mix`). Fixed step simulation with leftover-time carry, so the pose does not depend on
  the render rate; translation offsets are world space (documented deviation, since a
  `BoneSource` writes world transforms).
- Demo: a cape bone authored every frame, with physics on top of it.
- Tests: 158 -> 167 assertions (resting offset, `mix 0`, inertia lag and recovery, speed limit,
  frame-rate independence).

## 0.3.0 — 2026-11-16

- `TwoBoneAim`: aim a whole limb (shoulder -> elbow -> hand) at a world point. Lengths measured once,
  hand position clamped instead of bones stretched, elbow side from a world pole axis, optional hand
  orientation towards the target, damped target and a hard swing cap that applies from frame one.
- `ChainIK.tip_dir_*`: orient the last segment (claw / blade) after solving, with the reported end
  point rebuilt so it still matches the written pose.
- Ordering guarantee proven by test: a `TransformConstraint` registered after a `TwoBoneAim` reads the
  hand pose written in the same frame.
- Demo: a real two bone arm (shoulder / elbow / hand) aims at the cursor, the wand follows the hand
  through a child-of constraint instead of being parented to it.
- Tests: 145 -> 158 assertions.

## 0.2.0 — 2026-11-16

P1 / P2 of the runtime capability list.

- `AimConstraint`: point a bone at a world point or direction; range limit against the animation
  pose, hard angular speed cap, critically damped smoothing. Rotates only, never translates.
- `TransformConstraint`: child-of follow for sockets and props. Rotation always; position opt-in
  through the new optional `BoneSource.set_origin` (implemented by both bundled adapters).
- `RootMotionAudit`: root speed vs authored stride (`set_expected_from_stride`), `ok / fast / slow /
  stalled`, clamped playback-rate suggestion, `stride_out_of_tolerance` signal on the rig. Audits
  only; it never changes a clip or drags a foot.
- `ChainIK`: FABRIK for any number of segments, reach flag, length preserving write back.
- `VerletChain`: distance constraints, gravity, damping, optional floor, stiffness pull-back to the
  animation pose.
- `FootLockRig`: `add_constraint()` / `clear_constraints()` (run before the lock captures FK) and
  `set_root_audit()`; both surfaces are visible in `get_state()`.
- Demo: a wand bone aimed at the cursor (`A` toggles), stride audit telemetry.
- Tests: 50 -> 145 assertions (aim, transform, audit, chain IK, verlet, rig hook ordering).

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
