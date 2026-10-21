class_name LimbHider
extends SkeletonModifier3D
## Runs last in the modifier stack: collapses every bone in `hidden` to zero
## scale, so a limb that was shot off disappears from the body (its subtree
## collapses into the stump) whatever the ragdoll or animator did before.

var hidden: PackedInt32Array = []


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for idx in hidden:
		skel.set_bone_pose_scale(idx, Vector3(0.0001, 0.0001, 0.0001))
