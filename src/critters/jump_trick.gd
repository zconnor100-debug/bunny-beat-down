class_name JumpTrick
extends RefCounted
## The species-specific move a critter pulls off in the air (CritterDef.JumpStyle).
## Given the jump's predicted airtime it produces, at any moment, a rotation of
## the whole body about its centre of mass, timed to finish exactly as the
## critter lands, plus how much the limbs should tuck or stretch.
## Pure maths (no scene access), so it is unit-tested directly.

enum Variant { NONE, FRONT, BACK, LEFT, RIGHT }

var style: int = CritterDef.JumpStyle.FLIP
var variant: Variant = Variant.FRONT
var airtime := 1.0
var elapsed := 0.0
var active := false
## Seconds left in the post-landing settle (snaps leftover rotation upright).
var settle := 0.0
var _settle_from := Basis.IDENTITY

const SETTLE_TIME := 0.12


## local_vel: the critter's velocity in its own frame (x right, -z forward).
static func make(style_: int, local_vel: Vector3, airtime_: float) -> JumpTrick:
	var t := JumpTrick.new()
	t.style = style_
	t.airtime = maxf(airtime_, 0.3)
	t.active = true
	var fwd := -local_vel.z
	var side := local_vel.x
	match style_:
		CritterDef.JumpStyle.FLIP:
			# bunnies flip the way they're travelling; a standing jump is a backflip
			if fwd > 1.0 and fwd >= absf(side):
				t.variant = Variant.FRONT
			elif fwd < -1.0 and -fwd >= absf(side):
				t.variant = Variant.BACK
			elif absf(side) > 1.0:
				t.variant = Variant.RIGHT if side > 0.0 else Variant.LEFT
			else:
				t.variant = Variant.BACK
		CritterDef.JumpStyle.BARREL, CritterDef.JumpStyle.SPIN:
			t.variant = Variant.LEFT if side < -0.5 else Variant.RIGHT
		_:
			t.variant = Variant.FRONT
	return t


## Slow-fast-slow progress: a flip hangs a moment at take-off and landing.
static func ease_flip(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t - sin(TAU * t) / TAU


func progress() -> float:
	return clampf(elapsed / airtime, 0.0, 1.0)


func step(delta: float) -> void:
	if active:
		elapsed += delta
	elif settle > 0.0:
		settle = maxf(0.0, settle - delta)


## Called on touchdown: whatever rotation is left gets a quick settle upright.
func land() -> void:
	if not active:
		return
	_settle_from = rotation_at(progress())
	active = false
	settle = SETTLE_TIME


func finished() -> bool:
	return not active and settle <= 0.0


## Current body rotation (about the centre of mass, critter-local axes:
## x right, y up, -z forward).
func rotation() -> Basis:
	if active:
		return rotation_at(progress())
	if settle > 0.0:
		return _settle_from.slerp(Basis.IDENTITY, 1.0 - settle / SETTLE_TIME)
	return Basis.IDENTITY


func rotation_at(t: float) -> Basis:
	var e := ease_flip(t)
	match style:
		CritterDef.JumpStyle.FLIP:
			match variant:
				Variant.FRONT:
					return Basis(Vector3.RIGHT, -TAU * e)   # head goes forward and down
				Variant.BACK:
					return Basis(Vector3.RIGHT, TAU * e)
				Variant.RIGHT:
					return Basis(Vector3.FORWARD, TAU * e)    # rolls over toward its right
				Variant.LEFT:
					return Basis(Vector3.FORWARD, -TAU * e)
		CritterDef.JumpStyle.SPIN:
			var dir := -1.0 if variant == Variant.LEFT else 1.0
			return Basis(Vector3.UP, TAU * e * dir) * Basis(Vector3.RIGHT, 0.18 * sin(PI * t))
		CritterDef.JumpStyle.POUNCE:
			# nose up on the way up, then a steep head-first dive like a fox mousing
			var pitch := 0.45 * sin(PI * clampf(t / 0.45, 0.0, 1.0)) - 1.15 * smoothstep(0.45, 0.92, t)
			return Basis(Vector3.RIGHT, pitch)
		CritterDef.JumpStyle.TUCK_ROLL:
			return Basis(Vector3.RIGHT, -TAU * e)
		CritterDef.JumpStyle.FROG_LEAP:
			return Basis(Vector3.RIGHT, -0.6 * sin(PI * t))
		CritterDef.JumpStyle.TAIL_SLAP:
			return Basis(Vector3.RIGHT, 0.4 * sin(PI * t))
		CritterDef.JumpStyle.BARREL:
			var d := -1.0 if variant == Variant.LEFT else 1.0
			return Basis(Vector3.FORWARD, TAU * e * d)
	return Basis.IDENTITY


## Rotation-heavy tricks put the gun on the wrong side of the world mid-air,
## so they hold fire until the critter is nearly upright again.
func blocks_fire() -> bool:
	return active and progress() < 0.85 and style in [CritterDef.JumpStyle.FLIP, CritterDef.JumpStyle.SPIN,
		CritterDef.JumpStyle.TUCK_ROLL, CritterDef.JumpStyle.BARREL]


## Limb shaping for the animator: +1 = tuck knees/arms in tight, -1 = stretch out.
func tuck() -> float:
	if not active:
		return 0.0
	var arc := sin(PI * progress())
	match style:
		CritterDef.JumpStyle.FLIP, CritterDef.JumpStyle.BARREL:
			return arc
		CritterDef.JumpStyle.TUCK_ROLL:
			return minf(1.0, arc * 1.6)
		CritterDef.JumpStyle.FROG_LEAP, CritterDef.JumpStyle.POUNCE:
			return -arc
	return arc * 0.3
