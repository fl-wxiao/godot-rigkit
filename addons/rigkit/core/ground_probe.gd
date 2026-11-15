## Two-probe ground sampler for one foot.
##
## Ports the P.3-4 requirement: heel and toe probes, both must hit, a shape scan
## instead of a single ray so bumpy ground does not chatter, a moving average on
## height and slope, and a tilt clamp so the foot never rotates past the limit.
##
## The physics query itself is injected as a [member sampler] callable
## `func(world_pos: Vector2) -> Dictionary` returning
## `{hit: bool, point: Vector2, normal: Vector2}`. That keeps this class free of
## scene-tree dependencies (and unit testable), while the shipped
## [PhysicsProbeSampler] provides the ShapeCast2D implementation.
class_name GroundProbe
extends RefCounted

## Ankle height above the ground point, in world units.
var ankle_height: float = 0.12
## Heel / toe probe offsets relative to the ankle.
var heel_offset: Vector2 = Vector2(-0.07, 0.0)
var toe_offset: Vector2 = Vector2(0.07, 0.0)
## Maximum foot tilt against the FK pose, radians.
var tilt_limit: float = deg_to_rad(20.0)
## Moving average window.
var filter_frames: int = 4

## Probe query. `func(world_pos: Vector2) -> Dictionary`.
var sampler: Callable = Callable()

var _height_filter: RigKitMath.MovingAverage = null
var _angle_filter: RigKitMath.MovingAverage = null


func _init(frames: int = 4) -> void:
	filter_frames = frames
	_rebuild_filters()


func _rebuild_filters() -> void:
	_height_filter = RigKitMath.MovingAverage.new(filter_frames)
	_angle_filter = RigKitMath.MovingAverage.new(filter_frames)


func configure(params: RigKitParams) -> void:
	ankle_height = params.ankle_height
	heel_offset = params.heel_offset
	toe_offset = params.toe_offset
	tilt_limit = params.tilt_limit_rad()
	if filter_frames != params.filter_frames:
		filter_frames = params.filter_frames
		_rebuild_filters()


## Samples the ground under a foot.
##
## [param foot_hint] current ankle world position; the probes are placed around it.
## Returns:
## [code]
## valid        bool     both probes hit and the sample is usable
## point        Vector2  ankle target sitting [member ankle_height] above the ground
## height       float    ground surface y
## surface_angle float   foot rotation that matches the slope, already tilt clamped
## slope_raw    float    unclamped slope angle, for the gizmo / diagnostics
## heel, toe    Vector2  raw hit points
## [/code]
func sample(foot_hint: Vector2) -> Dictionary:
	var result: Dictionary = {
		"valid": false,
		"point": foot_hint,
		"height": foot_hint.y + ankle_height,
		"surface_angle": 0.0,
		"slope_raw": 0.0,
		"heel": foot_hint,
		"toe": foot_hint,
	}
	if sampler.is_null() or not sampler.is_valid():
		return result

	var heel_hit: Dictionary = sampler.call(foot_hint + heel_offset)
	var toe_hit: Dictionary = sampler.call(foot_hint + toe_offset)
	result["heel"] = heel_hit.get("point", foot_hint)
	result["toe"] = toe_hit.get("point", foot_hint)

	if not (heel_hit.get("hit", false) and toe_hit.get("hit", false)):
		# One probe lost the ground: no lock, no filtering, degrade to animation.
		_height_filter.reset()
		_angle_filter.reset()
		return result

	var heel_point: Vector2 = heel_hit["point"]
	var toe_point: Vector2 = toe_hit["point"]
	var surface: Vector2 = toe_point - heel_point
	var slope: float = RigKitMath.angle_of(surface) if surface.length_squared() > RigKitMath.EPS else 0.0

	_height_filter.push((heel_point.y + toe_point.y) * 0.5)
	_angle_filter.push(slope)

	var filtered_height: float = _height_filter.value((heel_point.y + toe_point.y) * 0.5)
	var filtered_slope: float = _angle_filter.value(slope)
	var clamped_slope: float = RigKitMath.clamp_angle(filtered_slope, tilt_limit)

	result["valid"] = true
	result["height"] = filtered_height
	result["slope_raw"] = filtered_slope
	result["surface_angle"] = clamped_slope
	result["point"] = Vector2(foot_hint.x, filtered_height - ankle_height)
	return result


func reset() -> void:
	if _height_filter != null:
		_height_filter.reset()
	if _angle_filter != null:
		_angle_filter.reset()
