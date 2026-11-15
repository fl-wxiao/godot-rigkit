## Bone source over plain dictionaries.
##
## Useful for procedural rigs, data driven characters, and headless tests: a
## bone is a Dictionary with `origin` (Vector2), `dir` (float world direction),
## optional `offset` (float), `length` (float) and `parent_rotation` (float).
##
## Dictionaries are reference types in GDScript, so [method set_world_dir] writes
## straight back into the caller's data.
class_name DictBoneSource
extends BoneSource


func get_origin(bone: Variant) -> Vector2:
	var dict: Dictionary = bone as Dictionary
	return dict.get("origin", Vector2.ZERO)


func get_world_dir(bone: Variant) -> float:
	var dict: Dictionary = bone as Dictionary
	return float(dict.get("dir", 0.0))


func get_dir_offset(bone: Variant) -> float:
	var dict: Dictionary = bone as Dictionary
	return float(dict.get("offset", 0.0))


func set_world_dir(bone: Variant, world_dir: float, _parent_global_rotation: float) -> void:
	var dict: Dictionary = bone as Dictionary
	dict["dir"] = world_dir


func get_parent_global_rotation(bone: Variant) -> float:
	var dict: Dictionary = bone as Dictionary
	return float(dict.get("parent_rotation", 0.0))


func get_length(bone: Variant) -> float:
	var dict: Dictionary = bone as Dictionary
	return float(dict.get("length", -1.0))


## Convenience factory so tests and procedural rigs stay short.
static func bone(origin: Vector2, dir: float = 0.0, length: float = 0.0, parent_rotation: float = 0.0) -> Dictionary:
	return {
		"origin": origin,
		"dir": dir,
		"length": length,
		"parent_rotation": parent_rotation,
		"offset": 0.0,
	}
