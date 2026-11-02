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
## Flowing through its keys instead of easing to a stop at each one: a curve
## through the keys either side that never overshoots a key, so a held pose
## still holds and a turn back still turns where it's keyed (a live animal's
## move, not a puppet's).
var flow := false
## (t: float) -> {role: degrees}: more on top of the keys every frame (a
## breath, a twitch of a paw in its sleep, a dizzy head going round).
var layer: Callable
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
			if flow:
				return _flowing(i, u)
			return blend(a[1], b[1], u * u * (3.0 - 2.0 * u))
	return keys.back()[1]


## `u` of the way from key i to the next, flowing (a monotone cubic through
## the keys: each role's angles carry on through a key heading the same way,
## and stop only where they turn back, at a hold, and at the ends).
func _flowing(i: int, u: float) -> Dictionary:
	var k1: Array = keys[i]
	var k2: Array = keys[i + 1]
	var k0: Array = keys[i - 1] if i > 0 else k1
	var k3: Array = keys[i + 2] if i + 2 < keys.size() else k2
	var h0 := float(k1[0]) - float(k0[0])
	var h := maxf(float(k2[0]) - float(k1[0]), 1e-4)
	var h2 := float(k3[0]) - float(k2[0])
	var u2 := u * u
	var u3 := u2 * u
	var c1 := 2.0 * u3 - 3.0 * u2 + 1.0
	var m1 := (u3 - 2.0 * u2 + u) * h
	var c2 := -2.0 * u3 + 3.0 * u2
	var m2 := (u3 - u2) * h
	var p0: Dictionary = k0[1]
	var p1: Dictionary = k1[1]
	var p2: Dictionary = k2[1]
	var p3: Dictionary = k3[1]
	var out := {}
	for pose_ in [p1, p2, p0, p3]:
		for r in pose_:
			if out.has(r):
				continue
			var a: Vector3 = p0.get(r, Vector3.ZERO)
			var b: Vector3 = p1.get(r, Vector3.ZERO)
			var c: Vector3 = p2.get(r, Vector3.ZERO)
			var d: Vector3 = p3.get(r, Vector3.ZERO)
			out[r] = b * c1 + _slope(a, b, c, h0, h) * m1 + c * c2 + _slope(b, c, d, h, h2) * m2
	return out


## How fast each angle is going through key value `b` (between `a`, `ha`
## seconds before, and `c`, `hb` after): the harmonic mean of the two slopes
## if they head the same way, else 0 (so the curve never overshoots).
static func _slope(a: Vector3, b: Vector3, c: Vector3, ha: float, hb: float) -> Vector3:
	var out := Vector3.ZERO
	if ha <= 1e-4 or hb <= 1e-4:
		return out
	for k in 3:
		var d1 := (b[k] - a[k]) / ha
		var d2 := (c[k] - b[k]) / hb
		if d1 * d2 > 0.0:
			out[k] = 2.0 / (1.0 / d1 + 1.0 / d2)
	return out


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
