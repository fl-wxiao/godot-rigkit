## Two bone aim: a whole limb (shoulder -> elbow -> hand) aims at a world point,
## instead of one bone turning towards it.
##
## This is the case that proves the ordering rules in RigKit: the aim solves the
## limb, and anything else that has to follow the hand (a weapon socket, a prop)
## is a [TransformConstraint] registered *after* it, so it reads the freshly
## solved pose inside the same frame instead of a stale one.
##
## [codeblock]
## var arm := TwoBoneAim.new()
## arm.bind(source, shoulder_bone, elbow_bone, hand_bone)
## arm.set_target_point(mouse_world)
## rig.add_constraint(arm)                 # first: solves the limb
## rig.add_constraint(prop_follow_constraint)  # second: reads the solved hand
## [/codeblock]
##
## Lengths are measured once; the solver clamps the *hand position*, never the
## bones, so the limb bends and never stretches.
class_name TwoBoneAim
extends RefCounted

var source: BoneSource = null
var upper: Variant = null
var lower: Variant = null
## Optional hand / tip bone: rotated towards the aim direction when enabled.
var tip: Variant = null

var enabled: bool = true
## 0 = animation pose, 1 = fully aimed.
var weight: float = 1.0
## World point the limb aims at.
var target_point: Vector2 = Vector2.ZERO
## World-space pole the elbow prefers to point at (default: downwards).
var knee_axis: Vector2 = Vector2(0.0, 1.0)
## +1 / -1 to force the elbow side, 0 to derive it from [member knee_axis].
var bend_sign: float = 0.0
## Critically damped smoothing of the aim direction. 0 = snap.
var smooth_time: float = 0.1
## Hard cap on how fast the aim direction may swing, in degrees per second.
var max_speed_deg: float = 0.0
## Rotate the hand bone towards the target as well.
var tip_follows_target: bool = true
## Offset of the hand bone against the aim direction, in radians.
var tip_dir_offset: float = 0.0

var ik: TwoBoneIK = TwoBoneIK.new()

var _dir: float = 0.0
var _dir_velocity: float = 0.0
var _has_state: bool = false


func bind(bone_source: BoneSource, upper_bone: Variant, lower_bone: Variant, tip_bone: Variant = null) -> bool:
	if bone_source == null or upper_bone == null or lower_bone == null:
		push_error("TwoBoneAim.bind: null bone source or bone")
		return false
	source = bone_source
	upper = upper_bone
	lower = lower_bone
	tip = tip_bone

	var upper_length: float = source.get_length(upper)
	if upper_length <= 0.0:
		upper_length = (source.get_origin(lower) - source.get_origin(upper)).length()
	var lower_length: float = source.get_length(lower)
	if lower_length <= 0.0:
		var tip_origin: Vector2 = source.get_origin(tip) if tip != null else Vector2.ZERO
		if tip != null:
			lower_length = (tip_origin - source.get_origin(lower)).length()
		else:
			push_warning("TwoBoneAim.bind: lower bone length unknown and no tip bone given")
			return false
	if upper_length <= 0.0 or lower_length <= 0.0:
		push_warning("TwoBoneAim.bind: degenerate bone lengths")
		return false

	ik.bind_lengths(upper_length, lower_length)
	ik.knee_axis = knee_axis.normalized() if knee_axis.length_squared() > RigKitMath.EPS else Vector2.DOWN
	ik.bend_sign = bend_sign
	_has_state = false
	return true


func set_target_point(point: Vector2) -> void:
	target_point = point


func set_knee_axis(axis: Vector2, forced_sign: float = 0.0) -> void:
	if axis.length_squared() <= RigKitMath.EPS:
		axis = Vector2.DOWN
	knee_axis = axis.normalized()
	ik.knee_axis = knee_axis
	ik.bend_sign = forced_sign
	bend_sign = forced_sign


func reset() -> void:
	_has_state = false
	_dir_velocity = 0.0


## Advances one frame and writes the limb. Returns telemetry.
func step(delta: float) -> Dictionary:
	if source == null or upper == null or lower == null or not enabled or delta <= 0.0:
		return {"applied": false}
	if weight <= 0.0001:
		_has_state = false
		return {"applied": false, "reason": "zero_weight"}

	var hip: Vector2 = source.get_origin(upper)
	var fk_upper: float = source.get_world_dir(upper)
	var fk_lower: float = source.get_world_dir(lower)
	var to_target: Vector2 = target_point - hip
	if to_target.length_squared() <= RigKitMath.EPS:
		return {"applied": false, "reason": "target_on_joint"}

	var wanted_dir: float = RigKitMath.angle_of(to_target)
	if not _has_state:
		# Start from the pose the animation actually shows, so the speed cap is
		# enforced from frame one instead of letting the first step snap.
		_dir = fk_lower
		_has_state = true

	var previous_dir: float = _dir
	if smooth_time > 0.0:
		var smoothed: Vector2 = RigKitMath.smooth_damp(_dir, wanted_dir, _dir_velocity, smooth_time, delta)
		_dir = smoothed.x
		_dir_velocity = smoothed.y
	else:
		_dir = wanted_dir

	if max_speed_deg > 0.0:
		var step_limit: float = deg_to_rad(max_speed_deg) * delta
		var moved: float = RigKitMath.angle_delta(previous_dir, _dir)
		if absf(moved) > step_limit:
			_dir = previous_dir + signf(moved) * step_limit
			_dir_velocity = 0.0

	# Hand position: along the aim direction at the requested distance, clamped to
	# what the limb can actually reach. The solver then clamps again for safety.
	var wanted_distance: float = to_target.length()
	var reach: float = ik.max_reach() - ik.reach_epsilon
	var floor_reach: float = ik.min_reach() + ik.reach_epsilon
	var hand_distance: float = clampf(wanted_distance, floor_reach, reach)
	var hand: Vector2 = hip + RigKitMath.dir(_dir) * hand_distance

	var solution: Dictionary = ik.solve(hip, hand, 1.0, fk_upper, fk_lower)
	if not solution.get("valid", false):
		return {"applied": false, "reason": "solve_failed"}

	var w: float = clampf(weight, 0.0, 1.0)
	var out_upper: float = lerp_angle(fk_upper, float(solution["blend_upper"]), w)
	var out_lower: float = lerp_angle(fk_lower, float(solution["blend_lower"]), w)

	var parent_rotation: float = source.get_parent_global_rotation(upper)
	source.set_world_dir(upper, out_upper, parent_rotation)
	source.set_world_dir(lower, out_lower, out_upper - source.get_dir_offset(upper))

	if tip != null and tip_follows_target:
		var fk_tip: float = source.get_world_dir(tip)
		var wanted_tip: float = _dir + tip_dir_offset
		source.set_world_dir(tip, lerp_angle(fk_tip, wanted_tip, w), out_lower - source.get_dir_offset(lower))

	return {
		"applied": true,
		"dir": _dir,
		"hand": solution["target_clamped"],
		"clamped": wanted_distance > reach or wanted_distance < floor_reach,
		"clamp_ratio": solution["clamp_ratio"],
		"reach": reach,
	}
