class_name IKMath
## Small, dependency-free maths helpers for the procedural animator.
## Everything here is pure (no scene access) so it is unit-tested directly.


## Analytic two-bone IK (law of cosines).
## root: shoulder/hip position, lengths l1 (upper) and l2 (lower),
## target: where the end (wrist/ankle) should go, pole: a point the middle
## joint (elbow/knee) should bend towards.
## Returns [mid_position, end_position] — the end is clamped to reach.
static func solve_two_bone(root: Vector3, l1: float, l2: float, target: Vector3, pole: Vector3) -> PackedVector3Array:
	var to_target := target - root
	var dist := to_target.length()
	var reach := l1 + l2
	dist = clampf(dist, absf(l1 - l2) + 0.0001, reach * 0.9999)
	var n := to_target.normalized() if to_target.length_squared() > 1e-10 else Vector3.DOWN
	var end := root + n * dist
	# angle at the root between the target line and the upper bone
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var bend := pole - root
	bend -= n * bend.dot(n)
	if bend.length_squared() < 1e-10:
		bend = n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.UP)
	bend = bend.normalized()
	var mid := root + (n * cos_a + bend * sin_a) * l1
	return PackedVector3Array([mid, end])


## Shortest-arc rotation taking direction `from` onto direction `to`.
static func from_to(from: Vector3, to: Vector3) -> Quaternion:
	var a := from.normalized()
	var b := to.normalized()
	var d := a.dot(b)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var axis := a.cross(Vector3.RIGHT)
		if axis.length_squared() < 1e-6:
			axis = a.cross(Vector3.UP)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(a.cross(b).normalized(), acos(d))


## Critically-damped spring step (useful for smoothing poses frame-rate
## independently). Returns [new_value, new_velocity].
static func spring_vec3(value: Vector3, velocity: Vector3, target: Vector3, half_life: float, dt: float) -> Array:
	var y := 0.6931472 * 2.0 / maxf(half_life, 1e-4) / 2.0
	var j0 := value - target
	var j1 := velocity + j0 * y
	var eydt := exp(-y * dt)
	return [eydt * (j0 + j1 * dt) + target, eydt * (velocity - j1 * y * dt)]


## Frame-rate independent exponential smoothing factor.
static func damp(rate: float, dt: float) -> float:
	return 1.0 - exp(-rate * dt)
