/* ==========================================================================
   Extras agent — library extras & tools
     overlays  folder-actions (sheet {path}) · paste-conflict (dialog {path, i, n})
               ex-books (popover {k}) · kosync (sheet {state}) · kosync-prompt (dialog)
               opds-book (sheet {cat, i, dl}) · ex-opds-edit (dialog) · calibre (sheet {state})
               read-timer (sheet {mode, active}) · autoturn (sheet) · profiles (sheet {id})
               news (sheet {state}) · ex-feed (dialog) · wallabag (sheet {state})
               cloud (page {acct, path}) · text-editor (page {file}) · terminal (page)
               ex-vb-word (dialog {i}) · ex-vb-settings (sheet)
     screens   bookmark-browser · vocab ({mode, i, show}) · dict-history · wiki-history
               opds ({cat, sec, page})
   Built only from shared components (ko-row / ko-group / ko-seg / ko-toggle /
   ko-slider / ko-chip) plus the Settings (mn-*, st-*) and library sheet (lba-*)
   classes, so every screen reads as the same app.
   ========================================================================== */
(function () {
  const A = App, esc = App.esc, I = App.icon;
  const G = "Library extras & tools";
  const S = (k, d) => A.get("ex." + k, d);
  const SET = (k, v) => A.set("ex." + k, v);

  /* ------------------------------------------------------------ plumbing */
  let STILL = false; // re-render without replaying the slide-in animation
  const still = () => (STILL ? " ex-still" : "");
  const redraw = () => { STILL = true; A.refresh(); STILL = false; };
  const setTopParams = (patch) => { const t = A.top(); if (!t) return; t.params = { ...t.params, ...patch }; STILL = true; A.renderLayers(true); STILL = false; A.syncHash(); };

  let PREV = null;
  const goFrom = (name, params = {}) => { if (A.current.name !== name) PREV = { name: A.current.name, params: { ...A.current.params } }; A.closeAll(); A.go(name, params); };
  const openOver = (name, params = {}) => { A.closeAll(); A.open(name, params); };
  A.action("ex-back", (el) => {
    const fb = el.dataset.arg ? JSON.parse(el.dataset.arg) : null;
    if (fb) return A.go(fb.name, fb.params || {});
    const p = PREV; PREV = null;
    if (p && p.name !== A.current.name) A.go(p.name, p.params); else A.go("library");
  });

  /* generic controls ---------------------------------------------------- */
  const tgRow = (ic, label, k, def, sub = "") => `<button class="ko-row mn-row" data-action="ex-tg" data-k="${k}" data-def="${def ? 1 : 0}">${ic ? `<span class="ko-icon-tile">${I(ic)}</span>` : ""}<span class="label"><span class="t">${label}</span>${sub ? `<span class="sub">${sub}</span>` : ""}</span>${A.toggle(S(k, def))}</button>`;
  const row = (ic, label, attrs = "", o = {}) => `<${o.div ? "div" : "button"} class="ko-row mn-row ${o.cls || ""}" ${attrs}>${ic ? `<span class="ko-icon-tile">${I(ic)}</span>` : ""}<span class="label"><span class="t">${label}</span>${o.sub ? `<span class="sub">${o.sub}</span>` : ""}</span>${o.value ? `<span class="value">${o.value}</span>` : ""}${o.tail ?? (o.chev ? I("chevron-right", "chev sm") : "")}</${o.div ? "div" : "button"}>`;
  const seg = (k, opts, def, cls = "") => { const cur = String(S(k, def)); return `<div class="ko-seg ex-seg ${cls}">${opts.map(([v, l]) => `<button class="${String(v) === cur ? "on" : ""}" data-action="ex-set" data-k="${k}" data-v="${esc(v)}">${l}</button>`).join("")}</div>`; };
  const segRow = (ic, label, k, opts, def) => `<div class="ko-row mn-row ex-segrow">${ic ? `<span class="ko-icon-tile">${I(ic)}</span>` : ""}<span class="label"><span class="t">${label}</span></span>${seg(k, opts, def)}</div>`;
  const stepRow = (ic, label, k, def, min, max, unit = "", sub = "") => `<div class="ko-row mn-row">${ic ? `<span class="ko-icon-tile">${I(ic)}</span>` : ""}<span class="label"><span class="t">${label}</span>${sub ? `<span class="sub">${sub}</span>` : ""}</span><span class="ko-stepper mn-step"><button data-action="ex-step" data-k="${k}" data-d="-1" data-min="${min}" data-max="${max}" data-def="${def}" aria-label="Decrease">${I("minus", "sm")}</button><span class="val num">${S(k, def)}${unit}</span><button data-action="ex-step" data-k="${k}" data-d="1" data-min="${min}" data-max="${max}" data-def="${def}" aria-label="Increase">${I("plus", "sm")}</button></span></div>`;
  A.action("ex-tg", (el) => { const k = el.dataset.k, on = !S(k, el.dataset.def === "1" || el.querySelector(".ko-toggle")?.classList.contains("on")); SET(k, on); el.querySelector(".ko-toggle")?.classList.toggle("on", on); if (el.dataset.redraw !== undefined) redraw(); });
  A.action("ex-set", (el) => { SET(el.dataset.k, isNaN(+el.dataset.v) ? el.dataset.v : +el.dataset.v); redraw(); });
  A.action("ex-step", (el) => { const k = el.dataset.k, v = Math.max(+el.dataset.min, Math.min(+el.dataset.max, Number(S(k, +el.dataset.def)) + Number(el.dataset.d))); SET(k, v); redraw(); });
  const fmtMin = (m) => (m >= 60 ? `${Math.floor(m / 60)} h${m % 60 ? ` ${m % 60} min` : ""}` : `${m} min`);
  const fmtSlide = (f, v) => (f === "s" ? (v >= 60 ? `${Math.floor(v / 60)} min${v % 60 ? ` ${v % 60} s` : ""}` : `${v} s`) : f === "min" ? fmtMin(v) : String(v));
  /* numeric settings: the shared slider row (label, −, slider, +, value on one line) */
  const SL = {};
  const fmtShort = (f, v) => (f === "s" ? (v >= 60 ? `${Math.floor(v / 60)}m${v % 60 ? ` ${v % 60}s` : ""}` : `${v} s`) : f === "min" ? (v >= 60 ? `${Math.floor(v / 60)}h${v % 60 ? ` ${v % 60}m` : ""}` : `${v} min`) : String(v));
  const slVal = (k, val) => { const c = SL[k]; return Math.max(c.min, Math.min(c.max, Math.round(val / c.step) * c.step)); };
  const showSl = (k, val) => document.querySelectorAll(`.ko-sr[data-id="${k}"] .val`).forEach((n) => (n.textContent = fmtShort(SL[k].fmt, val)));
  A.action("ex-sr", (s, v, end) => { const k = s.dataset.id, c = SL[k], val = slVal(k, c.min + v * (c.max - c.min)); showSl(k, val); if (end) { SET(k, val); redraw(); } });
  A.action("ex-sr-step", (el) => { const k = el.dataset.id, c = SL[k]; SET(k, slVal(k, Number(S(k, c.def)) + Number(el.dataset.dir) * c.step)); redraw(); });
  const slideRow = (lbl, k, def, min, max, fmt, step = 1, icon = "") => {
    SL[k] = { def, min, max, fmt, step };
    const v = S(k, def), pct = ((v - min) / (max - min)) * 100;
    return `<div class="ex-sr">${A.sliderRow({ label: lbl, icon, pct, value: fmtShort(fmt, v), slide: "ex-sr", step: "ex-sr-step", id: k })}</div>`;
  };
  const clockIn = (min) => { const t = new Date(Date.now() + min * 60000); return String(t.getHours()).padStart(2, "0") + ":" + String(t.getMinutes()).padStart(2, "0"); };

  /* shared shells -------------------------------------------------------- */
  const sheetHead = (ic, title, sub = "", right = "", back = "") => `<div class="grip"></div><div class="ko-sheet-head ex-sh">${back}<span class="ko-icon-tile ex-sh-ico">${I(ic)}</span><div class="grow ex-sh-t"><div class="title">${title}</div>${sub ? `<div class="ex-sh-sub">${sub}</div>` : ""}</div>${right}<button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button></div>`;
  const sheet = (cls, head, body, foot = "") => `<div class="ko-sheet ex-sheet ${cls}${still()}">${head}<div class="ko-scroll ex-sbody">${body}<div class="ex-end"></div></div>${foot ? `<div class="ex-sfoot">${foot}</div>` : ""}</div>`;
  const label = (t) => `<div class="ko-section-label ex-label">${t}</div>`;
  const group = (rows, cls = "") => `<div class="ko-group mn-group ex-group ${cls}">${rows}</div>`;
  /** full screen with the Settings-style header */
  const screen = (o) => `<div class="ko-view ex-view ${o.cls || ""}">${A.statusBar({ left: o.status || o.title })}
    <header class="ko-header ko-header--page ex-head"><button class="ko-icon-btn mn-back" data-action="ex-back" ${o.backTo ? `data-arg="${A.attrs(o.backTo)}"` : ""} aria-label="Back">${I("arrow-left")}</button>
      <div class="grow"><div class="ko-crumbs">${o.crumb ? `<span>${o.crumb}</span>` : ""}</div><div class="ko-page-title ex-title">${o.title}</div></div>${o.actions || ""}</header>
    ${o.sub || ""}<div class="ko-scroll ex-body">${o.body}<div class="ex-end"></div></div>${o.foot || ""}</div>`;
  const tiny = (b) => `<span class="ex-tcov">${Cover.html(b)}</span>`;
  const short = (b) => b.title.replace(/\s*\(.*\)$/, "");
  const spinner = () => `<span class="ex-spin">${I("loader-circle", "sm ko-spin")}</span>`;
  const field = (ic, ph, val, type = "text") => `<label class="ko-input ex-field">${I(ic, "sm")}<input type="${type}" placeholder="${ph}" value="${esc(val)}" autocomplete="off"></label>`;

  /* =====================================================================
     1 · FOLDER LONG-PRESS
     ===================================================================== */
  let FCLIP = null;
  const nameOf = (path) => path.split("/").pop() || "onboard";
  const folderInfo = (path) => {
    const name = nameOf(path);
    const books = DB.BOOKS.filter((b) => b.folder === name);
    const f = DB.FOLDERS.find((x) => x.name === name);
    const n = path === "Books" ? 28 : path === "" ? 5 : books.length || (f ? f.count : 6);
    const mb = books.length ? books.reduce((s, b) => s + parseFloat(b.size), 0) : n * 2.3;
    return { name, books, n, size: mb.toFixed(1) + " MB", modified: f ? f.modified : "yesterday", reading: books.filter((b) => b.status === "reading").length, finished: books.filter((b) => b.status === "finished").length };
  };
  const SHORTS = () => A.get("lib.shortcuts", ["Books", "Books/Classics", "Downloads", "Books/عربي"]);
  A.overlay("folder-actions", {
    layer: "sheet",
    render(p) {
      const path = String(p.path ?? "Books/Classics"), F = folderInfo(path);
      const inSc = SHORTS().includes(path), isHome = path === "Books";
      const tool = (ic, l, attrs, cls = "") => UI.tool({ icon: ic, html: l, attrs, size: "lg", danger: cls === "danger", cls: cls === "danger" ? "" : cls });
      const arg = esc(path);
      return `<div class="ko-sheet lba ex-sheet ex-fa${still()}">
        <div class="grip"></div>
        <div class="ko-sheet-head lba-head">
          <span class="ex-fa-ico">${I("folder")}</span>
          <div class="grow"><div class="title ellipsis"><span dir="auto">${esc(F.name)}</span>${isHome ? `<span class="lb-home">${I("house", "sm")}HOME</span>` : ""}</div>
            <div class="sub ellipsis" dir="ltr">/mnt/onboard/${esc(path)}</div>
            <div class="sub">${F.n} item${F.n === 1 ? "" : "s"} · ${F.size} · modified ${esc(F.modified)}</div></div>
          <button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button>
        </div>
        <div class="ko-scroll">
          <div class="lba-tools">
            ${tool("copy", "Copy", `data-action="ex-fclip" data-arg="copy|${arg}"`)}
            ${tool("scissors", "Cut", `data-action="ex-fclip" data-arg="cut|${arg}"`)}
            ${tool("clipboard-paste", "Paste", `data-action="ex-fpaste" data-arg="${arg}"`)}
            ${tool("square-check", "Select", `data-action="ex-fselect" data-arg="${arg}"`)}
            ${tool("pencil-line", "Rename", `data-action="ex-frename" data-arg="${arg}"`)}
            ${tool("trash-2", "Delete", `data-action="ex-fdelete" data-arg="${arg}"`, "danger")}
          </div>
          ${FCLIP ? `<div class="ex-clipnote">${I("clipboard", "sm")}<span class="grow ellipsis">Clipboard: <b dir="auto">${esc(FCLIP.name)}</b> · ${FCLIP.op === "cut" ? "cut" : "copied"}</span><button class="ko-btn ko-btn--ghost" data-action="ex-fclear">Clear</button></div>` : ""}
          <div class="ko-section-label">Folder</div>
          <div class="ko-group">
            ${row("folder-open", "Open folder in file browser", `data-action="ex-fopen" data-arg="${arg}"`, { chev: true })}
            ${row("house", "Set as HOME folder", isHome ? "" : `data-action="ex-fhome" data-arg="${arg}"`, { value: isHome ? "Current HOME" : "", cls: isHome ? "disabled" : "" })}
            ${row(inSc ? "bookmark-minus" : "bookmark-plus", inSc ? "Remove from folder shortcuts" : "Add to folder shortcuts", `data-action="ex-fshort" data-arg="${arg}"`, { value: inSc ? "In shortcuts" : "" })}
            ${row("folder-plus", "New folder inside", `data-action="ex-fnew" data-arg="${arg}"`)}
          </div>
          <div class="ko-section-label">Contents</div>
          <div class="ko-group">
            ${row("info", "Folder information", `data-action="ex-finfo" data-arg="${arg}"`, { chev: true })}
            ${row("shuffle", "Open random document here", `data-action="ex-frandom" data-arg="${arg}"`)}
            ${row("database-zap", "Extract and cache book information", `data-action="ex-fcache" data-arg="${arg}"`, { value: `${F.n} files` })}
          </div>
          <div class="ex-end"></div>
        </div>
      </div>`;
    },
  });
  const argOf = (el) => el.dataset.arg || "";
  A.action("ex-fclip", (el) => { const [op, path] = argOf(el).split("|"); FCLIP = { op, path, name: nameOf(path) }; A.closeAll(); A.toast(`${op === "cut" ? "Cut" : "Copied"} “${nameOf(path)}” · open a folder and Paste`); });
  A.action("ex-fclear", () => { FCLIP = null; redraw(); });
  A.action("ex-fpaste", (el) => A.replaceTop("paste-conflict", { path: argOf(el), i: 1, n: 3 }));
  A.action("ex-fselect", () => { A.closeAll(); const fn = A.actions["lib-select-start"]; if (fn) fn({ dataset: {} }); else A.toast("Select mode"); });
  A.action("ex-frename", (el) => A.replaceTop("input", { title: "Rename folder", hint: "Folder name", value: nameOf(argOf(el)), ok: "Rename", action: "ex-done", desc: "Books inside keep their reading progress, highlights and bookmarks." }));
  A.action("ex-fdelete", (el) => { const F = folderInfo(argOf(el)); A.replaceTop("confirm", { title: `Delete “${F.name}”?`, body: `The folder and its ${F.n} item${F.n === 1 ? "" : "s"} (${F.size}) will be permanently deleted, with their reading progress, highlights and bookmarks.`, ok: "Delete folder", danger: true, action: "ex-done" }); });
  A.action("ex-done", (el, v) => { A.closeAll(); A.toast(typeof v === "string" && v ? `Saved · ${v}` : "Done"); });
  A.action("ex-fopen", (el) => { A.closeAll(); A.go("folder", { path: argOf(el) }); });
  A.action("ex-fhome", (el) => { A.closeAll(); A.toast(`HOME folder set to /mnt/onboard/${argOf(el)}`); });
  A.action("ex-fshort", (el) => {
    const p = argOf(el), s = SHORTS(), on = s.includes(p);
    A.set("lib.shortcuts", on ? s.filter((x) => x !== p) : [...s, p]);
    A.closeAll(); A.refresh(); A.toast(`“${nameOf(p)}” ${on ? "removed from" : "added to"} folder shortcuts`);
  });
  A.action("ex-fnew", () => A.replaceTop("input", { title: "New folder", hint: "Folder name", value: "", ok: "Create", action: "ex-done", checkbox: "Enter folder after creation", checked: true }));
  A.action("ex-finfo", (el) => {
    const path = argOf(el), F = folderInfo(path);
    A.replaceTop("info", { title: F.name, icon: "folder", list: [["Path", "/mnt/onboard/" + path], ["Items", `${F.n}`], ["Size", F.size], ["Modified", F.modified], ["Reading", `${F.reading} book${F.reading === 1 ? "" : "s"}`], ["Finished", `${F.finished} book${F.finished === 1 ? "" : "s"}`]] });
  });
  A.action("ex-frandom", (el) => { const F = folderInfo(argOf(el)); const pool = F.books.length ? F.books : DB.BOOKS; A.closeAll(); A.open("book-details", { id: pool[Math.floor(Math.random() * pool.length)].id }); });
  A.action("ex-fcache", (el) => { A.closeAll(); A.toast(`Caching book information · ${folderInfo(argOf(el)).n} files`); });

  /* long-press on folder rows (contextmenu or 600 ms hold) */
  let fHold = null, fHeld = false;
  document.addEventListener("contextmenu", (ev) => {
    const el = ev.target.closest("[data-folder]"); if (!el || !el.closest(".ko-screen")) return;
    ev.preventDefault(); clearTimeout(fHold); A.open("folder-actions", { path: el.dataset.folder });
  });
  document.addEventListener("pointerdown", (ev) => {
    const el = ev.target.closest("[data-folder]"); if (!el || ev.button !== 0 || !el.closest(".ko-screen") || ev.target.closest(".lb-more")) return;
    fHeld = false; clearTimeout(fHold);
    fHold = setTimeout(() => { fHeld = true; A.open("folder-actions", { path: el.dataset.folder }); }, 600);
  });
  ["pointerup", "pointercancel"].forEach((t) => document.addEventListener(t, () => clearTimeout(fHold)));
  document.addEventListener("click", (ev) => { if (fHeld) { fHeld = false; ev.stopPropagation(); ev.preventDefault(); } }, true);

  /* =====================================================================
     2 · PASTE CONFLICT
     ===================================================================== */
  const CONFLICTS = [
    { id: "animal-farm", a: { size: "0.3 MB", date: "3 Nov 2026, 10:12" }, b: { size: "0.4 MB", date: "18 Nov 2026, 21:40" }, newer: "b", larger: "b" },
    { id: "frankenstein", a: { size: "3.9 MB", date: "12 Oct 2026, 08:03" }, b: { size: "3.9 MB", date: "12 Oct 2026, 08:03" }, newer: "", larger: "" },
    { id: "kafka", a: { size: "1.1 MB", date: "16 Nov 2026, 19:55" }, b: { size: "0.9 MB", date: "2 Mar 2025, 14:20" }, newer: "a", larger: "a" },
  ];
  A.overlay("paste-conflict", {
    layer: "dialog",
    render(p) {
      const n = +p.n || 3, i = Math.max(1, Math.min(n, +p.i || 1)), c = CONFLICTS[(i - 1) % 3], b = DB.book(c.id);
      const dest = nameOf(String(p.path ?? "Books/Classics"));
      const file = short(b) + "." + b.format;
      const col = (k, head) => {
        const f = c[k], tags = [c.newer === k ? "Newer" : "", c.larger === k ? "Larger" : ""].filter(Boolean);
        return `<div class="ex-cmp-col">
          <div class="ex-cmp-h">${I(k === "a" ? "file" : "clipboard-paste", "sm")}<span>${head}</span></div>
          <div class="ex-tags">${tags.length ? tags.map((t) => `<span class="ko-pill ko-pill--tint ex-tag">${t}</span>`).join("") : `<span class="ko-pill ex-tag">${c.newer ? "Older" : "Identical"}</span>`}</div>
          <dl class="ex-cmp-dl"><div><dt>Size</dt><dd class="num">${f.size}</dd></div><div><dt>Modified</dt><dd class="num">${f.date}</dd></div><div><dt>Progress</dt><dd>${k === "a" ? (b.progress ? b.progress + "% · 2 notes" : "Not opened") : "Not opened"}</dd></div></dl></div>`;
      };
      const all = S("pc.all", false);
      return `<div class="ko-dialog ex-pc${still()}" role="dialog">
        <div class="ex-pc-top"><div class="ko-dialog-title">File already exists</div><span class="ex-pc-n num">${i} of ${n}</span></div>
        <div class="ko-dialog-body">A file named <b dir="auto">${esc(file)}</b> already exists in <b dir="auto">${esc(dest)}</b>.</div>
        <div class="ex-cmp-file">${tiny(b)}<div class="grow"><div class="ex-cmp-n ellipsis" dir="auto">${esc(file)}</div><div class="ex-cmp-s ellipsis">${esc(b.author.split(";")[0])} · ${b.format.toUpperCase()}</div></div></div>
        <div class="ex-cmp">${col("a", "Existing")}${col("b", "Pasting")}</div>
        <button class="ko-check-row" data-action="ex-pc-all">${A.check(all)}<span>Apply to all ${n} conflicts</span></button>
        <div class="kb-field-help">${I("info", "sm")}<span>Rename keeps both: the pasted copy becomes “${esc(file.replace(/(\.\w+)$/, " (2)$1"))}”.</span></div>
        <div class="ko-dialog-actions ex-pc-act">
          <button class="ko-btn ko-btn--ghost" data-action="ex-pc" data-arg="skip">Skip</button>
          <button class="ko-btn ko-btn--ghost" data-action="ex-pc" data-arg="rename">Rename</button>
          <button class="ko-btn ko-btn--primary" data-action="ex-pc" data-arg="overwrite">Overwrite</button>
        </div>
      </div>`;
    },
  });
  A.action("ex-pc-all", () => { SET("pc.all", !S("pc.all", false)); redraw(); });
  A.action("ex-pc", (el) => {
    const p = A.top().params, i = +p.i || 1, n = +p.n || 3, verb = { skip: "Skipped", rename: "Kept both", overwrite: "Overwritten" }[el.dataset.arg];
    if (!S("pc.all", false) && i < n) { setTopParams({ i: i + 1 }); A.toast(`${verb} · ${n - i} conflict${n - i > 1 ? "s" : ""} left`); return; }
    A.closeAll(); A.toast(S("pc.all", false) ? `${verb} · applied to all ${n} files` : `${verb} · paste finished`);
  });

  /* =====================================================================
     3 · BOOKMARK BROWSER
     ===================================================================== */
  const snip = (id, n) => TextGen.paragraph(id + ":bm" + n).split(". ").slice(0, 2).join(". ").replace(/\.?$/, ".");
  const ANN = [
    ["animal-farm", "highlight", "lighten", "yellow", "Chapter I", 4, "Man is the only creature that consumes without producing.", "", "Nov 18", 1],
    ["animal-farm", "note", "lighten", "yellow", "Chapter II", 15, "The animals were happy as they had never conceived it possible to be.", "Irony starts here — compare with the ending.", "Nov 18", 2],
    ["animal-farm", "bookmark", "", "", "Chapter III", 22, "", "", "Nov 17", 3],
    ["animal-farm", "highlight", "underscore", "gray", "Chapter III", 24, "All animals are equal.", "", "Nov 17", 4],
    ["meditations", "highlight", "lighten", "green", "Book IV", 61, "Very little is needed to make a happy life; it is all within yourself, in your way of thinking.", "", "Nov 12", 5],
    ["meditations", "note", "lighten", "blue", "Book II", 22, "Begin the morning by saying to thyself, I shall meet with the busybody, the ungrateful, arrogant, deceitful.", "Morning routine — read before work.", "Nov 10", 6],
    ["meditations", "bookmark", "", "", "Book V", 79, "", "", "Nov 9", 7],
    ["frankenstein", "highlight", "lighten", "yellow", "Letter 4", 22, "Nothing is so painful to the human mind as a great and sudden change.", "", "Nov 2", 8],
    ["frankenstein", "highlight", "lighten", "red", "Chapter 10", 118, "Beware; for I am fearless, and therefore powerful.", "", "Nov 4", 9],
    ["frankenstein", "note", "strikeout", "gray", "Chapter 5", 61, "I had desired it with an ardour that far exceeded moderation.", "Victor's obsession — essay quote.", "Nov 3", 10],
    ["siddhartha", "note", "lighten", "purple", "The River", 103, "Wisdom cannot be imparted. Wisdom that a wise man attempts to impart always sounds like foolishness.", "Re-read before the book club.", "Oct 28", 11],
    ["siddhartha", "highlight", "lighten", "green", "Om", 121, "The river is everywhere at once.", "", "Oct 29", 12],
    ["pride", "highlight", "lighten", "yellow", "Chapter 1", 1, "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.", "", "Oct 21", 13],
    ["pride", "bookmark", "", "", "Chapter 34", 187, "", "", "Oct 24", 14],
    ["pride", "highlight", "invert", "gray", "Chapter 11", 54, "I declare after all there is no enjoyment like reading!", "", "Oct 22", 15],
    ["sherlock-2", "note", "lighten", "blue", "Chapter 1", 6, "When you have eliminated the impossible, whatever remains, however improbable, must be the truth.", "The method, stated outright.", "Oct 18", 16],
    ["sherlock-2", "bookmark", "", "", "Chapter 6", 58, "", "", "Oct 19", 17],
    ["moby", "highlight", "lighten", "blue", "Loomings", 1, "Call me Ishmael.", "", "Sep 30", 18],
    ["moby", "highlight", "underscore", "gray", "The Chapel", 41, "Methinks my body is but the lees of my better being.", "", "Oct 2", 19],
    ["ar-poems", "highlight", "lighten", "yellow", "القصيدة الأولى", 12, "الخيل والليل والبيداء تعرفني", "", "Oct 14", 20],
  ].map(([book, type, style, color, ch, page, text, note, date, n]) => ({ book, type, style, color, ch, page, text: type === "bookmark" ? snip(book, n) : text, note, date, n }));
  const STYLE_N = { lighten: "Highlight", underscore: "Underline", strikeout: "Strikeout", invert: "Invert" };
  const COLORS = ["yellow", "green", "blue", "red", "purple", "gray"];
  const cap = (s) => s[0].toUpperCase() + s.slice(1);
  let bbQ = "";
  const bbList = () => {
    const t = S("bb.type", "all"), c = S("bb.color", "all"), bk = S("bb.book", "all"), q = bbQ.toLowerCase();
    return ANN.filter((a) => (t === "all" || a.type === t) && (c === "all" || a.color === c) && (bk === "all" || a.book === bk)
      && (!q || (a.text + " " + a.note + " " + DB.book(a.book).title).toLowerCase().includes(q)));
  };
  const markQ = (s) => { const e = esc(s); if (!bbQ) return e; const re = new RegExp("(" + esc(bbQ).replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")", "ig"); return e.replace(re, '<b class="ex-hit">$1</b>'); };
  const annCard = (a, withBook) => {
    const b = DB.book(a.book), ar = b.lang === "ar";
    const bk = withBook ? `<b dir="auto">${esc(short(b))}</b> · ` : "";
    if (a.type === "bookmark") return `<button class="rd-ann ex-ann bm" data-action="ex-open-book" data-arg="${a.book}">
        <span class="ex-rib">${I("bookmark", "sm")}</span>
        <span class="txt"><span class="q ex-snip ${ar ? "ar" : ""}">${markQ(a.text)}</span><span class="meta">${bk}Bookmark · ${esc(a.ch)} · p. ${a.page} · ${a.date}</span></span></button>`;
    return `<button class="rd-ann ex-ann" data-action="ex-open-book" data-arg="${a.book}">
        <span class="sw s-${a.style} c-${a.color}"></span>
        <span class="txt"><span class="q ${ar ? "ar" : ""}"><mark class="hl s-${a.style} c-${a.color}">${markQ(a.text)}</mark></span>
        ${a.note ? `<span class="note">${I("pen-line", "sm")}<span>${markQ(a.note)}</span></span>` : ""}
        <span class="meta">${bk}${a.type === "note" ? "Note" : STYLE_N[a.style]}${a.style === "lighten" ? ` · ${cap(a.color)}` : ""} · <span dir="auto">${esc(a.ch)}</span> · p. ${a.page} · ${a.date}</span></span></button>`;
  };
  const bbResults = () => {
    const list = bbList();
    if (!list.length) return `<div class="ko-empty">${I("bookmark-x")}<div>Nothing matches</div><div class="faint">Try another type, colour or book, or clear the search.</div><button class="ko-btn" data-action="ex-bb-reset">Clear filters</button></div>`;
    if (S("bb.sort", "book") === "date") return `<div class="rd-anns ex-anns ex-flat">${list.slice().sort((a, b) => a.n - b.n).map((a) => annCard(a, true)).join("")}</div>`;
    const books = [...new Set(list.map((a) => a.book))];
    return books.map((id) => {
      const b = DB.book(id), its = list.filter((a) => a.book === id);
      return `<section class="ex-bk"><div class="ex-bk-h">${tiny(b)}<div class="grow"><div class="ex-bk-t ellipsis" dir="auto">${esc(short(b))}</div><div class="ex-bk-s ellipsis"><span dir="auto">${esc(b.author.split(";")[0])}</span> · ${its.length} item${its.length > 1 ? "s" : ""}</div></div>
        <button class="ko-btn ko-btn--ghost ex-bk-open" data-action="ex-open-book" data-arg="${id}">${I("book-open", "sm")}Open</button></div>
        <div class="rd-anns ex-anns">${its.map((a) => annCard(a)).join("")}</div></section>`;
    }).join("");
  };
  const bookChip = (k, lbl) => { const bk = S(k, "all"); return `<button class="ko-chip ex-bookchip ${bk !== "all" ? "on" : ""}" data-open="ex-books" data-params="${A.attrs({ k })}">${I("book", "sm")}<span class="ellipsis" dir="auto">${bk === "all" ? lbl : esc(short(DB.book(bk)))}</span>${I("chevron-down", "sm")}</button>`; };
  const bbCount = () => { const l = bbList(), nb = new Set(l.map((a) => a.book)).size; return `${l.length} item${l.length === 1 ? "" : "s"} · ${nb} book${nb === 1 ? "" : "s"}`; };
  A.screen("bookmark-browser", {
    render() {
      const t = S("bb.type", "all"), c = S("bb.color", "all");
      const n = (k) => ANN.filter((a) => k === "all" || a.type === k).length;
      const types = [["all", "All"], ["highlight", "Highlights"], ["note", "Notes"], ["bookmark", "Bookmarks"]];
      const chips = types.map(([k, l]) => `<button class="ko-chip ${t === k ? "on" : ""}" data-action="ex-set" data-k="bb.type" data-v="${k}">${l}<span class="ex-cn num">${n(k)}</span></button>`).join("");
      const dots = [["all", "Any colour"]].concat(COLORS.map((x) => [x, cap(x)])).map(([k, l]) => `<button class="ko-chip ex-cchip ${c === k ? "on" : ""}" data-action="ex-set" data-k="bb.color" data-v="${k}">${k === "all" ? I("palette", "sm") : `<span class="rd-ann ex-dot"><span class="sw s-lighten c-${k}"></span></span>`}${l}</button>`).join("");
      const sub = `<div class="ex-search"><label class="ko-input ko-input--card">${I("search", "sm")}<input type="search" id="ex-bb-q" placeholder="Search highlights, notes and books" value="${esc(bbQ)}" autocomplete="off"></label></div>
        <div class="ex-chips">${bookChip("bb.book", "All books")}<span class="ex-vsep"></span>${chips}</div>
        <div class="ex-chips ex-chips2">${dots}</div>`;
      const foot = `<div class="ko-pager ex-foot"><span class="num ellipsis" id="ex-bb-n">${bbCount()}</span><span class="grow"></span>${seg("bb.sort", [["book", "By book"], ["date", "By date"]], "book")}<button class="ko-btn ex-exp" data-action="ex-bb-export">${I("share", "sm")}Export</button></div>`;
      return screen({ title: "Bookmark browser", crumb: "Library", status: "Bookmarks", sub, body: `<div id="ex-bb-res">${bbResults()}</div>`, foot, cls: "ex-bb" });
    },
    mount(root) {
      const inp = root.querySelector("#ex-bb-q"); if (!inp) return;
      inp.addEventListener("input", () => { bbQ = inp.value.trim(); root.querySelector("#ex-bb-res").innerHTML = bbResults(); root.querySelector("#ex-bb-n").textContent = bbCount(); A.icons(); });
    },
  });
  A.action("ex-bb-reset", () => { ["bb.type", "bb.color", "bb.book"].forEach((k) => SET(k, "all")); bbQ = ""; redraw(); });
  A.action("ex-bb-export", () => { const l = bbList(); A.open("info", { title: "Export annotations", icon: "share", body: `${l.length} items from ${new Set(l.map((a) => a.book)).size} books, using the formats chosen in Tools › Export highlights.`, list: [["Formats", "Markdown, JSON"], ["Folder", "/mnt/onboard/clipboard"]], ok: "Export" }); });
  A.action("ex-open-book", (el) => { A.closeAll(); A.go("reader", { id: el.dataset.arg }); });

  /* book picker popover shared by bookmark browser and vocabulary builder */
  A.overlay("ex-books", {
    layer: "popover", clear: true,
    render(p) {
      const k = p.k || "bb.book", src = k.startsWith("vb") ? VOCAB : ANN, cur = S(k, "all");
      const ids = [...new Set(src.map((a) => a.book))];
      const top = k.startsWith("vb") ? 236 : 186;
      const r = (id, l, n, cov = "") => `<button class="ko-row ex-pick ${cur === id ? "on" : ""}" data-action="ex-pick" data-k="${k}" data-v="${id}">${A.radio(cur === id)}${cov}<span class="label ellipsis" dir="auto">${l}</span><span class="value num">${n}</span></button>`;
      return `<div class="ko-popover ex-pop" style="top:${top}px;left:16px;width:300px">
        <div class="ko-section-label">Show items from</div>
        ${r("all", "All books", src.length)}
        ${ids.map((id) => r(id, esc(short(DB.book(id))), src.filter((a) => a.book === id).length, tiny(DB.book(id)))).join("")}
      </div>`;
    },
  });
  A.action("ex-pick", (el) => { SET(el.dataset.k, el.dataset.v); A.close(); redraw(); });

  /* =====================================================================
     4 · VOCABULARY BUILDER
     ===================================================================== */
  const VOCAB = [
    ["conceived", "verb", "animal-farm", "The animals were happy as they had never conceived it possible to be.", "to form or devise a plan or idea in the mind; to imagine", "due", "now", 1, "Nov 18"],
    ["tyranny", "noun", "animal-farm", "All the evils of this life of ours spring from the tyranny of human beings.", "cruel and oppressive government or rule", "due", "now", 2, "Nov 18"],
    ["ardour", "noun", "frankenstein", "I had desired it with an ardour that far exceeded moderation.", "great enthusiasm or passion", "due", "now", 0, "Nov 3"],
    ["lees", "noun", "moby", "Methinks my body is but the lees of my better being.", "the sediment of wine in the barrel; the worst part of something", "due", "now", 1, "Oct 2"],
    ["busybody", "noun", "meditations", "I shall meet with the busybody, the ungrateful, arrogant, deceitful.", "a meddling or prying person", "due", "now", 3, "Nov 10"],
    ["improbable", "adjective", "sherlock-2", "Whatever remains, however improbable, must be the truth.", "not likely to be true or to happen", "due", "now", 0, "Oct 18"],
    ["countenance", "noun", "pride", "Her countenance betrayed nothing of the agitation within.", "a person's face or facial expression", "due", "now", 2, "Oct 22"],
    ["impart", "verb", "siddhartha", "Wisdom that a wise man attempts to impart always sounds like foolishness.", "to make information known; to communicate", "learning", "in 2 days", 3, "Oct 28"],
    ["moderation", "noun", "frankenstein", "An ardour that far exceeded moderation.", "the avoidance of excess or extremes", "learning", "tomorrow", 1, "Nov 3"],
    ["acknowledged", "adjective", "pride", "It is a truth universally acknowledged.", "recognized as being true or valid", "learning", "in 5 days", 4, "Oct 21"],
    ["loomings", "noun", "moby", "Chapter 1. Loomings.", "things that appear indistinctly, often threateningly", "learning", "in 3 days", 2, "Sep 30"],
    ["fearless", "adjective", "frankenstein", "Beware; for I am fearless, and therefore powerful.", "lacking fear; bold", "learned", "learned", 6, "Nov 4"],
    ["comrade", "noun", "animal-farm", "Now, comrades, what is the nature of this life of ours?", "a companion who shares one's activities", "learned", "learned", 7, "Nov 17"],
    ["imparted", "verb", "siddhartha", "Wisdom cannot be imparted.", "past tense of impart: communicated", "learned", "learned", 6, "Oct 28"],
  ].map(([w, pos, book, ctx, def, state, next, streak, added], i) => ({ w, pos, book, ctx, def, state, next, streak, added, i }));
  const vState = (v) => S("vb.s." + v.i, v.state);
  const ctxHTML = (v, blank) => esc(v.ctx).replace(new RegExp("\\b(" + v.w + "s?)\\b", "i"), blank ? '<span class="ex-blank">$1</span>' : "<b>$1</b>");
  const vList = () => {
    const f = S("vb.f", "due"), bk = S("vb.book", "all"), so = S("vb.sort", "due");
    const l = VOCAB.filter((v) => (bk === "all" || v.book === bk) && (f === "all" || vState(v) === f));
    const rank = { due: 0, learning: 1, learned: 2 };
    return so === "az" ? l.slice().sort((a, b) => a.w.localeCompare(b.w)) : so === "new" ? l.slice().reverse() : l.slice().sort((a, b) => rank[vState(a)] - rank[vState(b)]);
  };
  const statusPill = (v) => { const s = vState(v); return s === "due" ? `<span class="lb-pill new">Due</span>` : s === "learned" ? `<span class="ex-st">${I("circle-check", "sm")}Learned</span>` : `<span class="ex-st">${I("clock", "sm")}${esc(S("vb.n." + v.i, v.next))}</span>`; };
  const vocabRow = (v) => {
    const b = DB.book(v.book), s = vState(v);
    return `<div class="ex-word ${s}">
      <div class="ex-word-top"><button class="ex-w" data-action="ex-vb-lookup" data-arg="${v.i}">${esc(v.w)}</button><span class="ex-pos">${v.pos}</span><span class="grow"></span>${statusPill(v)}</div>
      <div class="ex-ctx" dir="auto">${ctxHTML(v)}</div>
      <div class="ex-word-foot"><span class="ex-wmeta">${tiny(b)}<span class="ellipsis" dir="auto">${esc(short(b))} · ${v.added} · ${v.streak}× right</span></span>
        ${s === "due" ? `<span class="ex-wbtns"><button class="ko-btn ko-btn--ghost" data-action="ex-vb-ans" data-arg="${v.i}|forgot">${I("rotate-ccw", "sm")}Forgot</button><button class="ko-btn" data-action="ex-vb-ans" data-arg="${v.i}|got">${I("check", "sm")}Got it</button></span>`
          : `<button class="ko-icon-btn lb-more" data-open="ex-vb-word" data-params="${A.attrs({ i: v.i })}" aria-label="Word options">${I("ellipsis-vertical", "sm")}</button>`}</div>
    </div>`;
  };
  const QUEUE = () => VOCAB.filter((v) => v.state === "due");
  function vocabReview(p) {
    const queue = QUEUE(), i = Math.max(0, Math.min(queue.length - 1, +p.i || 0)), v = queue[i], b = DB.book(v.book), show = String(p.show) === "1";
    return `<div class="ko-view ex-view ex-review">${A.statusBar({ left: "Vocabulary" })}
      <header class="ko-header ko-header--page ex-head ex-rv-head"><button class="ko-icon-btn mn-back" data-go="vocab" aria-label="Close review">${I("x")}</button>
        <div class="grow"><div class="ko-crumbs"><span>Vocabulary builder</span></div><div class="ex-rv-t"><span>Review</span><span class="num faint">${i + 1} of ${queue.length}</span></div>${A.progress(((i + (show ? 0.5 : 0)) / queue.length) * 100, "ko-progress--thin")}</div>
        <button class="ko-icon-btn" data-action="ex-vb-lookup" data-arg="${v.i}" aria-label="Look up in dictionary">${I("book-a")}</button></header>
      <div class="ko-scroll ex-body"><div class="ko-card ex-card">
        <div class="ex-card-src">${tiny(b)}<span class="ellipsis" dir="auto">${esc(short(b))}</span><span class="faint">· looked up ${v.added}</span></div>
        <div class="ex-card-w">${esc(v.w)}</div><div class="ex-card-pos">${v.pos}</div>
        <div class="ex-card-ctx" dir="auto">“${ctxHTML(v, !show)}”</div>
        ${show ? `<div class="ex-card-def"><div class="ex-card-dn">${I("book-a", "sm")}${esc(DB.DICTIONARIES[0])}</div><div class="ex-def">${esc(v.def)}</div></div>`
          : `<button class="ko-btn ko-btn--block ex-show" data-go="vocab" data-params="${A.attrs({ mode: "review", i, show: 1 })}">${I("eye", "sm")}Show meaning</button>`}
      </div>
      <div class="ex-rv-hint faint">${I("calendar-clock", "sm")}Got it: next review ${v.streak >= 2 ? "in 6 days" : "in 2 days"} · Forgot: tomorrow</div></div>
      <div class="ex-rv-act"><button class="ko-btn ex-rv-b" data-action="ex-vb-rv" data-arg="${i}|forgot">${I("rotate-ccw", "sm")}Forgot</button><button class="ko-btn ko-btn--primary ex-rv-b" data-action="ex-vb-rv" data-arg="${i}|got">${I("check", "sm")}Got it</button></div>
    </div>`;
  }
  A.screen("vocab", {
    render(p) {
      if (p.mode === "review") return vocabReview(p);
      const f = S("vb.f", "due"), cnt = (s) => VOCAB.filter((v) => s === "all" || vState(v) === s).length;
      const due = cnt("due");
      const tabs = `<nav class="ko-tabs ex-tabs">${[["due", "Due"], ["learning", "Learning"], ["learned", "Learned"], ["all", "All"]].map(([k, l]) => `<button class="ko-tab ${f === k ? "on" : ""}" data-action="ex-set" data-k="vb.f" data-v="${k}">${l}<span class="ex-cn num">${cnt(k)}</span></button>`).join("")}</nav>`;
      const hero = `<div class="ko-card ex-vhero"><div class="grow"><div class="ex-vh-t">${due ? `${due} word${due > 1 ? "s" : ""} to review today` : "All caught up"}</div>
          <div class="ex-vh-s">${VOCAB.length} words · ${cnt("learning")} learning · ${cnt("learned")} learned</div>
          <div class="ex-vh-bar">${A.progress((cnt("learned") / VOCAB.length) * 100)}</div></div>
          <button class="ko-btn ko-btn--primary" ${due ? `data-go="vocab" data-params="${A.attrs({ mode: "review", i: 0 })}"` : "disabled"}>${I("play", "sm")}Start review</button></div>`;
      const list = vList();
      const body = hero + `<div class="ex-chips ex-vchips">${bookChip("vb.book", "All books")}<span class="grow"></span>${seg("vb.sort", [["due", "Due first"], ["az", "A–Z"], ["new", "Newest"]], "due")}</div>`
        + (list.length ? `<div class="ex-words">${list.map(vocabRow).join("")}</div>` : `<div class="ko-empty">${I("graduation-cap")}<div>No words here</div><div class="faint">Words you look up in the dictionary while reading are added automatically.</div></div>`);
      const actions = `<button class="ko-icon-btn" data-open="ex-vb-settings" aria-label="Vocabulary settings">${I("settings-2")}</button>`;
      return screen({ title: "Vocabulary builder", crumb: "Search", status: "Vocabulary", sub: tabs, body, actions, cls: "ex-vb" });
    },
  });
  A.action("ex-vb-ans", (el) => {
    const [i, a] = el.dataset.arg.split("|");
    SET("vb.s." + i, "learning"); SET("vb.n." + i, a === "got" ? "in 2 days" : "tomorrow");
    A.toast(a === "got" ? "Got it · next review in 2 days" : "Forgot · back tomorrow"); redraw();
  });
  A.action("ex-vb-rv", (el) => {
    const [i, a] = el.dataset.arg.split("|"), q = QUEUE(), v = q[+i];
    SET("vb.s." + v.i, "learning"); SET("vb.n." + v.i, a === "got" ? "in 2 days" : "tomorrow");
    if (+i + 1 >= q.length) { A.go("vocab"); A.toast("Review finished · see you tomorrow"); } else A.go("vocab", { mode: "review", i: +i + 1 });
  });
  A.action("ex-vb-lookup", (el) => { const v = VOCAB[+el.dataset.arg]; A.open("dict", { id: v.book, word: v.w }); });
  A.overlay("ex-vb-word", {
    layer: "dialog",
    render(p) {
      const v = VOCAB[+p.i || 0], b = DB.book(v.book);
      return `<div class="ko-dialog ex-vbw"><div class="ex-vbw-h"><span class="ko-dialog-title serif">${esc(v.w)}</span><span class="ex-pos">${v.pos}</span><span class="grow"></span>${statusPill(v)}</div>
        <div class="ko-dialog-body ex-vbw-def">${esc(v.def)}</div>
        <div class="ex-ctx" dir="auto">${ctxHTML(v)}</div><div class="ko-dialog-sub">${esc(short(b))} · looked up ${v.added}</div>
        <div class="ko-group ex-group ex-dlg-group">
          ${row("book-a", "Look up in dictionary", `data-action="ex-vb-lookup" data-arg="${v.i}"`, { chev: true })}
          ${row("rotate-ccw", "Reset progress", `data-action="ex-vb-reset" data-arg="${v.i}"`)}
          ${row("book-open", "Open book at this word", `data-action="ex-open-book" data-arg="${v.book}"`, { chev: true })}
          ${row("trash-2", "Remove word", `data-action="ex-vb-del" data-arg="${v.i}"`, { cls: "ex-danger" })}
        </div>
        <div class="ko-dialog-actions"><button class="ko-btn ko-btn--ghost" data-close>Close</button></div></div>`;
    },
  });
  A.action("ex-vb-reset", (el) => { SET("vb.s." + el.dataset.arg, "due"); A.close(); redraw(); A.toast("Progress reset · word is due now"); });
  A.action("ex-vb-del", () => { A.close(); A.toast("Word removed from vocabulary"); });
  A.overlay("ex-vb-settings", {
    layer: "sheet",
    render() {
      return sheet("ex-vbs", sheetHead("graduation-cap", "Vocabulary settings", "How words are collected and reviewed"),
        label("Collecting") + group(tgRow("book-a", "Save words looked up in the dictionary", "vb.save", true) + tgRow("text-quote", "Save the sentence around the word", "vb.ctx", true) + tgRow("filter", "Only words looked up in books", "vb.only", false))
        + label("Reviewing") + group(segRow("calendar-clock", "Review intervals", "vb.int", [["short", "Short"], ["std", "Standard"], ["long", "Long"]], "std") + stepRow("list-ordered", "Words per review session", "vb.per", 10, 5, 50) + tgRow("eye-off", "Hide the word in its sentence", "vb.hide", true))
        + label("Data") + group(row("download", "Export words as CSV", `data-toast="Exported 14 words to /mnt/onboard/vocabulary.csv"`) + row("trash-2", "Remove learned words", `data-toast="3 learned words removed"`, { cls: "ex-danger" })));
    },
  });

  /* =====================================================================
     5 · LOOKUP HISTORY (dictionary + Wikipedia)
     ===================================================================== */
  const DICT_H = [
    ["Today", "conceived", "animal-farm", 0, "21:08"], ["Today", "tyranny", "animal-farm", 0, "20:55"], ["Today", "البيداء", "ar-poems", 3, "08:12"],
    ["Yesterday", "busybody", "meditations", 2, "22:41"], ["Yesterday", "ardour", "frankenstein", 0, "22:30"], ["Yesterday", "moderation", "frankenstein", 0, "22:29"],
    ["This week", "improbable", "sherlock-2", 0, "Mon 23:02"], ["This week", "countenance", "pride", 1, "Sun 19:40"], ["This week", "lees", "moby", 0, "Sat 10:15"], ["This week", "impart", "siddhartha", 2, "Sat 09:58"],
    ["Earlier", "loomings", "moby", 0, "Oct 2"], ["Earlier", "acknowledged", "pride", 0, "Oct 21"],
  ].map(([g, w, book, d, t]) => ({ g, w, book, d, t }));
  const WIKI_H = [
    ["Today", "George Orwell", "EN", "animal-farm", "English novelist, essayist and critic, 1903–1950.", "21:02"], ["Today", "Napoleon", "EN", "animal-farm", "French military commander and emperor of the French.", "20:47"],
    ["Yesterday", "Stoicism", "EN", "meditations", "School of Hellenistic philosophy founded in Athens around 300 BC.", "22:12"], ["Yesterday", "Marcus Aurelius", "EN", "meditations", "Roman emperor from 161 to 180 and a Stoic philosopher.", "22:05"],
    ["This week", "Mary Shelley", "EN", "frankenstein", "English novelist who wrote the Gothic novel Frankenstein.", "Mon 21:30"], ["This week", "المتنبي", "AR", "ar-poems", "شاعر عربي من العصر العباسي، ولد في الكوفة.", "Sun 08:20"],
    ["Earlier", "Sperm whale", "EN", "moby", "The largest of the toothed whales and the largest toothed predator.", "Oct 2"], ["Earlier", "Baker Street", "EN", "sherlock-2", "Street in Marylebone, London, home of the fictional detective.", "Oct 18"],
  ].map(([g, w, lang, book, s, t]) => ({ g, w, lang, book, s, t }));
  const histQ = { dict: "", wiki: "" };
  const histList = (kind) => {
    const q = histQ[kind].toLowerCase(), src = kind === "dict" ? DICT_H : WIKI_H;
    const items = src.filter((h) => !q || (h.w + " " + (h.s || "") + " " + DB.book(h.book).title).toLowerCase().includes(q));
    if (!items.length) return `<div class="ko-empty">${I("search-x")}<div>No lookups match “${esc(histQ[kind])}”</div></div>`;
    const groups = [...new Set(items.map((h) => h.g))];
    return groups.map((g) => `${label(g)}${group(items.filter((h) => h.g === g).map((h) => {
      const b = DB.book(h.book), rtl = /[؀-ۿ]/.test(h.s || "");
      return kind === "dict"
        ? `<button class="ko-row mn-row ex-hrow" data-action="ex-h-open" data-k="dict" data-w="${esc(h.w)}" data-b="${h.book}"><span class="ko-icon-tile">${I("book-a")}</span><span class="label"><span class="t ex-hw" dir="auto">${esc(h.w)}</span><span class="sub"><span dir="auto">${esc(short(b))}</span> · ${esc(DB.DICTIONARIES[h.d])}</span></span><span class="value num">${h.t}</span></button>`
        : `<button class="ko-row mn-row ex-hrow" data-action="ex-h-open" data-k="wiki" data-w="${esc(h.w)}" data-b="${h.book}"><span class="ko-icon-tile ex-lang">${h.lang}</span><span class="label"><span class="t ex-hw" dir="auto">${esc(h.w)}</span><span class="sub" ${rtl ? 'dir="rtl"' : ""}>${esc(h.s)}</span></span><span class="value num">${h.t}</span></button>`;
    }).join(""))}`).join("");
  };
  const histScreen = (kind) => ({
    render() {
      const n = (kind === "dict" ? DICT_H : WIKI_H).length;
      const tabs = `<nav class="ko-tabs ex-tabs"><button class="ko-tab ${kind === "dict" ? "on" : ""}" data-go="dict-history">Dictionary<span class="ex-cn num">${DICT_H.length}</span></button><button class="ko-tab ${kind === "wiki" ? "on" : ""}" data-go="wiki-history">Wikipedia<span class="ex-cn num">${WIKI_H.length}</span></button></nav>`;
      const sub = tabs + `<div class="ex-search"><label class="ko-input ko-input--card">${I("search", "sm")}<input type="search" id="ex-h-q" placeholder="${kind === "dict" ? "Search looked-up words" : "Search articles"}" value="${esc(histQ[kind])}" autocomplete="off"></label></div>`;
      const foot = `<div class="ko-pager ex-foot"><span class="num">${n} ${kind === "dict" ? "lookups" : "articles"} · newest first</span><span class="grow"></span><button class="ko-btn ko-btn--ghost" data-open="confirm" data-params="${A.attrs({ title: `Clear ${kind === "dict" ? "dictionary" : "Wikipedia"} history?`, body: `All ${n} entries will be removed. Words in the vocabulary builder are kept.`, ok: "Clear history", danger: true, icon: "eraser" })}">${I("eraser", "sm")}Clear history</button></div>`;
      return screen({ title: kind === "dict" ? "Dictionary history" : "Wikipedia history", crumb: "Search", status: "Lookup history", sub, body: `<div id="ex-h-res">${histList(kind)}</div>`, foot, cls: "ex-hist" });
    },
    mount(root) {
      const inp = root.querySelector("#ex-h-q"); if (!inp) return;
      inp.addEventListener("input", () => { histQ[kind] = inp.value.trim(); root.querySelector("#ex-h-res").innerHTML = histList(kind); A.icons(); });
    },
  });
  A.screen("dict-history", histScreen("dict"));
  A.screen("wiki-history", histScreen("wiki"));
  A.action("ex-h-open", (el) => { const id = el.dataset.b; if (el.dataset.k === "dict") A.open("dict", { id, word: el.dataset.w }); else A.open("wiki", { id, q: el.dataset.w }); });

  /* =====================================================================
     6 · PROGRESS SYNC
     ===================================================================== */
  A.overlay("kosync", {
    layer: "sheet",
    render(p) {
      const logged = (p.state || (S("ks.in", false) ? "account" : "login")) === "account";
      const b = DB.book(A.current.params.id || "animal-farm");
      if (!logged) {
        const custom = S("ks.server", "default") === "custom";
        return sheet("ex-ks", sheetHead("refresh-cw", "Progress sync", "Continue on any device where you left off"),
          `<div class="ex-intro">${I("info", "sm")}<span>Only your reading position is synced, never your books. Use the same account on every device.</span></div>`
          + label("Server") + `<div class="ex-pad">${seg("ks.server", [["default", "KOReader sync"], ["custom", "Custom server"]], "default", "ex-seg-block")}</div>`
          + (custom ? `<div class="ex-pad ex-form ex-gap">${field("server", "https://sync.example.com", "https://sync.lan:7200")}</div>` : `<div class="ex-pad ex-hint">${I("globe", "sm")}sync.koreader.rocks · free, run by the KOReader project</div>`)
          + label("Account") + `<div class="ex-pad ex-form">${field("user", "Username", "seif")}${field("lock", "Password", "readingnook", "password")}</div>`
          + `<div class="ex-pad ex-hint">${I("shield-check", "sm")}Your password is hashed on this device before it is sent.</div>`,
          `<button class="ko-btn" data-action="ex-ks-login" data-arg="register">${I("user-plus", "sm")}Register</button><button class="ko-btn ko-btn--primary grow" data-action="ex-ks-login" data-arg="login">${I("log-in", "sm")}Log in</button>`);
      }
      const auto = S("ks.auto", true);
      const dev = (ic, name, sub, pct, cls = "") => `<div class="ex-dev ${cls}"><span class="ko-icon-tile">${I(ic)}</span><div class="grow"><div class="ex-dev-h"><span class="ex-dev-n ellipsis">${name}</span><span class="num">${pct}%</span></div>${A.progress(pct, "ko-progress--thin")}<div class="ex-dev-s">${sub}</div></div></div>`;
      return sheet("ex-ks", sheetHead("refresh-cw", "Progress sync", `Signed in as <b>seif</b> · sync.koreader.rocks`),
        `<div class="ko-card ex-kscard">
            <div class="ex-ks-book">${tiny(b)}<div class="grow"><div class="ex-dev-n ellipsis" dir="auto">${esc(short(b))}</div><div class="ex-dev-s">${I("circle-check", "sm")}In sync · pushed 2 min ago</div></div></div>
            ${dev("tablet-smartphone", "This device · Kobo Libra 2", "p. 9 of 112 · now", b.progress || 8, "me")}
            ${dev("book-open", "Kindle", "p. 72 of 112 · 3 hours ago", 64)}
            ${dev("smartphone", "Phone", "p. 7 of 112 · last week", 6)}
          </div>
          <div class="ex-pad ex-btnrow"><button class="ko-btn grow" data-action="ex-ks-push">${I("upload", "sm")}Push progress</button><button class="ko-btn grow" data-open="kosync-prompt">${I("download", "sm")}Pull progress</button></div>`
        + label("Automatic sync") + group(tgRow("refresh-ccw-dot", "Keep documents in sync automatically", "ks.auto", true, "On open, close, suspend and resume").replace('data-action="ex-tg"', 'data-action="ex-tg" data-redraw')
          + (auto ? stepRow("file-stack", "Also sync every", "ks.every", 5, 1, 50, " pages") : row("file-stack", "Periodically sync every # pages", "", { value: "Needs automatic sync", cls: "disabled", div: true })))
        + label("When another device is") + group(segRow("fast-forward", "Further ahead", "ks.newer", [["silent", "Silently"], ["prompt", "Prompt"], ["never", "Never"]], "prompt") + segRow("rewind", "Further behind", "ks.older", [["silent", "Silently"], ["prompt", "Prompt"], ["never", "Never"]], "never"))
        + label("Matching") + group(segRow("fingerprint", "Match books by", "ks.match", [["binary", "File content"], ["name", "Filename"]], "binary") + tgRow("file-text", "Send document metadata", "ks.meta", false, "Title and author, for custom servers"))
        + label("Account") + group(row("monitor-smartphone", "Device name", `data-open="input" data-params="${A.attrs({ title: "Device name", value: "Kobo Libra 2", ok: "Save" })}"`, { value: "Kobo Libra 2", tail: I("pencil", "chev sm") }) + row("server", "Sync server", `data-open="input" data-params="${A.attrs({ title: "Custom sync server", value: "https://sync.koreader.rocks", ok: "Save" })}"`, { value: "sync.koreader.rocks", tail: I("pencil", "chev sm") }) + row("log-out", "Log out", `data-action="ex-ks-out"`, { cls: "ex-danger" })));
    },
  });
  A.action("ex-ks-login", (el) => { SET("ks.in", true); setTopParams({ state: "account" }); A.toast(el.dataset.arg === "register" ? "Account created · signed in as seif" : "Signed in as seif"); });
  A.action("ex-ks-out", () => { SET("ks.in", false); setTopParams({ state: "login" }); A.toast("Logged out of progress sync"); });
  A.action("ex-ks-push", () => A.toast("Progress pushed · page 9 (8%)"));
  A.overlay("kosync-prompt", {
    layer: "dialog",
    render() {
      const b = DB.book(A.current.params.id || "animal-farm");
      const pos = (ic, who, sub, pct, cls) => `<div class="ex-pos-row ${cls}"><span class="ko-icon-tile">${I(ic)}</span><div class="grow"><div class="ex-dev-h"><b>${who}</b><span class="num">${pct}%</span></div>${A.progress(pct, "ko-progress--thin")}<div class="ex-dev-s">${sub}</div></div></div>`;
      return `<div class="ko-dialog ex-ksp${still()}">
        <div class="ko-dialog-title">Newer position found</div>
        <div class="ko-dialog-body">A newer position exists on another device (Kindle, 64%): jump there?</div>
        <div class="ex-pos-box">${pos("book-open", "Kindle", "p. 72 · Chapter VII · 3 hours ago", 64, "them")}${pos("tablet-smartphone", "This device", `p. 9 · Chapter I · now`, b.progress || 8, "me")}</div>
        <button class="ko-check-row" data-action="ex-tg-check" data-k="ks.always">${A.check(S("ks.always", false))}<span>Always jump without asking</span></button>
        <div class="ko-dialog-actions"><button class="ko-btn ko-btn--ghost" data-close>Stay here</button><button class="ko-btn ko-btn--primary" data-action="ex-ks-jump">${I("arrow-right", "sm")}Jump to 64%</button></div>
      </div>`;
    },
  });
  A.action("ex-tg-check", (el) => { SET(el.dataset.k, !S(el.dataset.k, false)); redraw(); });
  A.action("ex-ks-jump", () => { A.closeAll(); A.toast("Jumped to page 72 · Chapter VII"); });

  /* =====================================================================
     7 · OPDS CATALOGS
     ===================================================================== */
  const CATALOGS = [
    { k: "gutenberg", n: "Project Gutenberg", u: "m.gutenberg.org/ebooks.opds", ic: "landmark", note: "70,000+ free classics" },
    { k: "standard", n: "Standard Ebooks", u: "standardebooks.org/feeds/opds", ic: "book-marked", note: "Carefully produced public-domain books" },
    { k: "archive", n: "Internet Archive", u: "bookserver.archive.org/catalog", ic: "archive", note: "Lending library and public domain" },
    { k: "calibre", n: "Calibre on MacBook", u: "192.168.1.20:8080/opds", ic: "library", note: "Your calibre library · 1,284 books", lock: true },
    { k: "manybooks", n: "ManyBooks", u: "manybooks.net/opds", ic: "book-copy", note: "Free and indie ebooks" },
  ];
  const SECTIONS_O = [
    ["new", "New releases", "sparkles", "Added in the last 30 days"], ["popular", "Most popular", "trending-up", "Downloads this month"],
    ["subjects", "Subjects", "tags", "Fiction, philosophy, poetry, science…"], ["authors", "Authors", "users", "Browse A–Z"],
    ["collections", "Collections", "layers", "Curated reading lists"], ["all", "All ebooks", "library-big", "Sorted by title"],
  ];
  const OBOOKS = [
    ["The Picture of Dorian Gray", "Oscar Wilde", 1890, ["#2d1b3d", "#ead9c4", "#8a5a9b"], "frame", "Fiction"],
    ["Middlemarch", "George Eliot", 1871, ["#6b4e2e", "#f3e9d8", "#3c2b18"], "column", "Fiction"],
    ["The Prince", "Niccolò Machiavelli", 1532, ["#5a1a1a", "#f0e2c8", "#c49a3c"], "band", "Philosophy"],
    ["Heart of Darkness", "Joseph Conrad", 1899, ["#14231c", "#d9e2d0", "#5d7a3a"], "leaf", "Fiction"],
    ["Beyond Good and Evil", "Friedrich Nietzsche", 1886, ["#1b1b1b", "#e8e1d0", "#a33b2a"], "deco", "Philosophy"],
    ["The Count of Monte Cristo", "Alexandre Dumas", 1844, ["#0e2f44", "#f1e6cf", "#c9a24b"], "wave", "Adventure"],
    ["Persuasion", "Jane Austen", 1817, ["#e3d3c5", "#4b3a32", "#b98d74"], "oval", "Fiction"],
    ["The Republic", "Plato", -375, ["#c8b88a", "#2f2a1f", "#8a7a4f"], "column", "Philosophy"],
  ].map(([title, author, year, palette, style, subject], i) => ({ id: "opds-" + i, title, author, year, palette, style, subject, lang: "en", i, size: (0.4 + ((i * 7) % 12) / 10), pages: 180 + ((i * 97) % 500) }));
  const FORMATS = [["epub", "EPUB", "Recommended · reflowable", 1], ["kepub", "Kobo EPUB", "Faster page turns on Kobo", 1.1], ["azw3", "AZW3", "Kindle format", 1.3], ["pdf", "PDF", "Fixed layout · not reflowable", 2.6], ["txt", "Plain text", "No formatting or images", 0.4]];
  const yr = (y) => (y < 0 ? -y + " BC" : String(y));
  A.screen("opds", {
    render(p) {
      const cat = CATALOGS.find((c) => c.k === p.cat);
      if (!cat) {
        const body = label("Catalogs") + group(CATALOGS.map((c) => `<div class="ko-row mn-row ex-orow" role="button" data-go="opds" data-params="${A.attrs({ cat: c.k })}"><span class="ko-icon-tile">${I(c.ic)}</span><span class="label"><span class="t">${c.n}${c.lock ? `<span class="ex-lock">${I("lock", "sm")}</span>` : ""}</span><span class="sub ellipsis">${c.note}</span></span><button class="ko-icon-btn lb-more" data-open="ex-opds-edit" data-params="${A.attrs({ k: c.k })}" aria-label="Edit catalog">${I("ellipsis-vertical", "sm")}</button></div>`).join(""))
          + `<div class="ex-pad"><button class="ko-btn ko-btn--block ex-add" data-open="ex-opds-edit" data-params="${A.attrs({ k: "" })}">${I("plus", "sm")}Add OPDS catalog</button></div>`
          + label("Recent downloads") + group(OBOOKS.slice(0, 2).map((b, i) => `<button class="ko-row mn-row ex-orow" data-action="ex-open-book" data-arg="middlemarch">${tiny(b)}<span class="label"><span class="t ellipsis">${esc(b.title)}</span><span class="sub">${["Standard Ebooks · EPUB · today", "Project Gutenberg · EPUB · yesterday"][i]}</span></span><span class="ex-st">${I("circle-check", "sm")}On device</span></button>`).join(""))
          + `<div class="ex-pad ex-hint">${I("folder-down", "sm")}Downloads are saved to Books/Downloads</div>`;
        return screen({ title: "OPDS catalogs", crumb: "Search", status: "OPDS", body, cls: "ex-opds", actions: `<button class="ko-icon-btn" data-go="folder" data-params="${A.attrs({ path: "Downloads" })}" aria-label="Downloads folder">${I("folder-down")}</button>` });
      }
      const sec = SECTIONS_O.find((s) => s[0] === p.sec);
      const searchBtn = `<div class="ex-search"><button class="ko-input ko-input--card ex-fakeinput" data-open="input" data-params="${A.attrs({ title: `Search ${cat.n}`, hint: "Title, author or subject", ok: "Search" })}">${I("search", "sm")}<span>Search ${esc(cat.n)}</span></button></div>`;
      if (!sec) {
        const body = searchBtn + label("Browse") + group(SECTIONS_O.map(([k, n, ic, d]) => row(ic, n, `data-go="opds" data-params="${A.attrs({ cat: cat.k, sec: k })}"`, { sub: d, chev: true })).join(""))
          + `<div class="ex-pad ex-hint">${I(cat.lock ? "lock" : "globe", "sm")}${cat.u}</div>`;
        return screen({ title: cat.n, crumb: "OPDS catalogs", status: "OPDS", body, cls: "ex-opds", backTo: { name: "opds", params: {} }, actions: `<button class="ko-icon-btn" data-toast="Catalog refreshed" aria-label="Refresh">${I("refresh-cw")}</button>` });
      }
      const page = +p.page || 1;
      const books = OBOOKS.map((b) => `<div class="ex-obook" role="button" data-open="opds-book" data-params="${A.attrs({ cat: cat.k, i: b.i })}">
          <span class="ex-ocov">${Cover.html(b)}</span>
          <div class="grow"><div class="ex-ob-t ellipsis">${esc(b.title)}</div><div class="ex-ob-a ellipsis">${esc(b.author)}</div>
            <div class="ex-ob-m">${b.subject} · <span class="num">${yr(b.year)}</span> · EPUB, AZW3, PDF</div></div>
          ${S("o.dl." + b.i, false) ? `<span class="ex-st">${I("circle-check", "sm")}On device</span>` : `<button class="ko-icon-btn ex-odl" data-open="opds-book" data-params="${A.attrs({ cat: cat.k, i: b.i })}" aria-label="Download">${I("download")}</button>`}</div>`).join("");
      const foot = `<div class="ko-pager"><span class="num">${OBOOKS.length * 12} books</span><span class="num">Page ${page} of 12</span><span class="row"><button class="ko-icon-btn" ${page > 1 ? `data-go="opds" data-params="${A.attrs({ cat: cat.k, sec: sec[0], page: page - 1 })}"` : "disabled"} aria-label="Previous page">${I("chevron-left")}</button><button class="ko-icon-btn" data-go="opds" data-params="${A.attrs({ cat: cat.k, sec: sec[0], page: page + 1 })}" aria-label="Next page">${I("chevron-right")}</button></span></div>`;
      return screen({ title: sec[1], crumb: `OPDS catalogs › ${esc(cat.n)}`, status: "OPDS", body: `<div class="ex-obooks">${books}</div>`, foot, cls: "ex-opds", backTo: { name: "opds", params: { cat: cat.k } } });
    },
  });
  A.overlay("ex-opds-edit", {
    layer: "dialog",
    render(p) {
      const c = CATALOGS.find((x) => x.k === p.k);
      return `<div class="ko-dialog ex-oedit${still()}"><div class="ko-dialog-title">${c ? "Edit catalog" : "Add OPDS catalog"}</div>
        <div class="ex-form">${field("tag", "Catalog name", c ? c.n : "")}${field("link", "Catalog URL", c ? "https://" + c.u : "https://")}${field("user", "Username (optional)", c && c.lock ? "seif" : "")}${field("lock", "Password (optional)", c && c.lock ? "secret" : "", "password")}</div>
        <button class="ko-check-row" data-action="ex-tg-check" data-k="o.raw">${A.check(S("o.raw", false))}<span>Use server filenames</span></button>
        <div class="ko-dialog-actions">${c ? `<button class="ko-btn ko-btn--ghost ex-left" data-action="ex-done">${I("trash-2", "sm")}Delete</button>` : ""}<button class="ko-btn ko-btn--ghost" data-close>Cancel</button><button class="ko-btn ko-btn--primary" data-action="ex-done">${c ? "Save" : "Add"}</button></div></div>`;
    },
  });
  A.overlay("opds-book", {
    layer: "sheet",
    render(p) {
      const b = OBOOKS[+p.i || 0], cat = CATALOGS.find((c) => c.k === p.cat) || CATALOGS[1];
      const fmt = S("o.fmt", "epub"), F = FORMATS.find((f) => f[0] === fmt) || FORMATS[0];
      const mb = (b.size * F[3]).toFixed(1);
      const dl = p.dl || "";
      const fmts = group(FORMATS.map(([k, n, d, m]) => `<button class="ko-row mn-row is-radio ${fmt === k ? "on" : ""}" ${dl ? "disabled" : `data-action="ex-set" data-k="o.fmt" data-v="${k}"`}>${A.radio(fmt === k)}<span class="label"><span class="t">${n}</span><span class="sub">${d}</span></span><span class="value num">${(b.size * m).toFixed(1)} MB</span></button>`).join(""), dl ? "ex-dim" : "");
      let foot;
      if (dl === "progress") foot = `<div class="ex-dlcard grow"><div class="ex-dl-h">${spinner()}<b>Downloading ${F[1]}</b><span class="grow"></span><span class="num">61%</span></div>${A.progress(61)}<div class="ex-dl-s num">${(mb * 0.61).toFixed(1)} of ${mb} MB · about 4 s left</div></div><button class="ko-btn" data-action="ex-o-dl" data-arg="">Cancel</button>`;
      else if (dl === "done") foot = `<div class="ex-dlcard grow"><div class="ex-dl-h">${I("circle-check", "sm")}<b>Downloaded</b></div><div class="ex-dl-s ellipsis">Books/Downloads/${esc(b.title)}.${fmt}</div></div><button class="ko-btn" data-go="folder" data-params="${A.attrs({ path: "Downloads" })}">Show</button><button class="ko-btn ko-btn--primary" data-action="ex-open-book" data-arg="middlemarch">${I("book-open", "sm")}Read</button>`;
      else foot = `<button class="ko-btn" data-open="info" data-params="${A.attrs({ title: "Save to", icon: "folder-down", body: "/mnt/onboard/Books/Downloads", ok: "OK" })}">${I("folder-down", "sm")}Folder</button><button class="ko-btn ko-btn--primary grow" data-action="ex-o-dl" data-arg="progress">${I("download", "sm")}Download ${F[1]} · ${mb} MB</button>`;
      return `<div class="ko-sheet ex-sheet ex-ob${still()}"><div class="grip"></div>
        <div class="ko-sheet-head lba-head ex-ob-head"><div class="ex-ob-cov">${Cover.html(b)}</div><div class="grow"><div class="title">${esc(b.title)}</div><div class="sub">${esc(b.author)}</div>
          <div class="sub">${esc(cat.n)} · ${b.pages} pages</div></div><button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button></div>
        <div class="ko-scroll ex-sbody"><p class="ex-syn">${esc(TextGen.synopsis({ id: b.id }))}</p>
          <div class="ex-meta">${[["Language", "English"], ["Subject", b.subject], ["Published", yr(b.year)], ["Rights", "Public domain"]].map(([a, v]) => `<div><span>${a}</span><b>${v}</b></div>`).join("")}</div>
          ${label("Download as")}${fmts}<div class="ex-end"></div></div>
        <div class="ex-sfoot">${foot}</div></div>`;
    },
  });
  A.action("ex-o-dl", (el) => {
    const v = el.dataset.arg, t = A.top();
    setTopParams({ dl: v });
    if (v === "progress") setTimeout(() => { const tt = A.top(); if (tt && tt === t && tt.params.dl === "progress") { SET("o.dl." + (tt.params.i || 0), true); setTopParams({ dl: "done" }); A.refresh(); } }, 1800);
  });

  /* =====================================================================
     8 · CALIBRE WIRELESS
     ===================================================================== */
  const INCOMING = [["dune-notes", "done"], ["walden", "done"], ["little-women", 46], ["art-of-war", "queued"], ["crime", "queued"]];
  A.overlay("calibre", {
    layer: "sheet",
    render(p) {
      const st = p.state || "searching";
      const head = sheetHead("library", "Calibre", "Wireless device connection");
      const host = `<div class="ko-card ex-calhost"><span class="ko-icon-tile">${I("laptop")}</span><div class="grow"><div class="ex-dev-n">Seif's MacBook Pro</div><div class="ex-dev-s">calibre 8.4 · 192.168.1.20:9090</div></div><span class="ex-st">${I("circle-check", "sm")}Connected</span></div>`;
      const settings = label("Wireless settings") + group(row("folder-input", "Inbox folder", "", { value: "Books/Calibre", chev: true }) + row("file-type", "Preferred format", "", { value: "EPUB", chev: true }) + row("key-round", "Password", "", { value: "Not set", tail: I("pencil", "chev sm") }) + segRow("network", "Server address", "cal.addr", [["auto", "Automatic"], ["manual", "Manual"]], "auto"));
      if (st === "searching") {
        return sheet("ex-cal", head,
          `<div class="ex-searching"><span class="ex-pulse">${I("radar")}</span><div class="ex-sr-t">Looking for calibre…</div><div class="ex-sr-s num">Searching 192.168.1.0/24 · 6 s</div></div>
           ${label("On your computer")}<ol class="ex-steps"><li><b>1</b><span>Open <b>calibre</b> and click <b>Connect/share</b>.</span></li><li><b>2</b><span>Choose <b>Start wireless device connection</b>.</span></li><li><b>3</b><span>Keep this screen open. Leaf connects on its own.</span></li></ol>` + settings,
          `<button class="ko-btn" data-open="input" data-params="${A.attrs({ title: "calibre address", hint: "192.168.1.20:9090", ok: "Connect", layout: "numeric" })}">${I("keyboard", "sm")}Enter address</button><button class="ko-btn ko-btn--primary grow" data-action="ex-cal" data-arg="connected">${I("refresh-cw", "sm")}Search again</button>`);
      }
      if (st === "connected") {
        return sheet("ex-cal", head,
          host + `<div class="ex-wait">${I("inbox")}<div class="grow"><b>Ready to receive books</b><span>In calibre, select books and choose <b>Send to device</b>. They arrive in Books/Calibre.</span></div></div>`
          + label("Library") + group(row("library-big", "Calibre Library", "", { sub: "1,284 books · metadata synced 2 min ago", div: true }) + tgRow("database", "Store metadata in cache", "cal.cache", true, "Makes calibre search fast"))
          + settings,
          `<button class="ko-btn" data-action="ex-cal" data-arg="searching">${I("unplug", "sm")}Disconnect</button><button class="ko-btn ko-btn--primary grow" data-action="ex-cal" data-arg="receiving">${I("download", "sm")}Receive 5 books</button>`);
      }
      const fin = st === "done", done = INCOMING.filter((x) => x[1] === "done").length;
      const rows = INCOMING.map(([id, s]) => {
        const b = DB.book(id), state = fin ? "done" : s;
        const right = state === "done" ? `<span class="ex-st">${I("circle-check", "sm")}Done</span>` : state === "queued" ? `<span class="ex-st">${I("clock", "sm")}Waiting</span>` : `<span class="ex-st num">${state}%</span>`;
        return `<div class="ko-row mn-row ex-inrow ${state === "queued" ? "q" : ""}">${tiny(b)}<span class="label"><span class="t ellipsis" dir="auto">${esc(b.title)}</span><span class="sub">${b.format.toUpperCase()} · ${b.size}</span>${typeof state === "number" ? A.progress(state, "ko-progress--thin") : ""}</span>${right}</div>`;
      }).join("");
      return sheet("ex-cal", head,
        host + `<div class="ex-recv"><div class="ex-dl-h">${fin ? I("circle-check", "sm") : spinner()}<b>${fin ? "Received 5 books" : `Receiving book ${done + 1} of 5`}</b><span class="grow"></span><span class="num">${fin ? 100 : 52}%</span></div>${A.progress(fin ? 100 : 52)}<div class="ex-dl-s">${fin ? "Saved to Books/Calibre · metadata updated" : "Keep Wi-Fi on until all books arrive"}</div></div>`
        + label("Incoming") + group(rows),
        fin ? `<button class="ko-btn" data-action="ex-cal" data-arg="connected">Done</button><button class="ko-btn ko-btn--primary grow" data-go="folder" data-params="${A.attrs({ path: "Books" })}">${I("folder-open", "sm")}Open Books/Calibre</button>`
          : `<button class="ko-btn grow" data-action="ex-cal" data-arg="done">${I("square", "sm")}Stop after this book</button>`);
    },
  });
  A.action("ex-cal", (el) => setTopParams({ state: el.dataset.arg }));

  /* =====================================================================
     9 · SMALL TOOLS
     ===================================================================== */
  /* ---- read timer ---- */
  A.overlay("read-timer", {
    layer: "sheet",
    render(p) {
      const mode = S("rt.mode", p.mode || "after");
      const min = S("rt.min", 20), hh = S("rt.h", 22), mm = S("rt.m", 30), every = S("rt.every", 30);
      const active = String(p.active) === "1";
      const presets = [5, 10, 15, 20, 30, 45, 60, 90];
      let body = "";
      if (active) body += `<div class="ko-card ex-live"><div class="ex-dl-h">${I("alarm-clock", "sm")}<b>Timer running</b><span class="grow"></span><span class="num">18 min left</span></div>${A.progress(28)}<div class="ex-dl-s num">Rings at ${clockIn(18)} · started at ${clockIn(-7)}</div>
          <div class="ex-btnrow"><button class="ko-btn grow" data-action="ex-rt-add">${I("plus", "sm")}5 min</button><button class="ko-btn grow" data-action="ex-rt-stop">${I("square", "sm")}Stop timer</button></div></div>`;
      body += `<div class="ex-pad">${seg("rt.mode", [["after", "After"], ["at", "At a time"], ["every", "Repeating"]], p.mode || "after", "ex-seg-block")}</div>`;
      if (mode === "after") {
        body += `<div class="ex-pad">${slideRow("Ring after", "rt.min", 20, 1, 120, "min")}</div>
          <div class="ex-pad ex-presets">${presets.map((v) => `<button class="ko-chip ${min === v ? "on" : ""}" data-action="ex-set" data-k="rt.min" data-v="${v}">${v < 60 ? v + " min" : fmtMin(v)}</button>`).join("")}</div>
          <div class="ex-pad ex-hint">${I("bell", "sm")}Rings at <b class="num">${clockIn(min)}</b></div>`;
      } else if (mode === "at") {
        body += group(stepRow("clock", "Hour", "rt.h", 22, 0, 23) + stepRow("clock-3", "Minute", "rt.m", 30, 0, 59)) + `<div class="ex-pad ex-hint">${I("bell", "sm")}Rings at <b class="num">${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}</b> today</div>`;
      } else {
        body += `<div class="ex-pad">${slideRow("Remind me every", "rt.every", 30, 5, 120, "min", 5)}</div><div class="ex-pad ex-hint">${I("repeat", "sm")}Repeats every ${fmtMin(every)} until you stop it</div>`;
      }
      body += label("When time is up") + group(segRow("message-square", "Show", "rt.exp", [["message", "Message"], ["notification", "Notice"], ["nothing", "Nothing"]], "message")
        + row("text-cursor-input", "Message text", `data-open="input" data-params="${A.attrs({ title: "Expiry message text", value: "Time is up. Take a break.", ok: "Save" })}"`, { value: "Default", tail: I("pencil", "chev sm") }));
      return sheet("ex-rt", sheetHead("timer", "Read timer", "A gentle alarm while you read"), body,
        `<button class="ko-btn" data-close>Cancel</button><button class="ko-btn ko-btn--primary grow" data-action="ex-rt-start">${I("alarm-clock", "sm")}${active ? "Restart timer" : "Start timer"}</button>`);
    },
  });
  A.action("ex-rt-start", () => { setTopParams({ active: 1 }); A.toast("Timer set"); });
  A.action("ex-rt-stop", () => { setTopParams({ active: 0 }); A.toast("Timer stopped"); });
  A.action("ex-rt-add", () => A.toast("Added 5 minutes · 23 min left"));

  /* ---- autoturn ---- */
  A.overlay("autoturn", {
    layer: "sheet",
    render() {
      const on = S("at.on", false), sec = S("at.sec", 20);
      return sheet("ex-at", sheetHead("timer-reset", "Autoturn", on ? `On · turning every ${fmtSlide("s", sec)}` : "Off · turns pages on its own, hands-free", `<button class="ex-headtg" data-action="ex-at-go" aria-label="Autoturn on or off">${A.toggle(on)}</button>`),
        `${on ? `<div class="ko-card ex-live"><div class="ex-dl-h">${I("timer-reset", "sm")}<b>Next page in 14 s</b><span class="grow"></span><span class="faint num">p. 9 → 10</span></div>${A.progress(30)}</div>` : ""}
          <div class="ex-pad">${slideRow("Turn the page every", "at.sec", 20, 2, 120, "s")}</div>
          <div class="ex-pad">${seg("at.sec", [[5, "5 s"], [10, "10 s"], [20, "20 s"], [30, "30 s"], [60, "1 min"], [120, "2 min"]], 20, "ex-seg-block")}</div>
          ${label("Turning")}${group(stepRow("files", "Pages per turn", "at.n", 1, 1, 10) + segRow("arrow-right-left", "Direction", "at.dir", [["fwd", "Forward"], ["back", "Backward"]], "fwd") + tgRow("pause", "Pause on any tap", "at.pause", true, "Tap the page again to resume"))}`,
        `<button class="ko-btn" data-close>Close</button><button class="ko-btn ko-btn--primary grow" data-action="ex-at-go">${I(on ? "square" : "play", "sm")}${on ? "Stop autoturn" : "Start autoturn"}</button>`);
    },
  });
  A.action("ex-at-go", () => { const on = !S("at.on", false); SET("at.on", on); redraw(); A.toast(on ? `Autoturn on · every ${fmtSlide("s", S("at.sec", 20))}` : "Autoturn off"); });

  /* ---- profiles ---- */
  const PROFILES = [
    { id: "night", n: "Night reading", ic: "moon", acts: [["Night mode", "On"], ["Frontlight", "8%"], ["Warmth", "80%"], ["Font size", "22"], ["Full refresh", "Every page"]], auto: ["On wake-up"] },
    { id: "manga", n: "Manga & comics", ic: "book-image", acts: [["Reading direction", "Right to left"], ["Zoom", "Fit page"], ["Panel zoom", "On"], ["Full refresh", "Every page"]], auto: ["When a book opens"] },
    { id: "commute", n: "Commute", ic: "train-front", acts: [["Wi-Fi", "Off"], ["Autoturn", "Off"], ["Status bar", "Minimal"]], auto: [] },
    { id: "papers", n: "PDF papers", ic: "file-text", acts: [["Two columns", "On"], ["Contrast", "1.4"], ["Margins", "Crop"], ["Rotation", "Landscape"]], auto: ["When a book opens", "On rotation"] },
  ];
  const TRIGGERS = [["power", "When Leaf starts"], ["sun", "On wake-up"], ["book-open", "When a book opens"], ["book", "When a book closes"], ["rotate-cw", "On rotation"], ["battery-charging", "When charging starts"], ["battery", "When charging stops"]];
  A.overlay("profiles", {
    layer: "sheet",
    render(p) {
      const pr = PROFILES.find((x) => x.id === p.id);
      if (!pr) {
        const list = group(PROFILES.map((x) => `<div class="ko-row mn-row ex-prow" role="button" data-action="ex-pr" data-arg="${x.id}"><span class="ko-icon-tile">${I(x.ic)}</span><span class="label"><span class="t">${x.n}</span><span class="sub ellipsis">${x.acts.length} settings · ${x.auto.length ? "auto: " + x.auto[0].toLowerCase() : "manual"}</span></span><button class="ko-btn ex-apply" data-action="ex-pr-apply" data-arg="${x.n}">Apply</button>${I("chevron-right", "chev sm")}</div>`).join(""));
        return sheet("ex-pr", sheetHead("user-cog", "Profiles", "Apply many settings in one tap"),
          label(`Your profiles · ${PROFILES.length}`) + list + label("Create") + group(row("plus", "New", `data-open="input" data-params="${A.attrs({ title: "New profile", hint: "Profile name", ok: "Create" })}"`, { sub: "Start empty, then add settings and actions", chev: true })
            + row("copy-plus", "New with current book settings", `data-open="input" data-params="${A.attrs({ title: "New profile from this book", hint: "Profile name", value: "Animal Farm setup", ok: "Create" })}"`, { sub: "Font, margins, spacing and refresh of the open book", chev: true }))
          + `<div class="ex-pad ex-hint">${I("hand", "sm")}Profiles also appear in the gesture manager, so a swipe can apply one.</div>`);
      }
      const back = `<button class="ko-icon-btn ex-sh-back" data-action="ex-pr" data-arg="" aria-label="Back">${I("arrow-left")}</button>`;
      const acts = group(pr.acts.map(([a, v]) => `<div class="ko-row mn-row ex-actrow"><span class="label"><span class="t">${a}</span></span><span class="value">${v}</span><button class="ko-icon-btn ex-x" data-toast="Removed ${esc(a)}" aria-label="Remove">${I("x", "sm")}</button></div>`).join(""))
        + group(row("plus", "Add a setting or action", `data-toast="Choose from the gesture action list"`, { chev: true }));
      const trig = group(TRIGGERS.map(([ic, l]) => { const k = `pr.${pr.id}.${l}`, on = S(k, pr.auto.includes(l)); return `<button class="ko-row mn-row" data-action="ex-tg" data-k="${k}" data-def="${pr.auto.includes(l) ? 1 : 0}" data-redraw><span class="ko-icon-tile">${I(ic)}</span><span class="label"><span class="t">${l}</span>${on && l === "When a book opens" ? `<span class="sub">Only for ${pr.id === "manga" ? "CBZ and CBR files" : pr.id === "papers" ? "PDF files" : "any book"}</span>` : ""}</span>${A.toggle(on)}</button>`; }).join(""));
      return sheet("ex-pr", sheetHead(pr.ic, pr.n, `${pr.acts.length} settings · ${pr.auto.length ? "runs automatically" : "manual"}`, "", back),
        label("Applies") + acts + label("Run automatically") + trig
        + label("Options") + group(tgRow("bell", "Show a notification when applied", `pr.${pr.id}.note`, true) + tgRow("hand", "Show in gesture manager", `pr.${pr.id}.gest`, true) + row("pencil-line", "Rename", `data-open="input" data-params="${A.attrs({ title: "Rename profile", value: pr.n, ok: "Rename" })}"`, { chev: true }) + row("trash-2", "Delete profile", `data-open="confirm" data-params="${A.attrs({ title: `Delete “${pr.n}”?`, body: "Gestures that apply this profile will do nothing.", ok: "Delete", danger: true })}"`, { cls: "ex-danger" })),
        `<button class="ko-btn ko-btn--primary grow" data-action="ex-pr-apply" data-arg="${esc(pr.n)}">${I("play", "sm")}Apply now</button>`);
    },
  });
  A.action("ex-pr", (el) => setTopParams({ id: el.dataset.arg }));
  A.action("ex-pr-apply", (el, ev) => { ev?.stopPropagation(); A.toast(`Applied “${el.dataset.arg}”`); });

  /* ---- news downloader ---- */
  const FEEDS = [
    ["The Guardian · Long Read", "theguardian.com/news/series/the-long-read/rss", 5, true, "2 h ago", "done", 5],
    ["Ars Technica", "feeds.arstechnica.com/arstechnica/index", 10, false, "2 h ago", "done", 10],
    ["Aeon Essays", "aeon.co/feed.rss", 3, true, "yesterday", 40, 3],
    ["BBC News · World", "feeds.bbci.co.uk/news/world/rss.xml", 10, false, "yesterday", "queued", 10],
    ["Hacker News · Best", "hnrss.org/best", 15, false, "3 days ago", "queued", 15],
  ];
  A.overlay("news", {
    layer: "sheet",
    render(p) {
      if (p.state === "fetching") {
        const rows = FEEDS.map(([n, , lim, , , st, got]) => {
          const right = st === "done" ? `<span class="ex-st">${I("circle-check", "sm")}${got} saved</span>` : st === "queued" ? `<span class="ex-st">${I("clock", "sm")}Waiting</span>` : `<span class="ex-st num">${Math.round((st / 100) * lim) + 1} of ${lim}</span>`;
          return `<div class="ko-row mn-row ex-inrow ${st === "queued" ? "q" : ""}"><span class="ko-icon-tile">${I("newspaper")}</span><span class="label"><span class="t ellipsis">${n}</span>${typeof st === "number" ? `<span class="sub">Downloading articles and images…</span>${A.progress(st, "ko-progress--thin")}` : `<span class="sub">${st === "done" ? "Saved as EPUB" : `Up to ${lim} articles`}</span>`}</span>${right}</div>`;
        }).join("");
        return sheet("ex-news", sheetHead("rss", "News downloader", "Fetching your feeds"),
          `<div class="ex-recv"><div class="ex-dl-h">${spinner()}<b>Fetching feed 3 of 5</b><span class="grow"></span><span class="num">46%</span></div>${A.progress(46)}<div class="ex-dl-s">15 articles saved · Wi-Fi stays on until finished</div></div>` + label("Feeds") + group(rows),
          `<button class="ko-btn grow" data-action="ex-news" data-arg="">${I("square", "sm")}Stop</button><button class="ko-btn grow" data-go="folder" data-params="${A.attrs({ path: "Books/News" })}">${I("folder-open", "sm")}News folder</button>`);
      }
      const rows = FEEDS.map(([n, u, lim, full, when]) => `<button class="ko-row mn-row" data-open="ex-feed" data-params="${A.attrs({ n, u, lim, full })}"><span class="ko-icon-tile">${I("newspaper")}</span><span class="label"><span class="t ellipsis">${n}</span><span class="sub ellipsis">${lim} articles · ${full ? "full text" : "summary only"}</span></span><span class="value">${when}</span>${I("chevron-right", "chev sm")}</button>`).join("")
        + row("plus", "Add feed", `data-open="ex-feed" data-params="${A.attrs({ n: "", u: "", lim: 5, full: true })}"`, { chev: true });
      return sheet("ex-news", sheetHead("rss", "News downloader", "RSS and Atom feeds, saved as EPUBs"),
        label(`Feeds · ${FEEDS.length}`) + group(rows)
        + label("Settings") + group(tgRow("image-off", "Never download images", "news.noimg", false, "Smaller files, faster sync") + row("folder-down", "Download folder", "", { value: "Books/News", chev: true }) + row("trash-2", "Delete all downloaded items", `data-open="confirm" data-params="${A.attrs({ title: "Delete all news?", body: "All 34 downloaded articles will be deleted from Books/News.", ok: "Delete", danger: true })}"`, { cls: "ex-danger" })),
        `<button class="ko-btn" data-go="folder" data-params="${A.attrs({ path: "Books/News" })}">${I("folder-open", "sm")}Open folder</button><button class="ko-btn ko-btn--primary grow" data-action="ex-news" data-arg="fetching">${I("refresh-cw", "sm")}Sync news feeds</button>`);
    },
  });
  A.action("ex-news", (el) => setTopParams({ state: el.dataset.arg }));
  A.overlay("ex-feed", {
    layer: "dialog",
    render(p) {
      return `<div class="ko-dialog ex-oedit${still()}"><div class="ko-dialog-title">${p.n ? esc(p.n) : "Add feed"}</div>
        <div class="ex-form">${field("link", "Feed URL", p.u ? "https://" + p.u : "https://")}</div>
        <div class="ko-group ex-group ex-dlg-group">${stepRow("list-ordered", "Articles to download", "feed.lim", +p.lim || 5, 1, 50)}${tgRow("file-text", "Download full article", "feed.full", p.full !== false)}${tgRow("image", "Include images", "feed.img", true)}</div>
        <div class="ko-dialog-actions">${p.n ? `<button class="ko-btn ko-btn--ghost ex-left" data-action="ex-done">${I("trash-2", "sm")}Remove</button>` : ""}<button class="ko-btn ko-btn--ghost" data-close>Cancel</button><button class="ko-btn ko-btn--primary" data-action="ex-done">Save</button></div></div>`;
    },
  });

  /* ---- wallabag ---- */
  A.overlay("wallabag", {
    layer: "sheet",
    render(p) {
      const st = p.state || "account";
      if (st === "setup") {
        return sheet("ex-wb", sheetHead("newspaper", "Wallabag", "Connect your read-it-later account"),
          `<div class="ex-intro">${I("info", "sm")}<span>Create an API client in wallabag under <b>API clients management</b>, then copy its ID and secret here.</span></div>`
          + label("Server") + `<div class="ex-pad ex-form">${field("globe", "Server URL", "https://app.wallabag.it")}</div>`
          + label("API client") + `<div class="ex-pad ex-form">${field("id-card", "Client ID", "4_2x8rf0ks")}${field("key-round", "Client secret", "secret", "password")}</div>`
          + label("Account") + `<div class="ex-pad ex-form">${field("user", "Username", "seif")}${field("lock", "Password", "secret", "password")}</div>`,
          `<button class="ko-btn" data-close>Cancel</button><button class="ko-btn ko-btn--primary grow" data-action="ex-wb" data-arg="account">${I("plug-zap", "sm")}Connect</button>`);
      }
      const syncing = st === "syncing";
      const stat = (n, l) => `<div class="ex-stat"><b class="num">${n}</b><span>${l}</span></div>`;
      return sheet("ex-wb", sheetHead("newspaper", "Wallabag", "seif · app.wallabag.it"),
        (syncing ? `<div class="ex-recv"><div class="ex-dl-h">${spinner()}<b>Downloading article 7 of 12</b><span class="grow"></span><span class="num">58%</span></div>${A.progress(58)}<div class="ex-dl-s">Uploaded 4 new articles and 6 status changes</div></div>`
          : `<div class="ko-card ex-stats">${stat(30, "on this device")}${stat(4, "to upload")}${stat(6, "status changes")}</div><div class="ex-pad ex-hint">${I("circle-check", "sm")}Last synced 2 hours ago</div>`)
        + label("Sync") + group(row("download", "Download new articles from server", `data-action="ex-wb" data-arg="syncing"`) + row("upload", "Upload queue of locally added articles", `data-toast="4 articles uploaded"`, { value: "4" }) + row("check-check", "Upload article statuses to server", `data-toast="6 statuses uploaded"`, { value: "6" }) + row("folder-open", "Go to download folder", `data-go="folder" data-params="${A.attrs({ path: "Articles" })}"`, { chev: true }))
        + label("Downloads") + group(tgRow("star", "Only download starred articles", "wb.star", false) + stepRow("hash", "Articles to keep locally", "wb.keep", 30, 5, 200) + tgRow("file-type", "Prefer original non-HTML document", "wb.orig", false))
        + label("After reading") + group(tgRow("check", "Mark finished articles as read", "wb.mark", true) + tgRow("archive", "Delete remotely archived articles locally", "wb.del", true, "Moved to the archive folder instead, if one is set"))
        + label("Account") + group(row("server-cog", "Configure Wallabag server", `data-action="ex-wb" data-arg="setup"`, { chev: true }) + row("info", "Info", `data-open="info" data-params="${A.attrs({ title: "Wallabag", icon: "newspaper", body: "Wallabag is a self-hostable read-it-later service. Leaf downloads unread articles as EPUBs and sends back what you finished." })}"`, { chev: true })),
        syncing ? `<button class="ko-btn grow" data-action="ex-wb" data-arg="account">${I("square", "sm")}Stop</button>` : `<button class="ko-btn ko-btn--primary grow" data-action="ex-wb" data-arg="syncing">${I("refresh-cw", "sm")}Sync now</button>`);
    },
  });
  A.action("ex-wb", (el) => setTopParams({ state: el.dataset.arg }));

  /* ---- cloud storage ---- */
  const ACCTS = [
    { k: "dropbox", n: "Dropbox", ic: "box", sub: "/Apps/KOReader", sync: "2 days ago" },
    { k: "webdav", n: "Nextcloud", ic: "cloud", sub: "WebDAV · cloud.home.lan", sync: "last week" },
    { k: "ftp", n: "Home NAS", ic: "hard-drive", sub: "FTP · 192.168.1.5/books", sync: "never" },
  ];
  const CFILES = {
    "": [["d", "Books", "38 items"], ["d", "Comics", "12 items"], ["d", "Papers", "21 items"], ["f", "reading-list.txt", "2 KB", "synced"], ["f", "Kindle_User_Guide.pdf", "2.4 MB", ""]],
    Books: [["d", "Series", "9 items"], ["f", "The Picture of Dorian Gray.epub", "1.1 MB", "synced"], ["f", "Heart of Darkness.epub", "0.5 MB", "synced"], ["f", "Beyond Good and Evil.epub", "0.8 MB", ""], ["f", "The Republic.pdf", "4.2 MB", ""], ["f", "Persuasion.epub", "0.7 MB", "new"]],
  };
  const pageHead = (title, crumb, backAttrs, actions = "") => `${A.statusBar({ left: title })}<header class="ko-header ko-header--page ex-head"><button class="ko-icon-btn mn-back" ${backAttrs} aria-label="Back">${I("arrow-left")}</button><div class="grow"><div class="ko-crumbs"><span>${crumb}</span></div><div class="ko-page-title ex-title">${title}</div></div>${actions}</header>`;
  A.overlay("cloud", {
    layer: "page",
    render(p) {
      const ac = ACCTS.find((a) => a.k === p.acct);
      if (!ac) {
        return `<div class="ko-page ex-view ex-cloud${still()}">${pageHead("Cloud storage", "Tools", "data-close")}<div class="ko-scroll ex-body">
          ${label("Accounts")}${group(ACCTS.map((a) => `<button class="ko-row mn-row" data-action="ex-cl" data-arg="${a.k}"><span class="ko-icon-tile">${I(a.ic)}</span><span class="label"><span class="t">${a.n}</span><span class="sub ellipsis">${a.sub}</span></span><span class="value">Synced ${a.sync}</span>${I("chevron-right", "chev sm")}</button>`).join(""))}
          ${label("Add account")}<div class="ex-tiles">${[["box", "Dropbox", "App folder access"], ["cloud", "WebDAV", "Nextcloud, ownCloud"], ["hard-drive", "FTP", "NAS or server"]].map(([ic, n, d]) => `<button class="ex-tile" data-open="input" data-params="${A.attrs({ title: `Add ${n} account`, hint: n === "Dropbox" ? "Account name" : "Server address", ok: "Next" })}"><span class="ko-icon-tile">${I(ic)}</span><b>${n}</b><span>${d}</span></button>`).join("")}</div>
          <div class="ex-pad ex-hint">${I("info", "sm")}Downloaded books go to Books/Cloud and keep their reading progress.</div><div class="ex-end"></div></div></div>`;
      }
      const path = String(p.path || ""), files = CFILES[path] || CFILES.Books;
      const rows = files.map(([t, n, s, st]) => t === "d"
        ? `<button class="ko-row mn-row ex-cf" data-action="ex-cl" data-arg="${ac.k}|${path ? path + "/" : ""}${n}"><span class="ex-cfi folder">${I("folder")}</span><span class="label"><span class="t">${n}</span><span class="sub">${s}</span></span>${I("chevron-right", "chev sm")}</button>`
        : `<div class="ko-row mn-row ex-cf"><span class="ex-cfi">${I(/\.pdf$/.test(n) ? "file-text" : /\.txt$/.test(n) ? "file-type" : "book")}</span><span class="label"><span class="t ellipsis">${n}</span><span class="sub">${s}${st === "new" ? " · new on server" : ""}</span></span>${st === "synced" ? `<span class="ex-st">${I("circle-check", "sm")}On device</span>` : `<button class="ko-btn ex-cdl" data-toast="Downloading ${esc(n)}">${I("download", "sm")}Get</button>`}</div>`).join("");
      const crumb = ["Cloud storage", ac.n].concat(path ? path.split("/").slice(0, -1) : []).join(" › ");
      const up = `data-action="ex-cl" data-arg="${path ? `${ac.k}|${path.split("/").slice(0, -1).join("/")}` : ""}"`;
      return `<div class="ko-page ex-view ex-cloud${still()}">${pageHead(path ? path.split("/").pop() : ac.n, esc(crumb), up, `<button class="ko-icon-btn" data-toast="Refreshed" aria-label="Refresh">${I("refresh-cw")}</button>`)}
        <div class="ko-scroll ex-body"><div class="ex-pad ex-hint">${I(ac.ic, "sm")}${ac.n} · ${ac.sub}</div>${group(rows)}<div class="ex-end"></div></div>
        <div class="ko-pager ex-foot"><span class="num ellipsis">${files.length} items · saved to Books/Cloud</span><span class="grow"></span><button class="ko-btn ko-btn--primary" data-toast="Synchronizing · 3 new files">${I("refresh-ccw", "sm")}Sync folder</button></div></div>`;
    },
  });
  A.action("ex-cl", (el) => { const [acct, path] = (el.dataset.arg || "").split("|"); setTopParams({ acct: acct || "", path: path || "" }); });

  /* ---- text editor ---- */
  const TE_TEXT = `# Reading notes, November

Animal Farm (EN-AR)
- Chapter II: the commandments, side by side with the Arabic.
- Look up: "conceived", "tyranny".

Meditations
- Book IV, p. 61: very little is needed.

To do
- Send Middlemarch to the Kobo via calibre.
- Back up highlights before the update.`;
  A.overlay("text-editor", {
    layer: "page",
    render(p) {
      if (!p.file) {
        const files = [["notes.txt", "/mnt/onboard", "today", "4 KB"], ["reading-list.md", "/mnt/onboard/Documents", "yesterday", "2 KB"], ["defaults.lua", "/mnt/onboard/.adds/koreader", "Nov 2", "18 KB"], ["styletweaks.css", "/mnt/onboard/.adds/koreader/styletweaks", "Oct 21", "1 KB"]];
        return `<div class="ko-page ex-view ex-te${still()}">${pageHead("Text editor", "Tools", "data-close")}
          <div class="ko-scroll ex-body"><div class="ex-pad ex-btnrow ex-top"><button class="ko-btn grow" data-open="input" data-params="${A.attrs({ title: "New file", hint: "File name", value: "untitled.txt", ok: "Create" })}">${I("file-plus", "sm")}New file</button><button class="ko-btn grow" data-action="ex-te-open">${I("folder-open", "sm")}Open file</button></div>
          ${label("Recent files")}${group(files.map(([n, d, w, s]) => `<button class="ko-row mn-row" data-action="ex-te" data-arg="${n}"><span class="ko-icon-tile">${I(/\.(lua|css)$/.test(n) ? "file-code" : "file-text")}</span><span class="label"><span class="t">${n}</span><span class="sub ellipsis">${d}</span></span><span class="value">${w} · ${s}</span></button>`).join(""))}
          ${label("Editor settings")}${group(tgRow("type", "Use monospace font", "te.mono", true) + stepRow("a-large-small", "Text font size", "te.fs", 16, 12, 28) + tgRow("keyboard", "Show keyboard on start", "te.kb", true) + tgRow("pilcrow", "Auto paragraph direction", "te.dir", true) + tgRow("qr-code", "Enable QR code export", "te.qr", false))}<div class="ex-end"></div></div></div>`;
      }
      const lines = TE_TEXT.split("\n"), cur = 4;
      return `<div class="ko-page ex-view ex-te ex-te-ed${still()}">${A.statusBar({ left: "Text editor" })}
        <header class="ex-te-head"><button class="ko-icon-btn" data-action="ex-te" data-arg="" aria-label="Back">${I("arrow-left")}</button>
          <div class="grow"><div class="ex-te-n"><span class="ellipsis">${esc(p.file)}</span><span class="ko-pill ko-pill--tint ex-tag">Edited</span></div><div class="ex-te-p ellipsis">/mnt/onboard/${esc(p.file)}</div></div>
          <button class="ko-icon-btn" data-toast="Undo" aria-label="Undo">${I("undo-2")}</button><button class="ko-icon-btn" data-toast="Redo" aria-label="Redo">${I("redo-2")}</button><button class="ko-icon-btn" data-open="input" data-params="${A.attrs({ title: "Find in file", hint: "Text to find", ok: "Find" })}" aria-label="Find">${I("search")}</button>
          <button class="ko-btn ko-btn--primary ex-save" data-toast="Saved ${esc(p.file)}">Save</button></header>
        <div class="ex-te-doc ${S("te.mono", true) ? "mono" : ""}" style="font-size:${S("te.fs", 16) - 2}px">${lines.map((l, i) => `<div class="ex-ln ${i === cur ? "cur" : ""}"><span class="ex-lno num">${i + 1}</span><span class="ex-lt">${esc(l) || "&nbsp;"}${i === cur ? '<i class="ex-caret"></i>' : ""}</span></div>`).join("")}</div>
        <div class="ex-te-bar"><span class="num ellipsis">Ln ${cur + 1}, Col 34 · ${lines.length} lines · UTF-8</span><span class="grow"></span>${["arrow-left", "arrow-up", "arrow-down", "arrow-right"].map((ic) => `<button class="ex-k" aria-label="${ic}">${I(ic, "sm")}</button>`).join("")}<button class="ex-k t">Select</button></div>
        ${A.keyboardHTML({ target: "ex-te" })}</div>`;
    },
  });
  A.action("ex-te", (el) => setTopParams({ file: el.dataset.arg || "" }));
  A.action("ex-te-open", () => { A.closeAll(); A.go("folder", { path: "" }); A.toast("Pick a text file to open"); });

  /* ---- terminal ---- */
  const TERM = [
    ["cmd", "uname -a"], ["out", "Linux kobo 4.9.77 #1 SMP PREEMPT armv7l GNU/Linux"],
    ["cmd", "df -h /mnt/onboard"], ["out", "Filesystem      Size  Used Avail Use% Mounted on"], ["out", "/dev/mmcblk0p3   28G   24G  3.1G  89% /mnt/onboard"],
    ["cmd", "ls /mnt/onboard/Books/Classics | head -4"], ["out", "Animal Farm.epub"], ["out", "Crime and Punishment.epub"], ["out", "Frankenstein.epub"], ["out", "Jane Eyre.epub"],
    ["cmd", "tail -n 2 crash.log"], ["out", "11/19 21:04:12 INFO  Leaf started · KOReader 2026.07.1"], ["out", "11/19 21:04:13 INFO  Wi-Fi connected · Home-5G"],
  ];
  A.overlay("terminal", {
    layer: "page",
    render() {
      const fs = S("term.fs", 14);
      const prompt = `<span class="ex-ps"><b>root@kobo</b>:<i>~/koreader</i>$</span>`;
      return `<div class="ko-page ex-view ex-term${still()}">${A.statusBar({ left: "Terminal" })}
        <header class="ex-te-head"><button class="ko-icon-btn" data-close aria-label="Back">${I("arrow-left")}</button>
          <div class="grow"><div class="ex-te-n">Terminal<span class="ko-pill ko-pill--tint ex-tag">Running</span></div><div class="ex-te-p ellipsis">/bin/bash · buffer 16 kB · font ${fs}</div></div>
          <button class="ko-icon-btn" data-action="ex-term-fs" data-d="-1" aria-label="Smaller text">${I("a-arrow-down")}</button><button class="ko-icon-btn" data-action="ex-term-fs" data-d="1" aria-label="Larger text">${I("a-arrow-up")}</button>
          <button class="ko-btn ex-save" data-open="confirm" data-params="${A.attrs({ title: "End terminal session?", body: "The shell and any running command are stopped.", ok: "End session", icon: "power" })}">${I("power", "sm")}End</button></header>
        <div class="ex-term-scr" style="font-size:${fs}px">${TERM.map(([t, s]) => (t === "cmd" ? `<div>${prompt} ${esc(s)}</div>` : `<div class="o">${esc(s)}</div>`)).join("")}<div>${prompt} <span class="ex-blk"></span></div></div>
        <div class="ex-te-bar ex-term-keys">${["Esc", "Tab", "Ctrl", "Alt", "|", "~", "/"].map((k) => `<button class="ex-k t ${k === "Ctrl" ? "on" : ""}">${k}</button>`).join("")}<span class="grow"></span>${["arrow-left", "arrow-up", "arrow-down", "arrow-right"].map((ic) => `<button class="ex-k" aria-label="${ic}">${I(ic, "sm")}</button>`).join("")}</div>
        ${A.keyboardHTML({ target: "ex-term" })}</div>`;
    },
  });
  A.action("ex-term-fs", (el) => { SET("term.fs", Math.max(10, Math.min(20, S("term.fs", 14) + +el.dataset.d))); redraw(); });

  /* =====================================================================
     MENU LINKS  (App.menuSpecial is the registry exposed by menus.js)
     ===================================================================== */
  const M = A.menuSpecial || (A.menuSpecial = {});
  Object.assign(M, {
    "bookmark browser": () => goFrom("bookmark-browser"),
    "vocabulary builder": () => goFrom("vocab"),
    "dictionary lookup history": () => goFrom("dict-history"),
    "wikipedia history": () => goFrom("wiki-history"),
    "register / login": () => openOver("kosync", { state: S("ks.in", false) ? "account" : "login" }),
    "push progress from this device now": () => { A.closeAll(); A.toast("Progress pushed · page 9 (8%)"); },
    "pull progress from other devices now": () => openOver("kosync-prompt"),
    "opds catalog": () => goFrom("opds"),
    connect: () => openOver("calibre", { state: "searching" }),
    "set alarm": () => { SET("rt.mode", "after"); openOver("read-timer", { mode: "after" }); },
    "set interval": () => { SET("rt.mode", "every"); openOver("read-timer", { mode: "every" }); },
    "stop timer": () => { A.closeAll(); A.toast("Timer stopped"); },
    "cloud storage": () => openOver("cloud"),
    "cloud storage+": () => openOver("cloud"),
    "download new articles from server": () => openOver("wallabag", { state: "syncing" }),
    "configure wallabag server": () => openOver("wallabag", { state: "setup" }),
    info: () => openOver("wallabag"),
    "sync news feeds": () => openOver("news", { state: "fetching" }),
    "edit news feeds": () => openOver("news"),
    "go to news folder": () => { A.closeAll(); A.go("folder", { path: "Books/News" }); },
    "new file": () => { openOver("text-editor"); A.open("input", { title: "New file", hint: "File name", value: "untitled.txt", ok: "Create" }); },
    "open file": () => openOver("text-editor"),
    new: () => openOver("profiles"),
    "new with current book settings": () => { openOver("profiles"); A.open("input", { title: "New profile from this book", hint: "Profile name", value: "Animal Farm setup", ok: "Create" }); },
    "open terminal session (not running)": () => openOver("terminal"),
  });
  /* "Autoturn" is a checkbox row in KOReader's menu that opens its interval dialog: intercept it */
  document.addEventListener("click", (ev) => {
    const r = ev.target.closest && ev.target.closest(".mn-row.is-check");
    if (!r || !/^autoturn\b/.test(r.dataset.label || "") || ev.target.closest(".mn-help")) return;
    ev.stopPropagation(); ev.preventDefault(); openOver("autoturn");
  }, true);

  /* =====================================================================
     DEMOS
     ===================================================================== */
  const H = (s, p = {}, o, op = {}) => {
    const q = new URLSearchParams(); const put = (k, v) => q.set(k, typeof v === "object" ? JSON.stringify(v) : v);
    Object.entries(p).forEach(([k, v]) => put(k, v)); if (o) { q.set("o", o); Object.entries(op).forEach(([k, v]) => put("o." + k, v)); }
    return `#/${s}${[...q].length ? "?" + q : ""}`;
  };
  const RD = { id: "animal-farm" };
  [
    ["Folder actions (long-press)", H("library", { tab: "folders", path: "Books" }, "folder-actions", { path: "Books/Classics" })],
    ["Folder actions · HOME folder", H("folder", { path: "" }, "folder-actions", { path: "Books" })],
    ["Paste conflict", H("folder", { path: "Books/Classics" }, "paste-conflict", { path: "Books/Classics", i: 1, n: 3 })],
    ["Paste conflict · identical files", H("folder", { path: "Books/Classics" }, "paste-conflict", { path: "Books/Classics", i: 2, n: 3 })],
    ["Bookmark browser", H("bookmark-browser")],
    ["Bookmark browser · pick a book", H("bookmark-browser", {}, "ex-books", { k: "bb.book" })],
    ["Vocabulary builder", H("vocab")],
    ["Vocabulary · review card", H("vocab", { mode: "review", i: 0 })],
    ["Vocabulary · review, meaning shown", H("vocab", { mode: "review", i: 1, show: 1 })],
    ["Vocabulary · word options", H("vocab", {}, "ex-vb-word", { i: 7 })],
    ["Vocabulary · settings", H("vocab", {}, "ex-vb-settings")],
    ["Dictionary lookup history", H("dict-history")],
    ["Wikipedia history", H("wiki-history")],
    ["Progress sync · log in", H("reader", RD, "kosync", { state: "login" })],
    ["Progress sync · signed in", H("reader", RD, "kosync", { state: "account" })],
    ["Progress sync · newer position prompt", H("reader", RD, "kosync-prompt")],
    ["OPDS · catalogs", H("opds")],
    ["OPDS · catalog sections", H("opds", { cat: "standard" })],
    ["OPDS · book list", H("opds", { cat: "standard", sec: "new" })],
    ["OPDS · add catalog", H("opds", {}, "ex-opds-edit", { k: "" })],
    ["OPDS · book entry & formats", H("opds", { cat: "standard", sec: "new" }, "opds-book", { cat: "standard", i: 0 })],
    ["OPDS · downloading", H("opds", { cat: "standard", sec: "new" }, "opds-book", { cat: "standard", i: 0, dl: "progress" })],
    ["OPDS · downloaded", H("opds", { cat: "standard", sec: "new" }, "opds-book", { cat: "standard", i: 0, dl: "done" })],
    ["Calibre · searching", H("library", {}, "calibre", { state: "searching" })],
    ["Calibre · connected", H("library", {}, "calibre", { state: "connected" })],
    ["Calibre · receiving books", H("library", {}, "calibre", { state: "receiving" })],
    ["Read timer", H("reader", RD, "read-timer", { mode: "after" })],
    ["Read timer · running", H("reader", RD, "read-timer", { mode: "after", active: 1 })],
    ["Autoturn", H("reader", RD, "autoturn")],
    ["Profiles", H("library", {}, "profiles")],
    ["Profiles · Night reading", H("library", {}, "profiles", { id: "night" })],
    ["News downloader", H("library", {}, "news")],
    ["News downloader · fetching", H("library", {}, "news", { state: "fetching" })],
    ["Wallabag", H("library", {}, "wallabag")],
    ["Wallabag · server setup", H("library", {}, "wallabag", { state: "setup" })],
    ["Cloud storage", H("library", {}, "cloud")],
    ["Cloud storage · Dropbox › Books", H("library", {}, "cloud", { acct: "dropbox", path: "Books" })],
    ["Text editor", H("library", {}, "text-editor")],
    ["Text editor · editing notes.txt", H("library", {}, "text-editor", { file: "notes.txt" })],
    ["Terminal", H("library", {}, "terminal")],
  ].forEach(([l, h]) => A.demo(G, l, h));
})();
