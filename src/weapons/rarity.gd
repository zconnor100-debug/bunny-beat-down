class_name Rarity
## Loot tiers. Higher tiers hit a little harder, hold a little more and reload
## a little faster — enough to make a Golden Carrot LMG worth running for.

enum Tier { BABY, GARDEN, PRIZE, HEIRLOOM, GOLDEN }

const NAMES := ["Baby", "Garden", "Prize", "Heirloom", "Golden"]
const COLORS := [
	Color(0.82, 0.82, 0.78),   # baby — off-white
	Color(0.45, 0.85, 0.35),   # garden — green
	Color(0.35, 0.65, 1.0),    # prize — ribbon blue
	Color(0.72, 0.42, 0.95),   # heirloom — purple
	Color(1.0, 0.78, 0.2),     # golden — gold
]
const DAMAGE := [1.0, 1.07, 1.14, 1.22, 1.3]
const MAGAZINE := [1.0, 1.0, 1.1, 1.2, 1.3]
const RELOAD := [1.0, 0.96, 0.92, 0.88, 0.82]
## Relative drop weights for floor loot / crates.
const FLOOR_WEIGHTS := [40.0, 30.0, 18.0, 9.0, 3.0]
const CRATE_WEIGHTS := [0.0, 30.0, 35.0, 24.0, 11.0]


static func roll(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return weights.size() - 1
