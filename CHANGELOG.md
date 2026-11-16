# Changelog

## 0.7.0 — 2026-11-16

Scale and shear enter the contract, and the last four Spine runtime semantics that were missing
from the enhancement surface are now implemented. This is the "not just for chibi cartoons" release:
squash-and-stretch, skew, animated path spacing and IK compression all work, and every adapter
states honestly whether it can honour them.

- **`BoneSource` capability flags** — `CAP_ROTATE / CAP_TRANSLATE / CAP_SCALE / CAP_SHEAR /
  CAP_LOCAL_ROTATION / CAP_INHERIT` plus `supports()`. The base adapter still reports rotation
  only, so the "zero stretch by construction" guarantee is unchanged for every existing rig; scale
  and shear are opt-in extras that a constraint must ask for and must degrade honestly without.
- **Four adapters updated**: `DictBoneSource` implements every channel (it is the reference the
  constraints are tested against); `Node2DBoneSource` adds scale and local rotation but **refuses
  shear** (Node2D has no skew field); `SpineBoneSource` detects `set_scale_x/y`, `set_shear_x/y`,
  `set_inherit` at runtime and reports only what it found; `RigbyBoneSource` reports rotation +
  local rotation and admits it cannot scale.
- **`RigKitTypes.Inherit`** — the five Spine 4.x inherit modes, and `RigKitMath.local_rotation()`
  converting a world direction into the local rotation the host will actually compose, including
  the reflection sign for `noRotationOrReflection`. Writing the NORMAL formula into a bone that
  ignores its parent rotation is the silent failure this closes.
- **`TransformConstraint`** — `follow_scale` / `follow_shear` with `scale_offset`, `shear_offset`,
  `mix_scale`, `mix_shear`; telemetry reports `scale_followed`, `shear_followed` and an explicit
  `unsupported` list when the adapter cannot store the channel.
- **`PhysicsConstraint`** — Spine's `offsets scaleX/scaleY/shearX/shearY` on the same spring
  (`scale_enabled`, `shear_enabled`, `get_scale_offset()`, `get_shear_offset()`). Skipped and
  reported rather than faked when the capability is missing.
- **`TwoBoneIK`** — `allow_stretch` (Spine IK compress/stretch: keep the target, return
  `stretch_ratio`) and `softness` (ease the last band of the reach instead of snapping straight),
  plus `TwoBoneIK.apply_stretch()` which writes the ratio through `CAP_SCALE` or returns false.
- **`PathConstraint`** — `spacing_track` (Spine's `PathConstraintSpacingTimeline`): keyed spacing
  sampled by path distance and honoured by `step_chain()`, instead of a fixed constant.
- Tests: 252 → **308 assertions**, four new suites (`caps`, `spine_semantics`, `scale_shear`, plus
  the extended path suite), still a clean headless exit.

## 0.6.2 — 2026-11-16

- Android arm64 build of the patched Rigby2D library: the client's `.gdextension` has an
  `android.arm64` entry, so shipping only a patched dylib would leave Android with a runtime that
  cannot write bones. Cross-compiled against NDK 27.2 (`aarch64-linux-android24-clang`),
  `elf` arm64, 4.0 MB, built in 1m47s. Recipe and the no-device verification (gdext puts method
  names in the string table; `nm` reports 0 even for a working build) are in
  `docs/rigby2d-drive-patch.md`. Artifact sits next to the dylib in the spike's addon bin; the
  client binaries are untouched.

## 0.6.1 — 2026-11-16

- Suite harness no longer leaks: `FootLockRig` is a `Node2D`, and the suite built one per
  foot-lock case without ever freeing it, so every run ended with `ObjectDB instances leaked`,
  `CanvasItem` RID leaks and `resources still in use`. The rigs are now tracked and freed before
  `quit()`, which also clears the `Cannot get path of node as it is not in a scene tree` error the
  leaked nodes produced. No assertion changed: 252 passed, 0 failed, and the exit is clean.

## 0.6.0 — 2026-11-16

- `PoseSnapshot`: capture/restore of origins and directions for a bone set, with `delta()`,
  `max_angle()`, `max_distance()` and `is_unchanged()`. Restoring rotation before origin, because an
  adapter may derive one from the other. Bones are matched with `is_same`, **not** by a content key:
  a `Dictionary` bone changes the instant a constraint writes it, so a `var_to_str()` key stops
  matching exactly when the pose differs from the capture — the first version of this class did that
  and silently returned "no change" for every write.
- `MeshDeform`: linear blend skinning over a vertex array — `bind_vertex`, `capture_rest`, `deform`,
  `deform_point`, plus `bind_spine_vertices()` for Spine's `[boneCount, slots…, weights…]` layout.
  Rigid vertices keep their distance to neighbours, weights are normalised, vertices nobody bound
  are left where they are. This covers custom `MeshInstance2D` draws and lets weights be validated
  without the real runtime; it does not try to replace Spine's own mesh deformation.
- Tests: 217 -> 252 assertions (`pose`, `mesh` suites). Two of the new cases were wrong on the first
  run and fixed rather than excused: `AimConstraint.use_point` defaults to true so `target_dir` alone
  does nothing, and a vertex sitting exactly on the bone's joint cannot be moved by rotating that
  bone.

## 0.5.0 — 2026-11-16

- `RigPath`: arc-length parameterised polyline. Sampling by accumulated vertex length, not by
  segment index — the difference shows up the moment a path mixes a long run with short bends, where
  index-based sampling makes a tail accelerate through the short segments. Open paths clamp at both
  ends, closed paths wrap, a degenerate path returns the first point with a +X tangent instead of a
  NaN. `closest_distance()` matches a path to existing art, which is how an artist strokes a flow
  line and then hands it to the constraint.
- `PathConstraint`: the last constraint type of the Spine family RigKit had not covered (IK /
  Transform / Physics were already in). `position`, `position_ratio`, `wrap`, `translate`, `rotate`,
  `rotate_offset`, `mix`, plus `step_chain(bones, spacing)` for hair / cloth chains. Translation
  needs `BoneSource.set_origin()`; when the adapter refuses (Rigby2D and spine-godot are
  rotation-only) the rotation still applies and `translate_supported` turns false — the caller
  learns the limitation instead of wondering why a cape does not slide.
- Tests: 186 -> 217 assertions (`path` suite: arc length, clamping, wrapping, translate, tangent
  alignment, `mix 0`, ratio, chain spacing, rotation-only adapter). No existing assertion changed.

## 0.4.1 — 2026-11-16

- `SpineBoneSource.rotation_is_degrees` (default `true`): Spine runtimes report degrees, RigKit
  works in radians. Everything auto-detected — world read, axis helper, parent chain, write-back —
  is converted; callables passed through `api` stay the caller's own contract. This would have bent
  bones the wrong way on first contact with a real runtime.
- `RigbyBoneSource`: adapter for Rigby2D (烬塔's runtime), where bones are names and the tree lives
  in the skeleton JSON. Direction is the bone rotation itself, so `dir_offset` is always 0 — the
  `SpineBoneSource` "first child angle" heuristic would invent a 54 degree offset on a rig like
  `chest -> arm_ul (70, 120)`. `probe()` reports whether the runtime in front of it has the setter.
- `docs/rigby2d-drive-patch.md` + `docs/patches/rigby2d-bone-write.patch`: the two accessors Rigby2D
  is missing (`get_bone_world_rotation`, `set_bone_local_rotation`), why local not world, how to
  build, and the per-frame write contract. Upstream is MIT OR Apache-2.0; the patch adds no Spine
  runtime code.
- Verified on the real runtime: `player_rigby` (15 bones) with `TwoBoneAim` on
  `arm_ur -> arm_fr -> hand_r` and `PhysicsConstraint` on `cloak_root` — hand error 0.00 px over 240
  frames, cloak 12.4 deg / 8.6 px behind a ±0.22 rad torso sway. See `docs/real-rig-validation.md`.
- Tests: 175 -> 186 assertions (`rigby_adapter`: radians passthrough, local write, JSON tree,
  no child heuristic, probe).

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
