#!/usr/bin/env python3
"""Bunny Beat Down — audio review player.

Opens an interactive review page in your browser: every sound in
assets/audio/manifest.json with play buttons for each variant, a waveform,
loudness readouts, what it *should* sound like (tools/audio/review_checklist.json),
gun bursts at each weapon's real rate of fire, seamless-loop playback, and
Good / Tweak / Replace verdicts with notes that save to
tools/audio/review_notes.json (so the next build can act on them).

    python3 tools/audio/review.py                 # start (or reopen) + open the browser
    python3 tools/audio/review.py --idle-exit     # quit once the review tab is closed
    python3 tools/audio/review.py --check         # checklist ↔ manifest consistency (CI)
    python3 tools/audio/review.py --write-doc     # regenerate docs/AUDIO_REVIEW.md
    python3 tools/audio/review.py --summary       # print saved notes as Markdown
    python3 tools/audio/review.py --install-launcher   # Desktop shortcut + app-menu entry

Standard library only. The server binds to 127.0.0.1 (default port 8765, so
the browser's draft backup survives restarts), serves only the page's own files
and the manifest's audio, refuses foreign Host / Origin / Sec-Fetch-Site
headers and framing, reads a request's whole body before answering (and closes
the connection after every error or a doubled Content-Length, so a body can never
be replayed as a second request), drops connections that haven't sent a whole
request within 30 s and caps how many it holds, keeps serving the last good sound
list while the checklist or manifest can't be read, and only ever writes the
notes file:
  * saves are field-level patches ({"changes": {key: {"verdict"…} | null}})
    merged into the file on disk under a lock, so two tabs never erase each
    other's notes, even on the same sound; each key is applied or refused on
    its own ("rejected" in the reply) and deleting a missing note is a no-op;
    a tab's close-time save carries a "save_id", and /api/data lists the ones
    that arrived ("delivered"), so the next visit never re-applies one;
  * a notes file that can't be parsed is moved aside (never overwritten) and the
    page says so; one with entries the player has to tidy up is copied to
    review_notes.json.repaired-<time> first;
  * notes for sounds that left the manifest are kept as "orphans" until deleted;
  * the file as it was when the server started is kept as review_notes.json.bak;
  * every audio file in /api/data has a content fingerprint ("h", the first 16
    hex digits of its sha256), and giving a verdict records the fingerprints of
    that sound's files in its note ("heard"), so a sound rebuilt since its
    verdict is shown as such until it gets a new one. Notes saved before that
    existed take theirs from review_baseline.json next to the notes file
    (read-only; {"files": {audio path: sha256}}).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import select
import shutil
import socket
import sys
import threading
import time
import urllib.request
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
AUDIO_DIR = ROOT / "assets" / "audio"
MANIFEST = AUDIO_DIR / "manifest.json"
CHECKLIST = Path(__file__).with_name("review_checklist.json")
NOTES = Path(__file__).with_name("review_notes.json")
PAGE_DIR = Path(__file__).with_name("review_page")
WEAPONS_DIR = ROOT / "data" / "weapons"
DOC = ROOT / "docs" / "AUDIO_REVIEW.md"

APP_ID = "bbd-audio-review"
DEFAULT_PORT = 8765
VERDICTS = ("good", "tweak", "replace")
MAX_BODY_BYTES = 512 * 1024
MAX_NOTE_CHARS = 4000
MAX_VARIANT = 64
PROTOCOL = 3                # save protocol: 2 = field-level changes + per-key "rejected"; 3 = + fingerprints, "heard"
BASELINE_NAME = "review_baseline.json"   # next to the notes file: what notes saved before "heard" were made on
MAX_HEARD = 64              # files recorded in one note's "heard"
HEX16 = re.compile(r"[0-9a-f]{16}")
HEX64 = re.compile(r"[0-9a-fA-F]{64}")
PRESENCE_GRACE = 20.0       # --idle-exit: seconds with no open review tab (or other use) before stopping
NEVER_CONNECTED = 180.0     # --idle-exit: give up if no tab ever connects
REQUEST_TIMEOUT = 30.0      # a request (line, headers and body) must arrive in full within this long
MAX_CONNECTIONS = 32        # connections served at once (one thread each)
MAX_PRESENCE = 8            # open review tabs tracked at once
MAX_DELIVERED = 64          # ids of close-time saves remembered (a later page asks whether one arrived)
SAVE_ID = re.compile(r"[A-Za-z0-9_-]{1,64}")
CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8", ".ogg": "audio/ogg", ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
}
PAGE_FILES = {"/": "index.html", "/index.html": "index.html", "/app.js": "app.js", "/style.css": "style.css"}
SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": ("default-src 'self'; script-src 'self'; style-src 'self'; "
                                "img-src 'self' data:; media-src 'self' blob:; connect-src 'self'; "
                                "frame-ancestors 'none'; base-uri 'none'; form-action 'none'"),
}


# ---------------------------------------------------------------------------
# data
# ---------------------------------------------------------------------------

def load_json(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        try:
            return json.load(f)
        except ValueError as e:   # name the file: the parser's message doesn't
            raise ValueError(f"{path.name}: {e}") from e


def manifest_sfx(manifest: dict) -> dict[str, list[str]]:
    """key -> list of files (relative to assets/audio), music excluded."""
    out = {}
    for key, files in manifest.items():
        if key == "music":
            continue
        out[key] = [files] if isinstance(files, str) else list(files)
    return out


def manifest_music(manifest: dict) -> list[str]:
    files: list[str] = []
    for slot in manifest.get("music", {}).values():
        for f in ([slot] if isinstance(slot, str) else slot):
            if f not in files:
                files.append(f)
    return files


def parse_tres(path: Path) -> dict[str, str]:
    """Tiny reader for the `key = value` lines of a Godot .tres resource."""
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r'^([a-z_]+) = (.+)$', line.strip())
        if m:
            out[m.group(1)] = m.group(2).strip()
    return out


def _unquote_godot(v: str) -> str:
    return v.lstrip("&").strip('"')


def weapon_bursts() -> dict[str, dict]:
    """sfx key -> how the game fires it (rate, auto, magazine/reload, follow-up sound)."""
    bursts = {}
    for tres in sorted(WEAPONS_DIR.glob("*.tres")):
        w = parse_tres(tres)
        key = _unquote_godot(w.get("sfx_fire", ""))
        if not key:
            continue
        bursts[key] = {
            "weapon": _unquote_godot(w.get("display_name", tres.stem)),
            "rpm": float(w.get("rounds_per_minute", "300")),
            "auto": w.get("fire_mode", "0") == "1",
            "magazine": int(float(w.get("magazine", "12"))),
            "reload_time": float(w.get("reload_time", "1.5")),
            "cycle": _unquote_godot(w.get("cycle_sfx", "")) or None,
            "cycle_delay": 0.45,
        }
    return bursts


def build_catalog() -> dict:
    """Everything the page lists (no notes)."""
    manifest = load_json(MANIFEST)
    checklist = load_json(CHECKLIST)
    sfx = manifest_sfx(manifest)
    bursts = weapon_bursts()
    groups = []
    for g in checklist["groups"]:
        keys = []
        for key, info in g["keys"].items():
            files = sfx.get(key, [])
            keys.append({
                "key": key,
                "expect": info.get("expect", ""),
                "when": info.get("when", ""),
                "loop": key.endswith("_loop"),
                "files": [{"n": i + 1, "file": f, "url": "/audio/" + f} for i, f in enumerate(files)],
                "burst": bursts.get(key),
            })
        groups.append({"id": g["id"], "title": g["title"], "keys": keys})
    music = []
    for f in manifest_music(manifest):
        info = checklist.get("music", {}).get(f, {})
        music.append({"key": "music:" + f, "file": f, "url": "/audio/" + f,
                      "title": info.get("title", Path(f).stem), "expect": info.get("expect", ""),
                      "when": info.get("when", "")})
    return {"groups": groups, "music": music}


class Fingerprints:
    """An audio file's content fingerprint: the first 16 hex digits of its sha256
    ("" if it's missing). Cached by (path, size, mtime_ns), so only a new or
    rebuilt file is ever read again and /api/data stays cheap."""

    def __init__(self):
        self._lock = threading.Lock()
        self._cache: dict[str, tuple[tuple[int, int], str]] = {}
        self.reads = 0   # files hashed so far (the tests check the cache with it)

    def get(self, path: Path, st: os.stat_result | None = None) -> str:
        try:
            st = st or path.stat()
        except OSError:
            return ""
        sig = (st.st_size, st.st_mtime_ns)
        with self._lock:
            hit = self._cache.get(str(path))
        if hit and hit[0] == sig:
            return hit[1]
        digest = hashlib.sha256()
        try:
            with open(path, "rb") as fh:
                for chunk in iter(lambda: fh.read(1 << 20), b""):
                    digest.update(chunk)
            after = path.stat()
        except OSError:
            return ""
        fp = digest.hexdigest()[:16]
        with self._lock:
            self.reads += 1
            if (after.st_size, after.st_mtime_ns) == sig:   # not rewritten while it was read
                self._cache[str(path)] = (sig, fp)
        return fp


FINGERPRINTS = Fingerprints()


def with_versions(catalog: dict, audio_dir: Path = AUDIO_DIR) -> dict:
    """The catalogue plus each audio file's version ("v": size-mtime) and content
    fingerprint ("h", see Fingerprints), both "" if it's missing, read fresh on
    every call: a rebuilt sound keeps its name (and the manifest may not change),
    so the page needs "v" to reload it and "h" to tell whether it is still what
    was reviewed. Doesn't touch the cached catalogue."""
    def info(f: str) -> dict:
        p = audio_dir / f
        try:
            st = p.stat()
        except OSError:
            return {"v": "", "h": ""}
        return {"v": f"{st.st_size:x}-{st.st_mtime_ns:x}", "h": FINGERPRINTS.get(p, st)}
    groups = [{**g, "keys": [{**k, "files": [{**f, **info(f["file"])} for f in k["files"]]} for k in g["keys"]]}
              for g in catalog["groups"]]
    return {**catalog, "groups": groups, "music": [{**m, **info(m["file"])} for m in catalog["music"]]}


def catalog_keys(catalog: dict) -> set[str]:
    keys = {k["key"] for g in catalog["groups"] for k in g["keys"]}
    keys.update(m["key"] for m in catalog["music"])
    return keys


def catalog_files(catalog: dict) -> dict[str, list[str]]:
    """sound key -> its audio files in take order (a music key: its one track)."""
    files = {k["key"]: [f["file"] for f in k["files"]] for g in catalog["groups"] for k in g["keys"]}
    files.update((m["key"], [m["file"]]) for m in catalog["music"])
    return files


def key_fingerprints(files: list[str], audio_dir: Path = AUDIO_DIR) -> dict[str, str]:
    """What a note's "heard" records: {file: fingerprint} of the files there are now."""
    out = {}
    for f in files:
        fp = FINGERPRINTS.get(audio_dir / f)
        if fp:
            out[f] = fp
    return out


def rebuilt_takes(entry: dict, files: list[str], audio_dir: Path = AUDIO_DIR) -> list[int]:
    """Takes (1-based) rebuilt since the entry's verdict: the file exists and its
    fingerprint isn't the one "heard" recorded (or none was recorded for it). An
    entry without a verdict, or without "heard", is never rebuilt. The page
    (rebuiltTakes in app.js) uses the same rule."""
    heard = entry.get("heard")
    if not entry.get("verdict") or not isinstance(heard, dict):
        return []
    out = []
    for n, f in enumerate(files, 1):
        fp = FINGERPRINTS.get(audio_dir / f)
        if fp and heard.get(f) != fp:
            out.append(n)
    return out


def rebuilt_label(key: str, takes: list[int]) -> str:
    """' — rebuilt since this verdict (takes 2, 3)' (a music track: '(new file)'), or ''."""
    if not takes:
        return ""
    what = "new file" if key.startswith("music:") else "takes " + ", ".join(map(str, takes))
    return f" — rebuilt since this verdict ({what})"


def catalog_audio(catalog: dict) -> set[str]:
    files = {f["file"] for g in catalog["groups"] for k in g["keys"] for f in k["files"]}
    files.update(m["file"] for m in catalog["music"])
    return files


class Catalog:
    """build_catalog(), cached and rebuilt whenever an input file changes, so a
    running server always agrees with the manifest it serves. While an input can't
    be read (a half-written manifest, a typo in the checklist) the last good
    catalogue is kept and every call tries again; `error` says why."""

    def __init__(self):
        self._lock = threading.Lock()
        self._stamp = None
        self._data = None
        self.error: str | None = None
        self.keys: set[str] = set()
        self.audio: set[str] = set()
        self.files: dict[str, list[str]] = {}   # key -> its audio files (see catalog_files)

    def _inputs_stamp(self):
        paths = [MANIFEST, CHECKLIST, *sorted(WEAPONS_DIR.glob("*.tres"))]
        return tuple((str(p), p.stat().st_mtime_ns) for p in paths if p.exists())

    def get(self) -> dict:
        with self._lock:
            try:
                stamp = self._inputs_stamp()
                if stamp != self._stamp:
                    data = build_catalog()
                    keys, audio, files = catalog_keys(data), catalog_audio(data), catalog_files(data)
                    self._data, self.keys, self.audio, self.files, self._stamp = data, keys, audio, files, stamp
                self.error = None
            except (OSError, ValueError, KeyError, TypeError, AttributeError) as e:
                # _stamp is left as it was, so the next call tries again
                why = f"{type(e).__name__}: {e}" if isinstance(e, (KeyError, TypeError, AttributeError)) else str(e)
                if why != self.error:
                    print(f"sound list problem: {why}", flush=True)
                self.error = why
                if self._data is None:
                    raise NotesUnavailable(f"Saving is paused because review_checklist.json or the audio manifest "
                                           f"could not be read — {why}. Fix that file and saving carries on.") from e
            return self._data


# ---------------------------------------------------------------------------
# notes (the only thing this tool ever writes)
# ---------------------------------------------------------------------------

class NotesError(Exception):
    """A problem with notes data, in plain words the page can show."""


class NotesUnavailable(NotesError):
    """The notes file itself can't be used right now (not the request's fault)."""


NOTES_FIELDS = ("version", "updated", "keys", "orphans")
ENTRY_FIELDS = ("verdict", "note", "bad_variants", "heard")
CHANGE_FIELDS = ("verdict", "note", "bad_add", "bad_remove", "bad_variants", "heard")


def empty_notes() -> dict:
    return {"version": 1, "updated": None, "keys": {}, "orphans": {}}


def _check_verdict(v: object) -> None:
    if v is not None and (not isinstance(v, str) or v not in VERDICTS):
        raise NotesError("the verdict must be good, tweak, replace or empty")


def _check_note(v: object) -> None:
    if not isinstance(v, str):
        raise NotesError("the note must be text")
    try:
        v.encode("utf-8")
    except UnicodeEncodeError:
        raise NotesError("the note has a broken character in it (a cut-off emoji?)") from None
    if len(v) > MAX_NOTE_CHARS:
        raise NotesError(f"the note is longer than {MAX_NOTE_CHARS} characters")


def _check_takes(v: object) -> set[int]:
    # bool is an int subclass: reject it
    if not isinstance(v, list) or not all(type(n) is int and 1 <= n <= MAX_VARIANT for n in v):
        raise NotesError(f"flagged takes must be a list of take numbers 1-{MAX_VARIANT}")
    return set(v)


def _check_heard(v: object) -> dict[str, str]:
    """A note's "heard": {audio file: 16-hex fingerprint}, at most MAX_HEARD of them."""
    if (not isinstance(v, dict) or len(v) > MAX_HEARD
            or not all(isinstance(f, str) and 0 < len(f) <= 256 and isinstance(fp, str) and HEX16.fullmatch(fp)
                       for f, fp in v.items())):
        raise NotesError("its record of which version of the sound you reviewed ('heard') isn't in the expected format")
    return dict(v)


def _clean_entry(entry: object, strict: bool) -> dict | None:
    """Normalise one stored note entry. strict=True raises NotesError on anything
    that repairing would change or drop (see notes_repairs); strict=False repairs
    what it can (data read from disk)."""
    def bad(e: NotesError):
        if strict:
            raise e

    if not isinstance(entry, dict):
        bad(NotesError("the entry isn't in the expected format"))
        return None
    extra = sorted(str(f) for f in entry if f not in ENTRY_FIELDS)
    if extra:
        bad(NotesError(f"it has fields the player doesn't use ({', '.join(extra)})"))
    verdict = entry.get("verdict")
    try:
        _check_verdict(verdict)
    except NotesError as e:
        bad(e)
        verdict = None
    note = entry.get("note", "")
    try:
        _check_note(note)
    except NotesError as e:
        bad(e)
        note = note if isinstance(note, str) else ""
        note = note.encode("utf-8", "replace").decode("utf-8")[:MAX_NOTE_CHARS]
    raw_bad = entry.get("bad_variants", [])
    try:
        variants = _check_takes(raw_bad)
    except NotesError as e:
        bad(e)
        variants = {n for n in raw_bad if type(n) is int and 1 <= n <= MAX_VARIANT} if isinstance(raw_bad, list) else set()
    heard = None
    if "heard" in entry:
        try:
            heard = _check_heard(entry["heard"])
        except NotesError as e:
            bad(e)   # dropped: the sound just isn't checked for rebuilds until its next verdict
    if verdict is None and not note.strip() and not variants:
        return None   # empty: nothing worth keeping ("heard" alone isn't)
    out = {"verdict": verdict, "note": note, "bad_variants": sorted(variants)}
    if heard is not None:
        out["heard"] = heard
    return out


def apply_change(entry: dict | None, change: object, stamp=None) -> dict | None:
    """Merge one field-level change into a stored entry (None = no entry yet).
    `change` holds any subset of CHANGE_FIELDS: verdict (null clears it), note,
    bad_variants (replace the list), then bad_add / bad_remove, and "heard": true
    ("I listened to the sound as it is now"). A legacy whole entry {verdict, note,
    bad_variants} is just a change that sets all three. After the other fields,
    "heard": true, or any change that sets a verdict, records stamp() (the
    fingerprints of the sound's files now) as the entry's "heard"; without a
    stamp (a note for a sound no longer in the game) "heard" is left as it was.
    Raises NotesError (plain words) if anything in it is invalid, so a change is
    applied whole or not at all; returns None if nothing worth keeping is left."""
    if not isinstance(change, dict):
        raise NotesError("the change isn't in the expected format")
    unknown = sorted(str(f) for f in change if f not in CHANGE_FIELDS)
    if unknown:
        raise NotesError(f"the change has fields the player doesn't use ({', '.join(unknown)})")
    if "heard" in change and change["heard"] is not True:
        raise NotesError("'heard' can only be true (it means you listened to the sound as it is now)")
    cur = entry or {"verdict": None, "note": "", "bad_variants": []}
    verdict, note, takes = cur["verdict"], cur["note"], set(cur["bad_variants"])
    heard = cur.get("heard")
    if "verdict" in change:
        _check_verdict(change["verdict"])
        verdict = change["verdict"]
    if "note" in change:
        _check_note(change["note"])
        note = change["note"]
    if "bad_variants" in change:
        takes = _check_takes(change["bad_variants"])
    if "bad_add" in change:
        takes |= _check_takes(change["bad_add"])
    if "bad_remove" in change:
        takes -= _check_takes(change["bad_remove"])
    if verdict is None and not note.strip() and not takes:
        return None
    if stamp is not None and (change.get("heard") is True or change.get("verdict") is not None):
        heard = stamp()
    out = {"verdict": verdict, "note": note, "bad_variants": sorted(takes)}
    if heard is not None:
        out["heard"] = heard
    return out


def notes_repairs(data: dict) -> list[str]:
    """What normalise_notes() has to change or drop in notes read from disk, as
    'key: why' lines (empty = nothing is lost; moving a note between "keys" and
    "orphans" isn't a loss). The file is rewritten with just these four fields."""
    out, seen = [], {}
    extra = sorted(str(f) for f in data if f not in NOTES_FIELDS)
    if extra:
        out.append(f"the file has fields the player doesn't use ({', '.join(extra)})")
    version = data.get("version", 1)
    if type(version) is not int or version != 1:
        out.append(f"the file says it is version {json.dumps(version)[:40]}, and the player only knows version 1")
    for section in ("keys", "orphans"):
        src = data.get(section)
        if src is None:
            continue
        if not isinstance(src, dict):
            out.append(f"the '{section}' section isn't a set of notes")
            continue
        for key, entry in src.items():
            try:
                clean = _clean_entry(entry, strict=True)
            except NotesError as e:
                out.append(f"{key}: {e}")
                continue
            if clean is None:
                continue
            if key in seen and seen[key] != clean:
                out.append(f"{key}: it was saved twice, and only the copy under '{section}' is kept")
            seen[key] = clean
    return out


def normalise_notes(data: dict, valid_keys: set[str]) -> dict:
    """Repair notes read from disk; sounds no longer in the catalogue become orphans."""
    out = empty_notes()
    out["updated"] = data.get("updated") if isinstance(data.get("updated"), str) else None
    sources = []
    if isinstance(data.get("keys"), dict):
        sources.append(data["keys"])
    if isinstance(data.get("orphans"), dict):
        sources.append(data["orphans"])
    for src in sources:
        for key, entry in src.items():
            if not isinstance(key, str):
                continue
            clean = _clean_entry(entry, strict=False)
            if clean is None:
                continue
            (out["keys"] if key in valid_keys else out["orphans"])[key] = clean
    return out


def read_notes_file(path: Path) -> dict:
    """Raw read. Raises NotesError if the file exists but isn't valid notes JSON."""
    if not path.exists():
        return empty_notes()
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError, RecursionError) as e:
        raise NotesError(f"{path} could not be read ({e})") from e
    if not isinstance(data, dict):
        raise NotesError(f"{path} could not be read (it isn't a JSON object)")
    return data


def write_notes(path: Path, notes: dict) -> None:
    """Atomic write (temp file + rename). Cleans up the temp file on failure."""
    tmp = path.with_name(path.name + ".tmp")
    try:
        tmp.write_text(json.dumps(notes, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        os.replace(tmp, path)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def read_baseline(path: Path) -> dict[str, str]:
    """review_baseline.json: {"about": …, "files": {audio path: sha256}} -> {audio
    path: fingerprint}. Raises NotesError (plain words) if it can't be used."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError, RecursionError) as e:
        raise NotesError(f"{path} could not be read ({e})") from e
    files = data.get("files") if isinstance(data, dict) else None
    if not isinstance(files, dict) or not all(isinstance(f, str) and isinstance(sha, str) and HEX64.fullmatch(sha)
                                              for f, sha in files.items()):
        raise NotesError(f'{path} isn\'t in the expected format ({{"files": {{audio file: sha256}}}})')
    return {f: sha[:16].lower() for f, sha in files.items()}


class Baseline:
    """review_baseline.json next to the notes file: the fingerprints of the audio as
    it was when notes saved before "heard" existed were written. Only ever read
    (re-read when it changes). A missing one is simply none; one that can't be
    used is ignored, with a console line once and `error` for the page."""

    def __init__(self, path: Path, log=None):
        self.path = path
        self.log = log or (lambda line: print(line, flush=True))
        self._lock = threading.Lock()
        self._stamp: object = None
        self._files: dict[str, str] = {}
        self.error: str | None = None

    def get(self) -> dict[str, str]:
        with self._lock:
            try:
                st = self.path.stat()
                stamp: object = (st.st_size, st.st_mtime_ns)
            except FileNotFoundError:
                self._stamp, self._files, self.error = None, {}, None   # the usual case: there is none
                return self._files
            except OSError as e:
                stamp = f"stat: {e}"
            if stamp != self._stamp:
                self._stamp = stamp
                try:
                    if isinstance(stamp, str):
                        raise NotesError(f"{self.path} could not be read ({stamp[6:]})")
                    self._files, error = read_baseline(self.path), None
                except NotesError as e:
                    self._files, error = {}, str(e)
                if error and error != self.error:
                    self.log(f"review baseline ignored: {error}")
                self.error = error
            return self._files


def fill_heard(notes: dict, key_files: dict[str, list[str]], baseline: dict[str, str]) -> None:
    """Notes saved before "heard" existed: each entry without one gets the
    baseline's fingerprints of its sound's files (the ones the baseline lists; a
    sound with none listed gets no "heard"). An upgrade, not a repair: nothing is
    reported, and it reaches the file with the next save."""
    if not baseline:
        return
    for key, entry in notes["keys"].items():
        if "heard" in entry:
            continue
        heard = {f: baseline[f] for f in key_files.get(key, []) if f in baseline}
        if heard:
            entry["heard"] = heard


class NotesStore:
    """Owns the notes file for one server: startup recovery, backups, merges."""

    def __init__(self, path: Path, catalog: Catalog):
        self.path = path
        self.catalog = catalog
        self.lock = threading.Lock()
        self.warnings: list[str] = []
        self.delivered: list[str] = []   # ids of close-time saves applied since startup, newest last
        self.baseline = Baseline(path.with_name(BASELINE_NAME))
        self.baseline.get()   # says so now if it can't be used
        self._startup()

    def _sibling(self, label: str) -> Path:
        """A new, unused review_notes.json.<label>-<time> path next to the notes."""
        stamp = time.strftime("%Y%m%d-%H%M%S")
        out, n = self.path.with_name(f"{self.path.name}.{label}-{stamp}"), 1
        while out.exists():
            n += 1
            out = self.path.with_name(f"{self.path.name}.{label}-{stamp}-{n}")
        return out

    def _keep_copy(self, label: str) -> Path:
        """Copy the notes file to .<label>-<time> once: an identical earlier copy is reused."""
        data = self.path.read_bytes()
        prefix = f"{self.path.name}.{label}-"
        for old in sorted(p for p in self.path.parent.iterdir() if p.name.startswith(prefix)):
            try:
                if old.read_bytes() == data:
                    return old
            except OSError:
                pass
        copy = self._sibling(label)
        shutil.copy2(self.path, copy)
        return copy

    def _startup(self) -> None:
        try:
            raw = read_notes_file(self.path)
        except NotesError as e:
            # never overwrite something we can't read: move it aside and say so
            aside = self._sibling("corrupt")
            os.replace(self.path, aside)
            print(f"notes file problem: {e}", flush=True)
            self.warnings.append(f"Your notes file was damaged, so it was moved to {aside} (nothing was lost).")
            return
        if not self.path.exists():
            return
        # session backup: the notes exactly as they were before this session
        shutil.copy2(self.path, self.path.with_name(self.path.name + ".bak"))
        repairs = notes_repairs(raw)
        if repairs:
            # The next save rewrites the file tidied up (and the next session's .bak
            # is that tidied file), so keep the original once, and say so.
            copy = self._keep_copy("repaired")
            for r in repairs:
                print(f"notes repaired: {r}", flush=True)
            shown = "; ".join(repairs[:3]) + (f"; and {len(repairs) - 3} more" if len(repairs) > 3 else "")
            self.warnings.append(f"Some saved notes had values the player can't use, so they are shown tidied up and "
                                 f"the original file was kept at {copy} (nothing was lost) — {shown}.")

    def read(self) -> dict:
        self.catalog.get()
        try:
            data = read_notes_file(self.path)
        except NotesError as e:
            print(f"notes file problem: {e}", flush=True)
            raise NotesUnavailable(f"Saving is paused because {self.path} could not be read; fix or move that "
                                   "file, then reload the page (your edits stay in this browser meanwhile).") from e
        notes = normalise_notes(data, self.catalog.keys)
        fill_heard(notes, self.catalog.files, self.baseline.get())
        return notes

    def baseline_warning(self) -> str | None:
        if not self.baseline.error:
            return None
        return (f"{self.baseline.path.name} couldn't be used, so sounds reviewed before the player recorded which "
                f"version you heard aren't checked for rebuilds — {self.baseline.error}. Your notes are fine.")

    def apply(self, changes: object, save_id: str | None = None) -> tuple[dict, dict[str, str]]:
        """Merge {key: change | null} into the file on disk, key by key (see
        apply_change). Returns (merged notes, {key: why it was refused}): valid
        keys are saved even when others are refused. null deletes a note, and
        deleting one that isn't there is a no-op (two tabs may both delete the
        same orphan). Notes for sounds no longer in the catalogue ("orphans") can
        be changed or deleted; a key that is neither is refused. A verdict or
        "heard": true records what the sound's files are now (see apply_change).
        The file is only rewritten when something actually changed (a "heard"
        stamped again with the same fingerprints isn't a change). `save_id` (a
        tab's close-time save) is remembered once applied, so the next page can
        tell it arrived."""
        if not isinstance(changes, dict):
            raise NotesError('expected {"changes": {sound key: change or null}}')
        rejected: dict[str, str] = {}
        with self.lock:
            notes = self.read()
            before = json.dumps(notes, sort_keys=True)
            for key, change in changes.items():
                section = ("keys" if key in self.catalog.keys else
                           "orphans" if key in notes["orphans"] else None)
                if change is None:
                    if section:
                        notes[section].pop(key, None)
                    continue
                if section is None:
                    rejected[key] = "this sound isn't in the sound list any more (it was renamed or removed)"
                    continue
                stamp = None
                if section == "keys":
                    def stamp(files=self.catalog.files.get(key, [])):
                        return key_fingerprints(files)
                try:
                    entry = apply_change(notes[section].get(key), change, stamp)
                except NotesError as e:
                    rejected[key] = str(e)
                    continue
                if entry is None:
                    notes[section].pop(key, None)
                else:
                    notes[section][key] = entry
            if json.dumps(notes, sort_keys=True) != before:
                notes["updated"] = time.strftime("%Y-%m-%dT%H:%M:%S")
                write_notes(self.path, notes)
            if save_id:   # a new list each time: readers never see one half-changed
                self.delivered = [*self.delivered[-(MAX_DELIVERED - 1):], save_id]
            return notes, rejected


# ---------------------------------------------------------------------------
# HTTP server
# ---------------------------------------------------------------------------

class ReviewServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, addr, handler, notes_path: Path):
        super().__init__(addr, handler)
        self.catalog = Catalog()
        self.catalog.get()
        self.store = NotesStore(notes_path, self.catalog)
        self.started_ms = int(time.time() * 1000)   # the page compares it with when its tab closed
        self.presence = 0
        self.presence_lock = threading.Lock()
        self.ever_connected = False
        self.last_activity = time.monotonic()   # --idle-exit: last tab open/close, ping or data load
        self.stopping = False                   # --idle-exit has decided to stop
        self.slots = threading.BoundedSemaphore(MAX_CONNECTIONS)
        self.deadlines: dict[socket.socket, float] = {}   # connection -> when its request must be in
        self.deadline_lock = threading.Lock()
        self._closed = threading.Event()
        threading.Thread(target=self._reap, daemon=True).start()

    def _reap(self) -> None:
        """Hang up on connections whose request hasn't arrived in full within
        REQUEST_TIMEOUT. The socket timeout restarts on every byte, so without this
        a client sending a byte every few seconds would hold its slot for good."""
        while not self._closed.wait(1.0):
            now = time.monotonic()
            with self.deadline_lock:
                late = [c for c, t in self.deadlines.items() if t <= now]
                for c in late:
                    del self.deadlines[c]
            for c in late:
                try:
                    c.shutdown(socket.SHUT_RDWR)   # its handler's read returns at once and it closes
                except OSError:
                    pass

    def server_close(self):
        self._closed.set()
        super().server_close()

    @property
    def origin_hosts(self) -> set[str]:
        port = self.server_address[1]
        return {f"127.0.0.1:{port}", f"localhost:{port}"}

    def touch(self) -> bool:
        """The page (or a relaunch) is in use: --idle-exit restarts its grace period.
        False once --idle-exit has already decided to stop."""
        with self.presence_lock:
            if self.stopping:
                return False
            self.last_activity = time.monotonic()
            return True

    def process_request(self, request, client_address):
        # one thread per connection, but never more than MAX_CONNECTIONS of them
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()

    def handle_error(self, request, client_address):
        pass   # a client hanging up mid-response is normal for audio seeking


class Handler(BaseHTTPRequestHandler):
    server: ReviewServer
    server_version = "BBDAudioReview/2.0"
    protocol_version = "HTTP/1.1"
    timeout = REQUEST_TIMEOUT    # idle / half-sent connections are dropped (presence waits with select)
    _body_done = False           # this request's body has been read (or it has none)

    def log_message(self, fmt, *args):
        pass

    def handle_one_request(self):
        # the whole request (line, headers, body) has REQUEST_TIMEOUT to arrive; see ReviewServer._reap
        self._body_done, self.headers = False, None    # nothing left over from the previous request
        srv = self.server
        with srv.deadline_lock:
            srv.deadlines[self.connection] = time.monotonic() + REQUEST_TIMEOUT
        try:
            super().handle_one_request()
        finally:
            self._request_in()

    def _request_in(self) -> None:
        """The request has arrived in full: answering it has no deadline (a
        presence stream, a long track to a slow client)."""
        with self.server.deadline_lock:
            self.server.deadlines.pop(self.connection, None)

    def parse_request(self) -> bool:
        if not super().parse_request():
            return False
        # Two Content-Lengths make it unclear where the body ends (RFC 9112 §6.3), on
        # any method: refuse and close, so no part of it is read as a next request.
        if len(self.headers.get_all("Content-Length") or []) > 1:
            self.send_error(HTTPStatus.BAD_REQUEST, "bad Content-Length")
            return False
        return True

    # --- helpers -------------------------------------------------------------
    def _host_ok(self) -> bool:
        # DNS-rebinding guard: only answer to our own loopback host name
        return self.headers.get("Host", "") in self.server.origin_hosts

    def _cross_site(self) -> bool:
        """A request another web page made: a foreign (or "null") Origin, or a
        Sec-Fetch-Site other than same-origin / none (a typed URL). Other ports on
        localhost count as foreign. Tools like urllib send neither header."""
        origin = self.headers.get("Origin")
        if origin is not None:
            o = urlsplit(origin)
            if o.scheme != "http" or o.netloc not in self.server.origin_hosts:
                return True
        return self.headers.get("Sec-Fetch-Site", "same-origin") not in ("same-origin", "none")

    def _body_unread(self) -> bool:
        headers = getattr(self, "headers", None)
        if self._body_done or headers is None:
            return False
        lengths = headers.get_all("Content-Length") or []   # every one of them, not just the first
        return (bool(headers.get("Transfer-Encoding")) or len(lengths) > 1
                or any(n.strip() not in ("", "0") for n in lengths))

    def _send(self, status: int, body: bytes, ctype: str, extra: dict | None = None) -> None:
        # Errors, and any reply sent without reading the request's body, end the
        # connection: leftover body bytes must never be parsed as a next request.
        close = status >= 400 or self._body_unread()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in {**SECURITY_HEADERS, **(extra or {})}.items():
            self.send_header(k, v)
        if close:
            self.send_header("Connection", "close")   # also sets self.close_connection
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, obj, status: int = 200, extra: dict | None = None) -> None:
        self._send(status, json.dumps(obj, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8", extra)

    def _error(self, status: int, msg: str, extra: dict | None = None) -> None:
        self._json({"error": msg}, status, extra)

    def send_error(self, code, message=None, explain=None):
        """Errors the stdlib sends itself (bad request line, unknown method, URI too
        long…): JSON with the security headers, closing the connection, like ours."""
        if self.request_version == "HTTP/0.9":   # request line unusable: still send a status line
            self.request_version = "HTTP/1.1"
        try:
            phrase = HTTPStatus(code).phrase
        except ValueError:
            phrase = "error"
        self._error(code, message or phrase)

    def _guarded(self, fn):
        self._body_done = False
        try:
            fn()
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True
        except Exception as e:  # never answer with an empty reply
            try:
                self._error(HTTPStatus.INTERNAL_SERVER_ERROR, f"internal error: {type(e).__name__}")
            except Exception:
                pass
            self.close_connection = True

    def finish(self):
        # Lingering close: after an early error reply, drop what the client is
        # still sending for a moment, so it gets the reply instead of a reset.
        if self.close_connection and self._body_unread():
            try:
                self.wfile.flush()
                self.connection.shutdown(socket.SHUT_WR)
                deadline, got = time.monotonic() + 2.0, 0
                while got < 4 * MAX_BODY_BYTES and time.monotonic() < deadline:
                    readable, _, _ = select.select([self.connection], [], [], max(0.0, deadline - time.monotonic()))
                    chunk = self.connection.recv(65536) if readable else b""
                    if not chunk:
                        break
                    got += len(chunk)   # discarded, never parsed
            except (OSError, ValueError):
                pass
        super().finish()

    # --- methods we don't serve ------------------------------------------------
    def _not_allowed(self):
        self._error(HTTPStatus.METHOD_NOT_ALLOWED, "method not allowed", {"Allow": "GET, HEAD, POST"})

    def do_PUT(self):
        self._guarded(self._not_allowed)

    def do_DELETE(self):
        self._guarded(self._not_allowed)

    def do_OPTIONS(self):
        self._guarded(self._not_allowed)

    def do_PATCH(self):
        self._guarded(self._not_allowed)

    # --- GET ---------------------------------------------------------------------
    def do_HEAD(self):
        self._guarded(self._get)

    def do_GET(self):
        self._guarded(self._get)

    def _get(self):
        self._request_in()   # no body to wait for (one that was sent is never read: the reply closes)
        if not self._host_ok():
            return self._error(HTTPStatus.FORBIDDEN, "bad host")
        path = unquote(urlsplit(self.path).path)
        if path in PAGE_FILES:
            f = PAGE_DIR / PAGE_FILES[path]
            return self._send(200, f.read_bytes(), CONTENT_TYPES[f.suffix])
        if path.startswith("/api/") and self._cross_site():
            return self._error(HTTPStatus.FORBIDDEN, "cross-origin request refused")
        if path == "/api/ping":
            # a relaunch about to reuse us: don't --idle-exit under it (or say we're going)
            if not self.server.touch():
                return self._error(HTTPStatus.SERVICE_UNAVAILABLE, "stopping: the review tab was closed")
            return self._json({"app": APP_ID, "notes": str(self.server.store.path), "protocol": PROTOCOL})
        if path == "/api/data":
            self.server.touch()
            catalog = with_versions(self.server.catalog.get())
            try:
                notes, notes_error = self.server.store.read(), None
            except NotesError as e:
                notes, notes_error = empty_notes(), str(e)
            warnings = list(self.server.store.warnings)
            baseline = self.server.store.baseline_warning()
            if baseline:
                warnings.append(baseline)
            if self.server.catalog.error:
                warnings.append("The sound list couldn't be re-read, so the page shows it as it was — "
                                f"{self.server.catalog.error}. Notes still save meanwhile.")
            return self._json({**catalog, "notes": notes, "notes_error": notes_error,
                               "warnings": warnings,
                               "notes_id": str(self.server.store.path), "protocol": PROTOCOL,
                               "delivered": self.server.store.delivered, "started": self.server.started_ms})
        if path == "/api/presence":
            return self._presence()
        if path.startswith("/audio/"):
            self.server.catalog.get()
            rel = path[len("/audio/"):]
            if rel not in self.server.catalog.audio:
                return self._error(HTTPStatus.NOT_FOUND, "not a manifest audio file")
            return self._serve_audio(AUDIO_DIR / rel)
        return self._error(HTTPStatus.NOT_FOUND, "not found")

    def _serve_audio(self, f: Path) -> None:
        """Serve an audio file with single-range support (so long tracks can seek)."""
        data = f.read_bytes()
        size = len(data)
        ctype = CONTENT_TYPES.get(f.suffix.lower(), "application/octet-stream")
        rng = self.headers.get("Range")
        if rng:
            m = re.fullmatch(r"bytes=(\d{0,15})-(\d{0,15})", rng.strip())
            if m and (m.group(1) or m.group(2)):
                if m.group(1):
                    start = int(m.group(1))
                    end = min(int(m.group(2)) if m.group(2) else size - 1, size - 1)
                else:   # suffix range: the last N bytes
                    start, end = max(0, size - int(m.group(2))), size - 1
                if start <= end and start < size:
                    return self._send(HTTPStatus.PARTIAL_CONTENT, data[start:end + 1], ctype,
                                      {"Accept-Ranges": "bytes", "Content-Range": f"bytes {start}-{end}/{size}"})
                return self._send(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE, b"", ctype,
                                  {"Content-Range": f"bytes */{size}"})
            # malformed or multi-range: ignore it and send the whole file (RFC 9110 allows this)
        self._send(200, data, ctype, {"Accept-Ranges": "bytes"})

    def _stream_headers(self) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        for k, v in SECURITY_HEADERS.items():
            self.send_header(k, v)
        self.send_header("Connection", "close")
        self.end_headers()

    def _presence(self) -> None:
        """Server-sent-event stream that stays open while a review tab is open.
        Background tabs keep it alive (unlike throttled timers); closing the tab
        closes the socket, which we notice immediately via select(). A HEAD gets
        the headers only and isn't counted as a tab."""
        if self.command == "HEAD":
            return self._stream_headers()
        srv = self.server
        with srv.presence_lock:
            full = srv.presence >= MAX_PRESENCE
            if not full:
                srv.presence += 1
                srv.ever_connected = True
                srv.last_activity = time.monotonic()
        if full:
            return self._error(HTTPStatus.SERVICE_UNAVAILABLE, f"too many open review tabs (at most {MAX_PRESENCE})")
        try:
            self._stream_headers()
            self.wfile.write(b"retry: 3000\n\n")
            self.wfile.flush()
            conn = self.connection
            while True:
                readable, _, _ = select.select([conn], [], [], 15.0)
                if readable:
                    if not conn.recv(1024, socket.MSG_PEEK):
                        break   # the tab went away
                    conn.recv(1024)
                self.wfile.write(b": still here\n\n")
                self.wfile.flush()
        except (OSError, ValueError):
            pass
        finally:
            with srv.presence_lock:
                srv.presence -= 1
                srv.last_activity = time.monotonic()

    # --- POST -------------------------------------------------------------------
    def do_POST(self):
        self._guarded(self._post)

    def _read_body(self) -> tuple[bytes | None, tuple[int, str] | None]:
        """Read the whole request body (at most MAX_BODY_BYTES) before anything is
        answered, so it can never be parsed as a second request on a kept-alive
        connection: a foreign page could otherwise hide a same-origin save inside
        the body of a request we refuse. Returns (body, None) or (None, (status,
        why)); in the second case the error reply closes the connection unread."""
        if self.headers.get("Transfer-Encoding"):
            return None, (HTTPStatus.LENGTH_REQUIRED, "send a Content-Length")
        lengths = self.headers.get_all("Content-Length") or []
        if not lengths:
            return None, (HTTPStatus.LENGTH_REQUIRED, "send a Content-Length")
        if len(lengths) > 1 or not re.fullmatch(r"\d{1,9}", lengths[0].strip()):
            return None, (HTTPStatus.BAD_REQUEST, "bad Content-Length")
        length = int(lengths[0])
        if length > MAX_BODY_BYTES:
            return None, (HTTPStatus.REQUEST_ENTITY_TOO_LARGE, f"body too large (over {MAX_BODY_BYTES} bytes)")
        try:
            body = self.rfile.read(length) if length else b""
        except OSError:   # timed out or hung up mid-body
            return None, (HTTPStatus.REQUEST_TIMEOUT, "the request body didn't arrive in time")
        if len(body) < length:
            return None, (HTTPStatus.BAD_REQUEST, "the request body was cut short")
        self._body_done = True
        self._request_in()
        if not body:
            return None, (HTTPStatus.BAD_REQUEST, "empty body")
        return body, None

    def _post(self):
        body, problem = self._read_body()   # first, always (see _read_body)
        if not self._host_ok():
            return self._error(HTTPStatus.FORBIDDEN, "bad host")
        if self._cross_site():
            return self._error(HTTPStatus.FORBIDDEN, "cross-origin request refused")
        if urlsplit(self.path).path != "/api/notes":
            return self._error(HTTPStatus.NOT_FOUND, "not found")
        if not self.headers.get("Content-Type", "").startswith("application/json"):
            return self._error(HTTPStatus.UNSUPPORTED_MEDIA_TYPE, "send application/json")
        if problem:
            return self._error(*problem)
        # A 4xx tells the page that sending the same save again can't help, so it is
        # only ever about the request itself; anything else is a 5xx and is retried.
        try:
            req = json.loads(body.decode("utf-8"))
        except (ValueError, RecursionError) as e:   # UnicodeDecodeError is a ValueError
            return self._error(HTTPStatus.BAD_REQUEST, f"the request isn't valid JSON: {e}")
        if not isinstance(req, dict) or not isinstance(req.get("changes"), dict):
            return self._error(HTTPStatus.BAD_REQUEST, 'expected {"changes": {sound key: change or null}}')
        store = self.server.store
        save_id = req.get("save_id")   # optional: sent with a tab's close-time save
        save_id = save_id if isinstance(save_id, str) and SAVE_ID.fullmatch(save_id) else None
        try:
            notes, rejected = store.apply(req["changes"], save_id)
        except NotesUnavailable as e:   # the notes file's (or the sound list's) fault: the page retries
            return self._error(HTTPStatus.SERVICE_UNAVAILABLE, str(e))
        except NotesError as e:
            return self._error(HTTPStatus.BAD_REQUEST, str(e))
        except OSError as e:
            return self._error(HTTPStatus.INTERNAL_SERVER_ERROR, f"Couldn't save to {store.path} ({e.strerror or e}).")
        self.server.touch()
        self._json({"ok": True, "updated": notes["updated"], "notes": notes, "rejected": rejected,
                    "protocol": PROTOCOL})


# ---------------------------------------------------------------------------
# lifecycle
# ---------------------------------------------------------------------------

def existing_instance(port: int, notes_path: Path) -> str | None:
    """URL of a review server already running on `port` for the same notes file."""
    url = f"http://127.0.0.1:{port}/"
    try:
        with urllib.request.urlopen(url + "api/ping", timeout=0.8) as r:
            info = json.loads(r.read())
        if info.get("app") == APP_ID and Path(info.get("notes", "")) == notes_path:
            return url
    except Exception:
        pass
    return None


def instance_protocol(url: str) -> int:
    """The save protocol a running review server reports (an old one says none: 1)."""
    try:
        with urllib.request.urlopen(url + "api/ping", timeout=0.8) as r:
            p = json.loads(r.read()).get("protocol")
        return p if type(p) is int else 1
    except Exception:
        return PROTOCOL   # can't tell: say nothing


def serve(port: int | None, open_browser: bool, idle_exit: bool) -> None:
    notes_path = NOTES
    want = DEFAULT_PORT if port is None else port
    if want:
        running = existing_instance(want, notes_path)
        if running:
            print(f"Audio review is already running at {running} — opening it.", flush=True)
            if instance_protocol(running) < PROTOCOL:
                # every tab counts: one left open from before keeps the old server running
                print("That review server is an older version, so rebuilt sounds aren't marked there: close every "
                      "Audio Review tab (any opened earlier too), wait a minute for it to stop, then start Audio "
                      "Review again.", flush=True)
            if open_browser:
                webbrowser.open(running)
            return
    try:
        httpd = ReviewServer(("127.0.0.1", want), Handler, notes_path)
    except OSError:
        if port is not None:
            raise
        httpd = ReviewServer(("127.0.0.1", 0), Handler, notes_path)
        print(f"Port {DEFAULT_PORT} is busy; using {httpd.server_address[1]} "
              "(the browser's unsaved-draft backup is per port).", flush=True)
    url = f"http://127.0.0.1:{httpd.server_address[1]}/"
    shown = notes_path.relative_to(ROOT) if notes_path.is_relative_to(ROOT) else notes_path
    print(f"Audio review: {url}   (Ctrl+C to stop; notes → {shown})", flush=True)
    for w in httpd.store.warnings:
        print("WARNING: " + w, flush=True)
    if idle_exit:
        def watchdog():
            # Stop once no tab is open and nothing used the page for the grace period;
            # a relaunch's /api/ping or a page load restarts it (see ReviewServer.touch).
            while True:
                time.sleep(1.0)
                with httpd.presence_lock:
                    open_tabs, ever, since = httpd.presence, httpd.ever_connected, httpd.last_activity
                    idle = open_tabs == 0 and time.monotonic() - since > (PRESENCE_GRACE if ever else NEVER_CONNECTED)
                    httpd.stopping = idle
                if idle:
                    print("review page closed — stopping", flush=True)
                    httpd.shutdown()
                    return
        threading.Thread(target=watchdog, daemon=True).start()
    if open_browser:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


# ---------------------------------------------------------------------------
# CLI extras
# ---------------------------------------------------------------------------

def check() -> int:
    manifest = load_json(MANIFEST)
    checklist = load_json(CHECKLIST)
    sfx = manifest_sfx(manifest)
    music = manifest_music(manifest)
    problems = []
    seen: dict[str, str] = {}
    for g in checklist["groups"]:
        for k, v in g["keys"].items():
            if k in seen:
                problems.append(f"{k}: listed in both '{seen[k]}' and '{g['id']}'")
            seen[k] = g["id"]
            if not v.get("expect"):
                problems.append(f"{k}: empty 'expect'")
    listed = set(seen)
    problems += [f"manifest key without checklist entry: {k}" for k in sorted(set(sfx) - listed)]
    problems += [f"checklist entry not in manifest: {k}" for k in sorted(listed - set(sfx))]
    music_listed = set(checklist.get("music", {}))
    problems += [f"music track without checklist entry: {f}" for f in music if f not in music_listed]
    problems += [f"checklist music not in manifest: {f}" for f in sorted(music_listed - set(music))]
    for key, files in sfx.items():
        problems += [f"{key}: missing file {f}" for f in files if not (AUDIO_DIR / f).exists()]
    problems += [f"music: missing file {f}" for f in music if not (AUDIO_DIR / f).exists()]
    for key, b in weapon_bursts().items():
        if key not in sfx:
            problems.append(f"weapon '{b['weapon']}' fires sound '{key}', which isn't in the manifest")
        if b["cycle"] and b["cycle"] not in sfx:
            problems.append(f"weapon '{b['weapon']}' cycles sound '{b['cycle']}', which isn't in the manifest")
    for p in problems:
        print(p)
    print(f"{len(sfx)} sound keys, {sum(len(v) for v in sfx.values())} files, "
          f"{len(music)} music tracks — {len(problems)} problem(s)")
    return 1 if problems else 0


def _when_with_rpm(when: str, burst: dict | None) -> str:
    if not burst:
        return when
    rpm = f"{burst['rpm']:.0f} rpm"
    if rpm in when:
        return when
    body = when[:-1] if when.endswith(".") else when
    return f"{body} ({rpm})."


def write_doc() -> None:
    data = build_catalog()
    lines = [
        "# Audio review checklist",
        "",
        "**To review with a player, run:**",
        "",
        "```bash",
        "python3 tools/audio/review.py",
        "```",
        "",
        "(or double-click the **Bunny Beat Down — Audio Review** shortcut that",
        "`python3 tools/audio/review.py --install-launcher` puts on your Desktop).",
        "",
        "That opens every sound below in your browser with play buttons for each variant,",
        "waveforms, loudness, gun bursts at each weapon's real rate of fire and seamless",
        "loop playback. Mark each sound **Good / Tweak / Replace**, flag bad takes (⚑) and",
        "add notes; they save to `tools/audio/review_notes.json` automatically",
        "(`--summary` prints them). Keyboard: `J`/`K` next/previous · `U` next unreviewed ·",
        "`Space` play · `1`–`9` play a variant · `A` play all · `B` burst · `L` loop ·",
        "`G`/`T`/`R` verdict · `N` note · `Esc` stop · `?` help.",
        "",
        "To fix a sound, tune it in `tools/audio/recipes.py` and rebuild only that key:",
        "",
        "```bash",
        "/snap/bin/blender -b --factory-startup --python-exit-code 1 \\",
        "  --python tools/audio/build_audio.py -- --only pistol_fire,smg_fire",
        "```",
        "",
        "An open review page picks up the rebuilt files when you switch back to its tab.",
        "Run a full build afterwards so `assets/audio/manifest.json` and the credits are",
        "rewritten. This file is generated by `python3 tools/audio/review.py --write-doc`",
        "from `tools/audio/review_checklist.json` — edit that, not this.",
        "",
    ]
    for g in data["groups"]:
        lines += [f"## {g['title']}", "", "| sound | should sound like | when it plays | listen |", "|---|---|---|---|"]
        for k in g["keys"]:
            links = " ".join(f"[{f['n']}](../assets/audio/{f['file']})" for f in k["files"])
            lines.append(f"| `{k['key']}` | {k['expect']} | {_when_with_rpm(k['when'], k.get('burst'))} | {links} |")
        lines.append("")
    lines += ["## Music (Kevin MacLeod, CC BY 4.0)", "", "| track | should sound like | when it plays | listen |", "|---|---|---|---|"]
    for m in data["music"]:
        lines.append(f"| {m['title']} | {m['expect']} | {m['when']} | [▶](../assets/audio/{m['file']}) |")
    lines.append("")
    DOC.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {DOC.relative_to(ROOT)}")


def summary() -> int:
    try:
        raw = read_notes_file(NOTES)
    except NotesError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    catalog = build_catalog()
    notes = normalise_notes(raw, catalog_keys(catalog))
    files = catalog_files(catalog)
    fill_heard(notes, files, Baseline(NOTES.with_name(BASELINE_NAME), log=lambda s: print(s, file=sys.stderr)).get())
    if not notes["keys"] and not notes["orphans"]:
        print("No review notes yet — run python3 tools/audio/review.py")
        return 0
    order = {"replace": 0, "tweak": 1, None: 2, "good": 3}

    def line(key, e):
        bad = e.get("bad_variants") or []
        extra = f" — bad takes: {', '.join(map(str, bad))}" if bad else ""
        note = f": {e['note'].strip()}" if e.get("note", "").strip() else ""
        stale = rebuilt_label(key, rebuilt_takes(e, files[key])) if key in files else ""
        return f"- **{key}** [{(e.get('verdict') or 'unrated').upper()}]{extra}{note}{stale}"

    print(f"# Audio review notes ({notes.get('updated')})\n")
    for key, e in sorted(notes["keys"].items(), key=lambda kv: (order.get(kv[1].get("verdict"), 2), kv[0])):
        print(line(key, e))
    if notes["orphans"]:
        print("\n## Notes for sounds no longer in the manifest\n")
        for key, e in sorted(notes["orphans"].items()):
            print(line(key, e))
    return 0


def _keyfile_escape(value: str) -> str:
    """Escape a .desktop (key-file) value: backslash, newline, tab, CR and a
    leading space, so a value can never spill onto a line of its own."""
    out = value.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")
    return "\\s" + out[1:] if out.startswith(" ") else out


def _desktop_quote(arg: str) -> str:
    """Quote one Exec argument per the Desktop Entry spec (quoting + key-file escapes)."""
    quoted = '"' + re.sub(r'([\\"`$])', r'\\\1', arg) + '"'
    return _keyfile_escape(quoted).replace("%", "%%")


LAUNCHER_NAME = "bunny-beat-down-audio-review.desktop"
CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f]")


def _launcher_targets(desktop: bool = True) -> tuple[Path, Path | None]:
    """(app-menu entry, Desktop shortcut or None). A redirected XDG_DATA_HOME means
    a test/sandbox install: the real Desktop is never touched then (install or remove)."""
    apps = Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share")) / "applications"
    desk = _desktop_dir() if desktop and not os.environ.get("XDG_DATA_HOME") else None
    return apps / LAUNCHER_NAME, (desk / LAUNCHER_NAME if desk else None)


def _desktop_dir() -> Path | None:
    """The user's Desktop folder (xdg-user-dir aware), or None if there isn't one."""
    try:
        import subprocess
        out = subprocess.run(["xdg-user-dir", "DESKTOP"], capture_output=True, text=True, timeout=5).stdout.strip()
        if out and Path(out).is_dir() and Path(out) != Path.home():
            return Path(out)
    except (OSError, ValueError, Exception):
        pass
    fallback = Path.home() / "Desktop"
    return fallback if fallback.is_dir() else None


def install_launcher(desktop: bool = True) -> None:
    """App-menu entry + Desktop shortcut that open the review player (and stop
    the server once the review tab is closed)."""
    script = str(Path(__file__).resolve())
    icon_file = Path(__file__).with_name("review_icon.png")
    icon = str(icon_file if icon_file.exists() else ROOT / "icon.png")
    for p in (sys.executable, script, icon):
        if CONTROL_CHARS.search(p):
            raise SystemExit(f"Not installing the launcher: the path {p!r} has a control character "
                             "(such as a line break) in it, which a desktop shortcut can't hold safely.")
    exec_line = " ".join(_desktop_quote(a) for a in [sys.executable, script, "--idle-exit"])
    text = (f"[Desktop Entry]\nType=Application\nVersion=1.0\nName={_keyfile_escape('Bunny Beat Down — Audio Review')}\n"
            "GenericName=Sound review player\n"
            "Comment=Listen to every Bunny Beat Down sound and mark it Good, Tweak or Replace\n"
            f"Exec={exec_line}\nIcon={_keyfile_escape(icon)}\nTerminal=false\nStartupNotify=false\n"
            "Categories=AudioVideo;Audio;\nKeywords=audio;sound;review;bunny;\n")
    entry, shortcut = _launcher_targets(desktop)
    entry.parent.mkdir(parents=True, exist_ok=True)
    for t in [entry, *([shortcut] if shortcut else [])]:
        t.write_text(text, encoding="utf-8")
        t.chmod(0o755)
        if t == shortcut:
            # GNOME only runs desktop icons that are marked trusted
            try:
                import subprocess
                subprocess.run(["gio", "set", str(t), "metadata::trusted", "true"], capture_output=True, timeout=5)
            except (OSError, Exception):
                pass
        print(f"installed {t}")


def remove_launcher() -> None:
    entry, shortcut = _launcher_targets()   # same sandbox rule as install
    for t in [entry, *([shortcut] if shortcut else [])]:
        if t.exists():
            t.unlink()
            print(f"removed {t}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--port", type=int, default=None, help=f"port to listen on (default {DEFAULT_PORT}, or any free port if busy)")
    ap.add_argument("--no-browser", action="store_true", help="don't open a browser tab")
    ap.add_argument("--idle-exit", action="store_true", help="stop once the review tab has been closed")
    ap.add_argument("--check", action="store_true", help="verify checklist and manifest agree, then exit")
    ap.add_argument("--write-doc", action="store_true", help="regenerate docs/AUDIO_REVIEW.md, then exit")
    ap.add_argument("--summary", action="store_true", help="print saved review notes as Markdown, then exit")
    ap.add_argument("--install-launcher", action="store_true", help="add a Desktop shortcut + app-menu entry for the review player")
    ap.add_argument("--remove-launcher", action="store_true", help="remove the Desktop shortcut and app-menu entry")
    ap.add_argument("--notes", type=Path, default=None,
                    help="notes file to read/write (default tools/audio/review_notes.json; tests use a temp file)")
    args = ap.parse_args()
    if args.notes:
        global NOTES
        NOTES = args.notes.resolve()
    if args.check:
        return check()
    if args.write_doc:
        write_doc()
        return 0
    if args.summary:
        return summary()
    if args.install_launcher:
        install_launcher()
        return 0
    if args.remove_launcher:
        remove_launcher()
        return 0
    try:
        serve(args.port, not args.no_browser, args.idle_exit)
    except NotesUnavailable as e:   # the sound list can't be read at startup
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
