# The Warren Gazette: the rogues live while you're away

> **Status (2026-10-28):** phase 1 built: `WarrenSim`, `GazettePanel`,
> `tests/test_gazette.gd`. Changes from the plan below, after seeing it run:
> - **Rarer scars that heal.** A beat-down leaves a scar 4% of the time, and
>   off-screen scars heal after 3 days. Otherwise every rogue was scarred
>   within a day, which would cheapen the ones you give (those never heal).
> - **A first edition right away.** The very first paper covers 2 matches,
>   so a new install or update has news.
> - **Varied stories.** Similar stories are spread out, so you don't get six
>   eye patches in a row.
>
> Phase 2 (the voiced headline and gossip lines) waits for the "new lines
> only" voice builds.

**The idea.** Close the game for a day and the rogues keep fighting each other.
When you come back there's a newspaper waiting: who won, who lost an eye to
whom, who's after whom, and who's after *you*. What happened off-screen
carries into your next match.

## Already in the game (this builds on it)

- `RivalBook` keeps bot-vs-bot grudges (`note_bot_beat`), wins, trackers,
  scars and director grudges, but only from matches you're in.
- In a match, a bot goes after one it holds a grudge against first
  (`AIBrain.grudges`), says a feud line when it spots it (`Cast.FEUD_LINES`),
  and the drop's headlines name feuds, the gang and the bounty.

So anything the off-screen season writes into `RivalBook` already shows up in
matches, with no new match code.

## What's new

1. **The off-screen season** (`src/match/warren_sim.gd`). On launch, the time
   since you last played (capped at 7 days) becomes off-screen matches: one
   per 3 hours away, 12 at most. Each is a quick statistical match, not a
   physics one. A lobby of 20–30 rogues meets in rounds:
   - Who runs into whom leans on grudges and aggression.
   - Who wins leans on each rogue's real record: tracked accuracy, damage,
     skill and its favourite gun's range.

   It's seeded from the session times, so the same absence always makes the
   same news, and tests can pin it.
2. **What it writes:** wins, bot-vs-bot beat-downs (new grudges), and scars
   other rogues dealt.
   - Off-screen scars are kept apart from yours (`scars_from: {scar: who}`),
     so the gallery says "eye patch, from Vex" and yours stay yours.
   - A rogue on a winning streak comes back cocky: braver, a bit sloppier.
   - A rogue that got thrashed comes back wary and keeps its distance.
3. **The Gazette** (`src/ui/gazette_panel.gd`). A newspaper page shown before
   the main menu after time away, and kept in the Burrow. It has:
   - a front-page headline and 3–5 stories
   - **Feud Watch:** the hottest grudges
   - **Wanted:** who's after you, and the current bounty
   - **Standings:** off-screen wins

   Stories are built from templates, like `MatchManager.headlines()`. It's
   gamepad-navigable like the other panels.
4. **Voiced** (phase 2):
   - A newsreel announcer voice (one new Maya1 design) reads the headline.
   - Rogues bring up the news when they spot the one who did it: "Vex took
     my eye. Where's Vex?" Each rogue says this in its own voice, reusing
     its existing name clips.

## Tests

- Same absence and seed give the same news. No time away gives no news.
  Over 7 days away is capped.
- Over 2,000 simulated matches, a rogue with better tracked stats wins more
  often than a weak one (a statistical check).
- A grudge made off-screen makes that rogue go after the other first in a
  real match (arena test through `AIBrain`).
- Off-screen scars show in the gallery with who gave them, and don't count
  as yours.
- **Reset all rogues** also clears off-screen history.
- The Gazette panel renders every section, and the pad can navigate it.

## Size

About a day for the season, the storage and the Gazette page. The voiced
headlines add one narrator voice (1–2 h of GPU). The rogues' new lines need
"new lines only" voice builds (see below).

## Your call

- **Pace:** one off-screen match per 3 hours away, at most 12. Faster or
  slower?
- **Retirement:** should rogues ever retire off-screen? The plan says no:
  scars and grudges only.

## Shared with the gang plan: "new lines only" voice builds

Today `build_voices_maya.py` re-records every clip of a rogue, about 30 min
each. It should keep the clips a rogue already has and record only the new
lines, so adding ~10 lines to all 49 rogues costs a few hours, not a day.
