## ShapeCast2D backed ground sampler.
##
## A shape scan (rather than a single ray) is what keeps the foot from chattering
## on bumpy ground: the probe reports the first contact of a small circle, so a
## pebble edge under one corner no longer produces a spike.
##
## The sampler owns a [ShapeCast2D] child of [param host], which must be inside
## the scene tree for physics queries to run.
class_name PhysicsProbeSampler
extends RefCounted

var start_lift: float = 0.05
var depth: float = 0.6

var _cast: ShapeCast2D = null


func _init(host: Node, layer_mask: int = 1, radius: float = 0.03, probe_depth: float = 0.6) -> void:
	depth = probe_depth
	# A shapecast that starts inside a collision reports "not colliding", so the
	# probe must begin clear of the ground: one radius plus a margin.
	start_lift = maxf(radius, 0.005) + 0.02
	if host == null:
		push_warning("PhysicsProbeSampler: host node is null, sampler disabled")
		return
	_cast = ShapeCast2D.new()
	_cast.name = "RigKitProbe"
	_cast.enabled = true
	_cast.collision_mask = layer_mask
	_cast.collide_with_areas = false
	_cast.collide_with_bodies = true
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = maxf(radius, 0.005)
	_cast.shape = shape
	_cast.target_position = Vector2(0.0, depth)
	host.add_child(_cast)


## `func(world_pos: Vector2) -> Dictionary` compatible with [member GroundProbe.sampler].
func sample(world_pos: Vector2) -> Dictionary:
	var miss: Dictionary = {"hit": false, "point": world_pos, "normal": Vector2.UP}
	if _cast == null or not _cast.is_inside_tree():
		return miss
	_cast.global_position = world_pos + Vector2(0.0, -start_lift)
	_cast.target_position = Vector2(0.0, depth + start_lift)
	_cast.force_shapecast_update()
	if not _cast.is_colliding():
		return miss
	var point: Vector2 = _cast.get_collision_point(0)
	var normal: Vector2 = _cast.get_collision_normal(0)
	return {"hit": true, "point": point, "normal": normal}


func free_probe() -> void:
	if _cast != null and is_instance_valid(_cast):
		_cast.queue_free()
	_cast = null
