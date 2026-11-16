## Small math helpers shared by the solver, the probes and the state machine.
##
## Everything is deterministic 2D math with no dependency on the scene tree, so
## the whole pipeline can be unit tested headless.
class_name RigKitMath
extends RefCounted

const EPS := 1.0e-6


static func dir(angle: float) -> Vector2:
	return Vector2(cos(angle), sin(angle))


static func angle_of(v: Vector2) -> float:
	return atan2(v.y, v.x)


static func cross2(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


## Wraps an angle into (-PI, PI].
static func wrap_angle(angle: float) -> float:
	return atan2(sin(angle), cos(angle))


## Shortest signed difference from [param from] to [param to].
static func angle_delta(from: float, to: float) -> float:
	return wrap_angle(to - from)


static func clamp_angle(angle: float, limit: float) -> float:
	if limit < 0.0:
		return angle
	return clampf(angle, -limit, limit)


## Linear ramp helper that saturates at both ends.
static func ramp(value: float, delta: float, low: float, high: float) -> float:
	if delta == 0.0:
		return value
	return clampf(value + delta, low, high)


## Quadratic ease in/out on a normalised 0..1 input. Used only for the pose blend
## so the IK weight itself stays strictly monotonic (acceptance criterion P.8.2).
static func ease_in_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Critically damped smoothing (Unity's SmoothDamp equivalent).
## Returns Vector2(value, velocity) so callers can keep the velocity across frames.
static func smooth_damp(current: float, target: float, velocity: float, smooth_time: float, delta: float) -> Vector2:
	var st: float = maxf(0.0001, smooth_time)
	var omega: float = 2.0 / st
	var x: float = omega * delta
	var exp_term: float = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change: float = current - target
	var temp: float = (velocity + omega * change) * delta
	var new_velocity: float = (velocity - omega * temp) * exp_term
	var new_value: float = target + (change + temp) * exp_term
	return Vector2(new_value, new_velocity)


## Local rotation that will make a bone point at [param world_dir] once the host
## composes it with [param inherit].
##
## [param parent_world_rotation] is the parent's world angle;
## [param parent_reflection] is -1.0 when the parent's scale flips the axis, +1.0
## otherwise.
##
## NORMAL is the ordinary case every adapter already handles:
## [code]world_dir - dir_offset - parent_world_rotation[/code]. The other modes
## exist because a bone may ignore its parent's rotation entirely
## (ONLY_TRANSLATION, NO_ROTATION_OR_REFLECTION) or keep it while ignoring scale
## (NO_SCALE). Writing the NORMAL formula into such a bone asks the host for a
## rotation it will not apply, and the bone ends up at the wrong angle - silently.
static func local_rotation(world_dir: float, parent_world_rotation: float, dir_offset: float, inherit: int = 0, parent_reflection: float = 1.0) -> float:
	match inherit:
		RigKitTypes.Inherit.ONLY_TRANSLATION:
			# Parent rotation never reaches the child, so the local value *is* the
			# world direction (reflection still applies to the local scale, not the
			# angle).
			return wrap_angle(world_dir - dir_offset)
		RigKitTypes.Inherit.NO_ROTATION_OR_REFLECTION:
			# Parent rotation is dropped but its reflection is kept: a mirrored
			# parent flips the child's apparent direction around the world axis.
			var local: float = wrap_angle(world_dir - dir_offset)
			return local if parent_reflection >= 0.0 else -local
		RigKitTypes.Inherit.NO_SCALE, RigKitTypes.Inherit.NO_SCALE_OR_REFLECTION:
			# Scale is dropped, rotation is kept: same as NORMAL for the angle.
			return wrap_angle(world_dir - dir_offset - parent_world_rotation)
		_:
			return wrap_angle(world_dir - dir_offset - parent_world_rotation)


## Scale factor that turns a bone of [param rest_length] into an effective length
## of [param target_length]. Used by the compress/stretch path of the Spine style
## IK: lengths stay authored, only the scale channel bends.
## Returns a scalar along the bone axis plus a uniform factor for the cross axis.
static func length_scale(rest_length: float, target_length: float) -> Vector2:
	if rest_length <= 0.0001:
		return Vector2.ONE
	var ratio: float = target_length / rest_length
	return Vector2(ratio, 1.0)


## Reflection sign of a bone's parent scale, +1.0 or -1.0. A negative determinant
## means the axis is mirrored, which inherit modes care about.
static func reflection_sign(parent_scale: Vector2) -> float:
	return -1.0 if parent_scale.x * parent_scale.y < 0.0 else 1.0


## Fixed size moving average used by the ground probes and by the lock anchor.
class MovingAverage:
	extends RefCounted

	var capacity: int = 4
	var _values: PackedFloat64Array = PackedFloat64Array()
	var _sum: float = 0.0

	func _init(size: int = 4) -> void:
		capacity = maxi(1, size)

	func reset() -> void:
		_values.clear()
		_sum = 0.0

	func push(value: float) -> void:
		if is_nan(value) or is_inf(value):
			return
		_values.push_back(value)
		_sum += value
		while _values.size() > capacity:
			_sum -= _values[0]
			_values.remove_at(0)

	func value(fallback: float = 0.0) -> float:
		if _values.is_empty():
			return fallback
		return _sum / float(_values.size())

	func is_empty() -> bool:
		return _values.is_empty()
