## Adapter interface between the rig and an actual skeleton.
##
## The rig only ever needs five things from a skeleton runtime: where a bone
## starts, which way it points, how long it is, how to rotate it, and the global
## rotation of its parent. Implement this class (or one of the bundled adapters)
## to drive Node2D rigs, Skeleton2D, a third party runtime, or a plain data
## structure in tests.
##
## Conventions
## * A bone's "world direction" is the angle of the bone axis in world space,
##   measured like [method @GlobalScope.atan2] on a Vector2 (y grows downwards).
## * "dir offset" is the constant between a runtime's own rotation value and the
##   bone axis: 0 for rigs authored along +X, -PI/2 for rigs authored along +Y.
## * Implementations must never move bones, only rotate them. That is what keeps
##   bone lengths - and therefore the "zero stretch" guarantee - intact.
class_name BoneSource
extends RefCounted


## World position of the bone origin (the joint).
func get_origin(_bone: Variant) -> Vector2:
	return Vector2.ZERO


## World direction angle of the bone axis.
func get_world_dir(_bone: Variant) -> float:
	return 0.0


## Constant between the runtime rotation and the bone axis, in radians.
func get_dir_offset(_bone: Variant) -> float:
	return 0.0


## Rotates the bone so its axis points at [param world_dir].
##
## [param parent_global_rotation] is the parent's global rotation the caller
## already knows, passed in so adapters never have to read a transform that may
## still be dirty inside the same frame.
func set_world_dir(_bone: Variant, _world_dir: float, _parent_global_rotation: float) -> void:
	pass


## Global rotation of the bone's parent, read before the chain is written.
func get_parent_global_rotation(_bone: Variant) -> float:
	return 0.0


## Bone length in world units, or a negative value when unknown (the chain then
## falls back to the rest distance between joint origins).
func get_length(_bone: Variant) -> float:
	return -1.0


## Moves the bone origin to [param world_pos]. Used only by attachment-style
## constraints ([TransformConstraint]); the IK solvers never call it, which is
## why "zero stretch" still holds for every chain they drive.
##
## Return false when the adapter cannot move bones (the default).
func set_origin(_bone: Variant, _world_pos: Vector2) -> bool:
	return false
