/* ==========================================================================
   Leaf — Gaps: KOReader surfaces the first design pass did not cover
   (prototype/coverage/coverage-report.md › "Gaps (missing and partial)").
   Every state is registered in the designer group "Gaps", labelled with the
   KOReader surface it designs. Built only from the shared components
   (UI.* helpers, .ko-*); css/screens/gaps.css only lays them out.

   Generic widgets (the base widgets of the Lua port)
     spin (dialog {k, v})            SpinWidget + NumberPickerWidget
     spin2 (dialog {k, a, b})        DoubleSpinWidget
     datetime (dialog {k, …})        DateTimeWidget
     number (dialog {min, max, …})   "Enter number" input with range errors
     arrange (page {k, sel, menu})   SortWidget
     path-chooser (page {mode, path, purpose}) · path-confirm (dialog)   PathChooser
     image-viewer (page {src, ui, rot, orig, i})                          ImageViewer
     key-popup · kb-layouts · clipboard · snippets · snippet-edit (keyboard / text field)
     text-viewer (sheet)            VerticalScrollBar inside long text
   Reader
     footer-mode {m} · flipping {k} · linkbox · link-ext {wiki} · bm-actions {i, hl}
     bm-view {i} · bm-select · search-nav {k} · quickmenu {k} · hl-multi · perception {set}
     crop (page) · pagemap (page) · pagemap-set (sheet) · tweak-info · tweak-editor {menu, dirty}
     dict-menu {k} · bookmap-menu · pb-menu · pb-hold · goto-pin · busy · screen scroll-mode
   Library, statistics, system
     open-with · selected-files · screenshot · coll-folders (+ coll-folder, coll-status)
     meta-field {f} · archive (page {sub, menu}) · archive-file · unlock · timer-up {k}
     book-stats (page {id}) · screen stats-cal {m, set} · stats-day (page) · stats-range (page {k}) · stats-books (page {reset})
   ========================================================================== */
(function () {
  const A = App, E = App.esc, I = App.icon, G = "Gaps";
  const RDX = () => window.RD;
  const D = (label, hash) => A.demo(G, label, hash);
  /** #/screen?sp…&o=overlay&o.k=v */
  const H = (screen, sp = {}, o, op = {}) => {
    const q = new URLSearchParams();
    Object.entries(sp).forEach(([k, v]) => q.set(k, typeof v === "object" ? JSON.stringify(v) : v));
    if (o) { q.set("o", o); Object.entries(op).forEach(([k, v]) => q.set("o." + k, typeof v === "object" ? JSON.stringify(v) : v)); }
    const s = q.toString();
    return `#/${screen}${s ? "?" + s : ""}`;
  };
  const top = () => (A.top() ? A.top().params : {});
  const setTop = (patch) => { const t = A.top(); if (!t) return; t.params = { ...t.params, ...patch }; A.renderLayers(true); A.syncHash(); };
  const below = () => A.state.stack[A.state.stack.length - 2];
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const pad = (n) => String(n).padStart(2, "0");
  const short = (b) => b.title.replace(/\s*\(.*\)$/, "");
  const P = (o) => A.attrs(o);

  /* ------------------------------------------------------------ shells */
  /** a level-2 sheet: grip, the shared header, a scrolling body and an optional footer */
  const sheet = (cls, head, body, foot = "") => `<div class="ko-sheet gp-sheet ${cls}"><div class="grip"></div>${head}<div class="ko-scroll gp-body">${body}<div class="gp-end"></div></div>${foot ? `<div class="gp-foot">${foot}</div>` : ""}</div>`;
  /** a full page with the level-2 page header */
  const page = (cls, head, body, foot = "") => `<div class="ko-page gp-page ${cls}">${A.statusBar()}${head}<div class="ko-scroll gp-body">${body}<div class="gp-end"></div></div>${foot ? `<div class="gp-foot">${foot}</div>` : ""}</div>`;
  /** action sheet (ButtonDialog without an anchor): head + groups of rows */
  const actions = (o) => sheet(UI.cls("gp-acts", o.cls), UI.sheetHead({ title: o.title, sub: o.sub, lead: o.lead, rule: !!o.lead }), o.body);
  const grow = '<span class="grow"></span>';
  const btn = UI.button;
  const ghost = (label, attrs, extra = {}) => btn({ label, kind: "ghost", attrs, ...extra });
  const primary = (label, attrs, extra = {}) => btn({ label, kind: "primary", attrs, ...extra });
  const koNote = (t) => `<div class="gp-ko">${I("info", "sm")}<span>KOReader: ${E(t)}</span></div>`;
  const help = (t) => `<p class="gp-help">${E(t)}</p>`;

  /* small help dialog for "About …" rows */
  A.overlay("gap-help", {
    layer: "dialog",
    render: (p) => UI.dialog({ title: p.title || "About", bodyHtml: `<div class="ko-dialog-body">${E(p.text || "")}</div>`, actions: [{ label: "Got it", kind: "primary", attrs: "data-close" }] }),
  });
  const helpAttrs = (title, text) => ({ open: "gap-help", params: { title, text } });

  /** position a popover next to an element (in the screen or in a layer) */
  const anchor = (layer, popSel, targetSel, o = {}) => {
    const scrEl = document.querySelector(".ko-screen"), pop = layer && layer.querySelector(popSel);
    const tEl = (layer && layer.querySelector(targetSel)) || document.querySelector(`#screen-root ${targetSel}`) || document.querySelector(targetSel);
    if (!scrEl || !pop || !tEl) return;
    const s = scrEl.getBoundingClientRect(), t = tEl.getBoundingClientRect();
    const pw = pop.offsetWidth, ph = pop.offsetHeight;
    let x = o.right ? t.right - s.left - pw : o.center ? t.left - s.left + (t.width - pw) / 2 : t.left - s.left;
    let y = o.above ? t.top - s.top - ph - 8 : o.over ? t.top - s.top + (t.height - ph) / 2 : t.bottom - s.top + 6;
    x = clamp(x, 8, s.width - pw - 8); y = clamp(y, 8, s.height - ph - 8);
    pop.style.left = x + "px"; pop.style.top = y + "px";
  };

  /* =====================================================================
     1 · NUMBER SPINNER (SpinWidget) — one compact dialog, one slider row
     ===================================================================== */
  const SPIN = {
    items: { title: "Items per page", label: "Items", min: 6, max: 30, def: 14, v: 14, help: "How many books or files one page of the library list shows. Fewer items means bigger rows.", ko: "File browser › Items per page" },
    battery: { title: "Hide battery below", label: "Level", unit: "%", min: 0, max: 100, def: 100, v: 30, step: 1, hold: 10, extra: "Disable", help: "The battery item in the status bar only appears when the charge is below this level.", ko: "Minimum threshold to hide battery item" },
    listmodes: { title: "Books per page in list view", label: "Books", min: 3, max: 10, def: 7, v: 7, help: "Number of rows on one page of the list views.", ko: "Project: Title › Items per page › List modes" },
    calbooks: { title: "Books per calendar day", label: "Books", min: 1, max: 5, def: 3, v: 3, ok: "Set", help: "The most book bars drawn in one day of the calendar view.", ko: "Statistics › Books per calendar day" },
    cpp: { title: "Characters per page", label: "Characters", min: 500, max: 3000, def: 1818, v: 1818, step: 100, extra: "Use publisher pages", help: "Stable page numbers are counted every this many characters, so they don't move when you change the font.", ko: "Stable page numbers › Characters per page" },
  };
  const spinCfg = (p) => ({ ...SPIN[p.k || "items"] });
  const spinVal = (p, c) => clamp(p.v != null ? +p.v : c.v, c.min, c.max);
  A.overlay("spin", {
    layer: "dialog",
    render(p) {
      const c = spinCfg(p), v = spinVal(p, c), pct = ((v - c.min) / (c.max - c.min)) * 100;
      const changed = v !== c.v;
      return UI.dialog({
        cls: "gp-spin", title: c.title,
        bodyHtml: `<div class="ko-dialog-body">${E(c.help)}</div>
          <div class="gp-spin-sr">${UI.sliderRow({ label: c.label, pct, value: String(v), unit: c.unit, slide: "gpSpinSlide", step: "gpSpinStep", id: "a" })}</div>
          <div class="gp-spin-meta"><span class="num">${c.min}–${c.max}${c.unit || ""} · default ${c.def}${c.unit || ""}</span>${grow}${btn({ kind: "link", label: "Type a number", icon: "keyboard", attrs: { action: "gpSpinType", arg: "a" } })}</div>
          ${koNote(c.ko)}`,
        actions: [ghost(c.extra ? "Default" : `Default · ${c.def}${c.unit || ""}`, { action: "gpSpinDef" }, { disabled: v === c.def }), grow,
          ...(c.extra ? [ghost(c.extra, { action: "gpSpinApply", arg: "extra" })] : []),
          ghost("Close", "data-close"), primary(c.ok || "Apply", { action: "gpSpinApply" }, { disabled: !changed })],
      });
    },
  });
  const spinStepOf = (c) => c.step || 1;
  A.action("gpSpinSlide", (el, f, done) => {
    const t = A.top(), c = t.name === "spin2" ? spin2Cfg(t.params)[el.dataset.id] : spinCfg(t.params);
    const s = spinStepOf(c), v = clamp(Math.round((c.min + f * (c.max - c.min)) / s) * s, c.min, c.max);
    const val = el.closest(".ko-sr").querySelector(".val"); if (val) val.firstChild.textContent = v;
    if (done) setTop({ [t.name === "spin2" ? el.dataset.id : "v"]: v });
  });
  A.action("gpSpinStep", (el) => {
    const t = A.top();
    if (t.name === "spin2") { const k = el.dataset.id, c = spin2Cfg(t.params)[k]; return setTop({ [k]: clamp(spin2Val(t.params, k) + +el.dataset.dir * spinStepOf(c), c.min, c.max) }); }
    const c = spinCfg(t.params); setTop({ v: clamp(spinVal(t.params, c) + +el.dataset.dir * spinStepOf(c), c.min, c.max) });
  });
  A.action("gpSpinDef", () => { const t = A.top(); if (t.name === "spin2") { const c = spin2Cfg(t.params); return setTop({ a: c.a.def, b: c.b.def }); } setTop({ v: spinCfg(t.params).def }); });
  A.action("gpSpinApply", (el) => {
    const t = A.top(); A.close();
    if (t.name === "spin2") { const c = spin2Cfg(t.params); return A.toast(`${c.title}: ${spin2Val(t.params, "a")} ${c.sep} ${spin2Val(t.params, "b")}${c.unit || ""}`); }
    const c = spinCfg(t.params);
    A.toast(el.dataset.arg === "extra" ? `${c.extra} · done` : `${c.title}: ${spinVal(t.params, c)}${c.unit || ""}`);
  });
  A.action("gpSpinType", (el) => {
    const t = A.top(), k = el.dataset.arg;
    const c = t.name === "spin2" ? spin2Cfg(t.params)[k] : t.name === "datetime" ? DT_FIELDS[k] : spinCfg(t.params);
    const v = t.name === "spin2" ? spin2Val(t.params, k) : t.name === "datetime" ? dtVal(t.params, k) : spinVal(t.params, c);
    A.open("number", { min: c.min, max: c.max, cur: v, key: t.name === "spin" ? "v" : k, label: c.label });
  });

  /* "Enter number": numeric keyboard, range errors under the field */
  A.overlay("number", {
    layer: "dialog",
    render(p) {
      A.kbInit("gpnum", p.value ?? "", p);
      const err = p.err === "max" ? `This value should be ${p.max} or less.` : p.err === "min" ? `This value should be ${p.min} or more.` : p.err === "nan" ? "Enter a number." : "";
      return UI.dialog({
        cls: "dl-input gp-number", title: "Enter a number", sub: p.label ? `${p.label} · now ${p.cur}` : "",
        bodyHtml: A.kbField("gpnum", { placeholder: `${p.cur ?? ""}`, cls: "kb-field--compact num" + (err ? " shake" : "") })
          + `<div class="kb-field-help${err ? " err" : ""}">${err ? I("circle-alert", "sm") + E(err) : `Between ${p.min} and ${p.max}. Start with = to calculate, e.g. =12*2`}</div>`,
        actions: [ghost("Cancel", "data-close"), primary("OK", 'data-action="gpNumOk" data-kb-submit="gpnum"')],
      }) + `<div class="dl-kbdock">${A.keyboardHTML({ layout: "numeric", target: "gpnum", enter: "Done" })}</div>`;
    },
  });
  A.action("gpNumOk", () => {
    const p = top(), raw = A.kbValue("gpnum").trim();
    let v = raw.startsWith("=") ? (() => { try { return Function(`"use strict";return (${raw.slice(1).replace(/[^\d+\-*/(). ]/g, "")})`)(); } catch { return NaN; } })() : Number(raw);
    if (raw === "" || isNaN(v)) return setTop({ err: "nan", value: raw });
    v = Math.round(v);
    if (v > p.max) return setTop({ err: "max", value: raw });
    if (v < p.min) return setTop({ err: "min", value: raw });
    A.close(); const t = A.top(); if (t) setTop({ [p.key]: v });
  });

  /* =====================================================================
     2 · DOUBLE SPINNER (DoubleSpinWidget) — two slider rows
     ===================================================================== */
  const SPIN2 = {
    battery: { title: "Battery alerts", sep: "–", unit: "%", a: { label: "Low", min: 1, max: 100, def: 20, v: 20 }, b: { label: "High", min: 1, max: 100, def: 100, v: 90 },
      help: "Low is checked while the device isn't charging, high while it is charging.", ko: "Battery level alert thresholds", def: "Default · 20 – 100%" },
    grid: { title: "Grid in portrait", sep: "×", a: { label: "Columns", min: 2, max: 4, def: 3, v: 3 }, b: { label: "Rows", min: 2, max: 4, def: 3, v: 3 },
      help: "Covers per row and rows per page in the portrait cover grid.", ko: "Project: Title › Items per page › Portrait cover grid mode", def: "Default · 3 × 3" },
    gridland: { title: "Grid in landscape", sep: "×", a: { label: "Columns", min: 2, max: 4, def: 4, v: 4 }, b: { label: "Rows", min: 2, max: 4, def: 2, v: 2 },
      help: "Covers per row and rows per page in the landscape cover grid.", ko: "Project: Title › Items per page › Landscape cover grid mode", def: "Default · 4 × 2" },
    hyph: { title: "Hyphenation limits", sep: "/", a: { label: "Before break", min: 1, max: 10, def: 2, v: 2 }, b: { label: "After break", min: 1, max: 10, def: 2, v: 3 },
      help: "Fewest letters left before and carried after a hyphen. Applies to every book with a hyphenation dictionary.", ko: "Hyphenation limits (Left / Right)", def: "Language defaults · 2 / 2" },
  };
  const spin2Cfg = (p) => SPIN2[p.k || "battery"];
  const spin2Val = (p, k) => { const c = spin2Cfg(p)[k]; return clamp(p[k] != null ? +p[k] : c.v, c.min, c.max); };
  A.overlay("spin2", {
    layer: "dialog",
    render(p) {
      const c = spin2Cfg(p), a = spin2Val(p, "a"), b = spin2Val(p, "b");
      const sr = (k, v) => { const f = c[k]; return UI.sliderRow({ label: f.label, pct: ((v - f.min) / (f.max - f.min)) * 100, value: String(v), unit: c.unit, slide: "gpSpinSlide", step: "gpSpinStep", id: k }); };
      const changed = a !== c.a.v || b !== c.b.v, isDef = a === c.a.def && b === c.b.def;
      return UI.dialog({
        cls: "gp-spin", title: c.title,
        bodyHtml: `<div class="ko-dialog-body">${E(c.help)}</div><div class="gp-spin-sr">${sr("a", a)}${sr("b", b)}</div>
          <div class="gp-spin-meta"><span class="num">${E(c.a.label)} ${a} ${c.sep} ${E(c.b.label.toLowerCase())} ${b}${c.unit || ""}</span>${grow}${btn({ kind: "link", label: "Type", icon: "keyboard", attrs: { action: "gpSpinType", arg: "a" } })}</div>${koNote(c.ko)}`,
        actions: [ghost(c.def, { action: "gpSpinDef" }, { disabled: isDef }), grow, ghost("Close", "data-close"), primary("Apply", { action: "gpSpinApply" }, { disabled: !changed })],
      });
    },
  });

  /* =====================================================================
     3 · DATE / TIME (DateTimeWidget) — stepper rows, like the read timer
     ===================================================================== */
  const DT_FIELDS = {
    d: { label: "Days", icon: "calendar", min: 0, max: 30 }, h: { label: "Hours", icon: "clock", min: 0, max: 23 }, m: { label: "Minutes", icon: "clock-3", min: 0, max: 59 }, s: { label: "Seconds", icon: "timer", min: 0, max: 59 },
  };
  const DT = {
    alarm: { title: "Alarm", sub: "Read timer", fields: ["h", "m"], v: { h: 22, m: 30 }, labels: { h: "Hour", m: "Minute" }, ok: "Set alarm", checks: ["Show timer in alt status bar", "Show timer in status bar"], on: [false, true],
      note: (v) => `Rings at <b class="num">${pad(v.h)}:${pad(v.m)}</b> · in 1 h 12 min` },
    interval: { title: "Interval", sub: "Read timer", fields: ["h", "m"], v: { h: 0, m: 20 }, max: { h: 17 }, ok: "Start timer", checks: ["Repeat when time is up", "Show timer in alt status bar", "Show timer in status bar"], on: [false, false, true], ko: "Auto-reschedule",
      note: (v) => `Time is up at <b class="num">21:${pad(38 + v.m > 59 ? 59 : 38 + v.m)}</b>` },
    daystart: { title: "Daily timeline starts at", sub: "Statistics", fields: ["h", "m"], v: { h: 4, m: 0 }, labels: { h: "Hour", m: "Minute" }, step: { m: 10 }, max: { m: 50 }, ok: "Set time",
      help: "Reading past midnight still counts for the evening before when the day starts later, e.g. at 04:00.", note: (v) => `Days run from <b class="num">${pad(v.h)}:${pad(v.m)}</b> to <b class="num">${pad(v.h)}:${pad(v.m)}</b>` },
    suspend: { title: "Sleep after", sub: "Auto suspend", fields: ["d", "h", "m"], v: { d: 0, h: 1, m: 0 }, step: { m: 5 }, ok: "Set timeout", help: "The device goes to sleep when you haven't touched it for this long.", ko: "Autosuspend timeout",
      note: (v) => `Sleeps after <b class="num">${v.d ? v.d + " d " : ""}${v.h} h ${pad(v.m)} min</b> without a touch` },
  };
  const dtCfg = (p) => DT[p.k || "alarm"];
  const dtVal = (p, f) => { const c = dtCfg(p); return clamp(p[f] != null ? +p[f] : c.v[f], DT_FIELDS[f].min, (c.max && c.max[f]) ?? DT_FIELDS[f].max); };
  A.overlay("datetime", {
    layer: "dialog",
    render(p) {
      const c = dtCfg(p), v = Object.fromEntries(c.fields.map((f) => [f, dtVal(p, f)]));
      const checks = p.c ? String(p.c).split("").map((x) => x === "1") : c.on || [];
      const rows = c.fields.map((f) => UI.row({ tag: "div", icon: DT_FIELDS[f].icon, label: (c.labels && c.labels[f]) || DT_FIELDS[f].label, trailing: "stepper",
        stepper: { value: pad(v[f]), attrsMinus: { action: "gpDtStep", arg: `${f}|-1` }, attrsPlus: { action: "gpDtStep", arg: `${f}|1` } } }));
      return UI.dialog({
        cls: "gp-dt", title: c.title, sub: c.sub,
        bodyHtml: (c.help ? `<div class="ko-dialog-body">${E(c.help)}</div>` : "")
          + `<div class="gp-dt-rows">${UI.group(rows, { sunken: true })}</div>
          <div class="gp-spin-meta"><span>${c.note(v)}</span>${grow}${btn({ kind: "link", label: "Type", icon: "keyboard", attrs: { action: "gpSpinType", arg: c.fields[c.fields.length - 1] } })}</div>`
          + (c.checks || []).map((l, i) => UI.checkRow({ label: l, on: checks[i], attrs: { action: "gpDtCheck", arg: i } })).join("")
          + (c.ko ? koNote(c.ko) : ""),
        actions: [ghost("Close", "data-close"), primary(c.ok, { action: "gpDtOk" })],
      });
    },
  });
  A.action("gpDtStep", (el) => {
    const [f, d] = el.dataset.arg.split("|"), p = top(), c = dtCfg(p), F = DT_FIELDS[f], max = (c.max && c.max[f]) ?? F.max, s = (c.step && c.step[f]) || 1;
    let v = dtVal(p, f) + +d * s; if (v > max) v = F.min; if (v < F.min) v = max;
    setTop({ [f]: v });
  });
  A.action("gpDtCheck", (el) => { const p = top(), c = dtCfg(p); const on = p.c ? String(p.c).split("").map((x) => x === "1") : (c.on || []).slice(); on[+el.dataset.arg] = !on[+el.dataset.arg]; setTop({ c: on.map((x) => (x ? 1 : 0)).join("") }); });
  A.action("gpDtOk", () => { const p = top(), c = dtCfg(p); A.close(); A.toast(c.k === "interval" || p.k === "interval" ? `Timer will ring in ${dtVal(p, "h") ? dtVal(p, "h") + " h " : ""}${dtVal(p, "m")} min` : p.k === "alarm" || !p.k ? `Alarm set for ${pad(dtVal(p, "h"))}:${pad(dtVal(p, "m"))}` : `${c.title}: saved`); });

  /* =====================================================================
     4 · ARRANGE (SortWidget) — tap an item, move it, save
     ===================================================================== */
  const ARR_DATA = {
    coll: { title: "Arrange collections", crumb: "Collections", icon: "library", items: ["Favorites", "To read this winter", "Sherlock Holmes", "Arabic", "Poetry", "Book club", "Philosophy", "Comics"] },
    books: { title: "Arrange books", crumb: "To read this winter", icon: "book", items: ["walden", "crime", "jane-eyre", "middlemarch", "little-women", "siddhartha", "odyssey"].map((id) => short(DB.book(id))) },
    footer: { title: "Status bar items", crumb: "Settings › Status bar", icon: "panel-bottom", checks: true,
      items: ["Current page", "Pages left in chapter", "Time left in chapter", "Progress percentage", "Current time", "Battery level", "Book title", "Chapter title", "Bookmark count", "Wi-Fi status", "Brightness level", "Time left in book"], on: [1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0] },
    dict: { title: "Dictionary order", crumb: "Dictionaries", icon: "book-a", items: DB.DICTIONARIES.slice() },
  };
  const ARR = {};
  const arrState = (k) => (ARR[k] ||= { order: ARR_DATA[k].items.map((_, i) => i), on: (ARR_DATA[k].on || []).map(Boolean), saved: null });
  A.overlay("arrange", {
    layer: "page",
    render(p) {
      const k = p.k || "coll", d = ARR_DATA[k], st = arrState(k), sel = p.sel != null && p.sel !== "" ? +p.sel : -1;
      const moved = st.order.some((x, i) => x !== i) || st.dirty;
      const rows = st.order.map((ix, pos) => {
        const on = st.on[ix];
        return `<div class="ko-row gp-arr-row ${pos === sel ? "sel" : ""}" data-action="gpArrSel" data-i="${pos}" role="button">${I(pos === sel ? "move-vertical" : "grip-vertical")}
          ${d.checks ? `<button class="gp-arr-check" data-action="gpArrCheck" data-stop data-i="${ix}" aria-label="Show item">${A.check(on)}</button>` : ""}
          <span class="label">${E(d.items[ix])}${d.checks && !on ? `<span class="sub">Hidden</span>` : ""}</span><span class="value num">${pos + 1}</span></div>`;
      }).join("");
      const foot = sel >= 0
        ? `<span class="gp-foot-t">${E(d.items[st.order[sel]])}</span>${grow}
           ${UI.iconButton({ icon: "chevrons-up", label: "Move to top", attrs: { action: "gpArrMove", arg: "top" }, disabled: sel === 0 })}
           ${UI.iconButton({ icon: "chevron-up", label: "Move up", attrs: { action: "gpArrMove", arg: "-1" }, disabled: sel === 0 })}
           ${UI.iconButton({ icon: "chevron-down", label: "Move down", attrs: { action: "gpArrMove", arg: "1" }, disabled: sel === st.order.length - 1 })}
           ${UI.iconButton({ icon: "chevrons-down", label: "Move to bottom", attrs: { action: "gpArrMove", arg: "bottom" }, disabled: sel === st.order.length - 1 })}
           ${btn({ label: "Done", attrs: { action: "gpArrSel", i: sel } })}`
        : `${ghost("Undo changes", { action: "gpArrUndo" }, { disabled: !moved, icon: "undo-2" })}${grow}${ghost("Close", "data-close")}${primary("Save", { action: "gpArrSave" }, { disabled: !moved })}`;
      const menu = p.menu ? `<div class="ko-popover gp-pop gp-arr-menu">${UI.sectionLabel("Sort")}${[["arrow-down-a-z", "A to Z", "az"], ["arrow-up-z-a", "Z to A", "za"], ["arrow-down-1-0", "A to Z, numbers in order", "nat"], ["arrow-up-1-0", "Z to A, numbers in order", "natr"]]
        .map(([ic, l, v]) => UI.row({ icon: ic, label: l, attrs: { action: "gpArrSort", arg: v } })).join("")}</div>` : "";
      return page("gp-arr", UI.pageHead({ title: d.title, crumbs: [d.crumb], rule: true, actions: UI.iconButton({ icon: "arrow-down-a-z", label: "Sort", attrs: { action: "gpArrMenu" }, active: !!p.menu, cls: "gp-arr-sortbtn" }) }),
        `${help(sel >= 0 ? "Move the selected item with the arrows below, or tap another item." : `Tap an item, then move it up or down.${d.checks ? " The check shows or hides it." : ""}`)}${UI.group(rows, { cls: "gp-arr-list" })}`, foot) + (menu ? `<div class="ko-scrim clear" data-action="gpArrMenu"></div>${menu}` : "");
    },
    mount(el, p) { if (p.menu) anchor(el, ".gp-arr-menu", ".gp-arr-sortbtn", { right: true }); },
  });
  A.action("gpArrSel", (el) => { const i = +el.dataset.i; setTop({ sel: top().sel === i ? "" : i }); });
  A.action("gpArrCheck", (el, ev) => { ev.stopPropagation(); const k = top().k || "coll", st = arrState(k), i = +el.dataset.i; st.on[i] = !st.on[i]; st.dirty = true; setTop({}); });
  A.action("gpArrMove", (el) => {
    const p = top(), st = arrState(p.k || "coll"), i = +p.sel, a = el.dataset.arg, o = st.order;
    const j = a === "top" ? 0 : a === "bottom" ? o.length - 1 : clamp(i + +a, 0, o.length - 1);
    const [x] = o.splice(i, 1); o.splice(j, 0, x); setTop({ sel: j });
  });
  A.action("gpArrUndo", () => { const k = top().k || "coll"; delete ARR[k]; setTop({ sel: "" }); A.toast("Order restored"); });
  A.action("gpArrSave", () => { const k = top().k || "coll"; ARR[k] = { ...arrState(k), order: arrState(k).order.slice() }; A.close(); A.toast("New order saved"); });
  A.action("gpArrMenu", () => setTop({ menu: top().menu ? "" : 1 }));
  A.action("gpArrSort", (el) => {
    const p = top(), k = p.k || "coll", d = ARR_DATA[k], st = arrState(k), v = el.dataset.arg;
    const nat = (s) => s.replace(/\d+/g, (n) => n.padStart(6, "0"));
    st.order.sort((x, y) => { const a = v.startsWith("nat") ? nat(d.items[x]) : d.items[x], b = v.startsWith("nat") ? nat(d.items[y]) : d.items[y]; return (v === "za" || v === "natr" ? -1 : 1) * a.localeCompare(b); });
    st.dirty = true; setTop({ menu: "", sel: "" });
  });

  /* =====================================================================
     5 · FOLDER / FILE CHOOSER (PathChooser)
     ===================================================================== */
  const TREE = {
    "": { dirs: ["Books", "Downloads", "Pictures", "Screenshots", "Documents"] },
    Books: { dirs: DB.FOLDERS.map((f) => f.name), files: [["notes.txt", "4 KB"]] },
    Downloads: { dirs: ["Comics", "Articles"], files: [["comics-pack.zip", "48 MB"], ["The Odyssey.epub", "1.2 MB"], ["receipt.pdf", "88 KB"]] },
    Pictures: { dirs: ["Covers"], files: [["lighthouse.jpg", "412 KB"], ["map-of-the-farm.png", "1.1 MB"], ["wallpaper-01.png", "960 KB"], ["readme.txt", "1 KB"]] },
    "Pictures/Covers": { dirs: [], files: [["animal-farm-1945.jpg", "286 KB"], ["animal-farm-penguin.jpg", "302 KB"], ["moby-dick.png", "540 KB"]] },
    Screenshots: { dirs: [], files: [["Reader_Animal Farm_p12_2026-11-19.png", "96 KB"], ["FileManager_2026-11-18.png", "88 KB"]] },
    Documents: { dirs: [], files: [["reading-list.md", "2 KB"], ["styletweaks.css", "1 KB"]] },
  };
  const PURPOSE = {
    download: { title: "Choose download folder", mode: "folder", start: "Downloads" },
    home: { title: "Choose HOME folder", mode: "folder", start: "Books" },
    cover: { title: "Choose a cover image", mode: "file", start: "Pictures/Covers", filter: /\.(jpe?g|png|gif|webp|svg)$/i, kind: "images" },
    collection: { title: "Connect a folder", mode: "folder", start: "Books" },
    extract: { title: "Extract to…", mode: "folder", start: "Downloads" },
  };
  const isImg = (n) => /\.(jpe?g|png|gif|webp|svg)$/i.test(n);
  A.overlay("path-chooser", {
    layer: "page",
    render(p) {
      const pu = PURPOSE[p.purpose || "download"], mode = pu.mode, path = p.path != null ? String(p.path) : pu.start;
      const node = TREE[path] || { dirs: [], files: [] }, segs = path ? path.split("/") : [];
      const go = (to) => ({ action: "gpPathGo", arg: to });
      const crumbs = [{ label: "onboard", attrs: go("") }].concat(segs.map((s, i) => ({ label: s, attrs: go(segs.slice(0, i + 1).join("/")) })));
      const up = path ? [UI.row({ icon: "corner-left-up", label: "Up one level", sub: "/mnt/onboard" + (segs.length > 1 ? "/" + segs.slice(0, -1).join("/") : ""), attrs: go(segs.slice(0, -1).join("/")) })] : [];
      const dirs = node.dirs.map((n) => { const to = path ? `${path}/${n}` : n; const t = TREE[to]; const c = t ? t.dirs.length + (t.files || []).length : 4 + (n.length % 9); return UI.row({ icon: "folder", label: n, sub: `${c} items`, trailing: "chevron", attrs: go(to) }); });
      const files = (node.files || []).map(([n, size]) => {
        const ok = mode === "file" && (!pu.filter || pu.filter.test(n));
        return UI.row({ icon: isImg(n) ? "file-image" : /\.zip$/.test(n) ? "file-archive" : "file", label: n, sub: ok ? `${size} · tap to choose` : mode === "folder" ? size : `${size} · not an image`, disabled: !ok, attrs: ok ? { open: "path-confirm", params: { path: `${path}/${n}`, size } } : "" });
      });
      const list = up.concat(dirs, files);
      const foot = mode === "folder"
        ? `<div class="grow gp-path"><span class="ellipsis num">/mnt/onboard${path ? "/" + E(path) : ""}</span><span class="faint">${node.dirs.length} folders · ${(node.files || []).length} files</span></div>${ghost("Cancel", "data-close")}${primary("Use this folder", { action: "gpPathUse", arg: path })}`
        : `<div class="grow gp-path"><span>Tap an image to choose it</span><span class="faint">Only ${pu.kind} can be chosen</span></div>${ghost("Cancel", "data-close")}`;
      return page("gp-pc", UI.pageHead({ title: pu.title, crumbs, back: "data-close", rule: true,
        actions: UI.iconButton({ icon: "house", label: "HOME folder", attrs: go("Books") }) + UI.iconButton({ icon: "folder-symlink", label: "Folder shortcuts", attrs: { open: "lib-shortcuts" } }) + (mode === "folder" ? UI.iconButton({ icon: "folder-plus", label: "New folder", attrs: { open: "input", params: { title: "New folder", hint: "Folder name", ok: "Create" } } }) : "") }),
        list.length ? UI.list(list, { inset: true }) : UI.empty({ icon: "folder-open", title: "Empty folder", text: "Nothing inside yet." }), foot);
    },
  });
  A.action("gpPathGo", (el) => setTop({ path: el.dataset.arg }));
  A.action("gpPathUse", (el) => { A.close(); A.toast(`Folder set · /mnt/onboard/${el.dataset.arg}`); });
  A.overlay("path-confirm", {
    layer: "dialog",
    render(p) {
      const path = String(p.path || "Pictures/Covers/animal-farm-1945.jpg"), name = path.split("/").pop();
      return UI.dialog({
        title: "Choose this file?", sub: name,
        bodyHtml: UI.kv([["Folder", "/mnt/onboard/" + path.split("/").slice(0, -1).join("/")], ["Size", p.size || "286 KB"], ["Modified", "Nov 12, 18:40"]]),
        actions: [ghost("Cancel", "data-close"), primary("Choose", { action: "gpPathPick" })],
      });
    },
  });
  A.action("gpPathPick", () => { A.closeAll(); A.toast("Custom cover set"); });

  /* =====================================================================
     6 · IMAGE VIEWER (ImageViewer): covers, images in books, screenshots,
         archive images, OPDS page streaming
     ===================================================================== */
  const art = {
    barn: `<svg class="gp-iv-art" viewBox="0 0 320 240" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M10 210 H310"/><path d="M60 210 V120 L120 70 L180 120 V210"/><path d="M95 210 V160 H145 V210"/><path d="M95 160 L145 210 M145 160 L95 210"/>
      <path d="M120 70 V48 M110 48 H130"/><path d="M180 140 H262 V210"/><path d="M180 140 L221 108 L262 140"/><path d="M200 165 H222 V185 H200 Z"/>
      <path d="M30 210 C 34 180 26 160 40 150 C 52 160 44 182 48 210"/><path d="M276 210 C 280 176 270 150 286 138 C 300 152 290 182 294 210"/>
      <circle cx="260" cy="50" r="16"/><path d="M20 70 C 40 60 60 66 74 58 M196 62 C 214 54 230 60 244 52"/>
      <path d="M70 222 C 110 228 150 216 190 226 C 220 232 250 222 290 228" class="faint-s"/></svg>`,
    comic: `<svg class="gp-iv-art" viewBox="0 0 240 340" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">
      <rect x="10" y="10" width="220" height="100" rx="2"/><rect x="10" y="120" width="105" height="100" rx="2"/><rect x="125" y="120" width="105" height="100" rx="2"/><rect x="10" y="230" width="220" height="100" rx="2"/>
      <path d="M30 90 L70 40 L100 80 L130 50 L210 90"/><circle cx="62" cy="168" r="18"/><path d="M40 205 C 50 190 74 190 84 205"/><path d="M140 140 H210 M140 155 H200 M140 170 H190"/>
      <path d="M20 300 C 60 260 100 320 140 280 C 170 250 200 300 220 270"/><ellipse cx="170" cy="250" rx="30" ry="12"/></svg>`,
  };
  const shotMock = () => `<div class="gp-iv-shot" aria-hidden="true"><i class="h"></i>${Array.from({ length: 13 }, (_, i) => `<i class="${i === 5 ? "s" : ""}" style="width:${[96, 100, 92, 99, 88, 60, 0, 97, 100, 94, 98, 90, 72][i]}%"></i>`).join("")}<i class="f"></i></div>`;
  const IV = {
    cover: (p) => { const b = DB.book(p.id || "animal-farm"); return { title: short(b), sub: `Cover image · ${b.author.split(";")[0]}`, art: `<div class="gp-iv-cover">${UI.cover(b)}</div>`, caption: false }; },
    figure: () => ({ title: "The farm at dusk", sub: "Image in book · Chapter II", art: art.barn, caption: "Fig. 2 — Manor Farm, seen from the road to Willingdon.", page: true }),
    shot: () => ({ title: "Screenshot", sub: "Reader_Animal Farm_p12_2026-11-19.png", art: shotMock(), save: false }),
    archive: (p) => ({ title: `page-${pad(+(p.i || 3))}.jpg`, sub: "comics-pack.zip › Issue 1", art: art.comic, list: 24, page: true }),
    pse: (p) => ({ title: "The Long Field · Issue 3", sub: "Page stream · Kavita", art: art.comic, list: 48, pse: true, page: true }),
  };
  A.overlay("image-viewer", {
    layer: "page",
    render(p) {
      const src = p.src || "cover", m = IV[src](p), ui = String(p.ui ?? 1) !== "0", rot = +(p.rot || 0), orig = !!+(p.orig || 0), i = +(p.i || (m.pse ? 12 : 3));
      const showCap = m.caption && String(p.cap ?? 1) !== "0";
      const head = ui ? `<div class="gp-iv-top">${UI.iconButton({ icon: "x", label: "Close", attrs: "data-close" })}<div class="grow"><div class="ko-page-title ellipsis">${E(m.title)}</div><div class="gp-iv-sub ellipsis">${E(m.sub)}</div></div>
          ${m.caption ? UI.iconButton({ icon: showCap ? "captions" : "captions-off", label: showCap ? "Hide caption" : "Show caption", attrs: { action: "gpIvCap" } }) : ""}</div>` : "";
      const tools = [
        UI.tool({ icon: orig ? "shrink" : "expand", label: orig ? "Fit to screen" : "Original size", attrs: { action: "gpIvSet", arg: "orig" } }),
        UI.tool({ icon: "rotate-cw", label: rot ? "No rotation" : "Rotate", attrs: { action: "gpIvSet", arg: "rot" } }),
        m.list ? UI.tool({ icon: "hash", label: "Go to page", attrs: { open: "input", params: { title: m.pse ? "Stream from page" : "Go to image", hint: `1 – ${m.list}`, layout: "numeric", ok: m.pse ? "Stream" : "Go" } } }) : "",
        m.save === false ? "" : UI.tool({ icon: "camera", label: "Save view", attrs: { open: "screenshot", params: { from: "viewer" } } }),
      ].filter(Boolean).join("");
      const foot = ui ? `<div class="gp-iv-foot">${m.list ? `<div class="gp-iv-list"><span class="num">${i} / ${m.list}</span>${UI.progress((i / m.list) * 100, { size: "thin", cls: "grow" })}</div>` : ""}<div class="gp-iv-tools">${tools}</div></div>` : "";
      return `<div class="ko-page gp-iv ${ui ? "" : "bare"}">${ui ? A.statusBar() : ""}${head}
        <div class="gp-iv-stage" data-action="gpIvTap">${m.list ? `<button class="gp-iv-zone prev" data-action="gpIvStep" data-stop data-arg="-1" aria-label="Previous image"></button><button class="gp-iv-zone next" data-action="gpIvStep" data-stop data-arg="1" aria-label="Next image"></button>` : ""}
          <div class="gp-iv-img ${orig ? "orig" : ""} ${rot ? "rot" : ""} ${m.page ? "paper" : ""}">${m.art}</div></div>
        ${showCap && ui ? `<div class="gp-iv-cap">${E(m.caption)}</div>` : ""}${foot}
        ${ui ? "" : `<div class="gp-iv-hint">${E(m.list ? "Tap the sides for the previous or next image · the middle shows the controls" : "Tap to show the controls · pinch to zoom")}</div>`}</div>`;
    },
  });
  A.action("gpIvTap", () => setTop({ ui: String(top().ui ?? 1) === "0" ? 1 : 0 }));
  A.action("gpIvSet", (el) => { const p = top(), k = el.dataset.arg; setTop({ [k]: +(p[k] || 0) ? 0 : 1 }); });
  A.action("gpIvCap", () => setTop({ cap: String(top().cap ?? 1) === "0" ? 1 : 0 }));
  A.action("gpIvStep", (el, ev) => { ev.stopPropagation(); const p = top(), m = IV[p.src](p); setTop({ i: clamp(+(p.i || (m.pse ? 12 : 3)) + +el.dataset.arg, 1, m.list) }); });

  /* screenshot taken (Screenshoter) */
  A.overlay("screenshot", {
    layer: "sheet",
    render(p) {
      const inBook = A.current.name === "reader";
      return actions({
        title: "Screenshot saved", sub: "/mnt/onboard/Screenshots/Reader_Animal Farm_p12_2026-11-19.png",
        lead: `<span class="gp-shot-thumb">${shotMock()}</span>`,
        body: UI.group([
          UI.row({ icon: "eye", label: "View", attrs: { open: "image-viewer", params: { src: "shot" } } }),
          UI.row({ icon: "image", label: "Set as book cover", sub: inBook ? "Replaces the cover of Animal Farm" : "Open a book to use this", disabled: !inBook, attrs: { action: "gpToastClose", arg: "Screenshot set as book cover" } }),
          UI.row({ icon: "monitor-smartphone", label: "Set as sleep screen", attrs: { action: "gpToastClose", arg: "Sleep screen set to this screenshot" } }),
        ]) + UI.group([UI.row({ icon: "trash-2", label: "Delete screenshot", danger: true, attrs: { action: "gpToastClose", arg: "Screenshot deleted" } })], { cls: "gp-gap" })
          + `<div class="gp-note">${I("hand", "sm")}<span>Two-finger diagonal swipe takes a screenshot. Change the folder in Settings › Screenshots.</span></div>`,
      });
    },
  });
  A.action("gpToastClose", (el) => { A.close(); A.toast(el.dataset.arg); });

  /* =====================================================================
     7 · KEYBOARD: key long-press popup, layout switcher; TEXT FIELD clipboard
     ===================================================================== */
  const KEYPOP = { e: { center: "e", nw: "è", n: "E", ne: "é", w: "ẽ", e: "ê", sw: "ė", s: "ę", se: "ë", extra: ["ē", "ě", "€"] },
    a: { center: "a", nw: "à", n: "A", ne: "á", w: "ã", e: "â", sw: "å", s: "ą", se: "ä", extra: ["ā", "ǎ", "æ"] } };
  const field = (p) => A.overlays.input.render({ title: p.title || "Rename collection", value: p.value ?? "Café readi", ok: "Save", hint: "Collection name" });
  A.overlay("key-popup", {
    layer: "dialog",
    render(p) {
      const k = KEYPOP[p.key || "e"], hot = p.hot || "ne";
      const cell = (pos) => (k[pos] ? `<button class="kb-key gp-kp-cell ${pos === hot ? "on" : ""} ${pos === "center" ? "kb-fn" : ""}" data-action="gpKpType" data-arg="${E(k[pos])}">${E(k[pos])}</button>` : "<span></span>");
      return field(p) + `<div class="ko-popover gp-pop gp-kp" role="dialog" aria-label="Accents for ${k.center}">
        <div class="gp-kp-grid">${k.extra.map((c) => `<button class="kb-key gp-kp-cell" data-action="gpKpType" data-arg="${E(c)}">${E(c)}</button>`).join("")}
        ${["nw", "n", "ne", "w", "center", "e", "sw", "s", "se"].map(cell).join("")}</div>
        <div class="gp-kp-hint">Slide to a letter and lift · or swipe on the key</div></div>`;
    },
    mount(el, p) { anchor(el, ".gp-kp", `.kb-key[data-k="${(p.key || "e")}"]`, { center: true, above: true }); },
  });
  A.action("gpKpType", (el) => { A.close(); A.kbSet("input", A.kbValue("input") + el.dataset.arg); A.toast(`Typed ${el.dataset.arg}`); });

  const LAYOUTS = [["English", "en", 1, 1], ["العربية · Arabic", "ar", 1, 0], ["Français · French", "fr", 1, 0], ["Deutsch · German", "de", 0, 0], ["Español · Spanish", "es", 0, 0], ["Русский · Russian", "ru", 0, 0], ["Ελληνικά · Greek", "el", 0, 0]];
  A.overlay("kb-layouts", {
    layer: "dialog",
    render(p) {
      const cur = p.cur || "en";
      return field({ value: "", title: "Search" }) + `<div class="ko-popover gp-pop gp-kbl">
        ${UI.sectionLabel("Keyboard layout")}
        ${LAYOUTS.map(([n, c, inRot, def]) => UI.row({ label: n, sub: [inRot ? "In the globe-key rotation" : "", def ? "Default" : ""].filter(Boolean).join(" · ") || undefined, trailing: "radio", on: cur === c, attrs: { action: "gpKbl", arg: c } })).join("")}
        <div class="ko-divider"></div>
        ${UI.row({ icon: "settings-2", label: "Keyboard settings…", attrs: { go: "settings", params: { section: "keyboard" } } })}
        <div class="gp-kp-hint">Tap the globe key to switch between the layouts in the rotation.</div></div>`;
    },
    mount(el) { anchor(el, ".gp-kbl", '.kb-key[data-k="globe"]', { above: true }); },
  });
  A.action("gpKbl", (el) => { A.close(); A.toast(`Keyboard: ${LAYOUTS.find((l) => l[1] === el.dataset.arg)[0]}`); });

  /* hold on a text field: clipboard + editing actions */
  const SNIPS = [["Signature", "— sent from my e-reader"], ["", "Remember to return this book to the library."], ["Book club", "Book club · Thursday 19:00 · chapters 4–6"], ["Address", "12 Rue des Lilas, Lyon"]];
  A.overlay("clipboard", {
    layer: "dialog",
    render(p) {
      const empty = p.empty === 1 || p.empty === "1";
      return A.overlays.input.render({ title: "Add a note", value: "The windmill was finished at last, and the animals", ok: "Save", hint: "Note" }) + `<div class="ko-popover gp-pop gp-clip">
        <div class="gp-clip-top">${UI.eyebrow("Clipboard", { icon: "clipboard" })}<div class="gp-clip-txt ${empty ? "faint" : ""}">${empty ? "Nothing copied yet" : "“the creatures outside looked from pig to man”"}</div></div>
        ${UI.row({ icon: "clipboard-paste", label: "Paste", disabled: empty, attrs: { action: "gpToastClose", arg: "Pasted" } })}
        ${UI.row({ icon: "pin", label: "Snippets", value: `${SNIPS.length}`, trailing: "chevron", attrs: { action: "gpSwap", arg: "snippets" } })}
        <div class="ko-divider"></div>
        ${UI.row({ icon: "copy", label: "Copy all", attrs: { action: "gpToastClose", arg: "All text copied" } })}
        ${UI.row({ icon: "text", label: "Copy line", attrs: { action: "gpToastClose", arg: "Line copied" } })}
        ${UI.row({ icon: "type", label: "Copy word", attrs: { action: "gpToastClose", arg: "Word copied" } })}
        ${UI.row({ icon: "text-select", label: "Select text…", sub: "Long-press the start, then the end", attrs: { action: "gpToastClose", arg: "Long-press where the selection starts" } })}
        <div class="ko-divider"></div>
        ${UI.row({ icon: "undo-2", label: "Undo last deletion", disabled: true })}
        ${UI.row({ icon: "trash-2", label: "Delete all text", danger: true, attrs: { action: "gpToastClose", arg: "Text deleted · Undo is in this menu" } })}
      </div>`;
    },
    mount(el) { anchor(el, ".gp-clip", ".kb-field"); },
  });
  A.action("gpSwap", (el) => { let pr = {}; try { pr = JSON.parse(el.dataset.params || "{}"); } catch { /* none */ } A.replaceTop(el.dataset.arg, pr); });
  A.overlay("snippets", {
    layer: "sheet",
    render() {
      return sheet("gp-snips", UI.sheetHead({ title: "Snippets", sub: "Tap to insert · ⋯ to edit" }),
        UI.list(SNIPS.map(([n, t], i) => UI.row({ tag: "div", icon: "pin", label: n || t, sub: n ? t : undefined, attrs: { action: "gpToastClose", arg: "Snippet inserted", role: "button" },
          trailing: UI.iconButton({ icon: "ellipsis", label: "Edit snippet", size: "sm", attrs: { open: "snippet-edit", params: { i } } }) })), { inset: true }),
        `${ghost("Close", "data-close")}${grow}${primary("New snippet", { open: "snippet-edit", params: {} }, { icon: "plus" })}`);
    },
  });
  A.overlay("snippet-edit", {
    layer: "dialog",
    render(p) {
      const s = p.i != null ? SNIPS[+p.i] : null;
      return UI.dialog({
        cls: "gp-form", title: s ? "Edit snippet" : "New snippet",
        bodyHtml: `<div class="gp-field"><span class="ko-eyebrow">Text</span><div class="kb-field kb-field--compact gp-multi"><span class="kb-text">${E(s ? s[1] : "Remember to return this book to the library.")}</span></div></div>
          <div class="gp-field"><span class="ko-eyebrow">Name · optional</span>${UI.input({ placeholder: "Shown instead of the text", value: s ? s[0] : "" })}</div>`,
        actions: [...(s ? [ghost("Remove", { action: "gpToastClose", arg: "Snippet removed" })] : []), grow, ghost("Cancel", "data-close"), primary("Save", { action: "gpToastClose", arg: "Snippet saved" })],
      });
    },
  });

  /* long text with the one scroll-bar style (VerticalScrollBar) */
  A.overlay("text-viewer", {
    layer: "sheet",
    render() {
      const b = DB.book("middlemarch");
      const paras = TextGen.chapter("desc-mm", 0, 9);
      return `<div class="ko-sheet gp-sheet gp-tv"><div class="grip"></div>${UI.sheetHead({ title: "Book description", sub: short(b) + " · " + b.author, actions: UI.iconButton({ icon: "search", label: "Find", attrs: { open: "input", params: { title: "Find in text", hint: "Text to find", ok: "Find" } } }) + UI.iconButton({ icon: "a-large-small", label: "Text size", attrs: { open: "spin", params: { k: "items" } } }) })}
        <div class="gp-tv-wrap"><div class="ko-scroll gp-tv-body">${paras.map((t) => `<p>${E(t)}</p>`).join("")}</div>
        <div class="gp-scrollbar" aria-hidden="true"><i style="top:18%;height:26%"></i></div></div>
        <div class="gp-foot">${ghost("Top", { toast: "Top" }, { icon: "arrow-up-to-line" })}${ghost("Bottom", { toast: "Bottom" }, { icon: "arrow-down-to-line" })}${grow}${primary("Close", "data-close")}</div></div>`;
    },
  });

  /* expose for the other parts of this file */
  window.GAPS = { A, E, I, D, H, top, setTop, below, clamp, pad, short, P, sheet, page, actions, grow, ghost, primary, koNote, help, helpAttrs, anchor, RDX, art, shotMock };
})();

/* ==========================================================================
   Gaps · part 2 — reader surfaces
   ========================================================================== */
(function () {
  const { A, E, I, top, setTop, clamp, pad, short, sheet, page, actions, grow, ghost, primary, koNote, help, helpAttrs, anchor } = window.GAPS;
  const RD = window.RD;
  const cur = () => RD.cur();
  const L_ = () => RD.layout(cur().id);
  const btn = UI.button;

  /* ------------------------------------------------ status bar modes (ReaderFooter) */
  const FOOT = {
    page: { label: "Page number", text: (L, pi) => ["", `<span class="num pg">${pi + 1}<span class="of"> / ${L.total}</span></span>`] },
    bookleft: { label: "Pages left in book", text: (L, pi) => [`<span class="num">${L.total - pi - 1} pages left in book</span>`, ""] },
    clock: { label: "Clock", text: () => [`<span class="num">21:40</span>`, ""] },
    chleft: { label: "Pages left in chapter", text: (L, pi, f) => [`<span class="num">${f.chPages - f.inCh} pages left in chapter</span>`, ""] },
    battery: { label: "Battery level", text: () => [`<span class="num">Battery 87%</span>`, ""] },
    pct: { label: "Progress percentage", text: (L, pi, f) => [`<span class="num">${f.pct}%</span>`, ""] },
    booktime: { label: "Time left in book", text: () => [`<span class="num">4 h 10 min left in book</span>`, ""] },
    chtime: { label: "Time left in chapter", text: (L, pi, f) => [`<span class="num">${f.mins} min left in chapter</span>`, ""] },
    chprog: { label: "Page in chapter", text: (L, pi, f) => [`<span class="num">Page ${f.inCh} of ${f.chPages} in chapter</span>`, ""] },
    bar: { label: "Progress bar only", text: () => null },
    off: { label: "Hidden", text: () => null },
  };
  const CYCLE = ["page", "bookleft", "clock", "chleft", "battery", "pct", "booktime", "chtime", "chprog", "off"];
  let footDirty = false;
  A.overlay("footer-mode", {
    layer: "popover", clear: true,
    render: (p) => `<button class="gp-foot-tap" data-action="gpFootCycle" aria-label="Status bar: ${E(FOOT[p.m || "page"].label)} · tap for the next item"></button>`,
    mount(el, p) {
      const L = L_(), f = document.querySelector("#screen-root .rd-foot"); if (!L || !f) return;
      const pi = cur().page - 1, inf = RD.pageInfo(L, pi), m = FOOT[p.m || "page"], t = m.text(L, pi, inf);
      footDirty = true;
      f.classList.toggle("gp-foot-off", p.m === "off");
      const row = f.querySelector(".rd-foot-row");
      if (row) { row.style.display = t ? "" : "none"; if (t) row.innerHTML = `<span>${t[0]}</span>${t[1]}`; }
    },
  });
  A.action("gpFootCycle", () => { const m = top().m || "page", n = CYCLE[(CYCLE.indexOf(m) + 1) % CYCLE.length]; setTop({ m: n }); A.toast(`Status bar · ${FOOT[n].label}`); });
  document.addEventListener("leaf:navigate", () => { if (footDirty && !(A.top() && A.top().name === "footer-mode")) { footDirty = false; A.refresh(); } });

  /* ------------------------------------------------ flipping / render state mark (ReaderFlipping) */
  const FLIP = {
    flip: { icon: "book-open", label: "Flipping", banner: "Flipping mode · drag sideways to skip pages, up or down to move through the book. Tap the status bar to jump.", exit: "Exit" },
    bm: { icon: "bookmark", label: "Bookmarks", banner: "Bookmark flipping · swipe left or right to go to the next or previous bookmark.", exit: "Exit" },
    select: { icon: "text-select", label: "Selecting", banner: "Tap the word where the selection should end. It can be on another page.", exit: "Cancel" },
    render: { icon: "loader-circle", spin: true, label: "Re-rendering", banner: "Laying out the book with the new font in the background. You can keep reading." },
    ready: { icon: "refresh-cw", label: "Layout ready", banner: "The new layout is ready and is used from the next page turn.", exit: "Use now" },
  };
  A.overlay("flipping", {
    layer: "popover", clear: true,
    render(p) {
      const f = FLIP[p.k || "flip"];
      return `<div class="gp-flipmark ${p.k === "render" ? "soft" : ""}" aria-label="${E(f.label)}">${I(f.icon, f.spin ? "ko-spin" : "")}<span>${E(f.label)}</span></div>
        <div class="ko-popover gp-float gp-banner">${I(f.icon, f.spin ? "ko-spin" : "")}<span class="grow">${E(f.banner)}</span>${f.exit ? btn({ label: f.exit, size: "sm", attrs: "data-close" }) : ""}</div>`;
    },
  });

  /* ------------------------------------------------ tapped link (LinkBox) + external link dialog */
  A.overlay("linkbox", {
    layer: "popover", clear: true,
    render: () => `<div class="gp-linkbox" aria-hidden="true"></div>`,
    mount(el) {
      const box = el.querySelector(".gp-linkbox"), scr = document.querySelector(".ko-screen").getBoundingClientRect();
      const ws = [...document.querySelectorAll("#screen-root .rd-scan .w")];
      const pick = ws.slice(52, 56);
      if (!box || !pick.length) return;
      const rs = pick.map((w) => w.getBoundingClientRect()).filter((r) => Math.abs(r.top - pick[0].getBoundingClientRect().top) < 4);
      const x0 = Math.min(...rs.map((r) => r.left)), x1 = Math.max(...rs.map((r) => r.right)), y0 = Math.min(...rs.map((r) => r.top)), y1 = Math.max(...rs.map((r) => r.bottom));
      Object.assign(box.style, { left: x0 - scr.left - 4 + "px", top: y0 - scr.top - 3 + "px", width: x1 - x0 + 8 + "px", height: y1 - y0 + 6 + "px" });
    },
  });
  A.overlay("link-ext", {
    layer: "sheet",
    render(p) {
      const wiki = p.wiki === 1 || p.wiki === "1";
      const url = wiki ? "https://en.wikipedia.org/wiki/Windmill" : "https://www.orwellfoundation.com/the-orwell-foundation/orwell/essays";
      const rows = [];
      if (wiki) rows.push(UI.row({ icon: "globe", label: "Read online", sub: "Opens the article in the Wikipedia reader", attrs: { action: "gpSwapTo", arg: "wiki", params: { demo: 1 } } }),
        UI.row({ icon: "book-open", label: "Read the saved EPUB", sub: "Saved on Nov 2 · Wikipedia/Windmill.epub", attrs: { action: "gpToastClose", arg: "Opening Windmill.epub" } }));
      rows.push(UI.row({ icon: "external-link", label: "Open in browser", attrs: { action: "gpToastClose", arg: "Opening the browser" } }),
        UI.row({ icon: "copy", label: "Copy link", attrs: { action: "gpToastClose", arg: "Link copied" } }),
        UI.row({ icon: "qr-code", label: "Show QR code", sub: "Scan it with your phone", attrs: { action: "gpSwapTo", arg: "qr", params: { text: url } } }),
        UI.row({ icon: "inbox", label: "Add to Wallabag", attrs: { action: "gpToastClose", arg: "Added to Wallabag" } }));
      return actions({ title: wiki ? "Wikipedia article" : "External link", sub: url.replace(/^https:\/\//, ""), lead: UI.iconTile(wiki ? "globe" : "link"), body: UI.group(rows) });
    },
  });
  A.action("gpSwapTo", (el) => { let pr = {}; try { pr = JSON.parse(el.dataset.params || "{}"); } catch { /* none */ } A.replaceTop(el.dataset.arg, pr); });

  /* ------------------------------------------------ bookmarks: long-press, details, select mode */
  const marks = (id) => {
    const L = RD.layout(id); if (!L) return [];
    const bm = RD.bms(id).map((m) => ({ kind: "bm", ...m, pg: RD.pageOf(L, m) + 1, text: "" }));
    const hl = RD.hls(id).map((h) => ({ kind: "hl", ...h, pg: RD.pageOf(L, { ch: h.ch, pid: h.pid, a: h.a }) + 1, text: RD.hlText(id, h) }));
    return bm.concat(hl).sort((a, b) => a.pg - b.pg);
  };
  const STYLE = { lighten: "Highlight", underscore: "Underline", strikeout: "Strikeout", invert: "Invert" };
  const cap = (s) => s ? s[0].toUpperCase() + s.slice(1) : "";
  A.overlay("bm-actions", {
    layer: "sheet",
    render(p) {
      const { id } = cur(), ms = marks(id); if (!ms.length) return "";
      const m = ms[clamp(+(p.i || 0), 0, ms.length - 1)], ch = RD.chapters(id)[m.ch];
      const hl = m.kind === "hl";
      const g1 = [UI.row({ icon: "arrow-right", label: `Go to page ${m.pg}`, attrs: { action: "gpBmGo", arg: m.pg } }),
        UI.row({ icon: "panel-top-open", label: "View details", attrs: { action: "gpSwapTo", arg: "bm-view", params: { i: +(p.i || 0) } } }),
        UI.row({ icon: "notebook-pen", label: m.note ? "Edit note" : "Add note", attrs: { action: "gpSwapTo", arg: "input", params: { title: m.note ? "Edit note" : "Add note", value: m.note || "", hint: "Note", ok: "Save" } } })];
      if (hl) g1.push(UI.row({ icon: "text-cursor-input", label: "Edit highlighted text", sub: "Fix OCR or hyphenation mistakes", attrs: { action: "gpSwapTo", arg: "input", params: { title: "Edit highlighted text", value: m.text, ok: "Save" } } }),
        UI.row({ icon: "rotate-ccw", label: "Reset to the original text", disabled: true }),
        UI.row({ icon: "palette", label: "Style and colour", value: `${STYLE[m.style]} · ${cap(m.color)}`, trailing: "chevron", attrs: { action: "gpSwapTo", arg: "hl-popup", params: { id, hid: m.hid } } }));
      const g2 = [UI.row({ icon: "list-checks", label: "Select several…", attrs: { action: "gpSwapTo", arg: "bm-select", params: { sel: [+(p.i || 0)] } } }),
        UI.row({ icon: "trash-2", label: hl ? "Remove highlight" : "Remove bookmark", danger: true, attrs: { action: "gpToastClose", arg: hl ? "Highlight removed" : "Bookmark removed" } })];
      return actions({ title: `Page ${m.pg} · ${ch.label}`, sub: hl ? `“${m.text}”` : `Bookmark · ${m.date}`, lead: UI.iconTile(hl ? "highlighter" : "bookmark"), body: UI.group(g1) + UI.group(g2, { cls: "gp-gap" }) });
    },
  });
  A.action("gpBmGo", (el) => { A.closeAll(); RD.goPage(cur().id, +el.dataset.arg); });
  A.overlay("bm-view", {
    layer: "sheet",
    render(p) {
      const { id } = cur(), ms = marks(id); if (!ms.length) return "";
      const i = clamp(+(p.i || 0), 0, ms.length - 1), m = ms[i], ch = RD.chapters(id)[m.ch], hl = m.kind === "hl";
      const nav = UI.iconButton({ icon: "chevron-left", label: "Previous (hold: first)", attrs: { action: "gpBmView", arg: i - 1 }, disabled: i === 0 }) + UI.iconButton({ icon: "chevron-right", label: "Next (hold: last)", attrs: { action: "gpBmView", arg: i + 1 }, disabled: i === ms.length - 1 });
      const meta = [m.date, `Page ${m.pg}`, hl ? STYLE[m.style] : "Page bookmark", hl ? cap(m.color) : ""].filter(Boolean).join(" · ");
      const body = `<div class="gp-bmv"><div class="ko-eyebrow">${E(ch.label)} · ${E(ch.title)}</div><div class="gp-bmv-meta">${I(hl ? "highlighter" : "bookmark", "sm")}<span>${E(meta)}</span></div>
        ${hl ? `<blockquote class="gp-quote">${E(m.text)}</blockquote>` : `<blockquote class="gp-quote">${E(RD.hlText(id, { ch: m.ch, pid: m.pid, a: m.a, b: m.a + 24 }))}…</blockquote>`}
        ${UI.card(m.note ? `<div class="gp-bmv-note">${I("pen-line", "sm")}<span>${E(m.note)}</span></div>` : `<div class="gp-bmv-note faint">${I("pen-line", "sm")}<span>No note yet</span></div>`, { sunken: true, sm: true })}</div>`;
      return sheet("gp-bmview", UI.sheetHead({ title: `${i + 1} of ${ms.length}`, sub: hl ? "Highlight" : "Bookmark", actions: nav }), body,
        `${UI.iconButton({ icon: "trash-2", label: "Remove", attrs: { open: "confirm", params: { title: "Remove this bookmark?", ok: "Remove", danger: true } } })}
         ${hl ? UI.iconButton({ icon: "text-cursor-input", label: "Edit text", attrs: { open: "input", params: { title: "Edit highlighted text", value: m.text, ok: "Save" } } }) + UI.iconButton({ icon: "rotate-ccw", label: "Reset text", disabled: true }) : ""}
         ${grow}${btn({ label: m.note ? "Edit note" : "Add note", attrs: { open: "input", params: { title: "Note", value: m.note || "", ok: "Save" } } })}${primary("Go to", { action: "gpBmGo", arg: m.pg })}`);
    },
  });
  A.action("gpBmView", (el) => setTop({ i: +el.dataset.arg }));
  A.overlay("bm-select", {
    layer: "sheet",
    render(p) {
      const { id, page: pg } = cur(), ms = marks(id), sel = new Set([].concat(p.sel ?? [0, 2, 3]).map(Number));
      const rows = ms.map((m, i) => UI.row({ icon: m.kind === "hl" ? "highlighter" : "bookmark", label: m.kind === "hl" ? `“${m.text.replace(/^[“"]+|[”"]+$/g, "")}”` : `Page ${m.pg} bookmark`, sub: `Page ${m.pg} · ${m.date}${m.note ? " · note" : ""}`, trailing: "check", on: sel.has(i), sel: sel.has(i), attrs: { action: "gpBmSel", arg: i } }));
      const n = sel.size, notes = ms.filter((m, i) => sel.has(i) && m.note).length;
      return sheet("gp-bmsel", UI.sheetHead({ title: n ? `${n} selected` : "None selected", sub: `Bookmarks & highlights · ${ms.length}`,
        actions: btn({ kind: "link", label: "All", attrs: { action: "gpBmSelAll", arg: 1 } }) + btn({ kind: "link", label: "This page", attrs: { action: "gpBmSelPage", arg: pg } }) + btn({ kind: "link", label: "None", attrs: { action: "gpBmSelAll", arg: 0 } }), closeAttrs: "data-close" }),
        UI.list(rows, { inset: true }),
        `${ghost("Done", "data-close")}${grow}${btn({ label: `Delete notes${notes ? " · " + notes : ""}`, disabled: !notes, attrs: { open: "confirm", params: { title: "Delete the notes of the selected items?", body: "The highlights stay; only their notes are removed.", ok: "Delete", danger: true } } })}${btn({ label: `Remove ${n || ""}`.trim(), kind: "danger", disabled: !n, attrs: { open: "confirm", params: { title: `Remove ${n} selected item${n === 1 ? "" : "s"}?`, body: "Bookmarks, highlights and their notes are deleted.", ok: "Remove", danger: true } } })}`);
    },
  });
  const selOf = () => new Set([].concat(top().sel ?? [0, 2, 3]).map(Number));
  A.action("gpBmSel", (el) => { const s = selOf(), i = +el.dataset.arg; s.has(i) ? s.delete(i) : s.add(i); setTop({ sel: [...s] }); });
  A.action("gpBmSelAll", (el) => setTop({ sel: +el.dataset.arg ? marks(cur().id).map((_, i) => i) : [] }));
  A.action("gpBmSelPage", (el) => setTop({ sel: marks(cur().id).map((m, i) => (m.pg === +el.dataset.arg ? i : -1)).filter((i) => i >= 0) }));

  /* ------------------------------------------------ in-page search navigation */
  A.overlay("search-nav", {
    layer: "popover", clear: true,
    render(p) {
      const k = p.k || "result", ib = (icon, label, attrs, o = {}) => UI.iconButton({ icon, label, attrs, ...o });
      let inner;
      if (k === "wait") inner = `${I("loader-circle", "ko-spin")}<span class="grow">Searching for “windmill”…</span>${btn({ label: "Cancel", size: "sm", attrs: "data-close" })}`;
      else if (k === "bar") inner = `${ib("chevron-first", "Search from the start", { toast: "Searching from the start" })}${ib("chevron-left", "Previous match", { toast: "Previous match · page 9" })}
        <button class="gp-sn-q" data-open="input" data-params='${A.attrs({ title: "Search in book", value: "windmill", ok: "Search" })}'>${I("search", "sm")}<span class="ellipsis">windmill</span></button>
        ${ib("chevron-right", "Next match", { toast: "Next match · page 14" })}${ib("chevron-last", "Search from the end", { toast: "Searching from the end" })}<span class="gp-sn-sep"></span>${ib("x", "Close search", "data-close")}`;
      else inner = `${ib("undo-2", "Back to page 12, where you started", { action: "gpBmGo", arg: 12 })}<span class="gp-sn-sep"></span>${ib("chevron-left", "Previous result (hold: first)", { toast: "Result 2 of 41" })}
        <button class="gp-sn-q" data-go="search" data-params='${A.attrs({ q: "windmill", scope: "book", id: cur().id })}'><span class="num">3 of 41</span><span class="faint">results</span></button>
        ${ib("chevron-right", "Next result (hold: last)", { toast: "Result 4 of 41" })}<span class="gp-sn-sep"></span>${ib("search", "New search", { open: "input", params: { title: "Search in book", value: "windmill", ok: "Search" } })}${ib("x", "Close search", "data-close")}`;
      return `<div class="ko-popover gp-float gp-sn ${k}">${inner}</div>`;
    },
  });

  /* ------------------------------------------------ gesture quick menu */
  A.overlay("quickmenu", {
    layer: "popover",
    render(p) {
      const prof = p.k === "profile";
      const rows = [
        ["moon", "Night mode"], ["sun", "Frontlight"], ["map", "Book map"], ["bookmark", "Toggle bookmark"], ["list", "Table of contents"], "-",
        ["pin", "Go to pinned page", true], ["languages", "Translate this page"], ["chart-no-axes-column", "Book statistics"],
      ];
      return `<div class="ko-popover gp-qm">
        <div class="gp-qm-top">${UI.eyebrow(prof ? "Profile" : "Gesture")}<div class="gp-qm-title">${prof ? "Night reading" : "Two-finger swipe up"}</div></div>
        ${prof ? UI.row({ icon: "play", label: "Run all actions", attrs: { action: "gpToastClose", arg: "Night reading · 4 actions done" } }) + '<div class="ko-divider"></div>' : ""}
        ${rows.map((r) => (r === "-" ? '<div class="ko-divider"></div>' : UI.row({ icon: r[0], label: r[1], disabled: !!r[2], sub: r[2] ? "No pinned page in this book" : undefined, attrs: { action: "gpToastClose", arg: r[1] } }))).join("")}
        <div class="ko-divider"></div>${UI.row({ icon: "settings-2", label: "Edit this gesture…", attrs: { go: "tapzones", params: { tab: "swipe" } } })}</div>`;
    },
  });

  /* ------------------------------------------------ overlapping highlights chooser */
  A.overlay("hl-multi", {
    layer: "popover", clear: true,
    render() {
      const { id } = cur(), hs = RD.hls(id).slice(0, 3);
      return `<div class="ko-popover gp-pop gp-hlm">${UI.sectionLabel(`${hs.length} highlights here`)}
        ${hs.map((h) => UI.row({ lead: `<span class="gp-sw ${h.style} c-${h.color}" aria-hidden="true"></span>`, label: `“${RD.hlText(id, h).replace(/^[“"]+|[”"]+$/g, "")}”`, sub: `${STYLE[h.style]} · ${cap(h.color)}${h.note ? " · has a note" : ""}`, attrs: { action: "gpSwapTo", arg: "hl-popup", params: { id, hid: h.hid } } })).join("")}</div>`;
    },
    mount(el) { anchor(el, ".gp-hlm", "mark.hl"); },
  });

  /* ------------------------------------------------ perception expander */
  A.overlay("perception", {
    layer: "popover", clear: true,
    render(p) {
      if (p.set) return "";
      return `<i class="gp-pe-line l" aria-hidden="true"></i><i class="gp-pe-line r" aria-hidden="true"></i>
        <div class="ko-popover gp-float gp-banner">${I("columns-2")}<span class="grow">Perception expander · read each line between the guides, without moving your eyes to the edges.</span>${btn({ label: "Settings", size: "sm", attrs: { action: "gpSwapTo", arg: "pe-set" } })}</div>`;
    },
  });
  A.overlay("pe-set", {
    layer: "sheet",
    render() {
      const sr = (label, pct, value, unit) => UI.sliderRow({ label, pct, value, unit, slide: "gpNoop", step: "gpNoop" });
      return sheet("gp-pe", UI.sheetHead({ title: "Perception expander", sub: "Speed reading guides" }),
        UI.group([UI.row({ icon: "columns-2", label: "Show guide lines", trailing: "toggle", on: true, attrs: { action: "gpTg" } })])
        + UI.sectionLabel("Lines") + `<div class="gp-srs">${sr("Thickness", 25, "2", "px")}${sr("From edges", 20, "10", "%")}${sr("Darkness", 30, "3", "/10")}${sr("Move in after", 20, "100", "pg")}</div>`
        + help("Every time you read that many pages the guides move 3% closer together, up to 37% from each edge. Set it to 0 to keep them still.")
        + UI.group([UI.row({ icon: "info", label: "About perception expander", trailing: "chevron", attrs: { open: "gap-help", params: { title: "Perception expander", text: "Two thin lines help you take in a whole line of text with one glance instead of reading word by word. Start with the lines near the edges and let them move inwards as you practise." } } })], { cls: "gp-gap" }),
        `${ghost("Cancel", "data-close")}${grow}${primary("Apply", { action: "gpToastClose", arg: "Guides updated" })}`);
    },
  });
  A.action("gpNoop", (el, v, done) => { const r = el.closest(".ko-sr"); if (r && typeof v === "number") { const val = r.querySelector(".val"); if (val && val.firstChild) val.firstChild.textContent = Math.round(v * 100); } });
  A.action("gpTg", (el) => el.querySelector(".ko-toggle")?.classList.toggle("on"));

  /* ------------------------------------------------ manual PDF crop (BBoxWidget) */
  A.overlay("crop", {
    layer: "page",
    render() {
      const { id, page: pg } = cur(), L = L_(); if (!L) return "";
      const { w, h } = RD.screenSize(), S = RD.SCAN;
      const s = Math.min((Math.min(w, 760) - 48) / S.w, (h - 26 - 64 - 76 - 40) / S.h);
      const bx = { x0: 34, y0: 28, x1: 388, y1: 570 };
      const px = (v) => (v * s).toFixed(1) + "px";
      const handles = [["nw", bx.x0, bx.y0], ["n", (bx.x0 + bx.x1) / 2, bx.y0], ["ne", bx.x1, bx.y0], ["e", bx.x1, (bx.y0 + bx.y1) / 2], ["se", bx.x1, bx.y1], ["s", (bx.x0 + bx.x1) / 2, bx.y1], ["sw", bx.x0, bx.y1], ["w", bx.x0, (bx.y0 + bx.y1) / 2]];
      const stage = `<div class="gp-crop-stage" style="width:${px(S.w)};height:${px(S.h)}">
          <div class="gp-crop-scan" style="transform:scale(${s.toFixed(4)})">${RD.scanHTML(L, pg - 1, { thumb: true })}</div>
          <i class="gp-crop-dim" style="left:0;top:0;width:100%;height:${px(bx.y0)}"></i><i class="gp-crop-dim" style="left:0;top:${px(bx.y1)};width:100%;bottom:0"></i>
          <i class="gp-crop-dim" style="left:0;top:${px(bx.y0)};width:${px(bx.x0)};height:${px(bx.y1 - bx.y0)}"></i><i class="gp-crop-dim" style="left:${px(bx.x1)};top:${px(bx.y0)};right:0;height:${px(bx.y1 - bx.y0)}"></i>
          <i class="gp-crop-box" style="left:${px(bx.x0)};top:${px(bx.y0)};width:${px(bx.x1 - bx.x0)};height:${px(bx.y1 - bx.y0)}"></i>
          ${handles.map(([k, x, y]) => `<button class="gp-crop-h ${k}" style="left:${px(x)};top:${px(y)}" data-toast="Drag to move this ${k.length > 1 ? "corner" : "edge"}" aria-label="Move ${k} handle"></button>`).join("")}</div>`;
      return page("gp-crop", UI.pageHead({ title: "Crop margins", crumbs: [short(RD.book(id)), `Page ${pg}`], back: "data-close", rule: true }),
        `<div class="gp-crop-wrap">${stage}</div>`,
        `<div class="grow gp-path"><span>Tap or drag near an edge or a corner to move it.</span><span class="faint">Applies to this page and every ${pg % 2 ? "odd" : "even"} page.</span></div>${ghost("Cancel", "data-close")}${primary("Apply crop", { action: "gpToastClose", arg: "Margins cropped" })}`);
    },
  });

  /* ------------------------------------------------ busy (Kindle activity indicator replacement) */
  A.overlay("busy", {
    layer: "popover", clear: true,
    render: () => `<div class="ko-toast gp-busy">${I("loader-circle", "sm ko-spin")}<span>Reflowing page…</span></div>`,
  });

  /* ------------------------------------------------ pinned page in Go to */
  A.overlay("goto-pin", {
    layer: "sheet",
    render(p) {
      const html = A.overlays.goto.render({}); const pinned = p.none ? 0 : 42;
      const row = `<div class="gp-pin">${UI.eyebrow("Pinned page", { icon: "pin" })}${grow}
        ${pinned ? UI.chip({ label: `Go to page ${pinned}`, icon: "corner-down-right", attrs: { action: "gpBmGo", arg: pinned } }) : ""}
        ${UI.chip({ label: pinned ? "Pin this page instead" : "Pin this page", icon: "pin", attrs: { action: "gpToastClose", arg: "Page pinned" } })}
        ${pinned ? UI.iconButton({ icon: "pin-off", label: "Remove pinned page", size: "sm", attrs: { open: "confirm", params: { title: "Remove the pinned page?", body: "Page 42 stays as it is; only the pin is removed.", ok: "Remove", danger: true } } }) : ""}</div>`;
      return html.replace('<div class="rd-sheet-foot">', row + '<div class="rd-sheet-foot">');
    },
  });

  /* ------------------------------------------------ stable page numbers (ReaderPageMap) */
  const ROM = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii"];
  A.overlay("pagemap", {
    layer: "page",
    render() {
      const { id } = cur(), b = RD.book(id), here = 23;
      const labels = ROM.concat(Array.from({ length: 48 }, (_, i) => String(i + 1)));
      const rows = labels.map((l, i) => UI.row({ label: `Page ${l}`, value: `${i + 3} on screen`, sel: i === here, trailing: i === here ? UI.pill("You are here", { kind: "current", sm: true }) : "none", attrs: { action: "gpBmGo", arg: i + 3 } })).join("");
      return page("gp-pm", UI.pageHead({ title: "Stable page numbers", crumbs: [short(b)], back: "data-close", rule: true, actions: UI.iconButton({ icon: "settings-2", label: "Page number settings", attrs: { action: "gpSwapTo", arg: "pagemap-set" } }) }),
        `<div class="gp-pm-src">${UI.pill("Publisher", { kind: "current", sm: true })}<span>Print edition · Penguin Classics, 2008 · pages i–xii, 1–214</span></div>${UI.list([rows])}`,
        `<span class="faint">Page 12 of the print edition</span>${grow}${btn({ label: "Go to a page…", icon: "hash", attrs: { open: "input", params: { title: "Go to page", hint: "Print page, e.g. 12 or xii", ok: "Go" } } })}`);
    },
    mount(el) { RD.center && RD.center(el, ".ko-row.sel"); },
  });
  A.overlay("pagemap-set", {
    layer: "sheet",
    render() {
      const t = (icon, label, on, sub) => UI.row({ icon, label, sub, trailing: "toggle", on, attrs: { action: "gpTg" } });
      return sheet("gp-pms", UI.sheetHead({ title: "Stable page numbers", sub: "Page numbers that don't change with the font" }),
        UI.sectionLabel("This book") + UI.group([
          t("hash", "Use stable page numbers", true, "In the status bar, Go to and notes"),
          t("panel-left", "Show them in the margin", false),
          UI.row({ icon: "book-copy", label: "Numbers come from", value: "Print edition", trailing: "chevron", attrs: helpAttrs("Publisher page numbers", "Publisher page numbers available. Pages i – 214. Source (print edition): Penguin Classics, London 2008. ISBN 978-0-14-118776-1.") }),
          UI.row({ icon: "type", label: "Characters per page", value: "1818", trailing: "chevron", attrs: { open: "spin", params: { k: "cpp" } } }),
          UI.row({ icon: "list-ordered", label: "Page number list", trailing: "chevron", attrs: { action: "gpSwapTo", arg: "pagemap" } }),
        ]) + UI.sectionLabel("New books") + UI.group([
          t("hash", "Use stable page numbers", true), t("panel-left", "Show them in the margin", false),
          t("book-copy", "Prefer publisher page numbers", true, "When the book has them"), t("message-circle-question", "Ask before using publisher numbers", false),
          UI.row({ icon: "type", label: "Characters per page", value: "Off", trailing: "chevron", attrs: { open: "spin", params: { k: "cpp" } } }),
        ]) + `<div class="gp-srs">${UI.sliderRow({ label: "Number size", pct: 33, value: "12", slide: "gpNoop", step: "gpNoop" })}</div>`
        + UI.group([UI.row({ icon: "info", label: "About stable page numbers", trailing: "chevron", attrs: helpAttrs("Stable page numbers", "Leaf counts pages from the layout on screen, so the number changes when you change the font. Stable page numbers stay the same on every device: they come from the printed edition when the book has them, or are counted every fixed number of characters.") })], { cls: "gp-gap" }));
    },
  });

  /* ------------------------------------------------ style tweaks: info, book-specific editor */
  const CSS_HY = `* {
    hyphens: auto !important;
    -cr-hint: none;
}`;
  A.overlay("tweak-info", {
    layer: "sheet",
    render() {
      return sheet("gp-twk", UI.sheetHead({ title: "Hyphenate all text", sub: "Style tweak · Text › Hyphenation" }),
        `<div class="gp-pad">${help("Hyphenate words in every paragraph, even where the book's own style sheet turns hyphenation off.")}
          <div class="gp-code-wrap"><pre class="gp-code">${E(CSS_HY)}</pre>${UI.iconButton({ icon: "copy", label: "Copy CSS", size: "sm", attrs: { toast: "CSS copied" }, cls: "gp-code-copy" })}</div></div>`
        + UI.group([UI.row({ icon: "globe", label: "Use on all books", sub: "Otherwise only on this book", trailing: "toggle", on: true, attrs: { action: "gpTg" } }),
          UI.row({ icon: "hand", label: "Show in the gesture action list", trailing: "toggle", on: false, attrs: { action: "gpTg" } })]),
        `${UI.pill("On in all books", { kind: "current" })}${grow}${primary("Close", "data-close")}`);
    },
  });
  const TW_TEXT = `/* Only for this book */
p.dropcap::first-letter {
    font-size: 3em;
    float: left;
}
.footnote {
    -cr-hint: footnote-inpage;
}
blockquote {
    margin-left: 1.2em;
    font-style: italic;
}`;
  A.overlay("tweak-editor", {
    layer: "page",
    render(p) {
      const { id } = cur(), lines = TW_TEXT.split("\n");
      const ed = page("gp-twe", UI.pageHead({ title: "Book style tweak", crumbs: [short(RD.book(id)), "Style tweaks"], back: "data-close", rule: true,
        actions: UI.iconButton({ icon: "history", label: "Restore the last saved version", attrs: { toast: "Book tweak restored" } }) }),
        `<div class="gp-twe-tools">${btn({ label: "Prettify", icon: "wand-sparkles", size: "sm", attrs: { toast: "Prettified · tap again to condense" } })}${btn({ label: "CSS snippets", icon: "list", size: "sm", attrs: { action: "gpTwMenu" }, cls: "gp-twe-css" })}${grow}<span class="faint gp-twe-pos num">Ln 6 · ${lines.length} lines</span></div>
         <div class="gp-twe-doc">${lines.map((l, i) => `<div class="gp-ln ${i === 5 ? "cur" : ""}"><span class="num">${i + 1}</span><span>${E(l) || "&nbsp;"}</span></div>`).join("")}</div>`,
        `<span class="faint">Applies only to this book</span>${grow}${ghost("Close", { action: "gpTwClose" })}${primary("Apply", { action: "gpToastClose", arg: "Book tweak updated, applying…" })}`);
      const menu = p.menu ? `<div class="ko-scrim clear" data-action="gpTwMenu"></div><div class="ko-popover gp-pop gp-twm">${UI.sectionLabel("Insert a snippet")}
          ${[["crosshair", "Matching elements", "p.className, aside > p, p:first-child…"], ["paintbrush", "Common properties", "font-size, text-indent, hyphens…"], ["cpu", "Reader-only properties", "-cr-hint: footnote-inpage, toc-level1…"], ["quote", "Useful content: values", "::before snippets"]]
            .map(([ic, l, s]) => UI.row({ icon: ic, label: l, sub: s, trailing: "chevron", attrs: { toast: `${l} · tap one to insert, hold for its description` } })).join("")}
          <div class="gp-kp-hint">Tip: View HTML shows the classes this book uses.</div></div>` : "";
      const dirty = p.dirty ? `<div class="ko-scrim"></div>${UI.dialog({ title: "Unsaved changes", body: "You changed this book's tweak. Apply it before closing?", actions: [ghost("Cancel", { action: "gpTwDirty" }), grow, ghost("Discard", "data-close"), primary("Apply", { action: "gpToastClose", arg: "Book tweak updated, applying…" })] })}` : "";
      return ed + menu + dirty;
    },
    mount(el, p) { if (p.menu) anchor(el, ".gp-twm", ".gp-twe-css"); },
  });
  A.action("gpTwMenu", () => setTop({ menu: top().menu ? "" : 1 }));
  A.action("gpTwClose", () => setTop({ dirty: 1 }));
  A.action("gpTwDirty", () => setTop({ dirty: "" }));

  /* ------------------------------------------------ dictionary popup: results menu, look-up input, Wikipedia language */
  A.overlay("dict-menu", {
    layer: "sheet",
    render(p) {
      const k = p.k || "results";
      if (k === "lookup") {
        A.kbInit("gplookup", "silence", p);
        return UI.dialog({ cls: "dl-input gp-lookup", title: "Look up a word",
          bodyHtml: A.kbField("gplookup", { placeholder: "Word or phrase", cls: "kb-field--compact" })
            + UI.group([UI.row({ icon: "text-search", label: "Find in this definition", attrs: { action: "gpToastClose", arg: "3 matches in the definition" } }),
              UI.row({ icon: "languages", label: "Translate", attrs: { action: "gpSwapTo", arg: "translate", params: {} } }),
              UI.row({ icon: "globe", label: "Search Wikipedia", attrs: { action: "gpSwapTo", arg: "wiki", params: { demo: 1 } } }),
              UI.row({ icon: "sliders-horizontal", label: "Search with a preset", value: "Arabic books", trailing: "chevron", attrs: { toast: "Dictionary presets" } })], { sunken: true, cls: "gp-lookup-g" }),
          actions: [ghost("Cancel", "data-close"), primary("Look up", { action: "gpToastClose", arg: "Looking up…" })] })
          + `<div class="dl-kbdock">${A.keyboardHTML({ target: "gplookup", enter: "Look up" })}</div>`;
      }
      if (k === "wikilang") {
        return A.overlays.wiki.render({ demo: 1 }) + `<div class="ko-scrim clear" data-close></div><div class="ko-popover gp-pop gp-dm">${UI.sectionLabel("Wikipedia language")}
          ${[["English", 1], ["العربية · Arabic"], ["Français · French"], ["Deutsch · German"]].map(([l, on]) => UI.row({ label: l, trailing: "radio", on: !!on, attrs: { action: "gpToastClose", arg: `Searching ${l.split(" · ").pop()} Wikipedia` } })).join("")}
          <div class="ko-divider"></div>${UI.row({ icon: "settings-2", label: "Wikipedia languages…", attrs: { go: "settings", params: { section: "search" } } })}</div>`;
      }
      const dicts = DB.DICTIONARIES;
      return A.overlays.dict.render({ demo: 1 }) + `<div class="ko-scrim clear" data-close></div><div class="ko-popover gp-pop gp-dm">${UI.sectionLabel("Results")}
        ${dicts.map((d, i) => UI.row({ label: /AR|Mawrid/.test(d) ? "سكوت" : i === 2 ? "silences" : "silence", sub: d, trailing: "radio", on: i === 0, attrs: { action: "gpSwapTo", arg: "dict", params: { demo: 1, d: i } } })).join("")}
        <div class="ko-divider"></div>
        ${UI.row({ icon: "chevrons-left", label: "First dictionary", attrs: { action: "gpSwapTo", arg: "dict", params: { demo: 1, d: 0 } } })}
        ${UI.row({ icon: "chevrons-right", label: "Last dictionary", attrs: { action: "gpSwapTo", arg: "dict", params: { demo: 1, d: dicts.length - 1 } } })}
        ${UI.row({ icon: "pencil", label: "Look up another word…", attrs: { action: "gpSwapTo", arg: "dict-menu", params: { k: "lookup" } } })}</div>`;
    },
    mount(el, p) { if ((p.k || "results") === "results") anchor(el, ".gp-dm", ".rd-dict-head .hw"); if (p.k === "wikilang") anchor(el, ".gp-dm", ".ko-sheet-head .title"); },
  });

  /* ------------------------------------------------ book map / page browser options */
  const segRow = (label, items) => `<div class="ko-row gp-choice"><span class="label">${E(label)}</span>${UI.seg(items.map(([l, on]) => ({ label: l, on, attrs: { action: "gpSegPick" } })), { size: "sm" })}</div>`;
  A.action("gpSegPick", (el) => { el.parentElement.querySelectorAll("button").forEach((b) => b.classList.toggle("on", b === el)); });
  const sr = (label, pct, value) => UI.sliderRow({ label, pct, value, slide: "gpNoop", step: "gpNoop" });
  A.overlay("bookmap-menu", {
    layer: "page",
    render() {
      const base = A.overlays.bookmap.render({});
      return base + `<div class="ko-scrim" data-close></div>` + sheet("gp-bmo", UI.sheetHead({ title: "Book map options" }),
        UI.group([UI.row({ icon: "layout-grid", label: "Tapping a page opens the page browser", trailing: "toggle", on: true, attrs: { action: "gpTg" } }),
          UI.row({ icon: "contrast", label: "Alternative look", sub: "Outlined cells instead of filled ones", trailing: "toggle", on: false, attrs: { action: "gpTg" } })])
        + `<div class="gp-choices">${segRow("Layout", [["Grid", 1], ["Flat"]])}${segRow("Open at", [["Current page", 1], ["Where I started"]])}</div>`
        + `<div class="gp-srs">${sr("Chapter levels", 33, "2")}${sr("Page width", 40, "4")}${sr("10-page marks", 50, "1")}</div>`
        + UI.group([UI.row({ icon: "info", label: "About the book map", trailing: "chevron", attrs: helpAttrs("Book map", "Each cell is a page. ▲ marks the current page, filled cells are read, dots show bookmarks, highlights and notes, and the pin is your pinned page. Numbers show where you were before and after jumps.") }),
          UI.row({ icon: "hand", label: "Gestures", trailing: "chevron", attrs: helpAttrs("Book map gestures", "Tap a page to go there or open the page browser. Swipe up or down to scroll. Pinch to show fewer or more chapter levels. Long-press the menu button to switch between the current and the initial view.") })], { cls: "gp-gap" }));
    },
  });
  A.overlay("pb-menu", {
    layer: "page",
    render() {
      return A.overlays.pagebrowser.render({}) + `<div class="ko-scrim" data-close></div>` + sheet("gp-bmo", UI.sheetHead({ title: "Page browser options" }),
        UI.group([UI.row({ icon: "images", label: "Prepare next and previous thumbnails", sub: "Faster paging, uses more memory", trailing: "toggle", on: true, attrs: { action: "gpTg" } })])
        + `<div class="gp-srs">${sr("Columns", 40, "3")}${sr("Rows", 40, "3")}${sr("Page numbers", 50, "Some")}${sr("Chapter levels", 33, "1")}</div>`
        + UI.group([UI.row({ icon: "info", label: "About the page browser", trailing: "chevron", attrs: helpAttrs("Page browser", "Thumbnails of the pages around the current one. The strip at the bottom shows the chapters; tap it to jump. Bookmarked pages carry a ribbon.") }),
          UI.row({ icon: "hand", label: "Gestures", trailing: "chevron", attrs: helpAttrs("Page browser gestures", "Swipe left or right for the next or previous set of pages. Tap a thumbnail to go there. Long-press a thumbnail for page actions. Pinch to change the number of thumbnails.") })], { cls: "gp-gap" }));
    },
  });
  A.overlay("pb-hold", {
    layer: "page",
    render() {
      return A.overlays.pagebrowser.render({}) + `<div class="ko-scrim" data-close></div>` + actions({ title: "Page 14", sub: "Chapter II · The Meeting in the Barn", lead: UI.iconTile("file-text"),
        body: UI.group([UI.row({ icon: "bookmark-plus", label: "Bookmark this page", attrs: { action: "gpToastClose", arg: "Page 14 bookmarked" } }),
          UI.row({ icon: "list-plus", label: "Start a chapter here", sub: "Adds an entry to your own table of contents", attrs: { open: "input", params: { title: "Chapter title", hint: "Title", ok: "Add" } } }),
          UI.row({ icon: "eye-off", label: "Hide pages from here", sub: "Starts a hidden flow (e.g. notes, index)", attrs: { action: "gpToastClose", arg: "Hidden flow starts at page 14" } })]) });
    },
  });

  /* ------------------------------------------------ scroll mode with page gaps */
  A.screen("scroll-mode", {
    render(p) {
      const id = p.id || "animal-farm", b = RD.book(id), c = RD.cfg(id);
      const paras = TextGen.chapter(id, 2, 18);
      const pages = [paras.slice(0, 6), paras.slice(6, 12), paras.slice(12, 18)];
      const body = pages.map((ps, i) => `<div class="gp-sm-page">${ps.map((t, j) => `<p class="rd-p ${i && !j ? "cont" : ""}">${E(t)}</p>`).join("")}</div>${i < 2 ? `<div class="gp-sm-gap"><span class="num">${37 + i} · ${38 + i}</span></div>` : ""}`).join("");
      return `<div class="ko-view rd-screen gp-sm" style="${RD.style(b, c)}">
        <header class="rd-head"><span class="t ellipsis">${E(short(b))}</span><span class="c ellipsis">Chapter III · Harvest</span></header>
        <div class="ko-scroll gp-sm-body" data-action="gpSmTap"><div class="rd-text gp-sm-text">${body}</div></div>
        <footer class="rd-foot"><div class="rd-line"><span class="fill" style="width:17%"></span></div><div class="rd-foot-row"><span class="num">17%<span class="dot">·</span>Scroll mode · page gap 12 px</span><span class="num pg">37<span class="of"> / 214</span></span></div></footer></div>`;
    },
    mount(root) { const s = root.querySelector(".gp-sm-body"), g = root.querySelector(".gp-sm-gap"); if (s && g) s.scrollTop = Math.max(0, g.offsetTop - s.clientHeight * 0.45); },
  });
  A.action("gpSmTap", () => A.toast("Scroll mode · swipe to scroll, tap the edges to move a screen"));
})();

/* ==========================================================================
   Gaps · part 3 — library, statistics, system
   ========================================================================== */
(function () {
  const { A, E, I, top, setTop, clamp, pad, short, sheet, page, actions, grow, ghost, primary, koNote, help, helpAttrs, anchor } = window.GAPS;
  const btn = UI.button;
  const thumb = (b) => `<span class="gp-thumb">${UI.cover(b, { thumb: true })}</span>`;
  const fmt = (m) => { const h = Math.floor(m / 60), r = m % 60; return h ? `${h}h ${pad(r)}m` : `${r}m`; };

  /* ------------------------------------------------ Open with… (OpenWithDialog) */
  A.overlay("open-with", {
    layer: "sheet",
    render(p) {
      const b = DB.book(p.id || "frankenstein"), file = `${short(b)}.${b.format}`, ext = b.format;
      const pick = p.e || "cre", c1 = !!+(p.f || 0), c2 = !!+(p.t || 0);
      const eng = [["cre", "book-open-text", "Leaf reflowable reader", "EPUB, FB2, MOBI, HTML · KOReader: crengine"], ["mupdf", "file-text", "Leaf page reader", "Keeps the original page layout · KOReader: MuPDF"],
        ["text", "file-code", "Text editor", "Opens the file as plain text"], ["archive", "file-archive", "Archive viewer", "Lists the files inside"]];
      return sheet("gp-ow", UI.sheetHead({ title: "Open with", sub: file }),
        UI.sectionLabel("Engine") + UI.group(eng.map(([k, ic, l, s]) => UI.row({ icon: ic, label: l, sub: s, trailing: "radio", on: pick === k, attrs: { action: "gpOwPick", arg: k } })))
        + `<div class="gp-pad">${UI.checkRow({ label: "Always use it for this file", on: c1, attrs: { action: "gpOwCheck", arg: "f" } })}${UI.checkRow({ label: `Always use it for .${ext} files`, on: c2, attrs: { action: "gpOwCheck", arg: "t" } })}</div>`
        + UI.group([UI.row({ icon: "rotate-ccw", label: `Reset the default for .${ext} files`, sub: "Now: Leaf reflowable reader", attrs: { action: "gpToastClose", arg: `Default for .${ext} reset` } }),
          UI.row({ icon: "list", label: "Defaults for file types", trailing: "chevron", attrs: helpAttrs("Defaults for file types", `epub: Leaf reflowable reader\npdf: Leaf page reader\ncbz: Leaf page reader\ntxt: Text editor`) })], { cls: "gp-gap" }),
        `${ghost("Cancel", "data-close")}${grow}${primary("Open", c1 || c2 ? { action: "gpSwapTo", arg: "confirm", params: { title: c2 ? `Always open .${ext} files with the ${pick === "mupdf" ? "page reader" : "reflowable reader"}?` : `Always open “${file}” this way?`, body: "You can change it later from Open with.", ok: "Always" } } : { action: "gpToastClose", arg: `Opening ${file}` })}`);
    },
  });
  A.action("gpOwPick", (el) => setTop({ e: el.dataset.arg }));
  A.action("gpOwCheck", (el) => { const k = el.dataset.arg; setTop({ [k]: +(top()[k] || 0) ? 0 : 1 }); });

  /* ------------------------------------------------ selected files list */
  A.overlay("selected-files", {
    layer: "page",
    render() {
      const ids = ["frankenstein", "dracula", "walden", "sherlock-1", "ar-poems"];
      const rows = ids.map((id) => { const b = DB.book(id); return UI.row({ tag: "div", lead: thumb(b), label: `${short(b)}.${b.format}`, sub: `/mnt/onboard/Books/${b.folder}`, attrs: { action: "gpToastClose", arg: `Showing ${short(b)} in ${b.folder}`, role: "button" },
        trailing: UI.iconButton({ icon: "x", label: "Deselect", size: "sm", attrs: { toast: "Deselected" } }) }); });
      return page("gp-self", UI.pageHead({ title: `Selected files · ${ids.length}`, crumbs: ["Library", "Select mode"], back: "data-close", rule: true }),
        help("Tap a file to show it in its folder.") + UI.list(rows, { inset: true }),
        `${ghost("Deselect all", { action: "gpToastClose", arg: "Selection cleared" })}${grow}${primary("Done", "data-close")}`);
    },
  });

  /* ------------------------------------------------ collections: connected folders + filters */
  const CF = [["Books/Classics", 1, 0], ["Downloads", 0, 1], ["Books/Philosophy", 1, 1]];
  A.overlay("coll-folders", {
    layer: "page",
    render(p) {
      const name = p.name || "To read this winter";
      const rows = CF.map(([path, sub, scan], i) => UI.row({ tag: "div", icon: "folder-symlink", label: path.split("/").pop(), sub: `/mnt/onboard/${path}${sub ? " · with subfolders" : ""}${scan ? " · checked on open" : ""}`, attrs: { action: "gpToastClose", arg: `Showing ${path}`, role: "button" },
        trailing: UI.iconButton({ icon: "ellipsis-vertical", label: "Folder options", size: "sm", attrs: { open: "coll-folder", params: { i } } }) }));
      return page("gp-cf", UI.pageHead({ title: "Connected folders", crumbs: ["Collections", name], back: "data-close", rule: true }),
        help("New books in these folders join the collection automatically.") + UI.group(rows)
        + UI.sectionLabel("Only add") + UI.group([
          UI.row({ icon: "file-type", label: "File types", value: "epub, pdf", trailing: "chevron", attrs: { open: "input", params: { title: "File types for new books", hint: "epub, pdf", value: "epub, pdf", ok: "Save", desc: "Separate with commas. Leave empty to add every type." } } }),
          UI.row({ icon: "book-check", label: "Reading status", value: "New, Reading", trailing: "chevron", attrs: { open: "coll-status" } })]),
        `${ghost("Close", "data-close")}${grow}${primary("Connect a folder", { open: "path-chooser", params: { purpose: "collection" } }, { icon: "folder-plus" })}`);
    },
  });
  A.overlay("coll-folder", {
    layer: "sheet",
    render(p) {
      const [path, sub, scan] = CF[clamp(+(p.i || 0), 0, CF.length - 1)];
      return actions({ title: path.split("/").pop(), sub: `/mnt/onboard/${path}`, lead: UI.iconTile("folder-symlink"),
        body: UI.group([UI.row({ icon: "folder-tree", label: "Include subfolders", sub: "Turning it on scans them now", trailing: "toggle", on: !!sub, attrs: { action: "gpTg" } }),
          UI.row({ icon: "scan-search", label: "Check for new books when the collection opens", trailing: "toggle", on: !!scan, attrs: { action: "gpTg" } })])
          + UI.group([UI.row({ icon: "unlink", label: "Disconnect folder", sub: "Books already added stay in the collection", danger: true, attrs: { action: "gpToastClose", arg: "Folder disconnected" } })], { cls: "gp-gap" }) });
    },
  });
  A.overlay("coll-status", {
    layer: "sheet",
    render() {
      const st = [["New", "sparkles", 1], ["Reading", "book-open", 1], ["On hold", "pause", 0], ["Finished", "circle-check", 0]];
      return sheet("gp-cs", UI.sheetHead({ title: "Only add books that are", sub: "To read this winter" }),
        UI.group(st.map(([l, ic, on]) => UI.row({ icon: ic, label: l, trailing: "check", on: !!on, attrs: { action: "gpCheck" } }))),
        `${ghost("Clear filter", { action: "gpToastClose", arg: "Status filter cleared" })}${grow}${primary("Done", { action: "gpToastClose", arg: "Status filter saved" })}`);
    },
  });
  A.action("gpCheck", (el) => { const c = el.querySelector(".ko-check"); if (c) { const on = !c.classList.contains("on"); c.outerHTML = A.check(on); A.icons(); } });

  /* ------------------------------------------------ book information: edit a metadata field / custom cover */
  A.overlay("meta-field", {
    layer: "sheet",
    render(p) {
      const b = DB.book(p.id || "animal-farm"), f = p.f || "title";
      if (f === "cover") return actions({ title: "Cover image", sub: "Custom cover · animal-farm-1945.jpg", lead: `<span class="gp-thumb lg">${UI.cover(b, { thumb: true })}</span>`,
        body: UI.group([UI.row({ icon: "eye", label: "View cover", attrs: { action: "gpSwapTo", arg: "image-viewer", params: { src: "cover", id: b.id } } }),
          UI.row({ icon: "image-plus", label: "Choose another image…", sub: "Remove the custom cover first to pick a new one", disabled: true }),
          UI.row({ icon: "image", label: "View the book's own cover", attrs: { action: "gpSwapTo", arg: "image-viewer", params: { src: "cover", id: "gatsby" } } })])
          + UI.group([UI.row({ icon: "rotate-ccw", label: "Remove custom cover", sub: "The image file is deleted", danger: true, attrs: { action: "gpSwapTo", arg: "confirm", params: { title: "Remove the custom cover?", body: "The image file will be deleted and the book's own cover comes back.", ok: "Remove", danger: true } } })], { cls: "gp-gap" }) });
      const F = { title: ["Title", "Animal Farm (EN-AR)", "Animal Farm", true], author: ["Authors", b.author.replace(";", ",") , b.author.split(";")[0], false], series: ["Series", "—", "", false] }[f];
      const [label, val, orig, custom] = F;
      return actions({ title: label, sub: custom ? `${val} · edited` : val, lead: UI.iconTile(custom ? "pencil" : "text-cursor-input"),
        body: UI.group([UI.row({ icon: "pencil", label: "Edit…", attrs: { action: "gpSwapTo", arg: "input", params: { title: `Edit ${label.toLowerCase()}`, value: val, ok: "Save" } } }),
          UI.row({ icon: "copy", label: "Copy original", sub: orig || "Empty in the file", disabled: !orig, attrs: { action: "gpToastClose", arg: "Copied" } }),
          UI.row({ icon: "file-search", label: "View original", attrs: helpAttrs(`Original ${label.toLowerCase()}`, orig || "The book file has no value for this field.") })])
          + UI.group([UI.row({ icon: "rotate-ccw", label: "Reset to original", danger: custom, disabled: !custom, attrs: { action: "gpSwapTo", arg: "confirm", params: { title: "Reset this field?", body: `${label} goes back to “${orig}”.`, ok: "Reset", danger: true } } })], { cls: "gp-gap" }) });
    },
  });

  /* ------------------------------------------------ archive viewer */
  const ZIP = { "": { dirs: [["Issue 1", 24], ["Issue 2", 22]], files: [["cover.jpg", "380 KB"], ["readme.txt", "2 KB"]] },
    "Issue 1": { files: Array.from({ length: 9 }, (_, i) => [`page-${pad(i + 1)}.jpg`, `${(1.6 + ((i * 7) % 9) / 10).toFixed(1)} MB`]) } };
  A.overlay("archive", {
    layer: "page",
    render(p) {
      const sub = p.sub || "", node = ZIP[sub] || ZIP[""];
      const go = (s) => ({ action: "gpZipGo", arg: s });
      const rows = (sub ? [UI.row({ icon: "corner-left-up", label: "Up", sub: "comics-pack.zip", attrs: go("") })] : [])
        .concat((node.dirs || []).map(([n, c]) => UI.row({ icon: "folder", label: n, sub: `${c} files`, trailing: "chevron", attrs: go(n) })))
        .concat((node.files || []).map(([n, s]) => UI.row({ icon: /\.jpe?g$/.test(n) ? "file-image" : "file-text", label: n, value: s, attrs: { open: "archive-file", params: { f: n, sub } } })));
      const menu = p.menu ? `<div class="ko-scrim clear" data-action="gpZipMenu"></div><div class="ko-popover gp-pop gp-zipm">${UI.row({ icon: "package-open", label: "Extract all files…", attrs: { action: "gpSwapTo", arg: "archive-extract" } })}</div>` : "";
      return page("gp-zip", UI.pageHead({ title: sub ? `comics-pack.zip › ${sub}` : "comics-pack.zip", crumbs: [{ label: "Downloads", attrs: "data-close" }], back: "data-close", rule: true,
        actions: UI.iconButton({ icon: "ellipsis-vertical", label: "Archive actions", attrs: { action: "gpZipMenu" }, cls: "gp-zip-more" }) }),
        `<div class="gp-pm-src">${I("file-archive", "sm")}<span>Archive · 48 MB · ${sub ? "9 files" : "2 folders, 2 files"}</span></div>` + UI.list(rows, { inset: true }),
        `<span class="faint">Tap a file to view or extract it</span>`) + menu;
    },
    mount(el, p) { if (p.menu) anchor(el, ".gp-zipm", ".gp-zip-more", { right: true }); },
  });
  A.action("gpZipGo", (el) => setTop({ sub: el.dataset.arg, menu: "" }));
  A.action("gpZipMenu", () => setTop({ menu: top().menu ? "" : 1 }));
  A.overlay("archive-file", {
    layer: "sheet",
    render(p) {
      const f = p.f || "page-03.jpg", img = /\.jpe?g$/.test(f);
      return actions({ title: f, sub: `comics-pack.zip${p.sub ? " › " + p.sub : ""}`, lead: UI.iconTile(img ? "file-image" : "file-text"),
        body: UI.group([UI.row({ icon: "eye", label: "View", sub: img ? "Opens with the other images of the archive" : "Opens as text", attrs: { action: "gpSwapTo", arg: img ? "image-viewer" : "text-viewer", params: img ? { src: "archive", i: 3 } : {} } }),
          UI.row({ icon: "download", label: "Extract to Downloads", attrs: { action: "gpToastClose", arg: `Extracted to /mnt/onboard/Downloads` } }),
          UI.row({ icon: "folder-input", label: "Extract to…", trailing: "chevron", attrs: { action: "gpSwapTo", arg: "path-chooser", params: { purpose: "extract" } } })])
          + `<div class="gp-note">${I("info", "sm")}<span>A file with the same name in the target folder is replaced.</span></div>` });
    },
  });
  A.overlay("archive-extract", {
    layer: "dialog",
    render: () => UI.dialog({ title: "Extract all files?", body: "To /mnt/onboard/Downloads.\nFiles with the same name are replaced.",
      actions: [ghost("Choose folder…", { action: "gpSwapTo", arg: "path-chooser", params: { purpose: "extract" } }), '<span class="grow"></span>', ghost("Cancel", "data-close"), primary("Extract", { action: "gpToastClose", arg: "All files extracted to Downloads" })] }),
  });

  /* ------------------------------------------------ sleep screen lock: gesture to wake */
  A.overlay("unlock", {
    layer: "page",
    render(p) {
      const base = A.overlays.lockscreen.render({ preview: 1 });
      const none = p.k === "tap";
      return base + `<div class="ko-popover gp-float gp-unlock">${I(none ? "pointer" : "chevrons-up")}<span>${none ? "Tap anywhere to wake" : "Swipe up to unlock"}</span></div>`;
    },
  });

  /* ------------------------------------------------ read timer: time is up */
  A.overlay("timer-up", {
    layer: "dialog",
    render(p) {
      if (p.k === "alarm") return UI.dialog({ title: "Time is up", body: "Your 22:30 alarm. Good night!", actions: [primary("OK", "data-close")] });
      return UI.dialog({ title: "Time is up", body: "You've been reading for 20 minutes. Time for a break?",
        bodyHtml: `<div class="gp-spin-meta"><span>${I("timer", "sm")} Read timer · interval</span></div>`,
        actions: [ghost("Done", { action: "gpToastClose", arg: "Timer stopped" }), primary("Repeat · 20 min", { action: "gpToastClose", arg: "Timer will ring in 20 min" })] });
    },
  });

  /* ------------------------------------------------ statistics: current book */
  const BS = { session: [18, 9], today: [35, 21], total: 134, days: 6, perDay: 22, perPage: "1m 31s", left: "1h 41m", start: ["Nov 13", "6 days ago"], finish: ["Nov 24", "in 5 days"], page: [43, 112], hl: 6, notes: 2 };
  A.overlay("book-stats", {
    layer: "page",
    render(p) {
      const b = DB.book(p.id || "animal-farm"), pct = Math.round((BS.page[0] / BS.page[1]) * 100);
      const info = (t, s) => UI.iconButton({ icon: "info", label: "About this value", size: "sm", attrs: helpAttrs(t, s) });
      const r = (label, value, o = {}) => UI.row({ tag: o.attrs ? "button" : "div", label, value, trailing: o.trailing || "none", attrs: o.attrs });
      const hero = UI.card(`<div class="gp-bs-hero">${thumb(b)}<div class="grow"><div class="gp-bs-t ellipsis">${E(short(b))}</div><div class="faint ellipsis">${E(b.author.split(";")[0])}</div>
          ${UI.progress(pct, { size: "md", cls: "gp-bs-bar" })}<div class="gp-bs-meta num">${pct}% · page ${BS.page[0]} of ${BS.page[1]}</div></div></div>`, { cls: "gp-bs-card" });
      const tiles = UI.stats([{ label: "This session", value: `${BS.session[0]}m` }, { label: "Today", value: `${BS.today[0]}m` }, { label: "With this book", value: fmt(BS.total) }, { label: "Days", value: String(BS.days) }], { card: true, center: true, cls: "gp-bs-tiles" });
      return page("gp-bs", UI.pageHead({ title: "Book statistics", crumbs: [short(b)], back: "data-close", rule: true, actions: UI.iconButton({ icon: "calendar-days", label: "Calendar", attrs: { go: "stats-cal" } }) }),
        `<div class="gp-pad">${hero}${tiles}</div>`
        + UI.sectionLabel("Time") + UI.group([r("Total time", fmt(BS.total)), r("Average per day", `${BS.perDay}m`), r("Average per page", BS.perPage),
          r("Estimated time left", BS.left, { trailing: info("Estimated time left", "Pages left × your average time per page in this book.") })])
        + UI.sectionLabel("Days") + UI.group([r("Today", `${BS.today[0]}m · ${BS.today[1]} pages`, { trailing: "chevron", attrs: { open: "stats-day" } }), r("This session", `${BS.session[0]}m · ${BS.session[1]} pages`),
          r("Days reading this book", String(BS.days), { trailing: "chevron", attrs: { action: "gpSwapTo", arg: "stats-range", params: { k: "days" } } }),
          r("Started", `${BS.start[0]} · ${BS.start[1]}`), r("Estimated finish", `${BS.finish[0]} · ${BS.finish[1]}`, { trailing: info("Estimated finish", "When you will finish at your average pace per day of reading.") })])
        + UI.sectionLabel("Pages and notes") + UI.group([r("Current page", `${BS.page[0]} / ${BS.page[1]}`), r("Pages read", `${BS.page[0]} · ${pct}%`), r("Highlights", String(BS.hl)), r("Notes", String(BS.notes))])
        + UI.group([UI.row({ label: "Reset statistics for this book", danger: true, attrs: { open: "confirm", params: { title: "Reset statistics for this book?", body: "Reading time and page history of Animal Farm are deleted. Your position and highlights stay.", ok: "Reset", danger: true } } })], { cls: "gp-gap" }));
    },
  });

  /* ------------------------------------------------ statistics: calendar (month) */
  const MONTH = { name: "November 2026", days: 30, first: 6 /* Mon-based offset: Nov 1 2026 is a Sunday */, today: 19 };
  const SPANS = [["Frankenstein", 1, 7, "b2"], ["Animal Farm", 13, 19, "b1"], ["Meditations", 3, 12, "b3"], ["Walden", 9, 10, "b2"], ["The Odyssey", 15, 17, "b3"], ["Siddhartha", 18, 19, "b2"]];
  const hist = (d) => Array.from({ length: 24 }, (_, h) => { const r = Math.sin(d * 7.3 + h * 1.7) * 0.5 + 0.5; return (h >= 6 && h <= 8) || h >= 20 ? (r > 0.35 ? Math.round(r * 4) : 0) : r > 0.86 ? 1 : 0; });
  A.screen("stats-cal", {
    render(p) {
      const per = 2, cells = [];
      const wd = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
      for (let i = 0; i < MONTH.first; i++) cells.push('<span class="gp-cal-day pad"></span>');
      for (let d = 1; d <= MONTH.days; d++) {
        const fut = d > MONTH.today, sp = fut ? [] : SPANS.filter(([, a, z]) => d >= a && d <= z);
        const shown = sp.slice(0, per), more = sp.length - shown.length;
        const h = fut ? [] : hist(d);
        cells.push(`<button class="gp-cal-day ${d === MONTH.today ? "today" : ""} ${fut ? "fut" : ""}" ${fut ? "disabled" : `data-open="stats-day" data-params='${A.attrs({ d })}'`} aria-label="${d} November">
          <span class="d num">${d}</span>${h.length && h.some(Boolean) ? `<span class="gp-cal-hist">${h.map((v) => `<i class="v${v}"></i>`).join("")}</span>` : ""}
          ${shown.map(([t, a, z, c]) => { const col = (d + MONTH.first - 1) % 7, s = d === a || col === 0; return `<span class="gp-cal-bar ${c} ${s ? "s" : ""} ${d === z || col === 6 ? "e" : ""}">${s ? E(t) : ""}</span>`; }).join("")}
          ${more > 0 ? `<span class="gp-cal-more num">+${more}</span>` : ""}</button>`);
      }
      return `<div class="ko-view gp-cal">${A.statusBar()}
        ${UI.screenHead({ title: MONTH.name, back: { go: "stats" }, actions: UI.iconButton({ icon: "settings-2", label: "Calendar settings", attrs: { open: "stats-cal-set" } }) })}
        <div class="gp-cal-wd">${wd.map((w) => `<span>${w}</span>`).join("")}</div>
        <div class="ko-scroll"><div class="gp-cal-grid">${cells.join("")}</div>
          <div class="gp-cal-key">${[["b1", "Animal Farm"], ["b2", "Frankenstein · Walden · Siddhartha"], ["b3", "Meditations · The Odyssey"]].map(([c, t]) => `<span><i class="gp-cal-bar ${c} s e"></i>${E(t)}</span>`).join("")}<span><i class="gp-cal-hist-k"></i>Reading by hour</span></div></div>
        <div class="ko-pager"><span class="num">October 2026</span><span class="row">${UI.iconButton({ icon: "chevrons-left", label: "First month", attrs: { toast: "March 2024 · first month with statistics" } })}${UI.iconButton({ icon: "chevron-left", label: "Previous month", attrs: { toast: "October 2026" } })}
          <button class="gp-cal-ym num" data-open="input" data-params='${A.attrs({ title: "Go to month", hint: "YYYY-MM", value: "2026-11", ok: "Go" })}'>2026-11</button>${UI.iconButton({ icon: "chevron-right", label: "Next month", disabled: true })}${UI.iconButton({ icon: "chevrons-right", label: "Last month", disabled: true })}</span></div></div>`;
    },
  });
  A.overlay("stats-cal-set", {
    layer: "sheet",
    render() {
      const t = (icon, label, on, sub) => UI.row({ icon, label, sub, trailing: "toggle", on, attrs: { action: "gpTg" } });
      return sheet("gp-cals", UI.sheetHead({ title: "Calendar settings" }),
        `<div class="gp-choices"><div class="ko-row gp-choice"><span class="label">Weeks start on</span>${UI.seg([["Saturday"], ["Sunday"], ["Monday", 1]].map(([l, on]) => ({ label: l, on: !!on, attrs: { action: "gpSegPick" } })), { size: "sm" })}</div></div>`
        + `<div class="gp-srs">${UI.sliderRow({ label: "Books per day", pct: 25, value: "2", slide: "gpNoop", step: "gpNoop" })}</div>`
        + UI.group([t("chart-no-axes-column", "Show reading by hour in each day", true), t("calendar-plus", "Allow browsing coming months", false),
          UI.row({ icon: "sunrise", label: "Days start at", value: "04:00", trailing: "chevron", attrs: { open: "datetime", params: { k: "daystart" } } }),
          t("calendar-days", "Use that start in the calendar too", true, "Reading after midnight counts for the evening before")]));
    },
  });

  /* ------------------------------------------------ statistics: day timeline */
  const SESS = [["b1", "Animal Farm", 6 * 60 + 40, 22], ["b1", "Animal Farm", 7 * 60 + 5, 9], ["b2", "Siddhartha", 12 * 60 + 30, 14], ["b1", "Animal Farm", 21 * 60 + 2, 25], ["b2", "Siddhartha", 21 * 60 + 30, 8]];
  A.overlay("stats-day", {
    layer: "page",
    render(p) {
      const d = +(p.d || 19), off = 4 * 60; // the day starts at 04:00
      const hours = Array.from({ length: 24 }, (_, i) => (i + 4) % 24);
      const rows = hours.map((h) => {
        const s0 = h * 60, blocks = SESS.filter(([, , st]) => st >= s0 && st < s0 + 60).map(([c, t, st, len]) => `<i class="gp-tl-blk ${c}" style="left:${((st - s0) / 60) * 100}%;width:${Math.min(len, s0 + 60 - st) / 0.6}%" title="${E(t)} · ${len} min"></i>`).join("");
        const now = d === 19 && h === 21 ? `<i class="gp-tl-now" style="left:${(40 / 60) * 100}%"></i>` : "";
        return `<div class="gp-tl-line"><span class="num">${pad(h)}:00</span><span class="gp-tl-track">${blocks}${now}</span></div>`;
      }).join("");
      const books = [["b1", "animal-farm", 56, 38], ["b2", "siddhartha", 22, 14]];
      return page("gp-day", UI.pageHead({ title: `Thursday ${d} November`, crumbs: ["Statistics", "Calendar"], back: "data-close", rule: true }),
        `<div class="gp-pad">${UI.stats([{ label: "Read", value: "1h 18m" }, { label: "Pages", value: "52" }, { label: "Books", value: "2" }, { label: "Sessions", value: "5" }], { card: true, center: true })}</div>`
        + UI.group(books.map(([c, id, m, pg]) => { const b = DB.book(id); return UI.row({ lead: `<span class="gp-tl-sw ${c}" aria-hidden="true"></span>`, label: short(b), sub: `${m}m · ${pg} pages`, trailing: "check", on: true, attrs: { action: "gpCheck" } }); }))
        + `<div class="gp-tl-top">${UI.eyebrow("Timeline")}<span class="grow"></span>${UI.button({ kind: "link", label: "Day starts at 04:00", attrs: { open: "datetime", params: { k: "daystart" } } })}</div><div class="gp-tl">${rows}</div>`,
        `${UI.iconButton({ icon: "chevron-left", label: "Previous day", attrs: { action: "gpDay", arg: d - 1 } })}<span class="grow gp-day-n num">${d} of 30</span>${UI.iconButton({ icon: "chevron-right", label: "Next day", attrs: { action: "gpDay", arg: d + 1 }, disabled: d >= 19 })}`);
    },
  });
  A.action("gpDay", (el) => setTop({ d: clamp(+el.dataset.arg, 1, 19) }));

  /* ------------------------------------------------ statistics: time ranges and lists */
  const RANGE_MENU = [["library", "All books", "212 h 40 min", "books"], ["calendar-range", "Books by week", "", "weeks"], ["calendar", "Books by month", "", "months"], ["calendar-days", "Last 7 days", "4 h 06 min", "week"],
    ["calendar-check", "Last month by day", "", "monthdays"], ["calendar-clock", "Last year by day", "", "monthdays"], ["calendar-fold", "Last year by week", "", "weeks"], ["history", "All statistics by month", "", "months"]];
  const LISTS = {
    week: { title: "Last 7 days", crumbs: ["Statistics", "Time range"], rows: [["Thu 19 Nov", "1h 18m · 52 pages"], ["Wed 18 Nov", "42m · 30 pages"], ["Tue 17 Nov", "55m · 38 pages"], ["Mon 16 Nov", "12m · 8 pages"], ["Sun 15 Nov", "1h 02m · 44 pages"], ["Sat 14 Nov", "—"], ["Fri 13 Nov", "37m · 26 pages"]], day: true },
    days: { title: "Days reading Animal Farm", crumbs: ["Book statistics"], rows: [["Thu 19 Nov", "35m · 21 pages"], ["Wed 18 Nov", "28m · 17 pages"], ["Tue 17 Nov", "20m · 12 pages"], ["Sun 15 Nov", "26m · 16 pages"], ["Sat 14 Nov", "11m · 6 pages"], ["Fri 13 Nov", "14m · 9 pages"]], day: true, hold: true },
    monthdays: { title: "Last month by day", crumbs: ["Statistics", "Time range"], rows: Array.from({ length: 14 }, (_, i) => [`${["Thu", "Wed", "Tue", "Mon", "Sun", "Sat", "Fri"][i % 7]} ${19 - i} Nov`, i % 6 === 5 ? "—" : `${20 + ((i * 17) % 50)}m · ${12 + ((i * 11) % 30)} pages`]), day: true },
    weeks: { title: "Books by week", crumbs: ["Statistics", "Time range"], rows: [["2026 · week 47", "4h 06m · 172 pages"], ["2026 · week 46", "5h 20m · 214 pages"], ["2026 · week 45", "3h 02m · 120 pages"], ["2026 · week 44", "6h 11m · 260 pages"], ["2026 · week 43", "2h 48m · 104 pages"]], next: true },
    months: { title: "Books by month", crumbs: ["Statistics", "Time range"], rows: [["November 2026", "14h 10m · 512 pages"], ["October 2026", "19h 44m · 702 pages"], ["September 2026", "16h 02m · 590 pages"], ["August 2026", "22h 30m · 820 pages"], ["July 2026", "11h 15m · 404 pages"]], next: true },
  };
  A.overlay("stats-range", {
    layer: "page",
    render(p) {
      const k = p.k || "menu";
      if (k === "menu") return page("gp-sr", UI.pageHead({ title: "Time range", crumbs: ["Statistics"], back: "data-close", rule: true }),
        UI.group(RANGE_MENU.map(([ic, l, v, to]) => UI.row({ icon: ic, label: l, value: v || undefined, trailing: "chevron", attrs: to === "books" ? { action: "gpSwapTo", arg: "stats-books" } : { action: "gpSr", arg: to } }))));
      if (k === "in") {
        const ids = ["animal-farm", "frankenstein", "meditations", "siddhartha", "walden"], t = ["4h 02m · 130 pages", "3h 40m · 122 pages", "2h 51m · 96 pages", "2h 10m · 88 pages", "1h 27m · 76 pages"];
        return page("gp-sr", UI.pageHead({ title: "Books read in November 2026", crumbs: ["Statistics", "Books by month"], back: { action: "gpSr", arg: "months" }, rule: true }),
          help("Tap a book for its statistics. Long-press to reset its statistics for this month.") + UI.list(ids.map((id, i) => { const b = DB.book(id); return UI.row({ lead: `<span class="gp-thumb">${UI.cover(b, { thumb: true })}</span>`, label: short(b), sub: t[i], trailing: "chevron", attrs: { action: "gpSwapTo", arg: "book-stats", params: { id } } }); }), { inset: true }));
      }
      const L = LISTS[k];
      return page("gp-sr", UI.pageHead({ title: L.title, crumbs: L.crumbs, back: k === "days" ? "data-close" : { action: "gpSr", arg: "menu" }, rule: true }),
        (L.hold ? help("Long-press a day to reset this book's statistics for it.") : "")
        + UI.group(L.rows.map(([a, b]) => UI.row({ label: a, value: b, trailing: L.next || (L.day && b !== "—") ? "chevron" : "none", disabled: b === "—", attrs: L.next ? { action: "gpSr", arg: "in" } : L.day ? { action: "gpSwapTo", arg: "stats-day", params: { d: parseInt(a.split(" ")[1], 10) } } : "" }))));
    },
  });
  A.action("gpSr", (el) => setTop({ k: el.dataset.arg }));
  A.overlay("stats-books", {
    layer: "page",
    render(p) {
      const reset = p.reset === 1 || p.reset === "1";
      const ids = ["frankenstein", "dracula", "meditations", "animal-farm", "pride", "sherlock-1", "siddhartha", "moby", "kafka", "war-worlds"];
      const t = [842, 611, 455, 134, 402, 380, 290, 210, 95, 160];
      const rows = ids.map((id, i) => { const b = DB.book(id); return UI.row({ lead: `<span class="gp-thumb">${UI.cover(b, { thumb: true })}</span>`, label: short(b), sub: b.author.split(";")[0], value: fmt(t[i]),
        trailing: reset ? UI.iconButton({ icon: "trash-2", label: "Reset statistics of this book", size: "sm", attrs: { open: "confirm", params: { title: "Reset statistics for this book?", body: `${short(b)} · ${fmt(t[i])} of reading time is deleted.`, ok: "Reset", danger: true } } }) : "chevron",
        attrs: reset ? "" : { action: "gpSwapTo", arg: "book-stats", params: { id } }, tag: reset ? "div" : "button" }); });
      const short_ = reset ? UI.sectionLabel("Remove short reads") + UI.group([1, 5, 15, 30, 60].map((m) => UI.row({ icon: "eraser", label: `Books read for less than ${m} min`, attrs: { open: "confirm", params: { title: `Remove statistics of books read for less than ${m} minutes?`, body: "Useful after opening books by mistake.", ok: "Remove", danger: true } } }))) : "";
      return page("gp-sb", UI.pageHead({ title: reset ? "Reset book statistics" : "All books", crumbs: ["Statistics"], back: "data-close", rule: true }),
        `<div class="gp-pm-src">${I("clock", "sm")}<span>${reset ? "The current book is not listed" : "Total time spent reading · 212 h 40 min"}</span></div>` + UI.list(rows, { inset: true }) + short_);
    },
  });
})();

/* ==========================================================================
   Gaps · designer states (one entry per state, labelled with the KOReader surface)
   ========================================================================== */
(function () {
  const { D, H } = window.GAPS;
  const af = { id: "animal-farm" }, pdf = { id: "pride", page: 3 };
  const R = (o, op = {}, sp = af) => H("reader", sp, o, op);
  const Lb = (o, op = {}) => H("library", {}, o, op);
  // P1
  [["page", "page number"], ["chtime", "time left in chapter"], ["bookleft", "pages left in book"], ["clock", "clock"], ["bar", "progress bar only"], ["off", "hidden"]]
    .forEach(([m, l]) => D(`ReaderFooter · tap mode: ${l}`, R("footer-mode", { m })));
  D("ReaderFlipping · page flipping (PDF)", R("flipping", { k: "flip" }, pdf));
  D("ReaderFlipping · bookmark flipping (PDF)", R("flipping", { k: "bm" }, pdf));
  D("ReaderFlipping · select mode (extend highlight)", R("flipping", { k: "select" }));
  D("ReaderFlipping · re-rendering in background", R("flipping", { k: "render" }));
  D("ReaderFlipping · new layout ready", R("flipping", { k: "ready" }));
  // P2 — generic widgets
  D("SpinWidget · Items per page", Lb("spin", { k: "items", v: 16 }));
  D("SpinWidget · with extra button (battery)", R("spin", { k: "battery" }));
  D("SpinWidget · Characters per page", R("spin", { k: "cpp" }));
  D("NumberPicker · Enter number, range error", Lb("number", { min: 6, max: 30, cur: 14, label: "Items", value: "42", err: "max", key: "v" }));
  D("DoubleSpinWidget · Battery alert thresholds", R("spin2", { k: "battery" }));
  D("DoubleSpinWidget · Hyphenation limits", R("spin2", { k: "hyph" }));
  D("Project: Title · Portrait cover grid (DoubleSpin)", Lb("spin2", { k: "grid" }));
  D("Project: Title · List modes (Spin)", Lb("spin", { k: "listmodes" }));
  D("DateTimeWidget · Read timer alarm", R("datetime", { k: "alarm" }));
  D("DateTimeWidget · Read timer interval", R("datetime", { k: "interval" }));
  D("DateTimeWidget · Daily timeline start", H("stats", {}, "datetime", { k: "daystart" }));
  D("DateTimeWidget · Autosuspend duration", H("settings", {}, "datetime", { k: "suspend" }));
  D("SortWidget · Arrange collections", Lb("arrange", { k: "coll" }));
  D("SortWidget · item selected", Lb("arrange", { k: "coll", sel: 2 }));
  D("SortWidget · sort menu", Lb("arrange", { k: "coll", menu: 1 }));
  D("SortWidget · Arrange books in collection", H("collection", { name: "To read this winter" }, "arrange", { k: "books" }));
  D("SortWidget · Status bar items (with checks)", R("arrange", { k: "footer" }));
  D("PathChooser · Choose download folder", Lb("path-chooser", { purpose: "download" }));
  D("PathChooser · Choose a cover image (files)", Lb("path-chooser", { purpose: "cover" }));
  D("PathChooser · Choose this file? confirm", Lb("path-confirm", { path: "Pictures/Covers/animal-farm-1945.jpg", size: "286 KB" }));
  D("ImageViewer · Book cover (book info)", Lb("image-viewer", { src: "cover", id: "animal-farm" }));
  D("ImageViewer · Image in book (long-press)", R("image-viewer", { src: "figure" }));
  D("ImageViewer · controls hidden", R("image-viewer", { src: "figure", ui: 0 }));
  D("ImageViewer · rotated, original size", Lb("image-viewer", { src: "cover", id: "moby", rot: 1, orig: 1 }));
  D("VirtualKeyPopup · accents (long-press e)", Lb("key-popup", { key: "e" }));
  D("LinkBox · tapped link (PDF)", R("linkbox", {}, pdf));
  D("External link dialog", R("link-ext"));
  D("External link · Wikipedia article", R("link-ext", { wiki: 1 }));
  D("Bookmark list · long-press a highlight", R("bm-actions", { i: 1 }));
  D("Bookmark list · long-press a bookmark", R("bm-actions", { i: 0 }));
  D("ReaderSearch · result navigation", R("search-nav", { k: "result" }));
  D("ReaderSearch · ◁ ▷ search bar", R("search-nav", { k: "bar" }));
  D("ReaderSearch · searching (wait)", R("search-nav", { k: "wait" }));
  D("Gesture QuickMenu", R("quickmenu"));
  D("Profile QuickMenu (Execute all)", R("quickmenu", { k: "profile" }));
  D("Statistics · Current book", R("book-stats"));
  D("Statistics · Calendar view (month)", H("stats-cal"));
  D("Statistics · Calendar settings", H("stats-cal", {}, "stats-cal-set"));
  D("Statistics · Day timeline", H("stats-cal", {}, "stats-day", { d: 19 }));
  D("Read timer · time is up (interval)", R("timer-up"));
  D("Read timer · alarm message", R("timer-up", { k: "alarm" }));
  // P3
  D("KeyboardLayoutDialog · globe long-press", Lb("kb-layouts"));
  D("InputText · hold: clipboard menu", Lb("clipboard"));
  D("InputText · clipboard snippets", Lb("snippets"));
  D("InputText · edit snippet", Lb("snippet-edit", { i: 2 }));
  D("VerticalScrollBar · long text", Lb("text-viewer"));
  D("OpenWithDialog", Lb("open-with", { id: "frankenstein" }));
  D("OpenWithDialog · always use, confirm", Lb("confirm", { title: "Always open .epub files with the page reader?", body: "You can change it later from Open with.", ok: "Always" }));
  D("Select mode · Show selected files list", Lb("selected-files"));
  D("Screenshoter · screenshot saved", R("screenshot"));
  D("Screenshoter · view screenshot", R("image-viewer", { src: "shot" }));
  D("Collections · Connected folders", H("collection", { name: "To read this winter" }, "coll-folders"));
  D("Collections · connected folder options", H("collection", { name: "To read this winter" }, "coll-folder", { i: 0 }));
  D("Collections · Filter by status", H("collection", { name: "To read this winter" }, "coll-status"));
  D("Book information · edit a field", Lb("meta-field", { f: "title" }));
  D("Book information · custom cover", Lb("meta-field", { f: "cover" }));
  D("Kindle activity indicator → Leaf busy toast", R("busy", {}, pdf));
  D("Scroll mode · page gap (EPUB)", H("scroll-mode", af));
  D("Perception expander · guide lines", R("perception"));
  D("Perception expander · settings", R("pe-set"));
  D("Overlapping highlights chooser", R("hl-multi"));
  D("Bookmark details viewer", R("bm-view", { i: 1 }));
  D("Bookmark list · select mode", R("bm-select"));
  D("Go to · pinned page", R("goto-pin"));
  D("Go to · remove pinned page", R("confirm", { title: "Remove the pinned page?", body: "Page 42 stays as it is; only the pin is removed.", ok: "Remove", danger: true }));
  D("Book map · options menu", R("bookmap-menu"));
  D("Page browser · options menu", R("pb-menu"));
  D("Page browser · long-press a page", R("pb-hold"));
  D("Stable page numbers · list", R("pagemap"));
  D("Stable page numbers · settings", R("pagemap-set"));
  D("Stable page numbers · publisher prompt", R("confirm", { title: "Publisher page numbers available", body: "This book has the page numbers of its print edition (Penguin Classics, 2008 · pages 1–214). Use them instead of Leaf's own?", ok: "Use them", cancel: "Not now" }));
  D("Style tweaks · tweak info (hold)", R("tweak-info"));
  D("Style tweaks · book-specific editor", R("tweak-editor"));
  D("Style tweaks · CSS snippets menu", R("tweak-editor", { menu: 1 }));
  D("Style tweaks · unsaved changes", R("tweak-editor", { dirty: 1 }));
  D("DictQuickLookup · results menu", R("dict-menu", { k: "results" }));
  D("DictQuickLookup · look up a word", R("dict-menu", { k: "lookup" }));
  D("DictQuickLookup · Wikipedia language", R("dict-menu", { k: "wikilang" }));
  D("ScreenSaverLockWidget · swipe to unlock", H("home", {}, "unlock"));
  D("ScreenSaverLockWidget · no gesture set", H("home", {}, "unlock", { k: "tap" }));
  D("Statistics · Time range", H("stats", {}, "stats-range", { k: "menu" }));
  D("Statistics · Last 7 days", H("stats", {}, "stats-range", { k: "week" }));
  D("Statistics · Books by month", H("stats", {}, "stats-range", { k: "months" }));
  D("Statistics · Books read in a month", H("stats", {}, "stats-range", { k: "in" }));
  D("Statistics · Days reading this book", R("stats-range", { k: "days" }));
  D("Statistics · All books", H("stats", {}, "stats-books"));
  D("Statistics · Reset book statistics", H("stats", {}, "stats-books", { reset: 1 }));
  D("OPDS · page streaming viewer", H("opds", {}, "image-viewer", { src: "pse", i: 12 }));
  D("ArchiveViewer · archive contents", Lb("archive"));
  D("ArchiveViewer · menu", Lb("archive", { menu: 1 }));
  D("ArchiveViewer · folder in archive", Lb("archive", { sub: "Issue 1" }));
  D("ArchiveViewer · file dialog", Lb("archive-file", { f: "page-03.jpg", sub: "Issue 1" }));
  D("ArchiveViewer · extract all", Lb("archive-extract"));
  D("ArchiveViewer · image list viewer", Lb("image-viewer", { src: "archive", i: 3 }));
})();
