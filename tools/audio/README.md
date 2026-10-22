# tools/audio — sound effects, music and audio credits

Builds everything in `assets/audio/` plus `assets/credits/audio.json`.
Every sound is CC0 (Kenney.nl; via OpenGameArt: The Free Firearm Sound Library,
Independent.nu wet / crunch / wood-crack impacts, qubodup's dry-leaf rustles and
squeaky rat, TinyWorlds' leaf footsteps), CC BY 3.0 (Michel Baradari via
OpenGameArt: rocket launch + explosion layers), CC BY 4.0 (Kevin MacLeod, music
only) or original synthesis written here (MIT, project).

Weapon fire sounds are built around real near-perspective firearm recordings
(one gun model per weapon class, several takes = variants), given extra punch
with synthesized thump/crack/body layers that never turn the crack down,
outdoor slap-back echoes + reverb tails, and only a faint Kenney wood "carrot
crunch" underneath. Gun handling (pump, bolt, reloads, swap) cuts the real
Model 12 / Marlin 336 strokes out of the same library and adds synthesized
metal/polymer part models.

## Review (listen + leave notes)

```sh
python3 tools/audio/review.py          # opens the review player in your browser
python3 tools/audio/review.py --summary          # print your saved notes as Markdown
python3 tools/audio/review.py --install-launcher # Desktop shortcut + app-menu entry (--remove-launcher undoes it)
```

The review player lists every manifest sound with a play button per variant,
a waveform with a playhead, length / peak / RMS readouts, what it should sound
like and when the game plays it (from `review_checklist.json`). Guns can be
fired as a burst at the weapon's real rate of fire (with the game's ±6 % pitch
variation), loops play seamlessly so you can hear the seam, and music tracks
are seekable. Mark each sound Good / Tweak / Replace, flag bad takes and write
notes: everything autosaves to `review_notes.json` (git-ignored) so the next
build can act on it. `review.py --check` (run in CI) fails if the checklist and
the manifest disagree; `--write-doc` regenerates `docs/AUDIO_REVIEW.md`.

The server is standard-library Python, binds to 127.0.0.1 only, serves just the
page and the manifest's audio files, refuses requests made by other web pages
(foreign Host, Origin or Sec-Fetch-Site headers), reads each request body in
full before answering and closes the connection after any error (or a doubled
`Content-Length`), drops connections that haven't sent a whole request within
30 s, and only ever writes the notes file. It keeps the file as it was at
startup as `.bak`, moves a damaged file aside as `.corrupt-<time>`, and keeps
the original of a file it had to tidy up (odd entries, or top-level fields it
doesn't use) as `.repaired-<time>`. While `review_checklist.json` or the manifest
can't be read (a typo, a build half-way through writing it) it keeps serving the
last good sound list, says so in the page, and saves carry on. Saves
are field-level changes merged per sound (`POST /api/notes` with
`{"changes": {key: {"verdict"|"note"|"bad_add"|"bad_remove"|"bad_variants"|"heard": …} | null}}`),
so two tabs never erase each other's edits; each key is saved or refused on its
own (`"rejected": {key: reason}` in the reply), and deleting a note that is
already gone is fine. A tab's last-chance save as it closes also carries a
`"save_id"`; `/api/data` lists the ones the server applied under `"delivered"`
(with `"started"`, when the server started), so the next visit knows whether
that save arrived.

The page sends only what changed (against an older `review.py`, without
`"protocol": 2` in `/api/data`, it sends whole entries as before), re-reads the
notes and reloads rebuilt sounds whenever you switch back to its tab, and keeps
edits that haven't reached the file in the browser, one backup slot per tab: a
closed tab's edits are restored on the next visit unless the file has a newer
change for that sound (an edit the closing tab already delivered is never
re-applied, so undoing it elsewhere sticks). Edits the server refuses, or that
weren't restored, are named in the page (also after a reload, until you close
that line) and kept under `not_saved` in Download notes. Only one tab per browser
holds the presence connection that `--idle-exit` watches. After a mouse click on
a toolbar control, Space and Enter go back to playing the highlighted sound; a
control reached with Tab keeps them.

**Rebuilt sounds** (save protocol 3). `/api/data` gives every audio file a
content fingerprint, `"h"` (the first 16 hex digits of its sha256, cached by
size + mtime; `""` if the file is missing). Whenever a sound gets a verdict, its
note records the fingerprints of that sound's files as `"heard"`
(`{"sfx/hop_1.ogg": "<16 hex>", …}`); a change can also say `"heard": true`
("I listened to it as it is now"; any other value is refused for that sound).
A sound with a verdict whose file's fingerprint isn't the one `"heard"` recorded
(or a take that isn't in it at all, like a new `hop_5`) is **rebuilt since your
review**: the page marks it (badge, "new" on each rebuilt take, the old verdict
shown as earlier), counts it as not reviewed (To review, the progress line, `U`)
until it gets a verdict again — any verdict button, the earlier one included,
gives the new version that verdict — and `--summary`, Copy summary and Download
notes add "rebuilt since this verdict (takes 2, 3)" ("new file" for music).
Editing only the note or the flags leaves the mark. A flag on a rebuilt take is
shown as earlier too, and the new verdict clears it unless you click that ⚑ to
flag the new take. Before a verdict is saved the page checks the sound's
fingerprints once more: if the sound was rebuilt after the page last loaded it,
the verdict is held back (it was given to the build before) and the page says
to listen again. Notes saved before
`"heard"` existed take theirs from `review_baseline.json` next to the notes file
(git-ignored too; `{"about": …, "files": {"sfx/x.ogg": "<sha256>", …}}`, only ever read; an
unreadable one is ignored with a warning); that fill-in is written with the next
save. Against an older `review.py` (protocol 1 or 2) the page marks nothing,
never sends `"heard"`, and says to close the tab and reopen Audio Review once the
old server has stopped.

## Rebuild

```sh
# 1. download raw sources into tools/_cache/audio/ (git-ignored, re-runnable;
#    includes the ~194 MB Free Firearm Sound Library archive)
python3 -I tools/audio/fetch_sources.py            # or: ... kenney | oga | music

# 2. render all SFX, copy the music, write manifest + credits (takes ~3 s)
/snap/bin/blender -b --factory-startup --python-exit-code 1 \
    --python tools/audio/build_audio.py

# iterate on a few keys without touching manifest/credits
/snap/bin/blender -b --factory-startup --python-exit-code 1 \
    --python tools/audio/build_audio.py -- --only hop,headshot
```

There is no system ffmpeg/sox/oggenc, so the build runs inside Blender's Python:
it ships numpy, and its `aud` (Audaspace) module decodes Kenney's `.ogg` files and
encodes our output through Blender's bundled FFmpeg. Builds are deterministic
(every random generator is seeded from the key and variant number).

## Files

| file | what it does |
|---|---|
| `sources.py` | every third-party source: Kenney pack zip URLs, OpenGameArt recordings (page, archive URL, author, licence), incompetech tracks (title, ISRC, slot, why it was picked) |
| `fetch_sources.py` | downloads + safely extracts sources into `tools/_cache/audio/` (zip via `zipfile`, 7z via the system libarchive through ctypes) |
| `dsp.py` | small numpy DSP kit: FFT/STFT filters, shelf and causal high-pass, varispeed, reverb, Karplus-Strong pluck, bells, compressor / look-ahead squash / limiter / oversampled soft clipper and waveshaper, seamless-loop helpers (incl. exactly periodic filters, reverb, compressor), K-weighted loudness normaliser |
| `blocks.py` | synthesized building blocks: thumps, gunshot kick/snap/noise body, noise bursts, cork pops, bonks, boings, squelches, wet grains, struck-object modes, droplets, crackles, twig snaps, whooshes, gun-part foley (noise-modal bodies, hits, scrapes), modal harp, wooden flute, clock tick, formant critter voices (squeaky + gritty), birds, crickets |
| `recipes.py` | one function per manifest key (`@recipe(key, variants, loud, src)`) layering Kenney clips, OpenGameArt recordings and synth blocks, plus the per-section helpers (gunshot punch kit, gun-foley kit, impact glue, footstep cuts, storm layers, the victory sting's rock band) |
| `build_audio.py` | runs every recipe, trims/fades/normalises, writes OGGs, `manifest.json` and `assets/credits/audio.json`; also imports any `recipes_wip_*.py` (see below) |
| `analyze.py` | measures rendered sounds without listening (length, peak, loudness, centroid, low-end share, punch/attack, decay), with deltas against an older copy and before\|after spectrogram PNGs |
| `review.py`, `review_page/`, `review_checklist.json` | the listening/notes tool above and the expected-sound checklist it (and `docs/AUDIO_REVIEW.md`) is built from |

## Output conventions

* `assets/audio/sfx/<key>.ogg` or `<key>_<n>.ogg` (variants) — mono, 44.1 kHz Ogg
  Vorbis, ≤ 3 s for one-shots, ≤ 10 s for loops. The game should pick a random
  variant per play (and can add ±5 % pitch jitter).
* **Keys ending in `_loop` are seamless loops** (`rocket_whoosh_loop`, `wind_loop`,
  `storm_loop`, `ambient_forest_loop`). Their `.ogg.import` files have `loop=true`;
  if those are ever regenerated (Godot's default for OGG is looping off), set
  `(stream as AudioStreamOggVorbis).loop = true` at load time instead.
* Levels are pre-balanced with a K-weighted short-term loudness target per key
  (weapons/explosions ≈ −8…−11 dB, impacts/gore ≈ −11…−13, pickups/voices ≈ −14,
  movement ≈ −17…−20, UI ≈ −20…−26, ambience loops ≈ −16…−24). Peaks never exceed
  −1 dBFS. Fine-tune in Godot with audio buses rather than by re-rendering.
* `match_countdown_go` (the final "GO!" after the countdown beeps) is an extra key
  beyond the original list.
* `assets/audio/music/*.mp3` are the official incompetech MP3s, unmodified.

## Credits

`build_audio.py` writes one credits entry per Kenney pack actually used (with the
output files and the original clip names in `source_files`), one entry for the
synthesized material, and one per music track (with the exact CC BY 4.0
attribution line in `attribution`). Recipes declare `src="synth" | "kenney" |
"mixed"`; Kenney usage is tracked automatically whenever a recipe loads a clip.

## Adding a sound

1. Add a `@recipe("new_key", variants=N, loud=-14, src="mixed")` function to
   `recipes.py` (use `c.k(pack, stem, speed=…, start=…, dur=…)` for Kenney clips,
   `c.rng` for randomness, `mix(min_len, (signal, offset_s, gain_db), …)` to layer).
2. Only sources listed in `sources.py` may be used (`c.k(...)` for Kenney packs,
   `c.o(oga_id, path)` for OpenGameArt recordings -- usage is tracked into the
   credits automatically). New third-party sources must be CC0 or CC BY (check the
   licence on the page *and* inside the pack) and get an entry in `sources.py`;
   `fetch_sources.py` then downloads them from that entry alone.
3. Rebuild (full build, so the manifest and credits are refreshed).

## Iterating on sounds

* **Scratch overrides.** `build_audio.py` imports every `tools/audio/recipes_wip_*.py`
  after `recipes.py`, and registering a key that already exists *replaces* its
  recipe in place (same manifest position). So a sound (or a group of them, even
  by several people at once) can be reworked in its own module without touching
  `recipes.py`: start it with `from recipes import *`, grab any original recipe
  function you still need (`import recipes as _orig; base = _orig.rifle_fire`)
  *before* re-registering, then `@recipe("rifle_fire", …)`. A module that fails to
  import is skipped with a warning. A new source can be registered from there with
  `sources.OGA.setdefault(...)` while iterating. When a rework is accepted, move
  it into `recipes.py` in place (helpers worth reusing into `blocks.py` / `dsp.py`,
  sources into `sources.py`), delete the module and do a full build: the rendered
  files must not change.
* **Build only what you are working on**: `... build_audio.py -- --only key1,key2`
  (never touches the manifest or credits). Add `--out DIR` to write the subset to
  `DIR/sfx/` instead, leaving `assets/audio` (and an open review page) alone while
  you try things. Check determinism by building a key twice and comparing the
  files' md5.
* **Measure, don't guess**: copy `assets/audio/sfx` somewhere first, then

  ```sh
  /snap/bin/blender -b --factory-startup --python tools/audio/analyze.py -- \
      --before /tmp/sfx_before --png /tmp/png key1 key2
  ```

  prints length / peak / loudness / centroid / low% / punch / attack / t20 with
  deltas, and writes before|after log-frequency spectrograms. Its centroid and
  low% use one window over the whole file, so they under-weight a hit at t = 0:
  judge attacks on short windows from the onset instead.
* Keep one-shots ≤ 3 s and loops ≤ 10 s and seamless, use `c.rng` (or a
  fixed-seed generator) for every random choice, and remember that `finish()`
  high-passes at 35 Hz, fades the first 1.5 ms and caps peaks at −1 dBFS: louder
  means a higher `loud` plus a denser sound, not clipping.
