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


func get_length(bone: Variant) -> float:
	var bone_2d: Bone2D = bone as Bone2D
	if bone_2d == null:
		return -1.0
	return bone_2d.length


## Forgets the cached axis offsets, e.g. after re-binding a different skeleton.
func clear_cache() -> void:
	_offsets.clear()
