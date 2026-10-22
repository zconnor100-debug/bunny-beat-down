#!/usr/bin/env python3
"""Tests for tools/notes/notes.py (stdlib only; temp notes files and a free port,
so the real tools/notes/game_notes.json and a running Game Notes page are never touched).

    python3 tools/notes/test_notes.py
"""
import http.client
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import notes  # noqa: E402

FAILS = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f"  ({detail})"))
    if not cond:
        FAILS.append(name)


def start(path: Path):
    srv = notes.NotesServer(("127.0.0.1", 0), path)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


def request(srv, method, url, body=None, headers=None):
    port = srv.server_address[1]
    h = {"Host": f"127.0.0.1:{port}"}
    if body is not None:
        h["Content-Type"] = "application/json"
        body = json.dumps(body).encode() if not isinstance(body, bytes) else body
    h.update(headers or {})
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    c.request(method, url, body=body, headers=h)
    r = c.getresponse()
    data = r.read()
    c.close()
    try:
        return r.status, json.loads(data)
    except ValueError:
        return r.status, data


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="bbd-notes-test-"))
    path = tmp / "game_notes.json"
    srv = start(path)
    post = lambda req, **kw: request(srv, "POST", "/api/notes", req, **kw)

    st, page = request(srv, "GET", "/")
    check("page served", st == 200 and b"Game Notes" in page)
    st, data = request(srv, "GET", "/api/notes")
    check("empty listing without a file", st == 200 and data["notes"] == [] and not path.exists())
    st, ping = request(srv, "GET", "/api/ping")
    check("ping names the app and file", ping.get("app") == notes.APP_ID and Path(ping["notes"]) == path)

    st, data = post({"action": "add", "text": "  Frogs jump too high  ", "category": "Characters"})
    n1 = data["notes"][0] if st == 200 else {}
    check("add", st == 200 and n1.get("id") == 1 and n1["status"] == "new"
          and n1["thread"][0] == {"who": "you", "text": "Frogs jump too high", "at": n1["thread"][0]["at"]})
    check("add records owner activity", notes.age_s(data["owner_activity"]) < 5)
    post({"action": "add", "text": "Louder rain", "category": "Audio"})
    st, data = post({"action": "edit", "id": 1, "text": "Frogs jump about half as high", "category": "Gameplay"})
    n1 = data["notes"][0]
    check("edit your latest words + category", n1["thread"][-1]["text"] == "Frogs jump about half as high"
          and n1["category"] == "Gameplay" and len(n1["thread"]) == 1)

    for name, req, want in [
        ("empty note refused", {"action": "add", "text": "   ", "category": "Bug"}, 409),
        ("unknown category refused", {"action": "add", "text": "x", "category": "Nope"}, 409),
        ("too long refused", {"action": "add", "text": "x" * (notes.MAX_TEXT + 1), "category": "Bug"}, 409),
        ("unknown id refused", {"action": "delete", "id": 99}, 409),
        ("string id refused", {"action": "delete", "id": "1"}, 409),
        ("unknown action refused", {"action": "wipe"}, 409),
        ("non-object refused", [1, 2], 409),
    ]:
        st, data = post(req)
        check(name, st == want and "error" in data, (st, data))

    # security
    st, _ = request(srv, "GET", "/api/notes", headers={"Host": "evil.example:80"})
    check("foreign Host refused (DNS rebinding)", st == 421)
    st, _ = post({"action": "add", "text": "x", "category": "Bug"}, headers={"Origin": "http://evil.example"})
    check("foreign Origin refused", st == 403)
    st, _ = post({"action": "add", "text": "x", "category": "Bug"}, headers={"Sec-Fetch-Site": "cross-site"})
    check("cross-site fetch refused", st == 403)
    st, _ = request(srv, "POST", "/api/notes", b'{"action":"delete","id":1}', headers={"Content-Type": "text/plain"})
    check("non-JSON content type refused", st == 415)
    st, _ = request(srv, "POST", "/api/notes", b"x" * (notes.MAX_BODY + 1))
    check("oversized body refused", st == 413)
    st, _ = request(srv, "DELETE", "/api/notes")
    check("other methods refused", st == 405)
    st, _ = request(srv, "GET", "/../notes.py")
    check("no files outside the page", st == 404)
    check("only the original two notes exist", [n["id"] for n in notes.read_notes(path)["notes"]] == [1, 2])

    # Claude's side
    claimed = notes.claim(path)
    check("claim takes every new note", [n["id"] for n in claimed] == [1, 2]
          and all(n["status"] == "working" for n in notes.read_notes(path)["notes"]))
    st, data = post({"action": "edit", "id": 1, "text": "changed my mind", "category": "Gameplay"})
    check("no edits while Claude works on it", st == 409)
    notes.claude_answer(path, 1, "done", "Frog jump height halved.")
    notes.claude_answer(path, 2, "needs_you", "Rain or the storm loop?")
    st, data = post({"action": "edit", "id": 2, "text": "x", "category": "Audio"})
    check("can't edit once Claude answered", st == 409)
    st, data = post({"action": "reply", "id": 2, "text": "The storm loop"})
    n2 = next(n for n in data["notes"] if n["id"] == 2)
    check("answering a question reopens it", n2["status"] == "new" and [m["who"] for m in n2["thread"]] == ["you", "claude", "you"])
    st, data = post({"action": "reply", "id": 1, "text": ""})
    check("reopen a done note without a comment", st == 200 and data["notes"][0]["status"] == "new")
    st, data = post({"action": "delete", "id": 1})
    check("delete", [n["id"] for n in data["notes"]] == [2])
    st, data = post({"action": "add", "text": "after delete", "category": "Other"})
    check("ids are never reused", data["notes"][-1]["id"] == 3)

    # the quiet-hour rule
    d = notes.read_notes(path)
    t = time.time()
    check("not ready right after a change", not notes.ready(d, 3600, now=t))
    check("ready after an hour of quiet", notes.ready(d, 3600, now=t + 3601))
    for n in d["notes"]:
        n["status"] = "done"
    check("never ready without new notes", not notes.ready(d, 3600, now=t + 99999))
    path2 = tmp / "quiet.json"
    notes.change(path2, lambda data: notes.apply_owner(data, {"action": "add", "text": "x", "category": "Bug"}))
    data2 = notes.read_notes(path2)
    data2["owner_activity"] = "2000-01-01T00:00:00+00:00"
    notes.write_notes(path2, data2)
    r = subprocess.run([sys.executable, notes.__file__, "--notes", str(path2), "--wait-idle", "60", "--poll", "0.1"],
                       capture_output=True, text=True, timeout=20)
    check("--wait-idle prints the ready notes and exits", r.returncode == 0 and "Note 1" in r.stdout, r.stderr)
    check("watcher heartbeat written", notes.heartbeat_path(path2).exists())

    # a damaged file is never overwritten
    bad = tmp / "bad.json"
    bad.write_text("{not json", encoding="utf-8")
    try:
        notes.change(bad, lambda data: notes.apply_owner(data, {"action": "add", "text": "x", "category": "Bug"}))
        ok = False
    except notes.NotesError:
        ok = True
    check("damaged file refused and left alone", ok and bad.read_text() == "{not json")
    check("no temp file left behind", not any(p.name.endswith(".tmp") for p in tmp.iterdir()))

    # launcher goes into a sandboxed XDG_DATA_HOME only
    os.environ["XDG_DATA_HOME"] = str(tmp / "xdg")
    notes.install_launcher()
    entry = tmp / "xdg" / "applications" / notes.LAUNCHER_NAME
    text = entry.read_text() if entry.exists() else ""
    check("launcher written to the sandbox", "Exec=" in text and "--idle-exit" in text and "Game Notes" in text)
    notes.remove_launcher()
    check("launcher removed", not entry.exists())

    srv.shutdown()
    srv.server_close()
    shutil.rmtree(tmp, ignore_errors=True)
    print("\nALL PASS" if not FAILS else f"\n{len(FAILS)} FAILED: {', '.join(FAILS)}")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
