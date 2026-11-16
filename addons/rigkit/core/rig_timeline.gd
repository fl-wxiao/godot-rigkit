## Pose tape: records what the rig actually wrote, and hands it back on demand.
##
## This is the answer to "why did the foot slide on frame 214?". RigKit does not
## own animation sampling - that is the animation player's job - so a timeline here
## cannot scrub a clip. What it can do is far more useful for debugging: capture
## every frame's bone channels, then replay that tape onto the skeleton, pause,
## step one frame, or scrub to any time. Because the tape is the rig's own output,
## replaying it reproduces the bug exactly, including the physics and the blends.
##
## [codeblock]
## var tape := RigTimeline.new()
## tape.setup(source, bones, 600)          # 600 frames ring buffer
## driver.timeline = tape                   # records after each step
## tape.seek(3.55)
## tape.apply_at_playhead()                 # skeleton now shows that frame
## [/codeblock]
##
## Channels that the adapter cannot write are not recorded as if they existed: a
## replay on a rotation-only adapter restores rotation only, and says so through
## [member last_apply] rather than silently pretending the pose is complete.
class_name RigTimeline
extends RefCounted

var source: BoneSource = null
var bones: Array = []
## Ring buffer size in frames. Old frames are dropped first-in-first-out.
var capacity: int = 600
## Recorded frames, oldest first, each `{ "time": float, "poses": Array, "extra": Dictionary }`.
var frames: Array[Dictionary] = []
## Tape head: time of the next recorded frame.
var time: float = 0.0
## Where [method apply_at_playhead] reads from.
var playhead: float = 0.0
var playing: bool = false
var play_rate: float = 1.0
## Restart from the oldest retained frame when playback reaches the end.
var loop: bool = true
## Called once per [method record] to attach small debug data (targets, state names).
var extra_provider: Callable = Callable()

## Summary of the last [method apply_sample]: which channels were written and which
## were skipped because the adapter cannot write them.
var last_apply: Dictionary = {}


## Binds the adapter and the bone list the tape should capture.
func setup(bone_source: BoneSource, bone_list: Array, buffer_frames: int = 600) -> bool:
	if bone_source == null:
		push_error("RigTimeline.setup: null source")
		return false
	if bone_list.is_empty():
		push_error("RigTimeline.setup: no bones to record")
		return false
	source = bone_source
	bones = bone_list.duplicate()
	capacity = maxi(buffer_frames, 2)
	clear()
	return true


func clear() -> void:
	frames.clear()
	time = 0.0
	playhead = 0.0
	playing = false
	last_apply = {}


## Appends one frame at [member time] and advances the tape head.
##
## Called by [RigDriver] right after the rig stepped, so the tape holds the solved
## pose rather than the animated one.
func record(delta: float) -> bool:
	if source == null or bones.is_empty():
		return false
	time += maxf(delta, 0.0)
	frames.append({
		"time": time,
		"poses": _capture(),
		"extra": extra_provider.call() if extra_provider.is_valid() else {},
	})
	while frames.size() > capacity:
		frames.pop_front()
	return true


func frame_count() -> int:
	return frames.size()


## Seconds covered by the tape. Zero when empty.
func duration() -> float:
	if frames.is_empty():
		return 0.0
	return float(frames[frames.size() - 1]["time"] - frames[0]["time"])


## Time of the oldest frame still retained (non-zero once the ring buffer wrapped).
func start_time() -> float:
	if frames.is_empty():
		return 0.0
	return float(frames[0]["time"])


## Clears the playhead to the middle of the tape and starts playback. Debug only:
## recording keeps running, so a replay does not corrupt the tape.
func start_playback() -> void:
	if frames.is_empty():
		return
	playhead = start_time()
	playing = true


## Moves the playhead. Values are clamped into the retained window.
func seek(t: float) -> void:
	if frames.is_empty():
		return
	playhead = clampf(t, start_time(), float(frames[frames.size() - 1]["time"]))


## Advances the playhead, stops at the end unless [member loop] is set.
func advance_playback(delta: float) -> bool:
	if not playing or frames.is_empty():
		return false
	playhead += delta * play_rate
	var end_time: float = float(frames[frames.size() - 1]["time"])
	if playhead >= end_time:
		if loop:
			playhead = start_time()
		else:
			playhead = end_time
			playing = false
	apply_at_playhead()
	return true


## Index of the last frame at or before [param t].
func index_before(t: float) -> int:
	var index: int = 0
	for i in frames.size():
		if float(frames[i]["time"]) <= t:
			index = i
		else:
			break
	return index


## Pose interpolated at [param t] (clamped to the tape). Angles interpolate the
## short way round, so a 359°-to-1° step does not spin the bone.
func sample(t: float) -> Dictionary:
	if frames.is_empty():
		return {}
	seek(t)
	var index: int = index_before(playhead)
	var a: Dictionary = frames[index]
	var b: Dictionary = frames[mini(index + 1, frames.size() - 1)]
	var span: float = maxf(float(b["time"]) - float(a["time"]), 0.000001)
	var weight: float = clampf((playhead - float(a["time"])) / span, 0.0, 1.0)
	return {
		"time": playhead,
		"poses": _blend(a["poses"], b["poses"], weight),
		"extra": a.get("extra", {}),
	}


## Applies the pose at [member playhead] to the bound skeleton.
func apply_at_playhead() -> Dictionary:
	if frames.is_empty():
		return {}
	var index: int = index_before(playhead)
	var result: Dictionary = apply_sample({
		"poses": frames[index]["poses"],
		"extra": frames[index].get("extra", {}),
	})
	return result


## Writes a sampled pose through the adapter, honouring its capabilities.
##
## Returns `{written: int, rotation: bool, origin: bool, scale: bool, shear: bool}` so a
## debug panel can state plainly that a channel was not restored.
func apply_sample(sample_pose: Dictionary) -> Dictionary:
	var poses: Array = sample_pose.get("poses", [])
	var written: int = 0
	for i in mini(poses.size(), bones.size()):
		var pose: Dictionary = poses[i]
		var bone: Variant = bones[i]
		if source.supports(BoneSource.CAP_ROTATE):
			source.set_local_rotation(bone, float(pose.get("r", 0.0)))
			written += 1
		if pose.has("o") and source.supports(BoneSource.CAP_TRANSLATE):
			source.set_origin(bone, pose["o"])
		if pose.has("s") and source.supports(BoneSource.CAP_SCALE):
			source.set_scale(bone, pose["s"])
		if pose.has("h") and source.supports(BoneSource.CAP_SHEAR):
			source.set_shear(bone, pose["h"])
	last_apply = {
		"written": written,
		"rotation": source.supports(BoneSource.CAP_ROTATE),
		"origin": source.supports(BoneSource.CAP_TRANSLATE),
		"scale": source.supports(BoneSource.CAP_SCALE),
		"shear": source.supports(BoneSource.CAP_SHEAR),
		"time": float(sample_pose.get("time", playhead)),
	}
	return last_apply


## Per-bone channel values, only for channels the adapter can actually write.
func _capture() -> Array:
	var poses: Array = []
	for bone in bones:
		var pose: Dictionary = {"r": source.get_local_rotation(bone)}
		if source.supports(BoneSource.CAP_TRANSLATE):
			pose["o"] = source.get_origin(bone)
		if source.supports(BoneSource.CAP_SCALE):
			pose["s"] = source.get_scale(bone)
		if source.supports(BoneSource.CAP_SHEAR):
			pose["h"] = source.get_shear(bone)
		poses.append(pose)
	return poses


func _blend(from_poses: Array, to_poses: Array, weight: float) -> Array:
	var out: Array = []
	for i in mini(from_poses.size(), to_poses.size()):
		var a: Dictionary = from_poses[i]
		var b: Dictionary = to_poses[i]
		var pose: Dictionary = {"r": lerp_angle(float(a.get("r", 0.0)), float(b.get("r", 0.0)), weight)}
		for channel in ["o", "s", "h"]:
			if a.has(channel) and b.has(channel):
				pose[channel] = (a[channel] as Vector2).lerp(b[channel] as Vector2, weight)
		out.append(pose)
	return out
