# Audio review checklist

What each sound is *meant* to sound like. Use it for a listening pass: play a
match, note any key that misses, then tune it in `tools/audio/recipes.py` and
rebuild only that key:

```bash
/snap/bin/blender -b --factory-startup --python-exit-code 1 \
  --python tools/audio/build_audio.py -- --only pistol_fire,smg_fire
```

Run a full build afterwards so `assets/audio/manifest.json` and the credits are
rewritten. Volume balance between groups is usually easier to fix with the
Music/SFX buses (Settings → volume) than by re-rendering.

## Weapons

| key | should sound like |
|---|---|
| `pistol_fire` (3) | real 9 mm handgun: sharp snappy crack, hint of slide clack, ~0.4 s outdoor tail |
| `smg_fire` (4) | tight, bright, light pops, almost no tail; 900 rpm bursts stay crisp |
| `rifle_fire` (3) | AR-15-style: sharp crack + body thump, one slap-back echo, ~0.7 s tail |
| `lmg_fire` (4) | heavier, chunkier 7.62 shots, lower than the rifle, faint belt rattle, ~0.3 s each |
| `shotgun_fire` (3) | 12-gauge pump: big boom, low-end punch, long rolling outdoor tail (~1.5 s) |
| `sniper_fire` (2) | .30-06 bolt rifle: huge crack + deep boom, long rolling echo (~2.6 s) |
| `rocket_fire` (2) | deep whoosh-thump back-blast, motor roaring away, crackly sizzle |
| `rocket_whoosh_loop` | steady sputtery rocket roar, seamless loop |
| `explosion` (3) | real-sounding blast: low boom, crunchy body, debris pattering down (~2 s) |
| `shotgun_pump` (2) | "chk-chk", slide back then forward |
| `sniper_bolt` | four-step bolt cycle: lift, pull, push, lock |
| `scope_in` | soft rising "zip" with a tiny click |
| `reload_start` / `reload_end` | cloth rustle + mag pop out / mag slap + latch snap |
| `dry_fire` | small dry metallic click |
| `weapon_swap` (2) | strap rustle ending in a latch click |

## Impacts and gore

| key | should sound like |
|---|---|
| `carrot_impact_dirt` (3) | soft thud with a dirt-and-grass crunch |
| `carrot_impact_wood` (3) | woody thunk with a little splinter |
| `carrot_impact_flesh` (3) | wet, meaty thunk with a squelch |
| `headshot` (2) | comedic hollow BONK / cork-style POP |
| `gore_splat` (3) | meaty splat, squish, droplet plips |
| `gore_limb_pop` (3) | cork-like POP, squelch, droplets |
| `body_fall` (3) | heavy thud on leaves with a small bounce |

## Movement, pickups, critters

| key | should sound like |
|---|---|
| `footstep_grass` (5) | light, slightly high grass steps |
| `hop` (3) | subtle cartoon spring "boing" per bunny hop (must not get annoying) |
| `jump` / `land` (3) | quick upward whoosh / soft thud with leaf crunch |
| `glider_open` (2) | fabric snap, canopy whump, brief flutter |
| `pickup_*`, `crate_open` | small clatters and rising plucks / chimes; crate = creak + sparkle |
| `armor_break` (2) | cracking crunch, two shell tinks, sad falling "bwoo" |
| `hurt_squeak` (6) / `death_squeak` (3) | short critter pain squeaks / falling wails and a slide whistle |

## Ambience, storm, UI, music

| key | should sound like |
|---|---|
| `ambient_forest_loop` | breeze, leaves, crickets, occasional birds (10 s loop) |
| `wind_loop` | gusty high-altitude wind (balloon ride) |
| `storm_loop` / `storm_damage_tick` | rumble, swirling wind, thorny crackle / scratch-prick |
| `ui_click`, `ui_hover`, `kill_confirm` | clean click, soft tick, bright satisfying ding |
| `victory_fanfare` / `defeat_sting` | pizzicato run + "da-da-DAAA" / sax "wah-wah-waaah" |
| Music | menu "Monkeys Spinning Monkeys"; match "Run Amok", "Scheming Weasel", "Bushwick Tarantella"; victory "Fluffing a Duck" (Kevin MacLeod, CC BY 4.0) |
