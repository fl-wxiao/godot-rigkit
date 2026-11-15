## Analytic two-bone IK: hip -> knee -> ankle.
##
## Deliberate constraints, because they are exactly the native runtimes' weak
## spots (see docs/design.zh.md):
##
## * Length preserving. The solver never returns a pose that needs a stretch:
##   when the target is out of reach the *target* is clamped, not the bones.
##   Because the writer only ever touches rotation, bone lengths are structurally
##   immutable, so "stretch == 0" holds by construction.
## * Knee side is enforced through a world space pole axis, so the knee cannot
##   flip to the wrong side when the target crosses the hip axis.
## * IK / FK are blended with an angle blend, so a weight of 0 reproduces the
##   animation pose exactly.
##
## The solver is pure math: it returns world space angles and never writes to a
## skeleton, which keeps it testable headless.
class_name TwoBoneIK
extends RefCounted

const MIN_LENGTH := 0.0001

## Length of the upper bone (hip -> knee), in world units.
var upper_length: float = 1.0
## Length of the lower bone (knee -> ankle), in world units.
var lower_length: float = 1.0
## World space direction the knee prefers to point at (the pole axis).
var knee_axis: Vector2 = Vector2(1.0, 0.0)
## +1 / -1 to force a bend side, 0 to derive it from [member knee_axis].
var bend_sign: float = 0.0
## Softening margin kept below full extension to avoid a degenerate straight leg.
var reach_epsilon: float = 0.0005


func bind_lengths(upper: float, lower: float) -> void:
	upper_length = maxf(upper, MIN_LENGTH)
	lower_length = maxf(lower, MIN_LENGTH)


func max_reach() -> float:
	return upper_length + lower_length


func min_reach() -> float:
	return absf(upper_length - lower_length)


## Solves the chain and blends the result with the incoming FK angles.
##
## [param hip] world position of the upper bone origin (the hip joint).
## [param target] world position the ankle should reach.
## [param weight] 0..1 IK blend. 0 returns the FK angles untouched.
## [param fk_upper] FK world direction angle of the upper bone.
## [param fk_lower] FK world direction angle of the lower bone.
##
## Returns a dictionary:
## [code]
## valid          bool     false only for degenerate input (NaN / zero length)
## hip            Vector2  echo of the input
## target         Vector2  requested ankle position
## target_clamped Vector2  actually reachable ankle position
## knee           Vector2  solved knee position
## upper_angle    float    pure IK world angle of the upper bone
## lower_angle    float    pure IK world angle of the lower bone
## blend_upper    float    upper_angle blended with fk_upper by weight
## blend_lower    float    lower_angle blended with fk_lower by weight
## clamp_ratio    float    (excess distance) / max_reach, 0 when reachable
## distance       float    requested hip -> target distance
## weight         float    echo of the weight
## [/code]
func solve(hip: Vector2, target: Vector2, weight: float, fk_upper: float, fk_lower: float) -> Dictionary:
	var result: Dictionary = {
		"valid": true,
		"hip": hip,
		"target": target,
		"target_clamped": target,
		"knee": hip,
		"upper_angle": fk_upper,
		"lower_angle": fk_lower,
		"blend_upper": fk_upper,
		"blend_lower": fk_lower,
		"clamp_ratio": 0.0,
		"distance": 0.0,
		"weight": weight,
	}
	if not _finite(hip) or not _finite(target):
		result["valid"] = false
		return result

	var reach: float = max_reach() - reach_epsilon
	var floor_reach: float = min_reach() + reach_epsilon
	var to_target: Vector2 = target - hip
	var distance: float = to_target.length()
	result["distance"] = distance

	var clamped_target: Vector2 = target
	var clamp_ratio: float = 0.0
	if distance > reach:
		# Out of reach: clamp the target, keep bone lengths intact.
		var direction: Vector2 = to_target.normalized() if distance > 0.0 else Vector2.DOWN
		clamped_target = hip + direction * reach
		clamp_ratio = (distance - reach) / max_reach()
	elif distance < floor_reach:
		# Too close to fold: push the target out to the minimum fold distance.
		var direction: Vector2 = to_target.normalized() if distance > 0.0 else Vector2.DOWN
		clamped_target = hip + direction * floor_reach
		clamp_ratio = (floor_reach - distance) / max_reach()
	result["target_clamped"] = clamped_target
	result["clamp_ratio"] = clamp_ratio

	var solved_distance: float = (clamped_target - hip).length()
	var base_angle: float = RigKitMath.angle_of(clamped_target - hip)
	var cos_alpha: float = (upper_length * upper_length + solved_distance * solved_distance - lower_length * lower_length) / (2.0 * upper_length * solved_distance)
	var alpha: float = acos(clampf(cos_alpha, -1.0, 1.0))

	var sign_value: float = bend_sign
	if is_zero_approx(sign_value):
		var axis: Vector2 = knee_axis
		if axis.length_squared() < RigKitMath.EPS:
			axis = Vector2.RIGHT
		var c: float = RigKitMath.cross2(clamped_target - hip, axis)
		sign_value = 1.0 if c >= 0.0 else -1.0

	var upper_angle: float = base_angle + sign_value * alpha
	var knee: Vector2 = hip + RigKitMath.dir(upper_angle) * upper_length
	var lower_angle: float = RigKitMath.angle_of(clamped_target - knee)

	var w: float = clampf(weight, 0.0, 1.0)
	result["knee"] = knee
	result["upper_angle"] = upper_angle
	result["lower_angle"] = lower_angle
	result["blend_upper"] = fk_upper if w <= 0.0 else RigKitMath.wrap_angle(lerp_angle(fk_upper, upper_angle, w))
	result["blend_lower"] = fk_lower if w <= 0.0 else RigKitMath.wrap_angle(lerp_angle(fk_lower, lower_angle, w))
	return result


## Angle the foot bone should take to stay parallel to the ground.
##
## [param fk_foot] FK world direction angle of the foot.
## [param surface_angle] ground surface direction angle from the probes.
## [param tilt_limit] maximum deviation from the FK pose, in radians.
## [param weight] 0..1 blend.
static func foot_angle_for_ground(fk_foot: float, surface_angle: float, tilt_limit: float, weight: float) -> float:
	var limited: float = RigKitMath.clamp_angle(RigKitMath.angle_delta(fk_foot, surface_angle), tilt_limit)
	var target: float = fk_foot + limited
	if weight <= 0.0:
		return fk_foot
	return RigKitMath.wrap_angle(lerp_angle(fk_foot, target, clampf(weight, 0.0, 1.0)))


static func _finite(v: Vector2) -> bool:
	return not (is_nan(v.x) or is_nan(v.y) or is_inf(v.x) or is_inf(v.y))
