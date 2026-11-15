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

### P1 / P2 — roadmap

Aim constraint, transform (child-of) constraint, root-motion stride audit, chain IK (tails, tendrils)
and lightweight Verlet for hair / capes. None of them are needed to ship foot lock.

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
and headless tests) and `SpineBoneSource` (a thin, optional adapter for a spine-style runtime's
public bone accessors — see the note below).

## Acceptance, not vibes

```bash
godot --headless --path . --import                # once, builds the class cache
godot --headless --path . --script res://tests/run_tests.gd
```

Current result on Godot 4.7.2: **50 assertions, 0 failures**, covering:

| Criterion | Result |
|---|---|
| Locked ankle drift during a stance, at 100 px/m | 0.000 px (target frozen exactly) |
| Landing / release weight curve | monotonic, no 0→1 step, ≥ 0.03 s ramp |
| Bone stretch while locked | 0 by construction; solved ankle lands on target (≤ 0.0005 m) |
| 15° slope | foot follows the slope; tilt clamped to ±20° |
| Ground loss | state leaves `LOCKED`, weight → 0, `degraded` flagged |
| Double support | never both pinned beyond the overlap window |
| Global switch off | skeleton untouched (native A/B reproducible) |

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
| `D` | debug gizmo |

## Layout

```
addons/rigkit/core/      state machine, IK solver, probes, params, rig, physics sampler
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

**怎么接**：`addons/rigkit` 丢进项目，`rig.setup(...)` 传两腿的 thigh/shin/foot 骨骼，
`process_priority` 排在动画之后。没有 contact 曲线也能跑（用地面间隙反推落地信号）。

**怎么验**：`godot --headless --path . --script res://tests/run_tests.gd`，50 条断言，
覆盖 1px 漂移、零拉伸、15° 斜坡、掉地降级、双腿互斥、总开关。
