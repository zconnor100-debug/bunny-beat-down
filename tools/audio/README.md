# tools/audio — sound effects, music and audio credits

Builds everything in `assets/audio/` plus `assets/credits/audio.json`.
Every sound is CC0 (Kenney.nl; The Free Firearm Sound Library via OpenGameArt),
CC BY 3.0 (Michel Baradari via OpenGameArt: rocket launch + explosion layers),
CC BY 4.0 (Kevin MacLeod, music only) or original synthesis written here (MIT, project).

Weapon fire sounds are built around real near-perspective firearm recordings
(one gun model per weapon class, several takes = variants), sharpened with
synthesized transient/boom layers, given outdoor slap-back echoes + reverb tails,
and carry only a faint Kenney wood "carrot crunch" underneath.

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
| `sources.py` | every third-party source: Kenney pack zip URLs, incompetech tracks (title, ISRC, slot, why it was picked) |
| `fetch_sources.py` | downloads + safely extracts sources into `tools/_cache/audio/` (zip via `zipfile`, 7z via the system libarchive through ctypes) |
| `dsp.py` | small numpy DSP kit: FFT/STFT filters, varispeed, reverb, Karplus-Strong pluck, bells, seamless-loop helpers, K-weighted loudness normaliser |
| `blocks.py` | synthesized building blocks: thumps, noise bursts, cork pops, bonks, boings, squelches, droplets, crackles, whooshes, formant critter voices, birds, crickets |
| `recipes.py` | one function per manifest key (`@recipe(key, variants, loud, src)`) layering Kenney clips and synth blocks |
| `build_audio.py` | runs every recipe, trims/fades/normalises, writes OGGs, `manifest.json` and `assets/credits/audio.json` |

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
   licence on the page *and* inside the pack) and get an entry in `sources.py`.
3. Rebuild (full build, so the manifest and credits are refreshed).
