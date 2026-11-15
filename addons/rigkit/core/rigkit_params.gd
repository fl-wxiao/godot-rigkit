## Tunables for the foot lock rig, grouped into gait presets.
##
## Every value is in world units per second / radians, so the same resource works
## for a 0.5 m chibi and a 2 m brute as long as the skeleton is authored to scale.
class_name RigKitParams
extends Resource

@export_group("Lock")
## How a locked foot follows the character. WORLD pins the foot in world space
## (true no-slide, needs the leg to compress/extend), ROOT_RELATIVE keeps the
## captured root-local offset (good for in-place cycles whose ankle drifts).
@export var lock_mode: int = RigKitTypes.LockMode.WORLD
## Contact curve semantics: rise above [member land_threshold] to allow landing,
## fall below [member lift_threshold] to release. Hysteresis lives between them.
@export_range(0.0, 1.0, 0.01) var land_threshold: float = 0.6
@export_range(0.0, 1.0, 0.01) var lift_threshold: float = 0.35
## Weight ramp duration for PRE_CONTACT / RELEASE. Never below 0.03 s (P.3 requirement).
@export_range(0.0, 0.4, 0.001) var blend_time: float = 0.06
## Maximum time both feet may stay locked at once before the weaker foot is released.
@export_range(0.0, 0.5, 0.001) var double_support_max: float = 0.12

@export_group("Ground")
## Ankle height above the sampled ground point, in world units.
@export var ankle_height: float = 0.12
## Heel / toe probe offsets relative to the ankle, along world X.
@export var heel_offset: Vector2 = Vector2(-0.07, 0.0)
@export var toe_offset: Vector2 = Vector2(0.07, 0.0)
## How far down a probe scans for ground.
@export var probe_depth: float = 0.6
## Radius of the probe shape (a shape scan does not jitter on bumpy ground).
@export var probe_radius: float = 0.03
## Physics layer shared with line of sight / projectile blockers.
@export_flags_2d_physics var ground_layer: int = 1
## Moving average window for sampled heights and normals (3..5 keeps it stable).
@export_range(1, 8, 1) var filter_frames: int = 4
## Maximum foot tilt against the FK pose, in degrees.
@export_range(0.0, 60.0, 0.5) var tilt_limit_deg: float = 20.0
## Ground clearance above which the foot counts as fully airborne, for the PROBE
## contact source only.
@export var contact_clearance: float = 0.06

@export_group("Safety")
## Clamp ratio above which the pose weight is faded out, so a locked foot can never
## drag the leg into a fully straight, snapping pose.
@export_range(0.0, 0.5, 0.01) var clamp_tolerance: float = 0.12
## Root displacement per frame above which WORLD locking fades, as a guard for
## root-motion animations that outrun the planted foot.
@export var root_step_tolerance: float = 0.25
## Weight fade speed used by the safety fade (per second, in weight units).
@export var safety_fade_speed: float = 6.0


func _init() -> void:
	apply_preset("run")


func apply_preset(preset: String) -> void:
	match preset:
		"walk":
			# 2.2 m/s character, longer stance, softer landing.
			lock_mode = RigKitTypes.LockMode.WORLD
			land_threshold = 0.55
			lift_threshold = 0.30
			blend_time = 0.09
			double_support_max = 0.18
			tilt_limit_deg = 22.0
			ankle_height = 0.10
			heel_offset = Vector2(-0.06, 0.0)
			toe_offset = Vector2(0.06, 0.0)
			contact_clearance = 0.05
		"run":
			# 5.6 m/s character (3.5 steps/s x 1.6 m stride).
			lock_mode = RigKitTypes.LockMode.WORLD
			land_threshold = 0.60
			lift_threshold = 0.35
			blend_time = 0.06
			double_support_max = 0.10
			tilt_limit_deg = 20.0
			ankle_height = 0.12
			heel_offset = Vector2(-0.07, 0.0)
			toe_offset = Vector2(0.07, 0.0)
			contact_clearance = 0.06
		"idle":
			# Standing still: both feet planted, no air phase.
			lock_mode = RigKitTypes.LockMode.WORLD
			land_threshold = 0.2
			lift_threshold = 0.05
			blend_time = 0.12
			double_support_max = 0.6
			tilt_limit_deg = 20.0
			ankle_height = 0.12
		"sprint":
			# Faster cadence: shorter overlap, snappier blend.
			lock_mode = RigKitTypes.LockMode.WORLD
			land_threshold = 0.65
			lift_threshold = 0.40
			blend_time = 0.045
			double_support_max = 0.06
			tilt_limit_deg = 18.0
			ankle_height = 0.13
		_:
			push_warning("RigKitParams: unknown preset '%s'" % preset)


func locked_blend_time() -> float:
	return maxf(blend_time, 0.03)


func tilt_limit_rad() -> float:
	return deg_to_rad(tilt_limit_deg)
