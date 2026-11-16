## Adapter interface between the rig and an actual skeleton.
##
## The rig reads a bone's origin, direction, length and parent rotation, and
## writes direction - optionally origin, scale and shear, depending on what the
## adapter declares in [method capabilities]. Implement this class (or one of the
## bundled adapters) to drive Node2D rigs, Skeleton2D, a third party runtime, or a
## plain data structure in tests.
##
## Conventions
## * A bone's "world direction" is the angle of the bone axis in world space,
##   measured like [method @GlobalScope.atan2] on a Vector2 (y grows downwards).
## * "dir offset" is the constant between a runtime's own rotation value and the
##   bone axis: 0 for rigs authored along +X, -PI/2 for rigs authored along +Y.
##
## Capabilities
## Every adapter reports what it can actually write through [method capabilities].
## The base implementation only rotates, which is what keeps bone lengths - and
## therefore the "zero stretch" guarantee - intact for every IK solver. Scale and
## shear are opt-in: a solver that wants them must ask
## [code]source.supports(BoneSource.CAP_SCALE)[/code] and degrade honestly when the
## answer is no, rather than silently dropping the write.
##
## [codeblock]
## if source.supports(BoneSource.CAP_SHEAR):
##     source.set_shear(bone, shear)
## else:
##     telemetry["shear_unsupported"] = true
## [/codeblock]
class_name BoneSource
extends RefCounted

## The adapter can rotate a bone ([method set_world_dir]). Baselines.
const CAP_ROTATE := 1
## The adapter can move a bone origin ([method set_origin]).
const CAP_TRANSLATE := 2
## The adapter can write a bone's scale ([method set_scale]).
const CAP_SCALE := 4
## The adapter can write a bone's shear/skew ([method set_shear]).
const CAP_SHEAR := 8
## The adapter exposes local rotation, so inherit modes can be honoured.
const CAP_LOCAL_ROTATION := 16
## The adapter can be told an inherit mode (Spine's inheritRotation etc).
const CAP_INHERIT := 32


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


## Bit mask of the [code]CAP_*[/code] constants this adapter can honour.
##
## Default is rotate only: adapters that cannot do more must not claim more, or
## the solvers above will silently write into a void.
func capabilities() -> int:
	return CAP_ROTATE


## Shorthand for [code](capabilities() & cap) != 0[/code].
func supports(cap: int) -> bool:
	return (capabilities() & cap) != 0


## Local (parent space) scale of the bone. Identity when unsupported.
##
## Bone lengths in RigKit are a constant, so a solver changes the *effective*
## length by scaling the child bone - that is how Spine's IK compress/stretch
## works, and it is why this channel exists at all.
func get_scale(_bone: Variant) -> Vector2:
	return Vector2.ONE


## Writes the bone's local scale. Return false when unsupported.
func set_scale(_bone: Variant, _scale: Vector2) -> bool:
	return false


## Local shear/skew of the bone, in the runtime's own convention. Zero when
## unsupported. Godot's Node2D has no skew channel, spine-godot exposes
## shearX/shearY, so this really is a per-runtime capability.
func get_shear(_bone: Variant) -> Vector2:
	return Vector2.ZERO


## Writes the bone's local shear. Return false when unsupported.
func set_shear(_bone: Variant, _shear: Vector2) -> bool:
	return false


## Local rotation of the bone, in radians. Only meaningful when
## [constant CAP_LOCAL_ROTATION] is reported.
##
## Hopeless to derive from [method get_world_dir] alone: a bone with
## inheritRotation = false has a world angle unrelated to its parent's.
func get_local_rotation(_bone: Variant) -> float:
	return 0.0


## Writes the local rotation. Return false when unsupported.
func set_local_rotation(_bone: Variant, _radians: float) -> bool:
	return false


## Inherit mode of the bone, as a [enum RigKitTypes.Inherit] value.
##
## Defaults to NORMAL, which is what every runtime without an inherit option
## behaves like. Adapters backed by Spine can pass the real value through.
func get_inherit(_bone: Variant) -> int:
	return RigKitTypes.Inherit.NORMAL


## Sets the inherit mode. Return false when the runtime has no such option.
##
## RigKit only needs this so a solver can predict how the host will compose the
## local rotation it just wrote; it never re-implements the composition itself.
func set_inherit(_bone: Variant, _mode: int) -> bool:
	return false
