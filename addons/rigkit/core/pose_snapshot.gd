## Captures the pose of a set of bones so it can be put back later.
##
## Rig with constraints needs three things this gives it:
##
## * **Rollback for A/B.** Capture the authored pose, let the constraints run,
##   put the pose back — the classic before/after switch, and the only honest way
##   to measure what a constraint actually changed.
## * **Rest data for skinning.** [MeshDeform] needs the unconstrained joint
##   origins and axes of every bone it binds to.
## * **Diffing.** [method delta] and [method max_change] answer "did anything
##   move", which is what an assertion or a debug overlay wants to know.
##
## Only what a [BoneSource] can write is captured: origin and direction. Length
## is not stored because no adapter may change it — that is the zero-stretch
## guarantee the whole design is built on.
##
## [codeblock]
## var snap := PoseSnapshot.new(source, ["arm_ul", "arm_fl", "hand_l"])
## snap.capture()
## aim.step(delta)
## snap.restore()                      # back to the authored pose
## var moved: float = snap.max_change()
## [/codeblock]
class_name PoseSnapshot
extends RefCounted

var source: BoneSource = null
var bones: Array = []

var _entries: Array = []


func _init(bone_source: BoneSource = null, bone_list: Array = []) -> void:
	source = bone_source
	bones = bone_list.duplicate()


## Reads origin and direction of every tracked bone into the snapshot.
func capture() -> void:
	_entries.clear()
	if source == null:
		return
	for bone in bones:
		_entries.append({
			"bone": bone,
			"origin": source.get_origin(bone),
			"dir": source.get_world_dir(bone),
			"parent": source.get_parent_global_rotation(bone),
		})


## Writes the captured pose back. Rotation first, then origin, because an
## adapter may compute one from the other internally.
func restore() -> void:
	if source == null:
		return
	for entry in _entries:
		source.set_world_dir(entry["bone"], entry["dir"], entry["parent"])
	for entry in _entries:
		source.set_origin(entry["bone"], entry["origin"])


## Difference between the captured pose and the current one.
## Returns [code]{origin: Vector2, dir: float, angle: float, distance: float}[/code].
func delta(bone: Variant) -> Dictionary:
	var empty: Dictionary = {"origin": Vector2.ZERO, "dir": 0.0, "angle": 0.0, "distance": 0.0}
	var index: int = _find(bone)
	if source == null or index < 0:
		return empty
	var entry: Dictionary = _entries[index]
	var now_origin: Vector2 = source.get_origin(bone)
	var now_dir: float = source.get_world_dir(bone)
	var d: Vector2 = now_origin - entry["origin"]
	return {
		"origin": d,
		"dir": now_dir - entry["dir"],
		"angle": absf(RigKitMath.angle_delta(entry["dir"], now_dir)),
		"distance": d.length(),
	}


## Largest absolute rotation change, in radians.
func max_angle() -> float:
	var worst: float = 0.0
	for entry in _entries:
		worst = maxf(worst, delta(entry["bone"])["angle"])
	return worst


## Largest origin displacement, in world units.
func max_distance() -> float:
	var worst: float = 0.0
	for entry in _entries:
		worst = maxf(worst, delta(entry["bone"])["distance"])
	return worst


## True when nothing has moved beyond the tolerances.
func is_unchanged(max_angle_tolerance: float = 0.0, max_distance_tolerance: float = 0.0) -> bool:
	return max_angle() <= max_angle_tolerance and max_distance() <= max_distance_tolerance


## Rest origin of a captured bone, or [code]Vector2.ZERO[/code] when unknown.
func rest_origin(bone: Variant) -> Vector2:
	var index: int = _find(bone)
	if index < 0:
		return Vector2.ZERO
	return _entries[index]["origin"]


## Rest world direction of a captured bone, or 0 when unknown.
func rest_dir(bone: Variant) -> float:
	var index: int = _find(bone)
	if index < 0:
		return 0.0
	return _entries[index]["dir"]


func has_bone(bone: Variant) -> bool:
	return _find(bone) >= 0


func tracked_count() -> int:
	return _entries.size()


## Bones are matched by identity, never by content: a [Dictionary] bone mutates
## as soon as a constraint writes it, so a content key would stop matching the
## moment the pose it describes changed - the exact opposite of what a snapshot
## is for.
func _find(bone: Variant) -> int:
	for i in _entries.size():
		if is_same(_entries[i]["bone"], bone):
			return i
	return -1
