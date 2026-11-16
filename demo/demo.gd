## Interactive demo: a stick figure walking over flat ground and a 15 degree
## ramp, with the foot lock visible in the debug gizmo.
##
## Keys:
##   SPACE    toggle the rig (A/B against the raw animation)
##   C        switch the landing signal: gait curve <-> probe only
##   1 2 3    walk / run / sprint preset
##   D        toggle the gizmo
##
## Everything is procedural: no skeleton assets, no third party runtime. The same
## rig drives a Skeleton2D rig, a spine style runtime or your own bone source.
extends Node2D

const SPEED: float = 1.6
const STANCE: float = 0.25
const SWING: float = 0.15
const RAMP_START: float = 4.0
const RAMP_END: float = 7.0
const RAMP_DEG: float = 15.0
const ANKLE_HEIGHT: float = 0.10
const LOOP_MIN: float = 0.0
const LOOP_MAX: float = 9.6

var _walker: Node2D = null
var _hips: Dictionary = {}
var _legs: Dictionary = {}
var _rig: FootLockRig = null
var _source: Node2DBoneSource = null
var _gait: Dictionary = {}
var _root_x: float = 0.2
var _use_probe_contact: bool = false
var _hud: Label = null
var _debug: RigDebugDraw = null
var _camera: Camera2D = null
var _preset: String = "walk"
var _wand: Node2D = null
var _arm: Dictionary = {}
var _arm_aim: TwoBoneAim = null
var _wand_follow: TransformConstraint = null
var _cape: Node2D = null
var _cape_physics: PhysicsConstraint = null
var _aim_enabled: bool = true
var _audit: RootMotionAudit = null
## `-- --stats` prints lock telemetry once a second; used by headless CI runs.
var _stats: bool = false
var _frames: int = 0


func _ready() -> void:
	_stats = "--stats" in OS.get_cmdline_user_args()
	_build_terrain()
	_build_walker()
	_build_rig()
	_build_hud()
	_gait = _new_gait(_root_x)


func _process(delta: float) -> void:
	if _rig == null:
		return
	_root_x += SPEED * delta
	if _root_x > LOOP_MAX:
		_root_x = LOOP_MIN
		_gait = _new_gait(_root_x + 0.2)
		_rig.reset_locks()
		if _audit != null:
			# The demo teleports the root back to the start of the loop; that is a
			# level reset, not a stride mismatch, so the audit starts fresh too.
			_audit.reset()

	_advance_gait(delta)
	_walker.position = Vector2(_root_x, ground_height(_root_x))
	_apply_fk_pose(delta)

	if _use_probe_contact:
		_rig.clear_manual_contact("left")
		_rig.clear_manual_contact("right")
	else:
		_rig.set_contact("left", float(_gait["contact"]))
		_rig.set_contact("right", 0.0)

	if _arm_aim != null and _aim_enabled:
		if DisplayServer.get_name() == "headless":
			var t: float = float(_frames) / 60.0
			_arm_aim.set_target_point(Vector2(_root_x + 0.42 + cos(t * 1.6) * 0.18, -0.50 + sin(t * 1.6) * 0.16))
		else:
			_arm_aim.set_target_point(get_global_mouse_position())

	_rig.step(delta)
	_update_hud()
	_frames += 1
	if _stats and _frames % 60 == 0:
		_print_stats()
	if _camera != null:
		_camera.position = _walker.position + Vector2(0.0, -0.42)



# ------------------------------------------------------------------ scene

func _build_terrain() -> void:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var points: PackedVector2Array = PackedVector2Array()
	var samples: int = 64
	for i in samples + 1:
		var x: float = -1.0 + 13.0 * float(i) / float(samples)
		points.append(Vector2(x, ground_height(x)))
	points.append(Vector2(12.0, 3.0))
	points.append(Vector2(-1.0, 3.0))

	var shape: CollisionShape2D = CollisionShape2D.new()
	var segments: PackedVector2Array = PackedVector2Array()
	for i in samples:
		var x0: float = -1.0 + 13.0 * float(i) / float(samples)
		var x1: float = -1.0 + 13.0 * float(i + 1) / float(samples)
		segments.append(Vector2(x0, ground_height(x0)))
		segments.append(Vector2(x1, ground_height(x1)))
	var concave: ConcavePolygonShape2D = ConcavePolygonShape2D.new()
	concave.segments = segments
	shape.shape = concave
	body.add_child(shape)

	var fill: Polygon2D = Polygon2D.new()
	fill.polygon = points
	fill.color = Color(0.16, 0.18, 0.22)
	fill.z_index = -1
	fill.z_as_relative = false
	body.add_child(fill)

	var line: PackedVector2Array = PackedVector2Array()
	for i in samples + 1:
		var x: float = -1.0 + 13.0 * float(i) / float(samples)
		line.append(Vector2(x, ground_height(x)))
	var edge: Line2D = Line2D.new()
	edge.points = line
	edge.width = 2.0
	edge.default_color = Color(0.45, 0.55, 0.7)
	body.add_child(edge)


func _build_walker() -> void:
	_walker = Node2D.new()
	_walker.name = "Walker"
	add_child(_walker)

	for side in ["left", "right"]:
		var hip: Node2D = Node2D.new()
		hip.name = "Hip%s" % side.capitalize()
		hip.position = Vector2(-0.07 if side == "left" else 0.07, -0.32)
		_walker.add_child(hip)
		_hips[side] = hip

		var thigh: Node2D = Node2D.new()
		thigh.name = "Thigh"
		hip.add_child(thigh)
		_add_limb(thigh, 0.32, 0.045, Color(0.75, 0.45, 0.35))

		var shin: Node2D = Node2D.new()
		shin.name = "Shin"
		shin.position = Vector2(0.32, 0.0)
		thigh.add_child(shin)
		_add_limb(shin, 0.30, 0.038, Color(0.65, 0.38, 0.30))

		var foot: Node2D = Node2D.new()
		foot.name = "Foot"
		foot.position = Vector2(0.30, 0.0)
		shin.add_child(foot)
		var foot_poly: Polygon2D = Polygon2D.new()
		foot_poly.polygon = PackedVector2Array([
			Vector2(-0.01, -0.03), Vector2(0.10, -0.03),
			Vector2(0.10, 0.02), Vector2(-0.01, 0.02),
		])
		foot_poly.color = Color(0.35, 0.3, 0.28)
		foot.add_child(foot_poly)

		_legs[side] = {"upper": thigh, "lower": shin, "foot": foot}

	# Cape: one bone plus a physics constraint. Its animation pose is authored
	# straight down; gravity and the walk's inertia decide where it actually hangs.
	var cape_bone: Node2D = Node2D.new()
	cape_bone.name = "Cape"
	cape_bone.position = Vector2(-0.06, -0.60)
	_walker.add_child(cape_bone)
	_add_limb(cape_bone, 0.30, 0.070, Color(0.34, 0.28, 0.42))
	_cape = cape_bone

	var body: Polygon2D = Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-0.11, -0.62), Vector2(0.11, -0.62),
		Vector2(0.09, -0.28), Vector2(-0.09, -0.28),
	])
	body.color = Color(0.55, 0.62, 0.78)
	_walker.add_child(body)

	# A wand bone on top of the body, aimed by an AimConstraint (P1 showcase).
	var wand: Node2D = Node2D.new()
	wand.name = "Wand"
	wand.position = Vector2(0.0, -0.5)
	_walker.add_child(wand)
	var stick: Polygon2D = Polygon2D.new()
	stick.polygon = PackedVector2Array([
		Vector2(0.0, -0.02), Vector2(0.34, -0.012),
		Vector2(0.34, 0.012), Vector2(0.0, 0.02),
	])
	stick.color = Color(0.85, 0.78, 0.55)
	wand.add_child(stick)
	var tip: Node2D = Node2D.new()
	tip.name = "Tip"
	tip.position = Vector2(0.34, 0.0)
	wand.add_child(tip)
	_wand = wand

	# A real two bone arm: shoulder -> elbow -> hand. The wand is not parented to
	# the hand on purpose: a TransformConstraint makes it follow the solved hand,
	# which is what proves the constraint ordering.
	var shoulder: Node2D = Node2D.new()
	shoulder.name = "Shoulder"
	shoulder.position = Vector2(0.0, -0.52)
	_walker.add_child(shoulder)
	var upper_arm: Node2D = Node2D.new()
	upper_arm.name = "UpperArm"
	shoulder.add_child(upper_arm)
	_add_limb(upper_arm, 0.22, 0.034, Color(0.58, 0.66, 0.80))
	var fore_arm: Node2D = Node2D.new()
	fore_arm.name = "ForeArm"
	fore_arm.position = Vector2(0.22, 0.0)
	upper_arm.add_child(fore_arm)
	_add_limb(fore_arm, 0.22, 0.028, Color(0.52, 0.60, 0.74))
	var hand: Node2D = Node2D.new()
	hand.name = "Hand"
	hand.position = Vector2(0.22, 0.0)
	fore_arm.add_child(hand)
	_arm = {"upper": upper_arm, "lower": fore_arm, "hand": hand}


func _add_limb(parent: Node2D, length: float, width: float, color: Color) -> void:
	var poly: Polygon2D = Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(0.0, -width), Vector2(length, -width * 0.6),
		Vector2(length, width * 0.6), Vector2(0.0, width),
	])
	poly.color = color
	parent.add_child(poly)


func _build_rig() -> void:
	_source = Node2DBoneSource.new()
	_rig = FootLockRig.new()
	_rig.name = "FootLockRig"
	_rig.params = RigKitParams.new()
	_rig.params.apply_preset("walk")
	_rig.root_path = NodePath()
	_rig.debug_enabled = true
	# The demo drives the rig explicitly from _process, so it must not also step
	# itself (that would advance the state machine twice per frame).
	_rig.auto_step = false
	add_child(_rig)
	var bones: Dictionary = {}
	for side in ["left", "right"]:
		bones[side] = {
			"upper": _legs[side]["upper"],
			"lower": _legs[side]["lower"],
			"foot": _legs[side]["foot"],
			"knee_axis": Vector2(0.35, 1.0),
		}
	_rig.setup(_source, bones, _walker)

	_arm_aim = TwoBoneAim.new()
	_arm_aim.bind(_source, _arm["upper"], _arm["lower"], _arm["hand"])
	_arm_aim.max_speed_deg = 480.0
	_arm_aim.smooth_time = 0.06
	_rig.add_constraint(_arm_aim)

	# Registered after the aim: it reads the hand this frame already solved.
	_wand_follow = TransformConstraint.new()
	_wand_follow.bind(_source, _wand)
	_wand_follow.target_node = _arm["hand"]
	_wand_follow.follow_position = true
	_wand_follow.position_offset = Vector2(-0.10, 0.0)
	_wand_follow.smooth_time = 0.03
	_rig.add_constraint(_wand_follow)

	_cape_physics = PhysicsConstraint.new()
	_cape_physics.bind(_source, _cape)
	# Tuned so the offset stays a few centimetres: a cape root that trails half a
	# metre would visibly detach from the shoulders.
	_cape_physics.inertia = 0.12
	_cape_physics.strength = 6.0
	_cape_physics.damping = 2.0
	_cape_physics.gravity = 0.25
	_cape_physics.limit = 1.2
	_rig.add_constraint(_cape_physics)

	_audit = RootMotionAudit.new()
	_audit.set_expected_from_stride(SPEED * (STANCE + SWING), 1.0 / (STANCE + SWING))
	_audit.tolerance_ratio = 0.2
	_rig.set_root_audit(_audit)


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16.0, 12.0)
	_hud.add_theme_font_size_override("font_size", 13)
	layer.add_child(_hud)

	var camera: Camera2D = Camera2D.new()
	camera.zoom = Vector2(420.0, 420.0)
	camera.position = Vector2(0.2, -0.45)
	camera.name = "Camera"
	add_child(camera)
	_camera = camera


# ------------------------------------------------------------------ motion

func _new_gait(start_x: float) -> Dictionary:
	return {
		"planted": true,
		"timer": 0.0,
		"plant_x": start_x,
		"from_x": start_x,
		"to_x": start_x,
		"ankle": Vector2(start_x, ground_height(start_x) - ANKLE_HEIGHT),
		"contact": 1.0,
	}


func _advance_gait(delta: float) -> void:
	_gait["timer"] = float(_gait["timer"]) + delta
	var stride: float = SPEED * (STANCE + SWING)
	if bool(_gait["planted"]):
		if float(_gait["timer"]) >= STANCE:
			_gait["planted"] = false
			_gait["timer"] = 0.0
			_gait["from_x"] = _gait["plant_x"]
			_gait["to_x"] = float(_gait["plant_x"]) + stride
			_gait["contact"] = 0.0
		else:
			_gait["ankle"] = Vector2(_gait["plant_x"], ground_height(float(_gait["plant_x"])) - ANKLE_HEIGHT)
			_gait["contact"] = 1.0
	else:
		var t: float = clampf(float(_gait["timer"]) / SWING, 0.0, 1.0)
		var x: float = lerpf(float(_gait["from_x"]), float(_gait["to_x"]), t)
		_gait["ankle"] = Vector2(x, ground_height(x) - ANKLE_HEIGHT - sin(PI * t) * 0.22)
		_gait["contact"] = 0.0
		if float(_gait["timer"]) >= SWING:
			_gait["planted"] = true
			_gait["timer"] = 0.0
			_gait["plant_x"] = _gait["to_x"]
			_gait["contact"] = 1.0


## Writes the animation pose for this frame; the rig only re-poses afterwards.
func _apply_fk_pose(_delta: float) -> void:
	for side in ["left", "right"]:
		var hip: Node2D = _hips[side]
		var hip_world: Vector2 = hip.global_position
		var ankle: Vector2
		if side == "left":
			ankle = _gait["ankle"]
		else:
			# Right leg trails half a cycle: it rests behind the body.
			var trail: float = float(_gait["plant_x"]) - 0.28
			ankle = Vector2(trail, ground_height(trail) - ANKLE_HEIGHT - 0.02)
		_place_leg(side, hip_world, ankle)

	# The cape's animation pose is authored too: straight down at its rest offset.
	# Physics can only lag a pose it is told about each frame, never its own output.
	if _cape != null:
		_source.set_origin(_cape, _walker.global_position + Vector2(-0.06, -0.60))
		_source.set_world_dir(_cape, PI * 0.5, 0.0)


func _place_leg(side: String, hip: Vector2, ankle: Vector2) -> void:
	var chain: BoneChain = _rig._sides[side]["chain"]
	var to_ankle: Vector2 = ankle - hip
	var distance: float = clampf(to_ankle.length(), 0.001, chain.leg_length() - 0.001)
	var base: float = RigKitMath.angle_of(to_ankle)
	var cos_alpha: float = (chain.upper_length * chain.upper_length + distance * distance - chain.lower_length * chain.lower_length) / (2.0 * chain.upper_length * distance)
	var alpha: float = acos(clampf(cos_alpha, -1.0, 1.0))
	var knee_dir: float = base + alpha
	var knee: Vector2 = hip + RigKitMath.dir(knee_dir) * chain.upper_length
	var shin_dir: float = RigKitMath.angle_of(ankle - knee)

	_source.set_world_dir(_legs[side]["upper"], knee_dir, 0.0)
	_source.set_world_dir(_legs[side]["lower"], shin_dir, knee_dir)
	_source.set_world_dir(_legs[side]["foot"], deg_to_rad(-6.0), shin_dir)


func _update_hud() -> void:
	var state: Dictionary = _rig.get_state()
	var left: Dictionary = state.get("left", {})
	var right: Dictionary = state.get("right", {})
	var text: String = "RigKit foot lock demo\n"
	text += "rig: %s   contact: %s   preset: %s\n" % [
		"ON" if bool(state.get("enabled", false)) else "OFF (native A/B)",
		"probe only" if _use_probe_contact else "gait curve",
		_preset,
	]
	text += "L %s w=%.2f   R %s w=%.2f\n" % [
		left.get("state_name", "-"), float(left.get("pose_weight", 0.0)),
		right.get("state_name", "-"), float(right.get("pose_weight", 0.0)),
	]
	text += "cape: dx=%+.3f dy=%+.3f   aim: %s (%.0f deg)\n" % [
		_cape_physics.get_offset().x if _cape_physics != null else 0.0,
		_cape_physics.get_offset().y if _cape_physics != null else 0.0,
		"ON" if _aim_enabled else "OFF",
		rad_to_deg(_source.get_world_dir(_wand)),
	]
	text += "stride: %s\n" % [(_audit.status if _audit != null else "-")]
	text += "SPACE rig   C contact   A aim   1/2/3 presets   D gizmo"
	_hud.text = text


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_SPACE:
			_rig.set_enabled(not _rig.enabled)
		KEY_C:
			_use_probe_contact = not _use_probe_contact
		KEY_A:
			_aim_enabled = not _aim_enabled
			if _arm_aim != null:
				_arm_aim.enabled = _aim_enabled
			if _wand_follow != null:
				_wand_follow.enabled = _aim_enabled
		KEY_D:
			_rig.set_debug_enabled(not _rig.debug_enabled)
		KEY_1:
			_preset = "walk"
			_rig.params.apply_preset(_preset)
			_rig.refresh_probes()
		KEY_2:
			_preset = "run"
			_rig.params.apply_preset(_preset)
			_rig.refresh_probes()
		KEY_3:
			_preset = "sprint"
			_rig.params.apply_preset(_preset)
			_rig.refresh_probes()


# ------------------------------------------------------------------ ground

## Analytic ground profile shared by the collision mesh and the animation, so the
## visual ground and the probe hits cannot drift apart.
func ground_height(x: float) -> float:
	if x <= RAMP_START:
		return 0.0
	if x >= RAMP_END:
		return (RAMP_END - RAMP_START) * tan(deg_to_rad(RAMP_DEG))
	return (x - RAMP_START) * tan(deg_to_rad(RAMP_DEG))


func _print_stats() -> void:
	var state: Dictionary = _rig.get_state()
	var left: Dictionary = state.get("left", {})
	var right: Dictionary = state.get("right", {})
	print("t=%.2fs gait=%s ct=%.2f  L %s w=%.2f c=%.2f clamp=%.3f gnd=%s | R %s w=%.2f" % [
		float(_frames) / 60.0, "plant" if bool(_gait["planted"]) else "swing", float(_gait["contact"]),
		left.get("state_name", "-"), float(left.get("pose_weight", 0.0)),
		float(left.get("contact", 0.0)), float(left.get("clamp_ratio", 0.0)),
		str(left.get("has_ground", false)),
		right.get("state_name", "-"), float(right.get("pose_weight", 0.0)),
	])
	print("   cape=(%+.3f,%+.3f)  aim=%.0f deg  stride=%s (%.2f / %.2f)" % [
		_cape_physics.get_offset().x if _cape_physics != null else 0.0,
		_cape_physics.get_offset().y if _cape_physics != null else 0.0,
		rad_to_deg(_source.get_world_dir(_wand)) if _wand != null else 0.0,
		_audit.status if _audit != null else "-",
		_audit.speed if _audit != null else 0.0,
		_audit.expected_speed if _audit != null else 0.0,
	])

