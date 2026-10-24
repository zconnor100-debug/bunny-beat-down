extends "res://tests/workshop_stage.gd"
## Stage for tests/capture_guns.gd.

const ALL := ["carrot_pistol", "carrot_smg", "carrot_shotgun", "carrot_rifle", "carrot_lmg", "carrot_sniper",
	"carrot_rocket_launcher"]

var ids: Array = []


func _run() -> void:
	var light := WorldLighting.new()
	add_child(light)
	light.build(3)
	light.sun.rotation_degrees = Vector3(-35, -140, 0)
	light.env.fog_density = 0.001
	_ground()
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var guns := {}
	var list: Array = ids if not ids.is_empty() else ALL
	for i in list.size():
		var data := WeaponDB.get_weapon(StringName(list[i]))
		var gun := ModelUtil.instantiate(data.model_path)
		add_child(gun)
		gun.position = Vector3(i * 4.0, 1.2, 0.0)
		gun.rotation.y = PI / 2.0   # (barrel along +X: side on to a camera looking down -Z)
		guns[list[i]] = gun
	await _wait(0.8)
	for id in list:
		var gun: Node3D = guns[id]
		var size := WeaponDB.get_weapon(StringName(id)).hold_distance
		var length := _length(gun)
		cam.fov = 30
		cam.global_position = gun.global_position + Vector3(0.0, 0.05, length * 1.95 + 0.15)
		cam.look_at(gun.global_position + Vector3(0, 0.0, 0), Vector3.UP)
		await _wait(0.25)
		await _snap("90_%s_side" % id)
		cam.global_position = gun.global_position + Vector3(length * 1.1, length * 0.55, length * 1.45)
		cam.look_at(gun.global_position, Vector3.UP)
		await _wait(0.25)
		await _snap("91_%s_34" % id)
	if ids.is_empty():
		# the armoury: all of them side by side on a rack, from above
		for i in list.size():
			guns[list[i]].position = Vector3(0.0, 1.2, i * 0.32)
		cam.fov = 42
		cam.global_position = Vector3(0.05, 3.1, list.size() * 0.16 + 0.05)
		cam.look_at(Vector3(0.05, 1.2, list.size() * 0.16), Vector3.FORWARD)
		await _wait(0.3)
		await _snap("92_armoury")
	get_tree().quit()


func _length(n: Node3D) -> float:
	var aabb := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	return maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
