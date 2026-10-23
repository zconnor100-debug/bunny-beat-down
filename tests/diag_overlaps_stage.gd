extends Node3D
## See tests/diag_overlaps.gd. MapCheck does the work (tests use it too).

const MapCheck := preload("res://tests/map_check.gd")

var map := "cage"
var seed_value := 777
var min_depth := 0.35


func _ready() -> void:
	add_child(FX.new())
	add_child(Projectiles.new())
	var island: Island = {"cage": HamsterCage, "toybox": ToyBox}.get(map, Island).new()
	add_child(island)
	await island.generate(seed_value, 2, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var found := MapCheck.overlaps(island, min_depth)
	for o in found:
		print("OVERLAP %.2f m  %s  <->  %s  at %s" % [o.depth, o.a, o.b, (o.at as Vector3).snapped(Vector3.ONE * 0.1)])
	for o in MapCheck.overlaps(island, maxf(min_depth, 0.5), true):
		print("PARTS %.2f m  %s  <->  %s  at %s" % [o.depth, o.a, o.b, (o.at as Vector3).snapped(Vector3.ONE * 0.1)])
	var lost := MapCheck.buried_loot(island)
	for l in lost:
		print("LOOT IN SOLID  %s at %s" % [l.what, (l.at as Vector3).snapped(Vector3.ONE * 0.1)])
	print("%s #%d: %d overlaps, %d buried loot spots" % [map, seed_value, found.size(), lost.size()])
	get_tree().quit()
