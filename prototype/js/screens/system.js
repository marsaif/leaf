/* ==========================================================================
   Leaf — System screens (owned by the System agent)

   overlays  opening      (page)    {id, phase:"open"|"cache", pct, auto, first}
             error        (dialog)  {kind:"unsupported"|"corrupt"|"storage", file}
             battery      (dialog/page) {state:"low"|"critical"|"charging"|"full", pct}
             lockscreen   (page)    {preview, charging}   clock + message screensaver
             usb          (dialog/page) {phase:"ask"|"connected"|"importing"|"done"}
             update       (page)    {state:"idle"|"checking"|"uptodate"|"available"|"downloading"|"ready"|"installing", pct}
             tz-pick      (sheet)   {key, name, def, builtin}   gesture action picker
   screens   welcome      {step: 0..5}            first run + Quickstart guide
             tapzones     {tab:"tap"|"hold"|"swipe"|"multi", mode, zone}
             dict-manager {tab:"installed"|"catalog", profile, lang, dl, pct}

   Menu links: App.menuSpecial entries for leaf rows, plus shortcut cards
   (the Menus agent's .mn-hero look) injected at the top of matching menu
   pages (Gesture manager, Dictionary settings, Help, Device status alerts…).
   App.openBook(id, {first}) plays the opening transition, then opens the reader.
   ========================================================================== */
(function () {
  const esc = App.esc, icon = App.icon;
  const G = "System";
  const KM = window.KO_MENUS || {}, SH = KM.shared || {};
  const kids = (n) => (!n || !n.items ? [] : Array.isArray(n.items) ? n.items : SH[n.items.ref] || []);
  const findIn = (items, labels) => { let cur = items, n = null; for (const l of labels) { n = cur.find((x) => String(x.text).trim() === l || String(x.text).startsWith(l + " ") || String(x.text).startsWith(l + ":")); if (!n) return null; cur = kids(n); } return n; };
  const tabItems = (tree, ic) => { const t = (KM[tree] || []).find((x) => x.icon === ic); return t ? (Array.isArray(t.items) ? t.items : kids(t)) : []; };
  const pad = (n) => String(n).padStart(2, "0");
  const clock = () => { const t = new Date(); return pad(t.getHours()) + ":" + pad(t.getMinutes()); };
  const shortTitle = (b) => b.title.replace(/\s*\(.*\)$/, "");
  const H = (screen, params = {}, ov, op = {}) => {
    const q = new URLSearchParams(); const put = (k, v) => q.set(k, typeof v === "object" ? JSON.stringify(v) : v);
    for (const [k, v] of Object.entries(params)) put(k, v);
    if (ov) { q.set("o", ov); for (const [k, v] of Object.entries(op)) put("o." + k, v); }
    return `#/${screen}${[...q].length ? "?" + q.toString() : ""}`;
  };
  const truthy = (v) => v === true || v === 1 || v === "1" || v === "true";
  /** status strip with a custom battery state */
  const sbar = (left = "", o = {}) => {
    const pct = o.pct ?? 87;
    const bi = o.charging ? "battery-charging" : pct <= 20 ? "battery-low" : pct <= 60 ? "battery-medium" : "battery-full";
    return `<div class="ko-status"><span>${left}</span><span class="right">${o.wifi === false ? "" : icon("wifi", "sm")}<span>${clock()}</span>${icon(bi, "sm")}<span class="num">${pct}%</span></span></div>`;
  };
  const battGlyph = (pct, o = {}) => `<span class="sy-batt ${o.size || ""} ${pct <= 20 ? "low" : ""}" role="img" aria-label="Battery ${pct}%"><span class="sy-batt-body"><i style="width:${Math.max(4, pct)}%"></i>${o.charging ? `<span class="sy-bolt">${icon("zap")}</span>` : ""}</span><span class="sy-batt-cap"></span></span>`;
  const head = (title, opts = {}) => `<header class="ko-header sy-head"><button class="ko-icon-btn back" ${opts.back || "data-close"} aria-label="Back">${icon("arrow-left")}</button><span class="title">${esc(title)}</span><span class="spacer"></span>${opts.right || ""}</header>`;
  const toggleRow = (ic, label, sub, on, attrs) => `<button class="ko-row sy-row" role="switch" aria-checked="${!!on}" ${attrs}>${ic ? `<span class="ko-icon-tile">${icon(ic)}</span>` : ""}<span class="label"><span class="t">${label}</span>${sub ? `<span class="sub">${sub}</span>` : ""}</span>${App.toggle(on)}</button>`;
  const linkRow = (ic, label, sub, attrs, value) => `<button class="ko-row sy-row" ${attrs}>${ic ? `<span class="ko-icon-tile">${icon(ic)}</span>` : ""}<span class="label"><span class="t">${label}</span>${sub ? `<span class="sub">${sub}</span>` : ""}</span>${value ? `<span class="value">${value}</span>` : ""}${icon("chevron-right", "chev sm")}</button>`;
  const seg = (opts, cur, action, extra = "") => `<div class="ko-seg sy-seg">${opts.map(([v, l]) => `<button class="${String(v) === String(cur) ? "on" : ""}" data-action="${action}" data-v="${v}" ${extra}>${l}</button>`).join("")}</div>`;
  /** generic store-backed flag toggle: data-action="syFlag" data-k="key" data-def="1" */
  App.action("syFlag", (el) => {
    const k = el.dataset.k, on = !App.get(k, el.dataset.def === "1");
    App.set(k, on);
    el.querySelector(".ko-toggle")?.classList.toggle("on", on); el.setAttribute("aria-checked", on);
    if (el.dataset.name) App.toast(`${el.dataset.name} · ${on ? "On" : "Off"}`);
    if (el.dataset.refresh) App.refresh();
  });
  const flag = (k, def) => App.get(k, def);
  const flagRow = (ic, label, sub, k, def, extra = "") => toggleRow(ic, label, sub, flag(k, def), `data-action="syFlag" data-k="${k}" data-def="${def ? 1 : 0}" data-name="${esc(label)}" ${extra}`);

  /* =================================================================
     1. Opening a book
     ================================================================= */
  const opTimers = new WeakSet();
  App.openBook = (id, o = {}) => App.open("opening", { id, auto: 1, ...(o.first ? { first: 1 } : {}) });
  App.overlay("opening", {
    title: "Opening a book", layer: "page",
    render(p) {
      const b = DB.book(p.id || "animal-farm");
      const phase = p.phase || "open";
      const pct = p.pct != null ? Number(p.pct) : p.auto ? 4 : 30;
      const cache = phase === "cache";
      const resume = b.progress ? `Resuming at page ${Math.max(1, Math.round((b.progress / 100) * b.pages))} of ${b.pages}` : `${b.pages} pages · opening for the first time`;
      return `<div class="ko-page sy-op" data-phase="${phase}">
        ${sbar(esc(shortTitle(b)))}
        <div class="sy-op-main">
          <div class="sy-op-cover">${Cover.html(b)}</div>
          <div class="sy-op-title serif">${esc(shortTitle(b))}</div>
          <div class="sy-op-author">${esc(b.author.split(";")[0])}</div>
          <div class="sy-op-track">${App.progress(pct, "ko-progress--thin")}</div>
          <div class="sy-op-cap"><span class="sy-op-step">${cache ? "Building cache…" : "Opening file…"}</span><span class="num sy-op-pct">${pct}%</span></div>
          <div class="sy-op-note">${cache ? `First time only. Laying out ${b.pages} pages and fonts so this book opens instantly next time.` : esc(resume)}</div>
        </div>
        <div class="sy-op-foot"><span>${b.format.toUpperCase()}</span><i></i><span>${esc(b.size)}</span><i></i><span>${esc(b.folder)}</span></div>
      </div>`;
    },
    mount(el, p) {
      if (!truthy(p.auto) || opTimers.has(p)) return;
      opTimers.add(p);
      const id = p.id || "animal-farm";
      const first = truthy(p.first) || !App.get("sy.cached." + id, false);
      let pct = 4, phase = "open";
      const tick = () => {
        const root = document.querySelector("#layer-root .sy-op"); if (!root || App.top()?.params !== p) return;
        pct = Math.min(100, pct + (phase === "open" ? 9 : 6));
        if (phase === "open" && first && pct >= 36) {
          phase = "cache"; root.dataset.phase = "cache";
          root.querySelector(".sy-op-step").textContent = "Building cache…";
          root.querySelector(".sy-op-note").textContent = `First time only. Laying out ${DB.book(id).pages} pages and fonts so this book opens instantly next time.`;
        }
        root.querySelector(".ko-progress > i").style.width = pct + "%";
        root.querySelector(".sy-op-pct").textContent = pct + "%";
        if (pct >= 100) { App.set("sy.cached." + id, true); setTimeout(() => App.go("reader", { id }), 220); return; }
        setTimeout(tick, phase === "open" ? 110 : 140);
      };
      setTimeout(tick, 180);
    },
  });

  /* =================================================================
     2. Errors: unsupported / damaged file, storage almost full
     ================================================================= */
  const ERR = {
    unsupported: { icon: "file-x", title: "Couldn't open this file", file: "Quarterly report.pages",
      body: (f) => `Leaf can't read “${f}”. Apple Pages documents aren't a format KOReader supports.`,
      list: [["Format", "Apple Pages (.pages)"], ["Size", "2.4 MB"], ["Folder", "/mnt/us/documents"]],
      hint: "Export it as PDF or EPUB on your computer, then copy it over. Leaf reads EPUB, PDF, DjVu, CBZ, FB2, MOBI, DOCX, RTF, TXT and HTML.",
      acts: [["folder-open", "Show in folder", "Opens the library at this file", 'data-action="syErrAct" data-msg="Showing in library"'],
        ["usb", "Copy a converted file", "Connect to your computer over USB", 'data-action="syErrUsb"']] },
    corrupt: { icon: "file-warning", title: "This book seems damaged", file: "The Hound of the Baskervilles.epub",
      body: (f) => `“${f}” stopped loading at chapter 4. The file may be incomplete, for example if a copy was interrupted.`,
      list: [["Format", "EPUB"], ["Size", "412 KB (expected 1.9 MB)"], ["Error", "ZIP: unexpected end of archive"]],
      hint: "Your highlights and reading position are stored separately and are safe.",
      acts: [["file-text", "Open what can be read", "Chapters 1–3 open, the rest is skipped", 'data-action="syErrAct" data-msg="Opening chapters 1–3"'],
        ["usb", "Copy the book again", "Connect to your computer over USB", 'data-action="syErrUsb"']] },
  };
  const STORE = { total: 28.6, parts: [["Books", 21.4, "a"], ["Cache & covers", 4.1, "b"], ["System & other", 2.9, "c"]] };
  const CLEAN = [
    ["cache", "Clear page cache", "Rebuilt as you read", 820, true],
    ["covers", "Covers of deleted books", "Thumbnails nobody will see again", 140, true],
    ["finished", "Delete 5 finished books", "Dracula and 4 more · highlights are kept", 1100, false],
    ["dicts", "Unused dictionaries", "Webster's 1913, unused for 6 months", 52, false],
  ];
  const mb = (v) => (v >= 1000 ? (v / 1000).toFixed(1) + " GB" : v + " MB");
  const storageBar = (free, usedParts = STORE.parts) => {
    const kind = { a: 1, b: 2, c: 3 };
    return `<div class="sy-store">${UI.meter(usedParts.map(([, v, c]) => ({ pct: (v / STORE.total) * 100, kind: kind[c] })), {
      head: `<span>${icon("hard-drive", "sm")}Storage</span><span class="num"><b>${free}</b> free of ${STORE.total} GB</span>`,
      legend: usedParts.map(([l, v, c]) => ({ label: l, value: `${v} GB`, kind: kind[c] })) })}</div>`;
  };
  App.overlay("error", {
    title: "Error", layer: "dialog",
    render(p) {
      const kind = p.kind || "unsupported";
      if (kind === "storage") {
        const sel = App.state.syClean || (App.state.syClean = Object.fromEntries(CLEAN.map((c) => [c[0], c[4]])));
        const sum = CLEAN.filter((c) => sel[c[0]]).reduce((a, c) => a + c[3], 0);
        return `<div class="ko-dialog ko-dialog--scroll sy-err sy-storage">
          <div class="ko-dialog-title">${icon("hard-drive")}<span>Storage almost full</span></div><div class="ko-dialog-sub">186 MB left on the device</div>
          <div class="ko-dialog-body">New books, cover thumbnails and the page cache may fail to save.</div>
          ${storageBar("0.2 GB")}
          <div class="sy-sub-label">Free up space</div>
          <div class="sy-clean">${CLEAN.map(([k, l, s, v]) => `<button class="sy-clean-row ${sel[k] ? "on" : ""}" data-action="syClean" data-k="${k}" role="checkbox" aria-checked="${!!sel[k]}">${App.check(!!sel[k])}<span class="grow"><b>${l}</b><span>${s}</span></span><span class="num sy-clean-v">${mb(v)}</span></button>`).join("")}</div>
          <div class="ko-dialog-actions"><button class="ko-btn ko-btn--ghost" data-close>Not now</button><button class="ko-btn ko-btn--primary sy-nowrap" data-action="syCleanGo" ${sum ? "" : "disabled"}>${sum ? `Free up ${mb(sum)}` : "Select items"}</button></div>
        </div>`;
      }
      const e = ERR[kind] || ERR.unsupported, f = p.file || e.file;
      return `<div class="ko-dialog ko-dialog--scroll sy-err">
        <div class="ko-dialog-title">${icon(e.icon)}<span>${esc(e.title)}</span></div>
        <div class="ko-dialog-body">${esc(e.body(f))}</div>
        <div class="ko-kv">${e.list.map(([a, b]) => `<div><span>${esc(a)}</span><span>${esc(b)}</span></div>`).join("")}</div>
        <div class="sy-err-hint">${icon(kind === "corrupt" ? "shield-check" : "info", "sm")}<span>${esc(e.hint)}</span></div>
        <div class="sy-acts">${e.acts.map(([ic, l, s, a]) => `<button class="sy-act" ${a}><span class="ko-icon-tile">${icon(ic)}</span><span class="grow"><b>${l}</b>${s ? `<span>${s}</span>` : ""}</span>${icon("chevron-right", "sm")}</button>`).join("")}</div>
        <div class="ko-dialog-actions"><button class="ko-btn ko-btn--ghost sy-nowrap" data-action="syErrDelete">${icon("trash-2", "sm")}Delete file</button><span class="grow"></span><button class="ko-btn ko-btn--primary" data-close>OK</button></div>
      </div>`;
    },
  });
  App.action("syErrAct", (el) => { App.close(); App.toast(el.dataset.msg); });
  App.action("syErrUsb", () => App.replaceTop("usb", { phase: "ask" }));
  App.action("syErrDelete", () => App.replaceTop("confirm", { title: "Delete this file?", body: "The file is removed from the device. This can't be undone.", ok: "Delete", danger: true }));
  App.action("syClean", (el) => { const s = App.state.syClean; s[el.dataset.k] = !s[el.dataset.k]; App.renderLayers(true); });
  App.action("syCleanGo", () => {
    const s = App.state.syClean, sum = CLEAN.filter((c) => s[c[0]]).reduce((a, c) => a + c[3], 0);
    App.close(); App.toast(`Freed ${mb(sum)} · ${((186 + sum) / 1000).toFixed(1)} GB now free`);
  });

  /* =================================================================
     3. Battery: low / critical warnings, charging / full screen
     ================================================================= */
  App.overlay("battery", {
    title: "Battery", layer: "dialog",
    render(p) {
      const st = p.state || "low";
      const b = DB.current();
      if (st === "charging" || st === "full") {
        const full = st === "full", pct = full ? 100 : Number(p.pct ?? 64);
        const left = Math.round(((100 - pct) / 100) * 190);
        return `<div class="ko-page sy-chg" data-close>
          ${sbar(full ? "Charged" : "Charging", { pct, charging: !full })}
          <div class="sy-chg-main">
            ${battGlyph(pct, { size: "xl", charging: !full })}
            <div class="sy-chg-pct num">${pct}<span>%</span></div>
            <div class="sy-chg-state">${full ? `${icon("circle-check", "sm")}Fully charged. You can unplug the device.` : `${icon("plug-zap", "sm")}Charging · full in about ${Math.floor(left / 60) ? Math.floor(left / 60) + " h " : ""}${left % 60} min`}</div>
            <div class="sy-chg-facts">
              <div><span>Reading time</span><b>${full ? "About 4 weeks" : "About 2½ weeks"}</b></div>
              <div><span>Charger</span><b>USB · 5 V</b></div>
              <div><span>Battery health</span><b>Good</b></div>
            </div>
          </div>
          <div class="sy-chg-book">
            <div class="sy-chg-cov">${Cover.html(b)}</div>
            <div class="grow"><div class="ellipsis sy-chg-bt">${esc(shortTitle(b))}</div><div class="sy-chg-bs">Chapter I · ${b.progress}% · ${Math.floor(b.minutesLeft / 60)} h ${b.minutesLeft % 60} min left</div>${App.progress(b.progress, "ko-progress--thin")}</div>
            <button class="ko-btn ko-btn--primary sy-nowrap" data-go="reader" data-params='{"id":"${b.id}"}'>${icon("book-open", "sm")}Read</button>
          </div>
          <div class="sy-chg-hint">Tap anywhere to return</div>
        </div>`;
      }
      const crit = st === "critical", pct = Number(p.pct ?? (crit ? 4 : 15));
      return `<div class="ko-dialog ko-dialog--scroll sy-batt-dlg ${crit ? "crit" : ""}">
        <div class="ko-dialog-title">${battGlyph(pct)}<span class="grow">${crit ? "Battery critically low" : "Battery low"}</span><span class="sy-batt-n num">${pct}%</span></div>
        <div class="ko-dialog-body">${crit ? "Leaf will save your place and go to sleep at 3%. Connect a charger now." : "About 2 days of reading left at your usual pace. Connect a charger soon."}</div>
        ${crit ? `<div class="sy-err-hint">${icon("bookmark-check", "sm")}<span>Your place in <b>${esc(shortTitle(b))}</b> is saved.</span></div>` : `<div class="ko-group ko-group--sunken sy-dlg-group">
          ${flagRow("leaf", "Battery saver", "Dimmer light, Wi-Fi off", "sy.saver", false)}
          ${linkRow("bell", "Alert thresholds", "", 'data-action="syBattSettings"', "20% / 100%")}
        </div>`}
        <div class="ko-dialog-actions">${crit ? `<button class="ko-btn ko-btn--ghost sy-nowrap" data-action="sySleepNow">${icon("moon", "sm")}Sleep now</button><button class="ko-btn ko-btn--primary" data-close>OK</button>` : `<button class="ko-btn ko-btn--primary" data-close>OK</button>`}</div>
      </div>`;
    },
  });
  App.action("sySleepNow", () => App.replaceTop("lockscreen", { preview: 1 }));
  App.action("syBattSettings", () => { App.closeAll(); App.go("settings", { section: "device", path: devAlertsPath() }); });
  function devAlertsPath() {
    try { const items = Menus.resolveSource(Menus.SECTIONS.device.sources[0]).items; const i = items.findIndex((n) => /^Device status alerts/.test(n.text)); return i >= 0 ? [0, i] : [0]; } catch { return [0]; }
  }

  /* =================================================================
     9. Lock screen: clock + screensaver message
     ================================================================= */
  const LOCK = () => ({ msg: App.get("lock.msg", "If found, please return to the front desk. Reward offered."), pos: App.get("lock.pos", "bottom"),
    clock: App.get("lock.clock", true), book: App.get("lock.book", true), batt: App.get("lock.batt", true) });
  function lockFace(charging) {
    const s = LOCK(), b = DB.current(), d = new Date();
    const date = d.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" });
    const msg = s.msg ? `<div class="sy-lk-msg">${icon("message-square-text", "sm")}<span>${esc(s.msg)}</span></div>` : "";
    return `<div class="sy-lk pos-${s.pos}">
      ${s.pos === "top" ? msg : ""}
      ${s.clock ? `<div class="sy-lk-clock"><div class="sy-lk-time num">${clock()}</div><div class="sy-lk-date">${esc(date)}</div></div>` : ""}
      ${s.pos === "middle" ? msg : ""}
      <div class="grow"></div>
      ${s.book ? `<div class="sy-lk-book"><div class="sy-lk-cov">${Cover.html(b)}</div><div class="grow"><div class="sy-lk-bt ellipsis">${esc(shortTitle(b))}</div><div class="sy-lk-bs">${esc(b.author.split(";")[0])} · ${b.progress}%</div>${App.progress(b.progress, "ko-progress--thin")}</div></div>` : ""}
      ${s.pos === "bottom" ? msg : ""}
      <div class="sy-lk-foot"><span>${icon("moon", "sm")}Sleeping · press the power button to wake</span>${s.batt ? `<span class="num">${icon(charging ? "battery-charging" : "battery-full", "sm")}${charging ? "Charging · 64%" : "87%"}</span>` : ""}</div>
    </div>`;
  }
  App.overlay("lockscreen", {
    title: "Lock screen", layer: "page",
    render(p) {
      if (truthy(p.preview)) return `<div class="ko-page sy-lk-full" data-close>${lockFace(truthy(p.charging))}</div>`;
      const s = LOCK();
      return `<div class="ko-page sy-lkset">
        ${sbar("Sleep screen")}
        ${head("Clock & message", { right: `<button class="ko-btn sy-nowrap" data-open="lockscreen" data-params='{"preview":1}'>${icon("eye", "sm")}Preview</button>` })}
        <div class="ko-scroll"><div class="sy-wrap">
          <p class="sy-intro">A sleep screen with the time, a message and your current book. E Ink keeps it on screen without using power, so the time shown is when the device went to sleep.</p>
          <div class="sy-lk-frame" data-open="lockscreen" data-params='{"preview":1}' role="button" aria-label="Preview"><div class="sy-lk-zoom">${lockFace(false)}</div></div>
          <div class="ko-section-label">Message</div>
          <div class="ko-group">
            <button class="ko-row sy-row" data-open="input" data-params='${App.attrs({ title: "Sleep screen message", hint: "Message", value: s.msg, ok: "Save", action: "syLockMsg" })}'><span class="ko-icon-tile">${icon("message-square-text")}</span><span class="label"><span class="t">Message</span><span class="sub">${esc(s.msg || "None")}</span></span>${icon("pencil", "chev sm")}</button>
            <div class="ko-row sy-row"><span class="ko-icon-tile">${icon("align-vertical-space-around")}</span><span class="label"><span class="t">Position</span></span>${seg([["top", "Top"], ["middle", "Middle"], ["bottom", "Bottom"]], s.pos, "syLockPos")}</div>
          </div>
          <div class="ko-section-label">Show</div>
          <div class="ko-group">
            ${flagRow("clock", "Clock and date", "When the device went to sleep", "lock.clock", true, 'data-rl="1"')}
            ${flagRow("book-open", "Current book", "Cover, title and progress", "lock.book", true, 'data-rl="1"')}
            ${flagRow("battery-full", "Battery level", "Shows “Charging” while plugged in", "lock.batt", true, 'data-rl="1"')}
          </div>
        </div></div>
      </div>`;
    },
  });
  // re-render the preview when a lock-screen flag changes
  document.addEventListener("click", (e) => { const el = e.target.closest && e.target.closest('[data-rl="1"]'); if (el) setTimeout(() => App.renderLayers(true)); });
  App.action("syLockPos", (el) => { App.set("lock.pos", el.dataset.v); App.renderLayers(true); });
  App.action("syLockMsg", (el, v) => { App.set("lock.msg", typeof v === "string" ? v : ""); setTimeout(() => App.renderLayers(true)); });

  /* =================================================================
     4. USB: ask, connected (full screen), importing, done
     ================================================================= */
  const usbArt = () => `<svg class="sy-usb-art" viewBox="0 0 320 150" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <rect x="18" y="22" width="132" height="86" rx="6"/><rect x="28" y="32" width="112" height="66" rx="2" class="fill-soft"/>
      <path d="M6 116 h156 l-8 10 h-140 z"/>
      <path d="M44 50 h34 M44 60 h56 M44 70 h48 M44 80 h30" class="faint-s"/>
      <rect x="236" y="14" width="74" height="104" rx="9"/><rect x="244" y="24" width="58" height="80" rx="2" class="fill-soft"/>
      <path d="M252 38 h42 M252 46 h42 M252 54 h36 M252 62 h42 M252 70 h30" class="faint-s"/>
      <path d="M273 118 v12 q0 8 -8 8 h-60 q-14 0 -14 -14 v-50 q0 -10 -10 -10 h-31" class="cable"/>
      <rect x="186" y="68" width="16" height="12" rx="2" class="dot"/>
    </svg>`;
  App.overlay("usb", {
    title: "USB", layer: "dialog",
    render(p) {
      const ph = p.phase || "connected";
      if (ph === "ask") {
        const rem = App.get("usb.remember", false);
        return `<div class="ko-dialog ko-dialog--scroll sy-usbask">
          <div class="ko-dialog-title">${icon("usb")}<span>Connected to a computer</span></div>
          <div class="ko-dialog-body">Transfer books, or keep reading while the device charges?</div>
          <div class="sy-acts">
            <button class="sy-act" data-action="syUsbGo"><span class="ko-icon-tile">${icon("hard-drive-download")}</span><span class="grow"><b>Transfer books</b><span>The device appears as a drive. Reading pauses.</span></span>${icon("chevron-right", "sm")}</button>
            <button class="sy-act" data-action="syUsbCharge"><span class="ko-icon-tile">${icon("battery-charging")}</span><span class="grow"><b>Charge only</b><span>Keep reading while it charges</span></span>${icon("chevron-right", "sm")}</button>
          </div>
          <button class="ko-check-row" data-action="syUsbRemember">${App.check(rem)}<span>Remember my choice</span></button>
        </div>`;
      }
      if (ph === "done") {
        const nb = ["walden", "time-machine", "jane-eyre"].map((id) => DB.book(id));
        return `<div class="ko-dialog ko-dialog--scroll sy-usbdone">
          <div class="ko-dialog-title">${icon("library-big")}<span>3 new books added</span></div>
          <div class="ko-dialog-body">Found in /documents while you were connected.</div>
          <div class="sy-newbooks">${nb.map((b) => `<div class="sy-nb">${Cover.html(b, { badge: "New", badgeCls: "ko-badge--accent" })}<span class="ellipsis">${esc(shortTitle(b))}</span></div>`).join("")}</div>
          <div class="sy-err-hint">${icon("file-x", "sm")}<span>1 file skipped, not a book: <b>notes-backup.zip</b></span></div>
          <div class="ko-dialog-actions"><button class="ko-btn ko-btn--ghost" data-close>Close</button><button class="ko-btn ko-btn--primary sy-nowrap" data-action="syUsbLib">View new books</button></div>
        </div>`;
      }
      const importing = ph === "importing";
      const pct = Number(p.pct ?? 58);
      return `<div class="ko-page sy-usb">
        ${sbar("USB", { pct: 64, charging: true, wifi: false })}
        <div class="ko-scroll"><div class="sy-usb-main ${importing ? "imp" : ""}">
          ${usbArt()}
          <div class="sy-usb-title serif">${importing ? "Adding new books…" : "Connected to computer"}</div>
          <div class="sy-usb-sub">${importing ? "Reading covers and details of the files you copied." : "Transfer books from your computer"}</div>
          ${importing ? `<div class="sy-usb-prog">${App.progress(pct)}<div class="sy-op-cap"><span>Scanning /documents</span><span class="num">${Math.round(pct / 100 * 4)} of 4 files</span></div></div>` : `
          <ol class="sy-steps">
            <li><span class="sy-step-n num">1</span><span><b>Open the “Kindle” drive</b> in Finder or File Explorer.</span></li>
            <li><span class="sy-step-n num">2</span><span><b>Copy books into “documents”</b> or a folder inside it. EPUB, PDF, CBZ, FB2, MOBI, DjVu and more.</span></li>
            <li><span class="sy-step-n num">3</span><span><b>Eject the drive</b> on your computer, then tap Exit USB mode.</span></li>
          </ol>
          <div class="ko-card sy-usb-drive">
            <div class="sy-usb-dh"><span class="ko-icon-tile">${icon("hard-drive")}</span><span class="grow"><b>Kindle</b><span>/documents · 24 books</span></span><span class="sy-usb-chg">${icon("battery-charging", "sm")}<span class="num">Charging · 64%</span></span></div>
            ${storageBar("3.1 GB", [["Books", 21.4, "a"], ["Cache & covers", 1.2, "b"], ["System & other", 2.9, "c"]])}
          </div>`}
        </div></div>
        ${importing ? "" : `<footer class="sy-usb-foot"><button class="ko-btn ko-btn--primary sy-nowrap sy-wide" data-action="syUsbExit">${icon("log-out", "sm")}Exit USB mode</button><div class="sy-usb-note">${icon("lock", "sm")}Leaf is paused while connected. Your reading position is saved.</div></footer>`}
      </div>`;
    },
  });
  App.action("syUsbRemember", () => { App.set("usb.remember", !App.get("usb.remember", false)); App.renderLayers(true); });
  App.action("syUsbGo", () => App.replaceTop("usb", { phase: "connected" }));
  App.action("syUsbCharge", () => { App.close(); App.toast("Charging · 64%"); });
  App.action("syUsbLib", () => { App.closeAll(); App.go("library", { tab: "library" }); });
  App.action("syUsbExit", () => {
    App.replaceTop("usb", { phase: "importing", pct: 8 });
    let pct = 8;
    const t = setInterval(() => {
      if (App.top()?.name !== "usb") return clearInterval(t);
      pct += 23; const bar = document.querySelector("#layer-root .sy-usb .ko-progress > i");
      if (bar) { bar.style.width = Math.min(100, pct) + "%"; const n = document.querySelector("#layer-root .sy-usb .sy-op-cap .num"); if (n) n.textContent = `${Math.min(4, Math.round(pct / 25))} of 4 files`; }
      if (pct >= 100) { clearInterval(t); setTimeout(() => App.replaceTop("usb", { phase: "done" }), 250); }
    }, 260);
  });

  /* =================================================================
     5. First run welcome + Quickstart guide
     ================================================================= */
  const W = () => ({ theme: document.querySelector(".ko-screen.theme-paper") ? "paper" : "dark",
    size: App.get("wel.size", 20), font: App.get("wel.font", "literata"), margin: App.get("wel.margin", "m"), spacing: App.get("wel.spacing", "n"),
    folder: App.get("wel.folder", "/mnt/us/documents"), layout: App.get("tz.layout", "lr") });
  const FONTS = { literata: ["Literata", "var(--font-book)"], serif: ["Source Serif", '"Source Serif 4", Georgia, serif'], inter: ["Inter", "var(--font-ui)"] };
  function miniUI(t) {
    const bs = ["animal-farm", "pride", "meditations"].map((id) => DB.book(id));
    return `<div class="sy-mini theme-${t}" aria-hidden="true">
      <div class="sy-mini-top"><i></i><i></i></div>
      <div class="sy-mini-h"></div>
      <div class="sy-mini-hero"><div class="sy-mini-cov">${Cover.html(bs[0])}</div><div class="grow"><i class="l1"></i><i class="l2"></i><span class="sy-mini-bar"><i></i></span><span class="sy-mini-btn"></span></div></div>
      <div class="sy-mini-row">${bs.map((b) => `<div class="sy-mini-c">${Cover.html(b)}</div>`).join("")}</div>
    </div>`;
  }
  const gestRow = (ic, a, b) => `<div class="ko-row sy-row"><span class="ko-icon-tile">${icon(ic)}</span><span class="label"><span class="t">${a}</span><span class="sub">${b}</span></span></div>`;
  function welStep(step, s) {
    const hd = (n, title, sub) => `<div class="sy-wel-head"><div class="sy-eyebrow">Step ${n} of 4</div><h1 class="sy-wel-title serif">${title}</h1><p class="sy-wel-sub">${sub}</p></div>`;
    if (step === 0) {
      const bs = ["frankenstein", "animal-farm", "siddhartha"].map((id) => DB.book(id));
      return `<div class="sy-wel-hero">
        <div class="sy-fan">${bs.map((b, i) => `<div class="sy-fan-c c${i}">${Cover.html(b)}</div>`).join("")}</div>
        <div class="sy-wordmark serif">Leaf</div>
        <p class="sy-wel-tag">A calm home for your books, built on KOReader.</p>
        <div class="ko-group sy-wel-points">
          ${gestRow("palette", "Pick a look and reading defaults", "Dark or Paper, font size, margins")}
          ${gestRow("hand", "Learn the taps", "Turn pages, open menus, look up words")}
          ${gestRow("folder-open", "Choose your library folder", "Where books copied over USB go")}
        </div>
        <div class="sy-wel-keep">${icon("shield-check", "sm")}<span>Existing KOReader settings, highlights and reading progress are kept.</span></div>
      </div>`;
    }
    if (step === 1) return hd(1, "Choose a look", "Dark is gentle at night. Paper gives the crispest contrast on E Ink. Switch any time with Night mode.") + `
      <div class="sy-theme-pick" role="radiogroup">${[["dark", "Dark", "Near-black, warm accent"], ["paper", "Paper", "Light, like the page"]].map(([t, l, sub]) => `
        <button class="sy-theme-opt ${s.theme === t ? "on" : ""}" data-action="welTheme" data-v="${t}" role="radio" aria-checked="${s.theme === t}">
          <div class="sy-theme-frame">${miniUI(t)}${s.theme === t ? `<span class="ko-selmark sy-sel-badge">${icon("check", "sm")}</span>` : ""}</div>
          <div class="sy-theme-cap">${App.radio(s.theme === t)}<span class="grow"><b>${l}</b><span>${sub}</span></span></div>
        </button>`).join("")}</div>
      <div class="ko-group sy-gap">${flagRow("sunset", "Switch automatically", "Paper by day, Dark after sunset", "wel.autonight", false)}</div>`;
    if (step === 2) {
      const f = FONTS[s.font] || FONTS.literata;
      const lh = { c: 1.35, n: 1.55, a: 1.8 }[s.spacing] || 1.55, mg = { s: 14, m: 24, l: 38 }[s.margin] || 24;
      const paras = TextGen.chapter("animal-farm", 0, 3);
      return hd(2, "Reading defaults", "Used for every new book. Each book can still keep its own settings.") + `
        <div class="sy-read-prev" style="--rp-fs:${(s.size * 0.8).toFixed(1)}px; --rp-lh:${lh}; --rp-mg:${mg}px; --rp-ff:${f[1]}">
          <div class="sy-rp-chap">Chapter I</div>${paras.map((t) => `<p>${esc(t)}</p>`).join("")}
        </div>
        <div class="ko-card sy-read-ctl">
          ${App.sliderRow({ label: "Font size", icon: "a-large-small", pct: ((s.size - 12) / 20) * 100, value: s.size, unit: "pt", slide: "welSizeSl", step: "welStep", id: "wel-size", minIcon: "a-arrow-down", maxIcon: "a-arrow-up" })}
          <div class="sy-field"><span>Font</span>${seg(Object.entries(FONTS).map(([k, v]) => [k, v[0]]), s.font, "welSet", 'data-k="wel.font"')}</div>
          <div class="sy-field"><span>Margins</span>${seg([["s", "Narrow"], ["m", "Medium"], ["l", "Wide"]], s.margin, "welSet", 'data-k="wel.margin"')}</div>
          <div class="sy-field"><span>Line spacing</span>${seg([["c", "Compact"], ["n", "Normal"], ["a", "Airy"]], s.spacing, "welSet", 'data-k="wel.spacing"')}</div>
        </div>`;
    }
    if (step === 3) return hd(3, "Taps and gestures", "The page is split into zones. Tap the sides to turn pages, the top or bottom for menus.") + `
      <div class="sy-wel-gest">
        <div class="sy-wel-diag">${tzDiagram(tzZones("tap", "single"), { mini: true })}</div>
        <div class="ko-group sy-gest-list">
          ${gestRow("arrow-left-right", "Swipe left or right", "Turn pages")}
          ${gestRow("text-cursor", "Long-press a word", "Look it up in your dictionaries")}
          ${gestRow("hand-grab", "Pinch or spread", "Change the font size")}
          ${gestRow("move-diagonal-2", "Short diagonal swipe", "Full refresh, clears ghosting")}
        </div>
      </div>
      <div class="ko-group sy-gap"><div class="ko-row sy-row"><span class="ko-icon-tile">${icon("layout-panel-left")}</span><span class="label"><span class="t">Page-turn zones</span></span>${seg([["lr", "Left / right"], ["tb", "Top / bottom"]], s.layout === "bt" ? "tb" : s.layout, "welLayout")}</div>
      ${linkRow("hand", "Customise every zone", "Later, in Taps and gestures › Tap zones", 'data-go="tapzones"')}</div>`;
    if (step === 4) {
      const F = [["/mnt/us/documents", "Documents", "Kindle's default folder · 24 books found"], ["/mnt/us/books", "Books", "7 books found"], ["/mnt/us", "Whole device", "Slower to scan · 31 books found"]];
      return hd(4, "Where are your books?", "Leaf shows this folder as your library. Books copied over USB should go here.") + `
        <div class="ko-group sy-folders" role="radiogroup">${F.map(([path, l, sub]) => `<button class="ko-row sy-row sy-radio-row ${s.folder === path ? "on" : ""}" role="radio" aria-checked="${s.folder === path}" data-action="welFolder" data-v="${path}">${App.radio(s.folder === path)}<span class="label"><span class="t">${l}<span class="sy-path">${path}</span></span><span class="sub">${sub}</span></span></button>`).join("")}
          ${linkRow("folder-search", "Choose another folder…", "Browse the device", 'data-toast="Opening folder picker"')}</div>
        <div class="ko-section-label sy-sl">Options</div>
        <div class="ko-group">
          ${flagRow("folder-tree", "Include subfolders", "Books in folders inside it appear too", "wel.sub", true)}
          ${flagRow("file-question", "Show unsupported files", "Off hides notes, archives and other files", "wel.unsup", false)}
        </div>`;
    }
    const f = FONTS[s.font] || FONTS.literata;
    const st = (n) => `data-go="welcome" data-params='{"step":${n}}'`;
    return `<div class="sy-wel-done">
      <span class="sy-done-ic">${icon("check")}</span>
      <h1 class="sy-wel-title serif">You're all set</h1>
      <p class="sy-wel-sub">Everything here can be changed later in Settings.</p>
      <div class="ko-group sy-summary">
        ${linkRow(s.theme === "dark" ? "moon" : "sun", "Look", "", st(1), s.theme === "dark" ? "Dark" : "Paper")}
        ${linkRow("type", "Reading", "", st(2), `${f[0]} · ${s.size} pt`)}
        ${linkRow("hand", "Page turns", "", st(3), s.layout === "lr" ? "Left / right" : "Top / bottom")}
        ${linkRow("folder-open", "Library", "", st(4), esc(s.folder))}
      </div>
      <div class="sy-wel-keep">${icon("graduation-cap", "sm")}<span>Open this guide again from Help › Quickstart guide.</span></div>
    </div>`;
  }
  App.screen("welcome", {
    title: "Welcome",
    render(p) {
      const step = Math.max(0, Math.min(5, Number(p.step) || 0)), s = W();
      const dots = [1, 2, 3, 4].map((i) => `<i class="${i < step ? "done" : i === step ? "on" : ""}"></i>`).join("");
      const next = step === 0 ? "Get started" : step === 5 ? "Start reading" : "Continue";
      return `<div class="ko-view sy-wel" data-step="${step}">
        ${App.statusBar()}
        <header class="sy-wel-top">${step > 0 && step < 5 ? `<div class="sy-dots" aria-label="Step ${step} of 4">${dots}</div>` : `<span class="sy-wel-brand">${step === 5 ? "Setup complete" : "Quickstart"}</span>`}<span class="grow"></span>${step < 5 ? `<button class="ko-btn ko-btn--ghost sy-nowrap" data-action="welSkip">Skip</button>` : ""}</header>
        <div class="ko-scroll"><div class="sy-wel-body">${welStep(step, s)}</div></div>
        <footer class="sy-wel-foot">${step > 0 ? `<button class="ko-btn ko-btn--ghost sy-nowrap" data-go="welcome" data-params='{"step":${step - 1}}'>${icon("arrow-left", "sm")}Back</button>` : `<span></span>`}
          <button class="ko-btn ko-btn--primary sy-nowrap sy-next" ${step === 5 ? 'data-action="welFinish"' : `data-go="welcome" data-params='{"step":${step + 1}}'`}>${next}${step < 5 ? icon("arrow-right", "sm") : ""}</button></footer>
      </div>`;
    },
  });
  App.action("welTheme", (el) => { if (App.setTheme) App.setTheme(el.dataset.v); else App.refresh(); });
  App.action("welSet", (el) => { App.set(el.dataset.k, el.dataset.v); App.refresh(); });
  App.action("welLayout", (el) => { App.set("tz.layout", el.dataset.v); App.refresh(); });
  App.action("welFolder", (el) => { App.set("wel.folder", el.dataset.v); App.refresh(); });
  const setSize = (v) => {
    v = Math.max(12, Math.min(32, Math.round(v))); App.set("wel.size", v);
    const pv = document.querySelector(".sy-read-prev"); if (pv) pv.style.setProperty("--rp-fs", (v * 0.8).toFixed(1) + "px");
    const n = document.querySelector('.ko-sr[data-id="wel-size"] .val'); if (n) n.innerHTML = `${v}<small>pt</small>`;
    const sl = document.querySelector(".sy-read-ctl .ko-slider"); if (sl) sl.style.setProperty("--v", ((v - 12) / 20) * 100 + "%");
  };
  App.action("welSize", (el) => setSize(App.get("wel.size", 20) + Number(el.dataset.d)));
  App.action("welSizeSl", (s, v) => setSize(12 + v * 20));
  App.action("welStep", (el) => setSize(App.get("wel.size", 20) + Number(el.dataset.dir)));
  App.action("welSkip", () => { App.set("wel.done", true); App.go("home"); App.toast("Quickstart skipped · find it in Help"); });
  App.action("welFinish", () => { App.set("wel.done", true); App.go("home"); App.toast("Welcome to Leaf"); });

  /* =================================================================
     7. Visual tap-zone editor
     ================================================================= */
  const GMN = () => findIn(tabItems("reader_menu", "appbar.settings"), ["Taps and gestures", "Gesture manager"]);
  const gChild = (labels) => { const gm = GMN(); return gm ? findIn(kids(gm), labels) : null; };
  const actOf = (n) => { if (!n) return null; const m = String(n.text).match(/\s{3,}\((.+)\)\s*$/); return m ? m[1] : null; };
  const nodeName = (n) => String(n.text).replace(/\s{3,}\(.+\)\s*$/, "").trim();
  let CATS = null;
  /** the real gesture action list: categories of Gesture manager › Tap corner › Top left ({ref} lists resolved) */
  function actionCats() {
    if (CATS) return CATS;
    const tl = gChild(["Tap corner", "Top left"]);
    CATS = kids(tl).filter((n) => (n.kind === "submenu" || n.items) && kids(n).length && !/QuickMenu position/.test(n.text))
      .map((n) => ({ name: n.text, items: kids(n).map((c) => ({ t: c.text })) }));
    if (!CATS.length) CATS = [{ name: "Reader", items: ["Next chapter", "Previous chapter", "Table of contents", "Toggle bookmark"].map((t) => ({ t })) }];
    return CATS;
  }
  const BUILTIN = ["Previous page", "Next page", "Show reading controls"];
  const ACT_IC = [[/^pass through/i, "mouse-pointer-click"], [/^nothing/i, "ban"], [/previous page|turn pages: -/i, "chevron-left"], [/next page|turn pages/i, "chevron-right"],
    [/reading controls/i, "panel-bottom-open"], [/bottom menu/i, "sliders-horizontal"], [/show menu|menu search/i, "menu"], [/bookmark/i, "bookmark"],
    [/contents|toc/i, "list-tree"], [/refresh/i, "refresh-cw"], [/frontlight|warmth|light/i, "sun"], [/night/i, "moon"], [/font|typography|spacing/i, "type"],
    [/dictionary/i, "book-a"], [/wikipedia/i, "book-open-text"], [/search/i, "search"], [/history|previous location|back/i, "history"], [/zoom/i, "zoom-in"],
    [/flipping|skim|page browser|book map/i, "gallery-horizontal"], [/chapter/i, "skip-forward"], [/go to page/i, "hash"], [/favorites/i, "star"],
    [/status/i, "panel-bottom"], [/rotat|orientation/i, "rotate-cw"], [/screenshot/i, "camera"], [/statistics/i, "chart-column"], [/link/i, "link"],
    [/reflow/i, "wrap-text"], [/selection|highlight/i, "highlighter"], [/wi-?fi|network/i, "wifi"], [/sleep|exit|restart/i, "power"]];
  const actIcon = (a) => (ACT_IC.find(([re]) => re.test(a || "")) || [0, "zap"])[1];
  const catOf = (a) => { if (BUILTIN.includes(a)) return "Leaf"; for (const c of actionCats()) if (c.items.some((x) => x.t === a)) return c.name.replace(/\s*\(.*\)$/, ""); return ""; };

  // zone boxes in % of the screen: [x, y, w, h]
  const C = 13, CW = 22;
  const CORNERS = [["tl", "Top left"], ["tr", "Top right"], ["bl", "Bottom left"], ["br", "Bottom right"]];
  const corner = (k, name, src) => ({ k, name, box: { tl: [0, 0, CW, C], tr: [100 - CW, 0, CW, C], bl: [0, 100 - C, CW, C], br: [100 - CW, 100 - C, CW, C] }[k], src, corner: true });
  const corners = (group) => CORNERS.map(([k, l]) => corner(k, l + " corner", [group, l]));
  function tzZones(tab, mode) {
    const layout = App.get("tz.layout", "lr");
    if (tab === "tap" && mode === "double") return [...corners("Double tap"),
      { k: "left", name: "Left side", box: [0, C, 50, 100 - 2 * C], src: ["Double tap", "Left side"] },
      { k: "right", name: "Right side", box: [50, C, 50, 100 - 2 * C], src: ["Double tap", "Right side"] }];
    if (tab === "tap" && mode === "two") return [...corners("Two-finger tap corner"),
      { k: "rest", name: "Rest of the page", box: [0, C, 100, 100 - 2 * C], locked: "Two-finger taps only work in corners", lockNote: "Use Double tap or Hold for more gestures" }];
    if (tab === "hold") return [...corners("Long-press on corner"),
      { k: "text", name: "Text", box: [0, C, 100, 100 - 2 * C], locked: "Select text · look up a word", lockNote: "Change in Taps and gestures › Long-press on text" }];
    const z = [...corners("Tap corner"),
      { k: "top", name: "Top edge", box: [CW, 0, 100 - 2 * CW, C], def: "Show menu" },
      { k: "bottom", name: "Bottom edge", box: [CW, 100 - C, 100 - 2 * CW, C], def: "Show bottom menu" }];
    if (layout === "lr") z.push({ k: "left", name: "Left third", box: [0, C, 33.33, 100 - 2 * C], def: "Previous page" },
      { k: "center", name: "Centre", box: [33.33, C, 33.34, 100 - 2 * C], def: "Show reading controls" },
      { k: "right", name: "Right third", box: [66.67, C, 33.33, 100 - 2 * C], def: "Next page" });
    else { const up = layout === "tb" ? "Previous page" : "Next page", dn = layout === "tb" ? "Next page" : "Previous page";
      z.push({ k: "upper", name: "Upper half", box: [0, C, 100, (100 - 2 * C) / 2], def: up }, { k: "lower", name: "Lower half", box: [0, 50, 100, (100 - 2 * C) / 2], def: dn }); }
    return z;
  }
  const zKey = (tab, mode, k) => `tz:${tab}.${tab === "tap" ? mode : "-"}.${k}`;
  const defFor = (z) => z.def || actOf(gChild(z.src || [])) || "Pass through";
  const actFor = (key, def) => App.get(key, def);
  const isPass = (a) => /^(pass through|nothing)/i.test(a || "");
  const pageLines = () => `<div class="sy-dev-text">${[92, 96, 88, 94, 70, 95, 90, 97, 84, 93, 60, 91, 95, 78].map((w) => `<i style="width:${w}%"></i>`).join("")}</div>`;
  function tzDiagram(zones, o = {}) {
    const tab = o.tab || "tap", mode = o.mode || "single";
    return `<div class="sy-dev ${o.mini ? "mini" : ""}"><div class="sy-dev-scr">${pageLines()}
      ${zones.map((z) => {
        const a = z.locked || (o.mini ? defFor(z) : actFor(zKey(tab, mode, z.k), defFor(z)));
        const sel = o.sel === z.k, [x, y, w, h] = z.box;
        const inner = z.corner ? `<span class="sy-z-ic">${icon(actIcon(a), "sm")}</span>`
          : `<span class="sy-z-in"><span class="sy-z-name">${esc(z.name)}</span><span class="sy-z-act">${z.locked ? icon("lock", "sm") : ""}${esc(a)}</span></span>`;
        return `<button class="sy-zone ${z.corner ? "corner" : ""} ${sel ? "sel" : ""} ${isPass(a) ? "pass" : ""} ${z.locked ? "locked" : ""}" style="left:${x}%;top:${y}%;width:${w}%;height:${h}%" ${o.mini ? 'tabindex="-1"' : `data-action="tzZone" data-z="${z.k}"`} title="${esc(z.name)}: ${esc(a)}" aria-pressed="${sel}">${inner}${sel ? `<span class="sy-z-check">${icon("check", "sm")}</span>` : ""}</button>`;
      }).join("")}</div></div>`;
  }
  // one-finger swipe markers: [key, KOReader label, icon, [x%, y%]]
  const EDGES = [
    ["leu", "Left edge up", "arrow-up", [0, 32]], ["led", "Left edge down", "arrow-down", [0, 60]],
    ["reu", "Right edge up", "arrow-up", [100, 32]], ["red", "Right edge down", "arrow-down", [100, 60]],
    ["tel", "Top edge left", "arrow-left", [36, 0]], ["ter", "Top edge right", "arrow-right", [64, 0]],
    ["bel", "Bottom edge left", "arrow-left", [36, 100]], ["ber", "Bottom edge right", "arrow-right", [64, 100]],
    ["diag", "Short diagonal swipe", "move-diagonal", [50, 66]],
  ];
  function swipeDiagram(sel) {
    return `<div class="sy-dev"><div class="sy-dev-scr">${pageLines()}
      <div class="sy-sw-centre"><span class="sy-z-name">Swipe left or right</span><span class="sy-z-act">${icon("lock", "sm")}Turn pages</span></div>
      ${EDGES.map(([k, name, ic, [x, y]]) => {
        const a = actFor(zKey("swipe", "-", k), actOf(gChild(["One-finger swipe", name])) || "Pass through");
        return `<button class="sy-edge ${sel === k ? "sel" : ""} ${isPass(a) ? "pass" : ""}" style="left:${x}%;top:${y}%" data-action="tzZone" data-z="${k}" title="${name}: ${esc(a)}" aria-pressed="${sel === k}">${icon(ic, "sm")}${isPass(a) ? "" : `<span class="sy-edge-dot"></span>`}</button>`;
      }).join("")}</div></div>`;
  }
  const TWO = [["⇒", "Swipe right", "arrow-right"], ["⇐", "Swipe left", "arrow-left"], ["⇓", "Swipe down", "arrow-down"], ["⇑", "Swipe up", "arrow-up"],
    ["⇗", "Swipe up-right", "arrow-up-right"], ["⇖", "Swipe up-left", "arrow-up-left"], ["⇘", "Swipe down-right", "arrow-down-right"], ["⇙", "Swipe down-left", "arrow-down-left"]];
  const VEC = { "⬅": [-1, 0], "➡": [1, 0], "⬆": [0, -1], "⬇": [0, 1], "⬈": [1, -1], "⬉": [-1, -1], "⬊": [1, 1], "⬋": [-1, 1] };
  const ARW = { "⬅": "arrow-left", "➡": "arrow-right", "⬆": "arrow-up", "⬇": "arrow-down", "⬈": "arrow-up-right", "⬉": "arrow-up-left", "⬊": "arrow-down-right", "⬋": "arrow-down-left" };
  const dirWords = { "⬅": "left", "➡": "right", "⬆": "up", "⬇": "down", "⬈": "up-right", "⬉": "up-left", "⬊": "down-right", "⬋": "down-left" };
  const pickParams = (key, name, def, builtin) => App.attrs({ key, name, def, ...(builtin ? { builtin: 1 } : {}) });
  function detailPanel(tab, mode, z) {
    if (!z) return "";
    const kind = tab === "tap" ? { single: "Single tap", double: "Double tap", two: "Two-finger tap" }[mode] : tab === "hold" ? "Long-press" : "Swipe";
    if (z.locked) return `<div class="ko-card sy-tz-detail"><div class="sy-tz-dh"><b>${esc(z.name)}</b><span>${kind}</span></div>
      <div class="sy-tz-locked"><span class="ko-icon-tile">${icon("lock")}</span><span class="grow"><b>${esc(z.locked)}</b><span>${esc(z.lockNote || "")}</span></span></div></div>`;
    const key = zKey(tab, mode, z.k), def = defFor(z), a = actFor(key, def);
    return `<div class="ko-card sy-tz-detail">
      <div class="sy-tz-dh"><b>${esc(z.name)}</b><span>${kind}</span></div>
      <button class="ko-row sy-row sy-tz-act" data-open="tz-pick" data-params="${pickParams(key, z.name + " · " + kind, def, !z.src)}">
        <span class="ko-icon-tile ko-icon-tile--accent">${icon(actIcon(a))}</span><span class="label"><span class="t">${esc(a)}</span><span class="sub">${a === def ? "Default" : `${esc(catOf(a) || "Custom")} · default is ${esc(def)}`}</span></span><span class="value">Change</span>${icon("chevron-right", "chev sm")}</button>
      ${flagRow("shield", "Always active", "Also works in menus and dialogs", key + "#always", false)}
      ${a !== def ? `<button class="ko-row sy-row" data-action="tzReset" data-k="${key}"><span class="ko-icon-tile">${icon("rotate-ccw")}</span><span class="label"><span class="t">Reset to default</span><span class="sub">${esc(def)}</span></span></button>` : ""}
    </div>`;
  }
  const actRow = (ic, name, key, def) => { const a = actFor(key, def); return `<button class="ko-row sy-row" data-open="tz-pick" data-params="${pickParams(key, name, def)}"><span class="ko-icon-tile">${icon(ic)}</span><span class="label"><span class="t">${name}</span></span><span class="value ${isPass(a) ? "" : "set"}">${esc(a)}</span>${icon("chevron-right", "chev sm")}</button>`; };
  App.screen("tapzones", {
    title: "Tap zones",
    render(p) {
      const tab = ["tap", "hold", "swipe", "multi"].includes(p.tab) ? p.tab : "tap";
      const mode = ["single", "double", "two"].includes(p.mode) ? p.mode : "single";
      const tabs = [["tap", "Tap"], ["hold", "Hold"], ["swipe", "Swipe"], ["multi", "Multi-swipe"]].map(([k, l]) => `<button class="ko-tab ${tab === k ? "on" : ""}" data-go="tapzones" data-params='{"tab":"${k}"}'>${l}</button>`).join("");
      let body = "";
      if (tab === "tap" || tab === "hold") {
        const zones = tzZones(tab, mode);
        const selK = p.zone && zones.some((z) => z.k === p.zone) ? p.zone : zones.find((z) => !z.locked).k;
        const z = zones.find((x) => x.k === selK);
        const top = tab === "tap" ? `<div class="sy-tz-mode">${seg([["single", "Single"], ["double", "Double"], ["two", "Two fingers"]], mode, "tzMode")}<span class="sy-tz-hint">Tap a zone to change it</span></div>` : `<div class="sy-tz-mode sy-tz-note">${icon("info", "sm")}Hold a corner for about half a second.</div>`;
        const lay = App.get("tz.layout", "lr");
        const extra = tab === "tap" && mode === "single" ? `<div class="ko-section-label">Page turns</div><div class="ko-group">
            <div class="ko-row sy-row sy-row-stack"><span class="ko-icon-tile">${icon("layout-panel-left")}</span><span class="label"><span class="t">Page-turn zones</span></span>${seg([["lr", "Left / right"], ["tb", "Top / bottom"], ["bt", "Bottom / top"]], lay, "tzLayout")}</div>
            ${flagRow("arrow-left-right", "Invert page turn taps and swipes", "For left-handed reading", "tz.invert", false)}
            ${flagRow("hand", "Page turns with taps", "Off: only swipes and buttons turn pages", "tz.taps", true)}
          </div>` : tab === "hold" ? `<div class="ko-section-label">Options</div><div class="ko-group">${flagRow("ban", "Ignore long-press on corners", "If you hold the device by its corners", "tz.ignoreHold", false)}</div>`
          : mode === "double" ? `<div class="ko-section-label">Options</div><div class="ko-group">${flagRow("timer", "Disable double tap", "Single taps respond faster while it's off", "tz.noDouble", true)}</div>` : "";
        body = `${top}<div class="sy-tz-grid"><div class="sy-tz-left">${tzDiagram(zones, { tab, mode, sel: selK })}<div class="sy-tz-legend"><span><i class="lg-set"></i>Action set</span><span><i class="lg-pass"></i>Pass through</span><span><i class="lg-sel"></i>Selected</span></div></div>
          <div class="sy-tz-right">${detailPanel(tab, mode, z)}${extra}</div></div>`;
      } else if (tab === "swipe") {
        const selK = EDGES.some((e) => e[0] === p.zone) ? p.zone : "diag";
        const e = EDGES.find((x) => x[0] === selK);
        const z = { k: e[0], name: e[1], src: ["One-finger swipe", e[1]] };
        const two = TWO.map(([g, name, ic]) => actRow(ic, name, zKey("swipe", "-", "2" + ic), actOf(gChild(["Two-finger swipe", g])) || "Pass through")).join("");
        const other = [["Spread and pinch", "Spread", "Spread", "maximize-2"], ["Spread and pinch", "Pinch", "Pinch", "minimize-2"], ["Two-finger rotation", "Rotate clockwise", "Rotate clockwise", "rotate-cw"], ["Two-finger rotation", "Rotate counterclockwise", "Rotate counterclockwise", "rotate-ccw"]]
          .map(([grp, lbl, name, ic]) => actRow(ic, name, zKey("swipe", "-", "o" + ic), actOf(kids(gChild([grp])).find((x) => String(x.text).startsWith(lbl))) || "Pass through")).join("");
        body = `<div class="sy-tz-mode sy-tz-note">${icon("info", "sm")}Start at an edge of the screen and slide along it.</div>
          <div class="sy-tz-grid"><div class="sy-tz-left">${swipeDiagram(selK)}<div class="sy-tz-legend"><span><i class="lg-dot"></i>Action set</span><span><i class="lg-sel"></i>Selected</span></div></div>
          <div class="sy-tz-right">${detailPanel("swipe", "-", z)}
          <div class="ko-section-label">Two-finger swipes</div><div class="ko-group">${two}</div>
          <div class="ko-section-label">Pinch and rotate</div><div class="ko-group">${other}</div></div></div>`;
      } else {
        const ms = kids(gChild(["Multiswipes"]));
        const on = App.get("tz.multi", false);
        body = `<div class="sy-tz-mode sy-tz-note">${icon("info", "sm")}Draw the shape without lifting your finger. Straight and diagonal strokes can't be mixed.</div>
          <div class="ko-group sy-gap-top">${flagRow("spline", "Turn on multiswipes", "Adds a short delay to normal swipes", "tz.multi", false, 'data-refresh="1"')}</div>
          <div class="ko-section-label">${ms.length} shapes${on ? "" : " · off"}</div>
          <div class="ko-group sy-ms-list ${on ? "" : "dim"}">${ms.map((n) => {
            const seq = nodeName(n), def = actOf(n) || "Nothing", key = zKey("multi", "-", seq.replace(/\s+/g, "")), a = actFor(key, def);
            const words = [...seq].filter((c) => VEC[c]).map((c) => dirWords[c]).join(", ");
            return `<button class="ko-row sy-row" data-open="tz-pick" data-params="${pickParams(key, "Multiswipe · " + words, def)}"><span class="sy-ms-seq" aria-label="${words}">${[...seq].filter((c) => VEC[c]).map((c) => icon(ARW[c], "sm")).join("")}</span><span class="label"><span class="t">${esc(a)}</span><span class="sub">${words}</span></span>${icon("chevron-right", "chev sm")}</button>`;
          }).join("")}</div>
          <div class="ko-group sy-gap">${linkRow("circle-dot", "Record a custom multiswipe", "Draw your own shape, then pick its action", 'data-toast="Multiswipe recorder · draw a shape"')}</div>`;
      }
      return `<div class="ko-view sy-tz" data-tab="${tab}">
        ${App.statusBar({ left: "Settings" })}
        <header class="ko-header sy-head"><button class="ko-icon-btn back" data-go="settings" data-params='{"section":"gestures"}' aria-label="Back">${icon("arrow-left")}</button><span class="title">Tap zones</span><span class="spacer"></span>
          <button class="ko-icon-btn" data-action="tzResetAll" aria-label="Reset all gestures">${icon("rotate-ccw")}</button></header>
        <nav class="ko-tabs">${tabs}</nav>
        <div class="ko-scroll"><div class="sy-tz-body">${body}</div><div class="sy-end"></div></div>
        ${App.bottomNav("settings")}
      </div>`;
    },
  });
  App.action("tzZone", (el) => { App.current.params = { ...App.current.params, zone: el.dataset.z }; App.refresh(); App.syncHash(); });
  App.action("tzMode", (el) => App.go("tapzones", { tab: "tap", mode: el.dataset.v }));
  App.action("tzLayout", (el) => { App.set("tz.layout", el.dataset.v); const pp = { ...App.current.params }; delete pp.zone; App.current.params = pp; App.refresh(); App.syncHash(); });
  App.action("tzReset", (el) => { delete App.store[el.dataset.k]; App.save(); App.refresh(); App.toast("Reset to default"); });
  App.action("tzResetAll", () => App.open("confirm", { title: "Reset all gestures?", body: "Every tap zone, swipe and multiswipe goes back to KOReader's defaults.", ok: "Reset", danger: true, icon: "rotate-ccw", action: "tzResetAllOk" }));
  App.action("tzResetAllOk", () => { Object.keys(App.store).filter((k) => k.startsWith("tz:")).forEach((k) => delete App.store[k]); App.save(); setTimeout(() => { App.refresh(); App.toast("Gestures reset"); }); });

  /* action picker sheet */
  App.overlay("tz-pick", {
    title: "Choose action", layer: "sheet",
    render(p) {
      const cur = actFor(p.key, p.def);
      const row = (t, sub) => `<button class="ko-row sy-row sy-radio-row ${t === cur ? "on" : ""}" role="radio" aria-checked="${t === cur}" data-action="tzSet" data-v="${esc(t)}" data-f="${esc(t.toLowerCase())}">${App.radio(t === cur)}<span class="label"><span class="t">${esc(t)}${t === p.def ? `<span class="ko-pill ko-pill--caps sy-tag">Default</span>` : ""}</span>${sub ? `<span class="sub">${sub}</span>` : ""}</span></button>`;
      const cats = actionCats();
      const total = cats.reduce((a, c) => a + c.items.length, 0) + 2 + (truthy(p.builtin) ? BUILTIN.length : 0);
      return `<div class="ko-sheet sy-pick">
        <div class="grip"></div>
        <div class="ko-sheet-head"><div class="grow"><div class="ko-eyebrow sy-pick-eyebrow">${esc(p.name || "Gesture")}</div><div class="title">Choose an action</div></div><button class="ko-icon-btn" data-close aria-label="Close">${icon("x")}</button></div>
        <div class="sy-pick-filter"><label class="ko-input">${icon("search", "sm")}<input type="search" placeholder="Filter ${total} actions…" data-sy-filter=".sy-pick"></label></div>
        <div class="ko-scroll sy-pick-list">
          <div class="ko-group sy-fgroup">${row("Pass through", "The tap reaches the page: links, footnotes")}${row("Nothing", "Ignore this gesture")}</div>
          ${truthy(p.builtin) ? `<div class="ko-section-label sy-fhead">Leaf</div><div class="ko-group sy-fgroup">${BUILTIN.map((t) => row(t)).join("")}</div>` : ""}
          ${cats.map((c) => `<div class="ko-section-label sy-fhead">${esc(c.name)} <span class="sy-count">${c.items.length}</span></div><div class="ko-group sy-fgroup">${c.items.map((x) => row(x.t)).join("")}</div>`).join("")}
          <div class="sy-nores faint" hidden>No action matches.</div>
          <div class="sy-end"></div>
        </div>
      </div>`;
    },
    mount(el) { const on = el && el.querySelector(".sy-radio-row.on"), list = el && el.querySelector(".sy-pick-list"); if (on && list && on.offsetTop > list.clientHeight - 60) list.scrollTop = on.offsetTop - list.clientHeight / 2; },
  });
  App.action("tzSet", (el) => {
    const p = App.top()?.params || {}; const v = el.dataset.v;
    if (v === p.def) delete App.store[p.key]; else App.store[p.key] = v;
    App.save(); App.close(); App.refresh(); App.toast(v);
  });

  /* filter inputs (data-sy-filter="<scope selector>") hide rows and empty groups */
  document.addEventListener("input", (e) => {
    const f = e.target.closest && e.target.closest("[data-sy-filter]"); if (!f) return;
    const scope = f.closest(f.dataset.syFilter) || document; const q = f.value.trim().toLowerCase();
    let shown = 0;
    scope.querySelectorAll(".sy-fgroup").forEach((g) => {
      let any = 0; g.querySelectorAll("[data-f]").forEach((r) => { const ok = !q || r.dataset.f.includes(q); r.hidden = !ok; if (ok) any++; });
      g.hidden = !any; const h = g.previousElementSibling; if (h && h.classList.contains("sy-fhead")) h.hidden = !any; shown += any;
    });
    scope.querySelectorAll(".sy-hide-on-filter").forEach((x) => (x.hidden = !!q));
    const nr = scope.querySelector(".sy-nores"); if (nr) nr.hidden = !!shown;
  });

  /* =================================================================
     8. Dictionary manager
     ================================================================= */
  const DICTS = {
    oxford: { name: "Oxford Dictionary of English", pair: "English", entries: "350,000", size: 118, src: "StarDict" },
    mawrid: { name: "Al-Mawrid Mini", pair: "English → Arabic", entries: "61,000", size: 9.6, src: "StarDict" },
    wordnet: { name: "WordNet 3.1", pair: "English", entries: "155,000", size: 34, src: "Princeton" },
    "wikt-ar-en": { name: "Wiktionary Arabic → English", pair: "Arabic → English", entries: "52,800", size: 22, src: "Wiktionary" },
    webster: { name: "Webster's 1913", pair: "English", entries: "109,000", size: 52, src: "Project Gutenberg" },
    "wikt-en-ar": { name: "English → Arabic", full: "English → Arabic (Wiktionary, offline)", pair: "English → Arabic", entries: "48,210", size: 31, src: "Wiktionary, offline" },
    "wikt-en": { name: "Wiktionary English", pair: "English", entries: "1,240,000", size: 410, src: "Wiktionary" },
    "freedict-en-ar": { name: "FreeDict English → Arabic", pair: "English → Arabic", entries: "21,400", size: 4.1, src: "FreeDict" },
    "wikt-ar": { name: "Wiktionary Arabic", pair: "Arabic", entries: "38,500", size: 19, src: "Wiktionary" },
    "freedict-ar-en": { name: "FreeDict Arabic → English", pair: "Arabic → English", entries: "17,900", size: 3.2, src: "FreeDict" },
    simple: { name: "Simple English Wiktionary", pair: "English", entries: "92,000", size: 26, src: "Wiktionary" },
  };
  const PROFILES = { all: ["All books", ["oxford", "mawrid", "wordnet", "wikt-ar-en", "webster"], ["oxford", "mawrid", "wordnet", "wikt-ar-en"]],
    en: ["English books", ["oxford", "mawrid", "wordnet", "webster", "wikt-ar-en"], ["oxford", "mawrid", "wordnet"]],
    ar: ["Arabic books", ["wikt-ar-en", "mawrid", "oxford", "wordnet", "webster"], ["wikt-ar-en", "mawrid"]] };
  const installed = () => App.get("dict.installed", ["oxford", "mawrid", "wordnet", "wikt-ar-en", "webster"]);
  const orderOf = (pf) => { const inst = installed(); const o = App.get("dict.order." + pf, PROFILES[pf][1]).filter((id) => inst.includes(id)); inst.forEach((id) => { if (!o.includes(id)) o.push(id); }); return o; };
  const enabledOf = (pf) => App.get("dict.on." + pf, PROFILES[pf][2]);
  const dlState = (App.state.syDl = App.state.syDl || {});
  const fmtMB = (v) => (v >= 100 ? Math.round(v) : v) + " MB";
  const ALL_LANGS = (() => { const n = findIn(tabItems("reader_menu", "appbar.search"), ["Settings", "Dictionary settings", "Download dictionaries"]); return kids(n).map((x) => String(x.text)); })();
  const langCount = (l) => 1 + ((l.length * 7 + l.charCodeAt(0)) % 4);
  const LANG_DICTS = { English: ["wikt-en-ar", "wikt-en", "simple", "freedict-en-ar", "oxford", "wordnet", "webster"], Arabic: ["wikt-ar", "wikt-ar-en", "freedict-ar-en", "mawrid"] };
  const genDict = (lang, i) => {
    const kinds = [[`Wiktionary ${lang} → English`, `${lang} → English`, "Wiktionary"], [`Wiktionary English → ${lang}`, `English → ${lang}`, "Wiktionary"], [`FreeDict ${lang} → English`, `${lang} → English`, "FreeDict"], [`Wiktionary ${lang}`, lang, "Wiktionary"]];
    const [name, pair, src] = kinds[i % 4], size = +(((lang.length * 13 + i * 29) % 90) / 3 + 1.4).toFixed(1);
    return { id: `gen-${lang}-${i}`, name, pair, src, size, entries: (((lang.length * 3917 + i * 1201) % 90000) + 4000).toLocaleString("en-US") };
  };
  const dlPct = (id, p) => dlState[id] ?? (p.dl === id ? Number(p.pct ?? 46) : null);
  function dlButton(id, size, p) {
    if (installed().includes(id)) return `<span class="sy-dl-done">${icon("check", "sm")}Installed</span>`;
    const pct = dlPct(id, p);
    if (pct != null) return `<span class="sy-dl-prog" data-dl="${id}"><span class="num sy-dl-pct">${pct}%</span><button class="ko-icon-btn sy-dl-x" data-action="dmCancel" data-id="${id}" aria-label="Cancel download">${icon("x", "sm")}</button></span>`;
    return `<button class="ko-btn sy-nowrap" data-action="dmDownload" data-id="${id}">${icon("download", "sm")}${fmtMB(size)}</button>`;
  }
  const dlBar = (id, p) => { const pct = dlPct(id, p), d = DICTS[id]; return pct != null && d && !installed().includes(id) ? `<div class="sy-dl-bar" data-dlbar="${id}">${App.progress(pct, "ko-progress--thin")}<span class="num">${(d.size * pct / 100).toFixed(1)} of ${fmtMB(d.size)} · keep Wi-Fi on</span></div>` : ""; };
  const catRow = (id, d, p) => `<div class="ko-row sy-row sy-cat-row" data-f="${esc((d.name + " " + d.pair + " " + d.src).toLowerCase())}"><span class="label"><span class="t">${esc(d.full || d.name)}</span><span class="sub">${esc(d.src)} · ${d.entries} entries</span>${dlBar(id, p)}</span>${dlButton(id, d.size, p)}</div>`;
  function dictSettingsPath() {
    try { const items = Menus.resolveSource(Menus.SECTIONS.search.sources[0]).items; const i = items.findIndex((n) => n.text === "Settings"); const j = kids(items[i]).findIndex((n) => n.text === "Dictionary settings"); return i >= 0 && j >= 0 ? [0, i, j] : [0]; } catch { return [0]; }
  }
  App.screen("dict-manager", {
    title: "Dictionaries",
    render(p) {
      const tab = p.tab === "catalog" || p.lang ? "catalog" : "installed";
      const inst = installed();
      const tabs = `<nav class="ko-tabs"><button class="ko-tab ${tab === "installed" ? "on" : ""}" data-go="dict-manager">Installed<span class="sy-count">${inst.length}</span></button><button class="ko-tab ${tab === "catalog" ? "on" : ""}" data-go="dict-manager" data-params='{"tab":"catalog"}'>Get more</button></nav>`;
      let body;
      if (p.lang) {
        const ids = LANG_DICTS[p.lang];
        const list = ids ? ids.map((id) => catRow(id, DICTS[id], p)).join("") : Array.from({ length: langCount(p.lang) }, (_, i) => { const d = genDict(p.lang, i); DICTS[d.id] = d; return catRow(d.id, d, p); }).join("");
        body = `<button class="sy-crumb" data-go="dict-manager" data-params='{"tab":"catalog"}'>${icon("chevron-left", "sm")}All languages</button>
          <div class="sy-lang-h"><div class="sy-lang-t">${esc(p.lang)}</div><div class="sy-desc">${ids ? ids.length : langCount(p.lang)} dictionaries · work offline once downloaded</div></div>
          <div class="ko-group">${list}</div>`;
      } else if (tab === "installed") {
        const pf = PROFILES[p.profile] ? p.profile : "all";
        const order = orderOf(pf), on = enabledOf(pf);
        const total = inst.reduce((a, id) => a + (DICTS[id]?.size || 0), 0);
        let rank = 0;
        body = `<div class="sy-dm-prof"><span class="sy-dm-prof-l">Use for</span>${seg(Object.entries(PROFILES).map(([k, v]) => [k, v[0]]), pf, "dmProfile")}</div>
          <p class="sy-hint">${pf === "all" ? "Lookups search the enabled dictionaries from top to bottom." : `Books in ${pf === "en" ? "English" : "Arabic"} use this order instead of the default.`}</p>
          <div class="ko-group sy-dict-list">${order.map((id, i) => {
            const d = DICTS[id], en = on.includes(id); if (en) rank++;
            return `<div class="ko-row sy-row sy-dict ${en ? "" : "off"}">
              <span class="sy-rank num">${en ? rank : "–"}</span>
              <span class="label"><span class="t">${esc(d.full || d.name)}</span><span class="sub">${esc(d.pair)} · ${fmtMB(d.size)}</span></span>
              <span class="sy-reorder"><button class="ko-icon-btn" data-action="dmMove" data-id="${id}" data-d="-1" ${i === 0 ? "disabled" : ""} aria-label="Move up">${icon("arrow-up", "sm")}</button><button class="ko-icon-btn" data-action="dmMove" data-id="${id}" data-d="1" ${i === order.length - 1 ? "disabled" : ""} aria-label="Move down">${icon("arrow-down", "sm")}</button></span>
              <button class="sy-tg" data-action="dmToggle" data-id="${id}" role="switch" aria-checked="${en}" aria-label="Use ${esc(d.name)}">${App.toggle(en)}</button>
            </div>`;
          }).join("")}</div>
          <div class="sy-dm-sum">${icon("hard-drive", "sm")}<span>${inst.length} dictionaries · ${fmtMB(Math.round(total))} on the device</span><span class="grow"></span><button class="sy-inline-link" data-go="dict-manager" data-params='{"tab":"catalog"}'>${icon("download", "sm")}Get more</button></div>
          <div class="ko-section-label">Lookup</div>
          <div class="ko-group">
            ${flagRow("sparkles", "Fuzzy search", "Finds “running” under “run”", "dict.fuzzy", true)}
            ${flagRow("history", "Lookup history", "Keeps words for the vocabulary builder", "dict.hist", true)}
            ${flagRow("maximize-2", "Large window", "Open results in a taller panel", "dict.large", false)}
            ${linkRow("bookmark-plus", "Dictionary presets", "Save sets of enabled dictionaries", 'data-toast="Dictionary presets"')}
            ${linkRow("settings-2", "All dictionary settings", "Font size, buttons, external dictionary", `data-go="settings" data-params='${App.attrs({ section: "search", path: dictSettingsPath() })}'`)}
          </div>`;
      } else {
        const id = "wikt-en-ar", f = DICTS[id], inF = installed().includes(id), busy = dlPct(id, p) != null;
        const featured = `<div class="ko-card sy-feat">
          <div class="sy-feat-eyebrow">${icon("sparkles", "sm")}Recommended for you</div>
          <div class="sy-feat-main"><div class="sy-feat-glyph" aria-hidden="true"><span>Aa</span><span class="ar">ع</span></div>
            <div class="grow"><div class="sy-feat-t">English → Arabic</div><div class="sy-feat-s">Wiktionary, offline · ${f.entries} entries · ${fmtMB(f.size)}</div></div></div>
          <div class="sy-feat-why">You read in English and Arabic, like <i>${esc(shortTitle(DB.book("animal-farm")))}</i> and <bdi class="ar">${esc(DB.book("ar-poems").title)}</bdi>.</div>
          ${dlBar(id, p)}
          <div class="sy-feat-act">${inF ? `<span class="sy-dl-done">${icon("check", "sm")}Installed · used for English books</span>` : busy ? `<span class="sy-feat-busy">Downloading</span>${dlButton(id, f.size, p)}` : `<button class="ko-btn ko-btn--primary sy-nowrap" data-action="dmDownload" data-id="${id}">${icon("download", "sm")}Download · ${fmtMB(f.size)}</button><button class="ko-btn ko-btn--ghost sy-nowrap" data-go="dict-manager" data-params='{"tab":"catalog","lang":"English"}'>More English</button>`}</div>
        </div>`;
        const yours = ["English", "Arabic"].map((l) => `<div class="ko-section-label sy-fhead">${l}</div><div class="ko-group sy-fgroup">${LANG_DICTS[l].filter((x) => x !== id).slice(0, 3).map((x) => catRow(x, DICTS[x], p)).join("")}
          <button class="ko-row sy-row" data-go="dict-manager" data-params='${App.attrs({ tab: "catalog", lang: l })}' data-f="${l.toLowerCase()}"><span class="label"><span class="t">All ${l} dictionaries</span></span><span class="value">${LANG_DICTS[l].length}</span>${icon("chevron-right", "chev sm")}</button></div>`).join("");
        const all = `<div class="ko-section-label sy-fhead">All languages <span class="sy-count">${ALL_LANGS.length}</span></div><div class="ko-group sy-fgroup sy-langs">${ALL_LANGS.map((l) => `<button class="ko-row sy-row" data-go="dict-manager" data-params='${App.attrs({ tab: "catalog", lang: l })}' data-f="${esc(l.toLowerCase())}"><span class="label"><span class="t">${esc(l)}</span></span><span class="value">${LANG_DICTS[l] ? LANG_DICTS[l].length : langCount(l)}</span>${icon("chevron-right", "chev sm")}</button>`).join("")}</div>`;
        body = `<div class="sy-dm-search"><label class="ko-input">${icon("search", "sm")}<input type="search" placeholder="Search ${ALL_LANGS.length} languages" data-sy-filter=".sy-dm"></label></div>
          <div class="sy-hide-on-filter">${featured}</div><div class="ko-section-label sy-hide-on-filter sy-your">Your reading languages</div>${yours}${all}<div class="sy-nores faint" hidden>No language matches.</div>`;
      }
      return `<div class="ko-view sy-dm">
        ${App.statusBar({ left: "Settings" })}
        <header class="ko-header sy-head"><button class="ko-icon-btn back" ${p.lang ? `data-go="dict-manager" data-params='{"tab":"catalog"}'` : `data-go="settings" data-params='{"section":"search"}'`} aria-label="Back">${icon("arrow-left")}</button><span class="title">Dictionaries</span><span class="spacer"></span>
          <button class="ko-icon-btn" data-toast="Copy StarDict files to koreader/data/dict" aria-label="Install from file">${icon("folder-input")}</button></header>
        ${tabs}
        <div class="ko-scroll"><div class="sy-dm-body">${body}</div><div class="sy-end"></div></div>
        ${App.bottomNav("settings")}
      </div>`;
    },
  });
  App.action("dmProfile", (el) => App.go("dict-manager", el.dataset.v === "all" ? {} : { profile: el.dataset.v }));
  const curProfile = () => (PROFILES[App.current.params.profile] ? App.current.params.profile : "all");
  App.action("dmToggle", (el) => {
    const pf = curProfile(), on = enabledOf(pf).slice(), id = el.dataset.id, i = on.indexOf(id);
    if (i >= 0) on.splice(i, 1); else on.push(id);
    App.set("dict.on." + pf, on); App.refresh(); App.toast(`${DICTS[id].name} · ${i >= 0 ? "Off" : "On"}`);
  });
  App.action("dmMove", (el) => {
    const pf = curProfile(), o = orderOf(pf), i = o.indexOf(el.dataset.id), j = i + Number(el.dataset.d);
    if (j < 0 || j >= o.length) return; [o[i], o[j]] = [o[j], o[i]]; App.set("dict.order." + pf, o); App.refresh();
  });
  App.action("dmCancel", (el) => { delete dlState[el.dataset.id]; if (App.current.params.dl === el.dataset.id) { const pp = { ...App.current.params }; delete pp.dl; delete pp.pct; App.current.params = pp; App.syncHash(); } App.refresh(); App.toast("Download cancelled"); });
  App.action("dmDownload", (el) => {
    const id = el.dataset.id; if (dlState[id] != null) return;
    dlState[id] = 0; App.refresh();
    const t = setInterval(() => {
      if (dlState[id] == null) return clearInterval(t);
      dlState[id] = Math.min(100, dlState[id] + 9);
      const d = DICTS[id];
      document.querySelectorAll(`[data-dl="${id}"] .sy-dl-pct`).forEach((n) => (n.textContent = dlState[id] + "%"));
      document.querySelectorAll(`[data-dlbar="${id}"]`).forEach((b) => { b.querySelector(".ko-progress > i").style.width = dlState[id] + "%"; b.querySelector("span").textContent = `${(d.size * dlState[id] / 100).toFixed(1)} of ${fmtMB(d.size)} · keep Wi-Fi on`; });
      if (dlState[id] >= 100) {
        clearInterval(t); delete dlState[id];
        App.set("dict.installed", installed().concat(id));
        Object.keys(PROFILES).forEach((pf) => { if (pf !== "ar" || /^Arabic/.test(d.pair)) App.set("dict.on." + pf, enabledOf(pf).concat(id)); });
        if (App.current.name === "dict-manager") App.refresh();
        App.toast(`${d.full || d.name} installed`);
      }
    }, 220);
  });

  /* =================================================================
     6. Software update
     ================================================================= */
  const CHANGES = [
    ["New", ["Leaf interface: new home, library, reader and settings", "Visual tap-zone editor in Taps and gestures", "Dictionary catalog with offline Wiktionary, including English → Arabic"]],
    ["Improved", ["Large EPUBs open up to 3× faster", "Arabic shaping and justification in mixed-language books", "PDF reflow keeps simple tables together"]],
    ["Fixed", ["Highlights inside footnotes now export correctly", "Wi-Fi reconnects after sleep on Kindle Paperwhite", "Rare crash with CBZ files that have very long names"]],
  ];
  const UPD_STATES = ["idle", "checking", "uptodate", "available", "downloading", "ready", "installing"];
  App.overlay("update", {
    title: "Software update", layer: "page",
    render(p) {
      const st = UPD_STATES.includes(p.state) ? p.state : "available";
      const pct = Number(p.pct ?? 45);
      if (st === "installing") return `<div class="ko-page sy-op sy-inst">${sbar("Updating", { wifi: false })}<div class="sy-op-main">
          <span class="sy-upd-mark big">K</span>
          <div class="sy-op-title">Installing v2026.08</div>
          <div class="sy-op-author">Keep the device on</div>
          <div class="sy-op-track">${App.progress(pct, "ko-progress--thin")}</div>
          <div class="sy-op-cap"><span class="sy-op-step">Replacing files…</span><span class="num sy-op-pct">${pct}%</span></div>
          <div class="sy-op-note">Leaf restarts by itself and reopens ${esc(shortTitle(DB.current()))} where you left off.</div></div>
          <div class="sy-op-foot"><span>v2026.07.1</span>${icon("arrow-right", "sm")}<span>v2026.08</span></div></div>`;
      const cur = `<div class="ko-card sy-upd-cur"><span class="sy-upd-mark">K</span><div class="grow"><b>KOReader v2026.07.1</b><span>Leaf UI · installed 14 July · ${App.get("upd.channel", "stable") === "stable" ? "Stable" : "Nightly"} channel</span></div></div>`;
      let main = "";
      if (st === "idle") main = `<div class="sy-upd-state">${icon("clock", "sm")}<span>Last checked 3 days ago</span></div><button class="ko-btn ko-btn--primary ko-btn--block sy-nowrap" data-action="updCheck">${icon("refresh-cw", "sm")}Check for updates</button>`;
      if (st === "checking") main = `<div class="sy-upd-state">${icon("loader", "sm ko-spin")}<span>Checking koreader.rocks…</span></div><button class="ko-btn ko-btn--block sy-nowrap" disabled>Checking…</button>`;
      if (st === "uptodate") main = `<div class="ko-card sy-upd-ok">${icon("badge-check")}<div><b>You're up to date</b><span>v2026.07.1 is the latest stable release · checked just now</span></div></div>`;
      if (["available", "downloading", "ready"].includes(st)) {
        const act = st === "available" ? `<div class="sy-upd-btns"><button class="ko-btn ko-btn--primary sy-nowrap" data-action="updDownload">${icon("download", "sm")}Download · 38.4 MB</button><button class="ko-btn ko-btn--ghost sy-nowrap" data-close>Later</button></div>`
          : st === "downloading" ? `<div class="sy-upd-dl">${App.progress(pct)}<div class="sy-op-cap"><span class="num sy-upd-mb">${(38.4 * pct / 100).toFixed(1)} of 38.4 MB</span><span class="sy-upd-eta">About ${Math.max(2, Math.round((100 - pct) * 0.7))} s left</span></div></div><div class="sy-upd-btns"><button class="ko-btn sy-nowrap" data-action="updCancel">Cancel</button><span class="sy-upd-note">${icon("wifi", "sm")}Keep Wi-Fi on</span></div>`
          : `<div class="sy-upd-ready">${icon("circle-check", "sm")}<span>Downloaded and verified. Installing takes about a minute.</span></div><div class="sy-upd-btns"><button class="ko-btn ko-btn--primary sy-nowrap" data-action="updRestart">${icon("rotate-ccw", "sm")}Restart to install</button><button class="ko-btn ko-btn--ghost sy-nowrap" data-close>Later</button></div>`;
        main = `<div class="ko-card sy-upd-new">
          <div class="sy-upd-eyebrow">${st === "ready" ? "Ready to install" : "Update available"}</div>
          <div class="sy-upd-ver"><span class="sy-upd-v">v2026.08</span><span class="sy-upd-meta">Stable · 38.4 MB · released 16 November</span></div>
          ${act}
          <div class="sy-log">${CHANGES.map(([h, items]) => `<div class="sy-log-h">${h}</div><ul>${items.map((x) => `<li>${esc(x)}</li>`).join("")}</ul>`).join("")}
            <button class="sy-inline-link" data-toast="Opening full release notes">Full release notes ${icon("arrow-up-right", "sm")}</button></div>
        </div>`;
      }
      return `<div class="ko-page sy-upd">
        ${sbar("Settings")}
        ${head("Software update")}
        <div class="ko-scroll"><div class="sy-wrap">
          ${cur}${main}
          <div class="ko-section-label">Options</div>
          <div class="ko-group">
            <div class="ko-row sy-row"><span class="ko-icon-tile">${icon("git-branch")}</span><span class="label"><span class="t">Channel</span><span class="sub">Nightly gets fixes first, may be unstable</span></span>${seg([["stable", "Stable"], ["nightly", "Nightly"]], App.get("upd.channel", "stable"), "updChannel")}</div>
            ${flagRow("calendar-clock", "Check automatically", "Once a week, only on Wi-Fi", "upd.auto", true)}
            ${linkRow("file-archive", "Install from file", "An update package copied over USB", 'data-toast="No update package found in /koreader"')}
            ${linkRow("history", "Previous versions", "Roll back if something breaks", 'data-toast="v2026.07.1 · v2026.06 · v2026.05 available"')}
          </div>
        </div><div class="sy-end"></div></div>
      </div>`;
    },
  });
  const setUpd = (state, extra = {}) => { const t = App.top(); if (t && t.name === "update") { t.params = { state, ...extra }; App.renderLayers(); App.syncHash(); } };
  App.action("updChannel", (el) => { App.set("upd.channel", el.dataset.v); App.renderLayers(true); App.toast(`Channel · ${el.textContent}`); });
  App.action("updCheck", () => { setUpd("checking"); setTimeout(() => { if (App.top()?.name === "update") setUpd("available"); }, 1200); });
  let updTimer = null;
  App.action("updDownload", () => {
    setUpd("downloading", { pct: 0 }); let pct = 0; clearInterval(updTimer);
    updTimer = setInterval(() => {
      const t = App.top(); if (!t || t.name !== "update" || t.params.state !== "downloading") return clearInterval(updTimer);
      pct = Math.min(100, pct + 7); t.params.pct = pct;
      const root = document.querySelector("#layer-root .sy-upd"); if (root) {
        root.querySelector(".sy-upd-dl .ko-progress > i").style.width = pct + "%";
        root.querySelector(".sy-upd-mb").textContent = `${(38.4 * pct / 100).toFixed(1)} of 38.4 MB`;
        root.querySelector(".sy-upd-eta").textContent = `About ${Math.max(1, Math.round((100 - pct) * 0.7))} s left`;
      }
      if (pct >= 100) { clearInterval(updTimer); setUpd("ready"); }
    }, 200);
  });
  App.action("updCancel", () => { clearInterval(updTimer); setUpd("available"); App.toast("Download cancelled"); });
  App.action("updRestart", () => {
    setUpd("installing", { pct: 5 }); let pct = 5;
    const t = setInterval(() => {
      const top = App.top(); if (!top || top.name !== "update") return clearInterval(t);
      pct = Math.min(100, pct + 8);
      const root = document.querySelector("#layer-root .sy-inst"); if (root) { root.querySelector(".ko-progress > i").style.width = pct + "%"; root.querySelector(".sy-op-pct").textContent = pct + "%"; }
      if (pct >= 100) { clearInterval(t); App.closeAll(); App.go("home"); App.toast("Updated to v2026.08"); }
    }, 160);
  });

  /* =================================================================
     Menu links
     ================================================================= */
  const SP = App.menuSpecial || (App.menuSpecial = {});
  SP["quickstart guide"] = () => { App.closeAll(); App.go("welcome", { step: 0 }); };
  SP["gesture overview"] = () => { App.closeAll(); App.go("tapzones", { tab: "tap" }); };
  SP["multiswipe recorder"] = () => { App.closeAll(); App.go("tapzones", { tab: "multi" }); };
  SP["manage dictionaries"] = () => { App.closeAll(); App.go("dict-manager"); };
  SP["download dictionaries"] = () => { App.closeAll(); App.go("dict-manager", { tab: "catalog" }); };
  SP["check for updates"] = () => { App.closeAll(); App.open("update", { state: "idle" }); };

  // shortcut cards at the top of matching menu pages (the Menus agent's .mn-hero look)
  const card = (ic, a, b, attrs) => `<button class="ko-card ko-card--accent mn-hero sy-hero" ${attrs}><span class="ko-icon-tile">${icon(ic)}</span><span class="grow"><b>${a}</b><span>${b}</span></span>${icon("arrow-up-right", "sm")}</button>`;
  const HEROES = [
    [/^(taps and gestures|gesture manager|tap corner|double tap|long-press on corner|two-finger tap corner|page turns)$/i, () => card("hand", "Tap-zone editor", "See the screen's zones and reassign them on a picture", `data-go="tapzones"`)],
    [/^(one-finger swipe|two-finger swipe|spread and pinch|two-finger rotation)$/i, () => card("hand", "Tap-zone editor · Swipes", "Edge swipes, two-finger swipes and pinches", `data-go="tapzones" data-params='{"tab":"swipe"}'`)],
    [/^(multiswipes|custom multiswipes)$/i, () => card("spline", "Tap-zone editor · Multi-swipes", "Every shape drawn, with its action", `data-go="tapzones" data-params='{"tab":"multi"}'`)],
    [/^(dictionary settings|search & dictionaries)$/i, () => card("book-a", "Dictionary manager", `${installed().length} installed · order and on/off per language`, `data-go="dict-manager"`)],
    [/^download dictionaries$/i, () => card("download", "Dictionary catalog", "Sizes, sources and one-tap downloads", `data-go="dict-manager" data-params='{"tab":"catalog"}'`)],
    [/^help$/i, () => card("download", "Software update", "v2026.08 is available · 38.4 MB", `data-action="syOpenUpdate"`)],
    [/^help & about$/i, () => card("download", "Software update", "v2026.08 is available · 38.4 MB", `data-action="syOpenUpdate"`) + card("graduation-cap", "Quickstart guide", "Look, reading defaults, gestures, library folder", `data-go="welcome"`)],
    [/^device status alerts$/i, () => card("battery-low", "Preview battery alerts", "Low, critical and charging screens", `data-action="syOpenBatt"`)],
    [/^device$/i, () => card("clock", "Clock & message sleep screen", "Time, a message in case it's lost, current book", `data-action="syOpenLock"`)],
  ];
  App.action("syOpenUpdate", () => { App.closeAll(); App.open("update", { state: "available" }); });
  App.action("syOpenLock", () => { App.closeAll(); App.open("lockscreen"); });
  App.action("syOpenBatt", () => { App.closeAll(); App.open("battery", { state: "low" }); });
  function inject(root) {
    root.querySelectorAll(".set-view, .st-view, .mn-pane").forEach((pane) => {
      const t = pane.querySelector(".set-head .ko-page-title, .st-head .st-title, .mn-head .mn-title"), body = pane.querySelector(".set-body, .st-body, .mn-body");
      if (!t || !body || body.querySelector(".sy-hero")) return;
      const title = (t.childNodes[0]?.textContent || "").trim();
      const h = HEROES.find(([re]) => re.test(title)); if (!h) return;
      body.insertAdjacentHTML("afterbegin", h[1]());
      App.icons();
    });
  }
  const sr = document.getElementById("screen-root"), lr = document.getElementById("layer-root");
  if (window.MutationObserver && sr && lr) {
    const mo = new MutationObserver(() => { inject(sr); inject(lr); });
    mo.observe(sr, { childList: true }); mo.observe(lr, { childList: true });
  }

  /* =================================================================
     Designer states
     ================================================================= */
  const D = (label, hash) => App.demo(G, label, hash);
  D("Opening · Opening file…", H("library", {}, "opening", { id: "frankenstein", pct: 34 }));
  D("Opening · Building cache (first time)", H("library", {}, "opening", { id: "moby", phase: "cache", pct: 62 }));
  D("Opening · Animated, then reader", H("library", {}, "opening", { id: "animal-farm", auto: 1, first: 1 }));
  D("Error · Couldn't open (unsupported)", H("library", {}, "error", { kind: "unsupported" }));
  D("Error · Damaged file", H("library", {}, "error", { kind: "corrupt" }));
  D("Error · Storage almost full", H("home", {}, "error", { kind: "storage" }));
  D("Battery · Low (15%)", H("reader", { id: "animal-farm" }, "battery", { state: "low" }));
  D("Battery · Critical (4%)", H("reader", { id: "animal-farm" }, "battery", { state: "critical" }));
  D("Battery · Charging screen", H("home", {}, "battery", { state: "charging", pct: 64 }));
  D("Battery · Fully charged", H("home", {}, "battery", { state: "full" }));
  D("USB · Cable connected (ask)", H("home", {}, "usb", { phase: "ask" }));
  D("USB · Connected to computer", H("home", {}, "usb", { phase: "connected" }));
  D("USB · Adding new books", H("home", {}, "usb", { phase: "importing", pct: 58 }));
  D("USB · New books added", H("library", {}, "usb", { phase: "done" }));
  D("Welcome · 0 Intro", H("welcome", { step: 0 }));
  D("Welcome · 1 Theme", H("welcome", { step: 1 }));
  D("Welcome · 2 Reading defaults", H("welcome", { step: 2 }));
  D("Welcome · 3 Gestures", H("welcome", { step: 3 }));
  D("Welcome · 4 Library folder", H("welcome", { step: 4 }));
  D("Welcome · 5 Done", H("welcome", { step: 5 }));
  D("Update · Check", H("settings", {}, "update", { state: "idle" }));
  D("Update · Checking", H("settings", {}, "update", { state: "checking" }));
  D("Update · Up to date", H("settings", {}, "update", { state: "uptodate" }));
  D("Update · Available v2026.08", H("settings", {}, "update", { state: "available" }));
  D("Update · Downloading", H("settings", {}, "update", { state: "downloading", pct: 45 }));
  D("Update · Restart to install", H("settings", {}, "update", { state: "ready" }));
  D("Update · Installing", H("settings", {}, "update", { state: "installing", pct: 40 }));
  D("Tap zones · Tap", H("tapzones", { tab: "tap" }));
  D("Tap zones · Tap, top-left corner", H("tapzones", { tab: "tap", zone: "tl" }));
  D("Tap zones · Double tap", H("tapzones", { tab: "tap", mode: "double", zone: "right" }));
  D("Tap zones · Hold", H("tapzones", { tab: "hold" }));
  D("Tap zones · Swipe", H("tapzones", { tab: "swipe" }));
  D("Tap zones · Multi-swipe", H("tapzones", { tab: "multi" }));
  D("Tap zones · Action picker", H("tapzones", { tab: "tap", zone: "tl" }, "tz-pick", { key: "tz:tap.single.tl", name: "Top left corner · Single tap", def: "Toggle page flipping" }));
  D("Dictionaries · Installed", H("dict-manager"));
  D("Dictionaries · Arabic books order", H("dict-manager", { profile: "ar" }));
  D("Dictionaries · Catalog", H("dict-manager", { tab: "catalog" }));
  D("Dictionaries · Downloading EN → AR", H("dict-manager", { tab: "catalog", dl: "wikt-en-ar", pct: 46 }));
  D("Dictionaries · English", H("dict-manager", { tab: "catalog", lang: "English" }));
  D("Lock screen · Clock & message", H("settings", {}, "lockscreen"));
  D("Lock screen · Preview", H("home", {}, "lockscreen", { preview: 1 }));
  D("Lock screen · Preview, charging", H("home", {}, "lockscreen", { preview: 1, charging: 1 }));
})();
