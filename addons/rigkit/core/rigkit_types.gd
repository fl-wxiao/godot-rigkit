## Shared enums and constants for RigKit.
##
## RigKit is an engine-level runtime rig helper: it never edits animation data and
#  never touches an editor, it only re-poses bones after the animation system has
#  written them. Everything here is engine agnostic, so the same code drives
#  Node2D hierarchies, Skeleton2D rigs and third-party skeleton runtimes through
#  a BoneSource adapter (see core/bone_source.gd).
class_name RigKitTypes
extends RefCounted

## Per-foot state of the lock state machine.
##
## FK ---------> LIFT ---------> PRE_CONTACT ---------> LOCKED
## ^              ^                   |                    |
## |              +---- RELEASE <-----+--------------------+
##
enum FootState {
	FK,           ## IK off, the foot follows the animation verbatim.
	LIFT,         ## Foot is airborne, waiting for a landing sample.
	PRE_CONTACT,  ## Weight ramps 0 -> 1 while the target slides onto the ground point.
	LOCKED,       ## Foot is pinned, target follows root (or world) depending on LockMode.
	RELEASE,      ## Weight ramps 1 -> 0 and the foot returns to the animation.
}

## How the pinned foot follows the character.
enum LockMode {
	WORLD,          ## Target is frozen in world space: the foot does not slide at all.
	ROOT_RELATIVE,  ## Target = root transform * captured root-local offset.
}

## Where the landing signal comes from.
enum ContactSource {
	CURVE,  ## Explicit 0..1 contact curve (animation curve, callback, manual set).
	PROBE,  ## Derived from ground clearance when no curve exists.
}

## How a bone composes its parent's transform, mirroring Spine 4.x
## [code]Inherit[/code]. Godot's Node2D always behaves like [constant NORMAL].
##
## RigKit reads world transforms and writes world directions, so these modes
## matter in one place: predicting which local rotation to write when the host
## will not compose the parent rotation the way NORMAL assumes.
enum Inherit {
	NORMAL,                       ## Full 2D parent transform.
	ONLY_TRANSLATION,             ## Parent position only; rotation and scale ignored.
	NO_ROTATION_OR_REFLECTION,    ## Parent rotation ignored, reflection kept.
	NO_SCALE,                     ## Parent scale ignored, rotation kept.
	NO_SCALE_OR_REFLECTION,       ## No scale and no reflection.
}

const INHERIT_NAMES := {
	Inherit.NORMAL: "normal",
	Inherit.ONLY_TRANSLATION: "onlyTranslation",
	Inherit.NO_ROTATION_OR_REFLECTION: "noRotationOrReflection",
	Inherit.NO_SCALE: "noScale",
	Inherit.NO_SCALE_OR_REFLECTION: "noScaleOrReflection",
}

## Human readable state names, used by the debug gizmo and by tests.
const STATE_NAMES := {
	FootState.FK: "FK",
	FootState.LIFT: "LIFT",
	FootState.PRE_CONTACT: "PRE_CONTACT",
	FootState.LOCKED: "LOCKED",
	FootState.RELEASE: "RELEASE",
}

const LOCK_MODE_NAMES := {
	LockMode.WORLD: "WORLD",
	LockMode.ROOT_RELATIVE: "ROOT_RELATIVE",
}
