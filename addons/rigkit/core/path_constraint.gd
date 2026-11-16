## Path constraint: places a bone on a path, and optionally turns it along the
## path's tangent.
##
## This is the Spine 4.2 path constraint expressed against a [BoneSource]:
##
## [codeblock]
## path        the [RigPath] the bones are laid out on
## position    distance along the path, in world units
## position_ratio  when >= 0 it replaces `position` with a fraction of the path
## rotate      align the bone axis with the tangent
## translate   move the bone origin onto the path
## rotate_offset   fixed angle added to the tangent (bone axis vs. flow)
## mix         0 = animation pose untouched, 1 = fully on the path
## [/codeblock]
##
## Differences from Spine, stated rather than hidden:
##
## * Spine's `spacing` is made explicit as [method step_chain], which walks a
##   list of bones at a fixed distance from each other. Implicit spacing inside
##   `step` would require the constraint to know the whole chain, which the
##   one-bone-on-one-path contract deliberately avoids.
## * `mix_x` / `mix_y` are one `mix`, because a [BoneSource] moves bones with a
##   single [method BoneSource.set_origin] call, not per axis.
##
## Translation requires [method BoneSource.set_origin] to return true. When the
## adapter cannot move bones (Rigby2D, spine-godot: rotation only), the constraint
## keeps rotating and reports [member translate_supported] = false instead of
## silently doing nothing.
class_name PathConstraint
extends RefCounted

var source: BoneSource = null
var path: RigPath = null
var bone: Variant = null

var enabled: bool = true
## 0..1 influence of the constraint.
var mix: float = 1.0

## Distance along the path in world units.
var position: float = 0.0
## When >= 0, used as a 0..1 fraction of the path length instead of [member position].
var position_ratio: float = -1.0
var wrap: bool = true

var translate: bool = true
var rotate: bool = true
## Angle added to the tangent before the bone axis is aligned with it.
var rotate_offset: float = 0.0

## False when the adapter rejected [method BoneSource.set_origin]; rotation keeps working.
var translate_supported: bool = true
## Distance actually used by the last [method step] (after clamping or wrapping).
var applied_distance: float = 0.0

var _can_translate: bool = true


## Evaluates the path at the current position and writes the bone.
func step(_delta: float = 0.0) -> void:
	if not enabled or source == null or path == null or bone == null or mix <= 0.0:
		return
	var distance: float = position
	if position_ratio >= 0.0:
		distance = position_ratio * path.get_length()
	var sample: Dictionary = path.sample(distance, wrap)
	applied_distance = float(sample["distance"])
	var target_point: Vector2 = sample["point"]
	var tangent_angle: float = RigKitMath.angle_of(sample["tangent"])

	if translate and _can_translate:
		var current_origin: Vector2 = source.get_origin(bone)
		var wanted: Vector2 = current_origin.lerp(target_point, clampf(mix, 0.0, 1.0))
		_can_translate = source.set_origin(bone, wanted)
		translate_supported = _can_translate

	if rotate:
		var parent_rotation: float = source.get_parent_global_rotation(bone)
		var current_dir: float = source.get_world_dir(bone)
		var target_dir: float = tangent_angle + rotate_offset
		var blended: float = current_dir + RigKitMath.angle_delta(current_dir, target_dir) * clampf(mix, 0.0, 1.0)
		source.set_world_dir(bone, blended, parent_rotation)


## Lays a whole chain on the path: every bone sits at `position + spacing * i`,
## which is how Spine spaces hair, tails and cloth bones along one curve.
func step_chain(bones: Array, spacing: float, _delta: float = 0.0) -> void:
	if not enabled or source == null or path == null:
		return
	var first_bone: Variant = bone
	for i in bones.size():
		bone = bones[i]
		var saved: float = position
		position += spacing * i
		step(_delta)
		position = saved
	bone = first_bone


## Length of the path, or 0 when none is assigned.
func path_length() -> float:
	return 0.0 if path == null else path.get_length()
