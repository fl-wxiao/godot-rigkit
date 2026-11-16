## Lightweight Verlet chain for hair, capes, straps and anything that should
## trail behind a moving skeleton.
##
## Simulation happens on world points with distance constraints; only directions
## are written back to the bones, so - exactly like the rest of RigKit - a strand
## can swing but can never stretch. [member stiffness] pulls the shape back
## towards the animation pose, which is what keeps the motion from drifting into
## a permanently deformed rag after a fast turn.
##
## [codeblock]
## var hair := VerletChain.new()
## hair.bind(source, [hair_1, hair_2, hair_3])
## hair.gravity = Vector2(0.0, 2.2)
## hair.step(delta, head_bone_origin, head_bone_dir)
## [/codeblock]
class_name VerletChain
extends RefCounted

var source: BoneSource = null
var bones: Array = []
var lengths: PackedFloat64Array = PackedFloat64Array()
var offsets: PackedFloat64Array = PackedFloat64Array()

## World gravity in units per second squared (y grows downwards).
var gravity: Vector2 = Vector2(0.0, 2.4)
## Velocity retention per step; <= 0.5 stops quickly, 0.95 swings freely.
var damping: float = 0.86
var constraint_iterations: int = 4
## 0 = fully simulated, 1 = glued to the animation pose.
var stiffness: float = 0.45
## 0 = invisible, 1 = fully simulated pose written.
var weight: float = 1.0
## Length used for the last bone when the source cannot measure it.
var tip_length: float = 0.12
## Optional world y the strand may not go below (a quick ground/collision plane).
var floor_y: float = INF

var _points: PackedVector2Array = PackedVector2Array()
var _previous: PackedVector2Array = PackedVector2Array()
var _ready: bool = false


func bind(bone_source: BoneSource, bone_list: Array) -> bool:
	if bone_source == null or bone_list.is_empty():
		push_error("VerletChain.bind: null source or empty bone list")
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
			push_warning("VerletChain.bind: degenerate segment length at index %d" % i)
			return false
		lengths.append(measured)
	_ready = false
	return true


func reset() -> void:
	_ready = false


## Advances one frame. [param anchor] is the world origin the strand hangs from,
## [param anchor_dir] its world direction (usually the parent bone's).
func step(delta: float, anchor: Vector2, anchor_dir: float) -> Dictionary:
	if source == null or bones.is_empty() or delta <= 0.0:
		return {"valid": false}
	if not _ready:
		if not _initialise(anchor):
			return {"valid": false}

	var dt: float = minf(delta, 1.0 / 30.0)
	var count: int = bones.size()

	# Verlet integration on the free points (index 0 is pinned to the anchor).
	for i in range(1, count + 1):
		var velocity: Vector2 = (_points[i] - _previous[i]) * damping
		_previous[i] = _points[i]
		_points[i] = _points[i] + velocity + gravity * dt * dt

	_points[0] = anchor
	_satisfy(anchor, count)
	_blend_to_fk(count)
	_satisfy(anchor, count)

	if weight <= 0.0001:
		return {"valid": true, "applied": false, "tip": _points[count]}

	_write(anchor_dir)
	return {"valid": true, "applied": true, "tip": _points[count], "anchor": anchor}


func _initialise(anchor: Vector2) -> bool:
	var count: int = bones.size()
	_points = PackedVector2Array()
	_previous = PackedVector2Array()
	_points.resize(count + 1)
	_previous.resize(count + 1)
	_points[0] = anchor
	_previous[0] = anchor
	for i in count:
		var dir: float = source.get_world_dir(bones[i])
		_points[i + 1] = _points[i] + RigKitMath.dir(dir) * lengths[i]
		_previous[i + 1] = _points[i + 1]
	_ready = true
	return true


## Pulls every point onto its segment length, keeping point 0 pinned.
func _satisfy(anchor: Vector2, count: int) -> void:
	for iteration in constraint_iterations:
		_points[0] = anchor
		for i in count:
			var segment: Vector2 = _points[i + 1] - _points[i]
			var current: float = segment.length()
			if current <= RigKitMath.EPS:
				segment = RigKitMath.dir(source.get_world_dir(bones[i]))
				current = 1.0
			var corrected: Vector2 = _points[i] + segment / current * lengths[i]
			if floor_y < INF and corrected.y > floor_y:
				corrected.y = floor_y
			_points[i + 1] = corrected


## Blends the simulated direction towards the animation pose.
func _blend_to_fk(count: int) -> void:
	if stiffness <= 0.0:
		return
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(count + 1)
	points[0] = _points[0]
	for i in count:
		var fk_dir: float = source.get_world_dir(bones[i])
		var simulated: Vector2 = _points[i + 1] - _points[i]
		var simulated_dir: float = RigKitMath.angle_of(simulated) if simulated.length_squared() > RigKitMath.EPS else fk_dir
		var blended: float = lerp_angle(simulated_dir, fk_dir, stiffness)
		points[i + 1] = points[i] + RigKitMath.dir(blended) * lengths[i]
	_previous = _points.duplicate()
	_points = points


func _write(anchor_dir: float) -> void:
	var parent_rotation: float = source.get_parent_global_rotation(bones[0])
	var previous_offset: float = offsets[0] if offsets.size() > 0 else 0.0
	for i in bones.size():
		var segment: Vector2 = _points[i + 1] - _points[i]
		var solved: float = RigKitMath.angle_of(segment) if segment.length_squared() > RigKitMath.EPS else source.get_world_dir(bones[i])
		var out_dir: float = lerp_angle(source.get_world_dir(bones[i]), solved, clampf(weight, 0.0, 1.0))
		source.set_world_dir(bones[i], out_dir, parent_rotation)
		parent_rotation = out_dir - previous_offset
		previous_offset = offsets[i]
