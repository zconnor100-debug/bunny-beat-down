// Bunny Beat Down — game notes page (no dependencies). Talks to tools/notes/notes.py.
"use strict";

const STATUS_LABEL = { new: "New", working: "Claude is on it", done: "Done", needs_you: "Needs you" };
const POLL_MS = 15000;
const DRAFT_KEY = "bbd-notes-draft";
const FILTER_KEY = "bbd-notes-filter";

const state = { notes: [], ownerActivity: null, watching: false, idleMinutes: 60, categories: [],
                filter: "open", open: new Set(), loaded: false };

const el = (sel) => document.querySelector(sel);

/** Element builder: text always goes in as textContent (never parsed as HTML). */
function h(tag, props = {}, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") e.className = v;
    else if (k === "text") e.textContent = v;
    else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v);
  }
  for (const kid of kids) if (kid) e.append(kid);
  return e;
}

function store(key, value) { try { localStorage.setItem(key, value); } catch { /* private mode */ } }
function recall(key) { try { return localStorage.getItem(key); } catch { return null; } }

function when(iso) {
  return new Date(iso).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

function say(msg, isError = false) {
  const s = el("#save");
  s.textContent = msg;
  s.classList.toggle("err", isError);
}

function take(data) {
  state.notes = data.notes;
  state.ownerActivity = data.owner_activity;
  state.watching = data.watching;
  state.idleMinutes = data.idle_minutes;
  if (!state.categories.length) {
    state.categories = data.categories;
    const sel = el("#category");
    for (const c of data.categories) sel.append(h("option", { value: c, text: c }));
  }
  state.loaded = true;
}

async function load() {
  try {
    const r = await fetch("/api/notes", { cache: "no-store" });
    const data = await r.json();
    if (!r.ok) throw new Error(data.error || r.statusText);
    take(data);
    // an open edit/reply box is never redrawn under the cursor
    if (!state.open.size) render(); else renderStatus();
  } catch (e) {
    el("#status").textContent = "Can't reach the notes server: is Game Notes still running? (" + e.message + ")";
  }
}

async function send(req) {
  say("Saving…");
  try {
    const r = await fetch("/api/notes", { method: "POST", headers: { "Content-Type": "application/json" },
                                          body: JSON.stringify(req) });
    const data = await r.json();
    if (!r.ok) throw new Error(data.error || r.statusText);
    take(data);
    say("Saved");
    return true;
  } catch (e) {
    say("Not saved: " + e.message, true);
    return false;
  }
}

function renderStatus() {
  const count = (s) => state.notes.filter((n) => n.status === s).length;
  const fresh = count("new"), working = count("working"), needs = count("needs_you");
  const parts = [];
  if (needs) parts.push(`${needs} need${needs === 1 ? "s" : ""} you`);
  if (working) parts.push(`${working} being worked on`);
  if (fresh) {
    const quietMin = state.ownerActivity ? (Date.now() - Date.parse(state.ownerActivity)) / 60000 : Infinity;
    const left = Math.ceil(state.idleMinutes - quietMin);
    parts.push(`${fresh} new — ` + (left > 0
      ? `Claude starts in ${left} min (${state.idleMinutes} min after your last change)`
      : "Claude can start on them now"));
  }
  el("#status").textContent = parts.length ? parts.join(" · ") : "Nothing waiting: add a note to get started.";
  const w = el("#watch");
  w.classList.toggle("on", state.watching);
  w.replaceChildren(h("span", { class: "dot", "aria-hidden": "true" }), state.watching
    ? `Claude is watching for ${state.idleMinutes} quiet minutes.`
    : "Claude isn't watching right now: your notes wait until a Claude session picks them up.");
}

function visible(n) {
  if (state.filter === "done") return n.status === "done";
  if (state.filter === "open") return n.status !== "done";
  return true;
}

function render() {
  renderStatus();
  const rank = { needs_you: 0, working: 1, new: 2, done: 3 };
  const shown = state.notes.filter(visible).sort((a, b) => rank[a.status] - rank[b.status] || b.id - a.id);
  el("#list").replaceChildren(...shown.map(card));
  const empty = el("#empty");
  empty.hidden = shown.length > 0;
  empty.textContent = state.filter === "done" ? "Nothing finished yet." : "No open notes.";
}

function card(n) {
  const li = h("li", { class: `note ${n.status}`, id: `note-${n.id}` },
    h("div", { class: "head" },
      h("span", { class: "id", text: `#${n.id}` }),
      h("span", { class: "chip cat", text: n.category }),
      h("span", { class: `chip ${n.status}`, text: STATUS_LABEL[n.status] || n.status }),
      h("span", { class: "when", text: "added " + when(n.created) })));
  n.thread.forEach((m, i) => li.append(h("p", { class: `msg ${m.who}` }, m.text,
    i ? h("span", { class: "at", text: when(m.at) }) : null)));
  li.append(actions(n));
  return li;
}

function actions(n) {
  const row = h("div", { class: "actions" });
  const mine = n.thread[n.thread.length - 1].who === "you";
  if (n.status === "working") return row;
  if (n.status === "new" && mine) row.append(h("button", { class: "btn small", text: "Edit", onclick: () => editor(n, "edit") }));
  if (n.status === "needs_you") row.append(h("button", { class: "btn small primary", text: "Answer", onclick: () => editor(n, "reply") }));
  if (n.status === "done") row.append(h("button", { class: "btn small", text: "Reopen", onclick: () => editor(n, "reopen") }));
  const del = h("button", { class: "btn small", text: "Delete" });
  del.addEventListener("click", async () => {
    if (del.dataset.armed) { await send({ action: "delete", id: n.id }); state.open.delete(n.id); render(); return; }
    del.dataset.armed = "1";
    del.textContent = "Really delete?";
    setTimeout(() => { delete del.dataset.armed; del.textContent = "Delete"; }, 4000);
  });
  row.append(del);
  return row;
}

/** Inline box under a note: edit your words, answer Claude's question, or reopen with a comment. */
function editor(n, mode) {
  const li = document.getElementById(`note-${n.id}`);
  if (!li || li.querySelector(".edit")) return;
  state.open.add(n.id);
  const last = n.thread[n.thread.length - 1];
  const ta = h("textarea", { rows: "3", maxlength: "4000", "aria-label": mode === "edit" ? "Edit note" : "Your reply",
    placeholder: mode === "reopen" ? "What still needs doing? (optional)" : "" });
  if (mode === "edit") ta.value = last.text;
  const cat = h("select", { "aria-label": "Category" });
  for (const c of state.categories) cat.append(h("option", { value: c, text: c }));
  cat.value = n.category;
  const close = () => { state.open.delete(n.id); render(); };
  const save = async () => {
    const req = mode === "edit" ? { action: "edit", id: n.id, text: ta.value, category: cat.value }
                                : { action: "reply", id: n.id, text: ta.value };
    if (await send(req)) close();
  };
  ta.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) { e.preventDefault(); save(); }
    if (e.key === "Escape") close();
  });
  const label = { edit: "Save", reply: "Send answer", reopen: "Reopen" }[mode];
  li.append(h("div", { class: "edit" }, ta, h("div", { class: "actions" },
    mode === "edit" ? cat : null,
    h("button", { class: "btn small primary", text: label, onclick: save }),
    h("button", { class: "btn small", text: "Cancel", onclick: close }))));
  ta.focus();
}

// ---- add form ---------------------------------------------------------------
const text = el("#text");
text.value = recall(DRAFT_KEY) || "";
text.addEventListener("input", () => store(DRAFT_KEY, text.value));
text.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) { e.preventDefault(); el("#add").requestSubmit(); }
});
el("#add").addEventListener("submit", async (e) => {
  e.preventDefault();
  if (!text.value.trim()) { say("Write the note first.", true); text.focus(); return; }
  if (await send({ action: "add", text: text.value, category: el("#category").value })) {
    text.value = "";
    store(DRAFT_KEY, "");
    if (state.filter === "done") setFilter("open");
    render();
    text.focus();
  }
});

// ---- filter -----------------------------------------------------------------
function setFilter(f) {
  state.filter = f;
  store(FILTER_KEY, f);
  for (const b of document.querySelectorAll(".seg button")) {
    const on = b.dataset.filter === f;
    b.classList.toggle("on", on);
    b.setAttribute("aria-pressed", String(on));
  }
  if (state.loaded) render();
}
for (const b of document.querySelectorAll(".seg button")) b.addEventListener("click", () => setFilter(b.dataset.filter));
const saved = recall(FILTER_KEY);
if (["open", "done", "all"].includes(saved)) state.filter = saved;
setFilter(state.filter);

// ---- refresh: Claude's answers show up without reloading ----------------------
load();
// a hidden tab still pings (browsers slow it to about once a minute), so the
// server's --idle-exit only stops it once the page is really closed
setInterval(() => { if (!document.hidden) load(); else fetch("/api/ping").catch(() => {}); }, POLL_MS);
setInterval(() => { if (state.loaded) renderStatus(); }, 30000);   // the countdown, between polls
document.addEventListener("visibilitychange", () => { if (!document.hidden) load(); });
