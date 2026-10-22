// Bunny Beat Down — audio review page.
//
// Loads /api/data (sounds, what they should sound like, weapon fire rates and
// the saved notes), plays everything through one Web Audio graph (so bursts and
// loops are sample-accurate), draws waveforms + loudness, and saves review
// notes as field-level changes ("set the verdict", "flag take 2") that the
// server merges into the file on disk, so tabs never undo each other's edits.
// An older review.py (no "protocol": 2 in /api/data) gets whole entries, as it
// expects. Unsynced edits are also kept in localStorage (one slot per tab) and
// restored on the next visit, unless the notes file has newer changes for them.
"use strict";

const state = {
  data: null,
  notesId: "",
  protocol: 1,            // the server's save protocol: 2 = field-level changes + per-key "rejected"
  server: { keys: {}, orphans: {} },   // the notes as the server last sent them
  serverUpdated: null,    // their "updated" stamp
  delivered: null,        // ids of close-time saves the server got (a current review.py only)
  serverStarted: 0,       // when that server started (ms)
  known: false,           // the server's notes are readable (not while the file is damaged)
  notes: { keys: {}, orphans: {} },    // what the page shows: server notes + this tab's unsynced edits
  pending: new Map(),     // key -> op | null   (edited, not yet sent; null deletes an old note)
  inflight: new Map(),    // key -> op | null   being sent right now
  editedAt: new Map(),    // key -> time of its oldest unsynced edit (for the local backup)
  rejected: {},           // key -> {op, reason, at, shown}: edits the server refused, kept for the user
  refusedNow: new Map(),  // key -> reason: refused during this visit (the banner lists them)
  refusedSinceSave: 0,    // refused by an older review.py since the save status last said so
  restoreSkipped: new Set(),   // keys the restore line names (not restored from this browser)
  helpFromKeys: false,    // the shortcuts dialog was opened from its button with the keyboard
  cards: [],              // [{key, el, entry, music}]
  byKey: new Map(),       // key -> index in cards
  shape: "",              // the sound list this page was built from (to notice changes)
  focus: -1,
  filter: "all",
  query: "",
  ctx: null,
  master: null,
  buffers: new Map(),     // url -> Promise<AudioBuffer>
  voices: new Set(),      // playing one-shots/loops
  loops: new Map(),       // key -> voice | {pending: true} (a load in progress; compared by identity)
  nextVariant: new Map(),
  playGen: 0,             // bumped by stopAll(): stale scheduled UI callbacks bail out
  saveTimer: null,
  retryTimer: null,
  saving: false,
  saveGen: 0,             // bumped per save: a data refresh that raced a save is dropped
  failures: 0,            // saves failed in a row (retry back-off)
  batchKeys: Infinity,    // keys per save (lowered if the server ever says a save was too big)
  advanceTimer: null,     // pending "Next after 👍"
  refreshing: false,
  refreshedAt: -Infinity,
  restoreStarted: false,
  banner: new Map(),      // id -> text
  bannerShown: null,      // the lines the banner shows right now (it is only rebuilt when they change)
  dismissed: new Set(),   // "id\ntext" the user closed
  userScrolled: false,    // the page was scrolled since the highlight last moved
  autoScrollUntil: 0,     // our own smooth scroll is still running until then
  messageTimer: null,
};
const JITTER = 0.06;          // the game plays guns with ±6 % pitch variation
const MAX_NOTE = 4000;        // code points, like the server
const SAVE_DELAY = 600;
const RETRY_DELAY = 5000;     // first retry; doubles while the server stays away
const RETRY_MAX = 30000;
const SAVE_TIMEOUT = 15000;   // a save that hangs (e.g. no free connection) turns into a visible retry
const MAX_BATCH_BYTES = 256 * 1024;   // the server takes at most 512 KiB per save
const ADVANCE_DELAY = 220;
const KEEP_REFUSED_DAYS = 30;
const TAB_ID = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
const TAB_LOCK = "bbd-audio-review-tab:";
const PRESENCE_LOCK = "bbd-audio-review-presence";
// Sent first in every protocol-2 save as a no-op delete. A current review.py skips
// it; an older one refuses the whole save over it (unknown key) before writing
// anything, so field-level changes are never mistaken for whole entries there.
const PROTOCOL_GUARD = "(protocol 2 page)";
const FILTER_NAMES = { todo: "To review", work: "Needs work", good: "Good" };

// ---------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------

function el(sel, root = document) { return root.querySelector(sel); }

function h(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") node.className = v;
    else if (k === "text") node.textContent = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else if (v !== null && v !== undefined && v !== false) node.setAttribute(k, v === true ? "" : v);
  }
  for (const c of children.flat()) if (c != null) node.append(c);
  return node;
}

function cssId(s) { return s.replace(/[^a-zA-Z0-9_-]/g, "_"); }
function cardIndex(key) { return state.byKey.has(key) ? state.byKey.get(key) : -1; }
function cardOf(key) { return state.cards[cardIndex(key)]; }
function plural(n, word) { return `${n} ${word}${n === 1 ? "" : "s"}`; }
function isTextEntry(n) { return !!(n && n.matches && n.matches("textarea, input[type=search], input[type=text]")); }

/** Remove unpaired UTF-16 surrogates (a cut emoji) and cap the length in code points. */
function cleanNote(text) {
  const fixed = text.replace(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/g, "");
  const cps = Array.from(fixed);
  return cps.length > MAX_NOTE ? cps.slice(0, MAX_NOTE).join("") : fixed;
}

/** One short line in the sticky bar; the full text is its tooltip (details go in the banner). */
function setStatus(text, err = false, detail = "") {
  const s = el("#save-status");
  s.textContent = text;
  s.title = detail || text;
  s.classList.toggle("err", err);
}

/** Transient info toast, separate from the save status so it never hides a save error. */
function flash(text, ms = 4000) {
  const m = el("#message");
  m.textContent = text;
  clearTimeout(state.messageTimer);
  state.messageTimer = setTimeout(() => { m.textContent = ""; }, ms);
}

/** The banner holds lines by id (server warnings, notes-file problems, restored
 *  edits, save problems, refused edits), so each can be replaced or cleared on its own. */
function bannerSet(id, text) {
  if (text) state.banner.set(id, text); else state.banner.delete(id);
  renderBanner();
}

function renderBanner() {
  const b = el("#banner");
  const seen = new Set();   // the same sentence can come from two places (e.g. /api/data and a save)
  const lines = [...state.banner].filter(([id, text]) => !state.dismissed.has(`${id}\n${text}`) && !seen.has(text) && seen.add(text));
  // unchanged lines are left alone: rebuilding them (say, after every autosave)
  // makes screen readers announce the alert again
  const sig = lines.map(([id, text]) => `${id}\n${text}`).join("\n\n");
  if (state.bannerShown === sig) return;
  state.bannerShown = sig;
  b.hidden = !lines.length;
  b.textContent = "";
  if (!lines.length) return;
  b.append(h("div", { class: "banner-lines" }, lines.map(([, text]) => h("div", { text }))),
    h("button", { class: "banner-close", title: "Dismiss", "aria-label": "Dismiss these messages", text: "✕", onclick: dismissBanner }));
}

function dismissedKey() { return `bbd-audio-review:dismissed:${state.notesId}`; }

function dismissBanner() {
  for (const [id, text] of state.banner) state.dismissed.add(`${id}\n${text}`);
  // server warnings and the earlier-edits reminder come back on every reload: remember those
  try {
    const keep = [...state.dismissed].filter((d) => d.startsWith("warn:") || d.startsWith("kept\n")).slice(-20);
    localStorage.setItem(dismissedKey(), JSON.stringify(keep));
  } catch (_) { /* storage blocked: dismissed for this visit only */ }
  renderBanner();
}

/** fetch() + JSON with a time limit, so a request that never gets an answer
 *  (or a connection) turns into an error instead of hanging forever. */
async function fetchJson(url, opts = {}, ms = SAVE_TIMEOUT) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), ms);
  try {
    const r = await fetch(url, { cache: "no-store", ...opts, signal: ctl.signal });
    let body = {};
    try { body = await r.json(); } catch (e) { if (e.name === "AbortError") throw e; /* empty or non-JSON reply */ }
    return { ok: r.ok, status: r.status, body: body && typeof body === "object" ? body : {} };
  } finally {
    clearTimeout(timer);
  }
}

// ---------------------------------------------------------------------------
// audio engine
// ---------------------------------------------------------------------------

function audio() {
  if (!state.ctx) {
    state.ctx = new AudioContext();
    state.master = state.ctx.createGain();
    state.master.gain.value = Number(el("#volume").value);
    state.master.connect(state.ctx.destination);
  }
  if (state.ctx.state === "suspended") state.ctx.resume();
  return state.ctx;
}

/** A file's URL, versioned by its size + mtime when the server says them, so a
 *  rebuilt sound is fetched again instead of replaying the decoded old one. */
function fileUrl(f) { return f.v ? `${f.url}?v=${encodeURIComponent(f.v)}` : f.url; }

function buffer(url) {
  if (!state.buffers.has(url)) {
    const ctx = audio();
    const p = fetch(url)
      .then((r) => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.arrayBuffer(); })
      .then((ab) => ctx.decodeAudioData(ab));
    p.catch(() => state.buffers.delete(url));   // allow a retry later
    state.buffers.set(url, p);
  }
  return state.buffers.get(url);
}

/** Play a decoded buffer at `when` (AudioContext time). Returns a voice handle. */
function playBuffer(buf, { when = 0, loop = false, rate = 1, onEnd = null } = {}) {
  const ctx = audio();
  const src = ctx.createBufferSource();
  src.buffer = buf;
  src.loop = loop;
  src.playbackRate.value = rate;
  src.connect(state.master);
  const start = Math.max(when, ctx.currentTime);
  src.start(start);
  const voice = {
    src, start, duration: buf.duration / rate, loop,
    stop() { try { src.stop(); } catch (_) { /* already stopped */ } },
  };
  state.voices.add(voice);
  src.onended = () => { state.voices.delete(voice); if (onEnd) onEnd(); };
  return voice;
}

function jitterRate() {
  return el("#jitter").checked ? 1 + (Math.random() * 2 - 1) * JITTER : 1;
}

function stopAll() {
  state.playGen++;
  for (const v of [...state.voices]) v.stop();
  state.voices.clear();
  state.loops.clear();
  document.querySelectorAll(".play.playing").forEach((b) => b.classList.remove("playing"));
  document.querySelectorAll(".btn.on[data-act='loop']").forEach((b) => b.classList.remove("on"));
  document.querySelectorAll("audio").forEach((a) => a.pause());
}

// ---------------------------------------------------------------------------
// actions on one sound card
// ---------------------------------------------------------------------------

async function playVariant(card, n) {
  if (!card || card.music) return;
  const f = card.entry.files[n - 1];
  if (!f) return;
  const btn = card.el.querySelector(`.play[data-n="${n}"]`);
  const canvas = card.el.querySelector(`canvas[data-n="${n}"]`);
  const gen = state.playGen;
  try {
    const buf = await buffer(fileUrl(f));
    if (gen !== state.playGen) return;
    btn.classList.add("playing");
    const voice = playBuffer(buf, { rate: card.entry.burst ? jitterRate() : 1, onEnd: () => btn.classList.remove("playing") });
    animatePlayhead(canvas, buf, voice);
    state.nextVariant.set(card.key, n % card.entry.files.length + 1);
  } catch (e) {
    flash(`Couldn't play ${f.file}: ${e.message}`);
  }
}

async function playAll(card) {
  if (!card || card.music) return;
  const ctx = audio();
  const gen = state.playGen;
  let bufs;
  try { bufs = await Promise.all(card.entry.files.map((f) => buffer(fileUrl(f)))); }
  catch (e) { flash(`Couldn't load ${card.key}: ${e.message}`); return; }
  if (gen !== state.playGen) return;
  let t = ctx.currentTime + 0.05;
  card.entry.files.forEach((f, i) => {
    const buf = bufs[i];
    const btn = card.el.querySelector(`.play[data-n="${f.n}"]`);
    const voice = playBuffer(buf, { when: t, onEnd: () => btn.classList.remove("playing") });
    setTimeout(() => {
      if (gen !== state.playGen || !state.voices.has(voice)) return;
      btn.classList.add("playing");
      animatePlayhead(card.el.querySelector(`canvas[data-n="${f.n}"]`), buf, voice);
    }, Math.max(0, (t - ctx.currentTime) * 1000));
    t += Math.min(buf.duration, 3) + 0.35;
  });
}

/** How the game fires a weapon: shot count and spacing for a demo burst. */
function burstPlan(b) {
  let interval = 60 / b.rpm;
  let shots;
  if (b.magazine <= 1) {               // rocket launcher: one round, then a reload
    interval = Math.max(interval, b.reload_time + 0.25);
    shots = 3;
  } else if (b.auto) {
    shots = Math.max(6, Math.min(16, b.magazine, Math.round(1.6 / interval)));
  } else {
    shots = Math.min(b.magazine, Math.max(2, Math.min(4, Math.round(3 / interval))));
  }
  return { interval, shots };
}

/** Fire like the game does: variants cycled at the weapon's rate, ±pitch, plus
 *  the follow-up cycle sound (sniper bolt). */
async function burst(card) {
  const b = card && card.entry.burst;
  if (!b) return;
  const ctx = audio();
  const gen = state.playGen;
  let bufs, cycleBuf = null;
  try {
    bufs = await Promise.all(card.entry.files.map((f) => buffer(fileUrl(f))));
    const cycleCard = b.cycle ? cardOf(b.cycle) : null;
    if (cycleCard && cycleCard.entry.files.length) cycleBuf = await buffer(fileUrl(cycleCard.entry.files[0]));
  } catch (e) { flash(`Couldn't load ${card.key}: ${e.message}`); return; }
  if (gen !== state.playGen) return;
  const { interval, shots } = burstPlan(b);
  let t = ctx.currentTime + 0.06;
  for (let i = 0; i < shots; i++) {
    playBuffer(bufs[i % bufs.length], { when: t, rate: jitterRate() });
    if (cycleBuf) playBuffer(cycleBuf, { when: t + b.cycle_delay });
    t += interval;
  }
  flash(`${b.weapon}: ${shots} shots, one every ${interval.toFixed(2)} s${b.auto ? " (full auto)" : ""}`);
}

async function toggleLoop(card) {
  if (!card || !card.entry.loop) return;
  const btn = card.el.querySelector("[data-act='loop']");
  const existing = state.loops.get(card.key);
  if (existing && existing.pending) return;    // still loading: ignore double presses
  if (existing) {
    existing.stop();
    state.loops.delete(card.key);
    btn.classList.remove("on");
    return;
  }
  // a token per load: a load that finishes after Esc (or after a newer press) only
  // ever touches its own entry, never the newer press's
  const token = { pending: true };
  state.loops.set(card.key, token);
  try {
    const buf = await buffer(fileUrl(card.entry.files[0]));
    if (state.loops.get(card.key) !== token) return;
    const voice = playBuffer(buf, { loop: true });
    state.loops.set(card.key, voice);
    btn.classList.add("on");
    animatePlayhead(card.el.querySelector("canvas[data-n='1']"), buf, voice);
  } catch (e) {
    if (state.loops.get(card.key) === token) state.loops.delete(card.key);
    flash(`Couldn't loop ${card.key}: ${e.message}`);
  }
}

// ---------------------------------------------------------------------------
// waveforms + loudness
// ---------------------------------------------------------------------------

function analyse(buf) {
  let peak = 0, sum = 0, count = 0;
  for (let c = 0; c < buf.numberOfChannels; c++) {
    const ch = buf.getChannelData(c);
    for (let i = 0; i < ch.length; i++) {
      const v = ch[i];
      const a = v < 0 ? -v : v;
      if (a > peak) peak = a;
      sum += v * v;
    }
    count += ch.length;
  }
  const db = (x) => (x > 0 ? 20 * Math.log10(x) : -Infinity);
  return { peak: db(peak), rms: db(Math.sqrt(sum / Math.max(1, count))), duration: buf.duration };
}

function fmtDb(x) { return Number.isFinite(x) ? x.toFixed(1) : "−∞"; }

function drawWave(canvas, buf, playedFrac = 0) {
  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth, hgt = canvas.clientHeight;
  if (!w || !hgt) return;
  if (canvas.width !== Math.round(w * dpr)) { canvas.width = Math.round(w * dpr); canvas.height = Math.round(hgt * dpr); }
  const g = canvas.getContext("2d");
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, w, hgt);
  const css = getComputedStyle(document.documentElement);
  const base = css.getPropertyValue("--wave").trim();
  const played = css.getPropertyValue("--wave-played").trim();
  const ch = buf.getChannelData(0);
  const step = Math.max(1, Math.floor(ch.length / w));
  const mid = hgt / 2;
  for (let x = 0; x < w; x++) {
    let lo = 0, hi = 0;
    const s0 = x * step;
    const s1 = Math.min(s0 + step, ch.length);
    for (let i = s0; i < s1; i++) {
      const v = ch[i];
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    g.fillStyle = x / w < playedFrac ? played : base;
    g.fillRect(x, mid - hi * mid, 1, Math.max(1, (hi - lo) * mid));
  }
}

function animatePlayhead(canvas, buf, voice) {
  if (!canvas) return;
  const ctx = audio();
  const tick = () => {
    if (!state.voices.has(voice)) { drawWave(canvas, buf, 0); return; }
    const elapsed = ctx.currentTime - voice.start;
    const frac = elapsed < 0 ? 0 : voice.loop ? (elapsed % voice.duration) / voice.duration : Math.min(1, elapsed / voice.duration);
    drawWave(canvas, buf, frac);
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

const waveObserver = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (!e.isIntersecting) continue;
    waveObserver.unobserve(e.target);
    const canvas = e.target;
    const url = canvas.dataset.url;
    const stats = canvas.parentElement.querySelector(".stats");
    buffer(url).then((buf) => {
      if (canvas.dataset.url !== url) return;     // the file was rebuilt meanwhile
      drawWave(canvas, buf);
      const a = analyse(buf);
      stats.textContent = "";
      stats.append(`${a.duration.toFixed(2)} s · `,
        h("span", { class: a.peak > -0.5 ? "hot" : "", title: "peak level (dBFS)", text: `pk ${fmtDb(a.peak)}` }),
        h("br"), `rms ${fmtDb(a.rms)} dB`);
    }).catch((err) => { stats.textContent = "⚠ " + err.message; });
  }
}, { rootMargin: "300px" });

/** Pick up rebuilt sound files (their version changed in /api/data): drop the
 *  cached decode and redraw the waveform + stats (the old stats stay until the
 *  new ones are ready, so nothing jumps). A server that sends no versions (an
 *  older review.py) changes nothing. Returns how many changed. */
function applyAudioVersions(data) {
  const fresh = new Map();
  for (const g of data.groups || []) for (const k of g.keys) fresh.set(k.key, k);
  for (const m of data.music || []) fresh.set(m.key, m);
  let changed = 0;
  for (const c of state.cards) {
    const n = fresh.get(c.key);
    if (!n) continue;
    if (c.music) {
      const player = c.el.querySelector("audio");
      if (n.v && n.v !== c.entry.v && player.paused) {     // a playing track switches once it's paused
        c.entry.v = n.v;
        player.src = fileUrl(c.entry);
        changed++;
      }
      continue;
    }
    for (const f of c.entry.files) {
      const nf = (n.files || []).find((x) => x.file === f.file);
      if (!nf || !nf.v || nf.v === f.v) continue;
      state.buffers.delete(fileUrl(f));
      f.v = nf.v;
      changed++;
      const canvas = c.el.querySelector(`canvas[data-n="${f.n}"]`);
      if (canvas) {
        canvas.dataset.url = fileUrl(f);
        waveObserver.observe(canvas);
      }
    }
  }
  return changed;
}

// ---------------------------------------------------------------------------
// notes: server copy + this tab's edits ("ops")
// ---------------------------------------------------------------------------
//
// An op is one sound's unsynced edit, field by field:
//   {verdict?: "good"|"tweak"|"replace"|null, note?: text, bad?: {take: true|false}}
// null deletes the whole note (only used for notes of sounds no longer in the game).

function blankEntry() { return { verdict: null, note: "", bad_variants: [] }; }

/** An op applied to a stored entry (null = none): the new entry, or null if nothing is left. */
function applyOp(entry, op) {
  if (op === null) return null;
  const e = entry || blankEntry();
  let verdict = e.verdict || null, note = e.note || "";
  const takes = new Set(e.bad_variants || []);
  if ("verdict" in op) verdict = op.verdict || null;
  if ("note" in op) note = op.note;
  for (const [n, on] of Object.entries(op.bad || {})) { if (on) takes.add(Number(n)); else takes.delete(Number(n)); }
  if (!verdict && !note.trim() && !takes.size) return null;
  return { verdict, note, bad_variants: [...takes].sort((a, b) => a - b) };
}

/** An older op followed by a newer one for the same sound (the newer wins field by field). */
function mergeOps(older, newer) {
  if (older === undefined) return newer;
  if (newer === undefined) return older;
  if (older === null || newer === null) return newer;
  return { ...older, ...newer, bad: { ...(older.bad || {}), ...(newer.bad || {}) } };
}

/** Protocol-2 wire form: only what changed. */
function opToChange(op) {
  if (op === null) return null;
  const c = {};
  if ("verdict" in op) c.verdict = op.verdict || null;
  if ("note" in op) c.note = op.note;
  const bad = Object.entries(op.bad || {});
  const add = bad.filter(([, on]) => on).map(([n]) => Number(n));
  const remove = bad.filter(([, on]) => !on).map(([n]) => Number(n));
  if (add.length) c.bad_add = add;
  if (remove.length) c.bad_remove = remove;
  return c;
}

/** What gets sent for one key: field-level changes (protocol 2), or for an older
 *  review.py the whole entry as this page shows it (null = delete), exactly as
 *  the page used to send it. */
function wireChange(key, op, protocol) {
  if (protocol >= 2) return opToChange(op);
  if (op === null) return null;
  const n = state.notes.keys[key];
  return n ? { verdict: n.verdict || null, note: n.note || "", bad_variants: [...(n.bad_variants || [])] } : null;
}

function serverEntry(key) { return state.server.keys[key] || state.server.orphans[key] || null; }

function noteFor(key) {
  return state.notes.keys[key] || blankEntry();
}

/** What /api/data says about the server itself (an older review.py says less). */
function serverInfo(data) {
  state.protocol = data.protocol || 1;
  state.delivered = Array.isArray(data.delivered) ? data.delivered : null;
  state.serverStarted = Number(data.started) || 0;
}

/** Take the server's notes as the new base (edits in other tabs show up this way). */
function adoptServer(notes) {
  if (!notes || typeof notes !== "object") return;
  state.server = { keys: { ...(notes.keys || {}) }, orphans: { ...(notes.orphans || {}) } };
  state.serverUpdated = typeof notes.updated === "string" ? notes.updated : null;
  state.known = true;
}

/** Everything this tab hasn't got confirmed yet, per key. */
function unsyncedOps() {
  const all = new Map(state.inflight);
  for (const [k, op] of state.pending) all.set(k, mergeOps(all.get(k), op));
  return all;
}

/** Recompute what the page shows (server notes + unsynced edits) and update only
 *  the widgets whose note changed. */
function rebuildView() {
  const keys = { ...state.server.keys };
  const orphans = { ...state.server.orphans };
  for (const ops of [state.inflight, state.pending]) {
    for (const [k, op] of ops) {
      const into = k in state.server.orphans && !state.byKey.has(k) ? orphans : keys;
      const e = applyOp(into[k] || null, op);
      if (e) into[k] = e; else delete into[k];
    }
  }
  const before = state.notes;
  state.notes = { keys, orphans };
  if (!state.cards.length) return;
  for (const k of new Set([...Object.keys(before.keys), ...Object.keys(keys)])) {
    if (JSON.stringify(before.keys[k] || null) !== JSON.stringify(keys[k] || null)) refreshCardUI(k);
  }
  if (JSON.stringify(before.orphans) !== JSON.stringify(orphans)) renderOrphans();
  updateProgress();
}

// ---------------------------------------------------------------------------
// rendering
// ---------------------------------------------------------------------------

function updateHint(ta) {
  const left = MAX_NOTE - Array.from(ta.value).length;
  ta.nextElementSibling.textContent = left < 500 ? `${left} characters left` : "";
}

/** After a mouse click on a verdict or flag, Space should replay the sound (as
 *  documented), not click the same button again: keep DOM focus on the card.
 *  Keyboard activation (detail 0) leaves focus on the button. */
function afterClick(e, key) {
  if (e.detail > 0) { const card = cardOf(key); if (card) card.el.focus({ preventScroll: true }); }
}

function reviewBox(key) {
  const n = noteFor(key);
  // no maxlength: it counts UTF-16 units (an emoji is 2), the server and the hint count characters
  const ta = h("textarea", {
    class: "note", placeholder: "Notes — what's off? (N)", "aria-label": `Notes for ${key}`,
    oninput: (e) => {
      const v = cleanNote(e.target.value);
      if (v !== e.target.value) {
        e.target.value = v;
        if (Array.from(v).length >= MAX_NOTE) flash(`Notes can be at most ${MAX_NOTE} characters; the rest was cut off`);
      }
      ta._dirty = true;          // being typed in: syncs leave this box alone until it loses focus
      edit(key, { note: v });
      updateHint(ta);
    },
    onblur: () => { ta._dirty = false; ta._otherNote = undefined; refreshCardUI(key); },
  });
  ta.value = n.note || "";
  const hint = h("div", { class: "count-hint" });
  return h("div", { class: "review" },
    h("div", { class: "verdict", role: "group", "aria-label": `Verdict for ${key}` },
      ["good", "tweak", "replace"].map((v) => h("button", {
        "data-v": v, class: n.verdict === v ? "on" : "", "aria-pressed": String(n.verdict === v),
        title: { good: "Good (G)", tweak: "Needs a tweak (T)", replace: "Replace it (R)" }[v],
        onclick: (e) => { afterClick(e, key); setVerdict(key, v); },
        text: { good: "👍 Good", tweak: "🔧 Tweak", replace: "👎 Replace" }[v],
      }))),
    ta, hint);
}

function renderCard(entry) {
  const key = entry.key;
  const n = noteFor(key);
  const card = h("article", { class: "card", id: `k-${cssId(key)}`, "data-key": key, "data-verdict": n.verdict || "", tabindex: "-1" });
  card.append(h("div", {},
    h("h3", { text: key }),
    h("p", { class: "expect", text: entry.expect }),
    h("p", { class: "when", text: `▸ ${entry.when}` })));
  const variants = h("div", { class: "variants" });
  for (const f of entry.files) {
    const bad = (n.bad_variants || []).includes(f.n);
    const canvas = h("canvas", { class: "wave", "data-n": f.n, "data-url": fileUrl(f), title: `${f.file} — click to play` });
    canvas.addEventListener("click", () => { focusCard(cardIndex(key)); playVariant(cardOf(key), f.n); });
    variants.append(h("div", { class: "variant" },
      h("button", { class: "play", "data-n": f.n, title: `Play variant ${f.n} (${f.n})`, "aria-label": `Play ${key} variant ${f.n}`,
        onclick: () => { focusCard(cardIndex(key)); playVariant(cardOf(key), f.n); },
        text: `▶${entry.files.length > 1 ? f.n : ""}` }),
      canvas,
      h("span", { class: "stats", text: "…" }),
      h("button", { class: `badtake${bad ? " on" : ""}`, "data-n": f.n, title: "Flag this take as bad (the others may be fine)",
        "aria-pressed": String(bad), "aria-label": `Flag ${key} take ${f.n} as bad`,
        onclick: (e) => { afterClick(e, key); toggleBadTake(key, f.n); }, text: "⚑" })));
    waveObserver.observe(canvas);
  }
  card.append(variants);
  const actions = h("div", { class: "actions" });
  if (entry.files.length > 1) actions.append(h("button", { class: "btn", "data-act": "all", title: "Play every variant in turn (A)", onclick: () => playAll(cardOf(key)), text: "▶ Play all" }));
  if (entry.burst) {
    const { interval } = burstPlan(entry.burst);
    actions.append(h("button", { class: "btn", "data-act": "burst", title: "Fire like the game (B)", onclick: () => burst(cardOf(key)),
      text: entry.burst.magazine <= 1 ? `💥 Fire (reload ${interval.toFixed(1)} s)` : `💥 Burst at ${Math.round(entry.burst.rpm)} rpm` }));
  }
  if (entry.loop) actions.append(h("button", { class: "btn", "data-act": "loop", title: "Seamless loop (L) — listen for the seam", onclick: () => toggleLoop(cardOf(key)), text: "🔁 Loop" }));
  if (actions.childElementCount) card.append(actions);
  card.append(reviewBox(key));
  card.addEventListener("focusin", () => focusCard(cardIndex(key), { scroll: false, dom: false }));
  card.addEventListener("pointerdown", () => focusCard(cardIndex(key), { scroll: false, dom: false }));
  return card;
}

function renderMusic(m) {
  const n = noteFor(m.key);
  const card = h("article", { class: "card", id: `k-${cssId(m.key)}`, "data-key": m.key, "data-verdict": n.verdict || "", tabindex: "-1" });
  const player = h("audio", { controls: true, preload: "metadata", src: fileUrl(m) });
  player.volume = Number(el("#volume").value);
  player.addEventListener("play", () => { document.querySelectorAll("audio").forEach((a) => { if (a !== player) a.pause(); }); });
  card.append(h("div", {},
    h("h3", { text: m.title }),
    h("p", { class: "expect", text: m.expect }),
    h("p", { class: "when", text: `▸ ${m.when} · ${m.file}` })));
  card.append(h("div", { class: "variants" }, player));
  card.append(reviewBox(m.key));
  card.addEventListener("focusin", () => focusCard(cardIndex(m.key), { scroll: false, dom: false }));
  card.addEventListener("pointerdown", () => focusCard(cardIndex(m.key), { scroll: false, dom: false }));
  return card;
}

/** Deleting an old note can't be undone, so the button asks once more. Armed
 *  with the mouse, the keyboard goes back to the highlighted sound (never left on
 *  the armed button, where a Space meant to replay would confirm); armed with the
 *  keyboard, it stays, so Enter, Enter deletes. */
function onDeleteClick(ev, key) {
  const btn = ev.currentTarget;
  armDelete(btn, key);
  if (ev.detail > 0) {
    refocusAfterMouse(ev);
    if (document.activeElement === btn) btn.blur();
  }
}

function armDelete(btn, key) {
  if (btn.dataset.armed) { deleteOrphan(key); return; }
  btn.dataset.armed = "1";
  btn.classList.add("danger");
  btn.textContent = "Sure? Click again to delete";
  setTimeout(() => {
    if (!btn.isConnected) return;
    delete btn.dataset.armed;
    btn.classList.remove("danger");
    btn.textContent = "Delete this note";
  }, 4000);
}

function renderOrphans() {
  const old = el("#g-orphans");
  if (old) old.remove();
  const orphans = Object.entries(state.notes.orphans || {});
  if (orphans.length) {
    const sec = h("section", { id: "g-orphans" },
      h("h2", {}, "Notes for sounds no longer in the game ", h("span", { class: "count", "data-total": orphans.length, text: `(${orphans.length})` })));
    for (const [key, e] of orphans) {
      sec.append(h("article", { class: "card orphan", "data-key": key },
        h("div", {},
          h("h3", { text: key }),
          h("p", { class: "expect", text: `${(e.verdict || "unrated").toUpperCase()}${(e.bad_variants || []).length ? ` · bad takes ${e.bad_variants.join(", ")}` : ""}` }),
          h("p", { class: "when", text: e.note || "(no note)" })),
        h("div", { class: "review" },
          h("div", { class: "orphan-actions" },
            h("button", { class: "btn", text: "Delete this note", title: "Delete this note for good (asks once more)",
              onclick: (ev) => onDeleteClick(ev, key) })))));
    }
    el("#list").append(sec);
  }
  filterOrphans();
  updateSections();
}

function render() {
  const list = el("#list");
  const toc = el("#toc");
  list.textContent = "";
  toc.textContent = "";
  state.cards = [];
  state.byKey = new Map();
  const add = (key, node, entry, music) => {
    state.byKey.set(key, state.cards.length);
    state.cards.push({ key, el: node, entry, music });
  };
  for (const g of state.data.groups) {
    const section = h("section", { id: `g-${g.id}` },
      h("h2", {}, g.title, " ", h("span", { class: "count", "data-total": g.keys.length, text: `(${g.keys.length})` })));
    for (const entry of g.keys) {
      const node = renderCard(entry);
      section.append(node);
      add(entry.key, node, entry, false);
    }
    list.append(section);
    toc.append(h("a", { href: `#g-${g.id}`, text: g.title }));
  }
  const ms = h("section", { id: "g-music" },
    h("h2", {}, "Music ", h("span", { class: "count", "data-total": state.data.music.length, text: `(${state.data.music.length})` })));
  for (const m of state.data.music) {
    const node = renderMusic(m);
    ms.append(node);
    add(m.key, node, m, true);
  }
  list.append(ms);
  toc.append(h("a", { href: "#g-music", text: "Music" }));
  state.shape = catalogShape(state.data);
  renderOrphans();
  applyFilter();
  updateProgress();
}

/** Bring one card's review widgets in line with state.notes (after a merge). */
function refreshCardUI(key) {
  const card = cardOf(key);
  if (!card) return;
  const n = noteFor(key);
  card.el.dataset.verdict = n.verdict || "";
  card.el.querySelectorAll(".verdict button").forEach((b) => {
    const on = b.dataset.v === n.verdict;
    b.classList.toggle("on", on);
    b.setAttribute("aria-pressed", String(on));
  });
  card.el.querySelectorAll(".badtake").forEach((b) => {
    const on = (n.bad_variants || []).includes(Number(b.dataset.n));
    b.classList.toggle("on", on);
    b.setAttribute("aria-pressed", String(on));
  });
  const ta = card.el.querySelector("textarea");
  const want = n.note || "";
  if (!ta || ta.value === want) return;
  if (document.activeElement === ta && ta._dirty) {
    // being typed in: don't yank the text away, but say so once (what's typed next
    // replaces the other tab's version; leaving the box shows it). Text this tab
    // hasn't saved yet isn't another tab's change (a note of only spaces shows as none).
    const mine = unsyncedOps().get(key);
    if ((mine && mine.note === ta.value) || (!want && !ta.value.trim())) return;
    if (ta._otherNote !== want) {
      ta._otherNote = want;
      flash(`Another tab changed the note for ${key}. Press Esc to see that version, or keep typing to replace it.`, 8000);
    }
    return;
  }
  ta.value = want;
  updateHint(ta);
}

// ---------------------------------------------------------------------------
// review state + saving
// ---------------------------------------------------------------------------

function edit(key, op) {
  if (!state.editedAt.has(key)) state.editedAt.set(key, Date.now());
  state.pending.set(key, mergeOps(state.pending.get(key), op));
  rebuildView();
  persistLocal();
  scheduleSave();
}

function cancelAdvance() {
  clearTimeout(state.advanceTimer);
  state.advanceTimer = null;
}

function setVerdict(key, v) {
  const now = noteFor(key).verdict === v ? null : v;
  edit(key, { verdict: now });
  // The card stays visible even if the filter would now hide it; it drops out
  // when you move on (see moveFocus), so you can still add a note.
  cancelAdvance();
  if (now === "good" && el("#advance").checked) {
    state.advanceTimer = setTimeout(() => { state.advanceTimer = null; advanceAfterGood(); }, ADVANCE_DELAY);
  }
}

function toggleBadTake(key, n) {
  edit(key, { bad: { [n]: !(noteFor(key).bad_variants || []).includes(n) } });
}

function deleteOrphan(key) {
  if (!state.editedAt.has(key)) state.editedAt.set(key, Date.now());
  state.pending.set(key, null);
  rebuildView();
  persistLocal();
  scheduleSave();
  flash(`Deleted the old note for ${key}`);
}

function scheduleSave(delay = SAVE_DELAY) {
  setStatus("Saving…");
  clearTimeout(state.saveTimer);
  state.saveTimer = setTimeout(save, delay);
}

/** Move pending keys into one save, keeping the body well under the server's limit. */
function takeBatch(protocol) {
  const batch = new Map();
  const changes = protocol >= 2 ? { [PROTOCOL_GUARD]: null } : {};
  const enc = new TextEncoder();
  let bytes = 0;
  for (const [k, op] of state.pending) {
    const change = wireChange(k, op, protocol);
    const size = enc.encode(JSON.stringify(k) + JSON.stringify(change)).length + 2;
    if (batch.size && (bytes + size > MAX_BATCH_BYTES || batch.size >= state.batchKeys)) break;
    batch.set(k, op);
    changes[k] = change;
    bytes += size;
  }
  for (const k of batch.keys()) state.pending.delete(k);
  return { batch, changes };
}

/** A failed save's edits go back in the queue, under anything edited since. */
function putBack(batch) {
  for (const [k, op] of batch) state.pending.set(k, state.pending.has(k) ? mergeOps(op, state.pending.get(k)) : op);
}

/** An edit the server refused: out of the queue (it would only be refused again),
 *  shown to the user in plain words, and kept in this browser's backup and in
 *  Download notes so nothing is silently lost. */
function refuse(key, op, reason) {
  keepUnsaved(key, op, reason);
  if (!state.pending.has(key)) state.editedAt.delete(key);
}

/** Keep an edit that didn't reach the notes file (refused, or not restored) for
 *  Download notes, merged into what is already kept for that sound, so a second
 *  refusal never drops the first one's fields. */
function keepUnsaved(key, op, reason, at = Date.now()) {
  const prev = state.rejected[key];
  state.rejected[key] = { op: prev ? mergeOps(prev.op, op) : op, reason, at: prev ? prev.at : at, shown: true };
}

/** "dry_fire: why; hop: why" for a banner line. */
function whyList(entries) {
  return entries.map(([k, why]) => `${k}: ${String(why).replace(/\.$/, "")}`).join("; ");
}

function showRefused(list) {
  // a new refusal is shown even if the user closed an earlier version of this line
  if (list.length) for (const d of [...state.dismissed]) if (d.startsWith("refused\n")) state.dismissed.delete(d);
  for (const [k, why] of list) state.refusedNow.set(k, why);
  const all = [...state.refusedNow];
  if (all.length) {
    const one = all.length === 1;
    bannerSet("refused", `${one ? "This edit wasn't" : "These edits weren't"} saved — ${whyList(all)}. ` +
      `${one ? "It's" : "They're"} kept in this browser; Download notes lists ${one ? "it" : "them"} under “Not saved”.`);
  }
  showKept();
}

/** Edits kept from an earlier visit (refused then, or by a tab that has closed)
 *  that no other line names: one reminder, which stays closed once dismissed
 *  until the list changes. */
function showKept() {
  const named = new Set([...state.refusedNow.keys(), ...state.restoreSkipped]);
  const keys = Object.keys(state.rejected).filter((k) => !named.has(k)).sort();
  const one = keys.length === 1;
  bannerSet("kept", keys.length ? `${one ? "An earlier edit" : `${keys.length} earlier edits`} from this browser ` +
    `${one ? "wasn't" : "weren't"} saved: ${keys.join(", ")}. Download notes lists ${one ? "it" : "them"} under “Not saved”.` : null);
}

function retryDelay() { return Math.min(RETRY_MAX, RETRY_DELAY * 2 ** Math.max(0, state.failures - 1)); }

async function save() {
  if (state.saving || !state.pending.size) return;
  state.saving = true;
  state.saveGen++;
  clearTimeout(state.retryTimer);
  state.retryTimer = null;
  const protocol = state.protocol;
  const { batch, changes } = takeBatch(protocol);
  state.inflight = batch;
  let res = null, netError = null;
  try {
    res = await fetchJson("/api/notes", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ changes }),
    });
  } catch (e) {
    netError = e.name === "AbortError" ? "the review server took too long to answer"
      : "the review server isn't answering (is review.py still running?)";
  }
  state.inflight = new Map();
  try {
    if (res && res.ok) saved(batch, res.body);
    else failed(batch, protocol, res ? res.status : 0, netError || res.body.error || `HTTP ${res.status}`);
  } finally {
    state.saving = false;
    if (state.pending.size && !state.retryTimer) scheduleSave(200);
  }
}

function saved(batch, body) {
  if (typeof body.protocol === "number") state.protocol = body.protocol;
  const refused = [];
  const rejected = body.rejected && typeof body.rejected === "object" ? body.rejected : {};
  for (const [k, why] of Object.entries(rejected)) {
    if (!batch.has(k) || batch.get(k) === null) continue;
    refuse(k, batch.get(k), String(why));
    refused.push([k, String(why)]);
  }
  for (const k of batch.keys()) {
    if (!state.pending.has(k)) state.editedAt.delete(k);
    if (!(k in rejected)) delete state.rejected[k];   // a later save of that sound went through
  }
  adoptServer(body.notes);
  rebuildView();
  persistLocal();
  state.failures = 0;
  state.batchKeys = Infinity;
  // the problems the banner reported are over once a save gets through, and if
  // one comes back later (a new outage) it is shown again, even if it was closed
  for (const id of ["save", "notes-error", "restore"]) state.banner.delete(id);
  for (const d of [...state.dismissed]) if (/^(save|notes-error|restore)\n/.test(d)) state.dismissed.delete(d);
  renderBanner();
  showRefused(refused);
  // the status speaks once the queue is empty (more batches may still be on their way)
  state.refusedSinceSave += refused.length;
  if (!state.pending.size) {
    if (state.refusedSinceSave) setStatus(`${plural(state.refusedSinceSave, "edit")} not saved — see above`, true);
    else setStatus(`Saved ✓ ${new Date().toLocaleTimeString()}`);
    state.refusedSinceSave = 0;
  }
  if (!state.restoreStarted) restoreBackup();   // the notes file was unreadable when the page loaded
}

function failed(batch, protocol, status, reason) {
  const permanent = status >= 400 && status < 500 && status !== 408 && status !== 429;
  const unknown = /^unknown sound key: (['"])(.*)\1$/.exec(reason);
  if (permanent && unknown && unknown[2] === PROTOCOL_GUARD) {
    // an older review.py: it refused everything over the guard key, so nothing was
    // written; send the same edits again as whole entries
    state.protocol = 1;
    putBack(batch);
    return;
  }
  if (permanent && protocol >= 2) {
    if (status === 413 && batch.size > 1) {        // too big after all: send fewer keys at a time
      state.batchKeys = Math.max(1, Math.floor(batch.size / 2));
      putBack(batch);
      return;
    }
    // the whole save was refused (not one key): retrying can't help
    const list = [];
    for (const [k, op] of batch) if (op !== null) { refuse(k, op, reason); list.push([k, reason]); }
    rebuildView();
    persistLocal();
    showRefused(list);
    setStatus(`${plural(batch.size, "edit")} not saved — see above`, true, reason);
    return;
  }
  if (permanent && unknown && batch.has(unknown[2])) {
    // an older review.py refuses a whole save over one key it doesn't know: take
    // that key out (deleting an old note that is already gone is done) and go on
    const k = unknown[2], op = batch.get(k);
    batch.delete(k);
    if (op !== null) {
      const why = "this sound isn't in the sound list any more (it was renamed or removed)";
      refuse(k, op, why);
      showRefused([[k, why]]);
      state.refusedSinceSave++;   // the resend's saved() can't see it: count it for the status
    } else if (!state.pending.has(k)) state.editedAt.delete(k);
    putBack(batch);
    rebuildView();
    persistLocal();
    if (!state.pending.size) {    // nothing left to send, so no saved() will set the status
      if (state.refusedSinceSave) setStatus(`${plural(state.refusedSinceSave, "edit")} not saved — see above`, true);
      else setStatus(`Saved ✓ ${new Date().toLocaleTimeString()}`);
      state.refusedSinceSave = 0;
    }
    return;
  }
  // server away, timed out, notes file unreadable, …: keep everything and retry
  putBack(batch);
  rebuildView();
  persistLocal();
  state.failures++;
  const unreadable = status === 503 || /could not be read|refusing to overwrite/.test(reason);
  setStatus(unreadable ? "Not saved — notes file unreadable; your edits are kept here" : "Not saved yet — retrying", true, reason);
  bannerSet("save", unreadable && state.banner.has("notes-error") ? null   // that line already says why
    : unreadable && /[.)]$/.test(reason) ? `⚠ ${reason}`
    : `⚠ Your latest edits aren't saved yet: ${reason}. They're kept in this browser and saving is retried every few seconds.`);
  state.retryTimer = setTimeout(() => { state.retryTimer = null; save(); }, retryDelay());
}

// ---------------------------------------------------------------------------
// local backup: one slot per tab, so tabs never overwrite each other's
// ---------------------------------------------------------------------------

function slotPrefix() { return `bbd-audio-review:v2:${state.notesId}:`; }
function mySlot() { return slotPrefix() + TAB_ID; }
function legacySlot() { return `bbd-audio-review:${state.notesId}`; }   // pages before protocol 2: one slot for all tabs
function legacyDoneKey() { return `bbd-audio-review:legacy-migrated:${state.notesId}`; }   // key -> legacy entry taken over

/** Write this tab's slot: its unsynced edits, each with the server value it was
 *  made on (so a later visit can tell whether it still applies) and, once the
 *  close-time beacon carried it, when that was, its save id and protocol; plus
 *  edits the server refused. Only this tab writes it; a slot whose tab is gone is
 *  taken over (and removed) by the next page that loads. */
function persistLocal(sent = null) {
  try {
    const edits = {};
    for (const [k, op] of unsyncedOps()) {
      const rec = { op, at: state.editedAt.get(k) || Date.now() };
      if (state.known) rec.base = serverEntry(k);
      if (sent) Object.assign(rec, sent);   // {sent: time, beacon: save id, via: protocol}
      edits[k] = rec;
    }
    if (Object.keys(edits).length || Object.keys(state.rejected).length) {
      localStorage.setItem(mySlot(), JSON.stringify({ at: Date.now(), edits, rejected: state.rejected }));
    } else {
      localStorage.removeItem(mySlot());
    }
  } catch (_) { /* storage blocked or full: the server copy still works */ }
}

/** Tabs that are still open (each holds a Web Lock for its lifetime); null if unknown. */
async function liveTabs() {
  try {
    const { held = [] } = await navigator.locks.query();
    return new Set(held.map((l) => l.name).filter((n) => n.startsWith(TAB_LOCK)).map((n) => n.slice(TAB_LOCK.length)));
  } catch (_) {
    return null;   // no Web Locks: every other slot counts as left behind
  }
}

/** A pre-protocol-2 backup entry (a whole entry, or null) as a backup record.
 *  It has no base value, so it only applies if the notes file hasn't changed
 *  since it was written. */
function legacyRecord(key, entry, savedAt) {
  const cur = serverEntry(key);
  let op;
  if (entry === null || typeof entry !== "object") {
    op = state.byKey.has(key) ? { verdict: null, note: "", bad: {} } : null;
  } else {
    op = { verdict: entry.verdict || null, note: typeof entry.note === "string" ? cleanNote(entry.note) : "", bad: {} };
    for (const n of Array.isArray(entry.bad_variants) ? entry.bad_variants : []) if (Number.isInteger(n)) op.bad[n] = true;
  }
  if (op) for (const n of cur ? cur.bad_variants : []) if (!(n in op.bad)) op.bad[n] = false;
  const updated = Date.parse(state.serverUpdated || "");
  const stale = Number.isFinite(updated) && Number.isFinite(savedAt) && updated > savedAt + 1000;
  return { op, at: Number(savedAt) || 0, stale };
}

/** Which parts of a backed-up edit still need saving. Fields the server already
 *  has are done (e.g. the close-time beacon got through); fields the server
 *  changed after the edit was made are newer there and win (conflict). */
function resolveRecord(key, rec) {
  const cur = serverEntry(key);
  const hasBase = rec.base !== undefined;     // undefined: the server's notes weren't readable then
  const untouched = (now, was) => !rec.stale && (!hasBase || now === was);
  if (rec.op === null) {
    if (!cur) return { op: undefined, conflict: false };
    return untouched(JSON.stringify(cur), JSON.stringify(rec.base || null)) ? { op: null, conflict: false } : { op: undefined, conflict: true };
  }
  if (!rec.op || typeof rec.op !== "object") return { op: undefined, conflict: false };
  const c = cur || blankEntry(), b = rec.base || blankEntry();
  const out = {};
  let conflict = false;
  if ("verdict" in rec.op) {
    const want = rec.op.verdict || null;
    if ((c.verdict || null) !== want) {
      if (untouched(c.verdict || null, b.verdict || null)) out.verdict = want; else conflict = true;
    }
  }
  if ("note" in rec.op && typeof rec.op.note === "string") {
    if ((c.note || "") !== rec.op.note) {
      if (untouched(c.note || "", b.note || "")) out.note = cleanNote(rec.op.note); else conflict = true;
    }
  }
  for (const [n, on] of Object.entries(rec.op.bad || {})) {
    const now = (c.bad_variants || []).includes(Number(n));
    if (now === Boolean(on)) continue;
    if (untouched(now, (b.bad_variants || []).includes(Number(n)))) (out.bad ||= {})[n] = Boolean(on);
    else conflict = true;
  }
  return { op: Object.keys(out).length ? out : undefined, conflict };
}

const NOT_RESTORED = {
  newer: "the notes file has a newer change for this sound",
  beacon: "it was sent when its tab closed, but the notes file has no record of it",
};

/** Did an edit the close-time beacon carried reach the notes file? "landed",
 *  "lost" or "unknown". A current review.py lists the beacons it applied since it
 *  started; an older one refuses a protocol-2 save whole (the guard key). Failing
 *  those, the file's save time decides: saved since the beacon went out (its
 *  stamp has whole seconds) = landed. A file with no save time at all was
 *  deleted or replaced since, so an edit that may have been in it is unknown. */
function beaconFate(rec, written) {
  const stamped = Number.isFinite(written);
  if (Array.isArray(state.delivered) && rec.beacon) {
    if (state.delivered.includes(rec.beacon)) return stamped ? "landed" : "unknown";
    if (state.serverStarted && state.serverStarted < rec.sent) return "lost";   // this server was up, and never got it
  }
  if (rec.via >= 2 && state.protocol < 2) return "lost";
  if (!stamped) return "unknown";
  return written >= rec.sent - 2000 ? "landed" : "lost";
}

/** Edits left in this browser by tabs that are gone (closed, crashed, or the
 *  server was down when they closed): taken over, then re-applied where the notes
 *  file still has what each edit was made on. Runs once the server's notes are
 *  readable. */
async function restoreBackup() {
  if (state.restoreStarted) return;
  state.restoreStarted = true;
  const live = await liveTabs();
  const found = [];
  const adopted = [];
  let names = [];
  try { names = Array.from({ length: localStorage.length }, (_, i) => localStorage.key(i)); } catch (_) { /* storage blocked */ }
  for (const name of names) {
    if (!name || !name.startsWith(slotPrefix()) || name === mySlot()) continue;
    if (live && live.has(name.slice(slotPrefix().length))) continue;   // still open: it saves its own
    try {
      const slot = JSON.parse(localStorage.getItem(name) || "null");
      localStorage.removeItem(name);
      for (const [k, rec] of Object.entries((slot && slot.edits) || {})) if (rec && typeof rec === "object") found.push({ key: k, rec });
      for (const [k, r] of Object.entries((slot && slot.rejected) || {})) if (r && typeof r === "object") adopted.push([k, r]);
    } catch (_) { /* unreadable slot: skip it */ }
  }
  try {
    const legacy = JSON.parse(localStorage.getItem(legacySlot()) || "null");
    localStorage.removeItem(legacySlot());
    if (legacy && legacy.pending && typeof legacy.pending === "object") {
      // An old page that is still open (say, stuck retrying) writes that slot again
      // every few seconds with the same entries: each entry is taken over once only.
      let done = null;
      try { done = JSON.parse(localStorage.getItem(legacyDoneKey()) || "null"); } catch (_) { /* unreadable: start afresh */ }
      if (!done || typeof done !== "object" || Array.isArray(done)) done = {};
      for (const [k, entry] of Object.entries(legacy.pending)) {
        const print = JSON.stringify(entry);
        if (done[k] === print) continue;
        done[k] = print;
        found.push({ key: k, rec: legacyRecord(k, entry, legacy.saved_at) });
      }
      try { localStorage.setItem(legacyDoneKey(), JSON.stringify(done)); } catch (_) { /* storage full */ }
    }
  } catch (_) { /* unreadable: ignore */ }

  // edits refused on earlier visits: oldest first, merged per sound (so no field
  // drops out), under anything refused during this visit
  const cutoff = Date.now() - KEEP_REFUSED_DAYS * 864e5;
  const kept = {};
  adopted.sort((a, b) => (a[1].at || 0) - (b[1].at || 0));
  for (const [k, r] of adopted) {
    if (!(r.at > cutoff)) continue;
    kept[k] = kept[k] ? { ...r, op: mergeOps(kept[k].op, r.op), at: kept[k].at } : r;
  }
  for (const [k, r] of Object.entries(kept)) {
    const mine = state.rejected[k];
    state.rejected[k] = mine ? { ...mine, op: mergeOps(r.op, mine.op), at: r.at } : r;
  }
  const unseen = Object.entries(state.rejected).filter(([, r]) => !r.shown);
  for (const [, r] of unseen) r.shown = true;

  found.sort((a, b) => (a.rec.at || 0) - (b.rec.at || 0));
  const restored = new Map();
  const skipped = new Map();   // key -> why it wasn't restored
  const written = Date.parse(state.serverUpdated || "");   // the notes file's last save
  for (const { key, rec } of found) {
    // Carried by the close-time beacon: if it arrived, what the file holds now is
    // newer (it may have been undone on purpose), so leave it; if there's no
    // telling, keep it for the user rather than re-apply it; if it was lost,
    // restore it like any other edit.
    const fate = rec.sent ? beaconFate(rec, written) : "lost";
    if (fate === "landed") continue;
    const { op, conflict } = resolveRecord(key, rec);
    if (fate === "unknown") {
      if (op !== undefined || conflict) {
        skipped.set(key, NOT_RESTORED.beacon);
        keepUnsaved(key, rec.op, NOT_RESTORED.beacon, rec.at || Date.now());
      }
      continue;
    }
    if (conflict) {
      skipped.set(key, NOT_RESTORED.newer);
      keepUnsaved(key, rec.op, NOT_RESTORED.newer, rec.at || Date.now());
    }
    if (op === undefined) continue;
    if (op !== null && !state.byKey.has(key)) {
      keepUnsaved(key, op, "this sound isn't in the sound list any more (it was renamed or removed)", rec.at || Date.now());
      unseen.push([key, state.rejected[key]]);
      continue;
    }
    if (!state.editedAt.has(key) || state.editedAt.get(key) > (rec.at || 0)) state.editedAt.set(key, rec.at || Date.now());
    restored.set(key, mergeOps(restored.get(key), op));
  }
  for (const [k, op] of restored) state.pending.set(k, state.pending.has(k) ? mergeOps(op, state.pending.get(k)) : op);
  rebuildView();
  persistLocal();
  if (restored.size) {
    bannerSet("restore", `Restored ${plural(restored.size, "edit")} that hadn't reached the notes file yet — saving now.`);
    setStatus("Saving restored edits…");
    scheduleSave(100);
  }
  for (const k of skipped.keys()) state.restoreSkipped.add(k);
  if (skipped.size) {
    const one = skipped.size === 1;
    bannerSet("restore-skipped", `Didn't restore ${one ? "an older edit" : `${skipped.size} older edits`} from this browser — ` +
      `${whyList([...skipped])}. Download notes lists ${one ? "it" : "them"} under “Not saved”.`);
  }
  showRefused(unseen.map(([k, r]) => [k, r.reason]));   // and the reminder of edits kept from earlier visits
}

// ---------------------------------------------------------------------------
// staying in sync: other tabs' edits, rebuilt sounds, a changed sound list
// ---------------------------------------------------------------------------

function catalogShape(d) {
  return JSON.stringify([(d.groups || []).map((g) => g.keys.map((k) => [k.key, k.files.map((f) => f.file)])), (d.music || []).map((m) => m.key)]);
}

/** The banner line for an unreadable notes file; before any notes were read, it
 *  also explains why no verdicts are shown. */
function notesErrorLine(err) {
  if (state.known) return `⚠ ${err}`;
  return `⚠ ${err}${/[.!?]$/.test(err) ? "" : "."} Until then, the notes saved earlier aren't shown here.`;
}

function loadedStatus() {
  return Object.keys(state.notes.keys).length ? "Loaded your saved notes" : "Notes save automatically";
}

function setWarnings(list) {
  for (const id of [...state.banner.keys()]) if (id.startsWith("warn:")) state.banner.delete(id);
  for (const w of Array.isArray(list) ? list : []) state.banner.set(`warn:${w}`, String(w));
  renderBanner();
}

/** Re-read /api/data when the tab comes back into view: notes saved by other
 *  tabs show up (except in a note box that is being typed in), and rebuilt
 *  sounds are reloaded. */
async function refresh() {
  if (state.refreshing || document.hidden || !state.data || performance.now() - state.refreshedAt < 1500) return;
  state.refreshing = true;
  state.refreshedAt = performance.now();
  const gen = state.saveGen;
  try {
    const res = await fetchJson("/api/data", {}, 10000);
    if (!res.ok) return;
    const data = res.body;
    serverInfo(data);                             // the server may have been restarted
    const rebuilt = applyAudioVersions(data);
    if (rebuilt) flash(`Reloaded ${plural(rebuilt, "rebuilt sound file")}`);
    bannerSet("catalog", catalogShape(data) === state.shape ? null
      : "The sound list has changed since this page was opened (a sound was added, renamed or removed). Reload the page to see it; your notes are safe.");
    setWarnings(data.warnings);
    if (data.notes_error) { bannerSet("notes-error", notesErrorLine(data.notes_error)); return; }
    bannerSet("notes-error", null);
    if (gen !== state.saveGen || state.saving) return;   // a save raced this read: its reply is newer
    const wasKnown = state.known;
    adoptServer(data.notes);
    rebuildView();
    persistLocal();
    // the file was unreadable when the page loaded and is fine now (edits waiting to
    // be saved say so themselves when their retry gets through)
    if (!wasKnown && !state.pending.size) setStatus(loadedStatus());
    if (!state.restoreStarted) restoreBackup();
  } catch (_) {
    /* server away: the save status already says so if it matters */
  } finally {
    state.refreshing = false;
  }
}

/** Hold this tab's Web Lock (so other tabs know it is open) and, in one tab per
 *  browser, the presence stream that tells the server a review tab is open (it
 *  works in background tabs, unlike timers; --idle-exit stops after it closes).
 *  One stream per tab would use up the browser's six connections to the server. */
function holdLocks() {
  const presence = () => { try { new EventSource("/api/presence"); } catch (_) { /* old browser: no auto-exit */ } };
  if (!navigator.locks || !navigator.locks.request) { presence(); return; }
  navigator.locks.request(TAB_LOCK + TAB_ID, () => new Promise(() => {})).catch(() => {});
  navigator.locks.request(PRESENCE_LOCK, () => { presence(); return new Promise(() => {}); }).catch(presence);
}

function updateProgress() {
  const total = state.cards.length;
  const rated = state.cards.filter((c) => noteFor(c.key).verdict).length;
  const work = state.cards.filter((c) => ["tweak", "replace"].includes(noteFor(c.key).verdict)).length;
  el("#progress-fill").style.width = `${total ? (100 * rated) / total : 0}%`;
  const t = el("#progress-text");
  t.textContent = "";
  t.append(`${rated} / ${total}`, h("span", { class: "wide", text: " reviewed" }), work ? ` · ${work} need work` : "");
}

// ---------------------------------------------------------------------------
// filtering, focus, keyboard
// ---------------------------------------------------------------------------

function passes(text, verdict) {
  const q = state.query.trim().toLowerCase();
  if (q && !text.toLowerCase().includes(q)) return false;
  if (state.filter === "todo") return !verdict;
  if (state.filter === "work") return verdict === "tweak" || verdict === "replace";
  if (state.filter === "good") return verdict === "good";
  return true;
}

function matches(c) {
  return passes(`${c.key} ${c.entry.expect} ${c.entry.when} ${c.entry.title || ""}`, noteFor(c.key).verdict);
}

function filterOrphans() {
  document.querySelectorAll("#g-orphans .card").forEach((card) => {
    const e = state.notes.orphans[card.dataset.key] || blankEntry();
    card.classList.toggle("hidden", !passes(`${card.dataset.key} ${e.note || ""}`, e.verdict || null));
  });
}

/** Section visibility + counts, the TOC chips (none for hidden sections, one for
 *  old notes) and the "nothing matches" line. */
function updateSections() {
  let any = false;
  document.querySelectorAll("#list section").forEach((s) => {
    const visible = s.querySelectorAll(".card:not(.hidden)").length;
    s.hidden = !visible;
    any ||= visible > 0;
    const count = s.querySelector(".count");
    if (count && count.dataset.total) {
      const total = Number(count.dataset.total);
      count.textContent = visible === total ? `(${total})` : `(${visible} of ${total})`;
    }
  });
  const toc = el("#toc");
  const chip = toc.querySelector('a[href="#g-orphans"]');
  if (el("#g-orphans") && !chip) toc.append(h("a", { href: "#g-orphans", text: "Old notes" }));
  else if (!el("#g-orphans") && chip) chip.remove();
  toc.querySelectorAll("a").forEach((a) => {
    const s = document.getElementById(a.getAttribute("href").slice(1));
    a.hidden = !s || s.hidden;
  });
  const empty = el("#empty");
  empty.hidden = any || !state.cards.length;
  if (!empty.hidden) {
    const q = state.query.trim();
    const where = FILTER_NAMES[state.filter];
    el("#empty-text").textContent =
      q && where ? `Nothing under “${where}” matches “${q}”.`
      : q ? `No sounds match “${q}”.`
      : state.filter === "todo" ? "Nothing left to review 🎉"
      : state.filter === "work" ? "Nothing needs work right now."
      : "Nothing is marked Good yet.";
  }
}

/** Show/hide cards for the current filter. With refocus, a hidden highlighted
 *  card hands the highlight to the next visible one, without moving keyboard
 *  focus (typing in the search box must stay there). Callers that are about to
 *  move focus themselves pass refocus=false so no card gets skipped. */
function applyFilter({ refocus = true } = {}) {
  for (const c of state.cards) c.el.classList.toggle("hidden", !matches(c));
  filterOrphans();
  updateSections();
  const cur = state.cards[state.focus];
  if (refocus && cur && cur.el.classList.contains("hidden")) {
    const next = nearestVisible(state.focus, 1);
    if (next >= 0) focusCard(next, { scroll: false, dom: false });
  }
}

function setFilter(f) {
  document.querySelectorAll(".seg button").forEach((x) => {
    x.classList.toggle("on", x.dataset.filter === f);
    x.setAttribute("aria-pressed", String(x.dataset.filter === f));
  });
  state.filter = f;
  if (f === "all") { state.query = ""; el("#search").value = ""; }
  applyFilter();
}

function isVisible(i) { return i >= 0 && i < state.cards.length && !state.cards[i].el.classList.contains("hidden"); }

/** First visible card strictly after (dir=1) or before (dir=-1) index i; falls
 *  back to the other direction; -1 if nothing is visible. */
function nearestVisible(i, dir) {
  for (let j = i + dir; j >= 0 && j < state.cards.length; j += dir) if (isVisible(j)) return j;
  for (let j = i - dir; j >= 0 && j < state.cards.length; j -= dir) if (isVisible(j)) return j;
  return -1;
}

function focusCard(i, { scroll = true, dom = true } = {}) {
  if (i < 0 || i >= state.cards.length) return;
  if (i !== state.focus) cancelAdvance();
  if (state.focus >= 0 && state.cards[state.focus]) state.cards[state.focus].el.classList.remove("focused");
  state.focus = i;
  const c = state.cards[i];
  c.el.classList.add("focused");
  state.userScrolled = false;
  // keep real DOM focus with the highlight, so Space/Enter can't hit a button
  // left focused on another card (but never take it from a text box)
  const active = document.activeElement;
  if (dom && !c.el.contains(active) && !isTextEntry(active)) c.el.focus({ preventScroll: true });
  if (scroll) {
    state.autoScrollUntil = performance.now() + 1000;
    c.el.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }
}

/** The first visible card on screen below the sticky bar, or -1. */
function firstOnScreen() {
  const top = el("#bar").getBoundingClientRect().bottom;
  for (let i = 0; i < state.cards.length; i++) {
    if (!isVisible(i)) continue;
    const r = state.cards[i].el.getBoundingClientRect();
    if (r.bottom > top + 24 && r.top < window.innerHeight) return i;
  }
  return -1;
}

function moveFocus(step) {
  cancelAdvance();
  applyFilter({ refocus: false });   // cards that no longer match (e.g. just rated) drop out now
  if (state.focus < 0) { const first = nearestVisible(-1, 1); if (first >= 0) focusCard(first); return; }
  // scrolled away (wheel, TOC, scrollbar) from the highlight: go on from what's on screen
  if (state.userScrolled && isVisible(state.focus)) {
    const r = state.cards[state.focus].el.getBoundingClientRect();
    if (r.bottom < el("#bar").getBoundingClientRect().bottom || r.top > window.innerHeight) {
      const s = firstOnScreen();
      if (s >= 0) { focusCard(s); return; }
    }
  }
  let j = state.focus;
  for (j += step; j >= 0 && j < state.cards.length; j += step) if (isVisible(j)) break;
  if (j >= 0 && j < state.cards.length) focusCard(j);
  else if (!isVisible(state.focus)) { const n = nearestVisible(state.focus, -step); if (n >= 0) focusCard(n); }
}

function nextUnreviewed() {
  cancelAdvance();
  applyFilter({ refocus: false });
  const total = state.cards.length;
  for (let d = 1; d <= total; d++) {
    const j = (Math.max(state.focus, 0) + d) % total;
    if (isVisible(j) && !noteFor(state.cards[j].key).verdict) { focusCard(j); return; }
  }
  // nothing left to review here: keep a visible card highlighted
  if (!isVisible(state.focus)) { const n = nearestVisible(state.focus, 1); if (n >= 0) focusCard(n); }
  flash(state.filter === "all" && !state.query.trim() ? "Every sound has a verdict 🎉" : "Everything shown here has a verdict 🎉");
}

/** "Next after 👍": the next sound to review, or under Needs work / Good (where
 *  everything has a verdict) simply the next sound shown. */
function advanceAfterGood() {
  if (state.filter === "all" || state.filter === "todo") nextUnreviewed();
  else moveFocus(1);
}

/** Focused with the keyboard (it shows a focus ring), not by a mouse click. */
function hasFocusRing(t) {
  try { return t.matches(":focus-visible"); } catch (_) { return true; }   // a browser without it: as before
}

/** Space/Enter on a focused element: true = play the highlighted sound instead
 *  of letting the element act. Controls outside the sound cards (toolbar, filter,
 *  TOC, footer, old-note buttons) reached with the keyboard, and controls on the
 *  highlighted card, keep their own activation. Redirected: a control left
 *  focused on a different sound card, a toolbar button or link last clicked with
 *  the mouse (no focus ring), the volume slider (Space/Enter mean nothing to it)
 *  and Enter on a checkbox. */
function keyPlays(t, card, key) {
  if (!t || t === document.body || t === document.documentElement || t === card.el || t.id === "list") return true;
  const owner = t.closest && t.closest(".card");
  if (owner && owner !== card.el && !owner.classList.contains("orphan")) return true;
  if (t.matches("input[type=range]") || (key === "Enter" && t.matches("input[type=checkbox]"))) return true;
  if (!owner && t.matches("button, a") && !hasFocusRing(t)) return true;
  return !t.matches("button, a, input, select, textarea, summary, audio, [contenteditable]");
}

function onKey(e) {
  if (el("#help").open) return;                        // the dialog handles its own keys
  const t = e.target;
  if (t.matches && t.matches("textarea")) {
    if (e.key === "Escape") { const card = t.closest(".card"); t.blur(); if (card) card.focus({ preventScroll: true }); }
    return;
  }
  if (t.matches && t.matches("input[type=search]")) {
    if (e.key === "Escape") { e.preventDefault(); t.value = ""; state.query = ""; applyFilter(); t.blur(); }
    return;
  }
  if (e.ctrlKey || e.metaKey || e.altKey) return;
  const key = e.key.length === 1 ? e.key.toLowerCase() : e.key;
  if (/^(PageUp|PageDown|Home|End)$/.test(key)) state.userScrolled = true;
  // let real controls keep the keys they need, but nothing else
  if (t.matches && t.matches("audio") && key !== "Escape") return;
  if (t.matches && t.matches("input[type=range]") && /^Arrow|^Home$|^End$|^Page/.test(key)) return;
  if (t.matches && t.matches("input[type=checkbox]") && key === " ") return;
  if (key === "Escape") { stopAll(); return; }
  if (key === "?") { openHelp(false); return; }
  if (key === "/") { e.preventDefault(); el("#search").focus(); return; }
  if (key === "j" || key === "ArrowDown") { e.preventDefault(); moveFocus(1); return; }
  if (key === "k" || key === "ArrowUp") { e.preventDefault(); moveFocus(-1); return; }
  if (key === "u") { e.preventDefault(); nextUnreviewed(); return; }
  const card = state.cards[state.focus];
  if (!card || card.el.classList.contains("hidden")) return;
  if ((key === " " || key === "Enter") && !keyPlays(t, card, key)) return;   // the control acts itself
  if (card.music) {
    const player = card.el.querySelector("audio");
    if (key === " ") { e.preventDefault(); if (player.paused) player.play(); else player.pause(); }
  } else if (key === " " || key === "Enter") {
    e.preventDefault();
    playVariant(card, state.nextVariant.get(card.key) || 1);
  } else if (/^[1-9]$/.test(key)) {
    playVariant(card, Number(key));
  } else if (key === "a") {
    playAll(card);
  } else if (key === "b") {
    burst(card);
  } else if (key === "l") {
    toggleLoop(card);
  }
  if (key === "g") setVerdict(card.key, "good");
  else if (key === "t") setVerdict(card.key, "tweak");
  else if (key === "r") setVerdict(card.key, "replace");
  else if (key === "n") { e.preventDefault(); cancelAdvance(); card.el.querySelector("textarea").focus(); }
}

/** After a mouse click on a filter, Stop, Copy summary, Download notes, Show all
 *  or an old note's Delete, hand keyboard focus back to the highlighted sound so
 *  Space plays it (keyboard activation keeps focus). */
function refocusAfterMouse(e) {
  const card = state.cards[state.focus];
  if (e.detail > 0 && card && isVisible(state.focus)) card.el.focus({ preventScroll: true });
}

/** The shortcuts dialog. Closing it hands the keyboard back to the highlighted
 *  sound, unless it was opened from its button with the keyboard (then focus
 *  goes back to that button, as usual): the browser would otherwise put focus on
 *  the button with a focus ring, and Space would open the dialog again. */
function openHelp(fromButtonKeys) {
  state.helpFromKeys = fromButtonKeys;
  el("#help").showModal();
}

function onHelpClose() {
  const card = state.cards[state.focus];
  if (!state.helpFromKeys && card && isVisible(state.focus)) card.el.focus({ preventScroll: true });
}

/** A TOC jump highlights the first sound shown in that section. */
function onTocClick(e) {
  const a = e.target.closest && e.target.closest("a");
  if (!a) return;
  const sec = document.getElementById(a.getAttribute("href").slice(1));
  const first = sec && [...sec.querySelectorAll(".card:not(.hidden)")].map((n) => cardIndex(n.dataset.key)).find((i) => i >= 0);
  if (first !== undefined) focusCard(first, { scroll: false, dom: false });
  state.userScrolled = true;
}

// ---------------------------------------------------------------------------
// export
// ---------------------------------------------------------------------------

function summaryMarkdown() {
  const order = { replace: 0, tweak: 1, good: 3 };
  const line = (key, n) => {
    const bad = (n.bad_variants || []).length ? ` — bad takes: ${n.bad_variants.join(", ")}` : "";
    const note = n.note && n.note.trim() ? `: ${n.note.trim()}` : "";
    return `- **${key}** [${(n.verdict || "unrated").toUpperCase()}]${bad}${note}`;
  };
  const rows = state.cards
    .map((c) => ({ key: c.key, n: noteFor(c.key) }))
    .filter((r) => r.n.verdict || r.n.note || (r.n.bad_variants || []).length)
    .sort((a, b) => (order[a.n.verdict] ?? 2) - (order[b.n.verdict] ?? 2) || a.key.localeCompare(b.key));
  const lines = ["# Bunny Beat Down — audio review notes", "", ...rows.map((r) => line(r.key, r.n))];
  const orphans = Object.entries(state.notes.orphans || {});
  if (orphans.length) lines.push("", "## Notes for sounds no longer in the game", "", ...orphans.map(([k, n]) => line(k, n)));
  return lines.join("\n") + "\n";
}

async function copySummary() {
  try { await navigator.clipboard.writeText(summaryMarkdown()); flash("Summary copied to the clipboard ✓"); }
  catch (_) { flash("The clipboard is blocked here — use Download notes instead"); }
}

function downloadNotes() {
  const out = { version: 1, keys: state.notes.keys, orphans: state.notes.orphans };
  const refused = Object.entries(state.rejected);
  // edits the server refused (or that a newer change replaced): kept so nothing is silently lost
  if (refused.length) out.not_saved = Object.fromEntries(refused.map(([k, r]) => [k, { change: opToChange(r.op), reason: r.reason }]));
  const blob = new Blob([JSON.stringify(out, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = h("a", { href: url, download: "audio_review_notes.json" });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

// ---------------------------------------------------------------------------
// boot
// ---------------------------------------------------------------------------

async function boot() {
  try {
    const res = await fetchJson("/api/data", {}, 20000);
    if (!res.ok) throw new Error(`server said ${res.status}`);
    state.data = res.body;
  } catch (e) {
    const why = e.name === "AbortError" ? "the server took too long to answer" : e.message;
    el("#list").textContent = `Couldn't load the sound list (${why}). Is tools/audio/review.py running?`;
    return;
  }
  state.refreshedAt = performance.now();
  serverInfo(state.data);
  state.notesId = state.data.notes_id || "default";
  try { state.dismissed = new Set(JSON.parse(localStorage.getItem(dismissedKey()) || "[]")); } catch (_) { /* ignore */ }
  holdLocks();
  setWarnings(state.data.warnings);
  if (state.data.notes_error) bannerSet("notes-error", notesErrorLine(state.data.notes_error));
  else adoptServer(state.data.notes);
  rebuildView();

  render();
  if (state.data.notes_error) setStatus("Not saved — notes file unreadable; your edits are kept here", true, state.data.notes_error);
  else setStatus(loadedStatus());

  el("#volume").addEventListener("input", (e) => {
    const v = Number(e.target.value);
    if (state.master) state.master.gain.value = v;
    document.querySelectorAll("audio").forEach((a) => { a.volume = v; });
  });
  el("#stop-all").addEventListener("click", (e) => { stopAll(); refocusAfterMouse(e); });
  el("#help-btn").addEventListener("click", (e) => openHelp(e.detail === 0));
  el("#help").addEventListener("close", onHelpClose);
  const narrow = matchMedia("(max-width: 600px)");   // the phone bar has room for a short hint only
  const placeholder = () => { el("#search").placeholder = narrow.matches ? "Filter…" : "Filter sounds…  (/)"; };
  placeholder();
  narrow.addEventListener("change", placeholder);
  el("#search").addEventListener("input", (e) => { state.query = e.target.value; applyFilter(); });
  el("#search").addEventListener("search", (e) => { state.query = e.target.value; applyFilter(); });
  document.querySelectorAll(".seg button").forEach((b) => b.addEventListener("click", (e) => { setFilter(b.dataset.filter); refocusAfterMouse(e); }));
  el("#show-all").addEventListener("click", (e) => { setFilter("all"); refocusAfterMouse(e); });
  el("#toc").addEventListener("click", onTocClick);
  document.querySelectorAll("[data-act='copy-summary']").forEach((b) => b.addEventListener("click", (e) => { copySummary(); refocusAfterMouse(e); }));
  document.querySelectorAll("[data-act='download-json']").forEach((b) => b.addEventListener("click", (e) => { downloadNotes(); refocusAfterMouse(e); }));
  document.addEventListener("keydown", onKey);
  document.addEventListener("focusin", (e) => { if (isTextEntry(e.target)) cancelAdvance(); });
  window.addEventListener("resize", () => {
    document.querySelectorAll("canvas.wave").forEach((c) => {
      const p = state.buffers.get(c.dataset.url);
      if (p) p.then((buf) => drawWave(c, buf)).catch(() => {});
    });
  });
  // J/K go on from what's on screen after the reader scrolls away from the highlight
  // (wheel, touch, scroll keys, or any scroll that isn't our own smooth scroll)
  const scrolledByUser = () => { state.userScrolled = true; };
  window.addEventListener("wheel", scrolledByUser, { passive: true });
  window.addEventListener("touchmove", scrolledByUser, { passive: true });
  window.addEventListener("scroll", () => { if (performance.now() > state.autoScrollUntil) scrolledByUser(); }, { passive: true });
  // keep jump targets clear of the sticky bar, whatever its height
  const bar = el("#bar");
  new ResizeObserver(() => {
    document.documentElement.style.scrollPaddingTop = `${bar.offsetHeight + 12}px`;
  }).observe(bar);
  // other tabs' notes, rebuilt sounds: catch up whenever this tab is looked at again
  document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
  window.addEventListener("focus", refresh);
  // last-chance save when the tab goes away; the backup slot stays, and the next
  // visit only re-applies what the server doesn't have yet
  window.addEventListener("pagehide", () => {
    const ops = unsyncedOps();
    if (!ops.size) return;
    const protocol = state.protocol;
    const changes = protocol >= 2 ? { [PROTOCOL_GUARD]: null } : {};
    for (const [k, op] of ops) changes[k] = wireChange(k, op, protocol);
    // the id lets a later visit ask a current review.py whether this arrived (an older one ignores it)
    const saveId = `${TAB_ID}-${Date.now().toString(36)}`;
    const queued = navigator.sendBeacon("/api/notes", new Blob([JSON.stringify({ changes, save_id: saveId })], { type: "application/json" }));
    // only worth marking as sent if saves were getting through (a queued beacon may still fail)
    if (queued && !state.failures) persistLocal({ sent: Date.now(), beacon: saveId, via: protocol });
  });
  const first = nearestVisible(-1, 1);
  if (first >= 0) focusCard(first, { scroll: false });
  if (state.known) restoreBackup();
}

boot();
