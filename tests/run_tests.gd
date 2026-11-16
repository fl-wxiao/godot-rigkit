## Headless acceptance suite for RigKit.
##
## Run:
## [codeblock]
## godot --headless --path . --script res://tests/run_tests.gd
## [/codeblock]
##
## The cases mirror docs/acceptance.md, which in turn mirrors the P0/P.8 acceptance
## criteria the rig has to satisfy before it may replace a native runtime.
extends SceneTree

const DT: float = 1.0 / 60.0


## Minimal stand-in for a degree based runtime bone (spine-godot / Rigby2D shape):
## world rotation in degrees, parent chain, length, and a rotation setter.
class FakeDegreeBone:
	extends RefCounted
	var name: String = "bone"
	var rotation_deg: float = 0.0
	var parent: Variant = null
	var length: float = 10.0

	func get_world_rotation() -> float:
		return rotation_deg

	func set_rotation(value: float) -> void:
		rotation_deg = value

	func get_length() -> float:
		return length

	func get_parent() -> Variant:
		return parent
## Minimal stand-in for Rigby2D's patched `RigbySkeleton2D`: bones are names, world
## rotations are radians in Godot axes, and the setter takes a local rotation.
class FakeRigbyRuntime:
	extends RefCounted
	var rotations: Dictionary = {}
	var writes: Array = []

	func get_bone_position(bone_name: String) -> Vector2:
		return Vector2(bone_name.length(), 0.0)

	func get_bone_world_rotation(bone_name: String) -> float:
		return float(rotations.get(bone_name, 0.0))

	func set_bone_local_rotation(bone_name: String, radians: float) -> bool:
		writes.append([bone_name, radians])
		rotations[bone_name] = float(rotations.get(bone_name, 0.0)) + radians
		return true

const PX_PER_M: float = 100.0

var _pass: int = 0
var _fail: int = 0
var _suite: String = ""
var _messages: Array[String] = []


func _initialize() -> void:
	_run_suite("two_bone_ik", [
		_test_ik_reachable,
		_test_ik_clamped_no_stretch,
		_test_ik_knee_side,
		_test_ik_zero_weight,
		_test_ik_blend_monotonic,
		_test_ik_degenerate,
	])
	_run_suite("ground_probe", [
		_test_probe_flat,
		_test_probe_slope_clamped,
		_test_probe_needs_both_heel_and_toe,
		_test_probe_filter_rejects_spikes,
	])
	_run_suite("foot_lock", [
		_test_lock_ramp_is_monotonic,
		_test_world_lock_does_not_slide,
		_test_root_relative_lock_follows_root,
		_test_ground_lost_degrades_to_fk,
		_test_double_support_guard,
		_test_enable_switch_is_pure_fk,
		_test_no_stretch_during_run,
	])
	_run_suite("aim", [
		_test_aim_reaches_target,
		_test_aim_speed_is_capped,
		_test_aim_range_limit,
		_test_aim_zero_weight_is_native,
	])
	_run_suite("transform", [
		_test_transform_follows_rotation,
		_test_transform_follows_position,
		_test_transform_zero_weight_is_native,
	])
	_run_suite("root_audit", [
		_test_audit_ok,
		_test_audit_fast,
		_test_audit_stalled,
	])
	_run_suite("chain_ik", [
		_test_chain_ik_reaches,
		_test_chain_ik_keeps_lengths,
		_test_chain_ik_unreachable,
		_test_chain_ik_zero_weight,
		_test_chain_tip_direction,
		_test_chain_tip_keeps_length,
	])
	_run_suite("two_bone_aim", [
		_test_two_bone_aim_reaches,
		_test_two_bone_aim_clamps_far_target,
		_test_two_bone_aim_speed_is_capped,
		_test_two_bone_aim_zero_weight,
	])
	_run_suite("verlet", [
		_test_verlet_stiff_reproduces_fk,
		_test_verlet_keeps_length,
		_test_verlet_zero_weight,
	])
	_run_suite("spine_adapter", [
		_test_spine_adapter_degrees_to_radians,
		_test_spine_adapter_parent_chain,
		_test_spine_adapter_ignores_child_angle,
	])
	_run_suite("rigby_adapter", [
		_test_rigby_adapter_reads_radians,
		_test_rigby_adapter_write_is_local,
		_test_rigby_adapter_reads_json_tree,
		_test_rigby_adapter_has_no_child_heuristic,
		_test_rigby_adapter_probe,
	])
	_run_suite("physics", [
		_test_physics_settles_under_gravity,
		_test_physics_mix_zero_leaves_pose,
		_test_physics_inertia_lags_then_recovers,
		_test_physics_limit_caps_speed,
		_test_physics_fps_is_decoupled,
	])
	_run_suite("rig_hooks", [
		_test_rig_runs_constraints_and_audit,
		_test_constraint_order_solves_then_follows,
	])
	_print_summary()
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------- harness

func _run_suite(name: String, tests: Array) -> void:
	_suite = name
	print("\n== %s ==" % name)
	for test in tests:
		var before_fail: int = _fail
		var method_name: String = String(test.get_method())
		test.call()
		var ok: bool = _fail == before_fail
		print("  %s %s" % ["PASS" if ok else "FAIL", method_name])


func _check(condition: bool, message: String) -> bool:
	if condition:
		_pass += 1
		return true
	_fail += 1
	_messages.append("[%s] %s" % [_suite, message])
	print("    !! %s" % message)
	return false


func _check_close(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return _check(absf(actual - expected) <= tolerance, "%s (actual=%.6f expected=%.6f tol=%.6f)" % [message, actual, expected, tolerance])


# ---------------------------------------------------------------- two bone ik

func _test_ik_reachable() -> void:
	var ik: TwoBoneIK = TwoBoneIK.new()
	ik.bind_lengths(0.4, 0.4)
	var hip: Vector2 = Vector2.ZERO
	var target: Vector2 = Vector2(0.0, 0.7)
	var sol: Dictionary = ik.solve(hip, target, 1.0, PI * 0.5, PI * 0.5)
	_check(sol["valid"], "solution is valid")
	_check_close(float(sol["clamp_ratio"]), 0.0, 0.000001, "reachable target is not clamped")
	_check_close((sol["knee"] - hip).length(), 0.4, 0.001, "upper bone keeps its length")
	_check_close((target - sol["knee"]).length(), 0.4, 0.001, "lower bone keeps its length")
	_check_close((sol["target_clamped"] - target).length(), 0.0, 0.0001, "ankle reaches the requested target")


func _test_ik_clamped_no_stretch() -> void:
	var ik: TwoBoneIK = TwoBoneIK.new()
	ik.bind_lengths(0.4, 0.4)
	var hip: Vector2 = Vector2.ZERO
	var target: Vector2 = Vector2(0.0, 1.5)
	var sol: Dictionary = ik.solve(hip, target, 1.0, PI * 0.5, PI * 0.5)
	var clamped: Vector2 = sol["target_clamped"]
	var reach: float = 0.8 - ik.reach_epsilon
	_check_close((clamped - hip).length(), reach, 0.0005, "unreachable target is clamped to full reach")
	_check(float(sol["clamp_ratio"]) > 0.0, "clamp ratio reports the excess")
	var full_length: float = (sol["knee"] - hip).length() + (clamped - sol["knee"]).length()
	_check_close(full_length, 0.8, 0.0005, "solved knee keeps both bone lengths (zero stretch)")
	_check((sol["target_clamped"] - target).length() > 0.1, "the requested target is not silently reached")


func _test_ik_knee_side() -> void:
	var ik: TwoBoneIK = TwoBoneIK.new()
	ik.bind_lengths(0.4, 0.4)
	ik.knee_axis = Vector2(1.0, 0.0)
	var sol: Dictionary = ik.solve(Vector2.ZERO, Vector2(0.0, 0.7), 1.0, 0.0, 0.0)
	_check(float(sol["knee"].x) > 0.0, "knee bends towards the pole axis (right)")

	ik.knee_axis = Vector2(-1.0, 0.0)
	var sol_left: Dictionary = ik.solve(Vector2.ZERO, Vector2(0.0, 0.7), 1.0, 0.0, 0.0)
	_check(float(sol_left["knee"].x) < 0.0, "knee bends towards the pole axis (left)")

	ik.knee_axis = Vector2(1.0, 0.0)
	ik.bend_sign = 1.0
	var forced: Dictionary = ik.solve(Vector2.ZERO, Vector2(0.0, 0.7), 1.0, 0.0, 0.0)
	_check(float(forced["knee"].x) < 0.0, "bend_sign flips the pole derived knee side")
	ik.bend_sign = 0.0

	# Cross the hip axis a few times: the knee must not flip between frames.
	var previous_sign: float = 0.0
	var flips: int = 0
	for i in 60:
		var x: float = -0.1 + 0.2 * float(i) / 59.0
		var s: Dictionary = ik.solve(Vector2.ZERO, Vector2(x, 0.7), 1.0, 0.0, 0.0)
		var knee_sign: float = signf(float(s["knee"].x))
		if previous_sign != 0.0 and knee_sign != previous_sign:
			flips += 1
		previous_sign = knee_sign
	_check(flips == 0, "knee never flips while the target crosses the hip axis (flips=%d)" % flips)


func _test_ik_zero_weight() -> void:
	var ik: TwoBoneIK = TwoBoneIK.new()
	ik.bind_lengths(0.35, 0.3)
	var fk_upper: float = 1.2
	var fk_lower: float = 0.4
	var sol: Dictionary = ik.solve(Vector2.ZERO, Vector2(0.2, 0.6), 0.0, fk_upper, fk_lower)
	_check_close(float(sol["blend_upper"]), fk_upper, 0.000001, "weight 0 keeps the FK upper angle")
	_check_close(float(sol["blend_lower"]), fk_lower, 0.000001, "weight 0 keeps the FK lower angle")


func _test_ik_blend_monotonic() -> void:
	var ik: TwoBoneIK = TwoBoneIK.new()
	ik.bind_lengths(0.35, 0.3)
	var sol: Dictionary = ik.solve(Vector2.ZERO, Vector2(0.1, 0.55), 1.0, 0.0, 0.0)
	var full: float = absf(RigKitMath.angle_delta(0.0, float(sol["blend_upper"])))
	var previous: float = -1.0
	var monotonic: bool = true
	for i in 11:
		var w: float = float(i) / 10.0
		var s: Dictionary = ik.solve(Vector2.ZERO, Vector2(0.1, 0.55), w, 0.0, 0.0)
		var delta: float = absf(RigKitMath.angle_delta(0.0, float(s["blend_upper"])))
		if delta < previous - 0.0001:
			monotonic = false
		previous = delta
	_check(monotonic, "blend is monotonic across 0..1")
	_check(full > 0.0, "IK actually moves the bone when weight = 1")


func _test_ik_degenerate() -> void:
	var ik: TwoBoneIK = TwoBoneIK.new()
	ik.bind_lengths(0.0, 0.0)
	var sol: Dictionary = ik.solve(Vector2.ZERO, Vector2.ZERO, 1.0, 0.0, 0.0)
	_check(sol["valid"], "degenerate lengths fall back to a minimum instead of NaN")
	_check(not is_nan(float(sol["blend_upper"])), "no NaN in the blended angle")
	var nan_sol: Dictionary = ik.solve(Vector2(NAN, 0.0), Vector2.ZERO, 1.0, 0.0, 0.0)
	_check(not nan_sol["valid"], "NaN input is rejected")


# ---------------------------------------------------------------- ground probe

func _test_probe_flat() -> void:
	var probe: GroundProbe = GroundProbe.new(4)
	probe.ankle_height = 0.12
	probe.tilt_limit = deg_to_rad(20.0)
	probe.sampler = _flat_ground
	var sample: Dictionary = probe.sample(Vector2(0.0, 0.0))
	_check(sample["valid"], "flat ground sample is valid")
	_check_close(float(sample["height"]), 0.0, 0.001, "height comes from both probes")
	_check_close(float(sample["surface_angle"]), 0.0, 0.001, "flat ground has no slope")
	_check_close(float(sample["point"].y), -0.12, 0.001, "ankle target sits above the ground")


func _test_probe_slope_clamped() -> void:
	var probe: GroundProbe = GroundProbe.new(4)
	probe.ankle_height = 0.12
	probe.tilt_limit = deg_to_rad(20.0)
	probe.sampler = func(pos: Vector2) -> Dictionary:
		# 15 degree slope: y grows with x.
		var slope: float = deg_to_rad(15.0)
		return {"hit": true, "point": Vector2(pos.x, pos.x * tan(slope)), "normal": Vector2.UP}
	for i in 8:
		probe.sample(Vector2.ZERO)
	var sample: Dictionary = probe.sample(Vector2(0.1, 0.0))
	_check(sample["valid"], "slope sample is valid")
	_check_close(float(sample["surface_angle"]), deg_to_rad(15.0), deg_to_rad(2.0), "foot follows a 15 degree slope")

	var steep: GroundProbe = GroundProbe.new(4)
	steep.tilt_limit = deg_to_rad(20.0)
	steep.sampler = func(pos: Vector2) -> Dictionary:
		var slope: float = deg_to_rad(45.0)
		return {"hit": true, "point": Vector2(pos.x, pos.x * tan(slope)), "normal": Vector2.UP}
	for i in 8:
		steep.sample(Vector2.ZERO)
	var steep_sample: Dictionary = steep.sample(Vector2(0.1, 0.0))
	_check_close(float(steep_sample["surface_angle"]), deg_to_rad(20.0), deg_to_rad(0.5), "tilt is clamped to the limit")


func _test_probe_needs_both_heel_and_toe() -> void:
	var probe: GroundProbe = GroundProbe.new(4)
	probe.ankle_height = 0.12
	probe.sampler = func(pos: Vector2) -> Dictionary:
		# Only the toe finds ground - a ledge edge.
		if pos.x > 0.0:
			return {"hit": true, "point": Vector2(pos.x, 0.0), "normal": Vector2.UP}
		return {"hit": false}
	_check(not probe.sample(Vector2(0.0, 0.0))["valid"], "one missing probe invalidates the sample")


func _test_probe_filter_rejects_spikes() -> void:
	var probe: GroundProbe = GroundProbe.new(5)
	probe.ankle_height = 0.12
	probe.filter_frames = 5
	var counter: Array[int] = [0]
	probe.sampler = func(pos: Vector2) -> Dictionary:
		counter[0] += 1
		var spike: float = 0.25 if counter[0] % 2 == 1 else 0.0
		return {"hit": true, "point": Vector2(pos.x, spike), "normal": Vector2.UP}
	var heights: Array[float] = []
	for i in 10:
		var s: Dictionary = probe.sample(Vector2.ZERO)
		heights.append(float(s["height"]))
	var minimum: float = heights.min()
	var maximum: float = heights.max()
	_check(maximum - minimum < 0.18, "moving average flatens the spike (range=%.3f)" % (maximum - minimum))


# ---------------------------------------------------------------- foot lock

func _test_lock_ramp_is_monotonic() -> void:
	var params: RigKitParams = RigKitParams.new()
	var lock: FootLock = FootLock.new(params, "L")
	var frames: int = 0
	var rising: bool = true
	var previous: float = -1.0
	while frames < 40:
		lock.update(DT, {
			"root": Transform2D.IDENTITY,
			"fk_pos": Vector2(0.0, 0.0),
			"fk_foot_angle": 0.0,
			"contact": 1.0,
			"ground": _flat_sample(Vector2(0.0, 0.0)),
		})
		if lock.weight < previous - 0.000001:
			rising = false
		previous = lock.weight
		if lock.state == RigKitTypes.FootState.LOCKED and lock.locked_time > 0.5:
			break
		frames += 1
	_check(rising, "weight ramp is monotonic")
	_check(lock.state == RigKitTypes.FootState.LOCKED, "contact above threshold locks the foot")
	_check(params.locked_blend_time() >= 0.03, "blend time never drops under 0.03 s")
	_check(frames > 0, "the ramp takes more than one frame")
	_check_close(lock.weight, 1.0, 0.0001, "locked weight is 1")


func _test_world_lock_does_not_slide() -> void:
	var params: RigKitParams = RigKitParams.new()
	params.apply_preset("run")
	params.lock_mode = RigKitTypes.LockMode.WORLD
	var rig: FootLockRig = _make_rig(params, _flat_ground)
	# 2.0 m/s gait with a 0.18 s stance: the planted foot stays inside leg reach
	# while the body moves 0.36 m over the stance, which is what the 1 px rule
	# actually measures (per stance, not per step).
	var gait: Dictionary = _gait_new(2.0, 0.18, 0.12)
	var root_x: float = 0.0
	var episode_active: bool = false
	var episode_ref: Vector2 = Vector2.ZERO
	var worst_drift: float = 0.0
	var episodes: int = 0

	for i in 240:
		root_x += float(gait["speed"]) * DT
		_gait_advance(gait, DT)
		_pose_chain(rig, "left", Vector2(root_x - 0.06, -0.32), gait["ankle"])
		_pose_chain(rig, "right", Vector2(root_x + 0.06, -0.32), Vector2(root_x + 0.06, 0.0))
		rig.set_contact("left", float(gait["contact"]))
		rig.set_contact("right", 0.0)
		rig.root_transform = Transform2D(0.0, Vector2(root_x, 0.0))
		rig.step(DT)

		var left: Dictionary = rig.get_state()["left"]
		if left["state_name"] == "LOCKED":
			if not episode_active:
				episode_active = true
				episode_ref = left["target"]
				episodes += 1
			worst_drift = maxf(worst_drift, (Vector2(left["target"]) - episode_ref).length())
		else:
			episode_active = false

	_check(episodes >= 3, "the foot locked for several stances (episodes=%d)" % episodes)
	var drift_px: float = worst_drift * PX_PER_M
	_check(drift_px <= 1.0, "locked ankle drift stays at or under 1 px at 100 px/m (%.5f px)" % drift_px)
	_check_close(worst_drift, 0.0, 0.000001, "WORLD lock freezes the target exactly")


func _test_root_relative_lock_follows_root() -> void:
	var params: RigKitParams = RigKitParams.new()
	params.apply_preset("run")
	params.lock_mode = RigKitTypes.LockMode.ROOT_RELATIVE
	var rig: FootLockRig = _make_rig(params, _flat_ground)
	var gait: Dictionary = _gait_new(2.0, 0.18, 0.12)
	var root_x: float = 0.0
	var previous_target: Vector2 = Vector2.ZERO
	var in_episode: bool = false
	var max_delta: float = 0.0
	var expected_delta: float = float(gait["speed"]) * DT

	for i in 240:
		root_x += float(gait["speed"]) * DT
		_gait_advance(gait, DT)
		_pose_chain(rig, "left", Vector2(root_x - 0.06, -0.32), gait["ankle"])
		_pose_chain(rig, "right", Vector2(root_x + 0.06, -0.32), Vector2(root_x + 0.06, 0.0))
		rig.set_contact("left", float(gait["contact"]))
		rig.set_contact("right", 0.0)
		rig.root_transform = Transform2D(0.0, Vector2(root_x, 0.0))
		rig.step(DT)

		var left: Dictionary = rig.get_state()["left"]
		if left["state_name"] == "LOCKED":
			if in_episode:
				max_delta = maxf(max_delta, (Vector2(left["target"]) - previous_target).length())
			previous_target = left["target"]
			in_episode = true
		else:
			in_episode = false

	_check(in_episode or max_delta > 0.0, "the foot locked in root relative mode")
	_check_close(max_delta, expected_delta, 0.0005, "root relative target follows the root exactly")


func _test_ground_lost_degrades_to_fk() -> void:
	var params: RigKitParams = RigKitParams.new()
	var rig: FootLockRig = _make_rig(params, _flat_ground)
	rig.set_contact("left", 1.0)
	rig.set_contact("right", 0.0)
	for i in 30:
		rig.step(DT)
	var left: Dictionary = rig.get_state()["left"]
	_check(left["state_name"] == "LOCKED", "left foot locks on flat ground")

	# Drop the floor.
	rig.set_ground_sampler(func(_pos: Vector2) -> Dictionary: return {"hit": false})
	for i in 30:
		rig.step(DT)
	left = rig.get_state()["left"]
	_check(left["state_name"] != "LOCKED", "losing the ground releases the lock")
	_check(float(left["pose_weight"]) <= 0.0001, "pose weight falls back to animation")
	_check(left["degraded"] or left["state_name"] == "FK", "degradation is flagged or the foot is back on FK")


func _test_double_support_guard() -> void:
	var params: RigKitParams = RigKitParams.new()
	params.double_support_max = 0.1
	var rig: FootLockRig = _make_rig(params, _flat_ground)
	rig.set_contact("left", 1.0)
	rig.set_contact("right", 1.0)
	for i in 60:
		rig.step(DT)
	var state: Dictionary = rig.get_state()
	var both: bool = float(state["left"]["pose_weight"]) > 0.85 and float(state["right"]["pose_weight"]) > 0.85
	_check(not both, "both feet are not locked at the same time after the overlap window")
	_check(float(state["left"]["pose_weight"]) > 0.0 or float(state["right"]["pose_weight"]) > 0.0,
		"at least one foot stays planted")


func _test_enable_switch_is_pure_fk() -> void:
	var params: RigKitParams = RigKitParams.new()
	var rig: FootLockRig = _make_rig(params, _flat_ground)
	rig.set_contact("left", 1.0)
	rig.set_contact("right", 1.0)
	for i in 10:
		rig.step(DT)
	var before_dirs: Array[float] = _read_dirs(rig)
	rig.set_enabled(false)
	rig.step(DT)
	var after_dirs: Array[float] = _read_dirs(rig)
	_check(_arrays_equal(before_dirs, after_dirs), "disabled rig does not touch the skeleton (native A/B)")
	_check(not rig.get_state().get("enabled", true), "state reports the disabled switch")


func _test_no_stretch_during_run() -> void:
	var params: RigKitParams = RigKitParams.new()
	params.apply_preset("run")
	var rig: FootLockRig = _make_rig(params, _flat_ground)
	var gait: Dictionary = _gait_new(2.0, 0.18, 0.12)
	var root_x: float = 0.0
	var worst_error: float = 0.0
	var worst_clamp: float = 0.0
	var locked_frames: int = 0

	for i in 300:
		root_x += float(gait["speed"]) * DT
		_gait_advance(gait, DT)
		_pose_chain(rig, "left", Vector2(root_x - 0.06, -0.32), gait["ankle"])
		_pose_chain(rig, "right", Vector2(root_x + 0.06, -0.32), Vector2(root_x + 0.06, 0.0))
		rig.set_contact("left", float(gait["contact"]))
		rig.set_contact("right", 0.0)
		rig.root_transform = Transform2D(0.0, Vector2(root_x, 0.0))
		rig.step(DT)

		var left: Dictionary = rig.get_state()["left"]
		if left["state_name"] != "LOCKED":
			continue
		locked_frames += 1
		var chain: BoneChain = _rig_chains[rig]["left"]
		var hip: Vector2 = chain.hip_position()
		var upper_dir: float = chain.source.get_world_dir(chain.upper)
		var lower_dir: float = chain.source.get_world_dir(chain.lower)
		var ankle: Vector2 = hip + RigKitMath.dir(upper_dir) * chain.upper_length + RigKitMath.dir(lower_dir) * chain.lower_length
		var target: Vector2 = left["target"]
		worst_error = maxf(worst_error, (ankle - target).length())
		worst_clamp = maxf(worst_clamp, float(left["clamp_ratio"]))

	_check(locked_frames > 10, "the foot locked long enough to measure (frames=%d)" % locked_frames)
	_check(worst_error <= 0.0005, "solved ankle lands on the target (%.5f m)" % worst_error)
	_check(worst_clamp <= 0.02, "the leg is never clamped into an over-stretch (%.4f)" % worst_clamp)


# ---------------------------------------------------------------- helpers

# ---------------------------------------------------------------- aim

func _test_aim_reaches_target() -> void:
	var source: DictBoneSource = DictBoneSource.new()
	var bone: Dictionary = DictBoneSource.bone(Vector2.ZERO, 0.0, 0.4)
	var aim: AimConstraint = AimConstraint.new()
	aim.bind(source, bone)
	aim.smooth_time = 0.0
	aim.max_speed_deg = 0.0
	aim.set_target_point(Vector2(0.0, 1.0))
	for i in 3:
		aim.step(DT)
	_check_close(source.get_world_dir(bone), PI * 0.5, 0.0005, "aim reaches the target direction")
	_check(source.get_origin(bone).is_equal_approx(Vector2.ZERO), "aim never moves the bone origin")


func _test_aim_speed_is_capped() -> void:
	var source: DictBoneSource = DictBoneSource.new()
	var bone: Dictionary = DictBoneSource.bone(Vector2.ZERO, 0.0, 0.4)
	var aim: AimConstraint = AimConstraint.new()
	aim.bind(source, bone)
	aim.smooth_time = 0.0
	aim.max_speed_deg = 90.0
	aim.set_target_point(Vector2(-1.0, 0.0))
	var previous: float = source.get_world_dir(bone)
	var limit: float = deg_to_rad(90.0) * DT + 0.0005
	var worst: float = 0.0
	for i in 150:
		# An animation system rewrites the bone every frame; the aim sees a fresh
		# FK pose instead of its own previous output.
		source.set_world_dir(bone, 0.0, 0.0)
		aim.step(DT)
		var current: float = source.get_world_dir(bone)
		worst = maxf(worst, absf(RigKitMath.angle_delta(previous, current)))
		previous = current
	_check(worst <= limit, "aim per frame rotation %.4f rad <= %.4f rad" % [worst, limit])
	_check_close(absf(RigKitMath.angle_delta(0.0, source.get_world_dir(bone))), PI, 0.02, "aim still arrives after the speed cap")


func _test_aim_range_limit() -> void:
	var source: DictBoneSource = DictBoneSource.new()
	var bone: Dictionary = DictBoneSource.bone(Vector2.ZERO, 0.0, 0.4)
	var aim: AimConstraint = AimConstraint.new()
	aim.bind(source, bone)
	aim.smooth_time = 0.0
	aim.max_speed_deg = 0.0
	aim.range_deg = 60.0
	aim.set_target_point(Vector2(-1.0, 0.0))
	for i in 4:
		source.set_world_dir(bone, 0.0, 0.0)
		aim.step(DT)
	var deviation: float = absf(RigKitMath.angle_delta(0.0, source.get_world_dir(bone)))
	_check(deviation <= deg_to_rad(60.0) + 0.0005, "aim respects the range limit (%.2f deg)" % rad_to_deg(deviation))


func _test_aim_zero_weight_is_native() -> void:
	var source: DictBoneSource = DictBoneSource.new()
	var bone: Dictionary = DictBoneSource.bone(Vector2.ZERO, 0.0, 0.4)
	var aim: AimConstraint = AimConstraint.new()
	aim.bind(source, bone)
	aim.weight = 0.0
	aim.set_target_point(Vector2(0.0, 1.0))
	for i in 20:
		aim.step(DT)
	_check_close(source.get_world_dir(bone), 0.0, 0.000001, "aim weight 0 leaves the bone untouched")


# ---------------------------------------------------------------- transform

func _test_transform_follows_rotation() -> void:
	var source: DictBoneSource = DictBoneSource.new()
	var bone: Dictionary = DictBoneSource.bone(Vector2.ZERO, 0.0, 0.3)
	var socket: Node2D = Node2D.new()
	socket.rotation = 0.6
	var follow: TransformConstraint = TransformConstraint.new()
	follow.bind(source, bone)
	follow.target_node = socket
	follow.smooth_time = 0.05
	follow.rotation_offset = 0.1
	for i in 40:
		follow.step(DT)
	_check_close(source.get_world_dir(bone), 0.7, 0.01, "child follows the socket rotation plus offset")
	socket.free()


func _test_transform_follows_position() -> void:
	var source: DictBoneSource = DictBoneSource.new()
	var bone: Dictionary = DictBoneSource.bone(Vector2.ZERO, 0.0, 0.3)
	var socket: Node2D = Node2D.new()
	socket.position = Vector2(1.0, 0.5)
	var follow: TransformConstraint = TransformConstraint.new()
	follow.bind(source, bone)
	follow.target_node = socket
	follow.follow_rotation = false
	follow.follow_position = true
	follow.smooth_time = 0.0
	follow.step(DT)
	var origin: Vector2 = source.get_origin(bone)
	_check_close(origin.x, 1.0, 0.0005, "child follows socket x")
	_check_close(origin.y, 0.5, 0.0005, "child follows socket y")
	socket.free()


func _test_transform_zero_weight_is_native() -> void:
	var source: DictBoneSource = DictBoneSource.new()
	var bone: Dictionary = DictBoneSource.bone(Vector2.ZERO, 0.0, 0.3)
	var socket: Node2D = Node2D.new()
	socket.rotation = 1.0
	var follow: TransformConstraint = TransformConstraint.new()
	follow.bind(source, bone)
	follow.target_node = socket
	follow.weight = 0.0
	for i in 20:
		follow.step(DT)
	_check_close(source.get_world_dir(bone), 0.0, 0.000001, "transform weight 0 leaves the bone untouched")
	socket.free()


# ---------------------------------------------------------------- root audit

func _test_audit_ok() -> void:
	var audit: RootMotionAudit = RootMotionAudit.new()
	audit.set_expected_from_stride(1.6, 3.5)
	var position: Vector2 = Vector2.ZERO
	for i in 60:
		position.x += audit.expected_speed * DT
		audit.update(DT, position)
	_check(audit.status == "ok", "audit reports ok for matching stride (%s, ratio %.3f)" % [audit.status, audit.ratio])
	_check_close(audit.ratio, 1.0, 0.05, "audit ratio is 1 for a matching stride")


func _test_audit_fast() -> void:
	var audit: RootMotionAudit = RootMotionAudit.new()
	audit.expected_speed = 1.6
	var position: Vector2 = Vector2.ZERO
	for i in 60:
		position.x += 4.0 * DT
		audit.update(DT, position)
	_check(audit.status == "fast", "audit flags an outrunning root (%s)" % audit.status)
	_check(audit.suggested_rate <= audit.max_rate_scale + 0.0001, "suggested rate stays clamped")


func _test_audit_stalled() -> void:
	var audit: RootMotionAudit = RootMotionAudit.new()
	audit.expected_speed = 1.6
	for i in 40:
		audit.update(DT, Vector2.ZERO)
	_check(audit.status == "stalled", "audit flags a stalled root (%s)" % audit.status)


# ---------------------------------------------------------------- chain ik

func _make_chain(count: int, segment: float) -> Dictionary:
	var source: DictBoneSource = DictBoneSource.new()
	var bones: Array = []
	for i in count:
		var bone: Dictionary = DictBoneSource.bone(Vector2(i * segment, 0.0), 0.0, segment)
		bones.append(bone)
	var chain: ChainIK = ChainIK.new()
	chain.bind(source, bones)
	return {"source": source, "bones": bones, "chain": chain}


func _test_chain_ik_reaches() -> void:
	var rig: Dictionary = _make_chain(4, 0.25)
	var chain: ChainIK = rig["chain"]
	var result: Dictionary = chain.solve(Vector2(0.5, 0.5), 1.0)
	_check(result["valid"], "chain ik solves")
	_check(result["reachable"], "chain ik reports the target reachable")
	_check((result["end"] as Vector2).distance_to(Vector2(0.5, 0.5)) <= 0.01, "chain ik reaches the target")


func _test_chain_ik_keeps_lengths() -> void:
	var rig: Dictionary = _make_chain(4, 0.25)
	var chain: ChainIK = rig["chain"]
	var source: DictBoneSource = rig["source"]
	var bones: Array = rig["bones"]
	var result: Dictionary = chain.solve(Vector2(0.4, 0.6), 1.0)
	var rebuilt: Vector2 = source.get_origin(bones[0])
	for i in bones.size():
		rebuilt += RigKitMath.dir(source.get_world_dir(bones[i])) * chain.lengths[i]
	_check(rebuilt.distance_to(result["end"]) <= 0.001, "written pose matches the solver (no stretch)")


func _test_chain_ik_unreachable() -> void:
	var rig: Dictionary = _make_chain(3, 0.2)
	var chain: ChainIK = rig["chain"]
	var result: Dictionary = chain.solve(Vector2(2.0, 0.0), 1.0)
	_check(not result["reachable"], "chain ik reports an unreachable target")
	var root: Vector2 = (rig["bones"][0] as Dictionary)["origin"]
	_check((result["end"] as Vector2).distance_to(root) <= chain.total_length() + 0.001, "chain never stretches past its total length")


func _test_chain_ik_zero_weight() -> void:
	var rig: Dictionary = _make_chain(3, 0.2)
	var chain: ChainIK = rig["chain"]
	var source: DictBoneSource = rig["source"]
	var bones: Array = rig["bones"]
	chain.solve(Vector2(0.0, 0.5), 0.0)
	for bone in bones:
		_check_close(source.get_world_dir(bone), 0.0, 0.000001, "chain ik weight 0 leaves bones untouched")


# ---------------------------------------------------------------- two bone aim

func _make_arm() -> Dictionary:
	var source: DictBoneSource = DictBoneSource.new()
	var upper: Dictionary = DictBoneSource.bone(Vector2(0.0, -0.5), 0.0, 0.22)
	var lower: Dictionary = DictBoneSource.bone(Vector2(0.22, -0.5), 0.0, 0.22)
	var tip: Dictionary = DictBoneSource.bone(Vector2(0.44, -0.5), 0.0, 0.06)
	var aim: TwoBoneAim = TwoBoneAim.new()
	aim.bind(source, upper, lower, tip)
	aim.smooth_time = 0.0
	aim.max_speed_deg = 0.0
	return {"source": source, "upper": upper, "lower": lower, "tip": tip, "aim": aim}


func _two_bone_aim_rebuilt_hand(rig: Dictionary) -> Vector2:
	var source: DictBoneSource = rig["source"]
	var hip: Vector2 = source.get_origin(rig["upper"])
	var knee: Vector2 = hip + RigKitMath.dir(source.get_world_dir(rig["upper"])) * 0.22
	return knee + RigKitMath.dir(source.get_world_dir(rig["lower"])) * 0.22


func _test_two_bone_aim_reaches() -> void:
	var rig: Dictionary = _make_arm()
	var aim: TwoBoneAim = rig["aim"]
	aim.set_target_point(Vector2(0.3, -0.3))
	var result: Dictionary = aim.step(DT)
	_check(result["applied"], "two bone aim applies")
	_check(not result["clamped"], "two bone aim reports the target reachable")
	_check((result["hand"] as Vector2).distance_to(Vector2(0.3, -0.3)) <= 0.005, "two bone aim puts the hand on the target")
	var rebuilt: Vector2 = _two_bone_aim_rebuilt_hand(rig)
	_check(rebuilt.distance_to(result["hand"]) <= 0.001, "written limb matches the solver (no stretch)")


func _test_two_bone_aim_clamps_far_target() -> void:
	var rig: Dictionary = _make_arm()
	var aim: TwoBoneAim = rig["aim"]
	aim.set_target_point(Vector2(2.0, -0.5))
	var result: Dictionary = aim.step(DT)
	_check(result["clamped"], "two bone aim flags an out of reach target")
	var reached: float = ((result["hand"] as Vector2) - Vector2(0.0, -0.5)).length()
	_check(reached <= 0.44 + 0.001, "two bone aim never stretches past the limb length (%.4f)" % reached)


func _test_two_bone_aim_speed_is_capped() -> void:
	var rig: Dictionary = _make_arm()
	var aim: TwoBoneAim = rig["aim"]
	aim.max_speed_deg = 90.0
	aim.set_target_point(Vector2(-1.0, -0.5))
	var previous: float = 0.0
	var limit: float = deg_to_rad(90.0) * DT + 0.0005
	var worst: float = 0.0
	for i in 150:
		var result: Dictionary = aim.step(DT)
		var current: float = float(result.get("dir", previous))
		worst = maxf(worst, absf(RigKitMath.angle_delta(previous, current)))
		previous = current
	_check(worst <= limit, "two bone aim per frame swing %.4f rad <= %.4f rad" % [worst, limit])
	_check_close(absf(RigKitMath.angle_delta(0.0, previous)), PI, 0.02, "two bone aim arrives despite the cap")


func _test_two_bone_aim_zero_weight() -> void:
	var rig: Dictionary = _make_arm()
	var aim: TwoBoneAim = rig["aim"]
	var source: DictBoneSource = rig["source"]
	aim.weight = 0.0
	aim.set_target_point(Vector2(0.3, -0.3))
	for i in 10:
		aim.step(DT)
	_check_close(source.get_world_dir(rig["upper"]), 0.0, 0.000001, "two bone aim weight 0 leaves the upper bone")
	_check_close(source.get_world_dir(rig["lower"]), 0.0, 0.000001, "two bone aim weight 0 leaves the lower bone")


# ---------------------------------------------------------------- chain tip

func _test_chain_tip_direction() -> void:
	var rig: Dictionary = _make_chain(4, 0.25)
	var chain: ChainIK = rig["chain"]
	var source: DictBoneSource = rig["source"]
	var bones: Array = rig["bones"]
	chain.tip_dir_enabled = true
	chain.tip_dir = -PI * 0.5
	chain.tip_dir_weight = 1.0
	chain.solve(Vector2(0.5, 0.5), 1.0)
	_check_close(absf(RigKitMath.angle_delta(-PI * 0.5, source.get_world_dir(bones[bones.size() - 1]))), 0.0, 0.0005,
		"chain tip ends up pointing at the requested world direction")


func _test_chain_tip_keeps_length() -> void:
	var rig: Dictionary = _make_chain(4, 0.25)
	var chain: ChainIK = rig["chain"]
	var source: DictBoneSource = rig["source"]
	var bones: Array = rig["bones"]
	chain.tip_dir_enabled = true
	chain.tip_dir = PI * 0.5
	var result: Dictionary = chain.solve(Vector2(0.4, 0.6), 1.0)
	var rebuilt: Vector2 = source.get_origin(bones[0])
	for i in bones.size():
		rebuilt += RigKitMath.dir(source.get_world_dir(bones[i])) * chain.lengths[i]
	_check(rebuilt.distance_to(result["end"]) <= 0.001, "tip direction keeps the chain length intact")

# ---------------------------------------------------------------- verlet

func _make_verlet(count: int, segment: float) -> Dictionary:
	var source: DictBoneSource = DictBoneSource.new()
	var bones: Array = []
	for i in count:
		var bone: Dictionary = DictBoneSource.bone(Vector2(i * segment, 0.0), 0.0, segment)
		bones.append(bone)
	var chain: VerletChain = VerletChain.new()
	chain.bind(source, bones)
	return {"source": source, "bones": bones, "chain": chain}


func _test_verlet_stiff_reproduces_fk() -> void:
	var rig: Dictionary = _make_verlet(3, 0.2)
	var chain: VerletChain = rig["chain"]
	var source: DictBoneSource = rig["source"]
	var bones: Array = rig["bones"]
	chain.stiffness = 1.0
	chain.gravity = Vector2.ZERO
	for i in 10:
		chain.step(DT, Vector2.ZERO, 0.0)
	for bone in bones:
		_check_close(source.get_world_dir(bone), 0.0, 0.001, "verlet with stiffness 1 keeps the animation pose")


func _test_verlet_keeps_length() -> void:
	var rig: Dictionary = _make_verlet(3, 0.2)
	var chain: VerletChain = rig["chain"]
	chain.stiffness = 0.0
	chain.gravity = Vector2(0.0, 2.0)
	var tip: Vector2 = Vector2.ZERO
	for i in 60:
		var result: Dictionary = chain.step(DT, Vector2.ZERO, 0.0)
		_check(result["valid"], "verlet step stays valid")
		tip = result["tip"]
	_check(not is_nan(tip.x) and not is_nan(tip.y), "verlet tip stays finite")
	_check(tip.length() <= 0.6 + 0.002, "verlet chain never stretches past its total length (%.4f)" % tip.length())


func _test_verlet_zero_weight() -> void:
	var rig: Dictionary = _make_verlet(3, 0.2)
	var chain: VerletChain = rig["chain"]
	var source: DictBoneSource = rig["source"]
	var bones: Array = rig["bones"]
	chain.weight = 0.0
	for i in 30:
		chain.step(DT, Vector2.ZERO, 0.0)
	for bone in bones:
		_check_close(source.get_world_dir(bone), 0.0, 0.000001, "verlet weight 0 leaves bones untouched")


# ---------------------------------------------------------------- spine adapter

func _test_spine_adapter_degrees_to_radians() -> void:
	var parent: FakeDegreeBone = FakeDegreeBone.new()
	parent.rotation_deg = 90.0
	var bone: FakeDegreeBone = FakeDegreeBone.new()
	bone.parent = parent
	bone.rotation_deg = 120.0
	var source: SpineBoneSource = SpineBoneSource.new()
	source.foot_axis_deg = 0.0
	_check_close(source.get_world_dir(bone), deg_to_rad(120.0), 0.0001,
		"adapter converts degree world rotation to radians")
	_check_close(source.get_parent_global_rotation(bone), deg_to_rad(90.0), 0.0001,
		"adapter converts the parent rotation too")

	source.set_world_dir(bone, deg_to_rad(45.0), deg_to_rad(90.0))
	_check_close(bone.rotation_deg, -45.0, 0.001,
		"adapter writes back in degrees (world 45, parent 90 -> local -45)")

	var radians_source: SpineBoneSource = SpineBoneSource.new()
	radians_source.rotation_is_degrees = false
	bone.rotation_deg = 1.0
	_check_close(radians_source.get_world_dir(bone), 1.0, 0.0001,
		"rotation_is_degrees=false passes radians through untouched")


func _test_spine_adapter_ignores_child_angle() -> void:
	# A child placed off the bone axis (Spine style) must not become a dir offset.
	var parent := FakeDegreeBone.new()
	parent.name = "chest"
	parent.rotation_deg = 0.0
	var child := FakeDegreeBone.new()
	child.name = "arm_ul"
	child.parent = parent
	# FakeDegreeBone has no get_children, so exercise the callable override too.
	var source := SpineBoneSource.new()
	source.api = {
		"dir_offset": func(bone): return 0.0,
		"dir": func(bone): return 0.0,
		"parent_rot": func(bone): return 0.0,
		"length": func(bone): return 120.0,
	}
	_check_close(source.get_dir_offset(child), 0.0, 0.000001, "api dir_offset wins")
	var plain := SpineBoneSource.new()
	_check_close(plain.get_dir_offset(child), 0.0, 0.000001, "default spine axis offset is 0")


func _test_spine_adapter_parent_chain() -> void:
	var grandparent: FakeDegreeBone = FakeDegreeBone.new()
	grandparent.rotation_deg = 30.0
	var parent: FakeDegreeBone = FakeDegreeBone.new()
	parent.parent = grandparent
	parent.rotation_deg = 60.0
	var bone: FakeDegreeBone = FakeDegreeBone.new()
	bone.parent = parent
	bone.rotation_deg = 90.0
	var source: SpineBoneSource = SpineBoneSource.new()
	var probe: Dictionary = SpineBoneSource.probe(bone)
	_check(bool(probe.get("alive", false)), "adapter probe sees a live bone")
	_check(bool(probe["methods"].get("get_world_rotation", false)), "probe reports get_world_rotation")
	_check(not bool(probe["methods"].get("set_local_rotation", false)), "probe reports missing methods as false")
	_check_close(source.get_world_dir(bone) - source.get_parent_global_rotation(bone), deg_to_rad(30.0), 0.0001,
		"world and parent angles stay consistent (local 30 deg)")


# ---------------------------------------------------------------- rigby adapter

func _make_rigby_source() -> Dictionary:
	var runtime := FakeRigbyRuntime.new()
	var path: String = "user://rigby_test_skeleton.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	var data: Dictionary = {"bones": [
		{"name": "torso", "length": 170},
		{"name": "chest", "parent": "torso", "length": 50},
		# A child placed off the parent's axis: the Spine convention keeps the bone
		# direction at the rotation itself, so this must not become a dir offset.
		{"name": "arm_ul", "parent": "chest", "x": 70, "y": 120, "length": 120},
	]}
	file.store_string(JSON.stringify(data))
	file.close()
	var source := RigbyBoneSource.new()
	source.bind(runtime, path)
	return {"source": source, "runtime": runtime}


func _test_rigby_adapter_reads_radians() -> void:
	var built: Dictionary = _make_rigby_source()
	var runtime: FakeRigbyRuntime = built["runtime"]
	var source: RigbyBoneSource = built["source"]
	runtime.rotations["arm_ul"] = 1.25
	# Radians pass through untouched: no degree conversion like SpineBoneSource needs.
	_check_close(source.get_world_dir("arm_ul"), 1.25, 0.000001, "rigby world dir is radians")


func _test_rigby_adapter_write_is_local() -> void:
	var built: Dictionary = _make_rigby_source()
	var runtime: FakeRigbyRuntime = built["runtime"]
	var source: RigbyBoneSource = built["source"]
	source.set_world_dir("arm_ul", 0.9, 0.25)
	_check(runtime.writes.size() == 1, "one write per set_world_dir")
	_check_close(float(runtime.writes[0][1]), 0.65, 0.000001, "local = world - parent")


func _test_rigby_adapter_reads_json_tree() -> void:
	var built: Dictionary = _make_rigby_source()
	var runtime: FakeRigbyRuntime = built["runtime"]
	var source: RigbyBoneSource = built["source"]
	runtime.rotations["chest"] = 0.4
	_check_close(source.get_parent_global_rotation("arm_ul"), 0.4, 0.000001, "parent rotation from json tree")
	_check_close(source.get_length("arm_ul"), 120.0, 0.000001, "length from json")
	_check_close(source.get_parent_global_rotation("torso"), 0.0, 0.000001, "root parent rotation is 0")


func _test_rigby_adapter_has_no_child_heuristic() -> void:
	var built: Dictionary = _make_rigby_source()
	var source: RigbyBoneSource = built["source"]
	_check_close(source.get_dir_offset("arm_ul"), 0.0, 0.000001, "dir offset stays 0 despite child at (70,120)")


func _test_rigby_adapter_probe() -> void:
	var built: Dictionary = _make_rigby_source()
	var runtime: FakeRigbyRuntime = built["runtime"]
	var probe: Dictionary = RigbyBoneSource.probe(runtime)
	_check(bool(probe["writable"]), "probe finds the bone setter")
	_check(not bool(RigbyBoneSource.probe(null)["writable"]), "probe rejects a null node")


# ---------------------------------------------------------------- physics

func _make_physics() -> Dictionary:
	var source: DictBoneSource = DictBoneSource.new()
	var bone: Dictionary = DictBoneSource.bone(Vector2(0.0, -0.5), 0.0, 0.3)
	var constraint: PhysicsConstraint = PhysicsConstraint.new()
	constraint.bind(source, bone)
	return {"source": source, "bone": bone, "pc": constraint}


## Every frame the animation system writes the pose first, then the constraint
## runs. Skipping the write would feed the constraint its own output.
func _physics_frame(rig: Dictionary, pose_origin: Vector2, delta: float) -> void:
	var source: DictBoneSource = rig["source"]
	source.set_origin(rig["bone"], pose_origin)
	(rig["pc"] as PhysicsConstraint).step(delta)


func _test_physics_settles_under_gravity() -> void:
	var rig: Dictionary = _make_physics()
	var pc: PhysicsConstraint = rig["pc"]
	pc.gravity = 0.5
	pc.strength = 1.0
	pc.damping = 1.0
	pc.rotate_enabled = false
	for i in 400:
		_physics_frame(rig, Vector2(0.0, -0.5), DT)
	var offset: Vector2 = pc.get_offset()
	_check(is_finite(offset.x) and is_finite(offset.y), "physics offset stays finite")
	_check_close(offset.y, 0.5, 0.02, "gravity and strength settle at gravity/strength")


func _test_physics_mix_zero_leaves_pose() -> void:
	var rig: Dictionary = _make_physics()
	var pc: PhysicsConstraint = rig["pc"]
	pc.mix = 0.0
	pc.gravity = 2.0
	for i in 60:
		_physics_frame(rig, Vector2(0.0, -0.5), DT)
	var source: DictBoneSource = rig["source"]
	_check(source.get_origin(rig["bone"]).distance_to(Vector2(0.0, -0.5)) <= 0.000001,
		"mix 0 writes nothing back")


func _test_physics_inertia_lags_then_recovers() -> void:
	var rig: Dictionary = _make_physics()
	var pc: PhysicsConstraint = rig["pc"]
	var source: DictBoneSource = rig["source"]
	pc.inertia = 1.0
	pc.strength = 0.5
	# Damping sets the decay time: ~2/damping seconds per e-fold. 0.2 rings for
	# tens of seconds on purpose, so the test uses a realistic cloth-ish value.
	pc.damping = 1.0
	pc.rotate_enabled = false
	for i in 5:
		_physics_frame(rig, Vector2(0.0, -0.5), DT)

	# Teleport the animated pose; the bone should stay where it was.
	_physics_frame(rig, Vector2(0.4, -0.5), DT)
	_check(pc.get_offset().x <= -0.2, "inertia produces a lag offset opposite to the movement (%.3f)" % pc.get_offset().x)
	var lagged: Vector2 = source.get_origin(rig["bone"])
	_check(lagged.distance_to(Vector2(0.0, -0.5)) <= 0.08,
		"the bone visually stays near its previous position (%.3f)" % lagged.x)

	for i in 600:
		_physics_frame(rig, Vector2(0.4, -0.5), DT)
	_check(absf(pc.get_offset().x) <= 0.02, "strength pulls the offset back to the animated pose")
	_check(source.get_origin(rig["bone"]).distance_to(Vector2(0.4, -0.5)) <= 0.03,
		"bone ends up on the animated pose once settled")


func _test_physics_limit_caps_speed() -> void:
	var rig: Dictionary = _make_physics()
	var pc: PhysicsConstraint = rig["pc"]
	pc.gravity = 5.0
	pc.strength = 0.0
	pc.damping = 0.0
	pc.limit = 0.5
	pc.rotate_enabled = false
	var previous: Vector2 = pc.get_offset()
	var worst: float = 0.0
	for i in 60:
		_physics_frame(rig, Vector2(0.0, -0.5), DT)
		var current: Vector2 = pc.get_offset()
		worst = maxf(worst, (current - previous).length() / DT)
		previous = current
	_check(worst <= 0.5 + 0.001, "limit caps translation speed (worst %.3f u/s)" % worst)


func _test_physics_fps_is_decoupled() -> void:
	var slow: Dictionary = _make_physics()
	var fast: Dictionary = _make_physics()
	for rig in [slow, fast]:
		var pc: PhysicsConstraint = rig["pc"]
		pc.gravity = 0.5
		pc.strength = 1.0
		pc.damping = 0.4
		pc.rotate_enabled = false
	for i in 300:
		_physics_frame(slow, Vector2(0.0, -0.5), DT)
	for i in 600:
		_physics_frame(fast, Vector2(0.0, -0.5), DT * 0.5)
	var a: float = (slow["pc"] as PhysicsConstraint).get_offset().y
	var b: float = (fast["pc"] as PhysicsConstraint).get_offset().y
	_check(absf(a - b) <= 0.01, "offsets agree across render rates (%.4f vs %.4f)" % [a, b])


# ---------------------------------------------------------------- rig hooks

func _test_rig_runs_constraints_and_audit() -> void:
	var params: RigKitParams = RigKitParams.new()
	params.apply_preset("idle")
	var rig: FootLockRig = _make_rig(params, _flat_sample)
	var source: DictBoneSource = DictBoneSource.new()
	var wand: Dictionary = DictBoneSource.bone(Vector2(0.0, -0.5), 0.0, 0.3)
	var aim: AimConstraint = AimConstraint.new()
	aim.bind(source, wand)
	aim.smooth_time = 0.0
	aim.max_speed_deg = 0.0
	aim.set_target_point(Vector2(0.0, 1.0))
	rig.add_constraint(aim)
	var audit: RootMotionAudit = RootMotionAudit.new()
	rig.set_root_audit(audit)
	rig.step(DT)
	var state: Dictionary = rig.get_state()
	_check(int(state.get("constraints", 0)) == 1, "rig runs the registered constraint")
	_check_close((state.get("audit", {}) as Dictionary).get("ratio", 0.0), 1.0, 0.0001, "rig feeds the stride audit")
	_check_close(source.get_world_dir(wand), PI * 0.5, 0.0005, "constraint ran before the lock captured its pose")
	rig.free()


## The case the whole ordering design exists for: the aim solves the limb, then
## a child-of constraint on the same frame reads the freshly solved hand.
func _test_constraint_order_solves_then_follows() -> void:
	var params: RigKitParams = RigKitParams.new()
	params.apply_preset("idle")
	var rig: FootLockRig = _make_rig(params, _flat_sample)
	var source: DictBoneSource = DictBoneSource.new()
	var upper: Dictionary = DictBoneSource.bone(Vector2(0.0, -0.5), 0.0, 0.22)
	var lower: Dictionary = DictBoneSource.bone(Vector2(0.22, -0.5), 0.0, 0.22)
	var hand: Dictionary = DictBoneSource.bone(Vector2(0.44, -0.5), 0.0, 0.06)
	var prop: Dictionary = DictBoneSource.bone(Vector2(0.0, -0.5), 0.0, 0.2)

	var arm: TwoBoneAim = TwoBoneAim.new()
	arm.bind(source, upper, lower, hand)
	arm.smooth_time = 0.0
	arm.max_speed_deg = 0.0
	arm.set_target_point(Vector2(0.3, -0.3))

	var prop_follow: TransformConstraint = TransformConstraint.new()
	prop_follow.bind(source, prop)
	prop_follow.smooth_time = 0.0
	prop_follow.transform_provider = func() -> Transform2D:
		# Read through the bone source, i.e. the pose written earlier this frame.
		var hand_dir: float = source.get_world_dir(hand)
		return Transform2D(hand_dir, Vector2.ZERO)

	rig.add_constraint(arm)
	rig.add_constraint(prop_follow)
	rig.step(DT)

	_check_close(absf(RigKitMath.angle_delta(source.get_world_dir(hand), source.get_world_dir(prop))), 0.0, 0.0005,
		"later constraint reads the pose the aim wrote in the same frame")
	rig.free()

var _rig_chains: Dictionary = {}


func _flat_ground(pos: Vector2) -> Dictionary:
	return {"hit": true, "point": Vector2(pos.x, 0.0), "normal": Vector2.UP}


func _flat_sample(foot_hint: Vector2) -> Dictionary:
	return {
		"valid": true,
		"point": Vector2(foot_hint.x, -0.12),
		"height": 0.0,
		"surface_angle": 0.0,
		"slope_raw": 0.0,
		"heel": Vector2(foot_hint.x - 0.07, 0.0),
		"toe": Vector2(foot_hint.x + 0.07, 0.0),
	}


## Builds a two foot rig over a Dictionary based skeleton.
func _make_rig(params: RigKitParams, sampler: Callable) -> FootLockRig:
	var source: DictBoneSource = DictBoneSource.new()
	var upper_l: Dictionary = DictBoneSource.bone(Vector2(0.0, -0.32), PI * 0.5, 0.32)
	var lower_l: Dictionary = DictBoneSource.bone(Vector2(0.0, 0.0), PI * 0.5, 0.30)
	var foot_l: Dictionary = DictBoneSource.bone(Vector2(0.0, 0.30), 0.0, 0.08)
	var upper_r: Dictionary = DictBoneSource.bone(Vector2(0.0, -0.32), PI * 0.5, 0.32)
	var lower_r: Dictionary = DictBoneSource.bone(Vector2(0.0, 0.0), PI * 0.5, 0.30)
	var foot_r: Dictionary = DictBoneSource.bone(Vector2(0.0, 0.30), 0.0, 0.08)

	var rig: FootLockRig = FootLockRig.new()
	rig.auto_step = false
	rig.params = params
	rig.root_transform = Transform2D.IDENTITY
	rig.setup(source, {
		"left": {"upper": upper_l, "lower": lower_l, "foot": foot_l},
		"right": {"upper": upper_r, "lower": lower_r, "foot": foot_r},
	}, null, sampler)

	_rig_chains[rig] = {
		"left": rig._sides["left"]["chain"],
		"right": rig._sides["right"]["chain"],
	}
	return rig


## Places one chain so its ankle sits exactly on [param ankle] (a plausible FK
## pose for an in-place animation whose planted foot is stationary in world space).
func _pose_chain(rig: FootLockRig, side: String, hip: Vector2, ankle: Vector2) -> void:
	var chain: BoneChain = _rig_chains[rig][side]
	var to_ankle: Vector2 = ankle - hip
	var distance: float = clampf(to_ankle.length(), 0.001, chain.leg_length() - 0.001)
	var base: float = RigKitMath.angle_of(to_ankle)
	var cos_alpha: float = (chain.upper_length * chain.upper_length + distance * distance - chain.lower_length * chain.lower_length) / (2.0 * chain.upper_length * distance)
	var alpha: float = acos(clampf(cos_alpha, -1.0, 1.0))
	var upper_dir: float = base + alpha
	var knee: Vector2 = hip + RigKitMath.dir(upper_dir) * chain.upper_length
	var lower_dir: float = RigKitMath.angle_of(ankle - knee)

	chain.source.set_world_dir(chain.upper, upper_dir, 0.0)
	chain.source.set_world_dir(chain.lower, lower_dir, 0.0)
	chain.source.set_world_dir(chain.foot, deg_to_rad(-6.0), 0.0)
	(chain.upper as Dictionary)["origin"] = hip
	(chain.lower as Dictionary)["origin"] = knee
	(chain.foot as Dictionary)["origin"] = ankle


## Synthetic in-place gait: the planted ankle is frozen in world space for the
## whole stance (which is what a matched stride looks like from outside), then
## swings forward with an arc.
func _gait_new(speed: float, stance: float, swing: float, start_x: float = 0.2) -> Dictionary:
	return {
		"speed": speed,
		"stance": stance,
		"swing": swing,
		"stride": speed * (stance + swing),
		"planted": true,
		"timer": 0.0,
		"plant_x": start_x,
		"from_x": start_x,
		"to_x": start_x,
		"ankle": Vector2(start_x, 0.0),
		"contact": 1.0,
	}


func _gait_advance(gait: Dictionary, dt: float) -> void:
	gait["timer"] = float(gait["timer"]) + dt
	if bool(gait["planted"]):
		if float(gait["timer"]) >= float(gait["stance"]):
			gait["planted"] = false
			gait["timer"] = 0.0
			gait["from_x"] = gait["plant_x"]
			gait["to_x"] = float(gait["plant_x"]) + float(gait["stride"])
			gait["ankle"] = Vector2(gait["from_x"], 0.0)
			gait["contact"] = 0.0
		else:
			gait["ankle"] = Vector2(gait["plant_x"], 0.0)
			gait["contact"] = 1.0
	else:
		var t: float = clampf(float(gait["timer"]) / float(gait["swing"]), 0.0, 1.0)
		gait["ankle"] = Vector2(lerpf(float(gait["from_x"]), float(gait["to_x"]), t), -sin(PI * t) * 0.28)
		gait["contact"] = 0.0
		if float(gait["timer"]) >= float(gait["swing"]):
			gait["planted"] = true
			gait["timer"] = 0.0
			gait["plant_x"] = gait["to_x"]
			gait["contact"] = 1.0


func _read_dirs(rig: FootLockRig) -> Array[float]:
	var chains: Dictionary = _rig_chains[rig]
	var dirs: Array[float] = []
	for side in ["left", "right"]:
		var chain: BoneChain = chains[side]
		dirs.append(chain.source.get_world_dir(chain.upper))
		dirs.append(chain.source.get_world_dir(chain.lower))
		dirs.append(chain.source.get_world_dir(chain.foot))
	return dirs


func _arrays_equal(a: Array[float], b: Array[float]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(a[i] - b[i]) > 0.000001:
			return false
	return true


func _print_summary() -> void:
	print("\n---------------------------------------------")
	print("assertions passed: %d, failed: %d" % [_pass, _fail])
	if _fail > 0:
		print("failures:")
		for message in _messages:
			print("  - %s" % message)
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("---------------------------------------------")
