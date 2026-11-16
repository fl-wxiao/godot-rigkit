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

## Spine runtimes report bone angles in degrees. Every auto-detected accessor is
## converted here, so the rest of RigKit keeps working in radians. Set false for a
## runtime that already speaks radians. Callables passed through [member api] are
## not converted - they are the caller's contract.
var rotation_is_degrees: bool = true

var _cache: Dictionary = {}

## Capability mask resolved from the last bone passed to
## [method detect_capabilities]. -1 means "not probed yet", and the adapter then
## claims rotation only - never more than it has proven it can do.
var _caps: int = -1


## Reads what the bone object can actually do and caches the mask.
##
## Called automatically on every write attempt, so a runtime that grows setters
## mid-session is picked up without re-binding.
func detect_capabilities(bone: Variant) -> int:
	var mask: int = CAP_ROTATE
	if _has(bone, "set_x") and _has(bone, "set_y"):
		mask |= CAP_TRANSLATE
	if _has(bone, "set_scale_x") and _has(bone, "set_scale_y"):
		mask |= CAP_SCALE
	if _has(bone, "set_shear_x") and _has(bone, "set_shear_y"):
		mask |= CAP_SHEAR
	if _has(bone, "set_rotation") or _has(bone, "set_local_rotation"):
		mask |= CAP_LOCAL_ROTATION
	if _has(bone, "set_inherit"):
		mask |= CAP_INHERIT
	_caps = mask
	return mask


func capabilities() -> int:
	return _caps if _caps >= 0 else CAP_ROTATE


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
		return _to_rad(float(bone.call("get_world_rotation_x"))) + get_dir_offset(bone)
	if _has(bone, "get_world_rotation"):
		return _to_rad(float(bone.call("get_world_rotation"))) + get_dir_offset(bone)
	if _has(bone, "get_world_transform"):
		var xf: Transform2D = bone.call("get_world_transform")
		return xf.get_rotation() + get_dir_offset(bone)
	return 0.0


func get_dir_offset(bone: Variant) -> float:
	if api.has("dir_offset"):
		return float(api["dir_offset"].call(bone))
	if _cache.has(bone):
		return _cache[bone]
	# Spine bones point along their local +X, and children are placed by explicit
	# translations, so a child's angle says nothing about the bone axis: ranger's
	# chest -> arm_ul sits at (70, 120), i.e. 54 degrees of pure nonsense. The axis
	# is the runtime's own convention (0 for every Spine export), not a measurement.
	# (Node2DBoneSource keeps the child heuristic - there a bone really is drawn
	# towards its child.)
	var offset: float = deg_to_rad(foot_axis_deg)
	_cache[bone] = offset
	return offset


func set_world_dir(bone: Variant, world_dir: float, parent_global_rotation: float) -> void:
	if api.has("set_dir"):
		api["set_dir"].call(bone, world_dir, parent_global_rotation)
		return
	var local_rotation: float = RigKitMath.wrap_angle(world_dir - get_dir_offset(bone) - parent_global_rotation)
	var written: float = _from_rad(local_rotation)
	if _has(bone, "set_rotation"):
		bone.call("set_rotation", written)
	elif _has(bone, "set_local_rotation"):
		bone.call("set_local_rotation", written)


func get_parent_global_rotation(bone: Variant) -> float:
	if api.has("parent_rot"):
		return float(api["parent_rot"].call(bone))
	if _has(bone, "get_parent"):
		var parent: Variant = bone.call("get_parent")
		if parent != null:
			if _has(parent, "get_world_rotation_x"):
				return _to_rad(float(parent.call("get_world_rotation_x")))
			if _has(parent, "get_world_rotation"):
				return _to_rad(float(parent.call("get_world_rotation")))
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


func get_scale(bone: Variant) -> Vector2:
	if api.has("scale"):
		return api["scale"].call(bone)
	if _has(bone, "get_scale_x") and _has(bone, "get_scale_y"):
		return Vector2(float(bone.call("get_scale_x")), float(bone.call("get_scale_y")))
	if _has(bone, "get_world_transform"):
		var xf: Transform2D = bone.call("get_world_transform")
		return xf.get_scale()
	return Vector2.ONE


func set_scale(bone: Variant, value: Vector2) -> bool:
	if api.has("set_scale"):
		api["set_scale"].call(bone, value)
		return true
	if _has(bone, "set_scale_x") and _has(bone, "set_scale_y"):
		bone.call("set_scale_x", value.x)
		bone.call("set_scale_y", value.y)
		return true
	return false


func get_shear(bone: Variant) -> Vector2:
	if api.has("shear"):
		return api["shear"].call(bone)
	if _has(bone, "get_shear_x") and _has(bone, "get_shear_y"):
		return Vector2(float(bone.call("get_shear_x")), float(bone.call("get_shear_y")))
	return Vector2.ZERO


func set_shear(bone: Variant, value: Vector2) -> bool:
	if api.has("set_shear"):
		api["set_shear"].call(bone, value)
		return true
	if _has(bone, "set_shear_x") and _has(bone, "set_shear_y"):
		bone.call("set_shear_x", value.x)
		bone.call("set_shear_y", value.y)
		return true
	return false


func get_local_rotation(bone: Variant) -> float:
	if api.has("local_rotation"):
		return float(api["local_rotation"].call(bone))
	if _has(bone, "get_rotation"):
		return _to_rad(float(bone.call("get_rotation")))
	if _has(bone, "get_local_rotation"):
		return _to_rad(float(bone.call("get_local_rotation")))
	return 0.0


func set_local_rotation(bone: Variant, radians: float) -> bool:
	if api.has("set_local_rotation"):
		api["set_local_rotation"].call(bone, radians)
		return true
	var written: float = _from_rad(radians)
	if _has(bone, "set_rotation"):
		bone.call("set_rotation", written)
		return true
	if _has(bone, "set_local_rotation"):
		bone.call("set_local_rotation", written)
		return true
	return false


func get_inherit(bone: Variant) -> int:
	if api.has("inherit"):
		return int(api["inherit"].call(bone))
	if _has(bone, "get_inherit"):
		return int(bone.call("get_inherit"))
	return RigKitTypes.Inherit.NORMAL


func set_inherit(bone: Variant, mode: int) -> bool:
	if api.has("set_inherit"):
		api["set_inherit"].call(bone, mode)
		return true
	if _has(bone, "set_inherit"):
		bone.call("set_inherit", mode)
		return true
	return false


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
		"get_scale_x", "get_scale_y", "set_scale_x", "set_scale_y",
		"get_shear_x", "get_shear_y", "set_shear_x", "set_shear_y",
		"get_inherit", "set_inherit",
	]:
		found[name] = _has(bone, name)
	return {"alive": true, "methods": found, "caps": SpineBoneSource.new_caps(bone)}


## Capability mask a fresh adapter instance would report for this bone.
static func new_caps(bone: Variant) -> int:
	var probe_source := SpineBoneSource.new()
	return probe_source.detect_capabilities(bone)


func _to_rad(value: float) -> float:
	return deg_to_rad(value) if rotation_is_degrees else value


func _from_rad(value: float) -> float:
	return rad_to_deg(value) if rotation_is_degrees else value


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
