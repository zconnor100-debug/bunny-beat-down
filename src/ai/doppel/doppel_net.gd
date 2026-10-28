class_name DoppelNet
extends RefCounted
## The Doppelbunny's brain: a small neural network (DoppelSense.INPUTS ->
## HIDDEN -> HIDDEN -> DoppelSense.OUTPUTS, ReLU), trained on what you did
## in your fights. Its outputs are the odds of each move (softmax over
## DoppelSense.MOVES) and of each other thing you do (a sigmoid per
## DoppelSense.FLAGS). Plain GDScript: every weight lives in one flat
## PackedFloat32Array written in place (a copy of a packed array would be
## copied on every write), fast enough to train a few passes over a few
## thousand moments in seconds (docs/plans/doppelbunny.md: the speed check).

const HIDDEN := 64
const MOVES := 5                     ## (DoppelSense.MOVES.size(): the first outputs)

var sizes: PackedInt32Array = [DoppelSense.INPUTS, HIDDEN, HIDDEN, DoppelSense.OUTPUTS]
var w := PackedFloat32Array()        ## each layer's weights, then its biases
var _wo: PackedInt32Array = []       # where each layer's weights start
var _bo: PackedInt32Array = []       # where each layer's biases start


func _init(seed := 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var at := 0
	for l in sizes.size() - 1:
		_wo.append(at)
		at += sizes[l] * sizes[l + 1]
		_bo.append(at)
		at += sizes[l + 1]
	w.resize(at)
	for l in sizes.size() - 1:
		var spread := sqrt(2.0 / sizes[l])   # (He: keeps ReLU layers from fading out)
		for k in sizes[l] * sizes[l + 1]:
			w[_wo[l] + k] = rng.randfn(0.0, spread)


## The odds for situation `x`: MOVES probabilities (summing to 1), then each flag's.
func predict(x: PackedFloat32Array) -> PackedFloat32Array:
	var acts := _forward(x)
	return _odds(acts[acts.size() - 1])


## One step of learning from one moment (`y`: DoppelSense.label). Returns its loss.
func learn(x: PackedFloat32Array, y: PackedFloat32Array, rate: float) -> float:
	var acts := _forward(x)
	var layers := sizes.size() - 1
	var p := _odds(acts[layers])
	# the error at the outputs: softmax cross-entropy for the move, a
	# sigmoid's for each flag (both come out as odds minus what happened)
	var grad := PackedFloat32Array()
	grad.resize(p.size())
	var move := int(y[0])
	var loss := -log(maxf(p[move], 1e-7))
	for o in p.size():
		var truth := (1.0 if o == move else 0.0) if o < MOVES else y[o - MOVES + 1]
		grad[o] = p[o] - truth
		if o >= MOVES:
			loss -= log(maxf(p[o] if truth > 0.5 else 1.0 - p[o], 1e-7))
	for l in range(layers - 1, -1, -1):
		var a := acts[l]
		var n_in := sizes[l]
		var row0 := _wo[l]
		var bo := _bo[l]
		var back := PackedFloat32Array()
		back.resize(n_in)
		for o in sizes[l + 1]:
			var g := grad[o]
			if g == 0.0:
				continue
			var row := row0 + o * n_in
			for k in n_in:
				back[k] += w[row + k] * g
				w[row + k] -= rate * g * a[k]
			w[bo + o] -= rate * g
		if l > 0:
			for k in n_in:
				if a[k] <= 0.0:
					back[k] = 0.0   # (ReLU: nothing flows back through a unit that was off)
			grad = back
	return loss


func _forward(x: PackedFloat32Array) -> Array[PackedFloat32Array]:
	var acts: Array[PackedFloat32Array] = [x]
	var layers := sizes.size() - 1
	for l in layers:
		var a := acts[l]
		var n_in := sizes[l]
		var z := PackedFloat32Array()
		z.resize(sizes[l + 1])
		for o in z.size():
			var s := w[_bo[l] + o]
			var row := _wo[l] + o * n_in
			for k in n_in:
				s += w[row + k] * a[k]
			z[o] = s if l == layers - 1 else maxf(s, 0.0)
		acts.append(z)
	return acts


func _odds(z: PackedFloat32Array) -> PackedFloat32Array:
	var p := z.duplicate()
	var top := z[0]
	for o in MOVES:
		top = maxf(top, z[o])
	var sum := 0.0
	for o in MOVES:
		p[o] = exp(z[o] - top)
		sum += p[o]
	for o in MOVES:
		p[o] /= sum
	for o in range(MOVES, z.size()):
		p[o] = 1.0 / (1.0 + exp(-z[o]))
	return p


## Train on `rows` (DoppelData: each moment's INPUTS then its LABELS), a
## few passes, holding a tenth back (never learned from) to measure honestly
## how often it does what you did: {net, likeness (its move matches yours,
## on the held-back moments), baseline (always guessing your most common
## move), flags (its other calls that match yours), moments}.
static func train(rows: PackedFloat32Array, passes := 3, rate := 0.01, seed := 1) -> Dictionary:
	var net := DoppelNet.new(seed)
	var per := DoppelSense.INPUTS + DoppelSense.LABELS
	var n := rows.size() / per
	var order := range(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	var held := order.slice(0, n / 10)
	var learn_on := order.slice(n / 10)
	for p in passes:
		for i in learn_on:
			net.learn(rows.slice(i * per, i * per + DoppelSense.INPUTS), rows.slice(i * per + DoppelSense.INPUTS, (i + 1) * per), rate)
		learn_on.reverse()   # (a different order each pass)
	var right := 0
	var flags_right := 0
	var counts := {}
	for i in held:
		var x := rows.slice(i * per, i * per + DoppelSense.INPUTS)
		var y := rows.slice(i * per + DoppelSense.INPUTS, (i + 1) * per)
		var p := net.predict(x)
		var best := 0
		for o in MOVES:
			if p[o] > p[best]:
				best = o
		right += 1 if best == int(y[0]) else 0
		counts[int(y[0])] = int(counts.get(int(y[0]), 0)) + 1
		for f in DoppelSense.FLAGS.size():
			flags_right += 1 if (p[MOVES + f] > 0.5) == (y[1 + f] > 0.5) else 0
	var most := 0
	for c in counts.values():
		most = maxi(most, int(c))
	var h := maxf(held.size(), 1.0)
	return {"net": net, "likeness": right / h, "baseline": most / h,
		"flags": flags_right / (h * DoppelSense.FLAGS.size()), "moments": n}


func to_dict() -> Dictionary:
	return {"sizes": Array(sizes), "w": Array(w)}


static func from_dict(d: Dictionary) -> DoppelNet:
	var net := DoppelNet.new()
	var shape := (d.get("sizes", []) as Array).map(func(v): return int(v))   # (JSON reads numbers back as floats)
	if shape != Array(net.sizes) or (d.get("w", []) as Array).size() != net.w.size():
		return null   # (a network of another shape: from an older version)
	net.w = PackedFloat32Array(d.w)
	return net
