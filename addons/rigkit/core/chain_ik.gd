## Chain IK (FABRIK) for tails, tendrils, ropes and multi-segment limbs.
##
## Unlike the two bone solver this one works on an arbitrary number of segments.
## It follows the same rule as everything else in RigKit: the solver may move
## points freely, but only *directions* are written back, so every segment keeps
## the length it was bound with - the chain can bend, it can never stretch.
##
## [codeblock]
## var chain := ChainIK.new()
## chain.bind(source, [tail_1, tail_2, tail_3, tail_4])
## chain.weight = 0.7
## chain.solve(world_target, 0.7)
## [/codeblock]
class_name ChainIK
extends RefCounted

var source: BoneSource = null
var bones: Array = []
var lengths: PackedFloat64Array = PackedFloat64Array()
var offsets: PackedFloat64Array = PackedFloat64Array()
## Solver iterations per frame; 4..10 is plenty for <= 6 segments.
var iterations: int = 8
## End effector error under which the solver stops early, in world units.
var tolerance: float = 0.002
## Length used for the last bone when the source cannot measure it, in world units.
var tip_length: float = 0.15

var _last_dirs: PackedFloat64Array = PackedFloat64Array()
var _has_last: bool = false


func bind(bone_source: BoneSource, bone_list: Array) -> bool:
	if bone_source == null or bone_list.is_empty():
		push_error("ChainIK.bind: null source or empty bone list")
		return false
	source = bone_source
	bones = bone_list.duplicate()
	lengths = PackedFloat64Array()
	offsets = PackedFloat64Array()
	for i in bones.size():
		var bone: Variant = bones[i]
		offsets.append(source.get_dir_offset(bone))
		var measured: float = source.get_length(bone)
		if measured <= 0.0:
			if i + 1 < bones.size():
				measured = (source.get_origin(bones[i + 1]) - source.get_origin(bone)).length()
			else:
				measured = tip_length
		if measured <= 0.0:
			push_warning("ChainIK.bind: degenerate segment length at index %d" % i)
			return false
		lengths.append(measured)
	_last_dirs = PackedFloat64Array()
	_last_dirs.resize(bones.size())
	_has_last = false
	return true


func total_length() -> float:
	var total: float = 0.0
	for length in lengths:
		total += length
	return total


## FK joint chain: n + 1 points, starting at the first bone's origin.
func fk_points() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var count: int = bones.size()
	points.resize(count + 1)
	points[0] = source.get_origin(bones[0])
	for i in count:
		points[i + 1] = points[i] + RigKitMath.dir(source.get_world_dir(bones[i])) * lengths[i]
	return points


func fk_dirs() -> PackedFloat64Array:
	var dirs: PackedFloat64Array = PackedFloat64Array()
	dirs.resize(bones.size())
	for i in bones.size():
		dirs[i] = source.get_world_dir(bones[i])
	return dirs


## Solves the chain towards [param target] and writes the blended directions.
func solve(target: Vector2, weight: float = 1.0) -> Dictionary:
	if source == null or bones.is_empty() or lengths.is_empty():
		return {"valid": false}

	var count: int = bones.size()
	var fk: PackedFloat64Array = fk_dirs()
	var root: Vector2 = source.get_origin(bones[0])

	# FK points are rebuilt from measured lengths, not from live origins: the
	# written pose has to be self-consistent inside the frame.
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(count + 1)
	points[0] = root
	for i in count:
		points[i + 1] = points[i] + RigKitMath.dir(fk[i]) * lengths[i]

	var total: float = total_length()
	var reachable: bool = true
	var to_target: Vector2 = target - root
	if to_target.length() > total - 0.0001:
		reachable = false
		var flat_dir: Vector2 = to_target.normalized() if to_target.length_squared() > RigKitMath.EPS else Vector2.RIGHT
		var running: float = 0.0
		for i in count:
			running += lengths[i]
			points[i + 1] = root + flat_dir * running
		points[count] = root + flat_dir * total
	else:
		for iteration in iterations:
			points[count] = target
			for i in range(count - 1, -1, -1):
				var backward: Vector2 = points[i] - points[i + 1]
				if backward.length_squared() <= RigKitMath.EPS:
					backward = points[i - 1] - points[i] if i > 0 else Vector2.LEFT
				points[i] = points[i + 1] + backward.normalized() * lengths[i]
			points[0] = root
			for i in count:
				var forward: Vector2 = points[i + 1] - points[i]
				if forward.length_squared() <= RigKitMath.EPS:
					forward = RigKitMath.dir(fk[i])
				points[i + 1] = points[i] + forward.normalized() * lengths[i]
			if (points[count] - target).length() <= tolerance:
				break

	var solved_dirs: PackedFloat64Array = PackedFloat64Array()
	solved_dirs.resize(count)
	for i in count:
		var segment: Vector2 = points[i + 1] - points[i]
		solved_dirs[i] = RigKitMath.angle_of(segment) if segment.length_squared() > RigKitMath.EPS else fk[i]

	var applied: bool = weight > 0.0001
	if applied:
		_apply(fk, solved_dirs, clampf(weight, 0.0, 1.0))

	_last_dirs = solved_dirs
	_has_last = true
	return {
		"valid": true,
		"reachable": reachable,
		"error": (points[count] - target).length(),
		"end": points[count],
		"target": target,
		"applied": applied,
	}


func _apply(fk: PackedFloat64Array, solved: PackedFloat64Array, weight: float) -> void:
	var parent_rotation: float = source.get_parent_global_rotation(bones[0])
	var previous_offset: float = offsets[0]
	for i in bones.size():
		var out_dir: float = lerp_angle(fk[i], solved[i], weight)
		source.set_world_dir(bones[i], out_dir, parent_rotation)
		parent_rotation = out_dir - previous_offset
		previous_offset = offsets[i]
