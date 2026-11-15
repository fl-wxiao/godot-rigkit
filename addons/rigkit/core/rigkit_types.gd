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
