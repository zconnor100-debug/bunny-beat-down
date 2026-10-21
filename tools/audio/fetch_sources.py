#!/usr/bin/env python3
"""Download the raw third-party audio sources into tools/_cache/audio/.

    python3 -I tools/audio/fetch_sources.py            # everything
    python3 -I tools/audio/fetch_sources.py kenney     # only Kenney packs
    python3 -I tools/audio/fetch_sources.py music      # only incompetech tracks

Re-runnable: files that already exist are skipped. Kenney zips are extracted
into their own directory (with zip-slip protection). Nothing here is shipped;
build_audio.py copies/processes only the files the game actually uses.
"""
import os
import sys
import time
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sources  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CACHE = os.path.join(ROOT, "tools", "_cache", "audio")
UA = "Mozilla/5.0 (X11; Linux x86_64) BunnyBeatDown-asset-fetch"


def download(url, dest, tries=4, timeout=180):
    """Fetch url -> dest atomically (via .part), retrying slow/flaky hosts."""
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        print(f"  have {os.path.relpath(dest, ROOT)}")
        return dest
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".part"
    for attempt in range(1, tries + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as r, open(tmp, "wb") as f:
                while True:
                    chunk = r.read(1 << 16)
                    if not chunk:
                        break
                    f.write(chunk)
            os.replace(tmp, dest)
            print(f"  got  {os.path.relpath(dest, ROOT)} ({os.path.getsize(dest)/1e6:.2f} MB)")
            return dest
        except Exception as e:  # network errors: retry with backoff
            print(f"  retry {attempt}/{tries} {url}: {e}")
            time.sleep(3 * attempt)
    raise SystemExit(f"failed to download {url}")


def safe_extract(zip_path, out_dir):
    """Extract a zip, refusing any member that would escape out_dir."""
    if os.path.isdir(out_dir) and os.listdir(out_dir):
        return
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.realpath(out_dir)
    with zipfile.ZipFile(zip_path) as z:
        for m in z.infolist():
            target = os.path.realpath(os.path.join(base, m.filename))
            if not target.startswith(base + os.sep) and target != base:
                raise SystemExit(f"unsafe path in {zip_path}: {m.filename}")
        z.extractall(base)


def fetch_kenney():
    print("Kenney packs (CC0):")
    for pid, p in sources.KENNEY_PACKS.items():
        z = download(p["zip"], os.path.join(CACHE, "kenney", pid + ".zip"))
        safe_extract(z, os.path.join(CACHE, "kenney", pid))


def fetch_music():
    print("Kevin MacLeod / incompetech (CC BY 4.0):")
    for t in sources.MUSIC:
        download(t["mp3"], os.path.join(CACHE, "incompetech", t["cache_name"]), timeout=600)


if __name__ == "__main__":
    what = sys.argv[1:] or ["kenney", "music"]
    if "kenney" in what:
        fetch_kenney()
    if "music" in what:
        fetch_music()
