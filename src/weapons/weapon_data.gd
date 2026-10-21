class_name WeaponData
extends Resource
## Static description of one carrot gun. Lives in res://data/weapons/*.tres so
## balancing is done in the inspector, never in code.

enum FireMode { SEMI, AUTO }
enum AmmoType { LIGHT, SHELLS, HEAVY, ROCKET }
enum ProjectileKind { BOLT, PELLET, ROCKET }

@export var id: StringName
@export var display_name := ""
@export_multiline var blurb := ""
@export_file("*.glb") var model_path := ""
@export var icon_color := Color.ORANGE

@export_group("Firing")
@export var fire_mode := FireMode.SEMI
@export var ammo_type := AmmoType.LIGHT
@export var magazine := 12
@export var rounds_per_minute := 300.0
@export var pellets := 1
@export var damage := 20.0
@export var headshot_multiplier := 1.75
@export var spread_hip_deg := 2.0
@export var spread_aim_deg := 0.5
@export var spread_move_deg := 1.5
@export var bloom_per_shot_deg := 0.3
@export var bloom_max_deg := 3.0

@export_group("Projectile")
@export var projectile := ProjectileKind.BOLT
@export var projectile_speed := 120.0
@export var projectile_gravity := 0.6   ## multiple of world gravity
@export var falloff_start := 30.0
@export var falloff_end := 80.0
@export var min_damage_scale := 0.5
@export var impulse := 6.0              ## N*s shove on the hit body part
@export var dismember_power := 0.2      ## chance-ish of popping a limb on a kill
@export var splash_radius := 0.0
@export var splash_damage := 0.0

@export_group("Handling")
@export var reload_time := 1.6
@export var equip_time := 0.35
@export var two_handed := true
@export var hold_distance := 0.26       ## grip distance in front of the shoulder (m)
@export var aim_fov_scale := 0.8
@export var recoil_pitch_deg := 1.5
@export var recoil_yaw_deg := 0.4
@export var camera_shake := 0.08
@export var move_speed_scale := 1.0
@export var scoped := false             ## aiming shows a scope overlay (sniper)

@export_group("Audio")
@export var sfx_fire: StringName = &"pistol_fire"
@export var cycle_sfx: StringName = &""  ## played after each shot (bolt action)

@export_group("AI")
@export var ai_preferred_range := 18.0
@export var ai_max_range := 55.0
@export var ai_min_range := 0.0         ## don't fire closer than this (rockets!)
@export var ai_burst := 1               ## shots per trigger pull for SEMI weapons

@export_group("Loot")
@export var loot_weight := 1.0


func seconds_per_shot() -> float:
	return 60.0 / maxf(rounds_per_minute, 1.0)


func damage_at(distance: float) -> float:
	if distance <= falloff_start:
		return damage
	var t := clampf((distance - falloff_start) / maxf(falloff_end - falloff_start, 0.01), 0.0, 1.0)
	return damage * lerpf(1.0, min_damage_scale, t)


static func ammo_name(t: AmmoType) -> String:
	return ["Baby Carrots", "Carrot Shells", "Carrot Belt", "Rocket Carrots"][t]
