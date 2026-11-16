# RigKit

Runtime rig extensions for Godot 4 — **foot lock, two-bone IK, ground probing, debug gizmos**.

A character animation that plays in place will slide its feet as soon as the body is driven by code
or physics. RigKit fixes that from the outside: it re-poses the leg *after* the animation system has
written the skeleton, so nothing in the art pipeline has to change — no extra bones, no baked root
motion, no editor plugin, no proprietary runtime.

```
animation pose  ──►  ground probes  ──►  foot lock state machine  ──►  two-bone IK  ──►  re-posed skeleton
```

## What it is / what it is not

| It is | It is not |
|---|---|
| A runtime re-poser for hip → knee → ankle chains | An animation editor, a timeline, a bone binding tool |
| Engine agnostic inside Godot (Node2D, Skeleton2D, custom skeletons, third-party runtimes) | A fork, wrapper or reimplementation of a commercial skeleton runtime |
| Deterministic math you can unit test headless | A "feel-based" tweak with no measurable acceptance |

RigKit never moves bones — it only writes rotations. Bone lengths are therefore immutable by
construction, which is why "zero stretch" is a guarantee rather than a tuning goal.

## Features

### P0 — shipped

- **Foot lock state machine** per foot (`FK → PRE_CONTACT → LOCKED → RELEASE → LIFT`), with hysteresis,
  monotonic weight ramps and a hard degradation path when the ground disappears.
- **Dual landing conditions**: a 0..1 contact signal (animation curve, provider callable, or manual)
  **and** both ground probes hitting. One alone does not lock.
- **Two-bone IK**: analytic solve, length preserving, knee side locked through a world-space pole axis,
  IK/FK angle blending with a minimum 0.03 s transition.
- **Two lock modes**: `WORLD` (foot frozen in world space — true no-slide) and `ROOT_RELATIVE`
  (target follows the root — for in-place cycles whose ankle drifts against the body).
- **Two-probe ground sampling** via `ShapeCast2D` (heel + toe), moving-average filtering, slope
  angle with a tilt clamp, one shared physics layer for ground / line of sight / blockers.
- **Safety guards**: leg-clamp fade (a locked foot can never straighten the leg into a snap),
  root-motion step guard, double-support guard (both feet pinned at once is time-limited, then the
  weaker foot must lift before it can land again), and a probe-loss fallback to animation.
- **Debug gizmo**: probes, hits, anchors, IK goals, leg lengths, state and weight text, plus a
  global on/off switch for A/B evidence.
- **Gait presets**: `walk` / `run` / `sprint` / `idle`.

### P1 — shipped

- **`AimConstraint`** — points one bone at a world point or direction, with a range limit against the
  animation pose, a hard angular speed cap and critically damped smoothing. Rotates only.
- **`TwoBoneAim`** — aim a whole limb (shoulder → elbow → hand) at a point: the pointer is solved
  by the two-bone solver, the elbow keeps its side, the hand can follow the aim direction. The
  canonical case for constraint ordering: register the arm first, then the prop that follows the hand.
- **`TransformConstraint`** — child-of follow for sockets / weapons: rotation always available,
  position opt-in through the optional `BoneSource.set_origin`, so IK chains are never moved.
- **`RootMotionAudit`** — measures root speed against the authored stride
  (`set_expected_from_stride(stride, steps_per_second)`), reports `ok / fast / slow / stalled` and a
  clamped playback-rate suggestion. It audits, it never silently "fixes" a mismatched clip by
  dragging the foot.

### P2 — shipped

- **`ChainIK`** — FABRIK for any number of segments (tails, tendrils, ropes). Points may move freely
  inside the solver, only directions are written back: a chain bends, it never stretches.
  `tip_dir_enabled` / `tip_dir` additionally orient the last segment (a claw, a blade) without
  breaking the length invariant.
- **`PhysicsConstraint`** — secondary motion for hair, cloth and tails, following the Spine 4.2
  physics constraint semantics one to one: `inertia`, `strength`, `damping`, `mass`, `wind`,
  `gravity`, `limit`, `mix`, and a fixed `fps` that decouples the simulation from the render rate.
- **`VerletChain`** — lightweight Verlet for hair / capes with distance constraints, gravity, damping,
  an optional floor and a stiffness knob that pulls the strand back to the animation pose.
- **`PoseSnapshot`** — captures and restores origins and directions of any bone set, plus
  `delta()` / `max_angle()` / `max_distance()`. This is the A/B switch ("run with the constraint,
  restore, run without, diff the pose") and the rest data [MeshDeform] binds against. Bones are
  matched **by identity**: a `Dictionary` bone mutates the moment a constraint writes it, so a
  content-based key would stop matching exactly when the pose changed.
- **`MeshDeform`** — linear blend skinning over a vertex array: `bind_vertex(index, bone, weight)`,
  `capture_rest()`, `deform(vertices)`. For custom `MeshInstance2D` / polyline draws that have no
  skeleton behind them, for validating exported weights without running the real runtime, and for
  asserting what a rig does to *geometry* rather than to bones. Weights are normalised, unbound
  vertices are left untouched, and `bind_spine_vertices()` parses Spine's per-vertex
  `[boneCount, slots…, weights…]` layout directly.
- **`PathConstraint`** + **`RigPath`** — lay bones on an arc-length parameterised curve: hair, tails
  and cloth follow a hand-authored flow instead of averaging between two bones. Spine's
  `position` / `rotate` / `translate` / `rotate_offset` / `mix` semantics, plus `step_chain()` for
  fixed spacing. The polyline is its own value object (no `Curve2D` scene dependency), samples by
  **arc length** rather than by segment index, so a path with one long segment does not move a tail
  twice as fast as one made of short segments. Adapters that cannot move bones (Rigby2D,
  spine-godot) keep the rotation part and report `translate_supported = false`.

## Install

1. Copy `addons/rigkit/` into your project's `addons/` folder.
2. That is it. The classes are `class_name` globals; enabling the plugin is optional (it only prints
   a line and exists so the asset shows up in the plugin list).

Requires Godot 4.4+. No third-party dependency, no native extension.

## Quick start

```gdscript
# Any Node2D bone hierarchy: bones authored along +X, each child placed at the parent's bone tip.
var source := Node2DBoneSource.new()

var rig := FootLockRig.new()
rig.params = RigKitParams.new()      # presets: walk / run / sprint / idle
rig.params.apply_preset("run")
add_child(rig)                        # probes are created under the rig
rig.setup(source, {
    "left":  {"upper": thigh_l, "lower": shin_l, "foot": foot_l, "knee_axis": Vector2(0.35, 1.0)},
    "right": {"upper": thigh_r, "lower": shin_r, "foot": foot_r, "knee_axis": Vector2(0.35, 1.0)},
}, character_root)                    # character_root drives ROOT_RELATIVE locking
```

Order matters: the animation system must write the pose **before** RigKit runs. With `Skeleton2D`
the default process order is enough; with `AnimationPlayer` driven rigs give the `FootLockRig`
a later `process_priority`.

### Landing signal

```gdscript
# 1) Animation curve (recommended): a 0..1 track, 0 = lifted, 1 = planted, >= 3 frames of blend.
rig.set_contact_provider("left", func() -> float: return contact_curve.sample(phase))

# 2) Manual value.
rig.set_contact("left", 1.0)

# 3) No curve at all: leave both unset and the rig derives contact from ground clearance.
```

### Constraints

```gdscript
# Aim: a wand / head / weapon follows the cursor or a target.
var aim := AimConstraint.new()
aim.bind(source, wand_bone)
aim.range_deg = 140.0        # never twist further than this from the animation pose
aim.max_speed_deg = 420.0    # hard cap, so a teleporting target cannot snap the neck
aim.set_target_point(get_global_mouse_position())
rig.add_constraint(aim)      # runs before the lock captures its pose

# Two bone aim: the whole arm reaches and points; the prop follows the solved hand.
var arm := TwoBoneAim.new()
arm.bind(source, upper_arm, forearm, hand_bone)
arm.set_knee_axis(Vector2(0, 1), 1.0)   # elbow points down, side forced
arm.set_target_point(mouse_world)
rig.add_constraint(arm)                  # first: solves the limb
rig.add_constraint(prop_follow)          # second: reads the hand solved above

# Child-of: a prop bone follows a socket, rotation + optional position.
var socket_follow := TransformConstraint.new()
socket_follow.bind(source, prop_bone)
socket_follow.target_node = hand_socket
socket_follow.follow_position = true
rig.add_constraint(socket_follow)
```

Everything else is usable standalone:

```gdscript
var audit := RootMotionAudit.new()
audit.set_expected_from_stride(1.6, 3.5)   # 1.6 m per step, 3.5 steps/s
rig.set_root_audit(audit)                    # -> state["audit"], stride_out_of_tolerance signal

var tail := ChainIK.new()
tail.bind(source, [tail_1, tail_2, tail_3, tail_4])
tail.solve(world_target, 0.7)

var cape := VerletChain.new()
cape.bind(source, [cape_1, cape_2, cape_3])
cape.gravity = Vector2(0.0, 2.4)
cape.step(delta, shoulder_origin, shoulder_dir)
```

### Custom skeletons and third-party runtimes

Implement five methods once and every feature works:

```gdscript
class MyBoneSource extends BoneSource:
    func get_origin(bone) -> Vector2            # world position of the joint
    func get_world_dir(bone) -> float           # world angle of the bone axis
    func get_dir_offset(bone) -> float          # 0 for +X rigs, -PI/2 for +Y rigs
    func set_world_dir(bone, dir, parent_rot)   # rotate only, never translate
    func get_parent_global_rotation(bone) -> float
    func get_length(bone) -> float              # optional, -1 = measure from rest pose
```

Bundled adapters: `Node2DBoneSource` (Node2D / Bone2D / Skeleton2D), `DictBoneSource` (data driven
and headless tests), `SpineBoneSource` (a thin, optional adapter for a spine-style runtime's
public bone accessors — see the note below), `RigbyBoneSource` (Rigby2D's `RigbySkeleton2D`: name
based bones, tree parsed from the skeleton JSON, needs the two-accessor patch in
`docs/rigby2d-drive-patch.md`).

## Acceptance, not vibes

```bash
godot --headless --path . --import                # once, builds the class cache
godot --headless --path . --script res://tests/run_tests.gd
```

Current result on Godot 4.7.2: **252 assertions, 0 failures**, covering:

| Criterion | Result |
|---|---|
| Locked ankle drift during a stance, at 100 px/m | 0.000 px (target frozen exactly) |
| Landing / release weight curve | monotonic, no 0→1 step, ≥ 0.03 s ramp |
| Bone stretch while locked | 0 by construction; solved ankle lands on target (≤ 0.0005 m) |
| 15° slope | foot follows the slope; tilt clamped to ±20° |
| Ground loss | state leaves `LOCKED`, weight → 0, `degraded` flagged |
| Double support | never both pinned beyond the overlap window |
| Global switch off | skeleton untouched (native A/B reproducible) |
| Aim speed cap | per-frame rotation ≤ cap at 60 fps, still arrives at the target |
| Aim range limit | never deviates further than `range_deg` from the animation pose |
| Constraints weight 0 | bone untouched (aim / transform / chain / verlet) |
| Transform follow | converges to socket rotation + offset; position follow exact with no smoothing |
| Stride audit | `ok` at the authored speed, `fast` / `stalled` otherwise, rate suggestion clamped |
| Chain IK | reaches a reachable target, segment lengths preserved, never exceeds total length |
| Verlet | stiffness 1 reproduces the animation pose, chain never stretches, always finite |
| Two bone aim | hand lands on a reachable target, clamps (never stretches) beyond the limb length |
| Two bone aim | speed cap enforced from the first frame, weight 0 leaves both bones untouched |
| Chain tip | last segment hits the requested world direction, chain length unchanged |
| Constraint order | a constraint registered after the aim reads the hand written in the same frame |
| Physics | gravity/strength settle at `gravity / strength`, `mix 0` writes nothing |
| Path | arc-length sampling (not per segment), open paths clamp, closed paths wrap |
| Path | bone lands on the sampled point, axis follows the tangent + `rotate_offset` |
| Path | `mix 0` leaves the pose alone, `position_ratio` maps to arc length, `step_chain` spaces bones |
| Path | adapter without origin writes still rotates and reports `translate_supported = false` |
| Snapshot | capture → constraint write → restore returns the exact authored pose; `delta` reports it |
| Mesh | a rigid vertex never changes distance to its neighbours, blend lands at the weighted midpoint |
| Mesh | weights normalise, unbound vertices stay put, Spine vertex arrays parse (bad data rejected) |
| Physics | inertia lags the pose then recovers, `limit` caps translation speed, offsets agree across render rates |

See [`docs/acceptance.md`](docs/acceptance.md) for the full mapping and the demo telemetry command:

```bash
godot --headless --path . --quit-after 600 -- --stats
```

## Demo

`demo/demo.tscn` builds a procedural biped walking over flat ground and a 15° ramp — no assets,
no third-party runtime.

| Key | Action |
|---|---|
| `SPACE` | rig on/off (compare against the raw animation) |
| `C` | landing signal: gait curve ↔ probe only |
| `1` `2` `3` | walk / run / sprint preset |
| `A` | arm aim on/off: the arm points at the cursor (orbit in headless runs), the wand follows the hand |
| `D` | debug gizmo |

## Layout

```
addons/rigkit/core/      state machine, two bone IK, chain IK, verlet, probes, constraints,
                         stride audit, params, rig, physics sampler
addons/rigkit/adapters/  Node2D / dict / spine-style bone sources
addons/rigkit/debug/     gizmo
demo/                    procedural demo scene
tests/run_tests.gd       headless acceptance suite
docs/                    design notes (zh) and acceptance record
```

## License and trademarks

MIT for everything in this repository — see [LICENSE](LICENSE). The code is an independent
implementation of textbook 2D IK and of a foot-lock state machine designed for this project; it
contains no code, data or tables copied from any commercial animation runtime, and it does not
reverse engineer one. It ships no third-party runtime: if you use a spine-style skeleton, you keep
your own licence for that runtime, and `SpineBoneSource` only calls its public bone accessors.
"Spine" is a trademark of its owner; this project is not affiliated with or endorsed by them.

## 中文速览

**解决什么**：原地循环动画 + 代码/物理驱动位移 = 必然滑步。RigKit 在动画写完之后重摆腿，
不改美术管线、不加骨骼、不进编辑器。

**四个部件**：双探针（脚跟/脚尖 `ShapeCast2D` 形状扫描）→ 锁脚状态机（四态 + 双条件落地 +
根相对/世界坐标两种锁法）→ 解析式双骨 IK（长度不可拉伸、膝盖轴向锁定、IK/FK 平滑混合）→
调试 Gizmo（锚点、目标、腿长、状态、权重）。

**P3 已补物理约束**：`PhysicsConstraint` 按 Spine 4.2 的参数语义（inertia / strength /
damping / mass / wind / gravity / limit / fps / mix）做逐骨次级运动，固定步长与渲染帧率解耦，
demo 里给角色挂了披风骨。

**P1/P2 已补齐**：Aim（单骨指向，带距动画姿态的角度范围和硬性角速度上限）、TwoBoneAim
（两骨手臂整条肢指向目标，肘部定向）、Transform（挂点跟随，位移可选且只走 `set_origin`）、
RootMotionAudit（步幅审计，只报告不改片速）、ChainIK（FABRIK，N 段链 + 末端朝向）、
Verlet（头发/披风，刚度回拉）。全部能单独用，也都能挂到 `FootLockRig.add_constraint()`，
在锁脚捕获姿态之前按注册顺序执行——"先解手臂、再跟手"这个顺序有专门的断言。

**怎么接**：`addons/rigkit` 丢进项目，`rig.setup(...)` 传两腿的 thigh/shin/foot 骨骼，
`process_priority` 排在动画之后。没有 contact 曲线也能跑（用地面间隙反推落地信号）。

**怎么验**：`godot --headless --path . --script res://tests/run_tests.gd`，252 条断言，
覆盖 1px 漂移、零拉伸、15° 斜坡、掉地降级、双腿互斥、总开关，以及 Aim/两步臂的权重与限速、
约束注册顺序、步幅审计的三态判定、链式 IK 的长度守恒与末端朝向、Verlet 的稳定性、物理约束的静止点与限速。
