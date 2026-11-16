## Bone source for Rigby2D (`RigbySkeleton2D`, 烬塔's runtime).
##
## Rigby2D identifies bones by name, not by object, and its stock API only reads
## (`get_bone_position` / `get_bone_transform`). Two accessors are needed to drive
## a rig, both added upstream-side in a small patch (see
## docs/rigby2d-drive-patch.md):
##
## [codeblock]
## get_bone_world_rotation(bone) -> float      # radians, Godot axes
## set_bone_local_rotation(bone, radians) -> bool
## [/codeblock]
##
## Parents and lengths are read from the same skeleton JSON the node plays, so no
## extra asset work is needed.
##
## Note the axis convention: Rigby2D reports angles in Godot space (Y down,
## clockwise positive) already, so unlike [SpineBoneSource] there is no degree
## conversion here. Bone direction is the bone rotation itself: Spine bones point
## along their local +X, and children are placed by explicit translations, so the
## axis offset is always 0. (Do not reuse the "first child" heuristic here - for a
## rig like 烬塔's chest -> arm_ul at (70, 120) it would invent a 54 degree offset.)
class_name RigbyBoneSource
extends BoneSource

var node: Object = null

var _parents: Dictionary = {}
var _lengths: Dictionary = {}


## Binds to a `RigbySkeleton2D` node and reads its skeleton JSON for the bone tree.
func bind(skeleton_node: Object, skeleton_json_path: String) -> bool:
	if skeleton_node == null:
		push_error("RigbyBoneSource.bind: null node")
		return false
	node = skeleton_node
	_parents.clear()
	_lengths.clear()
	if skeleton_json_path.is_empty():
		return true
	var text: String = FileAccess.get_file_as_string(skeleton_json_path)
	if text.is_empty():
		push_warning("RigbyBoneSource: cannot read %s, parent map empty" % skeleton_json_path)
		return true
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return true
	for entry in (parsed as Dictionary).get("bones", []):
		var bone: Dictionary = entry
		var bone_name: String = String(bone.get("name", ""))
		if bone_name.is_empty():
			continue
		_parents[bone_name] = String(bone.get("parent", ""))
		_lengths[bone_name] = float(bone.get("length", 0.0))
	return true


func get_origin(bone: Variant) -> Vector2:
	if node == null:
		return Vector2.ZERO
	return node.call("get_bone_position", String(bone))


func get_world_dir(bone: Variant) -> float:
	if node == null:
		return 0.0
	return float(node.call("get_bone_world_rotation", String(bone)))


func get_dir_offset(_bone: Variant) -> float:
	return 0.0


func set_world_dir(bone: Variant, world_dir: float, parent_global_rotation: float) -> void:
	if node == null:
		return
	node.call("set_bone_local_rotation", String(bone), RigKitMath.wrap_angle(world_dir - parent_global_rotation))


func get_parent_global_rotation(bone: Variant) -> float:
	if node == null:
		return 0.0
	var parent: String = _parents.get(String(bone), "")
	if parent.is_empty():
		return 0.0
	return float(node.call("get_bone_world_rotation", parent))


func get_length(bone: Variant) -> float:
	return float(_lengths.get(String(bone), -1.0))


## True when the runtime has the two accessors the patch adds.
static func probe(runtime_node: Object) -> Dictionary:
	var found: Dictionary = {}
	for name in ["get_bone_position", "get_bone_world_rotation", "set_bone_local_rotation", "get_bone_names"]:
		found[name] = runtime_node != null and runtime_node.has_method(name)
	return {"writable": bool(found.get("set_bone_local_rotation", false)), "methods": found}
