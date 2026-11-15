## Per-foot lock state machine.
##
## One instance per foot; the two feet never share state, so a landing on the
## right foot cannot disturb the left one. The machine is pure logic: it reads a
## context dictionary and produces a target ankle position plus a weight, it
## never touches a skeleton. That is what makes the acceptance criteria in
## docs/acceptance.md measurable in a headless run.
##
## Landing needs both signals at once, unlike naive implementations that only
## look at the animation curve:
##
## * condition A - contact at or above [member RigKitParams.land_threshold];
## * condition B - both probes found ground (valid sample).
##
## Exit is the inverse with hysteresis, plus hard degradation to FK whenever the
## ground is lost, so a missing floor can never leave the leg stuck.
class_name FootLock
extends RefCounted

var params: RigKitParams
var side: String = "L"

var state: int = RigKitTypes.FootState.FK
var weight: float = 0.0          ## Raw state machine weight, strictly monotonic while ramping.
var safety: float = 1.0          ## Safety attenuation (clamp / root motion), multiplies [member weight].
var contact: float = 0.0
var has_ground: bool = false
var ground_point: Vector2 = Vector2.ZERO
var ground_angle: float = 0.0

var anchor_world: Vector2 = Vector2.ZERO
var anchor_root_local: Vector2 = Vector2.ZERO
var target_world: Vector2 = Vector2.ZERO
var foot_angle: float = 0.0

var clamp_ratio: float = 0.0
var root_step: float = 0.0       ## Root displacement measured this frame (root motion guard).
var landing_blocked: bool = false ## Set by the double support guard: the foot must lift before it can lock again.
var degraded: bool = false
var release_reason: String = ""
var state_time: float = 0.0
var locked_time: float = 0.0
var lock_count: int = 0

var _prev_root_origin: Vector2 = Vector2.ZERO
var _has_prev_root: bool = false


func _init(state_params: RigKitParams, side_name: String = "L") -> void:
	params = state_params
	side = side_name


## Effective blend used for posing: state weight times safety attenuation.
func pose_weight() -> float:
	return clampf(weight * safety, 0.0, 1.0)


func state_name() -> String:
	return RigKitTypes.STATE_NAMES.get(state, "?")


## Advances one frame.
##
## Context keys:
## [code]
## root          Transform2D  character root transform (for ROOT_RELATIVE pinning)
## fk_pos        Vector2      animation ankle position this frame
## fk_foot_angle float        animation foot direction this frame
## contact       float        0..1 landing signal
## ground        Dictionary   GroundProbe.sample() result
## [/code]
func update(dt: float, ctx: Dictionary) -> void:
	state_time += dt
	contact = clampf(float(ctx.get("contact", contact)), 0.0, 1.0)
	var root_xf: Transform2D = ctx.get("root", Transform2D.IDENTITY)
	var fk_pos: Vector2 = ctx.get("fk_pos", target_world)
	var fk_foot_angle: float = float(ctx.get("fk_foot_angle", foot_angle))
	var ground: Dictionary = ctx.get("ground", {})

	has_ground = bool(ground.get("valid", false))
	if has_ground:
		ground_point = ground["point"]
		ground_angle = float(ground["surface_angle"])
		degraded = false

	var can_land: bool = has_ground and contact >= params.land_threshold and not landing_blocked
	var blend: float = params.locked_blend_time()

	if landing_blocked and contact < params.lift_threshold:
		landing_blocked = false

	match state:
		RigKitTypes.FootState.FK, RigKitTypes.FootState.LIFT:
			weight = 0.0
			target_world = fk_pos
			foot_angle = fk_foot_angle
			if can_land:
				_enter_pre_contact(root_xf, ground_point, fk_foot_angle)
		RigKitTypes.FootState.PRE_CONTACT:
			weight = clampf(weight + dt / blend, 0.0, 1.0)
			target_world = fk_pos.lerp(_pinned_target(root_xf, fk_pos), RigKitMath.ease_in_out(weight))
			foot_angle = TwoBoneIK.foot_angle_for_ground(fk_foot_angle, ground_angle, params.tilt_limit_rad(), weight)
			if weight >= 1.0:
				_set_state(RigKitTypes.FootState.LOCKED)
				locked_time = 0.0
				lock_count += 1
			elif not can_land:
				# Contact dropped before we finished the ramp: abort without a snap.
				_set_state(RigKitTypes.FootState.RELEASE, "aborted_landing")
		RigKitTypes.FootState.LOCKED:
			locked_time += dt
			weight = 1.0
			target_world = _pinned_target(root_xf, fk_pos)
			foot_angle = TwoBoneIK.foot_angle_for_ground(fk_foot_angle, ground_angle, params.tilt_limit_rad(), 1.0)
			if not has_ground:
				_set_state(RigKitTypes.FootState.RELEASE, "ground_lost")
				degraded = true
			elif contact < params.lift_threshold:
				_set_state(RigKitTypes.FootState.RELEASE, "contact_down")
		RigKitTypes.FootState.RELEASE:
			if can_land and weight < 1.0:				# Re-landing during the release ramp: just ramp back up.
				_set_state(RigKitTypes.FootState.PRE_CONTACT, "relock")
			else:
				weight = clampf(weight - dt / blend, 0.0, 1.0)
				target_world = _pinned_target(root_xf, fk_pos).lerp(fk_pos, RigKitMath.ease_in_out(1.0 - weight))
				foot_angle = TwoBoneIK.foot_angle_for_ground(fk_foot_angle, ground_angle, params.tilt_limit_rad(), weight)
				if weight <= 0.0:
					_set_state(RigKitTypes.FootState.LIFT)

	# Root motion guard input; the solver diagnostics arrive later from the rig,
	# so the safety attenuator is advanced in a single place (update_safety).
	root_step = (root_xf.origin - _prev_root_origin).length() if _has_prev_root else 0.0
	_prev_root_origin = root_xf.origin
	_has_prev_root = true


## Feeds the safety attenuator. Called by the rig with solver diagnostics.
##
## Two independent guards, both required by the spec:
## * clamp guard - the solver had to clamp the target, i.e. the leg would have to
##   stretch; the pose weight fades instead of snapping straight;
## * root motion guard - a WORLD locked foot whose root outruns
##   [member RigKitParams.root_step_tolerance] per frame fades as well.
func update_safety(dt: float, solved_clamp_ratio: float, root_step: float) -> void:
	clamp_ratio = solved_clamp_ratio
	var target_safety: float = 1.0
	var tolerance: float = maxf(params.clamp_tolerance, 0.0001)
	if clamp_ratio > tolerance:
		target_safety = clampf(1.0 - (clamp_ratio - tolerance) / tolerance, 0.0, 1.0)
	if root_step > 0.0 and root_step > params.root_step_tolerance:
		var excess: float = (root_step - params.root_step_tolerance) / maxf(params.root_step_tolerance, 0.0001)
		target_safety = minf(target_safety, clampf(1.0 - excess, 0.0, 1.0))
	safety = move_toward(safety, target_safety, params.safety_fade_speed * dt)


## Re-arms an airborne foot without touching the pose (used by the double support
## guard and by the global enable switch).
func force_release(reason: String = "forced") -> void:
	if state == RigKitTypes.FootState.LOCKED or state == RigKitTypes.FootState.PRE_CONTACT:
		_set_state(RigKitTypes.FootState.RELEASE, reason)
	elif state == RigKitTypes.FootState.FK or state == RigKitTypes.FootState.LIFT:
		state = RigKitTypes.FootState.RELEASE
		release_reason = reason


## Forbids a re-landing until the contact signal drops into the air phase.
## Used by the double support guard so a pinned foot cannot be re-locked instantly.
func block_landing(reason: String = "") -> void:
	landing_blocked = true
	force_release(reason)


func reset() -> void:
	state = RigKitTypes.FootState.FK
	weight = 0.0
	safety = 1.0
	anchor_world = Vector2.ZERO
	anchor_root_local = Vector2.ZERO
	target_world = Vector2.ZERO
	foot_angle = 0.0
	clamp_ratio = 0.0
	degraded = false
	landing_blocked = false
	release_reason = ""
	state_time = 0.0
	locked_time = 0.0
	lock_count = 0
	_has_prev_root = false


func describe() -> String:
	return "%s %s w=%.2f sw=%.2f contact=%.2f ground=%s clamp=%.3f" % [
		side, state_name(), weight, safety, contact, str(has_ground), clamp_ratio
	]


func _enter_pre_contact(root_xf: Transform2D, anchor: Vector2, fk_foot_angle: float) -> void:
	anchor_world = anchor
	anchor_root_local = root_xf.affine_inverse() * anchor
	weight = 0.0
	foot_angle = fk_foot_angle
	_set_state(RigKitTypes.FootState.PRE_CONTACT)


## The pinned ankle target for the current lock mode.
func _pinned_target(root_xf: Transform2D, fk_pos: Vector2) -> Vector2:
	if params.lock_mode == RigKitTypes.LockMode.ROOT_RELATIVE:
		return root_xf * anchor_root_local
	if anchor_world == Vector2.ZERO:
		return fk_pos
	return anchor_world


func _set_state(next_state: int, reason: String = "") -> void:
	if state == next_state:
		return
	state = next_state
	state_time = 0.0
	if reason != "":
		release_reason = reason
		if next_state == RigKitTypes.FootState.LOCKED:
			release_reason = ""
