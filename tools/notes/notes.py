#!/usr/bin/env python3
"""Bunny Beat Down — game notes: write down changes you want, Claude picks them up.

    python3 tools/notes/notes.py                     # open the notes page in your browser
    python3 tools/notes/notes.py --install-launcher  # Desktop shortcut + app-menu entry

Every note autosaves to tools/notes/game_notes.json (git-ignored). Each note is a
short thread: what you want changed, then Claude's answer (done, or a question
for you), then your reply if you reopen it. Claude waits for a quiet spell before
starting, so you can keep adding notes while you play:

    python3 tools/notes/notes.py --wait-idle 10      # returns once there are new notes
                                                     # and nothing changed for 10 min
    python3 tools/notes/notes.py --claim             # new -> working, printed for Claude
    python3 tools/notes/notes.py --done 3 "what changed"
    python3 tools/notes/notes.py --needs-you 4 "a question"

The server is standard-library Python bound to 127.0.0.1, answers only its own
host name, refuses requests made by other web pages, and only ever writes the
notes file (atomically, under a lock shared with the command-line tools).
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import shutil
import sys
import threading
import time
import urllib.request
import webbrowser
from contextlib import contextmanager
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PAGE = HERE / "page"
NOTES = HERE / "game_notes.json"
APP_ID = "bbd-game-notes"
DEFAULT_PORT = 8766              # Audio Review uses 8765
MAX_BODY = 64 * 1024
MAX_TEXT = 4000
MAX_NOTES = 2000
REQUEST_TIMEOUT = 30
IDLE_EXIT_S = 300                # --idle-exit: no page request for this long = the tab was closed
NEVER_CONNECTED_S = 120
WATCHER_FRESH_S = 150            # the watcher touches its heartbeat every poll (30 s)
IDLE_MINUTES = 10                # Claude starts once nothing was added or edited for this long
CATEGORIES = ("Gameplay", "Characters", "Weapons", "Map", "Visuals", "Audio", "Menus & UI", "Bug", "Other")
STATUSES = ("new", "working", "done", "needs_you")
STATIC = {"/": ("index.html", "text/html; charset=utf-8"),
          "/app.js": ("app.js", "text/javascript; charset=utf-8"),
          "/style.css": ("style.css", "text/css; charset=utf-8"),
          "/icon.png": ("../notes_icon.png", "image/png")}
SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": ("default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; "
                                "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"),
}


# ---------------------------------------------------------------------------
# the notes file
# ---------------------------------------------------------------------------
class NotesError(Exception):
    """A change that can't be made (the message is shown to the user)."""


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def age_s(iso: str | None, now: float | None = None) -> float:
    if not iso:
        return float("inf")
    return (time.time() if now is None else now) - datetime.fromisoformat(iso).timestamp()


def empty() -> dict:
    return {"version": 1, "next_id": 1, "owner_activity": None, "notes": []}


def heartbeat_path(path: Path) -> Path:
    return path.with_name("." + path.name + ".watcher")


@contextmanager
def locked(path: Path):
    """One writer at a time across the server and the command-line tools."""
    with open(path.with_name("." + path.name + ".lock"), "a") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(fh, fcntl.LOCK_UN)


def read_notes(path: Path) -> dict:
    if not path.exists():
        return empty()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise NotesError(f"{path.name} can't be read ({type(e).__name__}); nothing will be saved until it is "
                         "fixed or moved aside") from None
    if not (isinstance(data, dict) and isinstance(data.get("notes"), list) and type(data.get("next_id")) is int):
        raise NotesError(f"{path.name} isn't a notes file; nothing will be saved until it is fixed or moved aside")
    return data


def write_notes(path: Path, data: dict) -> None:
    tmp = path.with_name(path.name + ".tmp")
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def change(path: Path, fn):
    """Read, apply fn(data) -> result, write: all under the lock."""
    with locked(path):
        data = read_notes(path)
        result = fn(data)
        write_notes(path, data)
        return result


def find(data: dict, note_id: object) -> dict:
    if type(note_id) is not int:
        raise NotesError("that note id isn't a number")
    for n in data["notes"]:
        if n.get("id") == note_id:
            return n
    raise NotesError(f"note {note_id} doesn't exist (deleted?)")


def clean_text(text: object, allow_empty: bool = False) -> str:
    if not isinstance(text, str):
        raise NotesError("the note has to be text")
    text = text.replace("\r\n", "\n").strip()
    if not text and not allow_empty:
        raise NotesError("the note is empty")
    if len(text) > MAX_TEXT:
        raise NotesError(f"the note is longer than {MAX_TEXT} characters; split it into a few notes")
    return text


def clean_category(cat: object) -> str:
    if cat not in CATEGORIES:
        raise NotesError("unknown category")
    return cat


def _say(note: dict, who: str, text: str) -> None:
    note["thread"].append({"who": who, "text": text, "at": now_iso()})
    note["updated"] = note["thread"][-1]["at"]


def apply_owner(data: dict, req: object) -> dict:
    """A change from the page. Every one counts as owner activity (the idle clock)."""
    if not isinstance(req, dict):
        raise NotesError("bad request")
    action = req.get("action")
    if action == "add":
        if len(data["notes"]) >= MAX_NOTES:
            raise NotesError("too many notes; delete some finished ones first")
        note = {"id": data["next_id"], "category": clean_category(req.get("category")), "status": "new",
                "created": now_iso(), "thread": []}
        _say(note, "you", clean_text(req.get("text")))
        data["next_id"] += 1
        data["notes"].append(note)
    elif action == "edit":   # your latest words, while Claude hasn't answered them
        note = find(data, req.get("id"))
        if note["status"] == "working":
            raise NotesError("Claude is working on this one; add a new note (or reply when it's done)")
        if note["thread"][-1]["who"] != "you":
            raise NotesError("Claude already answered this; reply instead")
        note["thread"][-1]["text"] = clean_text(req.get("text"))
        note["category"] = clean_category(req.get("category", note["category"]))
        note["updated"] = now_iso()
    elif action == "reply":  # answer Claude's question, or reopen a finished note with more to do
        note = find(data, req.get("id"))
        if note["status"] == "working":
            raise NotesError("Claude is working on this one; add a new note for anything else")
        text = clean_text(req.get("text"), allow_empty=True)
        if text:
            _say(note, "you", text)
        elif note["status"] != "done":
            raise NotesError("the reply is empty")
        note["status"] = "new"
        note["updated"] = now_iso()
    elif action == "delete":
        note = find(data, req.get("id"))
        data["notes"].remove(note)
    else:
        raise NotesError("unknown action")
    data["owner_activity"] = now_iso()
    return data


def claude_answer(path: Path, note_id: int, status: str, text: str) -> dict:
    def fn(data):
        note = find(data, note_id)
        _say(note, "claude", clean_text(text))
        note["status"] = status
        return note
    return change(path, fn)


def claim(path: Path) -> list[dict]:
    """New notes -> working (the page shows Claude is on them)."""
    def fn(data):
        got = [n for n in data["notes"] if n["status"] == "new"]
        for n in got:
            n["status"] = "working"
            n["updated"] = now_iso()
        return got
    return change(path, fn)


def ready(data: dict, idle_s: float, now: float | None = None) -> bool:
    """There are new notes and the owner hasn't changed anything for idle_s."""
    pending = any(n["status"] == "new" for n in data["notes"])
    return pending and age_s(data.get("owner_activity"), now) >= idle_s


def as_markdown(notes: list[dict]) -> str:
    out = []
    for n in notes:
        out.append(f"## Note {n['id']} [{n['category']}] ({n['status']})")
        for m in n["thread"]:
            who = "Owner" if m["who"] == "you" else "Claude"
            out.append(f"**{who}** ({m['at']}):\n{m['text']}\n")
    return "\n".join(out) if out else "(no notes)"


def wait_idle(path: Path, minutes: float, poll: float = 30.0) -> int:
    """Block until ready(); keeps a heartbeat file fresh so the page can say Claude is watching."""
    hb = heartbeat_path(path)
    while True:
        try:
            hb.write_text(now_iso() + "\n", encoding="utf-8")
            data = read_notes(path)
            if ready(data, minutes * 60):
                print(as_markdown([n for n in data["notes"] if n["status"] == "new"]), flush=True)
                return 0
        except NotesError as e:
            print(f"warning: {e}", file=sys.stderr, flush=True)
        time.sleep(poll)


# ---------------------------------------------------------------------------
# server
# ---------------------------------------------------------------------------
class NotesServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, addr, notes_path: Path):
        super().__init__(addr, Handler)
        self.notes_path = notes_path
        self.last_request = time.monotonic()
        self.ever_connected = False
        if notes_path.exists():   # the file as it was at startup, in case something goes wrong
            shutil.copyfile(notes_path, notes_path.with_name(notes_path.name + ".bak"))

    @property
    def origin_hosts(self) -> set[str]:
        port = self.server_address[1]
        return {f"127.0.0.1:{port}", f"localhost:{port}"}

    def listing(self) -> dict:
        data = read_notes(self.notes_path)
        try:
            seen = heartbeat_path(self.notes_path).read_text(encoding="utf-8").strip()
        except OSError:
            seen = None
        return {"notes": data["notes"], "owner_activity": data.get("owner_activity"),
                "watching": age_s(seen) < WATCHER_FRESH_S if seen else False,
                "idle_minutes": IDLE_MINUTES, "categories": list(CATEGORIES), "server_time": now_iso()}


class Handler(BaseHTTPRequestHandler):
    server: NotesServer
    server_version = "BBDGameNotes/1.0"
    protocol_version = "HTTP/1.1"
    timeout = REQUEST_TIMEOUT

    def log_message(self, fmt, *args):
        pass

    def _send(self, status: int, body: bytes, ctype: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in SECURITY_HEADERS.items():
            self.send_header(k, v)
        if status >= 400:
            self.send_header("Connection", "close")   # never parse a leftover body as a next request
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, obj, status: int = 200) -> None:
        self._send(status, json.dumps(obj, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

    def _error(self, status: int, msg: str) -> None:
        self._json({"error": msg}, status)

    def _allowed(self) -> bool:
        """Only our own page: right Host (DNS rebinding), no foreign Origin or cross-site fetch."""
        if self.headers.get("Host", "") not in self.server.origin_hosts:
            self._error(HTTPStatus.MISDIRECTED_REQUEST, "wrong host")
            return False
        origin = self.headers.get("Origin")
        if origin is not None:
            o = urlsplit(origin)
            if o.scheme != "http" or o.netloc not in self.server.origin_hosts:
                self._error(HTTPStatus.FORBIDDEN, "cross-origin request refused")
                return False
        if self.headers.get("Sec-Fetch-Site", "same-origin") not in ("same-origin", "none"):
            self._error(HTTPStatus.FORBIDDEN, "cross-site request refused")
            return False
        self.server.last_request = time.monotonic()
        self.server.ever_connected = True
        return True

    def do_GET(self):
        if not self._allowed():
            return
        path = urlsplit(self.path).path
        try:
            if path == "/api/notes":
                return self._json(self.server.listing())
            if path == "/api/ping":
                return self._json({"app": APP_ID, "notes": str(self.server.notes_path)})
        except NotesError as e:
            return self._error(HTTPStatus.CONFLICT, str(e))
        if path in STATIC:
            name, ctype = STATIC[path]
            try:
                body = (PAGE / name).read_bytes()
            except OSError:
                return self._error(HTTPStatus.NOT_FOUND, "not found")
            return self._send(HTTPStatus.OK, body, ctype)
        self._error(HTTPStatus.NOT_FOUND, "not found")

    def do_HEAD(self):
        self.do_GET()

    def do_POST(self):
        if not self._allowed():
            return
        if urlsplit(self.path).path != "/api/notes":
            return self._error(HTTPStatus.NOT_FOUND, "not found")
        if self.headers.get("Content-Type", "").split(";")[0].strip() != "application/json":
            return self._error(HTTPStatus.UNSUPPORTED_MEDIA_TYPE, "expected application/json")
        if self.headers.get("Transfer-Encoding") or len(self.headers.get_all("Content-Length") or []) != 1:
            return self._error(HTTPStatus.BAD_REQUEST, "bad Content-Length")
        try:
            n = int(self.headers["Content-Length"])
        except ValueError:
            return self._error(HTTPStatus.BAD_REQUEST, "bad Content-Length")
        if n < 0 or n > MAX_BODY:
            return self._error(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "request too large")
        try:
            req = json.loads(self.rfile.read(n))
        except ValueError:
            return self._error(HTTPStatus.BAD_REQUEST, "bad JSON")
        try:
            change(self.server.notes_path, lambda data: apply_owner(data, req))
            self._json(self.server.listing())
        except NotesError as e:
            self._error(HTTPStatus.CONFLICT, str(e))

    def _not_allowed(self):
        self._error(HTTPStatus.METHOD_NOT_ALLOWED, "method not allowed")

    do_PUT = do_DELETE = do_PATCH = do_OPTIONS = _not_allowed


def existing_instance(port: int, notes_path: Path) -> str | None:
    url = f"http://127.0.0.1:{port}/"
    try:
        with urllib.request.urlopen(url + "api/ping", timeout=0.8) as r:
            info = json.loads(r.read())
        if info.get("app") == APP_ID and Path(info.get("notes", "")) == notes_path:
            return url
    except Exception:
        pass
    return None


def serve(notes_path: Path, port: int | None, open_browser: bool, idle_exit: bool) -> None:
    want = DEFAULT_PORT if port is None else port
    running = existing_instance(want, notes_path) if want else None
    if running:
        print(f"Game notes are already open at {running}", flush=True)
        if open_browser:
            webbrowser.open(running)
        return
    try:
        httpd = NotesServer(("127.0.0.1", want), notes_path)
    except OSError:
        if port is not None:
            raise
        httpd = NotesServer(("127.0.0.1", 0), notes_path)
    url = f"http://127.0.0.1:{httpd.server_address[1]}/"
    print(f"Game notes: {url}   (Ctrl+C to stop; notes -> {notes_path})", flush=True)
    if idle_exit:
        def watchdog():
            while True:
                time.sleep(5)
                quiet = time.monotonic() - httpd.last_request
                if quiet > (IDLE_EXIT_S if httpd.ever_connected else NEVER_CONNECTED_S):
                    print("notes page closed — stopping", flush=True)
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
# Desktop launcher (same scheme as tools/audio/review.py)
# ---------------------------------------------------------------------------
LAUNCHER_NAME = "bunny-beat-down-game-notes.desktop"
CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f]")


def _keyfile_escape(value: str) -> str:
    out = value.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")
    return "\\s" + out[1:] if out.startswith(" ") else out


def _desktop_quote(arg: str) -> str:
    quoted = '"' + re.sub(r'([\\"`$])', r'\\\1', arg) + '"'
    return _keyfile_escape(quoted).replace("%", "%%")


def _launcher_targets() -> tuple[Path, Path | None]:
    """(app-menu entry, Desktop shortcut or None); a redirected XDG_DATA_HOME
    (tests) never touches the real Desktop."""
    apps = Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share")) / "applications"
    desk = None
    if not os.environ.get("XDG_DATA_HOME"):
        try:
            import subprocess
            out = subprocess.run(["xdg-user-dir", "DESKTOP"], capture_output=True, text=True, timeout=5).stdout.strip()
            desk = Path(out) if out and Path(out).is_dir() and Path(out) != Path.home() else None
        except (OSError, ValueError, Exception):
            pass
        if desk is None and (Path.home() / "Desktop").is_dir():
            desk = Path.home() / "Desktop"
    return apps / LAUNCHER_NAME, (desk / LAUNCHER_NAME if desk else None)


def install_launcher() -> None:
    script, icon = str(Path(__file__).resolve()), str(HERE / "notes_icon.png")
    for p in (sys.executable, script, icon):
        if CONTROL_CHARS.search(p):
            raise SystemExit(f"Not installing the launcher: {p!r} has a control character in it.")
    exec_line = " ".join(_desktop_quote(a) for a in [sys.executable, script, "--idle-exit"])
    text = (f"[Desktop Entry]\nType=Application\nVersion=1.0\nName={_keyfile_escape('Bunny Beat Down — Game Notes')}\n"
            "GenericName=Game change notes\n"
            "Comment=Write down changes you want in Bunny Beat Down; Claude works through them\n"
            f"Exec={exec_line}\nIcon={_keyfile_escape(icon)}\nTerminal=false\nStartupNotify=false\n"
            "Categories=Development;\nKeywords=notes;todo;bunny;game;\n")
    entry, shortcut = _launcher_targets()
    entry.parent.mkdir(parents=True, exist_ok=True)
    for t in [entry, *([shortcut] if shortcut else [])]:
        t.write_text(text, encoding="utf-8")
        t.chmod(0o755)
        if t == shortcut:   # GNOME only runs Desktop icons marked trusted
            try:
                import subprocess
                subprocess.run(["gio", "set", str(t), "metadata::trusted", "true"], capture_output=True, timeout=5)
            except (OSError, Exception):
                pass
        print(f"installed {t}")


def remove_launcher() -> None:
    for t in _launcher_targets():
        if t and t.exists():
            t.unlink()
            print(f"removed {t}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--notes", type=Path, default=NOTES, help="notes file (default tools/notes/game_notes.json)")
    ap.add_argument("--port", type=int, default=None, help=f"port (default {DEFAULT_PORT}, or any free one)")
    ap.add_argument("--no-browser", action="store_true", help="don't open a browser tab")
    ap.add_argument("--idle-exit", action="store_true", help="stop a few minutes after the page is closed")
    ap.add_argument("--wait-idle", type=float, metavar="MIN",
                    help="wait until there are new notes and nothing changed for MIN minutes, print them, exit")
    ap.add_argument("--poll", type=float, default=30.0, help=argparse.SUPPRESS)
    ap.add_argument("--claim", action="store_true", help="mark every new note as being worked on and print them")
    ap.add_argument("--done", nargs=2, metavar=("ID", "MESSAGE"), help="answer a note and mark it done")
    ap.add_argument("--needs-you", nargs=2, metavar=("ID", "QUESTION"), help="ask the owner something about a note")
    ap.add_argument("--list", action="store_true", help="print every note that isn't done")
    ap.add_argument("--install-launcher", action="store_true", help="add a Desktop shortcut + app-menu entry")
    ap.add_argument("--remove-launcher", action="store_true", help="remove the Desktop shortcut and app-menu entry")
    a = ap.parse_args()
    path = a.notes.resolve()
    try:
        if a.wait_idle is not None:
            return wait_idle(path, a.wait_idle, a.poll)
        if a.claim:
            print(as_markdown(claim(path)))
            return 0
        if a.done or a.needs_you:
            note_id, text = a.done or a.needs_you
            n = claude_answer(path, int(note_id), "done" if a.done else "needs_you", text)
            print(f"note {n['id']}: {n['status']}")
            return 0
        if a.list:
            print(as_markdown([n for n in read_notes(path)["notes"] if n["status"] != "done"]))
            return 0
    except (NotesError, ValueError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    if a.install_launcher:
        install_launcher()
        return 0
    if a.remove_launcher:
        remove_launcher()
        return 0
    serve(path, a.port, not a.no_browser, a.idle_exit)
    return 0


if __name__ == "__main__":
    sys.exit(main())
