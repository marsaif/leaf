/* ==========================================================================
   Tools · on-screen keyboard + universal search
   --------------------------------------------------------------------------
   Keyboard API (shared with every agent):
     App.keyboardHTML({ layout: "qwerty"|"numeric"|"arabic", target: "field-id", enter: "Search" })
     App.kbField(target, { placeholder, icon, mask, clear, cls, trail })  -> soft filled input bound to target
     App.kbInit(target, value, ownerObject)  -> set the initial value once per owner (e.g. overlay params)
     App.kbValue(target) / App.kbSet(target, value)
     App.kbOn(target, { change(v), enter(v), focus() })                   -> optional hooks
   Enter with no hook clicks the element carrying data-kb-submit="<target>".
   A physical keyboard also types into the topmost on-screen keyboard's target.
   ========================================================================== */
(function () {
  const esc = App.esc;

  /* =====================================================================
     KEYBOARD
     ===================================================================== */
  const KB = (App.kbState = { values: {}, hooks: {}, over: {}, shift: 0, layer: "abc", lastShift: 0, inited: new WeakMap() });

  const AR_DIGITS = [..."١٢٣٤٥٦٧٨٩٠"];
  const SYM2 = [[..."~`|•√π÷×¶∆"], [..."£¥$¢^°={}\\"], [..."%©®™✓[]"]];
  const LAYOUTS = {
    qwerty: {
      name: "English", comma: ",",
      abc: [[..."qwertyuiop"], [..."asdfghjkl"], [..."zxcvbnm"]],
      sym: [[..."1234567890"], [..."@#€_&-+()/"], [..."*\"':;!?"]],
      sym2: SYM2,
    },
    arabic: {
      name: "العربية", comma: "،",
      abc: [[..."ضصثقفغعهخحجد"], [..."شسيبلاتنمكطذ"], [..."ئءؤرىةوزظ"]],
      shift: [["َ", "ً", "ُ", "ٌ", "ِ", "ٍ", "ْ", "ّ", "ـ", "«", "»", "؟"], ["أ", "إ", "آ", "ٱ", "لا", "لأ", "لإ", "لآ", "؛", "،", ":", "!"], ["ذ", "ئ", "ء", "ؤ", "ة", "ى", "٫", "…", "-"]],
      sym: [AR_DIGITS, [..."@#_&-+()/٪"], [..."*\"':؛!؟"]],
      sym2: SYM2,
    },
  };

  App.kbValue = (t) => String(KB.values[t] ?? "");
  App.kbOn = (t, hooks) => { KB.hooks[t] = Object.assign(KB.hooks[t] || {}, hooks); };
  App.kbInit = (t, value, owner) => {
    let set = KB.inited.get(owner);
    if (!set) KB.inited.set(owner, (set = new Set()));
    if (set.has(t)) return;
    set.add(t);
    KB.values[t] = String(value ?? "");
    delete KB.over[t];
    KB.shift = 0; KB.layer = "abc";
  };
  App.kbSet = (t, v) => { KB.values[t] = String(v); paint(t); KB.hooks[t]?.change?.(KB.values[t]); };

  const isRTL = (v) => /^[^A-Za-z]*[؀-ۿ]/.test(v);
  function paint(t) {
    const v = App.kbValue(t);
    document.querySelectorAll(".kb-field").forEach((f) => {
      if (f.dataset.kbField !== t) return;
      f.querySelector(".kb-val").textContent = f.dataset.mask === "1" ? "•".repeat([...v].length) : v;
      f.classList.toggle("empty", !v);
      f.dir = isRTL(v) ? "rtl" : "ltr";
      const box = f.querySelector(".kb-text");
      box.classList.remove("long");
      if (box.scrollWidth > box.clientWidth + 1) box.classList.add("long");
    });
  }
  App.kbPaint = paint;

  /** soft, filled input bound to a keyboard target */
  App.kbField = (t, o = {}) => {
    const v = App.kbValue(t);
    const shown = o.mask ? "•".repeat([...v].length) : v;
    return `<div class="kb-field ${o.cls || ""} ${v ? "" : "empty"}" dir="${isRTL(v) ? "rtl" : "ltr"}" data-kb-field="${esc(t)}" data-mask="${o.mask ? 1 : 0}" data-action="kb-focus" data-arg="${esc(t)}">
      ${o.icon ? `<span class="kb-icon">${App.icon(o.icon)}</span>` : ""}
      <span class="kb-text"><span class="kb-val" dir="auto">${esc(shown)}</span><i class="kb-caret"></i><span class="kb-ph">${esc(o.placeholder || "")}</span></span>
      ${o.clear === false ? "" : `<button class="kb-clear" data-action="kb-clear" data-arg="${esc(t)}" aria-label="Clear">${App.icon("x", "sm")}</button>`}
      ${o.trail || ""}
    </div>`;
  };

  const key = (k, label, cls = "", grow) =>
    `<button class="kb-key ${cls}" data-action="kb-key" data-k="${esc(k)}"${grow ? ` style="flex-grow:${grow}"` : ""}>${label}</button>`;
  const gap = (g = 0.5) => `<span class="kb-gap" style="flex-grow:${g}"></span>`;
  const labelOf = (k, upper) => (/^\p{M}$/u.test(k) ? "ـ" + k : upper ? k.toUpperCase() : k);

  /** the e-ink keyboard */
  App.keyboardHTML = (opts = {}) => {
    const target = opts.target || "keyboard";
    const base = opts.layout || "qwerty";
    const layout = KB.over[target] || base;
    const enterLabel = opts.enter ? `<span class="kb-enter-t">${esc(opts.enter)}</span>` : App.icon("corner-down-left");
    const data = `data-target="${esc(target)}" data-layout="${esc(base)}" data-enter="${esc(opts.enter || "")}"`;

    if (layout === "numeric") {
      const n = (k) => key(k, k, "kb-num");
      return `<div class="kb kb-numeric" ${data} dir="ltr"><div class="kb-pad">
        ${n("1")}${n("2")}${n("3")}${key("bksp", App.icon("delete"), "kb-fn")}
        ${n("4")}${n("5")}${n("6")}${key("%", "%", "kb-fn")}
        ${n("7")}${n("8")}${n("9")}${key("enter", enterLabel, "kb-enter kb-tall")}
        ${key("-", "−", "kb-fn")}${n("0")}${key(".", ".", "kb-fn")}
      </div></div>`;
    }

    const L = LAYOUTS[layout] || LAYOUTS.qwerty;
    const ar = layout === "arabic";
    const layer = KB.layer;
    let rows;
    if (layer === "abc") rows = ar && KB.shift ? L.shift : L.abc;
    else rows = layer === "sym" ? L.sym : L.sym2;
    const upper = !ar && layer === "abc" && KB.shift > 0;
    const keys = (r) => r.map((k) => key(k, esc(labelOf(k, upper)), ar && layer === "abc" ? "kb-ar" : "")).join("");

    let r3lead;
    if (layer === "abc") {
      const ic = KB.shift === 2 ? "arrow-big-up-dash" : "arrow-big-up";
      r3lead = key("shift", App.icon(ic), `kb-fn kb-shift ${KB.shift === 1 ? "on" : ""} ${KB.shift === 2 ? "caps" : ""}`, 1.5);
    } else r3lead = key(layer === "sym" ? "sym2" : "sym", layer === "sym" ? "=\\&lt;" : "?123", "kb-fn kb-t", 1.5);

    const row2 = rows[1].length < rows[0].length ? gap() + keys(rows[1]) + gap() : keys(rows[1]);
    const r3 = rows[2];
    const r3pad = Math.max(0, rows[0].length - 3 - r3.length);
    const toggle = layer === "abc" ? key("sym", ar ? "?١٢٣" : "?123", "kb-fn kb-t", 1.5) : key("abc", ar ? "أبج" : "ABC", "kb-fn kb-t", 1.5);

    return `<div class="kb ${ar ? "is-ar" : ""}" ${data} dir="ltr">
      <div class="kb-row">${keys(rows[0])}</div>
      <div class="kb-row">${row2}</div>
      <div class="kb-row">${r3lead}${r3pad ? gap(r3pad / 2) : ""}${keys(r3)}${r3pad ? gap(r3pad / 2) : ""}${key("bksp", App.icon("delete"), "kb-fn", 1.5)}</div>
      <div class="kb-row">
        ${toggle}${key("globe", App.icon("globe"), "kb-fn", 1.1)}${key(L.comma, L.comma, "kb-p")}
        ${key("space", `<span class="kb-lang">${esc(L.name)}</span>`, "kb-space", 5)}
        ${key(".", ".", "kb-p")}${key("enter", enterLabel, "kb-enter", 2)}
      </div>
    </div>`;
  };

  function redrawKeyboards(target) {
    document.querySelectorAll(".kb").forEach((kb) => {
      if (kb.dataset.target !== target) return;
      const tmp = document.createElement("div");
      tmp.innerHTML = App.keyboardHTML({ layout: kb.dataset.layout, target, enter: kb.dataset.enter || undefined });
      kb.replaceWith(tmp.firstElementChild);
    });
    App.icons();
  }

  function press(kb, k) {
    const t = kb.dataset.target;
    let v = App.kbValue(t);
    const layout = KB.over[t] || kb.dataset.layout;
    switch (k) {
      case "shift": {
        const now = Date.now();
        KB.shift = KB.shift === 0 ? 1 : KB.shift === 1 && now - KB.lastShift < 400 ? 2 : 0;
        KB.lastShift = now;
        return redrawKeyboards(t);
      }
      case "sym": case "sym2": case "abc": KB.layer = k === "abc" ? "abc" : k; KB.shift = 0; return redrawKeyboards(t);
      case "globe": KB.over[t] = layout === "arabic" ? "qwerty" : "arabic"; KB.layer = "abc"; KB.shift = 0; return redrawKeyboards(t);
      case "enter": return enter(t);
      case "bksp": v = [...v].slice(0, -1).join(""); break;
      case "space": v += " "; break;
      default:
        v += layout !== "arabic" && KB.layer === "abc" && KB.shift ? k.toUpperCase() : k;
        if (KB.shift === 1) { KB.shift = 0; App.kbSet(t, v); return redrawKeyboards(t); }
    }
    App.kbSet(t, v);
  }
  function enter(t) {
    const h = KB.hooks[t];
    if (h?.enter) return h.enter(App.kbValue(t));
    const btn = [...document.querySelectorAll("[data-kb-submit]")].reverse().find((b) => b.dataset.kbSubmit === t);
    if (btn) return btn.click();
    if (App.top()?.name === "keyboard") App.close();
  }

  App.action("kb-key", (el) => press(el.closest(".kb"), el.dataset.k));
  App.action("kb-clear", (el) => App.kbSet(el.dataset.arg, ""));
  App.action("kb-focus", (el) => KB.hooks[el.dataset.arg]?.focus?.());

  // e-ink press feedback: invert the key while the finger is down
  document.addEventListener("pointerdown", (e) => {
    const k = e.target.closest?.(".kb-key"); if (!k) return;
    k.classList.add("down");
    const up = () => { setTimeout(() => k.classList.remove("down"), 90); window.removeEventListener("pointerup", up); };
    window.addEventListener("pointerup", up);
  });
  // a physical keyboard types into the topmost on-screen keyboard
  document.addEventListener("keydown", (e) => {
    if (e.ctrlKey || e.metaKey || e.altKey || e.target.matches?.("input,textarea,[contenteditable]")) return;
    const all = document.querySelectorAll(".ko-screen .kb"); const kb = all[all.length - 1];
    if (!kb) return;
    const t = kb.dataset.target;
    if (e.key === "Backspace") { e.preventDefault(); App.kbSet(t, [...App.kbValue(t)].slice(0, -1).join("")); }
    else if (e.key === "Enter") { e.preventDefault(); enter(t); }
    else if (e.key.length === 1) { e.preventDefault(); App.kbSet(t, App.kbValue(t) + e.key); }
  });

  /* standalone keyboard overlay (docked, with its own field strip) */
  App.overlay("keyboard", {
    title: "Keyboard", layer: "sheet", clear: true,
    render(p) {
      const t = p.target || "keyboard";
      App.kbInit(t, p.value ?? "", p);
      return `<div class="kb-sheet">
        <div class="kb-strip">
          ${App.kbField(t, { placeholder: p.hint || "Type here", cls: "kb-strip-field" })}
          <button class="ko-btn ko-btn--primary kb-done" data-close>${esc(p.ok || "Done")}</button>
        </div>
        ${App.keyboardHTML({ layout: p.layout || "qwerty", target: t })}
      </div>`;
    },
  });

  /* =====================================================================
     SEARCH
     ===================================================================== */
  // remember where search/stats were opened from so "back" returns there
  let prev = { name: "home", params: {} };
  document.addEventListener("folio:navigate", () => {
    const c = App.current;
    if (c.name !== "search" && c.name !== "stats") prev = { name: c.name, params: c.params };
  });
  App.action("tools-back", () => App.go(prev.name, prev.params));

  const SCOPES = [["all", "All"], ["titles", "Titles"], ["authors", "Authors"], ["series", "Series"], ["folders", "Folders"], ["fulltext", "Full text"], ["book", "In this book"]];
  const fold = (s) => String(s).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  const has = (t, q) => fold(t).includes(fold(q));
  const first = (a) => a.split(";")[0].trim();

  /** highlight q inside text (accent/diacritic-insensitive), escaping everything else */
  function hl(text, q) {
    text = String(text ?? "");
    const nq = fold(q || "");
    if (!nq) return esc(text);
    let f = ""; const map = [];
    for (let i = 0; i < text.length; i++) for (const ch of fold(text[i])) { f += ch; map.push(i); }
    let out = "", last = 0, idx = f.indexOf(nq);
    while (idx !== -1) {
      const s = map[idx], e = map[idx + nq.length - 1] + 1;
      if (s >= last) { out += esc(text.slice(last, s)) + `<mark>${esc(text.slice(s, e))}</mark>`; last = e; }
      idx = f.indexOf(nq, idx + nq.length);
    }
    return out + esc(text.slice(last));
  }
  App.searchHighlight = hl;

  /* ---------- data ---------- */
  const push = (m, k, v) => { if (!m.has(k)) m.set(k, []); m.get(k).push(v); };
  function catalog(q) {
    const B = DB.BOOKS;
    const titles = B.filter((b) => !q || has(b.title, q));
    const byAuthor = q ? B.filter((b) => !has(b.title, q) && (has(b.author, q) || (b.series && has(b.series[0], q)))) : [];
    const am = new Map(); B.forEach((b) => push(am, first(b.author), b));
    const authors = [...am].filter(([a]) => !q || has(a, q)).map(([name, books]) => ({ name, books }));
    const sm = new Map(); B.forEach((b) => b.series && push(sm, b.series[0], b));
    const series = [...sm].filter(([s]) => !q || has(s, q)).map(([name, books]) => ({ name, books: books.sort((a, b) => a.series[1] - b.series[1]) }));
    const folders = DB.FOLDERS.filter((f) => !q || has(f.name, q));
    return { books: [...titles, ...byAuthor], titles, authors, series, folders };
  }

  const opt = (k) => !!App.get("search." + k, false);
  function ftRegex(q) {
    let src = opt("regex") ? q : q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (opt("word")) src = `\\b(?:${src})\\b`;
    try { return new RegExp(src, opt("case") ? "g" : "gi"); } catch { return null; }
  }
  function markAll(text, re) {
    let out = "", last = 0;
    for (const m of text.matchAll(re)) {
      if (!m[0]) continue;
      out += esc(text.slice(last, m.index)) + `<mark>${esc(m[0])}</mark>`; last = m.index + m[0].length;
    }
    return out + esc(text.slice(last));
  }
  function snippet(p, m, re) {
    let s = Math.max(0, m.index - 64), e = Math.min(p.length, m.index + m[0].length + 110);
    if (s > 0) s = p.indexOf(" ", s) + 1 || s;
    if (e < p.length) { const sp = p.lastIndexOf(" ", e); if (sp > m.index + m[0].length) e = sp; }
    return (s > 0 ? "…" : "") + markAll(p.slice(s, e), re) + (e < p.length ? "…" : "");
  }
  const ftCache = new Map();
  function fulltext(q, ids, allChapters) {
    const k = [q, ids.join(","), allChapters, opt("case"), opt("word"), opt("regex")].join("|");
    if (ftCache.has(k)) return ftCache.get(k);
    const re = q.length >= 2 ? ftRegex(q) : null;
    const res = { total: 0, groups: [], error: !re && q.length >= 2 };
    if (re) for (const id of ids) {
      const book = DB.book(id), chs = TextGen.chapters(id);
      const g = { book, count: 0, hits: [] };
      chs.slice(0, allChapters ? chs.length : 2).forEach((ch, ci) => {
        TextGen.chapter(id, ci).forEach((p, pi) => {
          const ms = [...p.matchAll(re)].filter((m) => m[0]);
          if (!ms.length) return;
          g.count += ms.length;
          g.hits.push({ ch: ch.title, ci, page: ch.page + Math.floor((pi * 11) / 14), html: snippet(p, ms[0], re), n: ms.length });
        });
      });
      if (g.count) { res.total += g.count; res.groups.push(g); }
    }
    ftCache.set(k, res);
    return res;
  }
  const libraryIds = () => DB.BOOKS.filter((b) => b.lang !== "ar").map((b) => b.id);
  const currentBook = (p) => DB.book(p.id || DB.current().id);
  const n = (x) => x.toLocaleString("en-US");

  function counts(p) {
    const q = String(p.q ?? "").trim();
    if (!q) return null;
    const c = catalog(q);
    const ft = q.length >= 2 ? fulltext(q, libraryIds(), false).total : 0;
    const bk = q.length >= 2 ? fulltext(q, [currentBook(p).id], true).total : 0;
    return { all: c.books.length + c.authors.length + c.series.length + c.folders.length + ft, titles: c.titles.length, authors: c.authors.length, series: c.series.length, folders: c.folders.length, fulltext: ft, book: bk };
  }

  /* ---------- rendering pieces ---------- */
  const thumb = (b) => `<div class="sr-thumb">${Cover.html(b)}</div>`;
  const badge = (b) => (b.progress ? (b.progress >= 100 ? App.icon("check", "sm") : b.progress + "%") : "");
  function status(b) {
    if (b.progress >= 100) return `<span class="sr-state done">${App.icon("check", "sm")}Finished</span>`;
    if (!b.progress) return `<span class="sr-state new">New</span>`;
    return `<span class="sr-state"><span class="sr-mini">${App.progress(b.progress)}</span>${b.progress}%</span>`;
  }
  const bookRow = (b, q) => `
    <div class="sr-item sr-book" ${b.lang === "ar" ? 'dir="rtl"' : ""} role="button" data-open="book-details" data-params='${App.attrs({ id: b.id })}'>
      ${thumb(b)}
      <div class="grow">
        <div class="sr-title ellipsis" dir="auto">${hl(b.title, q)}</div>
        <div class="sr-sub ellipsis" dir="auto">${hl(first(b.author), q)}${b.series ? ` · ${hl(b.series[0], q)} #${b.series[1]}` : ""}</div>
        <div class="sr-meta">${status(b)}<span class="ko-pill ko-pill--caps ko-pill--sm sr-fmt">${b.format.toUpperCase()}</span><span>${b.size}</span></div>
      </div>
      <button class="ko-btn ko-btn--sm sr-open" data-go="reader" data-params='${App.attrs({ id: b.id })}' aria-label="Read">${App.icon("book-open", "sm")}<span>${b.progress && b.progress < 100 ? "Resume" : "Open"}</span></button>
    </div>`;
  const initials = (name) => (/[؀-ۿ]/.test(name) ? name.trim()[0] : name.replace(/[^A-Za-z ]/g, " ").split(/\s+/).filter(Boolean).map((w) => w[0]).filter((c) => c === c.toUpperCase()).slice(0, 2).join(""));
  const stack = (books) => `<span class="sr-stack">${books.slice(0, 3).map((b) => `<span>${Cover.html(b)}</span>`).join("")}</span>`;
  const authorRow = (a, q, expand) => {
    const reading = a.books.filter((b) => b.progress && b.progress < 100).length;
    return `<div class="sr-item sr-author" ${/[\u0600-\u06FF]/.test(a.name) ? 'dir="rtl"' : ""} role="button" data-action="sr-q" data-arg="${esc(a.name)}" data-scope="titles">
      <span class="sr-mono" dir="auto">${esc(initials(a.name))}</span>
      <div class="grow"><div class="sr-title ellipsis" dir="auto">${hl(a.name, q)}</div>
        <div class="sr-sub">${a.books.length} book${a.books.length > 1 ? "s" : ""}${reading ? ` · ${reading} in progress` : ""}</div></div>
      ${expand && a.books.length > 1 ? "" : stack(a.books)}
      ${App.icon("chevron-right", "sm chev")}
    </div>${expand && a.books.length > 1 ? `<div class="sr-shelf">${a.books.map((b) => `<button class="sr-shelf-b" data-open="book-details" data-params='${App.attrs({ id: b.id })}'>${Cover.html(b, { badge: badge(b) })}<span class="ellipsis" dir="auto">${esc(b.title)}</span></button>`).join("")}</div>` : ""}`;
  };
  const seriesRow = (s, q) => {
    const done = s.books.filter((b) => b.progress >= 100).length;
    return `<div class="sr-item" role="button" data-go="collection" data-params='${App.attrs({ name: s.name })}'>
      <span class="ko-icon-tile ko-icon-tile--xl ko-icon-tile--plain sr-tile">${App.icon("layers")}</span>
      <div class="grow"><div class="sr-title ellipsis">${hl(s.name, q)}</div>
        <div class="sr-sub">${s.books.length} books · ${done} of ${s.books.length} finished</div></div>
      ${stack(s.books)}${App.icon("chevron-right", "sm chev")}
    </div>`;
  };
  const folderRow = (f, q) => `
    <div class="sr-item" role="button" data-go="library" data-params='${App.attrs({ folder: f.name })}'>
      <span class="ko-icon-tile ko-icon-tile--xl ko-icon-tile--plain sr-tile">${App.icon(f.count ? "folder" : "folder-open")}</span>
      <div class="grow"><div class="sr-title ellipsis" dir="auto">${hl(f.name, q)}</div>
        <div class="sr-sub ellipsis">${f.count ? `${f.count} book${f.count > 1 ? "s" : ""}` : "Empty"} · modified ${esc(f.modified)}</div></div>
      <span class="sr-path">/books/${esc(f.name)}</span>${App.icon("chevron-right", "sm chev")}
    </div>`;
  const hitRow = (b, h, showBook) => `
    <button class="ko-card ko-card--sm ko-card--tap sr-hit" data-go="reader" data-params='${App.attrs({ id: b.id, page: h.page })}'>
      <span class="sr-hit-loc">${showBook ? `<b>${esc(b.title)}</b><i></i>` : ""}<span>${esc(h.ch)}</span><i></i><span>p. ${h.page}</span>${h.n > 1 ? `<i></i><span>${h.n} matches</span>` : ""}</span>
      <span class="sr-hit-text">${h.html}</span>
    </button>`;
  const sec = (label, count, more) => `<div class="ko-section-label sr-sec"><span>${label}</span>${count != null ? `<span class="sr-count num">${n(count)}</span>` : ""}<span class="spacer"></span>${more || ""}</div>`;
  const seeAll = (scope, total, shown) => (total > shown ? `<button class="ko-link sr-link" data-action="sr-scope" data-arg="${scope}">See all ${n(total)}${App.icon("arrow-right", "sm")}</button>` : "");

  function optionsRow() {
    const o = (k, ic, label) => `<button class="sr-opt ${opt(k) ? "on" : ""}" data-action="sr-opt" data-arg="${k}">${App.check(opt(k))}${App.icon(ic, "sm")}${label}</button>`;
    return `<div class="sr-opts">${o("case", "case-sensitive", "Match case")}${o("word", "whole-word", "Whole words")}${o("regex", "regex", "Regex")}</div>`;
  }
  const empty = (icon, title, sub, actions = "") =>
    `<div class="sr-empty"><span class="sr-empty-ico">${App.icon(icon)}</span><div class="sr-empty-t">${title}</div><div class="sr-empty-s">${sub}</div>${actions ? `<div class="sr-empty-a">${actions}</div>` : ""}</div>`;

  function idleHTML() {
    const recent = DB.SEARCH_HISTORY;
    const c = catalog("");
    const tile = (scope, icon, label, count) => `<button class="ko-card ko-card--tap sr-browse-t" data-action="sr-scope" data-arg="${scope}"><span class="ko-icon-tile ko-icon-tile--xl ko-icon-tile--plain sr-tile">${App.icon(icon)}</span><span class="grow"><b>${label}</b><span>${count}</span></span></button>`;
    const hist = DB.HISTORY.slice(0, 8).map((id) => DB.book(id));
    return `
      ${recent.length ? `<section class="sr-block">${sec("Recent searches", null, `<button class="ko-link sr-link" data-action="sr-clear-history">Clear</button>`)}
        <div class="sr-chips">${recent.map((t) => `<button class="ko-chip ko-chip--lg sr-chip" data-action="sr-q" data-arg="${esc(t)}">${App.icon("history", "sm")}<span dir="auto">${esc(t)}</span></button>`).join("")}</div></section>` : ""}
      <section class="sr-block">${sec("Browse your library")}
        <div class="sr-browse">
          ${tile("titles", "book-copy", "Titles", `${c.titles.length} books`)}
          ${tile("authors", "user-round", "Authors", `${c.authors.length} authors`)}
          ${tile("series", "layers", "Series", `${c.series.length} series`)}
          ${tile("folders", "folder", "Folders", `${c.folders.length} folders`)}
        </div></section>
      <section class="sr-block">${sec("Recently opened")}
        <div class="sr-recent">${hist.map((b) => `<button class="sr-recent-b" data-open="book-details" data-params='${App.attrs({ id: b.id })}'>${Cover.html(b, { badge: badge(b) })}</button>`).join("")}</div></section>
      <p class="sr-tip">${App.icon("lightbulb", "sm")}<span><b>Full text</b> looks inside every book; <b>In this book</b> searches the one you are reading.</span></p>`;
  }

  function bodyHTML(p) {
    const q = String(p.q ?? "").trim();
    const scope = p.scope || "all";
    const c = catalog(q);

    if (scope === "book" || scope === "fulltext") {
      const head = scope === "book" ? (() => { const b = currentBook(p); return `<div class="ko-card sr-inbook">${thumb(b)}<div class="grow"><div class="ko-eyebrow sr-eyebrow">Searching in</div><div class="sr-title ellipsis">${esc(b.title)}</div><div class="sr-sub">${esc(first(b.author))} · ${b.pages} pages · ${TextGen.chapters(b.id).length} chapters</div></div></div>`; })() : "";
      if (q.length < 2) return head + optionsRow() + empty("text-search", scope === "book" ? "Search inside this book" : "Search inside every book", "Type at least two letters. Matches appear in context, with chapter and page.");
      const ids = scope === "book" ? [currentBook(p).id] : libraryIds();
      const ft = fulltext(q, ids, scope === "book");
      if (ft.error) return head + optionsRow() + empty("regex", "Invalid regular expression", "Check the pattern, or turn off Regex to search for the literal text.");
      if (!ft.total) return head + optionsRow() + noResults(q, scope);
      if (scope === "book") {
        const g = ft.groups[0], byCh = new Map();
        g.hits.forEach((h) => push(byCh, h.ch, h));
        return head + optionsRow() + `<div class="sr-summary"><b class="num">${n(ft.total)}</b> matches for “${esc(q)}” in ${byCh.size} chapters</div>` +
          [...byCh].map(([ch, hs]) => `<section class="sr-block">${sec(esc(ch), hs.reduce((a, h) => a + h.n, 0), `<span class="sr-pp">p. ${hs[0].page}–${hs[hs.length - 1].page}</span>`)}
            <div class="sr-hits">${hs.slice(0, 3).map((h) => hitRow(g.book, h, false)).join("")}</div>
            ${hs.length > 3 ? `<button class="ko-link sr-link sr-more" data-go="reader" data-params='${App.attrs({ id: g.book.id, page: hs[3].page })}'>${hs.length - 3} more in ${esc(ch)}${App.icon("arrow-right", "sm")}</button>` : ""}</section>`).join("");
      }
      return optionsRow() + `<div class="sr-summary"><b class="num">${n(ft.total)}</b> matches for “${esc(q)}” in ${ft.groups.length} books</div>` +
        ft.groups.slice(0, 8).map((g) => `<section class="sr-block sr-ftbook">
          <div class="sr-ft-head" role="button" data-open="book-details" data-params='${App.attrs({ id: g.book.id })}'>${thumb(g.book)}<div class="grow"><div class="sr-title ellipsis">${esc(g.book.title)}</div><div class="sr-sub">${esc(first(g.book.author))}</div></div><span class="sr-count num">${n(g.count)}</span></div>
          <div class="sr-hits">${g.hits.slice(0, 2).map((h) => hitRow(g.book, h, false)).join("")}</div></section>`).join("") +
        (ft.groups.length > 8 ? `<div class="sr-foot">${ft.groups.length - 8} more books contain “${esc(q)}”</div>` : "");
    }

    if (!q) {
      if (scope === "all") return idleHTML();
      if (scope === "titles") return sec("All books A–Z", c.titles.length) + `<div class="sr-list">${[...c.titles].sort((a, b) => a.title.localeCompare(b.title)).map((b) => bookRow(b, "")).join("")}</div>`;
      if (scope === "authors") return sec("All authors", c.authors.length) + `<div class="sr-list">${c.authors.sort((a, b) => a.name.localeCompare(b.name)).map((a) => authorRow(a, "")).join("")}</div>`;
      if (scope === "series") return sec("All series", c.series.length) + `<div class="sr-list">${c.series.map((s) => seriesRow(s, "")).join("")}</div>`;
      if (scope === "folders") return sec("All folders", c.folders.length) + `<div class="sr-list">${c.folders.map((f) => folderRow(f, "")).join("")}</div>`;
    }

    if (scope === "titles") return c.titles.length ? sec("Titles", c.titles.length) + `<div class="sr-list">${c.titles.map((b) => bookRow(b, q)).join("")}</div>` : noResults(q, scope);
    if (scope === "authors") return c.authors.length ? sec("Authors", c.authors.length) + `<div class="sr-list">${c.authors.map((a) => authorRow(a, q, true)).join("")}</div>` : noResults(q, scope);
    if (scope === "series") return c.series.length ? sec("Series", c.series.length) + `<div class="sr-list">${c.series.map((s) => seriesRow(s, q)).join("")}</div>` : noResults(q, scope);
    if (scope === "folders") return c.folders.length ? sec("Folders", c.folders.length) + `<div class="sr-list">${c.folders.map((f) => folderRow(f, q)).join("")}</div>` : noResults(q, scope);

    // all
    const ft = q.length >= 2 ? fulltext(q, libraryIds(), false) : { total: 0, groups: [] };
    const total = c.books.length + c.authors.length + c.series.length + c.folders.length + ft.total;
    if (!total) return noResults(q, scope);
    let html = `<div class="sr-summary"><b class="num">${n(total)}</b> results for “${esc(q)}”</div>`;
    if (c.books.length) html += `<section class="sr-block">${sec("Books", c.books.length, seeAll("titles", c.books.length, 4))}<div class="sr-list">${c.books.slice(0, 4).map((b) => bookRow(b, q)).join("")}</div></section>`;
    if (c.authors.length) html += `<section class="sr-block">${sec("Authors", c.authors.length, seeAll("authors", c.authors.length, 3))}<div class="sr-list">${c.authors.slice(0, 3).map((a) => authorRow(a, q)).join("")}</div></section>`;
    if (c.series.length) html += `<section class="sr-block">${sec("Series", c.series.length)}<div class="sr-list">${c.series.map((s) => seriesRow(s, q)).join("")}</div></section>`;
    if (c.folders.length) html += `<section class="sr-block">${sec("Folders", c.folders.length, seeAll("folders", c.folders.length, 3))}<div class="sr-list">${c.folders.slice(0, 3).map((f) => folderRow(f, q)).join("")}</div></section>`;
    if (ft.total) html += `<section class="sr-block">${sec("Inside books", ft.total, seeAll("fulltext", ft.total, 3))}<div class="sr-hits">${ft.groups.slice(0, 3).map((g) => hitRow(g.book, g.hits[0], true)).join("")}</div></section>`;
    return html;
  }

  function noResults(q, scope) {
    const label = SCOPES.find((s) => s[0] === scope)?.[1] || "All";
    const acts = [
      scope !== "fulltext" && scope !== "book" ? `<button class="ko-btn" data-action="sr-scope" data-arg="fulltext">${App.icon("text-search", "sm")}Search inside books</button>` : "",
      scope !== "all" ? `<button class="ko-btn" data-action="sr-scope" data-arg="all">Search everything</button>` : "",
      `<button class="ko-btn ko-btn--ghost" data-toast="Searching OPDS catalogs…">${App.icon("globe", "sm")}Online catalogs</button>`,
    ].join("");
    return empty("search-x", `No matches for “${esc(q)}”`, `Nothing in ${scope === "all" ? "your library" : label.toLowerCase()} matches. Check the spelling, or widen the search.`, acts);
  }

  function scopesHTML(p) {
    const sc = p.scope || "all";
    const c = counts(p);
    const fmt = (v) => (v > 999 ? (Math.round(v / 100) / 10) + "k" : v);
    return `<div class="ko-chips sr-scopes">${SCOPES.map(([k, l]) => `<button class="ko-chip sr-scope ${sc === k ? "on" : ""}" data-action="sr-scope" data-arg="${k}">${k === "book" ? App.icon("book-open", "sm") : ""}${l}${c && c[k] != null ? `<span class="n num ${c[k] ? "" : "zero"}">${fmt(c[k])}</span>` : ""}</button>`).join("")}</div>`;
  }

  function revealScope() {
    const on = document.querySelector(".sr-scope.on"), bar = on?.parentElement;
    if (bar && on.offsetLeft + on.offsetWidth > bar.clientWidth + bar.scrollLeft) bar.scrollLeft = on.offsetLeft + on.offsetWidth - bar.clientWidth + 16;
  }
  const kbShown = (p) => !(p.kb === 0 || p.kb === "0" || p.kb === false);

  App.screen("search", {
    title: "Search",
    render(p) {
      App.kbInit("search", p.q ?? "", p);
      if (p.kbl && !KB.over.search) KB.over.search = p.kbl;
      const placeholder = p.scope === "book" ? `Search in ${currentBook(p).title}` : "Titles, authors, words…";
      return `<div class="ko-view sr ${kbShown(p) ? "kb-on" : ""}">
        ${App.statusBar({ left: "Search" })}
        <header class="sr-head">
          <button class="ko-icon-btn" data-action="tools-back" aria-label="Back">${App.icon("arrow-left")}</button>
          ${App.kbField("search", { placeholder, icon: "search", cls: "kb-field--lg sr-field" })}
          <button class="ko-icon-btn sr-kbbtn ${kbShown(p) ? "on" : ""}" data-action="sr-kb" aria-label="Keyboard">${App.icon(kbShown(p) ? "keyboard-off" : "keyboard")}</button>
        </header>
        ${scopesHTML(p)}
        <div class="ko-scroll sr-body">${bodyHTML(p)}</div>
        ${kbShown(p) ? `<div class="sr-kb">${App.keyboardHTML({ target: "search", enter: "Search" })}</div>` : ""}
      </div>`;
    },
    mount() { paint("search"); revealScope(); },
  });

  function update() {
    const p = App.current.params;
    const body = document.querySelector(".sr-body");
    if (body) { body.innerHTML = bodyHTML(p); body.scrollTop = 0; }
    const sc = document.querySelector(".sr-scopes");
    if (sc) sc.outerHTML = scopesHTML(p);
    App.icons(); App.syncHash(); revealScope();
  }
  const setP = (k, v) => { const p = App.current.params; if (v === undefined || v === "") delete p[k]; else p[k] = v; };
  App.kbOn("search", {
    change(v) { if (App.current.name !== "search") return; setP("q", v); update(); },
    enter(v) {
      v = v.trim(); if (!v) return;
      const h = DB.SEARCH_HISTORY, i = h.findIndex((x) => x.toLowerCase() === v.toLowerCase());
      if (i >= 0) h.splice(i, 1);
      h.unshift(v); if (h.length > 8) h.pop();
      setP("kb", 0); App.refresh(); App.syncHash();
    },
    focus() { if (!kbShown(App.current.params)) { setP("kb"); App.refresh(); App.syncHash(); } },
  });
  App.action("sr-scope", (el) => { setP("scope", el.dataset.arg === "all" ? undefined : el.dataset.arg); App.refresh(); App.syncHash(); });
  App.action("sr-q", (el) => {
    KB.values.search = el.dataset.arg; setP("q", el.dataset.arg);
    if (el.dataset.scope) setP("scope", el.dataset.scope);
    setP("kb", 0); App.refresh(); App.syncHash();
  });
  App.action("sr-kb", () => { setP("kb", kbShown(App.current.params) ? 0 : undefined); App.refresh(); App.syncHash(); });
  App.action("sr-opt", (el) => { App.set("search." + el.dataset.arg, !opt(el.dataset.arg)); update(); });
  App.action("sr-clear-history", () => { DB.SEARCH_HISTORY.length = 0; update(); App.toast("Search history cleared"); });

  /* ---------- designer states ---------- */
  const H = (screen, params = {}) => `#/${screen}${Object.keys(params).length ? "?" + new URLSearchParams(params) : ""}`;
  App.toolsHash = H;
  const G = "Search & Stats";
  App.demo(G, "Search · start (history, browse)", H("search"));
  App.demo(G, "Search · results for “or”", H("search", { q: "or" }));
  App.demo(G, "Search · results, keyboard hidden", H("search", { q: "or", kb: 0 }));
  App.demo(G, "Search · authors scope", H("search", { q: "or", scope: "authors", kb: 0 }));
  App.demo(G, "Search · full text", H("search", { q: "or", scope: "fulltext", kb: 0 }));
  App.demo(G, "Search · in this book", H("search", { q: "silence", scope: "book", kb: 0 }));
  App.demo(G, "Search · folders (browse all)", H("search", { scope: "folders", kb: 0 }));
  App.demo(G, "Search · no results", H("search", { q: "xylophone" }));
  App.demo(G, "Search · Arabic keyboard", H("search", { q: "طه", kbl: "arabic" }));
  App.demo("Dialogs", "Keyboard · English", H("home", { o: "keyboard", "o.hint": "Type a note" }));
  App.demo("Dialogs", "Keyboard · Arabic", H("home", { o: "keyboard", "o.layout": "arabic", "o.hint": "اكتب هنا" }));
  App.demo("Dialogs", "Keyboard · numeric", H("home", { o: "keyboard", "o.layout": "numeric", "o.hint": "Page number" }));
})();
