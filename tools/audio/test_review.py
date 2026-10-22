"""End-to-end tests for the audio review server (tools/audio/review.py).

    python3 tools/audio/test_review.py

Runs real server processes against a temporary notes file on a free port, so
the owner's tools/audio/review_notes.json is never touched. Covers: corrupt
notes moved aside, repaired notes kept once, per-key merging between tabs,
field-level changes (two tabs editing different fields of one sound), per-key
rejection, idempotent deletes, close-time save ids, orphans, the protocol
marker, audio file versions (so the page reloads a rebuilt sound), security
headers, smuggled request bodies (also behind a doubled Content-Length), foreign
origins, presence (HEAD, cap, cross-origin), malformed requests, the connection
cap and slow-drip clients, single-instance reuse, unknown top-level fields,
--idle-exit (presence and relaunch grace), --summary errors, the launcher
(quoting, control characters, sandboxed removal) and saving while the checklist
can't be read (in a sandbox copy). Exits non-zero on any failure (CI).
"""
import atexit
import contextlib
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
check(data.get("protocol") == 2, "/api/data says protocol 2")
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
e = disk()["keys"]["lmg_fire"]
check(e == {"verdict": "good", "note": "belt rattle too loud", "bad_variants": []}, f"note and verdict patches both kept ({e})")
post({"hop": {"bad_add": [1]}})                                  # tab A flags take 1
post({"hop": {"bad_add": [3, 3]}})                               # tab B flags take 3
check(disk()["keys"]["hop"]["bad_variants"] == [1, 3], "bad_add from two tabs merges (sorted, unique)")
post({"hop": {"bad_remove": [1, 2]}})
check(disk()["keys"]["hop"]["bad_variants"] == [3], "bad_remove removes just those takes")
post({"lmg_fire": {"verdict": None}})
check(disk()["keys"]["lmg_fire"] == {"verdict": None, "note": "belt rattle too loud", "bad_variants": []},
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
check("already running" in second.stdout, "second launch reuses the running server")
stop(proc)

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
