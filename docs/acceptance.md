# Acceptance record

Everything below is produced by the headless suite, not by eyeballing the demo.

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

Last run: **Godot 4.7.2**, 217 assertions, 0 failures.

## Mapping to the design checklist

| # | Criterion | Test | Measured |
|---|---|---|---|
| 1 | Locked sole drift ≤ 1 px per frame at 100 px/m on flat ground | `_test_world_lock_does_not_slide` | 0.00000 px (target frozen exactly, 3+ stances) |
| 2 | Landing → release weight continuous and monotonic, no 0→1 step, no single-frame spike | `_test_lock_ramp_is_monotonic`, `_test_ik_blend_monotonic` | monotonic, ramp ≥ 0.03 s |
| 3 | Bone stretch = 0 while locked (clamp the target, never the bones) | `_test_ik_clamped_no_stretch`, `_test_no_stretch_during_run` | solved ankle lands on target ≤ 0.0005 m; clamp ratio ≤ 0.02 |
| 4 | On a 15° slope the sole matches the slope, within ±20° tilt | `_test_probe_slope_clamped` | 15° followed, 45° clamped to 20° |
| 5 | Global switch reproduces native behaviour for A/B | `_test_enable_switch_is_pure_fk` | skeleton untouched when disabled |
| 6 | Both feet never locked at once; probe loss degrades instead of breaking the leg | `_test_double_support_guard`, `_test_ground_lost_degrades_to_fk` | weaker foot released after the overlap window; degraded flag set |

Supporting cases: reachable / unreachable IK targeting, knee side stability while the target crosses the
hip axis, `bend_sign` override, NaN rejection, degenerate bone lengths, both-probes-required, spike filtering.

## P1 / P2 acceptance

| Module | Criterion | Test | Measured |
|---|---|---|---|
| Aim | arrives at the target direction | `_test_aim_reaches_target` | ≤ 0.0005 rad after 3 frames, bone origin unchanged |
| Aim | hard angular speed cap | `_test_aim_speed_is_capped` | worst frame ≤ 90°/s × dt, still arrives |
| Aim | range limit against the animation pose | `_test_aim_range_limit` | deviation stops at 60.0° for `range_deg = 60` |
| Aim / Transform | weight 0 = native pose | `_test_aim_zero_weight_is_native`, `_test_transform_zero_weight_is_native` | bone untouched (1e-6) |
| Transform | follows socket rotation + offset | `_test_transform_follows_rotation` | converges to 0.7 rad within 0.01 |
| Transform | optional position follow | `_test_transform_follows_position` | exact target position, no smoothing |
| Audit | status + clamped suggestion | `_test_audit_ok`, `_test_audit_fast`, `_test_audit_stalled` | ok at 1.6 m/s, fast at 4 m/s, stalled at 0 |
| Chain IK | reaches / length preserved | `_test_chain_ik_reaches`, `_test_chain_ik_keeps_lengths` | end within 0.01; rebuilt pose within 0.001 |
| Chain IK | never stretches | `_test_chain_ik_unreachable` | end ≤ total length |
| Verlet | stiffness 1 reproduces FK | `_test_verlet_stiff_reproduces_fk` | ≤ 0.001 rad |
| Verlet | never stretches, always finite | `_test_verlet_keeps_length` | tip ≤ total length + 0.002, no NaN |
| Rig hooks | constraints run before the lock captures FK | `_test_rig_runs_constraints_and_audit` | constraint counted and applied, audit fed |
| Rig hooks | later constraint reads the pose an earlier one wrote | `_test_constraint_order_solves_then_follows` | hand and prop directions identical after one step |
| Two bone aim | reachable target, no stretch | `_test_two_bone_aim_reaches` | hand within 0.005 of target, rebuilt limb matches solver |
| Two bone aim | out of reach | `_test_two_bone_aim_clamps_far_target` | reached distance ≤ limb length, `clamped` flag |
| Two bone aim | swing cap from frame one | `_test_two_bone_aim_speed_is_capped` | worst frame ≤ 90°/s × dt, still arrives |
| Chain IK | last segment orientation | `_test_chain_tip_direction` | last bone lands on the requested direction, length intact |
| Physics | resting offset under gravity | `_test_physics_settles_under_gravity` | offset.y == gravity/strength ± 0.02, finite |
| Physics | `mix 0` is a no-op | `_test_physics_mix_zero_leaves_pose` | bone stays exactly on the animated pose |
| Physics | inertia lag, then recovery | `_test_physics_inertia_lags_then_recovers` | lags opposite to the move, settles back within 0.02 |
| Physics | speed limit | `_test_physics_limit_caps_speed` | translation speed never exceeds `limit` |
| Physics | frame rate independence | `_test_physics_fps_is_decoupled` | same offset at 60 Hz and 120 Hz render rates |

| Path | arc length, not segment index, drives the sample | `_test_path_sampling_is_arc_length` | 60 units into a 120 unit run lands at y = -60 |
| Path | open path clamps, closed path wraps | `_test_path_open_clamps`, `_test_path_closed_wraps` | clamp at both ends; 450 on a 400 closed path == 50 |
| Path | origin lands on the path, axis on the tangent | `_test_path_constraint_translates`, `_test_path_constraint_aligns_tangent` | point exact; -90.0 deg then 0.0 deg with `rotate_offset` |
| Path | `mix 0` is a no-op, `position_ratio` uses arc length | `_test_path_constraint_zero_mix`, `_test_path_constraint_ratio` | pose untouched (1e-6); 0.5 exactly half the length |
| Path | `step_chain` spaces the chain | `_test_path_constraint_chain_spacing` | three bones at 30, 60, 90 |
| Path | rotation-only adapters degrade | `_test_path_constraint_without_move_capability` | origin untouched, direction applied, flag false |

Total: **217 assertions, 0 failures**.

## Continuous integration

The GitHub Actions workflow is not enabled on this repository: running jobs fails at the account level
before the first step ("job was not started because your account is locked due to a billing issue"),
which has nothing to do with this code. The suite is a single command and needs no services, so it runs
identically locally:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

## Behaviour of `LockMode.ROOT_RELATIVE` (on purpose, not a bug)

`ROOT_RELATIVE` deliberately makes the target follow the root (`_test_root_relative_lock_follows_root`
asserts a target delta equal to the root delta). That mode exists for in-place cycles whose ankle
drifts against the body: the leg pose stays stable but the foot still slides in world space. The
per-frame ≤ 1 px criterion is therefore asserted against `WORLD` only — see `docs/design.zh.md` §3.

## Demo telemetry (real physics, real `ShapeCast2D`)

```bash
godot --headless --path . --quit-after 600 -- --stats
```

Example output on flat ground and the 15° ramp:

```
t=2.00s gait=plant ct=1.00  L LOCKED w=1.00 c=1.00 clamp=0.000 gnd=true | R FK w=0.00
t=2.50s gait=swing ct=0.00  L LIFT   w=0.00 c=0.00 clamp=0.000 gnd=true | R FK w=0.00
t=3.00s gait=plant ct=1.00  L LOCKED w=1.00 c=1.00 clamp=0.000 gnd=true | R FK w=0.00
```

`clamp=0.000` on the ramp is the interesting line: the planted foot holds a world point while the
body climbs, and the leg still never needs to stretch.
