## A hip -> knee -> ankle chain bound to one skeleton, plus the solver setup.
##
## The chain measures bone lengths once, then only ever writes rotations:
##
## * read: hip position, FK world directions of upper / lower / foot;
## * write: blended world directions, converted to local rotations with the
##   parent rotation supplied by the caller, so no transform propagation is
##   needed mid-frame.
class_name BoneChain
extends RefCounted

var source: BoneSource = null
var upper: Variant = null
var lower: Variant = null
var foot: Variant = null

var upper_length: float = 0.0
var lower_length: float = 0.0
var ik: TwoBoneIK = null

var _upper_offset: float = 0.0
var _lower_offset: float = 0.0
var _foot_offset: float = 0.0


## Binds bones and measures lengths. Returns false when the chain is unusable.
func bind(bone_source: BoneSource, upper_bone: Variant, lower_bone: Variant, foot_bone: Variant) -> bool:
	source = bone_source
	upper = upper_bone
	lower = lower_bone
	foot = foot_bone
	if source == null or upper == null or lower == null or foot == null:
		return false

	_upper_offset = source.get_dir_offset(upper)
	_lower_offset = source.get_dir_offset(lower)
	_foot_offset = source.get_dir_offset(foot)

	upper_length = source.get_length(upper)
	if upper_length <= 0.0:
		upper_length = (source.get_origin(lower) - source.get_origin(upper)).length()
	lower_length = source.get_length(lower)
	if lower_length <= 0.0:
		lower_length = (source.get_origin(foot) - source.get_origin(lower)).length()

	if upper_length <= 0.0 or lower_length <= 0.0:
		push_warning("BoneChain: degenerate bone lengths, IK disabled for this chain")
		return false

	ik = TwoBoneIK.new()
	ik.bind_lengths(upper_length, lower_length)
	return true


## Rest length of the whole leg, used by the gizmo and by tests.
func leg_length() -> float:
	return upper_length + lower_length


func set_knee_axis(axis: Vector2, forced_sign: float = 0.0) -> void:
	if ik == null:
		return
	if axis.length_squared() < RigKitMath.EPS:
		axis = Vector2(1.0, 0.0)
	ik.knee_axis = axis.normalized()
	ik.bend_sign = forced_sign


func hip_position() -> Vector2:
	return source.get_origin(upper) if source != null else Vector2.ZERO


func foot_position() -> Vector2:
	return source.get_origin(foot) if source != null else Vector2.ZERO


## Reads the FK pose written by the animation system earlier this frame.
func read_fk() -> Dictionary:
	return {
		"upper": source.get_world_dir(upper),
		"lower": source.get_world_dir(lower),
		"foot": source.get_world_dir(foot),
		"pos": foot_position(),
		"hip": hip_position(),
	}


## Solves the chain against [param target] and blends with the FK pose.
func solve(target: Vector2, weight: float, fk: Dictionary) -> Dictionary:
	if ik == null:
		return {"valid": false}
	return ik.solve(hip_position(), target, weight, float(fk.get("upper", 0.0)), float(fk.get("lower", 0.0)))


## Writes the solved pose. A weight of 0 leaves the animation untouched.
##
## [param foot_angle] final world direction for the foot skeleton, already
## blended by the caller.
func apply(solution: Dictionary, weight: float, foot_angle: float) -> void:
	if source == null or not solution.get("valid", false) or weight <= 0.0001:
		return

	var new_upper: float = float(solution["blend_upper"])
	var new_lower: float = float(solution["blend_lower"])

	var parent_rotation_upper: float = source.get_parent_global_rotation(upper)
	source.set_world_dir(upper, new_upper, parent_rotation_upper)
	# The parent of the lower bone is the upper bone, whose new global rotation
	# is exactly new_upper minus its axis offset.
	source.set_world_dir(lower, new_lower, new_upper - _upper_offset)
	source.set_world_dir(foot, foot_angle, new_lower - _lower_offset)
