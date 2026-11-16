## Frame driver: the one place that guarantees the pose is authorised before the
## rig reads it.
##
## Every constraint in RigKit that looks at the pose it writes (foot lock, physics,
## verlet, path) only behaves correctly when the animation system re-writes the
## skeleton at the start of the frame. Feeding the rig its own output makes
## inertia cancel itself and the secondary motion silently vanishes - a failure
## mode that is invisible in code review and obvious only in telemetry.
##
## [RigDriver] makes that ordering structural instead of a comment:
##
## [codeblock]
## var driver := RigDriver.new()
## driver.setup(rig, func(delta): animation_player.advance(delta))
## add_child(driver)                      # or call driver.advance(delta) yourself
## [/codeblock]
##
## It also owns the playback side of the contract: [member time_scale] is applied
## to the authoriser only, never to the rig's simulation delta, because the spring
## constants are stated per real second. Scale the animation, not the physics.
class_name RigDriver
extends Node

## Rig advanced after the authoriser runs.
var rig: FootLockRig = null

## Callable that writes the animated pose, i.e. `func(delta: float) -> void`.
## Optional: without it the driver still orders the call, but nothing authorises
## the pose, and constraints that read their own writes will misbehave.
var authorizer: Callable = Callable()

## Scales the delta handed to [member authorizer]. 1.0 = authored speed. Use it for
## slow motion / speed-up, and for matching an authored stride to actual movement
## (see [RootMotionAudit.suggested_rate]).
var time_scale: float = 1.0

## Playback order: 0 = authorise, then step the rig; 1 = step the rig, then authorise.
## The second order exists only so a test can prove the difference; do not ship it.
var order: int = 0

var enabled: bool = true
## Calls [method advance] from [method _process].
var auto_process: bool = true
## Number of frames advanced.
var frames: int = 0
## Gate that the last advance actually ran an authoriser.
var last_authorized: bool = false


## Binds the rig and, optionally, the pose authoriser.
func setup(rig_node: FootLockRig, pose_authorizer: Callable = Callable()) -> bool:
	if rig_node == null:
		push_error("RigDriver.setup: null rig")
		return false
	rig = rig_node
	authorizer = pose_authorizer
	frames = 0
	return true


func _process(delta: float) -> void:
	if auto_process:
		advance(delta)


## One frame: authorise the pose, then let the rig read and re-pose it.
##
## Returns telemetry instead of void so a headless test can assert the order and
## catch a misconfigured driver instead of trusting it.
func advance(delta: float) -> Dictionary:
	if not enabled or rig == null or delta <= 0.0:
		return {"advanced": false, "reason": "disabled" if rig == null else "delta"}

	var scaled_delta: float = delta * maxf(time_scale, 0.0)
	last_authorized = authorizer.is_valid()

	if order == 0:
		if last_authorized:
			authorizer.call(scaled_delta)
		rig.step(delta)
	else:
		rig.step(delta)
		if last_authorized:
			authorizer.call(scaled_delta)

	frames += 1
	return {
		"advanced": true,
		"authorized": last_authorized,
		"frames": frames,
		"time_scale": time_scale,
		"scaled_delta": scaled_delta,
	}


## Convenience: drive the animation at the rate the root motion audit suggests,
## clamped by the audit itself so a broken input cannot turn the clip into a
## windmill.
func sync_time_scale_from_audit() -> float:
	if rig == null or rig.root_audit == null:
		return time_scale
	time_scale = clampf(rig.root_audit.suggested_rate, rig.root_audit.min_rate_scale, rig.root_audit.max_rate_scale)
	return time_scale
