## Runtime tuning panel: sliders that write straight into [member FootLockRig.params],
## plus live state read-outs.
##
## The gizmo ([RigDebugDraw]) shows *where* things are; this panel shows *why* -
## state, weight, ground validity, audit status - and lets a designer tune blend
## time and clearance without restarting the game.
##
## [codeblock]
## var panel := RigDebugPanel.new()
## panel.setup(rig)
## add_child(panel)
## [/codeblock]
class_name RigDebugPanel
extends Control

var rig: FootLockRig = null

var _title: Label = null
var _state_label: Label = null
var _audit_label: Label = null
var _sliders: Dictionary = {}
var _timeline: RigTimeline = null
var _tape_slider: HSlider = null
var _tape_label: Label = null


func _ready() -> void:
	custom_minimum_size = Vector2(240.0, 200.0)
	position = Vector2(12.0, 12.0)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	_title = Label.new()
	_title.text = "RigKit"
	column.add_child(_title)

	_state_label = Label.new()
	_state_label.text = "state: -"
	column.add_child(_state_label)

	_audit_label = Label.new()
	_audit_label.text = "audit: -"
	column.add_child(_audit_label)

	if _timeline != null:
		_build_timeline_controls(column)

	if rig != null:
		_add_slider(column, "blend_time", 0.0, 0.4, 0.001)
		_add_slider(column, "contact_clearance", 0.0, 0.5, 0.01)
		_add_slider(column, "clamp_tolerance", 0.0, 0.5, 0.01)


## Binds the rig. Called before or after [method Node._ready].
func setup(rig_node: FootLockRig) -> bool:
	if rig_node == null:
		push_error("RigDebugPanel.setup: null rig")
		return false
	rig = rig_node
	if _state_label != null and _sliders.is_empty():
		_add_slider(get_parent(), "blend_time", 0.0, 0.4, 0.001)
	return true


## Pulls the current state into the labels. Cheap enough to call every frame; the
## gizmo calls it already, so this is for standalone use.
func refresh() -> void:
	if rig == null or _state_label == null:
		return
	var state: Dictionary = rig.get_state()
	var parts: Array[String] = []
	# State is keyed by side at the top level ("left" / "right"), see FootLockRig._build_state.
	for side in ["left", "right"]:
		if not state.has(side):
			continue
		var entry: Dictionary = state[side]
		parts.append("%s %s w=%.2f" % [side, String(entry.get("state_name", "?")), float(entry.get("pose_weight", 0.0))])
	_state_label.text = "state: " + (", ".join(parts) if not parts.is_empty() else "-")

	var audit: Dictionary = state.get("audit", {})
	if audit.is_empty():
		_audit_label.text = "audit: off"
	else:
		_audit_label.text = "audit: %s ratio=%.2f comp=%.2f" % [
			String(audit.get("status", "?")),
			float(audit.get("ratio", 1.0)),
			float(audit.get("compensation", 1.0)),
		]


## Binds a pose tape: adds a scrub slider plus play / pause / single-frame buttons.
##
## The tape is the thing that makes a slide debuggable - the panel scrubs it while
## the gizmo draws the target trail.
func bind_timeline(tape: RigTimeline) -> bool:
	if tape == null:
		return false
	_timeline = tape
	if _state_label != null and _tape_slider == null:
		_build_timeline_controls(_state_label.get_parent())
	return true


func _build_timeline_controls(column: Node) -> void:
	var box: VBoxContainer = column as VBoxContainer
	if box == null or _timeline == null or _tape_slider != null:
		return
	_tape_label = Label.new()
	_tape_label.text = "tape: 0 frames"
	box.add_child(_tape_label)

	_tape_slider = HSlider.new()
	_tape_slider.min_value = 0.0
	_tape_slider.max_value = 1.0
	_tape_slider.step = 0.001
	_tape_slider.custom_minimum_size = Vector2(200.0, 18.0)
	_tape_slider.value_changed.connect(func(value: float) -> void:
		_timeline.playing = false
		_timeline.seek(value + _timeline.start_time())
		_timeline.apply_at_playhead()
	)
	box.add_child(_tape_slider)

	var row := HBoxContainer.new()
	box.add_child(row)
	for entry in [["PLAY", 0], ["PAUSE", 1], ["-1f", 2], ["+1f", 3]]:
		var button := Button.new()
		button.text = String(entry[0])
		var action: int = entry[1]
		button.pressed.connect(func() -> void: _tape_action(action))
		row.add_child(button)


func _tape_action(action: int) -> void:
	if _timeline == null or _timeline.frames.is_empty():
		return
	var frame_step: float = 1.0 / 60.0
	match action:
		0:
			_timeline.playing = true
		1:
			_timeline.playing = false
		2:
			_timeline.playing = false
			_timeline.seek(_timeline.playhead - frame_step)
			_timeline.apply_at_playhead()
		3:
			_timeline.playing = false
			_timeline.seek(_timeline.playhead + frame_step)
			_timeline.apply_at_playhead()


func _process(delta: float) -> void:
	if _timeline != null and _timeline.frames.is_empty() == false:
		if _timeline.playing:
			_timeline.advance_playback(delta)
		if _tape_slider != null and not _tape_slider.has_focus():
			_tape_slider.max_value = maxf(_timeline.duration(), 0.001)
			_tape_slider.set_value_no_signal(_timeline.playhead - _timeline.start_time())
		if _tape_label != null:
			_tape_label.text = "tape: %d f  %.2f/%.2fs" % [
				_timeline.frame_count(), _timeline.playhead - _timeline.start_time(), _timeline.duration()
			]
	refresh()


func _add_slider(parent: Node, field: String, minimum: float, maximum: float, step: float) -> void:
	if parent == null or rig == null:
		return
	var column: VBoxContainer = parent as VBoxContainer
	if column == null:
		return
	var label := Label.new()
	label.text = "%s: %.3f" % [field, float(rig.params.get(field))]
	column.add_child(label)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = float(rig.params.get(field))
	slider.custom_minimum_size = Vector2(200.0, 18.0)
	slider.value_changed.connect(func(value: float) -> void:
		rig.params.set(field, value)
		label.text = "%s: %.3f" % [field, value]
	)
	column.add_child(slider)
	_sliders[field] = slider
