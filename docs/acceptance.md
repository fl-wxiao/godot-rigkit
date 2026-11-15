# Acceptance record

Everything below is produced by the headless suite, not by eyeballing the demo.

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

Last run: **Godot 4.7.2**, 50 assertions, 0 failures.

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
