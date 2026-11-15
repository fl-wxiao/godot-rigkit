## Debug gizmo: probes, hits, lock anchors, IK goals, leg length and state.
##
## Drawn in world space on purpose - for a "is the foot sliding?" check you want
## to see the anchor stay put on the ground under the character, so screen space
## would defeat the purpose. Add a CanvasLayer variant if you need a fixed HUD.
class_name RigDebugDraw
extends Node2D

var rig: FootLockRig = null

var anchor_color: Color = Color(0.2, 1.0, 0.55, 1.0)
var target_color: Color = Color(1.0, 0.75, 0.2, 1.0)
var probe_color: Color = Color(0.35, 0.7, 1.0, 0.55)
var hit_color: Color = Color(0.35, 0.7, 1.0, 1.0)
var leg_color: Color = Color(0.85, 0.85, 0.9, 0.8)
var text_color: Color = Color(1.0, 1.0, 1.0, 0.9)

var _state: Dictionary = {}


func _ready() -> void:
	z_index = 100
	z_as_relative = false


func set_state(state: Dictionary) -> void:
	_state = state
	queue_redraw()


func _process(_delta: float) -> void:
	if _state.is_empty() and rig != null:
		_state = rig.get_state()
	queue_redraw()


func _draw() -> void:
	if _state.is_empty() or not _state.get("enabled", false):
		return
	var font: Font = ThemeDB.fallback_font
	var line_y: float = 0.0
	var origin: Vector2 = _origin_hint()

	for side in ["left", "right"]:
		if not _state.has(side):
			continue
		var s: Dictionary = _state[side]
		var fk_pos: Vector2 = s.get("fk_pos", Vector2.ZERO)
		var hip: Vector2 = s.get("hip", Vector2.ZERO)
		var knee: Vector2 = s.get("knee", Vector2.ZERO)
		var target: Vector2 = s.get("target", Vector2.ZERO)
		var anchor: Vector2 = s.get("anchor", Vector2.ZERO)

		# Leg skeleton, drawn from the solved joints.
		draw_line(hip, knee, leg_color, 2.0)
		draw_line(knee, target, leg_color, 2.0)

		# FK ankle (where the animation wants the foot) vs the IK goal.
		draw_circle(fk_pos, 3.0, Color(0.8, 0.4, 0.9, 0.9))
		draw_circle(target, 4.0, target_color)

		# Probes: two vertical scans around the FK ankle.
		var ground: Dictionary = s.get("ground", {})
		if ground.has("heel"):
			draw_line(fk_pos + Vector2(-0.07, 0.0), ground.get("heel", fk_pos), probe_color, 1.0)
			draw_line(fk_pos + Vector2(0.07, 0.0), ground.get("toe", fk_pos), probe_color, 1.0)
			draw_circle(ground.get("heel", fk_pos), 2.0, hit_color)
			draw_circle(ground.get("toe", fk_pos), 2.0, hit_color)

		# Lock anchor: it must not move while LOCKED in WORLD mode.
		if s.get("state_name", "") == "LOCKED":
			draw_arc(anchor, 6.0, 0.0, TAU, 16, anchor_color, 1.5)
			draw_line(anchor + Vector2(-8, 0), anchor + Vector2(8, 0), anchor_color, 1.0)
			draw_line(anchor + Vector2(0, -8), anchor + Vector2(0, 8), anchor_color, 1.0)

		# State text.
		var label: String = "%s %s w=%.2f c=%.2f clamp=%.2f%s" % [
			side,
			s.get("state_name", "?"),
			float(s.get("pose_weight", 0.0)),
			float(s.get("contact", 0.0)),
			float(s.get("clamp_ratio", 0.0)),
			" DEGRADED" if s.get("degraded", false) else "",
		]
		draw_string(font, origin + Vector2(0.0, line_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, text_color)
		line_y += 13.0

	var header: String = "RigKit  mode=%s  double_support=%.2fs" % [
		_state.get("lock_mode", "?"),
		float(_state.get("double_support", 0.0)),
	]
	draw_string(font, origin + Vector2(0.0, line_y), header, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, text_color)


func _origin_hint() -> Vector2:
	if rig != null and rig.is_bound():
		var left: Dictionary = _state.get("left", {})
		if left.has("hip"):
			return left["hip"] + Vector2(-120.0, -40.0)
	return Vector2(-120.0, -40.0)
