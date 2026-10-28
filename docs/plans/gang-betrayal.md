# Gangs that hunt together, then turn on each other

> **Status (2026-10-28):** built: `Gang`, the gang section of
> `MatchManager`, `AIBrain` pack tactics, `tests/test_gangs.gd`. The new
> lines show as speech bubbles until they're voiced with the "new lines only"
> build. Not built: staying out of each other's line of fire. Gang mates'
> carrots already pass harmlessly through each other, so it would only be
> for looks.

**The idea.** Gangs stop being three bots that happen to drop together. They
hunt like a pack: one pins you down while the others flank, and they call
out where you are and when you're reloading. When the circle closes and only
they're left, the alliance breaks. Someone says "nothing personal" and shoots
their partner in the back, and the one betrayed remembers it.

## Already in the game (this builds on it)

- `MatchManager._form_gang`: up to 3 bots you've made radical (or your
  rivals) drop in together and hunt you, with a gang name on their tags and a
  headline. The Trail's Grudge Match stop forms one from any bot you've made
  Sore.
- Gang mates can't hurt each other (`Critter`: their carrots do 0 damage),
  and they ignore each other (`AIBrain._perceive`).

## What's new

1. **Pack tactics** (`AIBrain`, a new gang section):
   - **Shared sight.** When one spots you, it calls it out, and its mates
     learn roughly where you are (within a couple of metres, for a few
     seconds) without seeing you.
   - **Roles.** The one with the longest gun pins: it holds range and fires
     bursts. The others flank, each to its own side, about 70° around you and
     out of your view.
   - **Timing.** They close in together when one shouts "reloading!" or
     "healing!", because they hear your reload and your clover.
   - They don't stand in each other's line of fire.
2. **Gangs that form mid-match.** Two bots with a common enemy who meet may
   team up for a while, with a quick "truce?" line. The common enemy is you
   when you lead the match in beat-downs, or a bot they both hold grudges
   against. Whether they join depends on personality:
   - grudge-holders and hotheads join
   - sneaks and calm ones work alone

   At most 2 gangs at once.
3. **Betrayal.** Each mate has a loyalty from its personality: nobles and
   calm ones high, sneaks and pranksters low.
   - **What lowers it:** a grudge against a mate, and the prize being close:
     the final circle, few left alive, a mate low on health with its back
     turned.
   - **When it tips:** a voiced line, the gang drops off its name tag, their
     carrots hurt each other again, and the betrayed one holds a grudge
     marked as a betrayal in `RivalBook`.
   - **What the grudge does:** they never gang up again, their feud lines
     mention it, and the Gazette prints it.
4. **Your move.** You can break a gang: beat one down in front of the others,
   and a disloyal mate may cut and run, or turn on its leader.

## New voice lines (about 10 per rogue)

- **Callouts:** "Over here!", "They're reloading!", "Flank left!"
- **Truce:** "Truce? Just till they're down."
- **Betraying:** "Nothing personal."
- **Betrayed:** "You RAT!", and "{them}! I trusted you!" using its existing
  name clips.

These are recorded with the "new lines only" build (see the Gazette plan).

## Tests (headless arena)

- One gang mate sees you, and the others know roughly where you are within
  1 s without seeing you.
- Flankers end up on different sides of you, more than 90° apart, within
  15 s.
- The gang closes in when you reload.
- With fixed seeds:
  - A sneak betrays in the final circle and a noble doesn't.
  - The betrayal is saved, and those two never gang up again.
- Gang mates never hurt each other before a betrayal, and do after.

## Size

Medium, a few days: pack tactics, mid-match gangs, betrayal and tests. Then
the voice lines in one "new lines only" build.

## Your call

- **A truce with you?** Should a rogue ever offer *you* a truce, teaming up
  against its nemesis? It's fun but makes the game less "you against
  everyone". The plan leaves it out unless you want it.
