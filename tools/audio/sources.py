"""Single source of truth for every third-party audio download.

Imported by fetch_sources.py (downloads) and build_audio.py (credits).
Only CC0 / CC BY sources are allowed here -- see docs/ASSET_PIPELINE.md.
"""

CC0 = ("CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/")
CC_BY_4 = ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/")
CC_BY_3 = ("CC BY 3.0", "https://creativecommons.org/licenses/by/3.0/")

# Kenney.nl audio packs (all CC0). The zip URLs are the "Download" links on each
# asset page; the hashed path segment is how kenney.nl versions its files.
KENNEY_PACKS = {
    "impact-sounds": {
        "title": "Impact Sounds",
        "zip": "https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip",
    },
    "interface-sounds": {
        "title": "Interface Sounds",
        "zip": "https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip",
    },
    "rpg-audio": {
        "title": "RPG Audio",
        "zip": "https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip",
    },
    "sci-fi-sounds": {
        "title": "Sci-fi Sounds",
        "zip": "https://kenney.nl/media/pages/assets/sci-fi-sounds/6b296f9ecf-1677589334/kenney_sci-fi-sounds.zip",
    },
    "casino-audio": {
        "title": "Casino Audio",
        "zip": "https://kenney.nl/media/pages/assets/casino-audio/2472606a04-1721639069/kenney_casino-audio.zip",
    },
    "ui-audio": {
        "title": "UI Audio",
        "zip": "https://kenney.nl/media/pages/assets/ui-audio/490d233f68-1677590494/kenney_ui-audio.zip",
    },
    "music-jingles": {
        "title": "Music Jingles",
        "zip": "https://kenney.nl/media/pages/assets/music-jingles/f37e530b9e-1677590399/kenney_music-jingles.zip",
    },
}

# Kevin MacLeod (incompetech.com) tracks, CC BY 4.0. Metadata (title, ISRC,
# filename, bpm, length) comes from incompetech's own catalogue
# (https://incompetech.com/music/royalty-free/pieces.json). The mp3 link is the
# official download link from each track page.
INCOMPETECH_BASE = "https://incompetech.com/music/royalty-free/mp3-royaltyfree/"
INCOMPETECH_PAGE = "https://incompetech.com/music/royalty-free/index.html?isrc="


def _track(title, isrc, filename, out_file, slot, why):
    return {
        "title": title,
        "isrc": isrc,
        "mp3": INCOMPETECH_BASE + filename.replace(" ", "%20"),
        "page": INCOMPETECH_PAGE + isrc,
        "cache_name": filename,
        "file": out_file,  # path relative to assets/audio/
        "slot": slot,
        "why": why,
    }


MUSIC = [
    _track("Monkeys Spinning Monkeys", "USUAN1400011", "Monkeys Spinning Monkeys.mp3",
           "music/menu_monkeys_spinning_monkeys.mp3", "menu",
           "Bright flutes + pizzicato strings, 144 bpm, written to loop cleanly: "
           "instantly says 'cartoon woodland' while you sit in the lobby."),
    _track("Run Amok", "USUAN1400024", "Run Amok.mp3",
           "music/match_run_amok.mp3", "match",
           "Full-orchestra comedy-action chase (148 bpm, tuba/brass/marimba): "
           "high energy for the mid-match scramble without losing the silliness."),
    _track("Scheming Weasel (faster version)", "USUAN1100085", "Scheming Weasel faster.mp3",
           "music/match_scheming_weasel.mp3", "match",
           "Sneaky-but-bouncy woodwinds and glockenspiel at 168 bpm -- a cartoon "
           "'villain on tiptoes' feel for stalking critters through the grass."),
    _track("Bushwick Tarantella", "USUAN1300002", "Bushwick Tarantella.mp3",
           "music/match_bushwick_tarantella.mp3", "match",
           "Breakneck 215 bpm accordion/clarinet tarantella -- frantic, bright, "
           "acoustic; ideal for the final briar-storm circle."),
    # the Hamster Cage's own genre: toy-box chiptune (plastic toys, a wind-up plane)
    _track("Pixel Peeker Polka - faster", "USUAN1100833", "Pixel Peeker Polka - faster.mp3",
           "music/cage_pixel_peeker_polka.mp3", "match_cage",
           "Bouncy 144 bpm chiptune polka -- an 8-bit toy box that never sits still: "
           "the Hamster Cage's busy, silly scramble between the wheel and the tubes."),
    _track("Itty Bitty 8 Bit", "USUAN1100764", "Itty Bitty 8 Bit.mp3",
           "music/cage_itty_bitty_8_bit.mp3", "match_cage",
           "Bright little 108 bpm square-wave tune: wind-up-toy cheer for looting the "
           "seed bowl and the hamster huts."),
    _track("Voxel Revolution", "USUAN2000025", "Voxel Revolution.mp3",
           "music/cage_voxel_revolution.mp3", "match_cage",
           "Grooving 122 bpm synth-pop chiptune with a driving beat: keeps the cage's "
           "toy-box sound but pushes harder for the final circles."),
    # Toy Box Bash: toy-box music in a kid's bedroom (no brass: the owner found
    # the trumpets in the old marches grating)
    _track("Vivacity", "USUAN1400052", "Vivacity.mp3",
           "music/toybox_vivacity.mp3", "match_toybox",
           "Happy, peppy 142 bpm vibraphone, bass, organ and percussion: bouncing "
           "round the bedroom floor between the toys."),
    _track("March of the Spoons", "USUAN1700008", "March of the Spoons.mp3",
           "music/toybox_march_of_the_spoons.mp3", "match_toybox",
           "Humorous 85 bpm woodwind-and-strings march, tin-soldier stiff and silly: "
           "sneaking through the dollhouse and the brick city."),
    _track("Divertimento K131", "USUAN1100533", "Divertimento K131.mp3",
           "music/toybox_divertimento_k131.mp3", "match_toybox",
           "Mozart's Divertimento arranged for bells, chimes, harp and celesta, 138 bpm: "
           "the bright tinkle of a music box in the toy chest."),
    _track("Fiddles McGinty", "USUAN1400051", "Fiddles McGinty.mp3",
           "music/victory_fiddles_mcginty.mp3", "victory",
           "Driving Celtic folk-rock reel (174 bpm, D major; uilleann pipes, recorder, guitar, "
           "bass, rock backbeat) that hits full tilt from the first bar: a cool, triumphant "
           "woodland-festival victory lap. victory_fanfare is written in its key and locked to "
           "its beat grid, so the rock sting plays straight into it."),
]


# OpenGameArt.org audio (real recordings under the weapons, impacts, gore and
# footsteps). Each entry's licence was checked on its OGA page (and in the pack
# where it has any text) -- only CC0 / CC BY allowed.
# "archive" is zip | 7z | None (single file).
_OGA_FILES = "https://opengameart.org/sites/default/files/"
# Independent.nu sound bank (Johannes Pinter), submitted to OpenGameArt by
# qubodup: CC0 on each OGA page; the author's original release granted
# "completely free rights". The archives hold only audio files, no licence text.
_INU = {
    "author": "Independent.nu (submitted to OpenGameArt by qubodup)",
    "author_url": "https://web.archive.org/web/20100307021017/http://www.johannespinter.com/inu/ljudbank.htm",
    "archive": "7z",
    "license": CC0,
}
OGA = {
    "free-firearm-sound-library": {
        "title": "The Free Firearm Sound Library, Prepared set",
        "author": "Ben Jaszczak, et al. (The Free Firearm Sound Library team)",
        "author_url": "https://web.archive.org/web/20141217041948/http://freefirearmsfx.com/",
        "page": "https://opengameart.org/content/the-free-firearm-sound-library",
        "url": "https://opengameart.org/sites/default/files/Prepared%20SFX%20Library.7z",
        "archive": "7z",
        "license": CC0,
    },
    "baradari-explosions": {
        "title": "2 High Quality Explosions",
        "author": "Michel Baradari",
        "author_url": "http://apollo-music.de",
        "page": "https://opengameart.org/content/2-high-quality-explosions",
        "url": "https://opengameart.org/sites/default/files/explosions.7z",
        "archive": "7z",
        "license": CC_BY_3,
    },
    "baradari-launches": {
        "title": "4 projectile launches",
        "author": "Michel Baradari",
        "author_url": "http://apollo-music.de",
        "page": "https://opengameart.org/content/4-projectile-launches",
        "url": "https://opengameart.org/sites/default/files/launches.7z",
        "archive": "7z",
        "license": CC_BY_3,
    },
    "tinyworlds-different-steps": {
        "title": "Different steps on wood, stone, leaves, gravel and mud",
        "author": "TinyWorlds (recorded by kddekadenz)",
        "author_url": "https://opengameart.org/users/tinyworlds",
        "page": "https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud",
        "url": _OGA_FILES + "%5Bkdd%5DDifferentSteps_0.zip",
        "archive": "zip",
        # page: CC0 (recordings from pdsounds.org, public domain); inside the pack
        # every file is tagged ALBUM="Public Domain", COMMENTS="Feel free to use this"
        "license": CC0,
    },
    "independent-nu-squish": dict(_INU, **{
        "title": "8 wet squish, slurp impacts",
        "page": "https://opengameart.org/content/8-wet-squish-slurp-impacts",
        "url": _OGA_FILES + "independent_nu_ljudbank-wet_squish_slurp_impacts.7z"}),
    "independent-nu-splatter": dict(_INU, **{
        "title": "2 wooden squish splatter sequences",
        "page": "https://opengameart.org/content/2-wooden-squish-splatter-sequences",
        "url": _OGA_FILES + "independent_nu_ljudbank-extreme_splatter.7z"}),
    "independent-nu-break-crunch": dict(_INU, **{
        "title": "5 break, crunch impacts",
        "page": "https://opengameart.org/content/5-break-crunch-impacts",
        "url": _OGA_FILES + "independent_nu_ljudbank-break_crunch_impact.7z"}),
    "independent-nu-wood-crack": dict(_INU, **{
        "title": "35 wooden cracks/hits/destructions",
        "page": "https://opengameart.org/content/35-wooden-crackshitsdestructions",
        "url": _OGA_FILES + "independent_nu_ljudbank-wood_crack_hit_destruction.7z"}),
    "qubodup-rustle": {
        "title": "20 rustles dry leaves",
        "author": "qubodup (Iwan Gabovitch)",
        "author_url": "https://opengameart.org/users/qubodup",
        "page": "https://opengameart.org/content/20-rustles-dry-leaves",
        "url": _OGA_FILES + "qubodup-rustle.7z",
        "archive": "7z",
        "license": CC0,
    },
    # real rat squeaks (edited from CC0 Freesound recordings): critter death cries
    "qubodup-squeaky-rat": {
        "title": "Squeaky Rat",
        "author": "qubodup (Iwan Gabovitch)",
        "author_url": "https://opengameart.org/users/qubodup",
        "page": "https://opengameart.org/content/squeaky-rat",
        "url": _OGA_FILES + "qubodupSqueakyRat.7z",
        "archive": "7z",
        "license": CC0,
    },
}
