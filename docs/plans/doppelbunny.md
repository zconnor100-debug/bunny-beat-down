# The Doppelbunny: a rogue that learned to play like you

**The idea.** After a few matches a new rogue arrives: your own critter in
your outfit, with a cracked-mirror shimmer, named "Doppel-{you}". It was
trained on how you play: where you land, which fights you take, when you run,
how you strafe and which guns you favour. It gets more like you every match,
and the game shows how alike ("plays 71% like you"). To beat it you have to
break your own habits.

**Why it's the portfolio piece.** It's a real imitation-learning pipeline:
recorded data, a trained neural network and an honest held-out accuracy,
running inside the game with no Python needed by players.

## Already in the game (this builds on it)

- Bots and you drive the same controls (`Critter.move_input`, look angles,
  `want_fire`…): "one body, two brains".
- `PlayerProfile` already learns where you land and the range you fight at,
  and the director uses it.
- `AIBrain` already handles moving, pathing, aiming by skill and bursts.

## The key choice: it learns your decisions, not your thumbs

Copying raw stick input makes a jittery bot that drifts off course, a
well-known failure of this kind of learning. Instead, the Doppel learns the
*choices* a bot makes every 0.2 s, and `AIBrain`'s own movement carries them
out.

- **Inputs:** about 30 numbers, all relative to you:
  - your health, armour, ammo, gun in hand and clovers
  - the nearest enemy's distance, direction and health, whether it sees you,
    and how many enemies are near
  - cover nearby, and the Briar's distance and direction
  - time since you were hit, and the match phase
- **Outputs:** what you did next:
  - push, hold, back off, strafe left or right
  - sprint, crouch, go prone, jump
  - heal, loot, head for the safe zone
  - throw a grenade, switch to which gun, club
- **Labels:** a small labeller turns your recorded input into those
  decisions (moving toward the target means push, and so on). It's tested on
  its own.

## Pipeline

1. **Recorder** (`src/ai/doppel/recorder.gd`): 5 samples a second in your
   matches, kept in `user://doppel/` as a ring of the last ~30 matches (a
   few MB).
2. **Network** (`doppel_net.gd`): a small one (30 → 64 → 64 → outputs) in
   plain GDScript, with its weights saved as JSON.
3. **Training:** after each match, on a background thread while you're on the
   results screen and in the Burrow. It runs a few thousand updates and holds
   10% of the samples back to measure the likeness honestly.
4. **The rogue** (`doppel_brain.gd`, extends `AIBrain`):
   - It asks the network what to do every think, and picks by its odds so
     it isn't robotic.
   - It lands where you land and favours your guns (`PlayerProfile`).
   - It arrives after ~3 matches of you, once its held-out score beats a
     no-skill baseline.

## Status (2026-10-28)

Both parts are built, with `tests/test_doppel.gd`.

**Part one: it learns you.** The recorder, the labeller, the network, the
trainer and storage. Every match records your fights (locally) and trains
after the match. On a scripted player ("backs off when hurt; far off, holds
and goes prone; otherwise charges, sprinting"), trained on 2,700 moments in
3.3 s, it matches that player's move 92% of the time on held-back moments.
Always guessing the player's most common move gets 41%. It also matches the
player's other actions, like sprinting and going prone, 98% of the time.

**Part two: it comes for you** (your calls: silent, in a Mirror Match).
- `DoppelBrain` extends `AIBrain`: it lands, loots, paths, aims and shoots
  as any bot, and in a fight asks the network every 0.2 s what you would do,
  picking by its odds. In the arena, trained on the careful player, it goes
  prone at range in about three moments of four, where a bot never does,
  and holds where a bot pushes in. Hurt, it backs off. Trained on a reckless
  player instead, it circles and jumps.
- It looks like you: your critter, fur and outfit under a cracked-mirror
  overlay (`mirror.gdshader`: a silver rim and Voronoi hairline cracks that
  glint), named "Doppel-Bun", carrying your favourite gun, landing at your
  favourite landmark. It never says a word, and the RivalBook keeps nothing
  of it.
- **Mirror Match:** once it has watched 3 matches and plays more like you
  than guessing (by 5 points), a new run gets one Mirror Match stop in its
  middle rows. It's in the lobby, hunting you; beat it down for a boon of
  its own (on top of the goal's).
- Its card heads the Rogues' Gallery: how alike it plays, how you fight as
  it sees it, and how your Mirror Matches went.

## Speed check: done (2026-10-28)

Plain GDScript, one thread, with every weight in one flat
`PackedFloat32Array` written in place, SGD with softmax cross-entropy, on
the Ryzen 9 9900X3D. "Pass" means one pass over 15k samples.

| network | weights | samples/s | one pass over 15k samples |
|---|---|---|---|
| 30 → 32 → 16 | 1,520 | 12,768 | 1.2 s |
| 30 → 64 → 16 | 3,024 | 6,460 | 2.3 s |
| 30 → 64 → 64 → 16 | 7,184 | 3,094 | 4.8 s |

**Decision:** the planned network trains fast enough in plain GDScript on a
background thread after a match, a few passes in 10–20 s. That holds even on
a PC 2–3× slower. No compute shaders, no C++ and no nearest-match fallback
needed.

## First step: a speed check

GDScript is slow at maths. Before building, I'll time training a network
this size in GDScript and report the numbers. If it can't train in a few
seconds after a match, the fallbacks are:

- (a) fewer, better-chosen samples
- (b) Godot compute shaders
- (c) nearest-match play: find the recorded moments most like now and do
  what you did. That needs no training. It's less "neural network", but has
  the same effect.

## Tests

- The recorder writes the agreed inputs. The labeller turns scripted input
  into the right decisions.
- **Learning a known style.** Train on a scripted "player" with one, for
  example "goes prone at long range, backs off below 40 hp":
  - The network predicts its held-out decisions well above chance.
  - In the arena, a Doppel trained on it does those things measurably more
    often than a normal bot.
- Two different scripted styles give two Doppels that behave differently.
- Tests never record into your real data (`BBD_TEST`), and nothing ever
  leaves the computer.

## Size

Large, about a week: the speed check, recorder and labeller, network and
trainer, the rogue and its look, tests, and a gallery card with its likeness
score. It needs no voice: it's silent.

## Your call (answered 2026-10-28)

- **Voice:** silent.
- **When it shows up:** only in a Mirror Match stop on the Trail.
