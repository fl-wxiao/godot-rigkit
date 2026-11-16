## Linear blend skinning on a vertex array, driven by the same bones every other
## RigKit module writes through.
##
## Why this exists: Spine and Rigby2D both support mesh attachments with per-vertex
## bone weights, and the runtime deforms them itself. RigKit does not replace that
## — but the *same math* is needed for three things the runtime cannot do:
##
## * **Validating weights** without running the real runtime (does a mesh tear at
##   the elbow? does a cape vertex carry too much of the wrong bone?).
## * **Custom mesh draws.** Anything drawn as your own `MeshInstance2D`,
##   `PackedVector2Array` or a `Line2D` has no skeleton behind it; this deforms it.
## * **Tests.** A weighted vertex cloud is the only way to assert what a rig does
##   to geometry, separately from what it does to bones.
##
## It is plain textbook skinning: [code]v' = Σ w_i · (T_i · v)[/code] with
## [code]T_i[/code] the bone's rest-to-current transform (rotate about the rest joint
## by the direction delta, then translate to the current joint). That is exactly
## what Spine's mesh deformation reduces to when a vertex sits on one bone — which
## is why a rigid vertex moves rigidly and never scales.
##
## [codeblock]
## var mesh := MeshDeform.new(source)
## mesh.bind_vertex(0, "hand_l", 1.0)
## mesh.capture_rest()
## aim.step(delta)
## var moved: PackedVector2Array = mesh.deform(rest_vertices)
## [/codeblock]
class_name MeshDeform
extends RefCounted

var source: BoneSource = null

## Bones in bind order: [code]{bone, rest_origin, rest_dir}[/code].
var _bones: Array = []
## vertex index -> Array of [bone slot, weight].
var _bindings: Dictionary = {}


func _init(bone_source: BoneSource = null) -> void:
	source = bone_source


## Binds a bone, using the pose it currently has as its rest pose.
## Call [method capture_rest] again when the authored pose changes.
func bind_bone(bone: Variant) -> int:
	for i in _bones.size():
		if is_same(_bones[i]["bone"], bone):
			return i
	var rest_origin: Vector2 = Vector2.ZERO
	var rest_dir: float = 0.0
	if source != null:
		rest_origin = source.get_origin(bone)
		rest_dir = source.get_world_dir(bone)
	# Identity, not content: see PoseSnapshot for why a Dictionary bone cannot be a key.
	_bones.append({"bone": bone, "rest_origin": rest_origin, "rest_dir": rest_dir})
	return _bones.size() - 1


## Re-reads the current pose as the rest pose for every bound bone.
func capture_rest() -> void:
	if source == null:
		return
	for entry in _bones:
		entry["rest_origin"] = source.get_origin(entry["bone"])
		entry["rest_dir"] = source.get_world_dir(entry["bone"])


## Adds influence of [param bone] on [param vertex_index]. Weights are normalised
## in [method deform], so callers can use whatever scale they like (Spine exports
## percentages, 0..1, or integers).
func bind_vertex(vertex_index: int, bone: Variant, weight: float) -> void:
	if vertex_index < 0 or weight <= 0.0 or not is_finite(weight):
		return
	var slot: int = bind_bone(bone)
	if not _bindings.has(vertex_index):
		_bindings[vertex_index] = []
	_bindings[vertex_index].append([slot, weight])


## Number of vertices with at least one bone.
func bound_vertex_count() -> int:
	return _bindings.size()


## Deforms [param rest_vertices] into a new array of the same size.
##
## Vertices with no weight (or a weight that cancelled out) are copied unchanged:
## a rig must not drag along geometry nobody bound to it.
func deform(rest_vertices: PackedVector2Array) -> PackedVector2Array:
	var output: PackedVector2Array = PackedVector2Array()
	output.resize(rest_vertices.size())
	for i in rest_vertices.size():
		output[i] = deform_point(rest_vertices[i], i)
	return output


## Deforms a single vertex. [param vertex_index] selects the bindings; pass
## [code]-1[/code] to get the point back unchanged.
func deform_point(point: Vector2, vertex_index: int) -> Vector2:
	if source == null or not _bindings.has(vertex_index):
		return point
	var weights: Array = _bindings[vertex_index]
	var total: float = 0.0
	for binding in weights:
		total += binding[1]
	if total <= 0.0:
		return point
	var result: Vector2 = Vector2.ZERO
	for binding in weights:
		var entry: Dictionary = _bones[binding[0]]
		var weight: float = binding[1] / total
		var now_origin: Vector2 = source.get_origin(entry["bone"])
		var now_dir: float = source.get_world_dir(entry["bone"])
		var delta: float = RigKitMath.angle_delta(entry["rest_dir"], now_dir)
		var local: Vector2 = point - entry["rest_origin"]
		result += (now_origin + local.rotated(delta)) * weight
	return result


## Parses a Spine mesh `vertices` array and binds accordingly.
##
## Spine 4 stores, per vertex: `boneCount`, then `boneCount` slot indices, then one
## weight per slot (the same weight drives x and y). `bone_slots` maps those
## indices to bones — pass the skeleton's bone list in Spine order.
## Returns the number of vertices parsed, or -1 when the data does not add up.
func bind_spine_vertices(vertex_count: int, spine_vertices: PackedInt32Array, bone_slots: Array) -> int:
	var cursor: int = 0
	for vertex in vertex_count:
		if cursor >= spine_vertices.size():
			return -1
		var bone_count: int = spine_vertices[cursor]
		cursor += 1
		if bone_count <= 0 or cursor + bone_count * 2 > spine_vertices.size():
			return -1
		var slots: Array = []
		for i in bone_count:
			slots.append(spine_vertices[cursor + i])
		cursor += bone_count
		for i in bone_count:
			var slot: int = slots[i]
			if slot < 0 or slot >= bone_slots.size():
				return -1
			bind_vertex(vertex, bone_slots[slot], float(spine_vertices[cursor + i]))
		cursor += bone_count
	return vertex_count


