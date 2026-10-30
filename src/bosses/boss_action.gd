class_name BossAction
extends RefCounted
## One thing a boss does (a slam, a throw, a charge, a roar): how long it
## takes, the poses it strikes along the way (keyframes, eased between), what
## happens when (events, each fired once), and anything it does every frame
## meanwhile (`tick`: moving the boss for a leap or a charge, sweeping a beam).

var name: StringName
var length := 1.0
var t := 0.0
var keys: Array = []            ## [[seconds, {role: Vector3 degrees, &"root": offset}], ...]
var events: Array = []          ## [[seconds, Callable], ...]
var tick: Callable              ## (t: float, delta: float) -> void, every frame
var blend_in := 0.2             ## seconds to ease from the walk into its first pose
var blend_out := 0.35           ## and back out at the end
var interruptible := true       ## (a leap in mid-air isn't)
var target := Vector3.ZERO      ## where it's aimed (the ground)
var data: Dictionary = {}
var _fired := 0


func _init(name_: StringName, length_: float) -> void:
	name = name_
	length = length_


## Strike `pose` at `at` seconds (keys are kept in time order).
func key(at: float, pose: Dictionary) -> BossAction:
	keys.append([at, pose])
	keys.sort_custom(func(a, b): return a[0] < b[0])
	return self


## Call `fn` once, `at` seconds in.
func on(at: float, fn: Callable) -> BossAction:
	events.append([at, fn])
	events.sort_custom(func(a, b): return a[0] < b[0])
	return self


## Run it on `delta` seconds: fire what's due, tick. False once it's over.
func step(delta: float) -> bool:
	t += delta
	while _fired < events.size() and t >= float(events[_fired][0]):
		var fn: Callable = events[_fired][1]
		_fired += 1
		if fn.is_valid():
			fn.call()
	if tick.is_valid():
		tick.call(t, delta)
	return t < length


## The pose at the moment (eased from key to key).
func pose() -> Dictionary:
	if keys.is_empty():
		return {}
	if t <= float(keys[0][0]):
		return keys[0][1]
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= float(b[0]):
			var u := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-4)
			return blend(a[1], b[1], u * u * (3.0 - 2.0 * u))
	return keys.back()[1]


## How much of the action's pose shows over the walk (easing in and out).
func weight() -> float:
	var w := 1.0
	if blend_in > 0.0:
		w = minf(w, t / blend_in)
	if blend_out > 0.0:
		w = minf(w, (length - t) / blend_out)
	return clampf(w, 0.0, 1.0)


static func blend(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var out := {}
	for k in a:
		out[k] = (a[k] as Vector3).lerp(b.get(k, Vector3.ZERO), u)
	for k in b:
		if not out.has(k):
			out[k] = Vector3.ZERO.lerp(b[k], u)
	return out
