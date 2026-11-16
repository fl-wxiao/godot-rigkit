## Bone source for plain Godot 2D hierarchies: Node2D, Bone2D / Skeleton2D, or any
## Node2D chain whose children sit on the bone axis.
##
## The bone axis offset is detected once per bone: a bone points at its first
## Node2D child, so `child.position.angle()` in the bone's local frame is the
## offset between rotation and axis. Leaf bones (feet, hands) have no child and
## fall back to [member tip_axis_deg], which defaults to 0 (rigs authored along
## +X).
class_name Node2DBoneSource
extends BoneSource

## Fallback axis offset for leaf bones, in degrees. 0 = authored along +X,
## -90 = authored along +Y (Godot's Bone2D drawing convention).
var tip_axis_deg: float = 0.0

var _offsets: Dictionary = {}

## Per-bone inherit overrides. Godot's Node2D has no inherit option at all (it
## always composes the full parent transform), so writing these only makes a
## solver's expectation explicit - it cannot change what the engine does.
var _inherit: Dictionary = {}


func get_origin(bone: Variant) -> Vector2:
	var node: Node2D = bone as Node2D
	if node == null:
		return Vector2.ZERO
	return node.global_position


func get_world_dir(bone: Variant) -> float:
	var node: Node2D = bone as Node2D
	if node == null:
		return 0.0
	return node.global_rotation + get_dir_offset(bone)


func get_dir_offset(bone: Variant) -> float:
	if _offsets.has(bone):
		return _offsets[bone]
	var offset: float = deg_to_rad(tip_axis_deg)
	var node: Node = bone as Node
	if node != null:
		for child in node.get_children():
			var child_2d: Node2D = child as Node2D
			if child_2d != null and child_2d.position.length() > 0.0001:
				offset = child_2d.position.angle()
				break
	_offsets[bone] = offset
	return offset


func set_world_dir(bone: Variant, world_dir: float, parent_global_rotation: float) -> void:
	var node: Node2D = bone as Node2D
	if node == null:
		return
	node.rotation = RigKitMath.wrap_angle(world_dir - get_dir_offset(bone) - parent_global_rotation)


func get_parent_global_rotation(bone: Variant) -> float:
	var node: Node = bone as Node
	if node == null:
		return 0.0
	var parent: Node = node.get_parent()
	var parent_2d: Node2D = parent as Node2D
	if parent_2d == null:
		return 0.0
	return parent_2d.global_rotation


## Rotation, translation and scale. No shear: Node2D has no skew channel, so
## claiming it would make constraints write into a void.
func capabilities() -> int:
	return CAP_ROTATE | CAP_TRANSLATE | CAP_SCALE | CAP_LOCAL_ROTATION


func get_scale(bone: Variant) -> Vector2:
	var node: Node2D = bone as Node2D
	if node == null:
		return Vector2.ONE
	return node.scale


## Writes the node's local scale. Returns false when the bone is not a Node2D.
func set_scale(bone: Variant, value: Vector2) -> bool:
	var node: Node2D = bone as Node2D
	if node == null:
		return false
	node.scale = value
	return true


func get_local_rotation(bone: Variant) -> float:
	var node: Node2D = bone as Node2D
	if node == null:
		return 0.0
	return node.rotation


func set_local_rotation(bone: Variant, radians: float) -> bool:
	var node: Node2D = bone as Node2D
	if node == null:
		return false
	node.rotation = RigKitMath.wrap_angle(radians)
	return true


func get_inherit(bone: Variant) -> int:
	return int(_inherit.get(bone, RigKitTypes.Inherit.NORMAL))


## Records the mode for bookkeeping only: Node2D always behaves like NORMAL, so
## this returns false to say "not honoured", and the solver keeps using world
## writes instead of local ones.
func set_inherit(bone: Variant, mode: int) -> bool:
	_inherit[bone] = mode
	return false


func get_length(bone: Variant) -> float:
	var bone_2d: Bone2D = bone as Bone2D
	if bone_2d == null:
		return -1.0
	return bone_2d.length


## Moves a bone to [param world_pos], keeping its rotation.
##
## Only attachment constraints use this; the leg chains never do, so the zero
## stretch guarantee of the IK is unaffected.
func set_origin(bone: Variant, world_pos: Vector2) -> bool:
	var node: Node2D = bone as Node2D
	if node == null:
		return false
	var parent_2d: Node2D = node.get_parent() as Node2D
	if parent_2d == null:
		node.global_position = world_pos
	else:
		node.position = parent_2d.to_local(world_pos)
	return true


## Forgets the cached axis offsets, e.g. after re-binding a different skeleton.
func clear_cache() -> void:
	_offsets.clear()
	_inherit.clear()
