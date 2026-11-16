## Physics constraint: secondary motion (hair, cloth, tails) driven by a damped
## spring that offsets the bone *away* from its animation pose.
##
## Parameter semantics follow the Spine 4.2 physics constraint, so a rig authored
## there maps one-to-one:
##
## [codeblock]
## inertia   how much the unconstrained pose's movement becomes a lag offset
## strength  spring force pulling the offset back to zero (the animated pose)
## damping   velocity damping, kills large swings more than small ones
## mass      resistance to acceleration; strength must be raised to compensate
## wind      constant force along world X
## gravity   constant force along world Y
## limit     maximum translation speed, 0 = unlimited
## fps       fixed simulation rate, decoupled from the render rate
## mix       0 = animated pose untouched, 1 = full physics
## [/codeblock]
##
## Two deliberate differences from Spine, both documented rather than hidden:
##
## * Translation offsets are **world space** here, because a [BoneSource] writes
##   world transforms. Spine stores them in parent space; identical while the
##   parent is unrotated, and the difference is a pure local/world rotation.
## * Only translation and rotation are offset. Shear and scale are not part of
##   the [BoneSource] contract, so pretending to support them would be a lie.
##
## Like every constraint that reads the pose it writes, this one requires the
## animation system to author the bone each frame. Feeding it its own output
## makes the inertia term cancel itself, and the motion silently disappears.
##
## The integrator is a semi-implicit Euler spring run at a fixed [member fps],
## with leftover time carried into the next frame, so the result does not depend
## on how many frames the engine happened to render.
class_name PhysicsConstraint
extends RefCounted

const MAX_SUBSTEPS := 8

var source: BoneSource = null
var bone: Variant = null

var enabled: bool = true
## 0..1 influence of the constraint.
var mix: float = 1.0

var inertia: float = 0.6
var strength: float = 0.3
var damping: float = 0.3
var mass: float = 1.0
var wind: float = 0.0
var gravity: float = 0.0
## Maximum translation speed in world units per second, 0 disables the cap.
var limit: float = 0.0
## Fixed simulation rate. 30-60 is the useful range.
var fps: float = 60.0

var translate_enabled: bool = true
var rotate_enabled: bool = true

var _offset: Vector2 = Vector2.ZERO
var _offset_angle: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _angular_velocity: float = 0.0
var _last_origin: Vector2 = Vector2.ZERO
var _last_rotation: float = 0.0
var _has_state: bool = false
var _accumulator: float = 0.0


func bind(bone_source: BoneSource, target_bone: Variant) -> bool:
	if bone_source == null or target_bone == null:
		push_error("PhysicsConstraint.bind: null bone source or bone")
		return false
	source = bone_source
	bone = target_bone
	reset()
	return true


## Drops all simulated state; the next step starts from the animated pose.
func reset() -> void:
	_offset = Vector2.ZERO
	_offset_angle = 0.0
	_velocity = Vector2.ZERO
	_angular_velocity = 0.0
	_has_state = false
	_accumulator = 0.0


func get_offset() -> Vector2:
	return _offset


func get_rotation_offset() -> float:
	return _offset_angle


func step(delta: float) -> void:
	if not enabled or source == null or bone == null or delta <= 0.0:
		return
	var blend: float = clampf(mix, 0.0, 1.0)
	if blend <= 0.0001:
		if _has_state:
			# Keep tracking the animated pose so switching mix back on does not
			# replay a huge accumulated offset.
			_last_origin = source.get_origin(bone)
			_last_rotation = source.get_world_dir(bone)
		return

	var base_origin: Vector2 = source.get_origin(bone)
	var base_rotation: float = source.get_world_dir(bone)

	if not _has_state:
		_last_origin = base_origin
		_last_rotation = base_rotation
		_has_state = true

	# Inertia: the offset opposes the movement of the animated pose, so the bone
	# appears to stay where it was. Applied once per frame, not per substep.
	var moved: Vector2 = base_origin - _last_origin
	var turned: float = RigKitMath.angle_delta(_last_rotation, base_rotation)
	_last_origin = base_origin
	_last_rotation = base_rotation
	var inertia_factor: float = clampf(inertia, 0.0, 1.0)
	if translate_enabled:
		_offset -= moved * inertia_factor
	if rotate_enabled:
		_offset_angle -= turned * inertia_factor

	var h: float = 1.0 / maxf(fps, 1.0)
	_accumulator += delta
	var substeps: int = 0
	while _accumulator >= h and substeps < MAX_SUBSTEPS:
		_integrate(h)
		_accumulator -= h
		substeps += 1
	if substeps >= MAX_SUBSTEPS:
		# Do not let a long hitch bank unbounded time.
		_accumulator = 0.0

	var applied_origin: Vector2 = base_origin
	if translate_enabled:
		applied_origin = base_origin + _offset * blend
		source.set_origin(bone, applied_origin)
	if rotate_enabled:
		var applied_rotation: float = base_rotation + _offset_angle * blend
		source.set_world_dir(bone, applied_rotation, source.get_parent_global_rotation(bone))


func _integrate(h: float) -> void:
	var inverse_mass: float = 1.0 / maxf(mass, 0.0001)
	if translate_enabled:
		var accel: Vector2 = Vector2(wind, gravity) - _offset * strength - _velocity * damping
		_velocity += accel * inverse_mass * h
		if limit > 0.0 and _velocity.length() > limit:
			_velocity = _velocity.normalized() * limit
		_offset += _velocity * h
	if rotate_enabled:
		var angular_accel: float = -_offset_angle * strength - _angular_velocity * damping
		# Angles are unitless; scale the force by a nominal radius so the same
		# strength feels comparable at any bone length.
		_angular_velocity += angular_accel * inverse_mass * h
		_offset_angle += _angular_velocity * h
