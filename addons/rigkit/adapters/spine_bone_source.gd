## Optional adapter for third party skeleton runtimes that expose per-bone
## transforms (the bundled default targets the spine-godot public bone API).
##
## RigKit does not ship, vendor or wrap any proprietary runtime: this adapter only
## calls the public bone accessors of the runtime you already licensed, and it
## degrades gracefully when a method is missing. If your runtime names things
## differently, pass your own callables through [member api] - five functions is
## the whole contract.
##
## [codeblock]
## var src := SpineBoneSource.new()
## src.api = {
##     "origin": func(bone): return bone.get_world_transform().origin,
##     "dir": func(bone): return bone.get_world_transform().get_rotation(),
##     "set_dir": func(bone, world_dir, parent_rot): bone.set_rotation(world_dir - parent_rot),
##     "parent_rot": func(bone): return bone.get_parent().get_world_rotation(),
##     "length": func(bone): return bone.get_length(),
## }
## [/codeblock]
class_name SpineBoneSource
extends BoneSource

## Accessor set. Every key is optional; missing keys fall back to the
## auto-detected spine-godot defaults.
var api: Dictionary = {}

## Fallback axis offset for the foot bone, in degrees. Autorigs that draw bones
## along +X keep this at 0.
var foot_axis_deg: float = 0.0

var _cache: Dictionary = {}


func get_origin(bone: Variant) -> Vector2:
	if api.has("origin"):
		return api["origin"].call(bone)
	if _has(bone, "get_world_x") and _has(bone, "get_world_y"):
		return Vector2(bone.call("get_world_x"), bone.call("get_world_y"))
	if _has(bone, "get_world_transform"):
		var xf: Transform2D = bone.call("get_world_transform")
		return xf.origin
	return Vector2.ZERO


func get_world_dir(bone: Variant) -> float:
	if api.has("dir"):
		return float(api["dir"].call(bone))
	if _has(bone, "get_world_rotation_x"):
		return float(bone.call("get_world_rotation_x")) + get_dir_offset(bone)
	if _has(bone, "get_world_rotation"):
		return float(bone.call("get_world_rotation")) + get_dir_offset(bone)
	if _has(bone, "get_world_transform"):
		var xf: Transform2D = bone.call("get_world_transform")
		return xf.get_rotation() + get_dir_offset(bone)
	return 0.0


func get_dir_offset(bone: Variant) -> float:
	if api.has("dir_offset"):
		return float(api["dir_offset"].call(bone))
	if _cache.has(bone):
		return _cache[bone]
	var offset: float = 0.0
	if _has(bone, "get_children"):
		for child in bone.call("get_children"):
			var child_len: float = _length_of(child)
			if child_len > 0.0001:
				offset = _angle_between(bone, child, child_len)
				break
	else:
		offset = deg_to_rad(foot_axis_deg)
	_cache[bone] = offset
	return offset


func set_world_dir(bone: Variant, world_dir: float, parent_global_rotation: float) -> void:
	if api.has("set_dir"):
		api["set_dir"].call(bone, world_dir, parent_global_rotation)
		return
	var local_rotation: float = RigKitMath.wrap_angle(world_dir - get_dir_offset(bone) - parent_global_rotation)
	if _has(bone, "set_rotation"):
		bone.call("set_rotation", local_rotation)
	elif _has(bone, "set_local_rotation"):
		bone.call("set_local_rotation", local_rotation)


func get_parent_global_rotation(bone: Variant) -> float:
	if api.has("parent_rot"):
		return float(api["parent_rot"].call(bone))
	if _has(bone, "get_parent"):
		var parent: Variant = bone.call("get_parent")
		if parent != null:
			if _has(parent, "get_world_rotation_x"):
				return float(parent.call("get_world_rotation_x"))
			if _has(parent, "get_world_rotation"):
				return float(parent.call("get_world_rotation"))
			if _has(parent, "get_world_transform"):
				var xf: Transform2D = parent.call("get_world_transform")
				return xf.get_rotation()
	return 0.0


func get_length(bone: Variant) -> float:
	if api.has("length"):
		return float(api["length"].call(bone))
	if _has(bone, "get_length"):
		return float(bone.call("get_length"))
	return -1.0


## Reports which accessors were actually resolved, so wiring a new runtime is a
## two minute job instead of a guess:
## [codeblock]
## print(SpineBoneSource.probe(my_bone))
## [/codeblock]
static func probe(bone: Variant) -> Dictionary:
	var found: Dictionary = {}
	if bone == null:
		return {"alive": false}
	for name in [
		"get_world_x", "get_world_y", "get_world_transform",
		"get_world_rotation", "get_world_rotation_x",
		"set_rotation", "set_local_rotation",
		"get_length", "get_parent", "get_children",
	]:
		found[name] = _has(bone, name)
	return {"alive": true, "methods": found}


static func _has(obj: Variant, method: String) -> bool:
	if obj == null:
		return false
	if obj is Object:
		return obj.has_method(method)
	return false


func _length_of(bone: Variant) -> float:
	return get_length(bone)


func _angle_between(parent: Variant, child: Variant, child_length: float) -> float:
	# Spine bones point along their local +X axis and children are authored as
	# translations, so the offset is the child's local angle. When the runtime
	# hides translations, fall back to the configured foot axis.
	if _has(child, "get_x") and _has(child, "get_y"):
		var lx: float = child.call("get_x")
		var ly: float = child.call("get_y")
		if absf(lx) + absf(ly) > 0.0001:
			return atan2(ly, lx)
	return deg_to_rad(foot_axis_deg)
