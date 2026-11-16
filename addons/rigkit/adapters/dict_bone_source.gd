## Bone source over plain dictionaries.
##
## Useful for procedural rigs, data driven characters, and headless tests: a
## bone is a Dictionary with `origin` (Vector2), `dir` (float world direction),
## optional `offset` (float), `length` (float) and `parent_rotation` (float).
##
## Dictionaries are reference types in GDScript, so [method set_world_dir] writes
## straight back into the caller's data.
##
## This adapter declares every capability, including shear, which makes it the
## reference implementation the constraints get tested against.
class_name DictBoneSource
extends BoneSource


func capabilities() -> int:
	return CAP_ROTATE | CAP_TRANSLATE | CAP_SCALE | CAP_SHEAR | CAP_LOCAL_ROTATION | CAP_INHERIT


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


func set_origin(bone: Variant, world_pos: Vector2) -> bool:
	var dict: Dictionary = bone as Dictionary
	dict["origin"] = world_pos
	return true


func get_scale(bone: Variant) -> Vector2:
	var dict: Dictionary = bone as Dictionary
	return dict.get("scale", Vector2.ONE)


func set_scale(bone: Variant, value: Vector2) -> bool:
	var dict: Dictionary = bone as Dictionary
	dict["scale"] = value
	return true


func get_shear(bone: Variant) -> Vector2:
	var dict: Dictionary = bone as Dictionary
	return dict.get("shear", Vector2.ZERO)


func set_shear(bone: Variant, value: Vector2) -> bool:
	var dict: Dictionary = bone as Dictionary
	dict["shear"] = value
	return true


func get_local_rotation(bone: Variant) -> float:
	var dict: Dictionary = bone as Dictionary
	return float(dict.get("local", 0.0))


func set_local_rotation(bone: Variant, radians: float) -> bool:
	var dict: Dictionary = bone as Dictionary
	dict["local"] = RigKitMath.wrap_angle(radians)
	return true


func get_inherit(bone: Variant) -> int:
	var dict: Dictionary = bone as Dictionary
	return int(dict.get("inherit", RigKitTypes.Inherit.NORMAL))


func set_inherit(bone: Variant, mode: int) -> bool:
	var dict: Dictionary = bone as Dictionary
	dict["inherit"] = mode
	return true


## Convenience factory so tests and procedural rigs stay short.
static func bone(origin: Vector2, dir: float = 0.0, length: float = 0.0, parent_rotation: float = 0.0) -> Dictionary:
	return {
		"origin": origin,
		"dir": dir,
		"length": length,
		"parent_rotation": parent_rotation,
		"offset": 0.0,
		"scale": Vector2.ONE,
		"shear": Vector2.ZERO,
		"local": 0.0,
		"inherit": RigKitTypes.Inherit.NORMAL,
	}
