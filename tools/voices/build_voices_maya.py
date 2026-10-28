"""Speak every rogue's lines in a voice designed for it with Maya1 (Maya Research, Apache-2.0).

    HF_HOME=~/ai/hf-cache ~/ai/venvs/chatterbox/bin/python tools/voices/build_voices_maya.py [--only "Sly,Nutsy"]
    ... build_voices_maya.py --new-lines [--dry-run]     (after lines.json gains lines: only what's new)

The successor to build_voices.py (Kokoro): the same clips and the same bank
(assets/voices/<rogue>.ogg + voices.json, which RogueVoice reads), but each
rogue's voice is described in words (tools/voices/maya_voices.json: age,
pitch, timbre, pacing, emotion, a character and an accent, in the attribute
vocabulary Maya1 was trained on), so it can have an accent and act its lines.

Maya1 makes a voice up from its description every time, so a rogue's voice
would wander from clip to clip. Three things hold it still:
  * anchors: two sentences in the rogue's voice, made once and kept
    (tools/voices/anchors/<rogue>.json), go in front of every clip as "this
    speaker said this", so each clip continues the same speaker;
  * takes: every clip is made several times (in batches, so it costs about
    the same as once), and the take that sounds most like the anchors wins...
  * ...of the takes that say the words: each is heard back (Whisper) and one
    that drops or swaps words doesn't count.
Accents Maya1 wasn't trained on come two ways: the words respelled in the
accent ("dialect": dialects.py; the text on screen stays as written) and,
for some, a short recording of a real speaker with that accent read in front
of the first anchor sentence (VCTK, CC BY 4.0, Kyutai's voice donations,
CC0, or GLOBE's Common Voice speakers, CC0: the anchor's "ref"), so the voice
starts out with the accent and the anchors carry it into every clip. A
"tag" (an emotion Maya1 acts, like <sigh>) goes in front of the rogue's own
line, or after its first sentence with "tag_at": "mid". A "pitch"
(semitones) makes a squeakier critter; a "tempo" reads it faster at the same
pitch, and a "pause" cuts the long pauses inside a line down to that many
seconds (lines barked mid-fight have to land quickly).
Lines added to the game later (lines.json gains templates, or a name) don't need
every voice rebuilt: --new-lines speaks only the clips no rogue has yet, into a
file of their own beside each rogue's (<rogue>_2.ogg, then _3...), and keeps
every clip already made where it is (re-encoding them would cost quality).
A clip's id is its words' place in the list of every line's words, so a new
line renumbers them: the bank keeps that list ("segs") to match them up.
Needs (in that venv): transformers, snac, librosa, chatterbox-tts (its voice
encoder scores how alike two clips sound), ffmpeg and a CUDA GPU (~16 GB).
"""
from __future__ import annotations

import argparse
import difflib
import glob
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / "assets" / "voices"
ANCHORS = HERE / "anchors"
sys.path.insert(0, str(HERE))
import build_voices as B  # noqa: E402  (the clips, the numbers, finishing and encoding)
import dialects as D  # noqa: E402
import lines as L  # noqa: E402

SR = 24000
REF1 = "Well, well. Look who decided to show up. I've been waiting all day for this, you know. Let's make it quick."
REF2 = "Ha! You thought you could hide from me? Think again, pal. Nobody gets away."
CODE_START, CODE_END, SOH, EOH, SOA, EOA, TEXT_EOT, PAD = 128257, 128258, 128259, 128260, 128261, 128262, 128009, 128263
SNAC_OFFSET, SNAC_MAX = 128266, 156937
PASS = 0.8          # how much of a clip's words must be heard back for a take to count
SHORT = 2           # lines of this many words or fewer are said without the description (Maya.turn)
KV_BYTES = 2 * 28 * 8 * 128 * 2     # Maya1's attention memory per token (K and V, 28 layers, 8 heads of 128, bf16)
KV_BUDGET = 3.8e9   # how much of it a batch may use (a 16 GB card: the model, Whisper and the batch's working memory)


class Maya:
    def __init__(self):
        import torch
        import librosa
        from transformers import AutoModelForCausalLM, AutoTokenizer, pipeline
        from snac import SNAC
        from safetensors.torch import load_file
        from chatterbox.models.voice_encoder import VoiceEncoder
        self.torch, self.librosa = torch, librosa
        self.tok = AutoTokenizer.from_pretrained("maya-research/maya1")
        self.model = AutoModelForCausalLM.from_pretrained("maya-research/maya1", dtype=torch.bfloat16).to("cuda")
        self.snac = SNAC.from_pretrained("hubertsiuzdak/snac_24khz").eval().to("cuda")
        self.ve = VoiceEncoder()
        self.ve.load_state_dict(load_file(glob.glob(str(Path.home() / "ai/hf-cache/hub/models--ResembleAI--chatterbox/snapshots/*/ve.safetensors"))[0]))
        self.ve.eval()
        # (medium.en: small.en heard "Vex." in a take that said "Thanks.")
        self.asr = pipeline("automatic-speech-recognition", model="openai/whisper-medium.en", device=0, dtype=torch.float16)

    def turn(self, desc: str, text: str, bare: bool | None = None) -> list:
        """A turn of the prompt: the description and the words, then where the audio starts. A word or two goes in
        bare, without the description (the anchors before it carry the voice): with so little to say, Maya1 reads the
        description out instead, more often than not ("Description equals creative, animated cartoon...")."""
        d = lambda i: self.tok.decode([i])
        said = text if (words(text) <= SHORT if bare is None else bare) else f'<description="{desc}"> {text}'
        s = d(SOH) + self.tok.bos_token + said + d(TEXT_EOT) + d(EOH) + d(SOA) + d(CODE_START)
        return self.tok(s, add_special_tokens=False).input_ids

    @staticmethod
    def codes_of(ids: list) -> list:
        out = []
        for t in ids:
            if t == CODE_END:
                break
            if SNAC_OFFSET <= t <= SNAC_MAX:
                out.append(t)
        return out[: len(out) // 7 * 7]

    def decode(self, codes: list) -> np.ndarray:
        n = len(codes) // 7
        if n < 4:
            return np.zeros(2400, np.float32)
        l1, l2, l3 = [], [], []
        for f in range(n):
            s = [(x - SNAC_OFFSET) % 4096 for x in codes[f * 7:(f + 1) * 7]]
            l1.append(s[0])
            l2 += [s[1], s[4]]
            l3 += [s[2], s[3], s[5], s[6]]
        cs = [self.torch.tensor(lv, dtype=self.torch.long, device="cuda").unsqueeze(0) for lv in (l1, l2, l3)]
        with self.torch.inference_mode():
            return self.snac.decoder(self.snac.quantizer.from_codes(cs))[0, 0].float().cpu().numpy()[2048:]

    def generate(self, desc: str, texts: list, anchors: list, takes: int, seed: int, max_new: int, bare: bool | None = None) -> list:
        """`takes` of each text, all in one batch: [[(codes, audio), ...] per text] (a batch too big for the GPU is
        made in halves)."""
        try:
            return self._generate(desc, texts, anchors, takes, seed, max_new, bare)
        except self.torch.OutOfMemoryError:
            if len(texts) < 2:
                raise
        self.torch.cuda.empty_cache()   # (out here, where the failed try no longer holds its memory)
        half = len(texts) // 2
        return (self.generate(desc, texts[:half], anchors, takes, seed, max_new, bare)
                + self.generate(desc, texts[half:], anchors, takes, seed, max_new, bare))

    def _generate(self, desc: str, texts: list, anchors: list, takes: int, seed: int, max_new: int, bare: bool | None) -> list:
        torch = self.torch
        pre = []
        for a_text, a_codes in anchors:
            pre += self.turn(desc, a_text) + a_codes + [CODE_END, EOA]
        rows = [pre + self.turn(desc, t, bare) for t in texts]
        width = max(len(r) for r in rows)
        ids = torch.tensor([[PAD] * (width - len(r)) + r for r in rows], device="cuda")
        mask = torch.tensor([[0] * (width - len(r)) + [1] * len(r) for r in rows], device="cuda")
        torch.manual_seed(seed)
        with torch.inference_mode():
            out = self.model.generate(ids, attention_mask=mask, max_new_tokens=max_new, min_new_tokens=14, temperature=0.3,
                                      top_p=0.9, repetition_penalty=1.1, do_sample=True, eos_token_id=CODE_END,
                                      pad_token_id=PAD, num_return_sequences=takes)
        res = []
        for i in range(len(texts)):
            row = []
            for k in range(takes):
                c = self.codes_of(out[i * takes + k, width:].tolist())
                row.append((c, self.decode(c)))
            res.append(row)
        return res

    def embed(self, audio: np.ndarray) -> np.ndarray:
        e = self.ve.embeds_from_wavs([self.librosa.resample(audio, orig_sr=SR, target_sr=16000)], sample_rate=16000)[0]
        return e / np.linalg.norm(e)

    def hear(self, audios: list) -> list:
        """What Whisper hears in each (greedy: beam search keeps five copies of its memory per clip)."""
        clips = [{"raw": self.librosa.resample(a, orig_sr=SR, target_sr=16000), "sampling_rate": 16000} for a in audios]
        try:
            outs = self.asr(clips, batch_size=8, generate_kwargs={"num_beams": 1})
        except self.torch.OutOfMemoryError:
            outs = None
        if outs is None:   # (out here, where the failed try no longer holds its memory)
            self.torch.cuda.empty_cache()
            outs = self.asr(clips, batch_size=1, generate_kwargs={"num_beams": 1})
        return [o["text"] for o in outs]


def speech_span(audio: np.ndarray) -> float:
    """Seconds from the first sound to the last (10 ms frames within 40 dB of the loudest)."""
    fr = SR // 100
    e = np.sqrt(np.mean(audio[: len(audio) // fr * fr].reshape(-1, fr) ** 2, axis=1)) + 1e-9
    loud = np.where(20 * np.log10(e / e.max()) > -40)[0]
    return (loud[-1] - loud[0] + 1) / 100 if len(loud) else 0.0


def words(text: str) -> int:
    return len(re.sub(r"<[^>]+>", " ", text).split())


def _letters(t: str) -> str:
    t = re.sub(r"<[^>]+>", " ", t).lower()
    t = re.sub(r"\b\d+\b", lambda m: B.number_words(int(m.group(0))) if int(m.group(0)) <= 99 else m.group(0), t)
    return re.sub(r"[^a-z]", "", t.replace("-", ""))


def heard_right(text: str, heard: str) -> float:
    """How much of `text` was heard back (letters only: "Lop-Eared" and "lop eared", "5" and "five" agree)."""
    a, b = _letters(text), _letters(heard)
    if not a:
        return 1.0
    return difflib.SequenceMatcher(None, a, b).ratio()


def choose(m: Maya, text: str, takes: list, voice: np.ndarray, central=False, said: str = "") -> tuple:
    """The take that sounds most like `voice` (or most like the others) of those heard saying the words (as written,
    or as `said` in the rogue's accent: "dat" may be heard as "dat")."""
    heard = m.hear([a for _, a in takes])
    embs = [m.embed(a) for _, a in takes]
    score = [max(heard_right(text, h), heard_right(said, h) if said else 0.0) for h in heard]
    if words(text) <= 3 and "<" not in (said or text):   # (a few words that take far too long have babble after them)
        longest = 0.6 + 0.12 * len(_letters(text))
        score = [min(sc, PASS - 0.01) if speech_span(a) > longest else sc for sc, (_, a) in zip(score, takes)]
    ok = [i for i in range(len(takes)) if score[i] >= PASS] or [int(np.argmax(score))]
    if len(ok) > 2:   # (not one that runs on much longer than the others: babble after the words, which Whisper misses)
        span = {i: speech_span(takes[i][1]) for i in ok}
        typical = float(np.median(list(span.values())))
        ok = [i for i in ok if span[i] <= 1.3 * typical + 0.15] or ok
    if central:
        best = max(ok, key=lambda i: sum(float(embs[i] @ embs[j]) for j in range(len(takes)) if j != i))
    else:
        best = max(ok, key=lambda i: float(embs[i] @ voice))
    return takes[best][0], takes[best][1], embs[best], score[best]


def _capital(text: str) -> str:
    """The first word capitalized (speech only): a line starting "theah ya are" had Maya1 read its description out."""
    return re.sub(r"^((?:<[^>]+>\s*)*[^A-Za-z0-9<]*)([a-z])", lambda m: m.group(1) + m.group(2).upper(), text, count=1)


def tagged(design: dict, text: str) -> str:
    """The rogue's own line with its tag acted in it: in front, or with "tag_at": "mid" after the line's first sentence
    ("Mine. <sigh> All of it. Mine."; a sigh in front was lost in the breath before the words)."""
    head, _, rest = text.partition(". ")
    return f'{head}. {design["tag"]} {rest}' if design.get("tag_at") == "mid" and rest else f'{design["tag"]} {text}'


def anchors_for(m: Maya, name: str, design: dict) -> tuple:
    """The rogue's two anchor sentences (made once, then kept): [(text, codes)], and its voice (their mean)."""
    path = ANCHORS / (B.slug(name) + ".json")
    desc = design["desc"]
    if path.exists():
        saved = json.loads(path.read_text())
        if saved.get("desc") == desc:
            anchors = [(a["text"], a["codes"]) for a in saved["anchors"]]
            embs = [m.embed(m.decode(c)) for _, c in anchors]
            v = sum(embs)
            return anchors, v / np.linalg.norm(v)
    seed = int(hashlib.sha1(name.encode()).hexdigest()[:6], 16)
    c1, _, e1, _ = choose(m, REF1, m.generate(desc, [REF1], [], 3, seed, 1100)[0], None, central=True)
    c2, _, e2, _ = choose(m, REF2, m.generate(desc, [REF2], [(REF1, c1)], 3, seed + 1, 900)[0], e1)
    ANCHORS.mkdir(exist_ok=True)
    path.write_text(json.dumps({"desc": desc, "anchors": [{"text": REF1, "codes": c1}, {"text": REF2, "codes": c2}]}) + "\n")
    v = e1 + e2
    return [(REF1, c1), (REF2, c2)], v / np.linalg.norm(v)


def speak_all(m: Maya, name: str, design: dict, clips: dict, log) -> dict:
    """Every clip of a rogue: {clip id: audio}."""
    anchors, voice = anchors_for(m, name, design)
    seed = int(hashlib.sha1(name.encode()).hexdigest()[:6], 16) + 7
    desc = design["desc"]
    accent = lambda t: _capital(D.say(t, design.get("dialect")))
    said = {cid: accent(tagged(design, t) if cid == "says" and design.get("tag") else t) for cid, t in clips.items()}
    prefix = sum(len(m.turn(desc, t)) + len(c) + 2 for t, c in anchors)
    best = {}   # clip id: (score, audio), the best take so far

    def run(texts: dict, takes: int, seed: int, what: str, bare: bool | None = None) -> None:
        """Every clip in `texts` ({clip id: words to say}) made `takes` times, keeping each one's best take. Clips of
        about the same length go together, as many as fit on the GPU, with room for as much audio as their words
        need (one take that rambles keeps its whole batch going until it runs out of room)."""
        order = sorted(texts, key=lambda c: len(texts[c]))
        room = lambda batch: min(900, 130 + 50 * max(len(texts[c].split()) for c in batch))
        i = 0
        while i < len(order):
            per = 1
            while per < min(16, len(order) - i) and (per + 1) * takes * (prefix + 60 + room(order[i:i + per + 1])) * KV_BYTES <= KV_BUDGET:
                per += 1
            batch = order[i:i + per]
            for cid, tk in zip(batch, m.generate(desc, [texts[c] for c in batch], anchors, takes, seed + i, room(batch), bare)):
                _, audio, _, score = choose(m, clips[cid], tk, voice, said=texts[cid])
                if cid not in best or score > best[cid][0]:
                    best[cid] = (score, audio)
            i += per
            log(f"{name}: {what} {i}/{len(order)}")

    short = {c: t for c, t in said.items() if words(t) <= SHORT}
    run(short, 3, seed, "short")
    run({c: t for c, t in said.items() if c not in short}, 4, seed + 500, "long")
    weak = [c for c in said if best[c][0] < PASS]
    # another go for any clip no take said right, then one with a tag in front (a line opening "Ah," had one voice
    # read its description out instead), then bare (no line said bare has read the description out)
    run({c: said[c] for c in weak}, 6, seed + 999, "again")
    run({c: accent(f'{design.get("tag") or "<chuckle>"} {clips[c]}') for c in weak if best[c][0] < PASS}, 6, seed + 1999, "tagged")
    run({c: said[c] for c in weak if best[c][0] < PASS}, 8, seed + 2999, "bare", bare=True)
    for c in weak:
        if best[c][0] < PASS:
            log(f"{name}: no take said {clips[c]!r} right (best {best[c][0]:.2f})")
    log(f"{name}: done ({len(weak)} needed another go)")
    return {c: a for c, (_, a) in best.items()}


def pitched(audio: np.ndarray, semitones: float) -> np.ndarray:
    """Higher (or lower) by some semitones, voice and all, as long as before: played faster, then stretched back to
    its length (a squeakier critter, chipmunk-style; ffmpeg's rubberband garbled Maya1's voices)."""
    r = 2 ** (semitones / 12)
    p = subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-af",
                        "asetrate=%d,aresample=%d,atempo=%.5f" % (round(SR * r), SR, 1 / r), "-f", "f32le", "-ar", str(SR), "-ac", "1", "-"],
                       input=audio.astype(np.float32).tobytes(), capture_output=True, check=True)
    return np.frombuffer(p.stdout, np.float32).copy()


def quickened(audio: np.ndarray, tempo: float = 1.0, pause: float | None = None) -> np.ndarray:
    """Read faster: any pause inside the line longer than `pause` seconds cut down to that (10 ms frames 40 dB
    under the loudest; the cut is from the middle of the pause), then the whole line played `tempo` times as fast at
    the same pitch (ffmpeg's atempo)."""
    if pause is not None:
        fr = SR // 100
        n = len(audio) // fr
        e = np.sqrt(np.mean(audio[: n * fr].reshape(-1, fr) ** 2, axis=1)) + 1e-9
        quiet = 20 * np.log10(e / e.max()) < -40
        loud = np.where(~quiet)[0]
        keep = np.ones(len(audio), bool)
        most = int(round(pause * 100))
        i = loud[0] if len(loud) else n
        while i < (loud[-1] if len(loud) else 0):
            if quiet[i]:
                j = i
                while j < n and quiet[j]:
                    j += 1
                if j - i > most:
                    cut = (j - i - most) // 2
                    keep[(i + most // 2 + 0) * fr:(i + most // 2 + 2 * cut) * fr] = False
                i = j
            else:
                i += 1
        audio = audio[keep]
    if abs(tempo - 1.0) > 1e-3:
        p = subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-af",
                            "atempo=%.4f" % tempo, "-f", "f32le", "-ar", str(SR), "-ac", "1", "-"],
                           input=audio.astype(np.float32).tobytes(), capture_output=True, check=True)
        audio = np.frombuffer(p.stdout, np.float32).copy()
    return audio


def render(m: Maya, name: str, design: dict, clips: dict, log) -> dict:
    """A rogue's clips spoken, pitched and quickened as its design says, and finished: {clip id: audio}."""
    audio = speak_all(m, name, design, clips, log)
    if design.get("pitch"):
        audio = {cid: pitched(a, design["pitch"]) for cid, a in audio.items()}
    if design.get("tempo") or design.get("pause"):
        audio = {cid: quickened(a, design.get("tempo", 1.0), design.get("pause")) for cid, a in audio.items()}
    return {cid: B.finish(a.astype(np.float32)) for cid, a in audio.items()}


def pack(audio: dict, path: Path, named: bool = False) -> dict:
    """Clips into one Ogg file with a short gap after each: {clip id: [start, length]} ([start, length, file] for a
    file of lines added later: `named`)."""
    pieces, index, t = [], {}, 0.0
    gap = np.zeros(int(SR * B.GAP), np.float32)
    for cid in sorted(audio):
        x = audio[cid]
        index[cid] = [round(t, 4), round(len(x) / SR, 4)] + ([path.name] if named else [])
        pieces += [x, gap]
        t += (len(x) + len(gap)) / SR
    B.encode(np.concatenate(pieces), path)
    return index


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--new-lines", action="store_true", help="speak only the clips no rogue has yet (lines.json gained lines)")
    ap.add_argument("--dry-run", action="store_true", help="with --new-lines: say what would be spoken, and stop")
    args = ap.parse_args()
    data = json.loads((HERE / "lines.json").read_text())
    templates, rogues, you = data["templates"], data["rogues"], data["you"]
    designs = json.loads((HERE / "maya_voices.json").read_text())
    missing = [r["name"] for r in rogues if r["name"] not in designs]
    if missing:
        sys.exit("no Maya1 voice for: %s" % missing)
    # the plans: every template's parts, words as shared segment ids (as build_voices.py)
    segs, seg_id, plans = [], {}, {}
    for k in sorted(templates):
        out = []
        for part in L.parts(templates[k]):
            if part[0] == "t":
                if part[1] not in seg_id:
                    seg_id[part[1]] = len(segs)
                    segs.append(part[1])
                out.append(["t", seg_id[part[1]]])
            else:
                out.append(part)
        plans[k] = out
    B.segs_text = segs
    B.names_needed = L.names_said(templates)
    only = {s.strip() for s in args.only.split(",") if s.strip()}
    OUT.mkdir(parents=True, exist_ok=True)
    bank_path = OUT / "voices.json"
    bank = json.loads(bank_path.read_text()) if bank_path.exists() else {"rogues": {}}
    t0 = time.time()
    log = lambda s: print("[%5.0fs] %s" % (time.time() - t0, s), flush=True)
    save = lambda: bank_path.write_text(json.dumps(bank, separators=(",", ":")) + "\n")
    if args.new_lines:
        new_lines(bank, data, designs, segs, seg_id, plans, only, args.dry_run, save, log)
        return
    m = Maya()
    for r in rogues:
        if only and r["name"] not in only:
            continue
        clips = {cid: L.spoken(t) for cid, t in B.rogue_clips(r, templates, plans, seg_id, you, rogues).items()}
        audio = render(m, r["name"], designs[r["name"]], clips, log)
        name = B.slug(r["name"]) + ".ogg"
        index = pack(audio, OUT / name)
        added = sorted({c[2] for c in bank["rogues"].get(r["name"], {}).get("clips", {}).values() if len(c) > 2})
        if added:
            log("%s: no longer uses %s (lines added before this build): delete them and their .import" % (r["name"], ", ".join(added)))
        bank["rogues"][r["name"]] = {"file": name, "says": r["says"], "clips": index}
        bank["plans"], bank["segs"] = plans, segs
        bank.setdefault("voices", {})[r["name"]] = {"engine": "maya1", **designs[r["name"]]}
        save()   # (after every rogue: a stopped build keeps what's done)
        t = max(s + n for s, n, *_ in index.values())
        log("VOICED %-18s %4d clips %6.1f s %5.2f MB" % (r["name"], len(index), t, (OUT / name).stat().st_size / 1e6))
    write_credits(bank)


def new_lines(bank: dict, data: dict, designs: dict, segs: list, seg_id: dict, plans: dict, only: set, dry: bool, save,
              log) -> None:
    """Speak only what no clip says yet. Every rogue's clips are matched to the clip ids as they are now (words by
    their words, a name or number by its id, its own line if it's still the same line); then, for each rogue (in
    `only`), the clips it doesn't have are spoken into a new file beside its own. A rogue whose voice design changed
    since it was built is left for a whole rebuild (new clips in another voice wouldn't match)."""
    templates, rogues, you = data["templates"], data["rogues"], data["you"]
    was_segs = bank.get("segs")
    if was_segs is None:
        if bank.get("plans") != plans:
            sys.exit("the bank doesn't list its clips' words (built before it kept them) and lines.json has changed since: "
                     "run --new-lines once with the lines.json it was built from (git), then again with the new one")
        was_segs = segs   # (the lines it was built from: this records them)
    was = {t: i for i, t in enumerate(was_segs)}
    need, gone = {}, 0
    for r in rogues:
        name = r["name"]
        entry = bank["rogues"].get(name)
        if entry is None:
            log(f"{name}: no voice yet: build it whole (--only)")
            continue
        old = entry["clips"]
        keep, missing = {}, {}
        for cid, text in B.rogue_clips(r, templates, plans, seg_id, you, rogues).items():
            num = re.fullmatch(r"t(\d+)", cid)
            if num:
                at = was.get(segs[int(num.group(1))])
                clip = None if at is None else old.get("t%d" % at)
            elif cid == "says":
                clip = old.get("says") if entry.get("says", r["says"]) == r["says"] else None
            else:
                clip = old.get(cid)
            if clip:
                keep[cid] = clip
            else:
                missing[cid] = L.spoken(text)
        used = {tuple(c) for c in keep.values()}
        gone += sum(1 for c in old.values() if tuple(c) not in used)
        entry["clips"], entry["says"] = keep, r["says"]
        if missing:
            need[name] = missing
    bank["plans"], bank["segs"] = plans, segs
    changed = [n for n in need if bank.get("voices", {}).get(n) != {"engine": "maya1", **designs[n]}]
    todo = {n: c for n, c in need.items() if n not in changed and (not only or n in only)}
    for n in changed:
        log(f"{n}: its voice design changed since it was built: rebuild it whole (--only \"{n}\")")
    total = sum(len(c) for c in todo.values())
    log(f"{len(rogues) - len(need)} rogues have every clip; {len(todo)} to speak ({total} clips, about {total * 5 / 60:.0f} min); "
        f"{gone} old clips no line uses now")
    for n, c in todo.items():
        log(f"  {n}: {len(c)}: " + ", ".join(repr(t) for t in list(c.values())[:6]) + (" ..." if len(c) > 6 else ""))
    if dry:
        return
    save()   # (every rogue's clips under the new ids first: the plans are everyone's)
    if not todo:
        write_credits(bank)
        return
    m = Maya()
    for n, clips in todo.items():
        slug, k = B.slug(n), 2
        while (OUT / f"{slug}_{k}.ogg").exists():
            k += 1
        path = OUT / f"{slug}_{k}.ogg"
        index = pack(render(m, n, designs[n], clips, log), path, named=True)
        bank["rogues"][n]["clips"].update(index)
        save()
        log("VOICED %-18s %4d new clips in %s" % (n, len(index), path.name))
    write_credits(bank)


def write_credits(bank: dict) -> None:
    """Credits for the voices as they are: Maya1's rogues, any still in Kokoro's voices, and the recordings of real
    accented speakers some Maya1 voices were started from."""
    engine = lambda n: bank.get("voices", {}).get(n, {}).get("engine", "kokoro")
    # (each rogue's file, and any of lines added later)
    files = lambda names: sorted({OUT / f for n in names for f in [bank["rogues"][n]["file"]]
                                  + [c[2] for c in bank["rogues"][n]["clips"].values() if len(c) > 2]})
    maya = [n for n in bank["rogues"] if engine(n) == "maya1"]
    kokoro = [n for n in bank["rogues"] if engine(n) != "maya1"]
    entries = []
    if maya:
        entries.append({
            "asset": "The rogues' voices (every taunt, %d rogue%s)" % (len(maya), "" if len(maya) == 1 else "s"),
            "author": "Synthesized with Maya1 by Maya Research",
            "author_url": "https://huggingface.co/maya-research",
            "source_url": "https://huggingface.co/maya-research/maya1",
            "license": "Apache 2.0",
            "license_url": "https://www.apache.org/licenses/LICENSE-2.0",
            "changes": "Each rogue's lines spoken by tools/voices/build_voices_maya.py in a voice designed for it from a "
                       "written description (tools/voices/maya_voices.json), held steady by two anchor sentences in that "
                       "voice (tools/voices/anchors/), the best of several takes kept (checked with Whisper and "
                       "Chatterbox's voice encoder), trimmed, levelled and packed into one Ogg Vorbis file per rogue",
            "used_for": "Rogues speaking their taunts out loud",
            "files": [str(f.relative_to(ROOT)) for f in files(maya)] + ["assets/voices/voices.json"],
        })
    refs = {}
    for n in maya:
        a = ANCHORS / (B.slug(n) + ".json")
        ref = json.loads(a.read_text()).get("ref") if a.exists() else None
        if ref:
            refs.setdefault(ref.split("/")[0], []).append((n, ref))
    for kind, used in sorted(refs.items()):
        who = ", ".join(f"{n} ({Path(r).name.replace('_enhanced.wav', '').replace('.wav', '')})" for n, r in used)
        credit = dict(REFERENCE_CREDITS[kind])
        via = credit.pop("via")
        entries.append({**credit,
                        "changes": f"One short recording of a real speaker with the accent, read once ({via}) "
                                   "in front of the voice's description so Maya1 starts the voice with that accent: " + who,
                        "used_for": "The accents of those rogues' voices",
                        "files": [str(f.relative_to(ROOT)) for f in files(n for n, _ in used)]})
    if kokoro:
        entries.append(B.kokoro_credit(files(kokoro)))
    path = ROOT / "assets" / "credits" / "voices.json"
    path.write_text(json.dumps(entries, indent=2) + "\n")
    print("WROTE", path)


REFERENCE_CREDITS = {
    "vctk": {"asset": "Accent reference recordings (CSTR VCTK Corpus)",
             "author": "Junichi Yamagishi, Christophe Veaux, Kirsten MacDonald (CSTR, University of Edinburgh)",
             "author_url": "https://www.cstr.ed.ac.uk/",
             "source_url": "https://datashare.ed.ac.uk/handle/10283/3443",
             "license": "CC BY 4.0", "license_url": "https://creativecommons.org/licenses/by/4.0/",
             "via": "via kyutai/tts-voices"},
    "voice-donations": {"asset": "Accent reference recordings (Unmute Voice Donation Project)",
                        "author": "Volunteers of the Unmute Voice Donation Project (Kyutai)",
                        "author_url": "https://unmute.sh/voice-donation",
                        "source_url": "https://huggingface.co/kyutai/tts-voices",
                        "license": "CC0 1.0", "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
                        "via": "via kyutai/tts-voices"},
    "globe": {"asset": "Accent reference recordings (GLOBE V2, from Mozilla Common Voice)",
              "author": "Mozilla Common Voice contributors; GLOBE by Wenbin Wang, Yang Song, Sanjay Jha",
              "author_url": "https://commonvoice.mozilla.org/",
              "source_url": "https://huggingface.co/datasets/MushanW/GLOBE_V2",
              "license": "CC0 1.0", "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
              "via": "the GLOBE speaker named, from its accent label"},
}


if __name__ == "__main__":
    main()
