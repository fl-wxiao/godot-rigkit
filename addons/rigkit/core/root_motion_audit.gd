## Root motion audit: compare how far the character actually travels against the
## distance the animation was authored for.
##
## This is the guard the design notes ask for: when a root-motion clip plays at a
## speed that no longer matches the character's movement, fix the *playback rate*
## (or the clip), do not drag the planted foot to hide it. The audit therefore
## only measures and suggests by default. Set [member compensation_enabled] to also
## get a live [member compensation] factor: when the stride and the movement
## disagree beyond tolerance, the foot lock's IK weight is scaled down so the foot
## is allowed to slide a controlled amount instead of asking the leg to stretch.
## That is the closed loop the design notes call for, and it is opt-in so the audit
## never silently changes a pose on its own.
##
## [codeblock]
## var audit := RootMotionAudit.new()
## audit.set_expected_from_stride(1.6, 3.5)      # 1.6 m per step, 3.5 steps/s
## audit.update(delta, character.global_position)  # -> {status, suggested_rate, ...}
## [/codeblock]
class_name RootMotionAudit
extends RefCounted

## Speed the animation was authored for, in world units per second.
var expected_speed: float = 2.2
## Allowed deviation before the audit reports a mismatch (0.15 = +-15%).
var tolerance_ratio: float = 0.15
## Clamp for the suggested playback rate, so a broken input cannot speed up a
## clip by 10x and turn the rig into a windmill.
var min_rate_scale: float = 0.6
var max_rate_scale: float = 1.6

## Last measured speed (smoothed), world units per second.
var speed: float = 0.0
## Measured / expected.
var ratio: float = 1.0
## "ok" | "fast" | "slow" | "stalled"
var status: String = "ok"
## Playback rate that would match the animation to the movement.
var suggested_rate: float = 1.0

## Enables the closed loop: [member compensation] follows the mismatch instead of
## staying at 1.0.
var compensation_enabled: bool = false
## Lowest IK weight scale the loop will ask for. 0.2 keeps a little lock so the
## foot still lands, instead of turning into pure FK.
var compensation_floor: float = 0.2
## How fast the scale may change, in units per second. 0 = immediate (snappy,
## good for tests); a real game wants 2-4 so the release is not a visible pop.
var compensation_rate: float = 0.0
## Current weight scale produced by the loop: 1.0 = trust IK, lower = let it slide.
var compensation: float = 1.0

var _previous: Vector2 = Vector2.ZERO
var _has_previous: bool = false
var _average: RigKitMath.MovingAverage


func _init(window: int = 24) -> void:
	_average = RigKitMath.MovingAverage.new(maxi(1, window))


func set_expected_from_stride(stride: float, steps_per_second: float) -> void:
	expected_speed = maxf(stride, 0.0) * maxf(steps_per_second, 0.0)


func reset() -> void:
	_has_previous = false
	speed = 0.0
	ratio = 1.0
	status = "ok"
	suggested_rate = 1.0
	compensation = 1.0
	_average.reset()


## Feeds one frame of root movement. Returns the same data [member status] etc.
## expose, so it can be dropped into telemetry in one line.
func update(delta: float, root_position: Vector2) -> Dictionary:
	if delta <= 0.0:
		return snapshot()
	if not _has_previous:
		_previous = root_position
		_has_previous = true
		return snapshot()

	var distance: float = (root_position - _previous).length()
	_previous = root_position
	_average.push(distance / delta)
	speed = _average.value(speed)

	if expected_speed <= RigKitMath.EPS:
		ratio = 1.0
		status = "ok"
		suggested_rate = 1.0
		return snapshot()

	ratio = speed / expected_speed
	suggested_rate = clampf(ratio, min_rate_scale, max_rate_scale)

	if speed <= expected_speed * 0.05:
		status = "stalled"
	elif ratio > 1.0 + tolerance_ratio:
		status = "fast"
	elif ratio < 1.0 - tolerance_ratio:
		status = "slow"
	else:
		status = "ok"

	_update_compensation(delta)
	return snapshot()


## Ramps [member compensation] towards the mismatch, at most
## [member compensation_rate] units per second.
##
## The mismatch is measured *beyond* tolerance: a 5% deviation with a 15% tolerance
## is still trusted, because the IK is the thing keeping the foot planted.
func _update_compensation(delta: float) -> void:
	if not compensation_enabled:
		compensation = 1.0
		return
	var excess: float = clampf(absf(ratio - 1.0) - tolerance_ratio, 0.0, 1.0)
	# A 100% overshoot removes the whole weight down to the floor.
	var target: float = maxf(compensation_floor, 1.0 - excess)
	if compensation_rate <= 0.0:
		compensation = target
		return
	var step: float = compensation_rate * delta
	compensation = clampf(compensation + signf(target - compensation) * minf(step, absf(target - compensation)), compensation_floor, 1.0)


func is_out_of_tolerance() -> bool:
	return status == "fast" or status == "slow"


func snapshot() -> Dictionary:
	return {
		"speed": speed,
		"expected": expected_speed,
		"ratio": ratio,
		"status": status,
		"suggested_rate": suggested_rate,
		"compensation": compensation,
	}
