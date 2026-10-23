class_name RealClock
extends RefCounted
## Time for things that play while the match is paused (the rewind running
## backwards, the final-shot replay). Normally that's wall-clock time: the
## paused engine's frame delta can drift well off real time. Under Movie
## Maker (a fixed frame rate, far slower than real time) it's the engine's
## own delta, so recordings play at the right speed.

static var movie := Engine.get_write_movie_path() != ""

var _us := 0


func start() -> void:
	_us = Time.get_ticks_usec()


## Seconds since start() or the last step() (at most 0.1, so a hitch doesn't jump).
func step(engine_delta: float) -> float:
	var now := Time.get_ticks_usec()
	var dt := minf((now - _us) / 1e6, 0.1)
	_us = now
	return engine_delta if movie else dt
