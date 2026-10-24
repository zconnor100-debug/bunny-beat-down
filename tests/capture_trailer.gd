extends SceneTree
## Records the 30-second trailer: runs tests/trailer_stage.gd (loaded at
## runtime so the autoloads exist). Record with Movie Maker (frames plus a WAV
## of the game's own sound), then tools/make_trailer.py makes an MP4 and a
## README GIF from them:
##   godot --path . --write-movie <dir>/f.png --fixed-fps 30 --resolution 1920x1080 \
##         -s tests/capture_trailer.gd
## Preview stills instead of a movie:
##   godot --path . --fixed-fps 30 -s tests/capture_trailer.gd -- <dir> preview
## The Hamster Cage cut: add "cage" after the folder (tests/trailer_cage_stage.gd);
## for the tall phone cut, record at --resolution 1080x1920.


func _initialize() -> void:
	Engine.max_fps = 0
	_start.call_deferred()


func _start() -> void:
	var cage := OS.get_cmdline_user_args().has("cage")
	root.add_child(load("res://tests/trailer_cage_stage.gd" if cage else "res://tests/trailer_stage.gd").new())
