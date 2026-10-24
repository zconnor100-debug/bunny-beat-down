class_name RealClock
extends RefCounted
## Time for things that play while the match is paused (the rewind running
## backwards, the final-shot replay). Normally that's wall-clock time: the
## paused engine's frame delta can drift well off real time. When frames are
## fixed (Movie Maker recordings, trailer previews; whoever drives those sets
## `fixed_step`) it's one fixed frame per frame, so recordings play at the
## right speed.

static var fixed_step := _fixed_step()

var _us := 0


static func _fixed_step() -> float:
	if Engine.get_write_movie_path() == "":
		return 0.0
	return 1.0 / maxf(float(ProjectSettings.get_setting("editor/movie_writer/fps", 60)), 1.0)


func start() -> void:
	_us = Time.get_ticks_usec()


## Seconds since start() or the last step() (at most 0.1, so a hitch doesn't jump).
func step(_engine_delta := 0.0) -> float:
	var now := Time.get_ticks_usec()
	var dt := minf((now - _us) / 1e6, 0.1)
	_us = now
	return fixed_step if fixed_step > 0.0 else dt
