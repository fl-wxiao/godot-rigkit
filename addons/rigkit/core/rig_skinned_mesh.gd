## Renders what [MeshDeform] computes: a [MeshInstance2D] whose vertices are
## re-skinned every frame.
##
## [MeshDeform] is pure math - it answers "where did these vertices end up" and
## leaves drawing to you. This node closes the last gap: bind it to a deform
## instance once, point it at a triangle list and a texture, and call
## [method refresh] after the rig has written the pose. It rebuilds the
## [ArrayMesh] surface only when the vertex count or the triangle list changes,
## and rewrites vertex positions in place otherwise.
##
## [codeblock]
## var skinned := RigSkinnedMesh.new()
## skinned.setup(deform, rest_vertices, indices, uvs)
## skinned.texture = load("res://char/cape.png")
## add_child(skinned)
## # each frame, after rig.step():
## skinned.refresh()
## [/codeblock]
##
## This is not an attachment system: it does not read Spine's meshes, skins or
## draw order. It draws one triangle soup you already hold - enough for cloth, capes
## and custom deformation, and deliberately not a second runtime.
class_name RigSkinnedMesh
extends MeshInstance2D

var deform: MeshDeform = null
var rest_vertices: PackedVector2Array = PackedVector2Array()
## Triangle list, three indices per triangle.
var indices: PackedInt32Array = PackedInt32Array()
var uvs: PackedVector2Array = PackedVector2Array()

var _mesh: ArrayMesh = null
var _dirty_topology: bool = true
## Number of refreshes performed, for tests and HUDs.
var updates: int = 0


## Binds the deformation source and the geometry. UVs are optional (empty = a
## small triangle soup that needs no texture sampling).
func setup(deform_instance: MeshDeform, rest: PackedVector2Array, triangles: PackedInt32Array, tex_uvs: PackedVector2Array = PackedVector2Array()) -> bool:
	if deform_instance == null:
		push_error("RigSkinnedMesh.setup: null deform")
		return false
	if rest.is_empty() or triangles.is_empty():
		push_error("RigSkinnedMesh.setup: empty geometry")
		return false
	if triangles.size() % 3 != 0:
		push_error("RigSkinnedMesh.setup: index count is not a multiple of 3")
		return false
	deform = deform_instance
	rest_vertices = rest
	indices = triangles
	uvs = tex_uvs
	_dirty_topology = true
	return true


## Rebuilds the surface after a topology change (rest vertices, indices or UVs).
func mark_topology_dirty() -> void:
	_dirty_topology = true


## Writes the deformed vertices into the mesh. Cheap when the topology is
## unchanged: one vertex buffer update, no surface rebuild.
func refresh() -> bool:
	if deform == null or rest_vertices.is_empty() or indices.is_empty():
		return false
	var deformed: PackedVector2Array = deform.deform(rest_vertices)
	if deformed.size() != rest_vertices.size():
		push_error("RigSkinnedMesh.refresh: deform returned %d vertices for %d" % [deformed.size(), rest_vertices.size()])
		return false

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = deformed
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	if _mesh == null or _dirty_topology:
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh = _mesh
		_dirty_topology = false
	else:
		_mesh.surface_update_vertex_region(0, 0, _pack_vertices(deformed))
	updates += 1
	return true


## Current deformed position of one vertex, without going through the mesh. Used by
## tests and by hit tests that need the geometry rather than the pixel result.
func vertex_position(vertex_index: int) -> Vector2:
	if deform == null:
		return rest_vertices[vertex_index] if vertex_index < rest_vertices.size() else Vector2.ZERO
	return deform.deform_point(rest_vertices[vertex_index], vertex_index)


## Triangle count the mesh was built with.
func triangle_count() -> int:
	return indices.size() / 3


## Vertex buffer in the layout the renderer wants. Godot accepts a
## [PackedVector2Array] for a 2D mesh, but the surface update path wants raw bytes,
## so this serialises exactly that layout and nothing else.
func _pack_vertices(vertices: PackedVector2Array) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(vertices.size() * 8)
	var offset: int = 0
	for vertex in vertices:
		bytes.encode_float(offset, vertex.x)
		bytes.encode_float(offset + 4, vertex.y)
		offset += 8
	return bytes
