class_name DamageInfo
extends RefCounted
## Everything a victim needs to know about one hit: how much, from whom, where,
## and how hard it should shove the body (and possibly which bits fall off).

enum Kind { BULLET, EXPLOSION, STORM, FALL, MELEE, BLEED }   ## BLEED: thorns and bleeding (Boons)

var amount: float = 0.0
var kind: Kind = Kind.BULLET
var attacker: Node = null            # Critter or null (storm)
var weapon_id: StringName = &""
var position: Vector3 = Vector3.ZERO # world-space hit point
var direction: Vector3 = Vector3.FORWARD
var impulse: float = 0.0             # N*s applied to the ragdoll / hit bone
var bone_role: StringName = &""      # e.g. &"head", &"l_lower_arm"
var headshot: bool = false
var dismember_power: float = 0.0     # 0 = never, 1 = guaranteed limb loss on kill
var mutated := false                 # a shard, or a carrot that pierced or bounced (Boons: Briar Shards)


static func make(amount_: float, kind_: Kind, attacker_: Node, weapon_id_: StringName = &"") -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amount_
	d.kind = kind_
	d.attacker = attacker_
	d.weapon_id = weapon_id_
	return d
