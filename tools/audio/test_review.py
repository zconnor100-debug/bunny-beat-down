"""End-to-end tests for the audio review server (tools/audio/review.py).

    python3 tools/audio/test_review.py

Runs real server processes against a temporary notes file on a free port, so
the owner's tools/audio/review_notes.json is never touched. Covers: corrupt
notes moved aside, repaired notes kept once, per-key merging between tabs,
field-level changes (two tabs editing different fields of one sound), per-key
rejection, idempotent deletes, close-time save ids, orphans, the protocol
marker, audio file versions (so the page reloads a rebuilt sound), content
fingerprints (cached until a file changes) and "heard" (recorded by a verdict
or "heard": true, only when it changes; anything but true refused per key; a
malformed one repaired), the review_baseline.json fill-in (no repair, written
with the next save, a bad baseline ignored) and --summary's "rebuilt since this
verdict" marks, security
headers, smuggled request bodies (also behind a doubled Content-Length), foreign
origins, presence (HEAD, cap, cross-origin), malformed requests, the connection
cap and slow-drip clients, single-instance reuse (and what a launch says when it
finds an older review server running), unknown top-level fields,
--idle-exit (presence and relaunch grace), --summary errors, the launcher
(quoting, control characters, sandboxed removal) and saving while the checklist
can't be read (in a sandbox copy). Exits non-zero on any failure (CI).
"""
import atexit
import contextlib
import hashlib
import http.client
import io
import json
import tempfile
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRATCH = Path(tempfile.mkdtemp(prefix="bbd-review-test-"))
sys.path.insert(0, str(REPO / "tools" / "audio"))
import review  # noqa: E402  (unit checks: launcher helpers, constants, the catalogue)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


PORT = free_port()
B = f"http://127.0.0.1:{PORT}"
NOTES = SCRATCH / "notes.json"
for p in SCRATCH.glob("notes.json*"):
    p.unlink()


STARTED = []


@atexit.register
def _stop_leftovers():
    # a crashed check must not leave a test server running
    for p in STARTED:
        if p.poll() is None:
            p.terminate()


def start(*extra, script=REPO / "tools/audio/review.py", port=PORT, notes=NOTES):
    proc = subprocess.Popen([sys.executable, str(script), "--no-browser", "--port", str(port),
                             "--notes", str(notes), *extra], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    STARTED.append(proc)
    for _ in range(50):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{port}/api/ping", timeout=0.3)
            return proc
        except Exception:
            time.sleep(0.1)
    raise SystemExit("server didn't start: " + proc.stdout.read())


def stop(proc):
    proc.terminate()
    proc.wait(5)


def post(changes, origin=None, body=None, base=B):
    data = json.dumps({"changes": changes}).encode() if body is None else body
    req = urllib.request.Request(base + "/api/notes", data=data,
                                 headers={"Content-Type": "application/json", "Origin": origin or base}, method="POST")
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def get(path, headers=None):
    with urllib.request.urlopen(urllib.request.Request(B + path, headers=headers or {}), timeout=10) as r:
        return r.status, dict(r.headers), r.read()


def get_status(path, headers):
    try:
        return get(path, headers)[0]
    except urllib.error.HTTPError as e:
        return e.code
    except OSError:   # e.g. an accepted presence stream that never ends
        return "no reply"


def raw(data: bytes, wait=3.0) -> bytes:
    """Send raw bytes; return everything the server sends until it closes (or `wait` passes)."""
    s = socket.create_connection(("127.0.0.1", PORT))
    s.settimeout(wait)
    s.sendall(data)
    out = b""
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            out += chunk
    except (socket.timeout, ConnectionResetError):
        pass
    s.close()
    return out


def disk():
    return json.loads(NOTES.read_text())


ok = True


def check(cond, msg):
    global ok
    print(("PASS " if cond else "FAIL ") + msg)
    ok &= bool(cond)


# 1. corrupt file is moved aside, never overwritten
NOTES.write_text('{"version": 1, "keys": {"pistol_fire": {"verdict": "good",}}}')
proc = start()
data = json.loads(get("/api/data")[2])
aside = list(SCRATCH.glob("notes.json.corrupt-*"))
check(len(aside) == 1 and "pistol_fire" in aside[0].read_text(), "corrupt notes moved aside intact")
check(any("was damaged" in w and str(aside[0]) in w for w in data["warnings"]),
      "page gets a plain warning naming the full path")
check(data.get("protocol") == 3, "/api/data says protocol 3")
files = [f for g in data["groups"] for k in g["keys"] for f in k["files"]] + data["music"]
check(files and all(f.get("v") for f in files), "/api/data gives every audio file a version")
snd = SCRATCH / "audio" / "sfx"
snd.mkdir(parents=True)
(snd / "x.ogg").write_bytes(b"one")
cat = {"groups": [{"id": "g", "title": "G", "keys": [{"key": "x", "files": [{"n": 1, "file": "sfx/x.ogg", "url": "/audio/sfx/x.ogg"}]}]}],
       "music": [{"key": "music:m.ogg", "file": "m.ogg", "url": "/audio/m.ogg"}]}
v1 = review.with_versions(cat, SCRATCH / "audio")
(snd / "x.ogg").write_bytes(b"two!")   # rebuilt under the same name
v2 = review.with_versions(cat, SCRATCH / "audio")
check(v1["groups"][0]["keys"][0]["files"][0]["v"] != v2["groups"][0]["keys"][0]["files"][0]["v"] and v2["music"][0]["v"] == ""
      and "v" not in cat["groups"][0]["keys"][0]["files"][0], "a rebuilt sound gets a new version; a missing one gets none")

# 2. per-key merges: two 'tabs' saving different keys keep both (legacy whole-entry form)
s1, r1 = post({"smg_fire": {"verdict": "tweak", "note": "tab A", "bad_variants": [2]}})
s2, r2 = post({"rifle_fire": {"verdict": "good", "note": "", "bad_variants": []}})
check(s1 == s2 == 200 and set(disk()["keys"]) == {"smg_fire", "rifle_fire"}, "two tabs' saves merge instead of overwriting")
check(r2["notes"]["keys"].get("smg_fire", {}).get("note") == "tab A", "response carries the merged notes")
check(r2.get("rejected") == {} and r2.get("ok") is True, "response has an empty 'rejected' when everything applied")

# 3. clearing a key removes it; deleting again (or deleting a note that never existed) is a no-op
post({"rifle_fire": None})
check("rifle_fire" not in disk()["keys"], "null change deletes a note")
before, mtime = NOTES.read_text(), NOTES.stat().st_mtime_ns
st, body = post({"rifle_fire": None, "never_existed_sound": None})
check(st == 200 and body["rejected"] == {} and NOTES.read_text() == before and NOTES.stat().st_mtime_ns == mtime,
      "deleting an absent note (known or unknown key) succeeds without rewriting the file")

# 4. invalid keys are refused one by one; the rest of the save still goes through
before = NOTES.read_text()
for bad, why in [({"nope": {"verdict": "good"}}, "unknown key"), ({"smg_fire": {"verdict": 5}}, "non-string verdict"),
                 ({"smg_fire": {"bad_variants": [True]}}, "boolean variant"), ({"smg_fire": {"note": "x" * 4001}}, "too long"),
                 ({"smg_fire": {"bad_add": [0]}}, "take 0"), ({"smg_fire": {"colour": "red"}}, "unknown field"),
                 ({"smg_fire": "good"}, "change that isn't an object")]:
    st, body = post(bad)
    key = next(iter(bad))
    check(st == 200 and body.get("rejected", {}).get(key), f"refuses {why} per key ({st}: {body.get('rejected', {}).get(key, '')[:60]})")
lone = '{"changes": {"smg_fire": {"note": "cut \\ud83d"}}}'.encode()
st, body = post(None, body=lone)
check(st == 200 and "broken character" in body.get("rejected", {}).get("smg_fire", ""), "refuses a lone surrogate (cut emoji) per key")
check(NOTES.read_text() == before, "refused changes leave the file untouched")
st, body = post({"nope": {"verdict": "good"}, "pistol_fire": {"verdict": "replace", "note": "still saved"}})
check(st == 200 and list(body["rejected"]) == ["nope"] and disk()["keys"]["pistol_fire"]["note"] == "still saved",
      "one refused key doesn't block the other keys in the same save")
for bad, why in [(b'{"changes": [1, 2]}', "changes not an object"), (b'[1]', "body not an object"),
                 (b'{"changes": {', "not JSON")]:
    st, body = post(None, body=bad)
    check(st == 400 and body.get("error"), f"malformed body ({why}) gets a 400 ({body.get('error', '')[:50]})")
st, body = post({"smg_fire": None}, origin="http://evil.example")
check(st == 403, "cross-origin POST refused")
st, body = post({"smg_fire": None}, origin=f"http://127.0.0.1:{free_port()}")
check(st == 403 and "smg_fire" in disk()["keys"], "POST from another localhost port refused")
st, body = post({"smg_fire": None}, origin="null")
check(st == 403, "POST with Origin: null refused")

# 5. field-level changes: two tabs editing different fields of one sound both survive
post({"lmg_fire": {"note": "belt rattle too loud"}})            # tab A types a note
post({"lmg_fire": {"verdict": "good"}})                          # stale tab B clicks Good
e = dict(disk()["keys"]["lmg_fire"])
lmg_heard = e.pop("heard", None)                                 # what the verdict was given on (see 6b)
check(e == {"verdict": "good", "note": "belt rattle too loud", "bad_variants": []} and lmg_heard,
      f"note and verdict patches both kept ({e})")
post({"hop": {"bad_add": [1]}})                                  # tab A flags take 1
post({"hop": {"bad_add": [3, 3]}})                               # tab B flags take 3
check(disk()["keys"]["hop"]["bad_variants"] == [1, 3], "bad_add from two tabs merges (sorted, unique)")
post({"hop": {"bad_remove": [1, 2]}})
check(disk()["keys"]["hop"]["bad_variants"] == [3], "bad_remove removes just those takes")
post({"lmg_fire": {"verdict": None}})
check(disk()["keys"]["lmg_fire"] == {"verdict": None, "note": "belt rattle too loud", "bad_variants": [], "heard": lmg_heard},
      "verdict: null clears only the verdict")
post({"hop": {"bad_remove": [3]}})
check("hop" not in disk()["keys"], "an entry left with nothing in it is removed")
# a tab's close-time save carries an id; /api/data lists the ones applied, so the next visit can tell
st, _ = post(None, body=json.dumps({"changes": {"hop": {"note": "sent as the tab closed"}}, "save_id": "tab1-abc"}).encode())
post(None, body=json.dumps({"changes": {"hop": {"note": ""}}, "save_id": "not an id!"}).encode())
kept_text = NOTES.read_text()
NOTES.write_text("{ broken")
st503, _ = post(None, body=json.dumps({"changes": {"hop": {"note": "lost"}}, "save_id": "tab2-def"}).encode())
NOTES.write_text(kept_text)
data = json.loads(get("/api/data")[2])
check(st == 200 and st503 == 503 and data.get("delivered") == ["tab1-abc"] and isinstance(data.get("started"), int)
      and "hop" not in disk()["keys"], f"close-time save ids: applied ones are listed, refused or malformed ones aren't ({data.get('delivered')})")

# 6. orphans: a note for a sound that left the manifest is kept, patchable and deletable (twice is fine)
d = disk()
d["keys"]["retired_sound"] = {"verdict": "replace", "note": "old", "bad_variants": []}
NOTES.write_text(json.dumps(d))
data = json.loads(get("/api/data")[2])
check("retired_sound" in data["notes"]["orphans"], "unknown key on disk is served as an orphan")
st, _ = post({"smg_fire": {"verdict": "good", "note": "", "bad_variants": []}})
check(st == 200 and "retired_sound" in disk()["orphans"], "orphan doesn't block other saves and is kept")
st, body = post({"retired_sound": {"note": "old, still bad"}})
check(st == 200 and disk()["orphans"]["retired_sound"]["note"] == "old, still bad", "an orphan's note can be changed")
st, _ = post({"retired_sound": None})
check(st == 200 and "retired_sound" not in disk().get("orphans", {}), "orphan can be deleted")
st, body = post({"retired_sound": None, "scope_in": {"verdict": "tweak", "note": "too quiet"}})
check(st == 200 and body["rejected"] == {} and disk()["keys"]["scope_in"]["note"] == "too quiet",
      "a second tab deleting the same orphan succeeds and its other edits save")

# 6b. protocol 3: every file's content fingerprint ("h"), and "heard" — what a verdict was given on
AUDIO = REPO / "assets" / "audio"


def sha16(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()[:16]


data = json.loads(get("/api/data")[2])
files = [f for g in data["groups"] for k in g["keys"] for f in k["files"]] + data["music"]
check(files and all(f.get("h") == sha16(AUDIO / f["file"]) for f in files),
      "/api/data gives every audio file its fingerprint (first 16 hex digits of its sha256)")
check(json.loads(get("/api/ping")[2]).get("protocol") == 3, "/api/ping says protocol 3")
reads = review.FINGERPRINTS.reads
x1 = review.with_versions(cat, SCRATCH / "audio")["groups"][0]["keys"][0]["files"][0]
x2 = review.with_versions(cat, SCRATCH / "audio")["groups"][0]["keys"][0]["files"][0]
cached = review.FINGERPRINTS.reads == reads   # (x.ogg was read in 1 already)
xs = (snd / "x.ogg").stat()
(snd / "x.ogg").write_bytes(b"tw0!")   # rebuilt again: same size, and (forced) a later mtime
os.utime(snd / "x.ogg", ns=(xs.st_atime_ns, xs.st_mtime_ns + 5_000_000))
x3 = review.with_versions(cat, SCRATCH / "audio")
check(x1["h"] == x2["h"] == hashlib.sha256(b"two!").hexdigest()[:16] and cached and review.FINGERPRINTS.reads == reads + 1
      and x3["groups"][0]["keys"][0]["files"][0]["h"] == hashlib.sha256(b"tw0!").hexdigest()[:16] and x3["music"][0]["h"] == "",
      "fingerprints are cached by size + mtime and read again once the file changes; a missing file has none")
key_files = {k["key"]: [f["file"] for f in k["files"]] for g in data["groups"] for k in g["keys"]}
key_files.update((m["key"], [m["file"]]) for m in data["music"])


def now_heard(key):
    return {f: sha16(AUDIO / f) for f in key_files[key]}


STALE = {"sfx/hop_1.ogg": "0" * 16}


def set_on_disk(key, entry):
    d = disk()
    d["keys"][key] = entry
    NOTES.write_text(json.dumps(d))


post({"hop": {"verdict": "replace"}})
check(disk()["keys"]["hop"].get("heard") == now_heard("hop"), "a verdict records the fingerprints of the sound's files ('heard')")
set_on_disk("hop", {"verdict": "replace", "note": "", "bad_variants": [], "heard": STALE})
post({"hop": {"note": "boing"}})
post({"hop": {"bad_add": [2]}})
check(disk()["keys"]["hop"]["heard"] == STALE, "a note or a flagged take alone doesn't record 'heard'")
post({"hop": {"verdict": None}})
check(disk()["keys"]["hop"]["heard"] == STALE, "clearing the verdict doesn't record 'heard'")
st, body = post({"hop": {"heard": True}})
check(st == 200 and body["rejected"] == {} and disk()["keys"]["hop"] == {"verdict": None, "note": "boing", "bad_variants": [2],
                                                                         "heard": now_heard("hop")},
      "'heard': true records the fingerprints and changes nothing else")
before, mtime, updated = NOTES.read_bytes(), NOTES.stat().st_mtime_ns, disk()["updated"]
time.sleep(1.1)   # "updated" has whole seconds
st, body = post({"hop": {"heard": True}, "jump": None})
check(st == 200 and NOTES.read_bytes() == before and NOTES.stat().st_mtime_ns == mtime and body["updated"] == updated,
      "recording the same 'heard' again isn't a change (file not rewritten, 'updated' kept)")
set_on_disk("hop", {"verdict": "tweak", "note": "boing", "bad_variants": [], "heard": STALE})
post({"hop": {"verdict": "tweak", "note": "boing!", "bad_variants": []}})   # an older page's whole entry
check(disk()["keys"]["hop"]["heard"] == now_heard("hop"), "a legacy whole-entry save (it carries the verdict) records 'heard'")
set_on_disk("hop", {"verdict": "replace", "note": "", "bad_variants": [], "heard": STALE})
post({"hop": {"verdict": "replace", "heard": True}})   # the earlier verdict, given again to the rebuilt sound
check(disk()["keys"]["hop"] == {"verdict": "replace", "note": "", "bad_variants": [], "heard": now_heard("hop")},
      "giving a rebuilt sound its earlier verdict again records 'heard'")
before = NOTES.read_text()
for val in (False, "true", 1, None, {}, ["sfx/hop_1.ogg"]):
    st, body = post({"hop": {"heard": val, "note": "not saved"}, "jump": {"note": f"saved {val!r}"}})
    why = body.get("rejected", {}).get("hop", "")
    check(st == 200 and "heard" in why and list(body["rejected"]) == ["hop"] and disk()["keys"]["jump"]["note"] == f"saved {val!r}",
          f"'heard': {json.dumps(val)} is refused for that sound only ({why[:60]})")
check(disk()["keys"]["hop"] == json.loads(before)["keys"]["hop"], "a refused 'heard' change leaves that note untouched")
music_key = data["music"][0]["key"]
post({music_key: {"verdict": "good"}})
check(disk()["keys"][music_key]["heard"] == now_heard(music_key), "a music track's verdict records that track's fingerprint")
st, body = post({"land": {"heard": True}})
check(st == 200 and "land" not in disk()["keys"], "'heard' alone doesn't create a note")
set_on_disk("land", {"verdict": None, "note": " ", "bad_variants": [], "heard": now_heard("land")})
check("land" not in json.loads(get("/api/data")[2])["notes"]["keys"], "a note with only 'heard' in it is dropped like an empty one")
d = disk()
d["orphans"]["retired_sound"] = {"verdict": "tweak", "note": "old", "bad_variants": []}
NOTES.write_text(json.dumps(d))
st, body = post({"retired_sound": {"verdict": "good", "heard": True}})
check(st == 200 and disk()["orphans"]["retired_sound"] == {"verdict": "good", "note": "old", "bad_variants": []},
      "a note for a sound no longer in the game takes 'heard' but has nothing to record")
post({"retired_sound": None, "land": None, "hop": None, "jump": None, music_key: None})

# 6c. review_baseline.json next to the notes: notes saved before "heard" existed take it from
# there (an upgrade: no warning, no .repaired copy, written with the next save); read-only
BL = SCRATCH / "baseline"
BL.mkdir()
bl_notes, bl_file = BL / "review_notes.json", BL / "review_baseline.json"
ex, hop_f, mus = key_files["explosion"], key_files["hop"], key_files[music_key][0]


def full(f):
    return hashlib.sha256((AUDIO / f).read_bytes()).hexdigest()


bl_file.write_text(json.dumps({"about": "test baseline", "files": {
    ex[0]: full(ex[0]), ex[1]: "ab" * 32, ex[2]: full(ex[2]).upper(),   # take 2 rebuilt since; case doesn't matter
    **{f: full(f) for f in hop_f[:3]},                                   # takes 4 and 5 are new files
    mus: "cd" * 32, key_files["rocket_fire"][0]: full(key_files["rocket_fire"][0]),
    key_files["rocket_fire"][1]: full(key_files["rocket_fire"][1]), "sfx/gone.ogg": "ef" * 32}}))
bl_bytes, bl_mtime = bl_file.read_bytes(), bl_file.stat().st_mtime_ns
own = {key_files["land"][0]: "1" * 16}
bl_notes.write_text(json.dumps({"version": 1, "updated": "2026-10-21T20:55:22", "keys": {
    "explosion": {"verdict": "good", "note": "", "bad_variants": [2]},
    "hop": {"verdict": "replace", "note": "", "bad_variants": []},
    "jump": {"verdict": "good", "note": "", "bad_variants": []},
    "land": {"verdict": "good", "note": "", "bad_variants": [], "heard": own},
    "rocket_fire": {"verdict": "good", "note": "", "bad_variants": []},
    music_key: {"verdict": "tweak", "note": "more fiddle", "bad_variants": []}}, "orphans": {}}))
notes_bytes = bl_notes.read_bytes()
port3 = free_port()
proc3 = start(port=port3, notes=bl_notes)
with urllib.request.urlopen(f"http://127.0.0.1:{port3}/api/data", timeout=10) as r:
    data3 = json.loads(r.read())
k3 = data3["notes"]["keys"]
check(k3["explosion"].get("heard") == {ex[0]: sha16(AUDIO / ex[0]), ex[1]: "abababababababab", ex[2]: sha16(AUDIO / ex[2])}
      and k3["hop"].get("heard") == {f: sha16(AUDIO / f) for f in hop_f[:3]} and k3[music_key].get("heard") == {mus: "cdcdcdcdcdcdcdcd"},
      "notes without 'heard' take the baseline's fingerprints of their files (the ones it lists)")
check("heard" not in k3["jump"] and k3["land"]["heard"] == own,
      "a sound the baseline doesn't list gets no 'heard'; a note's own 'heard' wins over the baseline")
check(data3["warnings"] == [] and not list(BL.glob("review_notes.json.repaired-*")) and bl_notes.read_bytes() == notes_bytes,
      "filling 'heard' in from the baseline is no repair (no warning, no .repaired copy) and doesn't write the file by itself")
st, _ = post({"jump": {"note": "lands softly"}}, base=f"http://127.0.0.1:{port3}")
d3 = json.loads(bl_notes.read_text())["keys"]
check(st == 200 and d3["explosion"].get("heard") == k3["explosion"]["heard"] and d3["hop"].get("heard") == k3["hop"]["heard"]
      and "heard" not in d3["jump"], "the filled-in 'heard' is written with the next save")
r = subprocess.run([sys.executable, str(REPO / "tools/audio/review.py"), "--notes", str(bl_notes), "--summary"],
                   capture_output=True, text=True)
lines = {ln.split("**")[1]: ln for ln in r.stdout.splitlines() if ln.startswith("- **")}
check(r.returncode == 0 and lines["explosion"].endswith(" — bad takes: 2 — rebuilt since this verdict (takes 2)")
      and lines["hop"].endswith("[REPLACE] — rebuilt since this verdict (takes 4, 5)")
      and lines[music_key].endswith(": more fiddle — rebuilt since this verdict (new file)")
      and lines["land"].endswith(f"(takes {', '.join(str(n) for n in range(1, len(key_files['land']) + 1))})")
      and "rebuilt" not in lines["jump"] + lines["rocket_fire"],
      "--summary marks verdicts given before a rebuild, with the takes (music: new file)\n    " + "\n    ".join(
          lines.get(k, "?") for k in ("explosion", "hop", music_key, "land", "jump", "rocket_fire")))
stop(proc3)
check(bl_file.read_bytes() == bl_bytes and bl_file.stat().st_mtime_ns == bl_mtime, "the baseline file is never written")
for bad_bl, why in [("{ broken", "not JSON"), (json.dumps({"files": {ex[0]: "not a sha256"}}), "a bad fingerprint"),
                    (json.dumps(["files"]), "not an object")]:
    for p in BL.glob("review_notes.json*"):
        p.unlink()
    bl_notes.write_text(notes_bytes.decode())
    bl_file.write_text(bad_bl)
    proc3 = start(port=port3, notes=bl_notes)
    with urllib.request.urlopen(f"http://127.0.0.1:{port3}/api/data", timeout=10) as r:
        data3 = json.loads(r.read())
    stop(proc3)
    log = proc3.stdout.read()
    check({k for k, e in data3["notes"]["keys"].items() if "heard" in e} == {"land"}   # only its own
          and not list(BL.glob("review_notes.json.repaired-*"))
          and len(data3["warnings"]) == 1 and "review_baseline.json" in data3["warnings"][0] and "review baseline ignored" in log,
          f"a baseline that can't be used ({why}) is ignored, with a console line and a plain warning ({data3['warnings'][0][:70]}…)")
r = subprocess.run([sys.executable, str(REPO / "tools/audio/review.py"), "--notes", str(bl_notes), "--summary"],
                   capture_output=True, text=True)
lines = {ln.split("**")[1]: ln for ln in r.stdout.splitlines() if ln.startswith("- **")}
check(r.returncode == 0 and "review baseline ignored" in r.stderr and "rebuilt since" in lines["land"]   # its own "heard"
      and not any("rebuilt" in lines[k] for k in ("explosion", "hop", music_key, "jump", "rocket_fire")),
      "--summary ignores a baseline that can't be used (and says so on stderr)")
bl_file.unlink()
bl_notes.write_text(json.dumps({"version": 1, "keys": {
    "jump": {"verdict": "good", "note": "", "bad_variants": [], "heard": {"sfx/jump_1.ogg": "XYZ"}},
    "land": {"verdict": "good", "note": "", "bad_variants": [], "heard": {f"sfx/{n}.ogg": "0" * 16 for n in range(65)}},
    "hop": {"verdict": "good", "note": "", "bad_variants": [], "heard": now_heard("hop")}}}))
bad_heard = bl_notes.read_text()
proc3 = start(port=port3, notes=bl_notes)
with urllib.request.urlopen(f"http://127.0.0.1:{port3}/api/data", timeout=10) as r:
    data3 = json.loads(r.read())
stop(proc3)
kept = list(BL.glob("review_notes.json.repaired-*"))
k3 = data3["notes"]["keys"]
check(len(kept) == 1 and kept[0].read_text() == bad_heard and "heard" not in k3["jump"] and "heard" not in k3["land"]
      and k3["hop"]["heard"] == now_heard("hop") and any("jump" in w and "land" in w and "heard" in w for w in data3["warnings"]),
      "a malformed 'heard' is dropped like other bad fields (warning + .repaired copy); a good one is kept")

# 7. headers + misc requests
st, hdrs, _ = get("/")
check(hdrs.get("X-Frame-Options") == "DENY" and "frame-ancestors 'none'" in hdrs.get("Content-Security-Policy", ""), "anti-framing headers")
req = urllib.request.Request(B + "/audio/sfx/pistol_fire_1.ogg", headers={"Range": "bytes=999999999999999999999-"})
try:
    with urllib.request.urlopen(req) as r:
        check(r.status in (200, 206), f"huge range handled ({r.status})")
except urllib.error.HTTPError as e:
    check(e.code == 416, f"huge range handled ({e.code})")
raw_s = socket.create_connection(("127.0.0.1", PORT))
raw_s.sendall(b"POST /api/notes HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Type: application/json\r\nContent-Length: 20\r\n\r\n[[[[[[[[[[[[[[[[[[[[" % PORT)
reply = raw_s.recv(200)
raw_s.close()
check(reply.startswith(b"HTTP/1.1 400"), f"malformed JSON gets a 400, not an empty reply ({reply[:20]!r})")
for method in ("PUT", "DELETE", "OPTIONS"):
    r = raw(b"%s /api/notes HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Length: 0\r\n\r\n" % (method.encode(), PORT))
    check(r.startswith(b"HTTP/1.1 405") and b"application/json" in r and b"X-Frame-Options: DENY" in r and b"Connection: close" in r,
          f"{method} gets a JSON 405 with security headers")
for bad_req, why in [(b"GARBAGE\r\n", "one-word request line"), (b"GET / HTTP/9\r\n", "bad HTTP version"),
                     (b"BREW / HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n" % PORT, "unknown method"),
                     (b"GET /" + b"a" * (65537 - 5), "URI too long")]:
    r = raw(bad_req)
    check(r[:10] in (b"HTTP/1.1 4", b"HTTP/1.1 5") and b"application/json" in r and b"Content-Security-Policy" in r,
          f"stdlib error ({why}) is JSON with a status line and CSP ({r[:24]!r})")
conn = http.client.HTTPConnection("127.0.0.1", PORT)
codes = []
for note in ("keep-alive 1", "keep-alive 2"):
    conn.request("POST", "/api/notes", json.dumps({"changes": {"wind_loop": {"note": note}}}),
                 {"Content-Type": "application/json", "Origin": B})
    resp = conn.getresponse()
    codes.append((resp.status, resp.getheader("Connection")))
    resp.read()
conn.close()
check(codes == [(200, None), (200, None)] and disk()["keys"]["wind_loop"]["note"] == "keep-alive 2",
      "successful saves keep the connection alive")

# 8. a refused request's body is never run as a second request (request smuggling)
snapshot = NOTES.read_text()
inner = json.dumps({"changes": {"smg_fire": None, "pistol_fire": {"verdict": "good", "note": "smuggled"}}}).encode()
smuggled = (b"POST /api/notes HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Type: application/json\r\n"
            b"Content-Length: %d\r\n\r\n" % (PORT, len(inner))) + inner
host = b"127.0.0.1:%d" % PORT
cases = [
    ("foreign Origin", b"POST /api/notes", host, b"Origin: https://evil.example\r\nContent-Type: text/plain\r\n"),
    ("Origin: null", b"POST /api/notes", host, b"Origin: null\r\nContent-Type: application/json\r\n"),
    ("other-port Origin", b"POST /api/notes", host, b"Origin: http://127.0.0.1:1\r\nContent-Type: text/plain\r\n"),
    ("bad Host (DNS rebinding)", b"POST /api/notes", b"evil.example:%d" % PORT, b"Content-Type: application/json\r\n"),
    ("415 text/plain", b"POST /api/notes", host, b"Content-Type: text/plain\r\n"),
    ("404 path", b"POST /whatever", host, b"Content-Type: application/json\r\n"),
    ("405 PUT", b"PUT /api/notes", host, b"Content-Type: application/json\r\n"),
    ("GET with a body", b"GET /api/ping", host, b""),
]
for why, line, h, hdrs in cases:
    r = raw(line + b" HTTP/1.1\r\nHost: " + h + b"\r\n" + hdrs + b"Content-Length: %d\r\n\r\n" % len(smuggled) + smuggled)
    check(r.count(b"HTTP/1.1 ") == 1 and b"Connection: close" in r,
          f"smuggled body after a refused request ({why}) is not run ({r.split(b' ', 2)[1:2]})")
r = raw(b"POST /api/notes HTTP/1.1\r\nHost: " + host + b"\r\nOrigin: https://evil.example\r\nContent-Type: text/plain\r\n"
        b"Transfer-Encoding: chunked\r\n\r\n" + smuggled)
check(r.count(b"HTTP/1.1 ") == 1, "smuggled body after a chunked request is not run")
r = raw(b"POST /api/notes HTTP/1.1\r\nHost: " + host + b"\r\nContent-Type: application/json\r\nContent-Length: 999999\r\n\r\n" + smuggled)
check(r.startswith(b"HTTP/1.1 413") and r.count(b"HTTP/1.1 ") == 1, "smuggled body after a too-large request is not run")
for method in (b"GET", b"HEAD", b"POST"):   # the first length says "no body", the second covers the smuggled request
    r = raw(method + b" / HTTP/1.1\r\nHost: " + host + b"\r\nContent-Type: application/json\r\nContent-Length: 0\r\n"
            b"Content-Length: %d\r\n\r\n" % len(smuggled) + smuggled)
    check(r.startswith(b"HTTP/1.1 400") and r.count(b"HTTP/1.1 ") == 1 and b"Connection: close" in r,
          f"{method.decode()} with two Content-Lengths gets a 400 and its body is not run")
check(NOTES.read_text() == snapshot, "no smuggled request changed the notes")

# 9. /api/* refuses other web pages; presence: HEAD isn't a tab, and open tabs are capped
for path in ("/api/presence", "/api/data", "/api/ping"):
    codes = [get_status(path, {"Origin": "https://evil.example"}), get_status(path, {"Sec-Fetch-Site": "cross-site"}),
             get_status(path, {"Sec-Fetch-Site": "same-site"})]
    check(codes == [403, 403, 403], f"{path} refuses foreign Origin / cross-site / same-site ({codes})")
check(get_status("/api/data", {"Origin": B, "Sec-Fetch-Site": "same-origin"}) == 200, "/api/data accepts its own page")
t0 = time.time()
r = raw(b"HEAD /api/presence HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n" % PORT)
check(r.startswith(b"HTTP/1.1 200") and r.endswith(b"\r\n\r\n") and b"retry" not in r and time.time() - t0 < 2,
      "HEAD /api/presence sends headers only and closes")
check(b"Content-Security-Policy" in r and b"X-Frame-Options: DENY" in r, "presence response carries the security headers")
tabs = []
for _ in range(8):
    s = socket.create_connection(("127.0.0.1", PORT))
    s.sendall(b"GET /api/presence HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n" % PORT)
    s.settimeout(3)
    tabs.append((s, s.recv(4096)))
check(all(h.startswith(b"HTTP/1.1 200") for _, h in tabs), "8 review tabs are tracked")
r = raw(b"HEAD /api/presence HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n" % PORT)
check(r.startswith(b"HTTP/1.1 200"), "HEAD still answers with 8 tabs open (it doesn't count as one)")
r = raw(b"GET /api/presence HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n" % PORT)
check(r.startswith(b"HTTP/1.1 503"), "a 9th presence stream is refused")
for s, _ in tabs:
    s.close()

# 10. connection cap: idle connections beyond the cap are dropped at once; the server keeps serving
idle = [socket.create_connection(("127.0.0.1", PORT)) for _ in range(40)]
time.sleep(0.5)
dropped = 0
for s in idle:
    s.settimeout(0.2)
    try:
        dropped += s.recv(1) == b""
    except (socket.timeout, ConnectionResetError):
        pass
for s in idle:
    s.close()
time.sleep(0.3)
check(dropped >= 8 and get("/api/ping")[0] == 200, f"connections over the cap are dropped ({dropped} of 40) and the server still answers")

# 11. single instance: a second launch on the same port/notes reuses the first
second = subprocess.run([sys.executable, str(REPO / "tools/audio/review.py"), "--no-browser", "--port", str(PORT), "--notes", str(NOTES)],
                        capture_output=True, text=True, timeout=10)
check("already running" in second.stdout and "older version" not in second.stdout, "second launch reuses the running server")
ping = json.loads(get("/api/ping")[2])
stop(proc)


class OlderServer(BaseHTTPRequestHandler):
    """An older review.py on the same port and notes: its ping says no "protocol"."""

    def do_GET(self):
        body = json.dumps({"app": ping["app"], "notes": ping["notes"]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


older = ThreadingHTTPServer(("127.0.0.1", PORT), OlderServer)
threading.Thread(target=older.serve_forever, daemon=True).start()
third = subprocess.run([sys.executable, str(REPO / "tools/audio/review.py"), "--no-browser", "--port", str(PORT), "--notes", str(NOTES)],
                       capture_output=True, text=True, timeout=10)
older.shutdown()
older.server_close()
check("already running" in third.stdout and "older version" in third.stdout and "close every Audio Review tab" in third.stdout
      and "any opened earlier too" in third.stdout,
      "a launch that finds an older review server running says to close every review tab (an earlier one keeps it running)")

# 12. notes the player has to tidy up: original kept once as .repaired-*, page warned
NOTES.write_text(json.dumps({"version": 1, "keys": {
    "hop": {"verdict": "Replace", "note": "", "bad_variants": []}, "land": {"note": "x" * 4100},
    "jump": {"bad_variants": [0, 2]}, "smg_fire": {"verdict": "good", "note": "", "bad_variants": []}}}))
original = NOTES.read_text()
proc = start()
data = json.loads(get("/api/data")[2])
kept = list(SCRATCH.glob("notes.json.repaired-*"))
check(len(kept) == 1 and kept[0].read_text() == original, "original of a repaired file is kept as .repaired-*")
check(any(str(kept[0]) in w and "hop" in w and "land" in w for w in data["warnings"]), "page is told which notes were tidied and where the original is")
post({"pistol_fire": {"verdict": "good"}})   # rewrites the file tidied up
stop(proc)
NOTES.write_text(original)                   # the same odd file again: no second copy
proc = start()
check(len(list(SCRATCH.glob("notes.json.repaired-*"))) == 1, "the same original isn't copied twice")
stop(proc)
NOTES.write_text(json.dumps({"version": 2, "todo_for_build": ["hop"], "keys": {"hop": {"verdict": "good", "note": "", "bad_variants": []}}}))
proc = start()
data = json.loads(get("/api/data")[2])
kept = [p for p in SCRATCH.glob("notes.json.repaired-*") if "todo_for_build" in p.read_text()]
check(len(kept) == 1 and any(str(kept[0]) in w and "todo_for_build" in w and "version 2" in w for w in data["warnings"]),
      "unknown top-level fields and another version are reported, and the original is kept")
post({"jump": {"verdict": "tweak"}})
check(sorted(disk()) == ["keys", "orphans", "updated", "version"] and "todo_for_build" in kept[0].read_text(),
      "the next save writes the tidied file; the kept copy still has the extra field")
stop(proc)

# 13b (runs alongside 13, on its own server). A client sending its request a byte at a
# time restarts the socket timeout with every byte, but must still lose its slot once
# REQUEST_TIMEOUT has passed: a full house of them can't lock the page out for good.
DRIP_PORT, drip = free_port(), {}


def drip_check():
    dproc = start(port=DRIP_PORT, notes=SCRATCH / "drip-notes.json")
    url = f"http://127.0.0.1:{DRIP_PORT}/api/ping"
    socks = [socket.create_connection(("127.0.0.1", DRIP_PORT)) for _ in range(review.MAX_CONNECTIONS)]
    line = b"GET / HTTP/1.1\r\nX-Pad: " + b"a" * 100
    try:
        for s in socks:
            s.sendall(line[:1])
        time.sleep(0.5)
        try:
            urllib.request.urlopen(url, timeout=2).read()
            drip["locked"] = False
        except OSError:
            drip["locked"] = True   # every slot is held by a dripper
        t0, i = time.time(), 1
        while time.time() - t0 < review.REQUEST_TIMEOUT + 4:
            time.sleep(3)
            for s in socks:
                try:
                    s.sendall(line[i:i + 1])
                except OSError:
                    pass
            i += 1
        try:
            drip["after"] = urllib.request.urlopen(url, timeout=2).status
        except OSError as e:
            drip["after"] = repr(e)
    finally:
        for s in socks:
            s.close()
        stop(dproc)


drip_thread = threading.Thread(target=drip_check, daemon=True)
drip_thread.start()

# 13. idle-exit: stays up while a presence stream is open, a ping restarts the grace, stops after
proc = start("--idle-exit")
pres = socket.create_connection(("127.0.0.1", PORT))
pres.sendall(b"GET /api/presence HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n" % PORT)
time.sleep(25)   # longer than the 20 s grace
check(proc.poll() is None, "server stays up while the tab (presence stream) is open")
pres.close()
time.sleep(14)
urllib.request.urlopen(B + "/api/ping", timeout=2)   # a relaunch checking for a running server
time.sleep(12)   # 26 s after the tab closed, 12 s after the ping
check(proc.poll() is None, "a relaunch's ping inside the grace keeps the server up")
t0 = time.time()
while proc.poll() is None and time.time() - t0 < 40:
    time.sleep(1)
check(proc.poll() is not None, f"server stops after the tab closes ({time.time() - t0:.0f} s after the check)")
drip_thread.join(60)
check(drip.get("locked") is True and drip.get("after") == 200,
      f"{review.MAX_CONNECTIONS} slow-drip clients hold every slot only until REQUEST_TIMEOUT ({drip})")

# 14. --summary on a corrupt file fails loudly
NOTES.write_text("{oops")
r = subprocess.run([sys.executable, str(REPO / "tools/audio/review.py"), "--notes", str(NOTES), "--summary"], capture_output=True, text=True)
check(r.returncode == 1 and "could not be read" in r.stderr, "--summary reports a corrupt file and exits 1")

# 15. launcher (isolated XDG dirs and a fake HOME with its own Desktop: the real ones are never touched)
home = SCRATCH / "home"
(home / "Desktop").mkdir(parents=True)
env = dict(os.environ, XDG_DATA_HOME=str(SCRATCH / "xdg"), HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
           XDG_DESKTOP_DIR=str(home / "Desktop"))
subprocess.run([sys.executable, str(REPO / "tools/audio/review.py"), "--install-launcher"], env=env, check=True, capture_output=True)
entry = SCRATCH / "xdg/applications/bunny-beat-down-audio-review.desktop"
desk = entry.read_text()
exec_line = next(l for l in desk.splitlines() if l.startswith("Exec="))
check(exec_line.startswith('Exec="') and "--idle-exit" in exec_line, f"launcher Exec is quoted: {exec_line[:90]}")
check(not (home / "Desktop" / entry.name).exists(), "sandboxed install leaves the Desktop alone")
q = review._desktop_quote("/x\nExec=evil\t\r")
check("\n" not in q and "\t" not in q and "\r" not in q and "\\n" in q, f"Exec quoting escapes line breaks ({q})")
check(review._keyfile_escape(" lead") == "\\slead", "a leading space is escaped as \\s")
odd = SCRATCH / "odd\nExec=touch pwned" / "tools" / "audio"
odd.mkdir(parents=True)
shutil.copy2(REPO / "tools/audio/review.py", odd / "review.py")
env_odd = dict(env, XDG_DATA_HOME=str(SCRATCH / "xdg-odd"))
r = subprocess.run([sys.executable, str(odd / "review.py"), "--install-launcher"], env=env_odd, capture_output=True, text=True)
check(r.returncode != 0 and "control character" in r.stderr and not (SCRATCH / "xdg-odd/applications").exists(),
      "install refuses a path with a line break in it")
(home / "Desktop" / entry.name).write_text("[Desktop Entry]\n")   # stands in for the owner's real shortcut
subprocess.run([sys.executable, str(REPO / "tools/audio/review.py"), "--remove-launcher"], env=env, check=True, capture_output=True)
check(not entry.exists() and (home / "Desktop" / entry.name).exists(),
      "sandboxed --remove-launcher removes its own entry and leaves the Desktop shortcut alone")

# 16. the checklist (or manifest) can't be read for a moment (a typo, a half-written
# build): saves still go through against the last good sound list, and the page is
# told why. In a sandbox copy, so the real checklist is never touched.
sbx = SCRATCH / "sbx"
(sbx / "tools/audio").mkdir(parents=True)
(sbx / "assets").mkdir()
shutil.copy2(REPO / "tools/audio/review.py", sbx / "tools/audio/review.py")
shutil.copy2(REPO / "tools/audio/review_checklist.json", sbx / "tools/audio/review_checklist.json")
os.symlink(REPO / "tools/audio/review_page", sbx / "tools/audio/review_page")
os.symlink(REPO / "assets/audio", sbx / "assets/audio")
os.symlink(REPO / "data", sbx / "data")
port2 = free_port()
B2 = f"http://127.0.0.1:{port2}"
notes2 = SCRATCH / "sbx-notes.json"
proc = start(script=sbx / "tools/audio/review.py", port=port2, notes=notes2)
checklist = sbx / "tools/audio/review_checklist.json"
good = checklist.read_text()
checklist.write_text("{ broken" + good[1:])
st, body = post({"hop": {"verdict": "tweak"}}, base=B2)
check(st == 200 and body.get("rejected") == {} and json.loads(notes2.read_text())["keys"]["hop"]["verdict"] == "tweak",
      f"a save while the checklist can't be read still goes through ({st}: {str(body)[:80]})")
with urllib.request.urlopen(B2 + "/api/data", timeout=10) as r:
    data = json.loads(r.read())
check(r.status == 200 and any("couldn't be re-read" in w and "review_checklist.json" in w for w in data["warnings"])
      and any(k["key"] == "hop" for g in data["groups"] for k in g["keys"]),
      "/api/data keeps the last good sound list and says why")
checklist.write_text(good)
with urllib.request.urlopen(B2 + "/api/data", timeout=10) as r:
    data = json.loads(r.read())
check(not any("couldn't be re-read" in w for w in data["warnings"]), "the warning goes once the checklist is fixed")
stop(proc)
saved_checklist = review.CHECKLIST
try:
    review.CHECKLIST = SCRATCH / "broken-checklist.json"
    review.CHECKLIST.write_text("{ broken")
    try:
        with contextlib.redirect_stdout(io.StringIO()):   # its log line
            review.Catalog().get()
        check(False, "no sound list at all: refused as unavailable")
    except review.NotesUnavailable as e:   # the server answers 503 (retried), never 400
        check("broken-checklist.json" in str(e), f"no sound list at all: refused as unavailable ({str(e)[:90]}…)")
finally:
    review.CHECKLIST = saved_checklist

print("\nALL PASS" if ok else "\nSOME FAILED")
sys.exit(0 if ok else 1)
