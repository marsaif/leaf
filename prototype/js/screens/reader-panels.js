/* ==========================================================================
   Leaf — Reader panels (owned by the Reader agent)
   Overlays: reader-more, toc, bookmarks, annotations, annotations-export, goto, skim,
             bookmap, pagebrowser, hl-popup, hl-note, hyphenate, qr, view-html,
             dict, translate, wiki, book-end
   Depends on window.RD from reader.js.
   ========================================================================== */
(function () {
  const E = App.esc, I = App.icon, RD = window.RD, clamp = RD.clamp;
  const cur = () => RD.cur();
  const L_ = (id) => RD.layout(id || cur().id);
  const P = (o) => App.attrs(o);

  /* ------------------------------------------------------------ helpers */
  const snippet = (L, pi, n = 16) => {
    const p = L.pages[pi]; const blocks = RD.blocks(L.id, p.ch, L.inline);
    const words = []; for (const it of p.items) { if (it.head) continue; words.push(...blocks[it.bi].w.slice(it.a, it.b)); if (words.length > n) break; }
    return words.slice(0, n).join(" ") + "…";
  };
  const pageOfHl = (L, h) => RD.pageOf(L, { ch: h.ch, pid: h.pid, a: h.a });
  const STYLE_NAMES = { lighten: "Highlight", underscore: "Underline", strikeout: "Strikeout", invert: "Invert" };
  const COLORS = ["yellow", "green", "blue", "red", "purple", "gray"];
  const isAr = (id) => RD.isAr(RD.book(id));

  /** scroll the overlay's list so the current item is centred (never scrollIntoView: it would scroll the device) */
  RD.center = (el, sel) => {
    if (App.state.stack.length && RD._centered === App.top()) return; RD._centered = App.top();
    const h = el.querySelector(sel), sc = h && h.closest(".ko-scroll"); if (!sc) return;
    const r = h.getBoundingClientRect(), q = sc.getBoundingClientRect(); sc.scrollTop = Math.max(0, r.top - q.top + sc.scrollTop - sc.clientHeight / 2 + r.height / 2);
  };

  /* ----------------------------------------------------------- more menu */
  App.overlay("reader-more", {
    layer: "popover", clear: true,
    render() {
      const { id } = cur(), b = RD.book(id);
      const row = (ic, label, attrs, sub) => `<button class="ko-row" ${attrs}>${I(ic)}<span class="label">${label}${sub ? `<span class="sub">${sub}</span>` : ""}</span></button>`;
      return `<div class="ko-popover rd-more">
        ${row("bookmark", "Bookmarks", `data-action="rdSwapAll" data-o="bookmarks"`)}
        ${row("hash", "Go to page", `data-action="rdSwapAll" data-o="goto"`)}
        ${row("gallery-horizontal", "Skim document", `data-action="rdSwapAll" data-o="skim"`)}
        ${row("map", "Book map", `data-action="rdSwapAll" data-o="bookmap"`)}
        ${row("layout-grid", "Page browser", `data-action="rdSwapAll" data-o="pagebrowser"`)}
        ${RD.bilingual(b) ? row("languages", "Translate paragraph", `data-action="rdSwapAll" data-o="translate"`, "English → العربية") : ""}
        <div class="ko-divider"></div>
        ${row("info", "Book information", `data-action="rdSwapAll" data-o="book-details"`)}
        ${row("chart-column", "Reading statistics", `data-go="stats"`)}
        ${row("flag", "End of book screen", `data-action="rdSwapAll" data-o="book-end"`)}
      </div>`;
    },
  });
  App.action("rdSwapAll", (el) => { const { id } = cur(); App.closeAll(); App.open(el.dataset.o, { id }); });

  /* ------------------------------------------------ navigator: toc / bm / notes */
  function navShell(active, body, opts = {}) {
    const { id, page } = cur(), b = RD.book(id), L = L_(id);
    const nb = RD.bms(id).length, nh = RD.hls(id).length;
    const pct = L ? Math.round((page / L.total) * 100) : b.progress;
    const tabs = [["toc", "Contents"], ["bookmarks", `Bookmarks<span class="n">${nb}</span>`], ["annotations", `Notes<span class="n">${nh}</span>`]];
    return `<div class="ko-sheet rd-nav">
      <div class="grip"></div>
      <div class="ko-sheet-head rd-nav-head">
        <div class="cv">${Cover.html(b)}</div>
        <div class="grow"><div class="title ellipsis">${E(RD.short(b))}</div><div class="sub ellipsis">${E(b.author.split(";")[0])}</div>
          <div class="pr">${App.progress(pct, "ko-progress--thin")}<span class="num">${pct}% · page ${page} of ${L ? L.total : "–"}</span></div></div>
        ${opts.action || ""}
        <button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button>
      </div>
      <div class="ko-tabs rd-nav-tabs">${tabs.map(([k, l]) => `<button class="ko-tab ${k === active ? "on" : ""}" data-action="navTab" data-v="${k}">${l}</button>`).join("")}</div>
      ${opts.sub || ""}
      <div class="ko-scroll rd-nav-body">${body}</div>
      ${opts.foot || ""}
    </div>`;
  }
  App.action("navTab", (el) => RD.quiet(() => App.replaceTop(el.dataset.v, { id: cur().id })));

  RD.tocOpen = RD.tocOpen || null;
  App.overlay("toc", {
    layer: "sheet",
    render() {
      const { id, page } = cur(), L = L_(id); if (!L) return "";
      const chs = RD.chapters(id), here = L.pages[page - 1].ch, ar = isAr(id);
      const open = RD.tocOpen || new Set([here]);
      const chEnd = (i) => (i + 1 < L.chStart.length ? L.chStart[i + 1] : L.total);
      const row = (c, i) => {
        const start = L.chStart[i] + 1, end = chEnd(i), read = end <= page - 1, isHere = i === here;
        const prog = isHere ? Math.round(((page - start + 1) / (end - start + 1)) * 100) : 0;
        const subs = c.sections.length && open.has(i) ? c.sections.map((s) => { const pg = start + Math.round(s.frac * (end - start)); return `<button class="rd-toc-row sub ${pg <= page && isHere ? "past" : ""}" data-action="tocGo" data-p="${pg}"><span class="ttl">${E(s.title)}</span><span class="pg num">${pg}</span></button>`; }).join("") : "";
        return `<div class="rd-toc-ch ${isHere ? "here" : ""} ${read ? "read" : ""}">
          <div class="rd-toc-row">
            ${c.sections.length ? `<button class="exp" data-action="tocExp" data-i="${i}" aria-label="Expand">${I(open.has(i) ? "chevron-down" : "chevron-right", "sm")}</button>` : `<span class="exp">${read ? I("check", "sm") : ""}</span>`}
            <button class="main" data-action="tocGo" data-p="${start}" ${ar ? 'dir="rtl"' : ""}>
              <span class="lbl">${E(c.label)}</span><span class="ttl">${E(c.title)}</span>
              ${isHere ? `<span class="here-tag">${App.progress(prog, "ko-progress--thin")}<em>Reading · ${prog}%</em></span>` : ""}
            </button>
            <span class="pg num">${start}</span>
          </div>${subs}</div>`;
      };
      const parts = RD.parts(id);
      const body = parts.length
        ? parts.map((pt) => `<div class="rd-toc-part"><span>${E(pt.title)}</span><span class="num">${L.chStart[pt.from] + 1}</span></div>${chs.slice(pt.from, pt.to + 1).map((c, j) => row(c, pt.from + j)).join("")}`).join("")
        : chs.map(row).join("");
      return navShell("toc", `<div class="rd-toc">${body}</div>`, {
        foot: `<div class="rd-nav-foot">${chs.some((c) => c.sections.length) ? "" : "<!--"}<button class="ko-btn ko-btn--ghost" data-action="tocExpAll">${I("list-tree", "sm")}${RD.tocOpen && RD.tocOpen.size > 1 ? "Collapse all" : "Expand all"}</button>${chs.some((c) => c.sections.length) ? "" : "-->"}<span class="grow"></span><button class="ko-btn" data-action="rdSwapAll" data-o="goto">${I("hash", "sm")}Go to page</button></div>`,
      });
    },
    mount(el) { RD.center(el, ".rd-toc-ch.here"); },
  });
  App.action("tocGo", (el) => { const { id } = cur(); RD.goPage(id, +el.dataset.p); });
  App.action("tocExp", (el) => { const { id, page } = cur(); const L = L_(id); const s = new Set(RD.tocOpen || [L.pages[page - 1].ch]); const i = +el.dataset.i; s.has(i) ? s.delete(i) : s.add(i); RD.tocOpen = s; RD.quiet(() => App.renderLayers(true)); });
  App.action("tocExpAll", () => { const { id } = cur(); RD.tocOpen = RD.tocOpen && RD.tocOpen.size > 1 ? new Set() : new Set(RD.chapters(id).map((_, i) => i)); RD.quiet(() => App.renderLayers(true)); });

  App.overlay("bookmarks", {
    layer: "sheet",
    render() {
      const { id, page } = cur(), L = L_(id); if (!L) return "";
      const bms = RD.bms(id).map((m, i) => ({ ...m, i, pg: RD.pageOf(L, m) + 1 })).sort((a, b) => a.pg - b.pg);
      const here = bms.some((m) => m.pg === page);
      const body = bms.length ? `<div class="rd-bms">${bms.map((m) => `<div class="rd-bm ${m.pg === page ? "here" : ""}">
          <button class="main" data-action="tocGo" data-p="${m.pg}">
            <span class="rib">${I("bookmark", "sm")}</span>
            <span class="txt"><span class="meta"><b>Page ${m.pg}</b> · ${E(RD.chapters(id)[m.ch].label)} · ${E(m.date)}</span>
            <span class="snip" ${isAr(id) ? 'dir="rtl"' : ""}>${E(snippet(L, m.pg - 1))}</span>
            ${m.note ? `<span class="note">${I("pen-line", "sm")}${E(m.note)}</span>` : ""}</span>
          </button>
          <button class="ko-icon-btn" data-action="bmDel" data-i="${m.i}" aria-label="Remove bookmark">${I("trash-2", "sm")}</button></div>`).join("")}</div>`
        : `<div class="ko-empty">${I("bookmark")}<div>No bookmarks yet</div><div class="faint">Tap the top-right corner of a page to bookmark it.</div></div>`;
      return navShell("bookmarks", body, {
        foot: `<div class="rd-nav-foot"><span class="faint">${bms.length} bookmark${bms.length === 1 ? "" : "s"}</span><span class="grow"></span><button class="ko-btn ${here ? "" : "ko-btn--primary"}" data-action="rdBookmark">${I(here ? "bookmark-minus" : "bookmark-plus", "sm")}${here ? "Remove this page" : "Bookmark this page"}</button></div>`,
      });
    },
  });
  App.action("bmDel", (el) => { const { id } = cur(); const v = RD.bms(id).filter((_, i) => i !== +el.dataset.i); RD.saveBms(id, v); RD.quietRefresh(); App.toast("Bookmark removed"); });

  RD.annFilter = "all"; RD.annSort = "page";
  App.overlay("annotations", {
    layer: "sheet",
    render() {
      const { id } = cur(), L = L_(id); if (!L) return "";
      const all = RD.hls(id).map((h) => ({ ...h, pg: pageOfHl(L, h) + 1, text: RD.hlText(id, h) }));
      const f = RD.annFilter;
      const list = all.filter((h) => f === "all" || (f === "notes" ? h.note : f === "hl" ? !h.note : h.style === f)).sort((a, b) => (RD.annSort === "page" ? a.pg - b.pg : b.date.localeCompare(a.date)));
      const chips = [["all", `All ${all.length}`], ["notes", `With notes ${all.filter((h) => h.note).length}`], ["lighten", "Highlight"], ["underscore", "Underline"], ["strikeout", "Strikeout"], ["invert", "Invert"]];
      const sub = `<div class="rd-ann-bar"><div class="chips">${chips.map(([k, l]) => `<button class="ko-chip ${f === k ? "on" : ""}" data-action="annFilter" data-v="${k}">${l}</button>`).join("")}</div></div>`;
      const foot = `<div class="rd-nav-foot"><span class="faint">${list.length} of ${all.length} · sorted by</span><div class="ko-seg"><button class="${RD.annSort === "page" ? "on" : ""}" data-action="annSort" data-v="page">Page</button><button class="${RD.annSort === "date" ? "on" : ""}" data-action="annSort" data-v="date">Date</button></div><span class="grow"></span><button class="ko-btn" data-action="annExport">${I("share", "sm")}Export</button></div>`;
      const body = list.length ? `<div class="rd-anns">${list.map((h) => `<button class="rd-ann" data-action="annOpen" data-hid="${h.hid}" data-p="${h.pg}">
          <span class="sw s-${h.style} c-${h.color}"></span>
          <span class="txt"><span class="q ${isAr(id) ? "ar" : ""}"><mark class="hl s-${h.style} c-${h.color}">${E(h.text)}</mark></span>
          ${h.note ? `<span class="note">${I("pen-line", "sm")}<span>${E(h.note)}</span></span>` : ""}
          <span class="meta">${E(RD.chapters(id)[h.ch].label)} · p. ${h.pg} · ${STYLE_NAMES[h.style]} · ${E(h.date)}</span></span></button>`).join("")}</div>`
        : `<div class="ko-empty">${I("highlighter")}<div>Nothing here yet</div><div class="faint">Long-press a word, then drag to select text.</div></div>`;
      return navShell("annotations", body, { sub, foot });
    },
  });
  App.action("annFilter", (el) => { RD.annFilter = el.dataset.v; RD.quiet(() => App.renderLayers(true)); });
  App.action("annSort", (el) => { RD.annSort = el.dataset.v; RD.quiet(() => App.renderLayers(true)); });
  App.action("annOpen", (el) => { const { id } = cur(); RD.goPage(id, +el.dataset.p); App.open("hl-popup", { id, hid: el.dataset.hid }); });
  App.action("annExport", () => App.open("annotations-export", { id: cur().id }));

  RD.exportFmt = "md";
  App.overlay("annotations-export", {
    layer: "sheet",
    render(p) {
      const id = p.id || cur().id, n = RD.hls(id).length, all = !!RD.exportAll;
      const fmts = [["md", "Markdown", "file-text", "Headings per chapter, notes as quotes"], ["html", "HTML", "file-code", "Printable page with styles"], ["json", "JSON", "braces", "For scripts and other apps"], ["txt", "Plain text", "file-type", "Simple and universal"], ["clip", "My Clippings", "scissors", "Kindle-compatible clippings file"]];
      const svc = [["readwise", "Readwise", "book-marked"], ["joplin", "Joplin", "notebook"], ["nextcloud", "Nextcloud Notes", "cloud"], ["memos", "Memos", "sticky-note"], ["flomo", "Flomo", "feather"], ["xmnote", "XMNote", "notebook-pen"]];
      return `<div class="ko-sheet rd-exp"><div class="grip"></div>
        <div class="ko-sheet-head"><span class="title">Export highlights</span><button class="ko-icon-btn" data-close>${I("x")}</button></div>
        <div class="ko-scroll" style="padding:0 var(--sp-5) var(--sp-3)">
          <div class="ko-seg rd-exp-scope"><button class="${all ? "" : "on"}" data-action="expScope" data-v="0">This book · ${n}</button><button class="${all ? "on" : ""}" data-action="expScope" data-v="1">All books · 214</button></div>
          <div class="rd-ts-sep">Save as file</div>
          ${fmts.map(([k, l, ic, s]) => `<button class="rd-radio-row rd-exp-row" data-action="expFmt" data-v="${k}">${I(ic)}<span class="grow"><b>${l}</b><small>${s}</small></span>${App.radio(RD.exportFmt === k)}</button>`).join("")}
          <div class="rd-ts-sep">Send to a service</div>
          <div class="rd-exp-svc">${svc.map(([k, l, ic]) => `<button class="ko-card ko-card--sm ko-card--tap ${RD.exportFmt === k ? "on" : ""}" data-action="expFmt" data-v="${k}">${I(ic)}<span>${l}</span></button>`).join("")}</div>
        </div>
        <div class="rd-sheet-foot"><button class="ko-btn ko-btn--ghost" data-close>Cancel</button><button class="ko-btn ko-btn--primary" data-action="expGo">${I("upload", "sm")}Export ${all ? 214 : n} highlights</button></div>
      </div>`;
    },
  });
  App.action("expScope", (el) => { RD.exportAll = el.dataset.v === "1"; RD.quiet(() => App.renderLayers(true)); });
  App.action("expFmt", (el) => { RD.exportFmt = el.dataset.v; RD.quiet(() => App.renderLayers(true)); });
  App.action("expGo", () => { App.close(); App.toast("Exported to koreader/clipboard/"); });

  /* ---------------------------------------------------------------- goto */
  RD.gotoVal = ""; RD.gotoMode = "page";
  App.overlay("goto", {
    layer: "sheet",
    render() {
      const { id, page } = cur(), L = L_(id); if (!L) return "";
      const v = RD.gotoVal, mode = RD.gotoMode;
      let target = null;
      if (v !== "") target = mode === "page" ? clamp(Math.round(+v), 1, L.total) : clamp(Math.round((+v / 100) * L.total), 1, L.total);
      const valid = v !== "" && !isNaN(+v) && (mode === "page" ? +v >= 1 && +v <= L.total : +v >= 0 && +v <= 100);
      const inf = target ? RD.pageInfo(L, target - 1) : null;
      const keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", mode === "pct" ? "." : "", "0", "⌫"];
      const kb = typeof App.keyboardHTML === "function" && false ? App.keyboardHTML({ numeric: true }) : `<div class="rd-keypad">${keys.map((k) => (k ? `<button data-action="gotoKey" data-k="${k}" class="${k === "⌫" ? "fn" : ""}">${k === "⌫" ? I("delete") : k}</button>` : "<span></span>")).join("")}</div>`;
      return `<div class="ko-sheet rd-goto"><div class="grip"></div>
        <div class="ko-sheet-head"><span class="title">Go to</span>
          <div class="ko-seg"><button class="${mode === "page" ? "on" : ""}" data-action="gotoMode" data-v="page">Page</button><button class="${mode === "pct" ? "on" : ""}" data-action="gotoMode" data-v="pct">Percent</button></div>
          <button class="ko-icon-btn" data-close>${I("x")}</button></div>
        <div class="rd-goto-body">
          <div class="rd-goto-field ${v === "" ? "empty" : ""} ${v !== "" && !valid ? "bad" : ""}">
            <span class="val num">${v === "" ? (mode === "page" ? page : Math.round((page / L.total) * 100)) : E(v)}</span><span class="caret"></span><span class="unit">${mode === "page" ? `of ${L.total}` : "%"}</span>
          </div>
          <div class="rd-goto-hint">${v === "" ? `You are on page ${page} · ${E(RD.pageInfo(L, page - 1).chapter.label)}` : valid ? `${I("corner-down-right", "sm")}Page ${target} · ${E(inf.chapter.label)} · ${E(inf.chapter.title)}` : `Enter ${mode === "page" ? `a page between 1 and ${L.total}` : "a value between 0 and 100"}`}</div>
          ${kb}
        </div>
        <div class="rd-sheet-foot"><button class="ko-btn ko-btn--ghost" data-action="rdSwapAll" data-o="skim">${I("gallery-horizontal", "sm")}Skim</button><span class="grow"></span><button class="ko-btn ko-btn--ghost" data-close>Cancel</button><button class="ko-btn ko-btn--primary" data-action="gotoGo" ${valid ? "" : "disabled"}>Go</button></div>
      </div>`;
    },
  });
  App.action("gotoMode", (el) => { RD.gotoMode = el.dataset.v; RD.gotoVal = ""; RD.quiet(() => App.renderLayers(true)); });
  App.action("gotoKey", (el) => { const k = el.dataset.k; RD.gotoVal = k === "⌫" ? RD.gotoVal.slice(0, -1) : (RD.gotoVal + k).slice(0, 5); RD.quiet(() => App.renderLayers(true)); });
  App.action("gotoGo", () => { const { id } = cur(), L = L_(id), v = +RD.gotoVal; const t = RD.gotoMode === "page" ? v : Math.max(1, Math.round((v / 100) * L.total)); RD.gotoVal = ""; RD.goPage(id, t); });

  /* ---------------------------------------------------------------- skim */
  App.overlay("skim", {
    layer: "sheet", clear: true,
    render(p) {
      const { id, page } = cur(), L = L_(id); if (!L) return "";
      const from = +p.from || page, inf = RD.pageInfo(L, page - 1);
      const ticks = L.chStart.slice(1).map((s) => `<i style="left:${(s / Math.max(1, L.total - 1)) * 100}%"></i>`).join("");
      const bmp = RD.bms(id).map((m) => RD.pageOf(L, m));
      const bmTicks = bmp.map((pi) => `<b style="left:${(pi / Math.max(1, L.total - 1)) * 100}%"></b>`).join("");
      const btn = (ic, l, a, d) => `<button class="rd-skim-btn" data-action="${a}" data-d="${d}">${I(ic)}<span>${l}</span></button>`;
      return `<div class="ko-sheet rd-skim"><div class="grip"></div>
        <div class="ko-sheet-head rd-skim-head"><div class="grow"><div class="title t num">Page ${page} <span class="faint">of ${L.total}</span></div><div class="sub ellipsis">${E(inf.chapter.label)} · ${E(inf.chapter.title)}</div></div>
          ${from !== page ? `<button class="ko-chip rd-pill" data-action="skimGo" data-p="${from}">${I("undo-2", "sm")}Back to ${from}</button>` : ""}
          <button class="ko-icon-btn ${RD.isBookmarked(L, page - 1) ? "active" : ""}" data-action="skimBm" aria-label="Bookmark">${I(RD.isBookmarked(L, page - 1) ? "bookmark-check" : "bookmark")}</button>
          <button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button></div>
        <div class="rd-skim-track"><div class="rd-scrub-ticks">${ticks}</div><div class="rd-skim-bms">${bmTicks}</div>${App.slider(((page - 1) / Math.max(1, L.total - 1)) * 100, `data-slide="skimSlide" data-from="${from}"`)}</div>
        <div class="rd-skim-row">
          ${btn("skip-back", "Chapter", "skimCh", -1)}${btn("chevrons-left", "−10", "skimBy", -10)}${btn("chevron-left", "−1", "skimBy", -1)}
          ${btn("chevron-right", "+1", "skimBy", 1)}${btn("chevrons-right", "+10", "skimBy", 10)}${btn("skip-forward", "Chapter", "skimCh", 1)}
        </div>
        <div class="rd-skim-row two">
          ${btn("bookmark", "Previous bookmark", "skimBmGo", -1)}${btn("bookmark", "Next bookmark", "skimBmGo", 1)}
        </div>
      </div>`;
    },
  });
  const skimTo = (pg) => { const { id, page } = cur(); const from = (App.top() && App.top().params.from) || page; RD.quiet(() => { RD.goPage(id, pg); App.open("skim", { id, from }); }); };
  App.action("skimGo", (el) => skimTo(+el.dataset.p));
  App.action("skimBy", (el) => skimTo(cur().page + +el.dataset.d));
  App.action("skimCh", (el) => { const { id, page } = cur(), L = L_(id), ch = L.pages[page - 1].ch, d = +el.dataset.d; let t = d > 0 ? ch + 1 : page - 1 > L.chStart[ch] ? ch : ch - 1; t = clamp(t, 0, L.chStart.length - 1); skimTo(L.chStart[t] + 1); });
  App.action("skimBmGo", (el) => { const { id, page } = cur(), L = L_(id), d = +el.dataset.d; const ps = RD.bms(id).map((m) => RD.pageOf(L, m) + 1).sort((a, b) => a - b); const t = d > 0 ? ps.find((x) => x > page) : ps.reverse().find((x) => x < page); if (t) skimTo(t); else App.toast("No more bookmarks"); });
  App.action("skimBm", () => { const from = App.top().params.from; App.actions.rdBookmark(); RD.quiet(() => App.replaceTop("skim", { id: cur().id, from })); });
  App.action("skimSlide", (el, v, done) => { const { id } = cur(), L = L_(id); const pg = Math.round(v * (L.total - 1)) + 1; const t = document.querySelector(".rd-skim-head .t"); if (t) t.innerHTML = `Page ${pg} <span class="faint">of ${L.total}</span>`; if (done) skimTo(pg); });

  /* ------------------------------------------------------------- book map */
  App.overlay("bookmap", {
    layer: "page",
    render() {
      const { id, page } = cur(), L = L_(id), b = RD.book(id); if (!L) return "";
      const bmp = new Set(RD.bms(id).map((m) => RD.pageOf(L, m)));
      const hlp = {}; RD.hls(id).forEach((h) => { const pi = pageOfHl(L, h); hlp[pi] = (hlp[pi] || 0) + 1; });
      const chs = RD.chapters(id);
      const rows = chs.map((c, i) => {
        const s = L.chStart[i], e = i + 1 < L.chStart.length ? L.chStart[i + 1] : L.total;
        const cells = []; for (let pi = s; pi < e; pi++) cells.push(`<button class="cell ${pi < page - 1 ? "read" : ""} ${pi === page - 1 ? "here" : ""}" data-action="tocGo" data-p="${pi + 1}" title="Page ${pi + 1}">${bmp.has(pi) ? '<i class="bm"></i>' : ""}${hlp[pi] ? '<i class="hl"></i>' : ""}</button>`);
        const done = Math.round((clamp(page - 1 - s, 0, e - s) / (e - s)) * 100);
        return `<div class="rd-map-ch ${page - 1 >= s && page - 1 < e ? "here" : ""}"><div class="hd" ${isAr(id) ? 'dir="rtl"' : ""}><span class="lbl">${E(c.label)}</span><span class="ttl ellipsis">${E(c.title)}</span><span class="pg num">${s + 1}–${e}${done && done < 100 ? ` · ${done}%` : done === 100 ? " · read" : ""}</span></div><div class="cells">${cells.join("")}</div></div>`;
      }).join("");
      const read = Math.round(((page - 1) / L.total) * 100);
      return `<div class="ko-page rd-map">
        ${App.statusBar()}
        <div class="ko-header"><button class="ko-icon-btn back" data-close>${I("arrow-left")}</button><span class="title">Book map</span><span class="spacer"></span>
          <button class="ko-icon-btn" data-action="rdSwapAll" data-o="pagebrowser" aria-label="Page browser">${I("layout-grid")}</button></div>
        <div class="rd-map-sum"><div><b class="num">${L.total}</b><span>pages</span></div><div><b class="num">${read}%</b><span>read</span></div><div><b class="num">${bmp.size}</b><span>bookmarks</span></div><div><b class="num">${RD.hls(id).length}</b><span>highlights</span></div></div>
        <div class="rd-map-legend"><span><i class="cell read"></i>Read</span><span><i class="cell"></i>Unread</span><span><i class="cell here"></i>Current</span><span><i class="cell"><i class="bm"></i></i>Bookmark</span><span><i class="cell"><i class="hl"></i></i>Highlight</span></div>
        <div class="ko-scroll rd-map-body">${rows}</div>
      </div>`;
    },
    mount(el) { RD.center(el, ".rd-map-ch.here"); },
  });

  /* --------------------------------------------------------- page browser */
  App.overlay("pagebrowser", {
    layer: "page",
    render(p) {
      const { id, page } = cur(), L = L_(id), b = RD.book(id); if (!L) return "";
      const { w, h } = RD.screenSize();
      const cols = +(p.cols || RD.pbCols || (w > h ? 5 : 3));
      const c = RD.cfg(id), scan = L.scan;
      const tw = (Math.min(w, 1000) - 40 - (cols - 1) * 14) / cols, s = tw / w, th = scan ? tw * (RD.SCAN.h / RD.SCAN.w) : (h - 64) * s;
      const rows = Math.max(1, Math.floor((h - 190) / (th + 44))), per = cols * rows;
      const start = p.start != null ? clamp(+p.start, 0, Math.max(0, L.total - 1)) : Math.floor((page - 1) / per) * per;
      const bmp = new Set(RD.bms(id).map((m) => RD.pageOf(L, m)));
      const style = RD.style(b, c);
      const thumbs = [];
      for (let pi = start; pi < Math.min(L.total, start + per); pi++) {
        const inner = scan
          ? `<div class="rd-thumb-scan" style="transform:scale(${(tw / RD.SCAN.w).toFixed(4)})">${RD.scanHTML(L, pi, { thumb: true })}</div>`
          : `<div class="rd-thumb-page rd-screen ${isAr(id) ? "is-ar" : ""} ${RD.twoCols(c) ? "two" : ""}" style="${style};width:${w}px;height:${h - 64}px;transform:scale(${s.toFixed(4)})"><div class="rd-body"><div class="rd-text" ${isAr(id) ? 'dir="rtl"' : ""}>${RD.pageHTML(L, pi, { thumb: true })}</div></div></div>`;
        thumbs.push(`<button class="rd-thumb ${pi === page - 1 ? "here" : ""}" data-action="tocGo" data-p="${pi + 1}"><span class="pv" style="height:${th.toFixed(0)}px">${inner}${bmp.has(pi) ? '<i class="bm"></i>' : ""}</span><span class="cap num">${pi + 1}${L.pages[pi].k === 0 ? `<em>${E(RD.chapters(id)[L.pages[pi].ch].label)}</em>` : ""}</span></button>`);
      }
      const strip = RD.chapters(id).map((ch, i) => { const s0 = L.chStart[i], e = i + 1 < L.chStart.length ? L.chStart[i + 1] : L.total; return `<button style="flex:${e - s0}" class="${start < e && start + per > s0 ? "on" : ""}" data-action="pbStart" data-v="${s0}" title="${E(ch.label)}"><span>${E(ch.num)}</span></button>`; }).join("");
      return `<div class="ko-page rd-pb">
        ${App.statusBar()}
        <div class="ko-header"><button class="ko-icon-btn back" data-close>${I("arrow-left")}</button><span class="title">Pages</span><span class="count num">${start + 1}–${Math.min(L.total, start + per)} of ${L.total}</span><span class="spacer"></span>
          <div class="ko-seg">${[2, 3, 4].concat(w > h ? [5] : []).map((n) => `<button class="${cols === n ? "on" : ""}" data-action="pbCols" data-v="${n}">${n}</button>`).join("")}</div></div>
        <div class="ko-scroll"><div class="rd-pb-grid" style="--cols:${cols}">${thumbs.join("")}</div></div>
        <div class="rd-pb-strip">${strip}</div>
        <div class="ko-pager"><span class="num">Page ${page} · ${E(RD.pageInfo(L, page - 1).chapter.label)}</span><span class="row">
          <button class="ko-icon-btn" data-action="pbStart" data-v="${start - per}" ${start <= 0 ? "disabled" : ""}>${I("chevron-left")}</button>
          <button class="ko-icon-btn" data-action="pbStart" data-v="${start + per}" ${start + per >= L.total ? "disabled" : ""}>${I("chevron-right")}</button></span></div>
      </div>`;
    },
  });
  App.action("pbStart", (el) => { const t = App.top(); RD.quiet(() => App.replaceTop("pagebrowser", { ...t.params, start: Math.max(0, +el.dataset.v) })); });
  App.action("pbCols", (el) => { RD.pbCols = +el.dataset.v; const t = App.top(); RD.quiet(() => App.replaceTop("pagebrowser", { ...t.params, cols: +el.dataset.v, start: undefined })); });

  /* ----------------------------------------------------- selection popup */
  const HL_ICONS = { "01_select": "text-select", "02_highlight": "highlighter", "03_copy": "copy", "04_add_note": "notebook-pen", "05_wikipedia": "globe", "06_dictionary": "book-a", "07_translate": "languages",
    "09_view_html": "code-xml", "10_user_dict": "scissors", "11_follow_link": "link", "12_search": "search", "12_generate_qr_code": "qr-code" };
  const PRIMARY = ["02_highlight", "04_add_note", "06_dictionary", "07_translate"];
  function selOf(p) {
    const id = p.id || cur().id, L = L_(id);
    if (p.hid) { const h = RD.hls(id).find((x) => x.hid === p.hid); return h ? { ...h, id } : null; }
    const s = p.pid != null && p.a != null ? { ch: +p.ch, pid: isNaN(+p.pid) ? p.pid : +p.pid, a: +p.a, b: +p.b } : L ? RD.demoSel(L, cur().page - 1, p.demo === "word" ? "word" : "range") : null;
    return s ? { ...s, id } : null;
  }
  RD.selText = (s) => { const blk = RD.para(s.id, s.ch, s.pid) || RD.blocks(s.id, s.ch, false).find((x) => x.pid === s.pid); return blk ? blk.w.slice(s.a, s.b).join(" ").replace(/^[“"]|[,;:.”"]+$/g, "") : ""; };
  const cleanWord = (w) => String(w || "").replace(/[^\p{L}'-]/gu, "");
  RD.hlPick = RD.hlPick || { style: "lighten", color: "yellow" };

  App.overlay("hl-popup", {
    layer: "popover", clear: true,
    render(p) {
      const s = selOf(p); if (!s) return "";
      const id = s.id, b = RD.book(id), existing = !!p.hid;
      const text = existing ? RD.hlText(id, s) : RD.selText(s);
      const words = text.split(/\s+/).length;
      const menu = (RD.isPdf(b) ? KO_MENUS.reader_highlight_pdf : KO_MENUS.reader_highlight) || [];
      const items = [...menu].sort((a, b2) => a.key.localeCompare(b2.key));
      const style = existing ? s.style : RD.hlPick.style, color = existing ? s.color : RD.hlPick.color;
      const prim = items.filter((x) => PRIMARY.includes(x.key));
      const rest = items.filter((x) => !PRIMARY.includes(x.key));
      const label = (x) => (existing && x.key === "02_highlight" ? "Delete" : existing && x.key === "04_add_note" ? (s.note ? "Edit note" : "Add note") : x.text);
      const icon = (x) => (existing && x.key === "02_highlight" ? "trash-2" : HL_ICONS[x.key] || "circle");
      const sp = existing ? P({ id, hid: p.hid }) : P({ id, ch: s.ch, pid: s.pid, a: s.a, b: s.b });
      const short = { "12_generate_qr_code": "QR code", "10_user_dict": "Hyphenate", "11_follow_link": "Follow link", "09_view_html": "View HTML" };
      const colorOn = style === "lighten" || style === "underscore";
      return `<div class="ko-popover rd-hl ${existing ? "existing" : ""}" data-sel='${sp}'>
        <div class="rd-hl-top">
          <span class="q ${isAr(id) ? "ar" : ""}">${E(text)}</span>
          <span class="meta">${existing ? `${E(RD.chapters(id)[s.ch].label)} · ${E(s.date)}` : `${words} word${words > 1 ? "s" : ""}`}</span>
        </div>
        ${existing && s.note ? `<div class="rd-hl-note">${I("pen-line", "sm")}<span>${E(s.note)}</span></div>` : ""}
        <div class="rd-hl-styles">
          <div class="ko-seg rd-hl-seg">${Object.keys(STYLE_NAMES).map((k) => `<button class="${style === k ? "on" : ""}" data-action="hlStyle" data-v="${k}"><span class="smp s-${k}">Ab</span>${STYLE_NAMES[k]}</button>`).join("")}</div>
          <div class="rd-hl-colors ${colorOn ? "" : "off"}">${COLORS.map((c) => `<button class="ko-chip rd-cchip ${color === c ? "on" : ""}" data-action="hlColor" data-v="${c}"><i class="rd-cdot c-${c}"></i>${c[0].toUpperCase() + c.slice(1)}</button>`).join("")}</div>
        </div>
        <div class="rd-hl-main">${prim.map((x) => `<button class="${existing && x.key === "02_highlight" ? "danger" : ""}" data-action="hlAct" data-k="${x.key}">${I(icon(x))}<span>${E(label(x))}</span></button>`).join("")}</div>
        <div class="rd-hl-more">${rest.map((x) => `<button data-action="hlAct" data-k="${x.key}" data-tip="${E(short[x.key] || x.text)}" aria-label="${E(short[x.key] || x.text)}">${I(icon(x))}</button>`).join("")}</div>
      </div>`;
    },
    mount(el, p) {
      const pop = el.querySelector(".rd-hl"); if (!pop) return;
      const scr = document.querySelector(".ko-screen").getBoundingClientRect();
      const marks = p.hid ? [...document.querySelectorAll(`.rd-screen mark[data-hid="${p.hid}"]`)] : [...document.querySelectorAll(".rd-screen mark.rd-sel")];
      const W = scr.width, H = scr.height, pw = Math.min(400, W - 24);
      pop.style.width = pw + "px";
      const ph = pop.offsetHeight;
      let top = H - ph - 16, left = (W - pw) / 2;
      if (marks.length) {
        const rs = marks.flatMap((m) => [...m.getClientRects()]);
        const t = Math.min(...rs.map((r) => r.top)) - scr.top, bt = Math.max(...rs.map((r) => r.bottom)) - scr.top;
        const cx = (Math.min(...rs.map((r) => r.left)) + Math.max(...rs.map((r) => r.right))) / 2 - scr.left;
        if (bt + 22 + ph < H - 8) top = bt + 22; else if (t - 22 - ph > 8) top = t - 22 - ph; else top = H - ph - 8;
        left = clamp(cx - pw / 2, 12, W - pw - 12);
        pop.style.setProperty("--ax", clamp(cx - left, 24, pw - 24) + "px");
        pop.classList.add(top > t ? "below" : "above");
      }
      pop.style.left = left + "px"; pop.style.top = top + "px";
    },
  });
  const popSel = () => { const el = document.querySelector(".rd-hl"); return el ? JSON.parse(el.dataset.sel) : null; };
  function addHl(s, extra = {}) {
    const v = RD.hls(s.id); const hid = "h" + Date.now().toString(36);
    v.push({ hid, ch: s.ch, pid: s.pid, a: s.a, b: s.b, style: RD.hlPick.style, color: RD.hlPick.color, note: "", date: RD.today, ...extra });
    RD.saveHls(s.id, v); return hid;
  }
  App.action("hlStyle", (el) => {
    const p = popSel(); RD.hlPick.style = el.dataset.v;
    if (p.hid) { const v = RD.hls(p.id).map((h) => (h.hid === p.hid ? { ...h, style: el.dataset.v } : h)); RD.saveHls(p.id, v); RD.quietRefresh(); return; }
    addHl(p); App.closeAll(); App.refresh(); App.toast(`${STYLE_NAMES[el.dataset.v]} saved`);
  });
  App.action("hlColor", (el) => {
    const p = popSel(); RD.hlPick.color = el.dataset.v;
    if (p.hid) { const v = RD.hls(p.id).map((h) => (h.hid === p.hid ? { ...h, color: el.dataset.v } : h)); RD.saveHls(p.id, v); }
    RD.quietRefresh();
  });
  App.action("hlAct", (el) => {
    const p = popSel(), k = el.dataset.k, s = selOf(p), id = p.id;
    const text = p.hid ? RD.hlText(id, s) : RD.selText(s);
    const selP = { id, ch: s.ch, pid: s.pid, a: s.a, b: s.b };
    const word = cleanWord(text.split(/\s+/)[0]);
    switch (k) {
      case "01_select": App.toast("Tap the word where the selection should end"); break;
      case "02_highlight":
        if (p.hid) { RD.saveHls(id, RD.hls(id).filter((h) => h.hid !== p.hid)); App.closeAll(); App.refresh(); App.toast("Highlight deleted"); }
        else { addHl(s); App.closeAll(); App.refresh(); App.toast("Highlighted"); }
        break;
      case "03_copy": try { navigator.clipboard && navigator.clipboard.writeText(text); } catch (e) { /* ignore */ } App.close(); App.toast("Copied to clipboard"); break;
      case "04_add_note": { const hid = p.hid || addHl(s); App.closeAll(); App.open("hl-note", { id, hid }); break; }
      case "05_wikipedia": App.replaceTop("wiki", { ...selP, q: text.split(/\s+/).length > 3 ? word : text }); break;
      case "06_dictionary": App.replaceTop("dict", { ...selP, word }); break;
      case "07_translate": App.replaceTop("translate", { id, ch: s.ch, pid: typeof s.pid === "number" ? s.pid : 0, sa: s.a, sb: s.b }); break;
      case "09_view_html": App.replaceTop("view-html", { id, ch: s.ch, pid: s.pid, a: s.a, b: s.b }); break;
      case "10_user_dict": App.replaceTop("hyphenate", { word }); break;
      case "11_follow_link": App.toast("No link in the selection"); break;
      case "12_search": App.closeAll(); App.go("search", { q: text.split(/\s+/).slice(0, 4).join(" "), scope: "book", id }); break;
      case "12_generate_qr_code": App.replaceTop("qr", { text }); break;
    }
  });

  /* note editor */
  App.overlay("hl-note", {
    layer: "sheet",
    render(p) {
      const id = p.id || cur().id, h = RD.hls(id).find((x) => x.hid === p.hid); if (!h) return "";
      return `<div class="ko-sheet rd-note-ed"><div class="grip"></div>
        <div class="ko-sheet-head"><span class="title">${h.note ? "Edit note" : "Add note"}</span><button class="ko-icon-btn" data-close>${I("x")}</button></div>
        <div class="rd-note-body">
          <div class="q"><mark class="hl s-${h.style} c-${h.color}">${E(RD.hlText(id, h))}</mark></div>
          <textarea id="rd-note-ta" placeholder="Write a note…" rows="4">${E(h.note || "")}</textarea>
          <div class="faint rd-note-hint">${I("info", "sm")}Notes are exported together with the highlight.</div>
        </div>
        <div class="rd-sheet-foot">${h.note ? `<button class="ko-btn ko-btn--ghost ko-btn--danger" data-action="noteSave" data-clear="1">${I("trash-2", "sm")}Remove note</button>` : ""}<span class="grow"></span><button class="ko-btn ko-btn--ghost" data-close>Cancel</button><button class="ko-btn ko-btn--primary" data-action="noteSave" data-hid="${h.hid}">Save</button></div>
      </div>`;
    },
    mount(el) { const t = el.querySelector("textarea"); if (t) setTimeout(() => t.focus({ preventScroll: true }), 50); },
  });
  App.action("noteSave", (el) => {
    const t = App.top(), id = t.params.id || cur().id, hid = t.params.hid, val = el.dataset.clear ? "" : (document.getElementById("rd-note-ta") || {}).value || "";
    RD.saveHls(id, RD.hls(id).map((h) => (h.hid === hid ? { ...h, note: val.trim() } : h))); App.closeAll(); App.refresh(); App.toast(val.trim() ? "Note saved" : "Note removed");
  });

  /* hyphenation (user dictionary) */
  function hyphenate(w) { const out = []; let cur2 = ""; const v = /[aeiouy]/i; for (let i = 0; i < w.length; i++) { cur2 += w[i]; if (i > 0 && i < w.length - 2 && v.test(w[i]) && !v.test(w[i + 1]) && cur2.length >= 2) { out.push(cur2); cur2 = ""; } } out.push(cur2); return out.filter(Boolean); }
  App.overlay("hyphenate", {
    layer: "dialog",
    render(p) {
      const w = cleanWord(p.word || "wondered"); const parts = RD.hyph && RD.hyph.w === w ? RD.hyph.parts : (RD.hyph = { w, parts: hyphenate(w) }).parts;
      const letters = parts.join("").split(""); const cuts = new Set(); let n = 0; parts.slice(0, -1).forEach((x) => { n += x.length; cuts.add(n); });
      return UI.dialog({
        cls: "rd-hyph", title: `Hyphenate “${w}”`, body: "Tap between letters to add or remove a break point. Saved to your user hyphenation dictionary.",
        bodyHtml: `<div class="rd-hyph-word">${letters.map((ch, i) => `${i ? `<button class="gap ${cuts.has(i) ? "on" : ""}" data-action="hyphGap" data-i="${i}" aria-label="Break">${cuts.has(i) ? "-" : ""}</button>` : ""}<span>${E(ch)}</span>`).join("")}</div>`,
        actions: [{ label: "Cancel", kind: "ghost", attrs: "data-close" }, { label: "Save", kind: "primary", attrs: { action: "hyphSave" } }],
      });
    },
  });
  App.action("hyphGap", (el) => { const i = +el.dataset.i, word = RD.hyph.parts.join(""); const cuts = new Set(); let n = 0; RD.hyph.parts.slice(0, -1).forEach((x) => { n += x.length; cuts.add(n); }); cuts.has(i) ? cuts.delete(i) : cuts.add(i); const pts = [0, ...[...cuts].sort((a, b) => a - b), word.length]; RD.hyph.parts = pts.slice(0, -1).map((s, k) => word.slice(s, pts[k + 1])); RD.quiet(() => App.renderLayers(true)); });
  App.action("hyphSave", () => { App.closeAll(); App.toast(`Saved: ${RD.hyph.parts.join("-")}`); });

  /* QR code */
  App.overlay("qr", {
    layer: "dialog",
    render(p) {
      const r = RD.rng("qr" + p.text), N = 29, cells = [];
      const finder = (x, y) => [[x, y], [x + N - 7, y], [x, y + N - 7]].some(([fx, fy]) => false);
      for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
        const inF = (fx, fy) => x >= fx && x < fx + 7 && y >= fy && y < fy + 7;
        const F = inF(0, 0) ? [0, 0] : inF(N - 7, 0) ? [N - 7, 0] : inF(0, N - 7) ? [0, N - 7] : null;
        let on;
        if (F) { const dx = x - F[0], dy = y - F[1]; on = dx === 0 || dy === 0 || dx === 6 || dy === 6 || (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4); }
        else on = r() < 0.47;
        if (on) cells.push(`<rect x="${x}" y="${y}" width="1.02" height="1.02"/>`);
      }
      void finder;
      return UI.dialog({
        cls: "rd-qr", title: "QR code",
        bodyHtml: `<div class="rd-qr-code"><svg viewBox="-2 -2 ${N + 4} ${N + 4}">${cells.join("")}</svg></div><div class="ko-dialog-body rd-qr-txt">“${E(String(p.text || "").slice(0, 120))}”</div>`,
        actions: [{ label: "Done", kind: "primary", attrs: "data-close" }],
      });
    },
  });

  /* View HTML */
  App.overlay("view-html", {
    layer: "page",
    render(p) {
      const id = p.id || cur().id, blk = RD.para(id, +p.ch, isNaN(+p.pid) ? p.pid : +p.pid); if (!blk) return "";
      const w = blk.w.map((x, i) => (i >= +p.a && i < +p.b ? `<span class="sel">${E(x)}</span>` : E(x))).join(" ");
      const t = (s) => `<span class="tg">${E(s)}</span>`;
      return `<div class="ko-page rd-html">
        ${App.statusBar()}
        <div class="ko-header"><button class="ko-icon-btn back" data-close>${I("arrow-left")}</button><span class="title">View HTML</span><span class="spacer"></span>
          <div class="ko-seg"><button class="on">HTML</button><button data-toast="Showing the computed CSS">CSS</button></div>
          <button class="ko-icon-btn" data-toast="HTML copied">${I("copy")}</button></div>
        <div class="ko-scroll"><pre class="rd-html-code">${t('<section id="chapter-' + (+p.ch + 1) + '" class="chapter">')}
  ${t("<p")} <span class="at">class</span>=<span class="st">"para"</span> <span class="at">id</span>=<span class="st">"p${p.pid}"</span>${t(">")}
    ${w}
  ${t("</p>")}
${t("</section>")}</pre>
        <div class="rd-html-path">${I("code-xml", "sm")}<span>body › section.chapter › p#p${E(p.pid)} › <b>text</b></span></div></div>
      </div>`;
    },
  });

  /* ------------------------------------------------------------- dictionary */
  const DEFS = {
    silence: ["ˈsaɪ.ləns", "noun", [["Complete absence of sound.", "the silence of the night"], ["The fact or state of abstaining from speech.", "she lapsed into silence"], ["The avoidance of mentioning or discussing something.", "the silence of the official report"]], "الصمت، السكون", ["quiet", "hush", "stillness"]],
    light: ["laɪt", "noun", [["The natural agent that stimulates sight and makes things visible.", "the light of the sun"], ["A source of illumination, especially a lamp.", "a light came on in the window"], ["Understanding of a problem or mystery; enlightenment.", "she saw light at last"]], "الضوء، النور", ["brightness", "glow", "illumination"]],
    evening: ["ˈiːv.nɪŋ", "noun", [["The period of time at the end of the day, usually from about 6 p.m. to bedtime.", "a quiet evening at home"], ["The last period of a person's life or career.", "in the evening of his life"]], "المساء", ["dusk", "twilight", "nightfall"]],
    window: ["ˈwɪn.dəʊ", "noun", [["An opening in a wall or roof, fitted with glass, to let in light or air.", "she looked out of the window"], ["An interval or opportunity for action.", "a window of opportunity"]], "النافذة", ["casement", "pane"]],
    morning: ["ˈmɔː.nɪŋ", "noun", [["The period of time from sunrise to noon.", "early in the morning"], ["The beginning or early period of something.", "the morning of the world"]], "الصباح", ["dawn", "daybreak", "forenoon"]],
    familiar: ["fəˈmɪl.i.ə", "adjective", [["Well known from long or close association.", "a familiar face"], ["In close friendship; intimate.", "on familiar terms"], ["Inappropriately intimate or informal.", "he is too familiar with the staff"]], "مألوف", ["well-known", "recognizable", "accustomed"]],
    strange: ["streɪndʒ", "adjective", [["Unusual or surprising; difficult to understand or explain.", "a strange noise"], ["Not previously visited, seen, or encountered; unfamiliar.", "a strange town"]], "غريب", ["odd", "peculiar", "curious"]],
    restless: ["ˈrest.ləs", "adjective", [["Unable to rest or relax as a result of anxiety or boredom.", "the audience grew restless"], ["Offering no physical or emotional rest.", "a restless night"]], "قَلِق، مضطرب", ["uneasy", "agitated", "fidgety"]],
    golden: ["ˈɡəʊl.dən", "adjective", [["Made of or coloured like gold.", "golden hair"], ["Very favourable or advantageous.", "a golden opportunity"], ["Relating to or denoting a period of great happiness or prosperity.", "the golden age of travel"]], "ذهبي", ["gilded", "aureate"]],
    hollow: ["ˈhɒl.əʊ", "adjective", [["Having a hole or empty space inside.", "a hollow tree"], ["Without significance; insincere.", "a hollow promise"], ["(of a sound) echoing, as if made in an empty space.", "a hollow knock"]], "أجوف", ["empty", "vacant", "void"]],
    distant: ["ˈdɪs.tənt", "adjective", [["Far away in space or time.", "the distant hills"], ["Not closely related.", "a distant cousin"], ["Not friendly or intimate; reserved.", "she seemed distant"]], "بعيد", ["far", "remote", "aloof"]],
    narrow: ["ˈnær.əʊ", "adjective", [["Of small width in relation to length.", "a narrow road"], ["Limited in extent, amount, or scope.", "a narrow victory"]], "ضيّق", ["slender", "tight", "confined"]],
    gentle: ["ˈdʒen.təl", "adjective", [["Mild in temperament or behaviour; kind or tender.", "a gentle voice"], ["(of wind) moderate; not strong.", "a gentle breeze"]], "لطيف، رقيق", ["tender", "mild", "soft"]],
    careful: ["ˈkeə.fəl", "adjective", [["Making sure of avoiding potential danger, mishap, or harm; cautious.", "be careful on the stairs"], ["Done with or showing thought and attention.", "a careful study"]], "حَذِر، دقيق", ["cautious", "attentive", "meticulous"]],
    remembered: ["rɪˈmem.bəd", "verb", [["Past of remember: had in or was able to bring to one's mind an awareness of someone or something from the past.", "she remembered the old farm"], ["Did not forget to do something necessary.", "he remembered to lock the door"]], "تذكّر", ["recalled", "recollected"]],
    wondered: ["ˈwʌn.dəd", "verb", [["Past of wonder: desired or was curious to know something.", "he wondered what she meant"], ["Felt admiration and amazement; marvelled.", "people wondered at the sight"]], "تساءل", ["pondered", "speculated", "marvelled"]],
    believed: ["bɪˈliːvd", "verb", [["Past of believe: accepted that something is true.", "they believed the story"], ["Held something as an opinion; thought.", "I believed him to be honest"]], "صدّق، اعتقد", ["trusted", "accepted", "supposed"]],
    listened: ["ˈlɪs.ənd", "verb", [["Past of listen: gave one's attention to a sound.", "the animals listened in silence"], ["Took notice of and acted on what someone said.", "nobody listened to his warnings"]], "أصغى، استمع", ["heard", "attended", "heeded"]],
    followed: ["ˈfɒl.əʊd", "verb", [["Past of follow: went or came after; moved or travelled behind.", "the dog followed him home"], ["Came after in time or order.", "the years that followed"]], "تبِع", ["trailed", "pursued", "succeeded"]],
    answered: ["ˈɑːn.səd", "verb", [["Past of answer: said or wrote something in reaction to someone.", "he answered without hesitation"]], "أجاب", ["replied", "responded"]],
    quiet: ["ˈkwaɪ.ət", "adjective", [["Making little or no noise.", "a quiet street"], ["Carried out discreetly, secretly, or with moderation.", "a quiet word"]], "هادئ", ["silent", "hushed", "calm"]],
    sudden: ["ˈsʌd.ən", "adjective", [["Occurring or done quickly and unexpectedly or without warning.", "a sudden change"]], "مفاجئ", ["abrupt", "unexpected", "swift"]],
    heavy: ["ˈhev.i", "adjective", [["Of great weight; difficult to lift or move.", "a heavy door"], ["Of more than the usual size, amount, or force.", "heavy rain"], ["Feeling or showing great sadness.", "a heavy heart"]], "ثقيل", ["weighty", "dense", "burdensome"]],
    stranger: ["ˈstreɪn.dʒə", "noun", [["A person whom one does not know or with whom one is not familiar.", "a stranger at the gate"], ["A person who does not know, or is not known in, a particular place.", "I'm a stranger here"]], "غريب", ["newcomer", "outsider", "visitor"]],
    carried: ["ˈkær.id", "verb", [["Past of carry: supported and moved someone or something from one place to another.", "she carried the lamp"]], "حمل", ["bore", "conveyed", "transported"]],
    watched: ["wɒtʃt", "verb", [["Past of watch: looked at or observed attentively over a period of time.", "they watched the road"]], "راقب", ["observed", "viewed", "regarded"]],
    opened: ["ˈəʊ.pənd", "verb", [["Past of open: moved a door or window so as to leave a space allowing access.", "he opened the door"]], "فتح", ["unlocked", "unfastened"]],
  };
  RD.DEFS = DEFS;
  RD.goodWord = (w) => !!DEFS[cleanWord(w).toLowerCase()];
  function lookup(word) {
    const w = cleanWord(word).toLowerCase() || "silence";
    if (DEFS[w]) return { w, ipa: DEFS[w][0], pos: DEFS[w][1], senses: DEFS[w][2], ar: DEFS[w][3], syn: DEFS[w][4] };
    const r = RD.rng("def" + w), pos = /ed$/.test(w) ? "verb" : /ly$/.test(w) ? "adverb" : r() < 0.5 ? "noun" : "adjective";
    const T = { noun: ["A thing or person that is {w}, especially in a rural or domestic setting.", "The state or quality of being {w}."], adjective: ["Having the quality of being {w}; marked by it.", "Used to describe something {w} in nature."], verb: ["Past of {w}: performed the action in question.", "Caused something to happen in a {w} manner."], adverb: ["In a {w} manner.", "To a {w} degree."] }[pos];
    return { w, ipa: w.replace(/e$/, "").replace(/th/g, "θ").replace(/sh/g, "ʃ"), pos, senses: T.map((s) => [s.replace(/\{w\}/g, w), ""]), ar: "—", syn: [] };
  }
  RD.dictIdx = 0;
  App.overlay("dict", {
    layer: "sheet",
    render(p) {
      const id = p.id || cur().id;
      let word = p.word;
      if (!word && p.demo) { const L = L_(id); const s = L && RD.demoSel(L, cur().page - 1, "word"); word = s ? RD.selText({ ...s, id }) : "silence"; }
      const d = lookup(word || "silence"), di = +(p.d ?? RD.dictIdx) % DB.DICTIONARIES.length, dn = DB.DICTIONARIES[di];
      const isAr = /AR|Mawrid/.test(dn), isWN = /WordNet/.test(dn);
      let body;
      if (isAr) body = `<div class="rd-dict-ar" dir="rtl" lang="ar"><span class="pos">${E({ noun: "اسم", adjective: "صفة", verb: "فعل", adverb: "ظرف" }[d.pos] || "")}</span><b>${E(d.ar)}</b></div>
        <ol class="rd-senses">${d.senses.slice(0, 2).map(([s, ex]) => `<li><span>${E(s)}</span>${ex ? `<em>${E(ex)}</em>` : ""}</li>`).join("")}</ol>`;
      else if (isWN) body = `<ol class="rd-senses">${d.senses.map(([s]) => `<li><span>(${d.pos.slice(0, 1)}) ${E(s.toLowerCase())}</span></li>`).join("")}</ol>${d.syn.length ? `<div class="rd-syn"><span class="faint">Synonyms</span>${d.syn.map((x) => `<button class="ko-chip" data-action="dictWord" data-w="${E(x)}">${E(x)}</button>`).join("")}</div>` : ""}`;
      else body = `<ol class="rd-senses">${d.senses.map(([s, ex]) => `<li><span>${E(s)}</span>${ex ? `<em>“${E(ex)}”</em>` : ""}</li>`).join("")}</ol>${d.syn.length ? `<div class="rd-syn"><span class="faint">Similar</span>${d.syn.map((x) => `<button class="ko-chip" data-action="dictWord" data-w="${E(x)}">${E(x)}</button>`).join("")}</div>` : ""}`;
      const sel = p.pid != null ? { id, ch: p.ch, pid: p.pid, a: p.a, b: p.b } : null;
      return `<div class="ko-sheet rd-dict" data-sel='${P(sel || {})}'><div class="grip"></div>
        <div class="ko-sheet-head rd-dict-head">
          <div class="grow"><div class="title hw">${E(d.w)}</div><div class="pr"><span class="ipa">/${E(d.ipa)}/</span><span class="pos">${E(d.pos)}</span></div></div>
          <button class="ko-icon-btn" data-toast="Pronunciation: /${E(d.ipa)}/">${I("volume-2")}</button>
          <button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button>
        </div>
        ${UI.tabs(DB.DICTIONARIES.map((n, i) => ({ label: n, on: i === di, attrs: `data-action="dictTab" data-i="${i}"` })), { cls: "ko-tabs--sm rd-dict-tabs" })}
        <div class="ko-scroll rd-dict-body">${body}<div class="rd-dict-src">${I("book-a", "sm")}${E(dn)} · ${di + 1} of ${DB.DICTIONARIES.length} dictionaries</div></div>
        <div class="rd-dict-acts">${[["hl", "highlighter", "Highlight"], ["wiki", "globe", "Wikipedia"], ["search", "search", "Search"], ["vocab", "graduation-cap", "Vocabulary"]]
          .map(([k, ic, l]) => UI.tool({ icon: ic, label: l, attrs: { action: "dictAct", k } })).join("")}${UI.tool({ icon: "x", label: "Close", attrs: "data-close" })}</div>
      </div>`;
    },
  });
  App.action("dictTab", (el) => { RD.dictIdx = +el.dataset.i; const t = App.top(); RD.quiet(() => App.replaceTop("dict", { ...t.params, d: +el.dataset.i })); });
  App.action("dictWord", (el) => { const t = App.top(); RD.quiet(() => App.replaceTop("dict", { id: t.params.id, word: el.dataset.w })); });
  App.action("dictAct", (el) => {
    const t = App.top(), p = t.params, id = p.id || cur().id, word = cleanWord(document.querySelector(".rd-dict .hw")?.textContent || p.word);
    const k = el.dataset.k;
    if (k === "hl") { const s = p.pid != null ? { id, ch: +p.ch, pid: +p.pid, a: +p.a, b: +p.b } : null; if (s) { addHl(s); App.closeAll(); App.refresh(); App.toast("Highlighted"); } else App.toast("Select the word in the text to highlight it"); }
    if (k === "wiki") App.replaceTop("wiki", { ...p, q: word });
    if (k === "search") { App.closeAll(); App.go("search", { q: word, scope: "book", id }); }
    if (k === "vocab") { const v = App.get("rd.vocab", []); if (!v.includes(word)) v.push(word); App.set("rd.vocab", v); App.toast(`“${word}” added to Vocabulary builder`); }
  });

  /* ------------------------------------------------------------- translate */
  const GLOSS = { night: "الليل", house: "البيت", field: "الحقل", morning: "الصباح", window: "النافذة", light: "الضوء", dark: "الظلام", water: "الماء", road: "الطريق", hand: "اليد", voice: "الصوت", heart: "القلب", door: "الباب", silence: "الصمت", wind: "الريح", evening: "المساء", farm: "المزرعة",
    remembered: "تذكّر", walked: "مشى", turned: "استدار", looked: "نظر", believed: "صدّق", wondered: "تساءل", carried: "حمل", watched: "راقب", opened: "فتح", followed: "تبع", waited: "انتظر", listened: "أصغى", answered: "أجاب", seemed: "بدا", began: "بدأ",
    quiet: "هادئ", heavy: "ثقيل", distant: "بعيد", narrow: "ضيّق", pale: "شاحب", bright: "ساطع", cold: "بارد", slow: "بطيء", sudden: "مفاجئ", careful: "حذِر", strange: "غريب", familiar: "مألوف", gentle: "لطيف", tired: "متعب", restless: "قلِق", golden: "ذهبي", hollow: "أجوف", stranger: "الغريب", miller: "الطحّان" };
  RD.trTarget = (L, p) => {
    if (p.pid != null && p.ch != null) return { ch: +p.ch, pid: +p.pid };
    const pg = L.pages[cur().page - 1]; if (!pg) return null;
    const blocks = RD.blocks(L.id, pg.ch, L.inline);
    const it = pg.items.find((x) => !x.head && x.a === 0 && blocks[x.bi].t === "p") || pg.items.find((x) => !x.head);
    return it ? { ch: pg.ch, pid: blocks[it.bi].t === "ar" ? blocks[it.bi].src : blocks[it.bi].pid } : null;
  };
  RD.trSrc = "book";
  App.overlay("translate", {
    layer: "sheet", clear: true,
    render(p) {
      const id = p.id || cur().id, L = L_(id), b = RD.book(id); if (!L) return "";
      const t = RD.trTarget(L, p); if (!t) return "";
      const blocks = RD.blocks(id, t.ch, false), blk = blocks.find((x) => x.pid === t.pid), n = blocks.length;
      const hasBook = RD.bilingual(b), src = hasBook ? RD.trSrc : "machine";
      const ar = RD.arFor(id, t.ch, t.pid + (src === "machine" ? 1000 : 0));
      const sa = p.sa != null ? +p.sa : -1, sb = p.sb != null ? +p.sb : -1;
      const en = blk.w.map((w, i) => `<button class="tw ${i >= sa && i < sb ? "sel" : ""}" data-action="trWord" data-w="${E(cleanWord(w))}" data-i="${i}">${E(w)}</button>`).join(" ");
      const gl = [...new Set(blk.w.map((w) => cleanWord(w).toLowerCase()).filter((w) => GLOSS[w] && w.length > 3))].slice(0, 6);
      const c = RD.cfg(id);
      return `<div class="ko-sheet rd-tr"><div class="grip"></div>
        <div class="ko-sheet-head rd-tr-head">
          <div class="grow"><div class="title">Translation</div><div class="sub">${E(RD.chapters(id)[t.ch].label)} · paragraph ${t.pid + 1} of ${n}</div></div>
          <span class="rd-lang"><span>English</span>${I("arrow-right", "sm")}<span class="ar">العربية</span></span>
          <button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button>
        </div>
        ${hasBook ? `<div class="rd-tr-src"><div class="ko-seg"><button class="${src === "book" ? "on" : ""}" data-action="trSrc" data-v="book">${I("book-open", "sm")}In this edition</button><button class="${src === "machine" ? "on" : ""}" data-action="trSrc" data-v="machine">${I("sparkles", "sm")}Machine</button></div><span class="faint">${src === "book" ? "Russell translation" : "Google Translate · online"}</span></div>` : ""}
        <div class="ko-scroll rd-tr-body">
          <div class="rd-tr-en"><div class="lang">EN</div><div class="txt">${en}</div></div>
          <div class="rd-tr-ar" dir="rtl" lang="ar"><div class="lang">ع</div><div class="txt">${E(ar)}</div></div>
          ${gl.length ? `<div class="rd-gloss"><div class="rd-ts-sep">Words in this paragraph</div><div class="chips">${gl.map((w) => `<button class="rd-gl" data-action="trWord" data-w="${w}"><span>${w}</span><span class="ar" lang="ar">${GLOSS[w]}</span></button>`).join("")}</div></div>` : ""}
          <div class="rd-tr-tip">${I("pointer", "sm")}Tap any English word to look it up.</div>
        </div>
        <div class="rd-tr-foot">
          <button class="ko-btn" data-action="trNav" data-d="-1" ${t.pid <= 0 && t.ch <= 0 ? "disabled" : ""}>${I("chevron-left", "sm")}Previous</button>
          <div class="mid">
            <button class="ko-icon-btn" data-action="trCopy" aria-label="Copy">${I("copy")}</button>
            <button class="ko-icon-btn ${c.tr_inline === "1" ? "active" : ""}" data-action="trInline" aria-label="Show inline">${I("rows-3")}</button>
            <button class="ko-icon-btn" data-action="trDefine" aria-label="Define word">${I("book-a")}</button>
          </div>
          <button class="ko-btn" data-action="trNav" data-d="1">Next${I("chevron-right", "sm")}</button>
        </div>
      </div>`;
    },
  });
  App.action("trWord", (el) => { const t = App.top().params; const id = t.id || cur().id; App.open("dict", { id, word: el.dataset.w }); });
  App.action("trDefine", () => { const w = document.querySelector(".rd-tr-en .tw.sel") || [...document.querySelectorAll(".rd-tr-en .tw")].find((x) => RD.goodWord(x.textContent)); App.open("dict", { id: cur().id, word: w ? cleanWord(w.textContent) : "silence" }); });
  App.action("trSrc", (el) => { RD.trSrc = el.dataset.v; RD.quiet(() => App.renderLayers(true)); });
  App.action("trCopy", () => App.toast("Translation copied"));
  App.action("trInline", () => { const { id } = cur(); const c = RD.cfg(id); RD.setCfg(id, "tr_inline", c.tr_inline === "1" ? "0" : "1"); App.toast(c.tr_inline === "1" ? "Arabic hidden in the text" : "Arabic shown under each paragraph"); });
  App.action("trNav", (el) => {
    const top = App.top(), p = top.params, id = p.id || cur().id, L = L_(id), t = RD.trTarget(L, p);
    let ch = t.ch, pid = t.pid + +el.dataset.d;
    const n = RD.blocks(id, ch, false).length;
    if (pid >= n) { if (ch + 1 >= RD.chapters(id).length) return; ch++; pid = 0; }
    if (pid < 0) { if (ch <= 0) return; ch--; pid = RD.blocks(id, ch, false).length - 1; }
    const pi = RD.pageOf(L, { ch, pid, a: 0 });
    if (pi !== cur().page - 1) RD.quiet(() => { RD.goPage(id, pi + 1); App.open("translate", { id, ch, pid }); });
    else RD.quiet(() => { App.replaceTop("translate", { id, ch, pid }); App.render(true); });
  });

  /* ------------------------------------------------------------- wikipedia */
  RD.wikiLang = "en";
  App.overlay("wiki", {
    layer: "sheet",
    render(p) {
      const id = p.id || cur().id;
      let q = p.q;
      if (!q) { const L = L_(id); const s = L && RD.demoSel(L, cur().page - 1, "word"); q = s ? RD.selText({ ...s, id }) : "Silence"; }
      q = String(q).replace(/^\w/, (c) => c.toUpperCase());
      const lang = RD.wikiLang, r = RD.rng("wiki" + q);
      const lead = lang === "ar" ? RD.arParagraph("wk" + q, 55) : `<b>${E(q)}</b> is ${E(TextGen.paragraph("wiki" + q).replace(/^\w/, (c) => c.toLowerCase()))}`;
      const lead2 = lang === "ar" ? RD.arParagraph("wk2" + q, 40) : E(TextGen.paragraph("wiki2" + q));
      const secs = ["Etymology", "History", "In literature", "Culture", "See also"];
      return `<div class="ko-sheet rd-wiki"><div class="grip"></div>
        <div class="ko-sheet-head rd-wiki-head">
          <span class="wlogo">${I("globe")}</span>
          <div class="grow"><div class="title">${E(q)}</div><div class="sub">From Wikipedia, the free encyclopedia</div></div>
          <div class="ko-seg">${["en", "ar", "fr"].map((l) => `<button class="${lang === l ? "on" : ""}" data-action="wikiLang" data-v="${l}">${l.toUpperCase()}</button>`).join("")}</div>
          <button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button>
        </div>
        <div class="ko-scroll rd-wiki-body" ${lang === "ar" ? 'dir="rtl" lang="ar"' : ""}>
          <figure class="rd-wiki-fig"><svg viewBox="0 0 120 80" preserveAspectRatio="xMidYMid slice"><rect width="120" height="80" class="sky"/><circle cx="${30 + r() * 60}" cy="24" r="9" class="sun"/><path d="M0 62 Q30 ${40 + r() * 10} 60 58 T120 54 V80 H0Z" class="hill"/><path d="M0 70 Q40 60 80 70 T120 66 V80 H0Z" class="hill2"/></svg><figcaption>${lang === "ar" ? "صورة توضيحية" : `Illustration · ${E(q)}`}</figcaption></figure>
          <p class="lead">${lead}</p><p>${lead2}</p>
          <div class="rd-wiki-secs">${secs.map((s) => `<button class="ko-row" data-toast="Opens the full article">${E(s)}<span class="grow"></span>${I("chevron-right", "sm")}</button>`).join("")}</div>
        </div>
        <div class="rd-sheet-foot"><button class="ko-btn ko-btn--ghost" data-toast="Saved to Wikipedia/${E(q)}.epub">${I("download", "sm")}Save as EPUB</button><span class="grow"></span><button class="ko-btn" data-action="wikiDict">${I("book-a", "sm")}Dictionary</button><button class="ko-btn ko-btn--primary" data-toast="Opening full article…">${I("external-link", "sm")}Full article</button></div>
      </div>`;
    },
  });
  App.action("wikiLang", (el) => { RD.wikiLang = el.dataset.v; RD.quiet(() => App.renderLayers(true)); });
  App.action("wikiDict", () => { const t = App.top().params; App.replaceTop("dict", { ...t, word: cleanWord(String(t.q || "silence").split(/\s+/)[0]) }); });

  /* -------------------------------------------------------------- book end */
  App.overlay("book-end", {
    layer: "page",
    render(p) {
      const id = p.id || cur().id, b = RD.book(id);
      const rating = App.get("rd.rating." + id, b.rating || 0), status = App.get("rd.status." + id, "finished");
      const nextInSeries = b.series ? DB.BOOKS.find((x) => x.series && x.series[0] === b.series[0] && x.series[1] === b.series[1] + 1) : null;
      const author = b.author.split(";")[0];
      let more = DB.BOOKS.filter((x) => x.id !== id && x.author.split(";")[0] === author);
      const moreTitle = more.length ? `More from ${author}` : "You might also like";
      if (!more.length) more = DB.BOOKS.filter((x) => x.id !== id && x.folder === b.folder).slice(0, 6);
      const hl = RD.hls(id).length, r = RD.rng("end" + id);
      const hours = 2 + Math.floor(r() * 7), mins = Math.floor(r() * 59);
      return `<div class="ko-page rd-end">
        ${App.statusBar()}
        <div class="ko-header"><button class="ko-icon-btn back" data-close aria-label="Back to the book">${I("arrow-left")}</button><span class="spacer"></span><button class="ko-icon-btn" data-go="library" aria-label="Library">${I("library-big")}</button></div>
        <div class="ko-scroll"><div class="rd-end-wrap">
          <div class="rd-end-hero">
            <div class="cv">${Cover.html(b)}</div>
            <div class="the-end">The End</div>
            <h2>You finished <em>${E(RD.short(b))}</em></h2>
            <div class="faint">${E(author)} · ${b.year < 0 ? -b.year + " BC" : b.year}</div>
          </div>
          <div class="rd-end-stats">
            <div><b class="num">${hours}h ${mins}m</b><span>reading time</span></div>
            <div><b class="num">${b.pages}</b><span>pages</span></div>
            <div><b class="num">${hl}</b><span>highlights</span></div>
            <div><b class="num">${6 + Math.floor(r() * 20)}</b><span>days</span></div>
          </div>
          <div class="rd-end-sec">
            <div class="ko-section-label">Your rating</div>
            <div class="rd-stars">${UI.stars(rating, { size: "lg", attrs: (n) => `data-action="endRate" data-v="${n}"` })}<span class="faint">${rating ? ["", "Didn't like it", "It was OK", "Liked it", "Really liked it", "Loved it"][rating] : "Tap to rate"}</span></div>
            <button class="rd-linkrow" data-open="input" data-params='${P({ title: "Review", hint: "What did you think?", ok: "Save" })}'>${I("pen-line", "sm")}<span class="lbl">Write a review<small>Saved with the book's metadata</small></span>${I("chevron-right", "sm")}</button>
          </div>
          <div class="rd-end-sec">
            <div class="ko-section-label">Status</div>
            <div class="ko-seg rd-end-status">${[["reading", "Reading", "book-open"], ["onhold", "On hold", "pause"], ["finished", "Finished", "check-check"]].map(([k, l, ic]) => `<button class="${status === k ? "on" : ""}" data-action="endStatus" data-v="${k}">${I(ic, "sm")}${l}</button>`).join("")}</div>
          </div>
          ${nextInSeries ? `<div class="rd-end-sec"><div class="ko-section-label">Next in ${E(b.series[0])}</div>
            <div class="rd-end-next"><div class="cv">${Cover.html(nextInSeries)}</div><div class="grow"><div class="t">${E(nextInSeries.title)}</div><div class="faint">Book ${nextInSeries.series[1]} · ${nextInSeries.pages} pages</div><button class="ko-btn ko-btn--primary" data-action="endOpen" data-id="${nextInSeries.id}">${I("book-open", "sm")}Start reading</button></div></div></div>` : ""}
          <div class="rd-end-sec"><div class="ko-section-label">${E(moreTitle)}</div>
            <div class="rd-end-more">${more.slice(0, 6).map((x) => `<button data-action="endOpen" data-id="${x.id}">${Cover.html(x, x.progress ? { badge: x.progress + "%" } : {})}<span class="ellipsis">${E(RD.short(x))}</span></button>`).join("")}</div></div>
          <div class="rd-end-sec rd-end-acts">
            <button class="rd-linkrow" data-action="endStart">${I("rotate-ccw", "sm")}<span class="lbl">Go to the beginning</span>${I("chevron-right", "sm")}</button>
            <button class="rd-linkrow" data-go="library">${I("library-big", "sm")}<span class="lbl">Back to library</span>${I("chevron-right", "sm")}</button>
            <button class="rd-linkrow" data-toast="Opening the next file in the folder">${I("file-symlink", "sm")}<span class="lbl">Open next file in folder</span>${I("chevron-right", "sm")}</button>
            <button class="rd-linkrow" data-open="confirm" data-params='${P({ title: "Delete this book?", body: "The file and its highlights will be removed from the device.", ok: "Delete", danger: true })}'>${I("trash-2", "sm")}<span class="lbl danger">Delete book</span>${I("chevron-right", "sm")}</button>
            <div class="rd-end-pref">${I("settings-2", "sm")}<span>When reaching the end of a book: <b>show this screen</b></span></div>
          </div>
        </div></div>
      </div>`;
    },
  });
  App.action("endRate", (el) => { const id = App.top().params.id || cur().id; App.set("rd.rating." + id, +el.dataset.v); RD.quiet(() => App.renderLayers(true)); });
  App.action("endStatus", (el) => { const id = App.top().params.id || cur().id; App.set("rd.status." + id, el.dataset.v); RD.quiet(() => App.renderLayers(true)); App.toast(el.dataset.v === "finished" ? "Marked as finished" : "Status updated"); });
  App.action("endOpen", (el) => { App.go("reader", { id: el.dataset.id }); });
  App.action("endStart", () => { const id = App.top().params.id || cur().id; RD.goPage(id, 1); });

  /* ---------------------------------------------------------------- demos */
  const D = (label, hash) => App.demo("Reader", label, hash);
  D("Contents (TOC)", "#/reader?id=animal-farm&o=toc");
  D("Bookmarks", "#/reader?id=animal-farm&o=bookmarks");
  D("Annotations", "#/reader?id=animal-farm&o=annotations");
  D("Export highlights", "#/reader?id=animal-farm&o=annotations-export");
  D("Go to page", "#/reader?id=animal-farm&o=goto");
  D("Skim", "#/reader?id=animal-farm&o=skim");
  D("Book map", "#/reader?id=animal-farm&o=bookmap");
  D("Page browser", "#/reader?id=animal-farm&o=pagebrowser");
  D("Page browser · PDF", "#/reader?id=pride&o=pagebrowser");
  D("More menu", "#/reader?id=animal-farm&o=reader-more");
  D("Selection + popup", "#/reader?id=animal-farm&o=hl-popup&o.demo=1");
  D("Tap on a highlight", "#/reader?id=animal-farm&hl=s2&o=hl-popup&o.hid=s2");
  D("Selection · PDF", "#/reader?id=pride&o=hl-popup&o.demo=1");
  D("Add note", "#/reader?id=animal-farm&hl=s2&o=hl-note&o.hid=s2");
  D("Dictionary", "#/reader?id=animal-farm&o=dict&o.demo=1");
  D("Dictionary · EN→AR", "#/reader?id=animal-farm&o=dict&o.demo=1&o.d=1");
  D("Translate paragraph", "#/reader?id=animal-farm&o=translate");
  D("Wikipedia", "#/reader?id=animal-farm&o=wiki&o.demo=1");
  D("View HTML", "#/reader?id=animal-farm&o=view-html&o.ch=0&o.pid=2&o.a=3&o.b=9");
  D("Hyphenate word", "#/reader?id=animal-farm&o=hyphenate&o.word=wondered");
  D("QR code", "#/reader?id=animal-farm&o=qr&o.text=The%20animals%20were%20happy");
  D("End of book", "#/reader?id=sherlock-1&o=book-end");
})();
