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


func _process(_delta: float) -> void:
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
