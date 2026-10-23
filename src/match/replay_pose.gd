class_name ReplayPose
extends SkeletonModifier3D
## Last in a critter's modifier stack while the KillCam records: every frame
## it notes what the critter looked like after the animator, the ragdoll and
## the limb hider had their say (where the body stood, how it leaned, every
## bone, where the gun was, where its chest was). During a replay it puts a
## recorded frame back instead (blended between the two nearest).

const KEEP := 5.0

var visual: CritterVisual
## [t, visual_xf, model_xf, holder_xf, holder_visible, focus, poses]
var frames: Array = []
var play_at := -1.0                ## >= 0: show the frame recorded at this time


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or visual == null:
		return
	if play_at >= 0.0:
		_show(skel, play_at)
		return
	var kc := KillCam.instance
	if kc == null or not KillCam.recording:
		return
	var poses: Array[Transform3D] = []
	poses.resize(skel.get_bone_count())
	for i in poses.size():
		poses[i] = skel.get_bone_pose(i)
	var holder := visual.holder
	frames.append([kc.clock, visual.global_transform, visual.model.transform, holder.transform if holder else Transform3D.IDENTITY,
		holder != null and holder.visible, focus_now(), poses])
	while frames.size() > 2 and float(frames[0][0]) < kc.clock - KEEP:
		frames.pop_front()


## Where to point a camera at this critter right now: its chest (ragdoll and all).
func focus_now() -> Vector3:
	if visual.rig and visual.rig.has_role(&"chest"):
		return visual.bone_world_position(&"chest")
	return visual.global_position + Vector3.UP


## The recorded frame at time t, blended: [visual_xf, model_xf, holder_xf,
## holder_visible, focus, poses]; empty if nothing was recorded by then.
func sample(t: float) -> Array:
	if frames.is_empty() or t < float(frames[0][0]) - 0.05:
		return []
	var i := frames.size() - 1
	while i > 0 and float(frames[i][0]) > t:
		i -= 1
	var a: Array = frames[i]
	var b: Array = frames[mini(i + 1, frames.size() - 1)]
	var span := float(b[0]) - float(a[0])
	var k := clampf((t - float(a[0])) / span, 0.0, 1.0) if span > 1e-5 else 0.0
	var pa: Array = a[6]
	var pb: Array = b[6]
	var poses: Array[Transform3D] = []
	poses.resize(pa.size())
	for j in pa.size():
		poses[j] = (pa[j] as Transform3D).interpolate_with(pb[j], k) if j < pb.size() else pa[j]
	return [(a[1] as Transform3D).interpolate_with(b[1], k), (a[2] as Transform3D).interpolate_with(b[2], k),
		(a[3] as Transform3D).interpolate_with(b[3], k), a[4], (a[5] as Vector3).lerp(b[5], k), poses]


## (The KillCam places the body itself, before the skeleton updates; this
## puts back the bones and the gun, after the animator has moved them.)
func _show(skel: Skeleton3D, t: float) -> void:
	var f := sample(t)
	if f.is_empty():
		return
	if visual.holder:
		visual.holder.transform = f[2]
		visual.holder.visible = f[3]
	var poses: Array = f[5]
	for i in mini(poses.size(), skel.get_bone_count()):
		skel.set_bone_pose(i, poses[i])
