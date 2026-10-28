# Your arsenal: guns and upgrades for gangs and your Doppelbunny

**The idea.** Gangs hunt you as a pack, and your Doppelbunny fights the way
you do. Three new guns, yours alone, and a few upgrades give you answers to
both. No bot ever carries these guns, and they're never found lying about,
so a gang never turns one on you.

## The guns

All three are built like the others: generated in Blender from code
(`tools/weapons`), carrots and all, from CC0/CC-BY scans.

- **Carrot Cruncher (minigun).** Six spinning carrot barrels. Hold the
  trigger to spin up (about 0.7 s, with a rising whine), then 1,200 carrots
  a minute from a 150-carrot belt. You walk slowly and can't sprint while it
  spins, and the spread tightens the longer it keeps spinning. It shreds a
  gang that rushes you, but it's poor at range. Spinning it up gives you
  away, and the bots hear it.
- **Carrot Lobber (grenade launcher).** A six-shot drum of explosive
  carrots, lobbed in an arc. Each bounces once and bursts on a critter or
  after 1.5 s, knocking critters down in the blast. It flushes a pack out
  of cover and breaks up flankers before they reach your sides.
- **Big Root .50 (anti-materiel rifle).** Five-round bolt action. Its slug
  goes through a critter and through thin cover (fences, crates, cardboard
  walls), takes limbs off, and beats down anyone under full armour with one
  chest hit. The recoil is huge, and it sways unless you crouch or go prone.
  It's the answer to a Doppelbunny that holds back at range.

## The upgrades

- **Gang Buster (boon).** Beat a gang member down and its mates panic for 3
  seconds: they stagger and scatter, and the pack is broken for a moment.
- **Pack Sense (Workshop).** When a gang member calls you out, the whole
  gang shows through walls for 2 seconds.
- **Habit Breaker (boon).** Your Doppelbunny predicts you from your habits.
  While you do something you rarely do (under 15% of your moments, from its
  own data), its odds are scrambled and it hesitates. "It didn't see that
  coming."
- **Cardboard You (gadget).** A cardboard cut-out of your critter. Gangs and
  your Doppelbunny shoot at it for 4 seconds.

## How you'd get them (your call)

- **(a) Recommended: unlock and call in.** Unlock each gun in the Workshop
  with acorns. Then, once a match, when a gang is hunting you or your
  Doppelbunny has seen you, call in a drop: a crate lands near you with
  your pick. That makes them answers to gangs and the Doppelbunny, not an
  everyday loadout.
- **(b) Rare loot only you can pick up.** Found in chests now and then;
  bots walk past them.
- **(c) Trail rewards.** Beat a Grudge Match or a Mirror Match and one is
  your keepsake for the next stop.

## Also your call

- **Can your Doppelbunny carry them?** If the Cruncher becomes your
  favourite gun, should your Doppelbunny bring one too ("it even brought
  your minigun"), or stay with ordinary guns?
- **Names:** Carrot Cruncher, Carrot Lobber, Big Root .50. Keep these, or
  pick others?

## Under the hood

- `WeaponData` gains `player_only` (bots skip it in `_find_loot`, loot
  never rolls it), `spin_up` (the Cruncher), and `pierce` / `pierce_cover`
  (the .50). The Lobber reuses the grenade's arc and blast code.
- `DoppelSense.GUN_CLASS` learns the new guns (Cruncher close, Lobber
  blast, .50 far), so your Doppelbunny reads them like any other gun.
- Tests: spin-up and the belt, slowed while spinning; the Lobber's bounce
  and blast; the .50 through a critter and a crate; bots never pick them
  up; each upgrade's effect; the call-in, once a match.

## Size

About a week: the three gun builders and their previews, firing code and
sounds, the four upgrades, the call-in, tests, and a trailer shot.
