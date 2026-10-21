"""Single source of truth for every third-party audio download.

Imported by fetch_sources.py (downloads) and build_audio.py (credits).
Only CC0 / CC BY sources are allowed here -- see docs/ASSET_PIPELINE.md.
"""

CC0 = ("CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/")
CC_BY_4 = ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/")

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
    _track("Fluffing a Duck", "USUAN1100768", "Fluffing a Duck.mp3",
           "music/victory_fluffing_a_duck.mp3", "victory",
           "Short (1:07) goofy trombone/tuba strut -- a triumphant-but-silly "
           "'you are the last bunny standing' victory lap."),
]
