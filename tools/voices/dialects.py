"""Accents by spelling: a line rewritten the way a rogue says it, before the
voice reads it (speech only: the text on screen stays as written). Cartoon
accents for cartoon critters: Brooklyn ("dat", "nuttin'"), a mob boss's
(Brooklyn and then some), Southern or bluegrass ("Ah", "mah", "y'all"),
stage French ("ze", "zis", no h's), Slavic ("ze", "I vill"), Boston ("pahk the cah"), Scottish ("ye
wee", "cannae"), Australian ("mate", no r's), Canadian ("aboot", "eh?"), a
California surfer's ("totally", "gnarly", "...dude"), a vampire's ("I vant")
and a stammer ("W-wait!").

    say("Is that the boss?", "brooklyn")  ->  "Is dat da boss?"
"""
from __future__ import annotations

import re

_WORDS = {
    "brooklyn": {
        "the": "da", "this": "dis", "that": "dat", "these": "dese", "those": "dose", "them": "dem",
        "then": "den", "there": "dere", "they": "dey", "their": "deir", "with": "wit", "think": "tink",
        "thing": "ting", "things": "tings", "nothing": "nuttin'", "something": "somethin'", "you": "ya",
        "your": "ya", "talk": "tawk", "coffee": "cawfee", "going to": "gonna", "want to": "wanna",
        "better": "bettah", "never": "nevah", "over": "ovah", "here": "heah", "forget": "fuhget",
    },
    "southern": {
        "i": "Ah", "i'm": "Ah'm", "i'll": "Ah'll", "i've": "Ah've", "i'd": "Ah'd", "my": "mah", "mine": "mahn",
        "you all": "y'all", "time": "tahm", "right": "raht", "fine": "fahn", "nice": "nahce", "like": "lahk",
        "tonight": "tonaht", "while": "whahl", "fight": "faht", "night": "naht", "ride": "rahd", "hi": "hah",
        "going to": "fixin' to", "you": "ya", "your": "yer", "there": "thar", "here": "hyar",
    },
    "french": {
        "the": "ze", "this": "zis", "that": "zat", "these": "zeez", "those": "zose", "them": "zem",
        "then": "zen", "there": "zere", "they": "zey", "their": "zeir", "with": "wiz", "think": "sink",
        "thing": "sing", "things": "sings", "nothing": "nossing", "something": "somesing", "is": "eez",
        "it": "eet", "it's": "eet's", "his": "'is", "him": "'im", "here": "'ere", "have": "'ave", "has": "'as",
        "how": "'ow", "hello": "'allo", "hit": "'it", "hey": "'ey", "happy": "'appy", "hurt": "'urt",
        "home": "'ome", "help": "'elp", "head": "'ead",
    },
}
_WORDS["boston"] = {
    "car": "cah", "park": "pahk", "yard": "yahd", "hard": "hahd", "smart": "smaht", "start": "staht", "party": "pahty",
    "here": "heah", "for": "fah", "your": "yah", "you're": "yah", "you": "ya",
    "more": "moah", "sure": "shuah", "very": "wicked", "really": "wicked", "four": "fowah", "dork": "dawk",
}
_WORDS["scottish"] = {
    "i": "Ah", "i'm": "Ah'm", "i'll": "Ah'll", "i've": "Ah've", "my": "ma", "you": "ye", "your": "yer", "yourself": "yersel'",
    "no": "nae", "not": "no'", "don't": "dinnae", "can't": "cannae", "won't": "willnae", "didn't": "didnae",
    "isn't": "isnae", "doesn't": "doesnae", "couldn't": "couldnae", "small": "wee", "little": "wee", "yes": "aye",
    "about": "aboot", "out": "oot", "house": "hoose", "down": "doon", "now": "noo", "going to": "gonnae", "what": "whit",
    "from": "fae", "with": "wi'", "all": "a'", "oh": "och", "to": "tae", "do": "dae", "well": "weel", "head": "heid",
    "dead": "deid", "home": "hame", "over": "ower", "never": "niver", "right": "richt", "night": "nicht",
}
_WORDS["australian"] = {
    "pal": "mate", "buddy": "mate", "friend": "mate", "hello": "g'day", "hi": "g'day", "you": "ya", "your": "yer",
    "afternoon": "arvo", "yes": "yeah", "today": "t'day", "never": "nevah",
    "for": "fer", "no": "nah", "really": "real", "very": "bloody",
}
_WORDS["canadian"] = {
    "about": "aboot", "out": "oot", "house": "hoose", "sorry": "sore-y", "about it": "aboot it", "south": "sooth",
    "mouth": "mooth", "shout": "shoot",
}
_WORDS["vampire"] = {
    "want": "vant", "will": "vill", "we": "ve", "what": "vat", "well": "vell", "welcome": "velcome", "wait": "vait",
    "with": "vith", "why": "vhy", "where": "vhere", "when": "vhen", "won't": "von't", "were": "vere", "was": "vas",
    "waiting": "vaiting", "way": "vay", "watch": "vatch", "win": "vin", "world": "vorld", "the": "ze", "evening": "eeevening",
}
_WORDS["slavic"] = {
    "the": "ze", "this": "zis", "that": "zat", "these": "zeez", "those": "zose", "them": "zem", "then": "zen",
    "there": "zere", "they": "zey", "their": "zeir", "think": "tink", "thing": "ting", "things": "tings",
    "nothing": "nossing", "something": "somesing", "with": "vith", "want": "vant", "will": "vill", "we": "ve",
    "what": "vat", "well": "vell", "wait": "vait", "why": "vhy", "where": "vhere", "when": "vhen", "was": "vas",
    "were": "vere", "way": "vay", "watch": "vatch", "win": "vin", "won't": "von't",
}
_WORDS["surfer"] = {
    "really": "totally", "very": "super", "great": "gnarly", "good": "rad", "cool": "rad", "awesome": "epic",
    "friend": "dude", "pal": "bro", "buddy": "bro", "man": "dude", "hello": "hey", "yes": "yeah", "wow": "whoa",
}
_WORDS["gangster"] = dict(_WORDS["brooklyn"], **{"boss": "bawss", "coming": "comin'", "go": "go", "out of": "outta"})
_WORDS["bluegrass"] = _WORDS["southern"]

# -ing endings dropped ("runnin'") where the accent does (not "thing", "king"...)
_DROP_G = {"brooklyn", "gangster", "southern", "bluegrass", "scottish", "australian"}
# no r after a vowel ("fastah", "dahk") where the accent drops it
_NO_R = {"boston", "australian"}
_KEEP_G = {"thing", "things", "king", "ring", "sing", "bring", "string", "spring", "swing", "wing", "sting", "ping", "ding", "ceiling"}


def _case_like(src: str, word: str) -> str:
    if src.isupper() and len(src) > 1:
        return word.upper()
    if src[:1].isupper():
        return word[:1].upper() + word[1:]
    return word


def say(text: str, dialect: str | None) -> str:
    """`text` as a rogue with this accent says it (unchanged for no accent)."""
    if not dialect or (dialect not in _WORDS and dialect != "stammer"):
        return text
    if "<" in text:   # (tags like "<gasp>" are left as they are)
        parts = re.split(r"(<[^>]+>)", text)
        if dialect == "stammer":   # (only the words after the tags)
            i = next((k for k, p in enumerate(parts) if not p.startswith("<") and p.strip()), None)
            if i is not None:
                words = parts[i].lstrip()
                parts[i] = parts[i][:len(parts[i]) - len(words)] + say(words, dialect)
            return "".join(parts)
        return "".join(p if p.startswith("<") else say(p, dialect) for p in parts)
    if dialect == "stammer":
        return _stammer(text)
    words = _WORDS[dialect]
    # two-word phrases first, then single words (whole words only)
    for phrase in sorted((w for w in words if " " in w), key=len, reverse=True):
        text = re.sub(r"\b%s\b" % re.escape(phrase), lambda m, p=phrase: _case_like(m.group(0), words[p]), text, flags=re.I)

    def one(m: re.Match) -> str:
        w = m.group(0)
        low = w.lower()
        if low in words and " " not in low:
            return _case_like(w, words[low])
        for tail in ("'s", "'re", "'ll", "'d", "'ve", "'m"):   # ("that's" -> "dat's")
            if low.endswith(tail) and low[:-len(tail)] in words:
                base = _case_like(w, words[low[:-len(tail)]])
                return (base[:-1] if base.endswith("'") else base) + w[-len(tail):]
        if dialect in _DROP_G and len(low) > 4 and low.endswith("ing") and low not in _KEEP_G:
            return w[:-1] + "'"
        if dialect in _NO_R and len(low) > 2:
            return re.sub(r"(?<=[a-z])er$", "ah", re.sub(r"(?<=[aeo])r(?=[bcdfgklmnpstvz])", "h", w))
        return w
    text = re.sub(r"[A-Za-z][A-Za-z']*", one, text)
    if dialect == "canadian":   # ("Where'd ya go, eh?")
        text = re.sub(r"(\w)([?!.]?)\s*$", lambda m: m.group(1) + ", eh" + (m.group(2) or "."), text, count=1) if len(text.split()) > 2 else text
    if dialect == "surfer" and not re.search(r"\b(dude|bro)\b", text, re.I):   # ("Wipeout, dude!")
        text = re.sub(r"(\w)([?!.]?)\s*$", lambda m: m.group(1) + ", dude" + (m.group(2) or "."), text, count=1) if len(text.split()) > 2 else text
    return text


def _stammer(text: str) -> str:
    """The first word of a longer line stammered, if it starts with a consonant ("W-wait, it's Bun!": "I-Is" came out
    as "I got a knot")."""
    if len(text.split()) < 3:
        return text
    return re.sub(r"^(\W*)([B-DF-HJ-NP-TV-Zb-df-hj-np-tv-z])(?=[a-z'])", lambda m: m.group(1) + m.group(2) + "-" + m.group(2).lower(), text, count=1)


if __name__ == "__main__":
    for d in ["brooklyn", "gangster", "southern", "french", "boston", "scottish", "australian", "canadian", "surfer", "vampire", "slavic", "stammer"]:
        print(d, "|", say("I'm going to get you, Bun! That's the thing about this: nothing's free. Boss coming through!", d))
