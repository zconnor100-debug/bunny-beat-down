class_name RigInfo
extends RefCounted
## A model's <id>.rig.json bound to its Skeleton3D: bone indices per role, rest
## pose in skeleton space, and the body segments used for hitboxes and the
## ragdoll. Works with any biped rig — roles, not bone names, drive the code.

const ROLES := [
	&"hips", &"spine", &"chest", &"neck", &"head",
	&"l_upper_arm", &"l_lower_arm", &"l_hand", &"r_upper_arm", &"r_lower_arm", &"r_hand",
	&"l_upper_leg", &"l_lower_leg", &"l_foot", &"r_upper_leg", &"r_lower_leg", &"r_foot",
]
## Segments that get a hitbox + physical bone, and their mass share.
const BODY_SEGMENTS := {
	&"hips": 0.2, &"spine": 0.12, &"chest": 0.2, &"head": 0.12,
	&"l_upper_arm": 0.04, &"l_lower_arm": 0.03, &"r_upper_arm": 0.04, &"r_lower_arm": 0.03,
	&"l_upper_leg": 0.07, &"l_lower_leg": 0.05, &"r_upper_leg": 0.07, &"r_lower_leg": 0.05,
}
## Damage multipliers per body part (head handled by the weapon's own multiplier).
const DAMAGE_SCALE := {
	&"hips": 1.0, &"spine": 1.0, &"chest": 1.0, &"head": 1.0,
	&"l_upper_arm": 0.8, &"l_lower_arm": 0.7, &"r_upper_arm": 0.8, &"r_lower_arm": 0.7,
	&"l_upper_leg": 0.85, &"l_lower_leg": 0.75, &"r_upper_leg": 0.85, &"r_lower_leg": 0.75,
}

var id := ""
var data: Dictionary = {}
var head_top := 1.0
var eye_height := 0.85
var skeleton: Skeleton3D
var bone: Dictionary = {}          # role -> bone index (-1 if absent)
var chains: Dictionary = {}        # chain name -> PackedInt32Array
var radii: Dictionary = {}         # role -> float
var rest: Dictionary = {}          # role -> Transform3D (skeleton space)
var segments: Dictionary = {}      # role -> {"start": Vector3, "end": Vector3, "radius": float}
var arm_length := {&"l": 0.3, &"r": 0.3}
var leg_length := {&"l": 0.4, &"r": 0.4}
var scale := 1.0                   # head_top / 0.95 — model size relative to the hero
## CritterDef.body_scale: the model node is scaled by this, so skeleton-space
## values (rest, segments, radii, head_top...) are model units; world = model * size.
var size := 1.0

var world_head_top: float:
	get:
		return head_top * size

var world_eye_height: float:
	get:
		return eye_height * size

var world_scale: float:
	get:
		return scale * size


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func bind(json: Dictionary, skel: Skeleton3D, size_ := 1.0) -> bool:
	data = json
	size = size_
	skeleton = skel
	id = str(json.get("id", "critter"))
	head_top = float(json.get("head_top", 1.0))
	eye_height = float(json.get("eye_height", head_top * 0.88))
	scale = head_top / 0.95
	var bones: Dictionary = json.get("bones", {})
	for role in ROLES:
		var name: Variant = bones.get(String(role))
		bone[role] = skel.find_bone(String(name)) if name is String else -1
	for essential in [&"hips", &"head", &"l_upper_arm", &"l_lower_arm", &"r_upper_arm", &"r_lower_arm",
			&"l_upper_leg", &"l_lower_leg", &"r_upper_leg", &"r_lower_leg"]:
		if bone[essential] < 0:
			push_warning("%s: rig is missing essential role %s" % [id, essential])
			return false
	# optional roles fall back to their neighbours so the code never sees -1 for them
	if bone[&"chest"] < 0:
		bone[&"chest"] = bone[&"spine"] if bone[&"spine"] >= 0 else bone[&"hips"]
	if bone[&"neck"] < 0:
		bone[&"neck"] = bone[&"head"]
	for c in json.get("chains", {}):
		var arr := PackedInt32Array()
		for b in json["chains"][c]:
			var i := skel.find_bone(String(b))
			if i >= 0:
				arr.append(i)
		if not arr.is_empty():
			chains[StringName(c)] = arr
	var r: Dictionary = json.get("radii", {})
	for role in ROLES:
		radii[role] = float(r.get(String(role), 0.05 * scale))
	for role in ROLES:
		if bone[role] >= 0:
			rest[role] = skel.get_bone_global_rest(bone[role])
	_build_segments()
	for side in [&"l", &"r"]:
		arm_length[side] = _p(StringName(side + "_upper_arm")).distance_to(_p(StringName(side + "_lower_arm"))) \
			+ _p(StringName(side + "_lower_arm")).distance_to(_hand_or_end(side))
		leg_length[side] = _p(StringName(side + "_upper_leg")).distance_to(_p(StringName(side + "_lower_leg"))) \
			+ _p(StringName(side + "_lower_leg")).distance_to(_foot_or_end(side))
	return true


func has_role(role: StringName) -> bool:
	return bone.get(role, -1) >= 0


func _p(role: StringName) -> Vector3:
	return (rest[role] as Transform3D).origin


func _hand_or_end(side: StringName) -> Vector3:
	var hand := StringName(side + "_hand")
	if has_role(hand):
		return _p(hand)
	var a := _p(StringName(side + "_upper_arm"))
	var b := _p(StringName(side + "_lower_arm"))
	return b + (b - a)


func _foot_or_end(side: StringName) -> Vector3:
	var foot := StringName(side + "_foot")
	if has_role(foot):
		return _p(foot)
	var b := _p(StringName(side + "_lower_leg"))
	return Vector3(b.x, 0.05 * scale, b.z)


func _build_segments() -> void:
	var hips := _p(&"hips")
	var has_spine: bool = has_role(&"spine") and bone[&"spine"] != bone[&"hips"]
	var chest := _p(&"chest")
	var neck := _p(&"neck")
	var head := _p(&"head")
	var head_end := Vector3(head.x, head_top, head.z)
	if has_spine:
		var spine := _p(&"spine")
		_seg(&"hips", hips, spine)
		_seg(&"spine", spine, chest if chest.distance_to(spine) > 0.02 else spine + Vector3.UP * 0.1 * scale)
	else:
		_seg(&"hips", hips, chest if chest.distance_to(hips) > 0.02 else hips + Vector3.UP * 0.12 * scale)
	_seg(&"chest", chest, neck if neck.distance_to(chest) > 0.03 else chest + Vector3.UP * 0.12 * scale)
	_seg(&"head", head if head.distance_to(neck) > 0.01 else neck, head_end)
	for side in [&"l", &"r"]:
		var ua := StringName(side + "_upper_arm")
		var la := StringName(side + "_lower_arm")
		var ul := StringName(side + "_upper_leg")
		var ll := StringName(side + "_lower_leg")
		_seg(ua, _p(ua), _p(la))
		var hand := _hand_or_end(side)
		# the forearm body also covers the paw
		_seg(la, _p(la), hand + (hand - _p(la)).normalized() * radii[la] * 1.5)
		_seg(ul, _p(ul), _p(ll))
		var foot := _foot_or_end(side)
		_seg(ll, _p(ll), foot)


func _seg(role: StringName, a: Vector3, b: Vector3) -> void:
	if a.distance_to(b) < 0.01:
		b = a + Vector3.UP * 0.05 * scale
	segments[role] = {"start": a, "end": b, "radius": maxf(radii.get(role, 0.05), 0.02)}


## Every bone in the subtree under `idx` (inclusive) — used to drop limbs.
func subtree(idx: int) -> PackedInt32Array:
	var out := PackedInt32Array([idx])
	var i := 0
	while i < out.size():
		for c in skeleton.get_bone_children(out[i]):
			out.append(c)
		i += 1
	return out


## The role whose segment owns `idx` (walking up the hierarchy), or &"".
func role_of_bone(idx: int) -> StringName:
	var i := idx
	while i >= 0:
		for role in BODY_SEGMENTS:
			if bone.get(role, -1) == i:
				return role
		i = skeleton.get_bone_parent(i)
	return &""
