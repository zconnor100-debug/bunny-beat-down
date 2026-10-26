extends SceneTree
## Records the 30-second trailer: runs tests/trailer_stage.gd (loaded at
## runtime so the autoloads exist). Record with Movie Maker (frames plus a WAV
## of the game's own sound), then tools/make_trailer.py makes an MP4 and a
## README GIF from them:
##   godot --path . --write-movie <dir>/f.png --fixed-fps 30 --resolution 1920x1080 \
##         -s tests/capture_trailer.gd
## Preview stills instead of a movie:
##   godot --path . --fixed-fps 30 -s tests/capture_trailer.gd -- <dir> preview
## The Hamster Cage cut: add "cage" after the folder (tests/trailer_cage_stage.gd),
## the Toy Box Bash cut: "toybox" (tests/trailer_toybox_stage.gd);
## for the tall phone cut, record at --resolution 1080x1920.
## The 30-second phone reel is recorded a map at a time ("reel island", "reel
## cage", "reel toybox": tests/trailer_reel_stage.gd) and cut together by
## tools/make_reel.py. "The Hunt" phone cut is the same, a map at a time
## ("hunt island", "hunt cage", "hunt toybox": tests/trailer_hunt_stage.gd),
## cut by tools/make_hunt_trailer.py.


func _initialize() -> void:
	Engine.max_fps = 0
	_start.call_deferred()


func _start() -> void:
	var a := OS.get_cmdline_user_args()
	var stage := "res://tests/trailer_cage_stage.gd" if a.has("cage") else ("res://tests/trailer_toybox_stage.gd" if a.has("toybox") else "res://tests/trailer_stage.gd")
	if a.has("reel"):
		stage = "res://tests/trailer_reel_stage.gd"   # (the phone reel: "reel island|cage|toybox")
	if a.has("hunt"):
		stage = "res://tests/trailer_hunt_stage.gd"   # (the hunt: "hunt island|cage|toybox")
	root.add_child(load(stage).new())
