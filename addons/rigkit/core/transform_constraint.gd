## Transform (child-of) constraint: make one bone follow the transform of another
## node - a socket, an attachment point, another bone's world matrix.
##
## Rotation follow is always available. Position follow is opt-in and requires a
## bone source that implements [method BoneSource.set_origin]; it is meant for
## attachment bones (weapons, props, hand sockets), never for the leg chains the
## foot lock drives, because moving a hip would invalidate the measured leg
## lengths the IK relies on.
##
## [codeblock]
## var child := TransformConstraint.new()
## child.bind(source, weapon_bone)
## child.target_node = hand_socket
## child.rotation_offset = deg_to_rad(-90.0)
## child.step(delta)
## [/codeblock]
class_name TransformConstraint
extends RefCounted

var source: BoneSource = null
var bone: Variant = null

var enabled: bool = true
## 0 = native pose, 1 = fully following the target transform.
var weight: float = 1.0
## Node2D whose global transform is followed. Ignored when a provider is set.
var target_node: Node2D = null
## Optional `func() -> Transform2D` provider, for procedurally computed sockets.
var transform_provider: Callable = Callable()

var follow_rotation: bool = true
var follow_position: bool = false
## Added to the target rotation, in radians.
var rotation_offset: float = 0.0
## Target-space offset applied to the target origin, in world units.
var position_offset: Vector2 = Vector2.ZERO
## Critically damped smoothing constant. 0 = snap.
var smooth_time: float = 0.1
## Hard angular speed cap in degrees per second. 0 = unlimited.
var max_speed_deg: float = 0.0

var _angle: float = 0.0
var _angle_velocity: float = 0.0
var _position: Vector2 = Vector2.ZERO
var _position_velocity: Vector2 = Vector2.ZERO
var _has_state: bool = false


func bind(bone_source: BoneSource, follow_bone: Variant) -> bool:
	if bone_source == null or follow_bone == null:
		push_error("TransformConstraint.bind: null bone source or bone")
		return false
	source = bone_source
	bone = follow_bone
	_has_state = false
	return true


func set_target(transform_or_node: Variant) -> void:
	if transform_or_node is Node2D:
		target_node = transform_or_node
		transform_provider = Callable()
	elif transform_or_node is Callable:
		transform_provider = transform_or_node
		target_node = null


func reset() -> void:
	_has_state = false
	_angle_velocity = 0.0
	_position_velocity = Vector2.ZERO


## Advances one frame and returns telemetry.
func step(delta: float) -> Dictionary:
	if source == null or bone == null or not enabled or delta <= 0.0:
		return {"applied": false}

	var target_xf: Transform2D = _target_transform()
	var target_valid: bool = bool(_target_transform_valid)
	if not target_valid:
		return {"applied": false, "reason": "no_target"}

	var fk_dir: float = source.get_world_dir(bone)
	var parent_rotation: float = source.get_parent_global_rotation(bone)
	var wanted_dir: float = target_xf.get_rotation() + rotation_offset

	if not _has_state:
		_angle = fk_dir
		_position = source.get_origin(bone)
		_has_state = true

	if smooth_time > 0.0:
		var smoothed: Vector2 = RigKitMath.smooth_damp(_angle, wanted_dir, _angle_velocity, smooth_time, delta)
		_angle = smoothed.x
		_angle_velocity = smoothed.y
	else:
		_angle = wanted_dir
		_angle_velocity = 0.0

	if max_speed_deg > 0.0:
		var step_limit: float = deg_to_rad(max_speed_deg) * delta
		var delta_angle: float = RigKitMath.angle_delta(_angle, wanted_dir)
		if absf(delta_angle) > step_limit:
			_angle = _angle + signf(delta_angle) * step_limit

	if weight <= 0.0001:
		_angle = fk_dir
		_angle_velocity = 0.0
		return {"applied": false, "reason": "zero_weight"}

	var clamped_weight: float = clampf(weight, 0.0, 1.0)
	if follow_rotation:
		var out_dir: float = lerp_angle(fk_dir, _angle, clamped_weight)
		source.set_world_dir(bone, out_dir, parent_rotation)

	var moved: bool = false
	if follow_position and source.has_method("set_origin"):
		var wanted_pos: Vector2 = target_xf * position_offset
		if smooth_time > 0.0:
			var sx: Vector2 = RigKitMath.smooth_damp(_position.x, wanted_pos.x, _position_velocity.x, smooth_time, delta)
			var sy: Vector2 = RigKitMath.smooth_damp(_position.y, wanted_pos.y, _position_velocity.y, smooth_time, delta)
			_position = Vector2(sx.x, sy.x)
			_position_velocity = Vector2(sx.y, sy.y)
		else:
			_position = wanted_pos
		var fk_pos: Vector2 = source.get_origin(bone)
		moved = bool(source.set_origin(bone, fk_pos.lerp(_position, clamped_weight)))

	return {
		"applied": true,
		"dir": source.get_world_dir(bone),
		"target_dir": wanted_dir,
		"position_followed": moved,
	}


var _target_transform_valid: bool = false


func _target_transform() -> Transform2D:
	_target_transform_valid = false
	if transform_provider.is_valid():
		_target_transform_valid = true
		return transform_provider.call()
	if target_node != null and is_instance_valid(target_node):
		_target_transform_valid = true
		return target_node.global_transform
	return Transform2D.IDENTITY
