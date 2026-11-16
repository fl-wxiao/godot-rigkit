## Arc-length parameterised polyline used by [PathConstraint].
##
## A [Curve2D] would drag a scene tree dependency into a pure data constraint, so
## the path is its own small value object: give it points, get back points and
## tangents by distance. Sampling is arc-length based rather than segment based,
## otherwise a path with one long segment would move a tail twice as fast as one
## with short segments - the exact artefact Spine avoids by storing vertex
## lengths.
##
## [codeblock]
## var path := RigPath.new()
## path.set_points([Vector2(0, 0), Vector2(0, -100), Vector2(40, -160)], false)
## var at_60: Dictionary = path.sample(60.0)   # {"point": ..., "tangent": ..., ...}
## [/codeblock]
class_name RigPath
extends RefCounted

var _points: PackedVector2Array = PackedVector2Array()
var _cumulative: PackedFloat32Array = PackedFloat32Array()
var _closed: bool = false
var _length: float = 0.0


## Replaces the path geometry. [param closed] appends the closing segment from the
## last point back to the first, then wraps sampling instead of clamping it.
func set_points(points: PackedVector2Array, closed: bool = false) -> void:
	_points = PackedVector2Array()
	for point in points:
		if not is_finite(point.x) or not is_finite(point.y):
			continue
		_points.append(point)
	_closed = closed and _points.size() > 2
	var walk: PackedVector2Array = _points
	if _closed:
		walk = _points.duplicate()
		walk.append(_points[0])
	_cumulative = PackedFloat32Array([0.0])
	_length = 0.0
	for i in range(1, walk.size()):
		_length += walk[i].distance_to(walk[i - 1])
		_cumulative.append(_length)


func get_point_count() -> int:
	return _points.size()


func is_closed() -> bool:
	return _closed


## Total arc length in world units.
func get_length() -> float:
	return _length


## Returns [code]{point, tangent, distance, clamped}[/code] for [param distance]
## along the path.
##
## On an open path the request is clamped to the ends and [code]clamped[/code] is
## true; on a closed path it wraps. A degenerate path (no length) returns the
## first point with a +X tangent instead of a NaN.
func sample(distance: float, wrap: bool = true) -> Dictionary:
	if _points.is_empty():
		return {"point": Vector2.ZERO, "tangent": Vector2.RIGHT, "distance": 0.0, "clamped": true}
	if _length <= 0.0:
		return {"point": _points[0], "tangent": Vector2.RIGHT, "distance": 0.0, "clamped": true}

	var d: float = distance
	var clamped: bool = false
	if _closed and wrap:
		d = fposmod(d, _length)
	else:
		if d < 0.0:
			d = 0.0
			clamped = true
		elif d > _length:
			d = _length
			clamped = true

	var segment: int = _find_segment(d)
	var walk: PackedVector2Array = _points
	if _closed:
		walk = _points.duplicate()
		walk.append(_points[0])
	var a: Vector2 = walk[segment]
	var b: Vector2 = walk[segment + 1]
	var span: float = _cumulative[segment + 1] - _cumulative[segment]
	var t: float = 0.0 if span <= 0.0 else (d - _cumulative[segment]) / span
	var tangent: Vector2 = b - a
	if tangent.length_squared() <= 0.0:
		tangent = Vector2.RIGHT
	else:
		tangent = tangent.normalized()
	return {
		"point": a.lerp(b, clampf(t, 0.0, 1.0)),
		"tangent": tangent,
		"distance": d,
		"clamped": clamped,
	}


## Shortest distance from [param point] to the path, found by sampling the
## segments analytically. Used to author paths against existing art.
func closest_distance(point: Vector2) -> float:
	if _points.is_empty():
		return 0.0
	var best: float = INF
	var walk: PackedVector2Array = _points
	if _closed:
		walk = _points.duplicate()
		walk.append(_points[0])
	for i in range(1, walk.size()):
		var a: Vector2 = walk[i - 1]
		var b: Vector2 = walk[i]
		var ab: Vector2 = b - a
		var length_squared: float = ab.length_squared()
		var t: float = 0.0
		if length_squared > 0.0:
			t = clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
		best = minf(best, point.distance_to(a + ab * t))
	return best


## Index of the segment containing [param distance].
func _find_segment(distance: float) -> int:
	var last: int = _cumulative.size() - 2
	for i in range(last + 1):
		if distance <= _cumulative[i + 1]:
			return i
	return maxi(last, 0)
