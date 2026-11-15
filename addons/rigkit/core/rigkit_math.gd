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
