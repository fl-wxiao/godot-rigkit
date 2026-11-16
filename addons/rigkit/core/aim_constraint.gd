## Aim constraint: rotate one bone towards a world point or a world direction.
##
## The bone is aimed *after* the animation system has posed it, by rotating only:
## bone length and origin are never touched, so an aimed bone can sit anywhere in
## a skeleton without breaking the zero-stretch invariant of the leg chains.
##
## Motion is shaped by three independent limits, which is what keeps an aimed
## head / weapon readable instead of snappy or spinning:
##
## * [member range_deg] - how far from the animation pose the bone may deviate;
## * [member max_speed_deg] - hard angular speed cap (degrees per second);
## * [member smooth_time] - critically damped smoothing of the target itself.
##
## Like every constraint in RigKit this runs *after* the animation system has
## written the bone, and assumes it will write it again next frame: the range
## limit is measured against that fresh pose, not against the constraint's own
## previous output.
##
## [codeblock]
## var aim := AimConstraint.new()
## aim.bind(source, head_bone)
## aim.set_target_point(mouse_world_position)
## aim.weight = 0.8
## aim.step(delta)   # call after animation, before / with the foot lock rig
## [/codeblock]
class_name AimConstraint
extends RefCounted

var source: BoneSource = null
var bone: Variant = null

var enabled: bool = true
## 0 = pure animation pose, 1 = fully aimed.
var weight: float = 1.0
## True: aim at [member target_point]; false: aim at [member target_dir].
var use_point: bool = true
var target_point: Vector2 = Vector2.ZERO
var target_dir: float = 0.0
## Maximum deviation from the animation pose, in degrees. 180 = free rotation.
var range_deg: float = 180.0
## Hard angular speed cap in degrees per second. 0 = unlimited.
var max_speed_deg: float = 360.0
## Critically damped smoothing constant for the target. 0 = snap.
var smooth_time: float = 0.12

var _angle: float = 0.0
var _velocity: float = 0.0
var _has_state: bool = false
var _has_applied: bool = false
var _last_applied_dir: float = 0.0
var _last_speed: float = 0.0
var _last_target: float = 0.0


func bind(bone_source: BoneSource, aim_bone: Variant) -> bool:
	if bone_source == null or aim_bone == null:
		push_error("AimConstraint.bind: null bone source or bone")
		return false
	source = bone_source
	bone = aim_bone
	_has_state = false
	return true


func set_target_point(point: Vector2) -> void:
	use_point = true
	target_point = point


func set_target_dir(world_dir: float) -> void:
	use_point = false
	target_dir = world_dir


## Forgets the smoothing state, e.g. after teleporting the character.
func reset() -> void:
	_has_state = false
	_velocity = 0.0


## Advances one frame. Returns a telemetry dictionary (also used by tests).
func step(delta: float) -> Dictionary:
	if source == null or bone == null or not enabled or delta <= 0.0:
		return {"applied": false}

	var fk_dir: float = source.get_world_dir(bone)
	var origin: Vector2 = source.get_origin(bone)
	var parent_rotation: float = source.get_parent_global_rotation(bone)

	var desired: float = fk_dir
	if use_point:
		var to_target: Vector2 = target_point - origin
		if to_target.length_squared() <= RigKitMath.EPS:
			return {"applied": false, "reason": "target_on_origin"}
		desired = RigKitMath.angle_of(to_target)
	else:
		desired = target_dir

	# Range limit is expressed against the animation pose, so an aim can never
	# twist a joint around by itself (a head cannot look backwards while the
	# animation says forward).
	var deviation: float = RigKitMath.clamp_angle(RigKitMath.angle_delta(fk_dir, desired), deg_to_rad(range_deg))
	desired = fk_dir + deviation
	_last_target = desired

	if not _has_state:
		_angle = fk_dir
		_has_state = true

	var solved: float = desired
	if smooth_time > 0.0:
		var smoothed: Vector2 = RigKitMath.smooth_damp(_angle, desired, _velocity, smooth_time, delta)
		solved = smoothed.x
		_velocity = smoothed.y

	if max_speed_deg > 0.0:
		var step_limit: float = deg_to_rad(max_speed_deg) * delta
		var delta_angle: float = RigKitMath.angle_delta(_angle, solved)
		if absf(delta_angle) > step_limit:
			solved = _angle + signf(delta_angle) * step_limit
			_velocity = 0.0

	_angle = solved

	if weight <= 0.0001:
		# Keep the solver state glued to the animation so re-enabling never jumps.
		_angle = fk_dir
		_velocity = 0.0
		_last_speed = 0.0
		return {"applied": false, "reason": "zero_weight"}

	var out_dir: float = lerp_angle(fk_dir, _angle, clampf(weight, 0.0, 1.0))
	_last_speed = RigKitMath.angle_delta(_last_applied_dir, out_dir) / delta if _has_applied else 0.0
	_has_applied = true
	_last_applied_dir = out_dir
	source.set_world_dir(bone, out_dir, parent_rotation)

	return {
		"applied": true,
		"dir": out_dir,
		"target": desired,
		"deviation": RigKitMath.angle_delta(fk_dir, out_dir),
		"speed": _last_speed,
	}
