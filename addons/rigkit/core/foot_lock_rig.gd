## FootLockRig: the orchestrator that owns two [FootLock] instances, two ground
## probes and two bone chains, and writes the resulting pose once per frame.
##
## Typical use, after the animation system has written the skeleton:
## [codeblock]
## var source := Node2DBoneSource.new()
## var rig := FootLockRig.new()
## rig.params = RigKitParams.new()
## rig.setup(source, {
##     "left":  {"upper": hip_l, "lower": knee_l, "foot": ankle_l},
##     "right": {"upper": hip_r, "lower": knee_r, "foot": ankle_r},
## }, character_root)
## add_child(rig)
## [/codeblock]
##
## Set [member process_priority] so this node runs *after* animation (default 0
## is fine for Skeleton2D; for AnimationPlayer driven rigs use a higher priority).
##
## The rig never reads a transform it wrote earlier in the same frame: FK is
## captured before any write, the knee position is computed analytically from the
## measured bone length, and local rotations are derived from the parent rotation
## the chain already knows. No frame lag, no dirty-transform reads.
class_name FootLockRig
extends Node2D

signal foot_locked(side: String, position: Vector2)
signal foot_released(side: String, reason: String)
## Emitted when root movement no longer matches the authored stride ("fast"/>
## "slow"). Consumers decide whether to adjust playback rate; the rig never does.
signal stride_out_of_tolerance(status: String, ratio: float)

const SIDES := ["left", "right"]

## Tunables. Replace with your own resource to keep presets editable.
@export var params: RigKitParams = RigKitParams.new()
## Master switch. Off = native behaviour, used for A/B evidence.
@export var enabled: bool = true
## Advance automatically in [method _process].
@export var auto_step: bool = true
## Character root used by ROOT_RELATIVE locking (and by the root motion guard).
@export var root_path: NodePath
## Optional editor wiring: bone paths bound automatically in [method _ready].
@export var upper_left_path: NodePath
@export var lower_left_path: NodePath
@export var foot_left_path: NodePath
@export var upper_right_path: NodePath
@export var lower_right_path: NodePath
@export var foot_right_path: NodePath
## Draw probes, anchors, IK goals and state text.
@export var debug_enabled: bool = false

## Character root transform. Driven by [member root_path] when set, assignable
## directly for tests or procedural characters.
var root_transform: Transform2D = Transform2D.IDENTITY

## Optional aim / transform constraints run before the lock captures its FK pose.
## They must only touch bones the leg chains do not own.
var constraints: Array = []
## Optional stride audit fed with the root position every frame.
var root_audit: RootMotionAudit = null

var _sides: Dictionary = {}
var _root_node: Node2D = null
var _double_support_time: float = 0.0
var _debug: RigDebugDraw = null
var _bound: bool = false
var _last_state: Dictionary = {}
var _last_audit_status: String = "ok"


## Registers an aim / transform / custom constraint, run before every lock step.
func add_constraint(constraint) -> void:
	if constraint != null and not constraints.has(constraint):
		constraints.append(constraint)


func remove_constraint(constraint) -> void:
	constraints.erase(constraint)


func clear_constraints() -> void:
	constraints.clear()


## Attaches a stride audit; it is fed with the root position on every step.
func set_root_audit(audit: RootMotionAudit) -> void:
	root_audit = audit
	_last_audit_status = "ok"


func _ready() -> void:
	add_to_group("rigkit_foot_lock")
	if not root_path.is_empty():
		_root_node = get_node_or_null(root_path) as Node2D
	if not _bound and not upper_left_path.is_empty():
		_bind_exported_paths()
	if debug_enabled:
		_ensure_debug()


## Binds a skeleton source and two chains.
##
## [param bones] must contain `left` and `right`, each with `upper`, `lower` and
## `foot` bone handles, and optionally `knee_axis` (Vector2) / `knee_sign` (float).
## [param ground_sampler] is an optional `func(pos) -> Dictionary`; when omitted a
## [PhysicsProbeSampler] is created under [param probe_host] (or this node).
func setup(source: BoneSource, bones: Dictionary, root_node: Node2D = null, ground_sampler: Callable = Callable(), probe_host: Node = null) -> bool:
	if source == null:
		push_error("FootLockRig.setup: bone source is null")
		return false
	_root_node = root_node
	_sides.clear()

	var host: Node = probe_host
	if host == null:
		host = self

	for side in SIDES:
		if not bones.has(side):
			push_error("FootLockRig.setup: missing bones for side '%s'" % side)
			return false
		var entry: Dictionary = bones[side]
		var chain: BoneChain = BoneChain.new()
		if not chain.bind(source, entry["upper"], entry["lower"], entry["foot"]):
			return false
		var axis: Vector2 = entry.get("knee_axis", Vector2(1.0, 0.0))
		var sign_value: float = float(entry.get("knee_sign", 0.0))
		chain.set_knee_axis(axis, sign_value)

		var lock: FootLock = FootLock.new(params, side.substr(0, 1).to_upper())
		var probe: GroundProbe = GroundProbe.new(params.filter_frames)
		probe.configure(params)

		var sampler: Callable = ground_sampler
		var sampler_object: PhysicsProbeSampler = null
		if not sampler.is_valid() and host.is_inside_tree():
			# Keep a strong reference: a Callable does not own the RefCounted it
			# points at, so the sampler would be freed as soon as setup() returns.
			sampler_object = PhysicsProbeSampler.new(host, params.ground_layer, params.probe_radius, params.probe_depth)
			sampler = sampler_object.sample
		probe.sampler = sampler

		_sides[side] = {
			"chain": chain,
			"lock": lock,
			"probe": probe,
			"sampler": sampler,
			"sampler_object": sampler_object,
			"contact_provider": Callable(),
			"manual_contact": -1.0,
			"contact": 0.0,
			"last_fk": {},
			"last_solution": {},
			"ground": {},
		}

	_bound = true
	if debug_enabled:
		_ensure_debug()
	return true


## Rebinds the probes after a runtime parameter change.
func refresh_probes() -> void:
	for side in SIDES:
		if not _sides.has(side):
			continue
		var probe: GroundProbe = _sides[side]["probe"]
		probe.configure(params)


func set_ground_sampler(sampler: Callable) -> void:
	for side in SIDES:
		if not _sides.has(side):
			continue
		var probe: GroundProbe = _sides[side]["probe"]
		probe.sampler = sampler
		probe.reset()
		_sides[side]["sampler"] = sampler


func set_contact_provider(side: String, provider: Callable) -> void:
	if _sides.has(side):
		_sides[side]["contact_provider"] = provider


## Manual 0..1 landing signal, for animations without a contact curve yet.
func set_contact(side: String, value: float) -> void:
	if _sides.has(side):
		_sides[side]["manual_contact"] = clampf(value, 0.0, 1.0)


func clear_manual_contact(side: String) -> void:
	if _sides.has(side):
		_sides[side]["manual_contact"] = -1.0


func set_knee_axis(side: String, axis: Vector2, forced_sign: float = 0.0) -> void:
	if _sides.has(side):
		var chain: BoneChain = _sides[side]["chain"]
		chain.set_knee_axis(axis, forced_sign)


## Master switch. Turning it off also clears every lock so the next frame is
## pure animation, exactly what the A/B comparison needs.
func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	if not enabled:
		reset_locks()


func reset_locks() -> void:
	for side in SIDES:
		if _sides.has(side):
			_sides[side]["lock"].reset()
			_sides[side]["probe"].reset()
	_double_support_time = 0.0


func is_bound() -> bool:
	return _bound


func _process(delta: float) -> void:
	if auto_step:
		step(delta)


## Advances the simulation by [param delta] and writes the pose. Safe to call
## manually (tests, custom main loops, fixed step servers).
func step(delta: float) -> void:
	if not _bound or not enabled:
		_last_state = {"enabled": false}
		return
	if delta <= 0.0:
		return

	if _root_node != null and is_instance_valid(_root_node):
		root_transform = _root_node.global_transform

	# Pass 0: attachment constraints (aim, child-of). They run first so the pose
	# captured below is the one the lock and the IK actually see.
	for constraint in constraints:
		if constraint != null and constraint.has_method("step"):
			constraint.step(delta)

	if root_audit != null:
		var audit: Dictionary = root_audit.update(delta, root_transform.origin)
		if root_audit.is_out_of_tolerance() and root_audit.status != _last_audit_status:
			stride_out_of_tolerance.emit(root_audit.status, float(audit.get("ratio", 1.0)))
		_last_audit_status = root_audit.status

	# Pass 1: capture the animation pose and sample the ground, no writes yet.
	for side in SIDES:
		var data: Dictionary = _sides[side]
		var chain: BoneChain = data["chain"]
		var fk: Dictionary = chain.read_fk()
		data["last_fk"] = fk
		var ground: Dictionary = data["probe"].sample(fk["pos"])
		data["ground"] = ground
		var provider: Callable = data["contact_provider"]
		var contact: float = 0.0
		if provider.is_valid():
			contact = clampf(float(provider.call()), 0.0, 1.0)
		elif float(data["manual_contact"]) >= 0.0:
			contact = float(data["manual_contact"])
		else:
			contact = _contact_from_clearance(fk["pos"], ground)
		data["contact"] = contact

	# Pass 2: state machines.
	for side in SIDES:
		var data: Dictionary = _sides[side]
		var lock: FootLock = data["lock"]
		var was_locked: bool = lock.state == RigKitTypes.FootState.LOCKED
		lock.update(delta, {
			"root": root_transform,
			"fk_pos": data["last_fk"]["pos"],
			"fk_foot_angle": data["last_fk"]["foot"],
			"contact": data["contact"],
			"ground": data["ground"],
		})
		if not was_locked and lock.state == RigKitTypes.FootState.LOCKED:
			foot_locked.emit(side, lock.target_world)
		elif was_locked and lock.state != RigKitTypes.FootState.LOCKED:
			foot_released.emit(side, lock.release_reason)

	# Pass 3: double support guard. Both feet pinned at once is only allowed for a
	# short overlap; after that the weaker foot is released so the rig can never
	# lock a standing pose into place.
	var left_lock: FootLock = _sides["left"]["lock"]
	var right_lock: FootLock = _sides["right"]["lock"]
	var both_pinned: bool = left_lock.pose_weight() > 0.85 and right_lock.pose_weight() > 0.85
	if both_pinned:
		_double_support_time += delta
		if _double_support_time > params.double_support_max:
			var weaker: FootLock = left_lock if left_lock.contact <= right_lock.contact else right_lock
			weaker.block_landing("double_support_guard")
			foot_released.emit(weaker.side, "double_support_guard")
			_double_support_time = 0.0
	else:
		_double_support_time = 0.0

	# Pass 4: solve and write.
	for side in SIDES:
		var data: Dictionary = _sides[side]
		var chain: BoneChain = data["chain"]
		var lock: FootLock = data["lock"]
		var weight: float = lock.pose_weight()
		var solution: Dictionary = chain.solve(lock.target_world, weight, data["last_fk"])
		data["last_solution"] = solution
		chain.apply(solution, weight, lock.foot_angle)
		lock.update_safety(delta, float(solution.get("clamp_ratio", 0.0)), lock.root_step)

	_last_state = _build_state()
	if _debug != null:
		_debug.set_state(_last_state)


## PROBE contact source: derive the landing signal from ground clearance.
##
## Feet that are exactly at their planted height report 1, feet raised by more
## than [member RigKitParams.contact_clearance] report 0.
func _contact_from_clearance(fk_pos: Vector2, ground: Dictionary) -> float:
	if not ground.get("valid", false):
		return 0.0
	var planted_y: float = ground["point"].y
	var clearance: float = planted_y - fk_pos.y
	var span: float = maxf(params.contact_clearance, 0.0001)
	return clampf(1.0 - clearance / span, 0.0, 1.0)


func _build_state() -> Dictionary:
	var state: Dictionary = {
		"enabled": enabled,
		"lock_mode": RigKitTypes.LOCK_MODE_NAMES.get(params.lock_mode, "?"),
		"double_support": _double_support_time,
		"constraints": constraints.size(),
		"audit": root_audit.snapshot() if root_audit != null else {},
	}
	for side in SIDES:
		if not _sides.has(side):
			continue
		var data: Dictionary = _sides[side]
		var lock: FootLock = data["lock"]
		var solution: Dictionary = data["last_solution"]
		state[side] = {
			"state": lock.state,
			"state_name": lock.state_name(),
			"weight": lock.weight,
			"pose_weight": lock.pose_weight(),
			"safety": lock.safety,
			"contact": lock.contact,
			"has_ground": lock.has_ground,
			"anchor": lock.anchor_world,
			"target": lock.target_world,
			"fk_pos": data["last_fk"].get("pos", Vector2.ZERO),
			"hip": data["last_fk"].get("hip", Vector2.ZERO),
			"knee": solution.get("knee", Vector2.ZERO),
			"leg_length": data["chain"].leg_length(),
			"upper_length": data["chain"].upper_length,
			"lower_length": data["chain"].lower_length,
			"clamp_ratio": lock.clamp_ratio,
			"degraded": lock.degraded,
			"reason": lock.release_reason,
			"ground": data["ground"],
		}
	return state


## Snapshot used by the gizmo, by tests and by acceptance tooling.
func get_state() -> Dictionary:
	return _last_state


func _exit_tree() -> void:
	for side in SIDES:
		if not _sides.has(side):
			continue
		var sampler_object: PhysicsProbeSampler = _sides[side].get("sampler_object")
		if sampler_object != null:
			sampler_object.free_probe()


func _ensure_debug() -> void:
	if _debug != null:
		return
	_debug = RigDebugDraw.new()
	_debug.name = "RigKitDebugDraw"
	_debug.rig = self
	add_child(_debug)


func set_debug_enabled(value: bool) -> void:
	debug_enabled = value
	if value:
		_ensure_debug()
	elif _debug != null:
		_debug.queue_free()
		_debug = null


func _bind_exported_paths() -> void:
	var source: Node2DBoneSource = Node2DBoneSource.new()
	var bones: Dictionary = {}
	var mapping: Dictionary = {
		"left": [upper_left_path, lower_left_path, foot_left_path],
		"right": [upper_right_path, lower_right_path, foot_right_path],
	}
	for side in mapping:
		var paths: Array = mapping[side]
		var entry: Dictionary = {}
		var keys: Array = ["upper", "lower", "foot"]
		for i in keys.size():
			var path: NodePath = paths[i]
			if path.is_empty():
				push_warning("FootLockRig: missing bone path for %s.%s" % [side, keys[i]])
				return
			var node: Node = get_node_or_null(path)
			if node == null:
				push_warning("FootLockRig: bone node not found at %s" % path)
				return
			entry[keys[i]] = node
		bones[side] = entry
	var root: Node2D = get_node_or_null(root_path) as Node2D
	setup(source, bones, root)
