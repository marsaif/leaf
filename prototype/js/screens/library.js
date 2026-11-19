/* ==========================================================================
   Library agent — screens: library, folder, history, collection
   overlays: book-details (page), book-actions (sheet), plus (popover),
             sort (popover), book-status (sheet)
   private overlays: lib-coll-pick, lib-coll-menu, lib-coll-new, lib-shortcuts,
             lib-hist-menu
   Shared helpers live on window.Lib (also used by home.js).
   ========================================================================== */
(function () {
  const A = App, esc = App.esc, I = App.icon;
  const Lib = (window.Lib = {});

  /* ------------------------------------------------------------------ state */
  Lib.status = (b) => A.get(`bk.${b.id}.status`, b.status);
  Lib.rating = (b) => A.get(`bk.${b.id}.rating`, b.rating);
  Lib.fav = (b) => A.get(`bk.${b.id}.fav`, b.favorite);
  Lib.pct = (b) => { const s = Lib.status(b); return s === "new" ? 0 : s === "finished" ? 100 : b.progress || 0; };
  Lib.minLeft = (b) => Math.max(1, Math.round(((100 - Lib.pct(b)) / 100) * b.pages * 1.6));
  Lib.dur = (min) => { const h = Math.floor(min / 60), m = min % 60; return h ? `${h} h${m ? ` ${m} min` : ""}` : `${m} min`; };
  Lib.durShort = (min) => { const h = Math.floor(min / 60), m = min % 60; return h ? `${h}h ${String(m).padStart(2, "0")}m` : `${m}m`; };
  Lib.author = (b) => b.author.split(";")[0].trim();
  Lib.year = (b) => (b.year < 0 ? `c. ${-b.year} BC` : String(b.year));
  Lib.file = (b) => `${b.lang === "ar" ? b.title : b.title.replace(/\s*\(.*?\)/, "").replace(/[^\w\s-]/g, "").trim()}.${b.format}`;
  Lib.path = (b) => `/mnt/onboard/Books/${b.folder}/${Lib.file(b)}`;
  Lib.page = (b) => Math.max(1, Math.round((Lib.pct(b) / 100) * b.pages));
  Lib.lang = (b) => (b.lang === "ar" ? ` lang="ar" dir="rtl"` : "");
  Lib.infoBody = (b) => [`Title: ${b.title}`, `Authors: ${b.author}`, `Series: ${b.series ? b.series[0] + " #" + b.series[1] : "—"}`, `Pages: ${b.pages}`, `Language: ${b.language}`, `Publisher: ${b.publisher}`, `File: ${Lib.path(b)}`, `Format: ${b.format.toUpperCase()} · ${b.size}`].join("\n");
  Lib.statusLabel = { new: "New", reading: "Reading", onhold: "On hold", finished: "Finished" };
  Lib.statusIcon = { new: "sparkle", reading: "book-open", onhold: "pause", finished: "check" };
  Lib.collections = () => DB.COLLECTIONS.map((c) => (c.name === "Favorites" ? { ...c, ids: DB.BOOKS.filter(Lib.fav).map((b) => b.id) } : c));
  Lib.dims = () => { const s = document.getElementById("screen") || document.querySelector(".ko-screen"); return { w: s?.clientWidth || 600, h: s?.clientHeight || 800 }; };
  Lib.stars = (n, id, cls = "") => UI.stars(n, { size: cls === "lg" ? "lg" : "", attrs: id ? (i) => ({ action: "lib-rate", arg: `${id}|${i}` }) : null });
  /** text cover used by "Mosaic with text covers" and deleted history items */
  Lib.textCover = (b, extra = "") => `<div class="ko-cover lb-tcover ${extra}"><div class="in"><span class="t"${b.lang === "ar" ? ' lang="ar" dir="rtl"' : ""}>${esc(b.title)}</span><span class="r"></span><span class="a">${esc(b.author ? b.author.split(";")[0] : "")}</span></div></div>`;

  let SEL = null;          // selection-mode set (in-memory)
  let CLIP = null;         // {op:"copy"|"cut", ids}
  const selSet = () => (SEL ||= new Set(["frankenstein", "pride", "dracula"]));

  /* ------------------------------------------------------------- settings */
  const VIEWS = [
    ["classic", "Classic (filename only)", "list"],
    ["grid", "Mosaic with cover images", "layout-grid"],
    ["textgrid", "Mosaic with text covers", "type"],
    ["detail", "Detailed list with cover images and metadata", "rows-3"],
    ["detail-noimg", "Detailed list with metadata, no images", "align-justify"],
    ["list", "Detailed list with cover images and filenames", "list-video"],
  ];
  const SORTS = [
    ["name", "Name"], ["natural", "Name (natural sorting)"], ["access", "Last read date"], ["date", "Date modified"],
    ["size", "Size"], ["type", "Type"], ["pct_first", "Percent – unopened first"], ["pct_last", "Percent – unopened last"],
    ["pct_fin_last", "Percent – unopened – finished last"],
    ["title", "Title", 1], ["authors", "Authors", 1], ["series", "Series", 1], ["keywords", "Keywords", 1], ["rating", "Rating", 1],
  ];
  const STARTS = [["filebrowser", "File browser"], ["history", "History"], ["favorites", "Favorites"], ["shortcuts", "Folder shortcuts"], ["last", "Last file"]];
  const TOGGLES = {
    subfolders: ["Show all files from subfolders", false], hidden: ["Show hidden files", false], unsupported: ["Show unsupported files", false],
    shrinkMosaic: ["Shrink item font size to fit more text", true], fileProps: ["Show file properties", false], flash: ["Flash when displaying covers", false],
    progMosaic: ["Show progress in mosaic mode", true], progList: ["Show progress in detailed list mode", true],
    pagesRead: ["Show number of pages read instead of progress %", false], pagesLeft: ["Show number of pages left to read", false],
    hintDesc: ["Show hint for books with description", true], hintHist: ["Show hint for book status in history", false], hintColl: ["Show hint for book status in collections", false],
    shrinkClassic: ["Shrink item font size to fit more text", false], boldOpened: ["Show opened files in bold", false], boldNew: ["Show new (not yet opened) files in bold", true],
    shortDate: ["Shorten date/time", false], freeze: ["Freeze last read date of finished books", false], autoRemove: ["Auto-remove deleted or purged items from history", false],
    showFilename: ["Show filename in Open last/previous menu items", false],
    shortHome: ["Shorten home folder", true], lockHome: ["Lock home folder", false],
    askOpen: ["Ask to open files", false], parent: ["Show parent folder", true], collMark: ["Show collection mark", true],
    reverse: ["Reverse sorting", false], mixed: ["Folders and files mixed", false], everywhere: ["Use this mode everywhere", true],
  };
  const tg = (k) => A.get("fb." + k, TOGGLES[k][1]);
  const NUMS = { mosaicP: [3, 2], mosaicL: [4, 2], listItems: 10, classicItems: 14, classicFont: 19, infoItems: 14 };
  const num = (k) => A.get("fb." + k, NUMS[k]);

  Lib.view = (p = {}) => p.view || A.get("lib.view", "grid");
  const sortKey = () => A.get("lib.sort", "name");
  const sortLabel = () => (SORTS.find((s) => s[0] === sortKey()) || SORTS[0])[1];
  const filters = () => A.get("lib.filter", []);

  /* ------------------------------------------------------------- sorting */
  const lastName = (b) => Lib.author(b).split(" ").pop();
  const hIdx = (b) => { const i = DB.HISTORY.indexOf(b.id); return i < 0 ? 999 : i; };
  Lib.sorted = (books, key = sortKey(), rev = tg("reverse")) => {
    const t = (a, b) => a.title.localeCompare(b.title, undefined, { numeric: key === "natural" });
    const pctKey = (b, unopenedLast, finLast) => { const p = Lib.pct(b), s = Lib.status(b); if (s === "new") return unopenedLast ? 1000 : -1; if (finLast && s === "finished") return 2000; return p; };
    const cmp = {
      name: t, natural: t, title: t, keywords: t,
      access: (a, b) => hIdx(a) - hIdx(b) || t(a, b),
      date: (a, b) => b.added.localeCompare(a.added),
      size: (a, b) => parseFloat(a.size) - parseFloat(b.size),
      type: (a, b) => a.format.localeCompare(b.format) || t(a, b),
      pct_first: (a, b) => pctKey(a) - pctKey(b), pct_last: (a, b) => pctKey(a, 1) - pctKey(b, 1),
      pct_fin_last: (a, b) => pctKey(a, 1, 1) - pctKey(b, 1, 1),
      authors: (a, b) => lastName(a).localeCompare(lastName(b)) || t(a, b),
      series: (a, b) => (a.series ? 0 : 1) - (b.series ? 0 : 1) || (a.series?.[0] || "").localeCompare(b.series?.[0] || "") || (a.series?.[1] || 0) - (b.series?.[1] || 0) || t(a, b),
      rating: (a, b) => Lib.rating(b) - Lib.rating(a) || t(a, b),
    }[key] || t;
    const out = [...books].sort(cmp);
    return rev ? out.reverse() : out;
  };
  const filtered = (books) => { const f = filters(); return f.length ? books.filter((b) => f.includes(Lib.status(b))) : books; };

  /* ------------------------------------------------------------- layout */
  const CHROME = { status: 26, header: 56, tabs: 46, pager: 48, nav: 60 };
  /** mosaic geometry for the available area */
  function mosaic(chrome) {
    const { w, h } = Lib.dims();
    const land = w > h;
    let [cols, rows] = land ? num("mosaicL") : num("mosaicP");
    if (land && w >= 900 && cols < 5 && !A.store["fb.mosaicL"]) cols = 5;
    const padX = w >= 900 ? 28 : 20, gapX = w >= 900 ? 24 : 16, gapY = 18, capH = 70;
    const availH = h - chrome - 18 - 10;
    const rowH = (availH - gapY * (rows - 1)) / rows;
    const colW = (w - padX * 2 - gapX * (cols - 1)) / cols;
    let ch = rowH - capH, cw = Math.min(colW - 8, ch * 2 / 3);
    ch = Math.round(cw * 1.5); cw = Math.round(cw);
    const capW = Math.round(Math.min(colW, cw * 1.42));
    return { cols, rows, per: cols * rows, cw, ch, capW, colW, rowH, padX, gapX, gapY };
  }
  function listPer(view, chrome) {
    const { h } = Lib.dims();
    const avail = h - chrome - 16;
    const rowH = { classic: 52, list: 72, detail: 112, "detail-noimg": 84 }[view] || 72;
    const fit = Math.max(3, Math.floor(avail / rowH));
    const want = view === "classic" ? num("classicItems") : num("listItems");
    return { per: Math.min(fit, want), rowH: Math.floor(avail / Math.min(fit, want)) };
  }

  /* ------------------------------------------------------------- pieces */
  const progLine = (b, opts = {}) => {
    const s = Lib.status(b), p = Lib.pct(b);
    if (s === "new") return `<div class="lb-prog new"><span>Not started</span></div>`;
    if (s === "finished") return `<div class="lb-prog done"><span>${I("circle-check", "sm")} Finished</span>${opts.rating !== false && Lib.rating(b) ? `<span class="lb-mini-stars">${"★".repeat(Lib.rating(b))}</span>` : ""}</div>`;
    const label = tg("pagesRead") ? `${Lib.page(b)}/${b.pages}` : tg("pagesLeft") ? `${b.pages - Lib.page(b)} left` : `${p}%`;
    return `<div class="lb-prog ${s}">${App.progress(p, "ko-progress--thin")}<span class="num">${s === "onhold" ? I("pause", "sm") : ""}${label}</span></div>`;
  };
  const coverBadge = (b) => { const s = Lib.status(b); return s === "new" ? { badge: "New", badgeCls: "ko-badge--accent" } : s === "finished" ? { badge: I("check", "sm") } : {}; };
  const collMark = (b) => (tg("collMark") && Lib.fav(b) ? `<span class="lb-mark" title="In Favorites">${I("heart", "sm")}</span>` : "");
  const selMark = (b, sel) => (sel ? `<span class="lb-selmark ${SEL.has(b.id) ? "on" : ""}">${SEL.has(b.id) ? I("check", "sm") : ""}</span>` : "");
  const bookAttrs = (b) => `data-action="lib-book" data-arg="${b.id}" data-book="${b.id}"`;
  const moreBtn = (b) => `<button class="ko-icon-btn lb-more" data-open="book-actions" data-params='${A.attrs({ id: b.id })}' aria-label="More">${I("ellipsis-vertical")}</button>`;

  function gridHTML(books, g, sel, text) {
    return `<div class="lb-grid" style="--cols:${g.cols};--rows:${g.rows};--cw:${g.cw}px;--ch:${g.ch}px;--capw:${g.capW}px;--rh:${g.rowH}px;padding:18px ${g.padX}px 10px;column-gap:${g.gapX}px;row-gap:${g.gapY}px">
      ${books.map((b) => { const cb = coverBadge(b); return `<div class="lb-cell ${sel && SEL.has(b.id) ? "picked" : ""}" ${bookAttrs(b)}>
        <div class="lb-cov">${text ? Lib.textCover(b) + (cb.badge ? `<span class="badge ko-badge ${cb.badgeCls || ""}">${cb.badge}</span>` : "") : Cover.html(b, cb)}${collMark(b)}${selMark(b, sel)}</div>
        <div class="lb-cap">
          <div class="t ellipsis"${Lib.lang(b)}>${esc(b.title)}</div>
          <div class="a ellipsis"${Lib.lang(b)}>${esc(Lib.author(b))}</div>
          ${tg("progMosaic") ? progLine(b, { rating: false }) : ""}
        </div></div>`; }).join("")}
      ${Array.from({ length: g.per - books.length }, () => `<div class="lb-cell ghost"></div>`).join("")}
    </div>`;
  }
  function listHTML(books, view, rowH, sel) {
    const rows = books.map((b) => {
      const s = Lib.status(b);
      const check = sel ? `<span class="lb-lcheck">${App.check(SEL.has(b.id))}</span>` : "";
      if (view === "classic") return `<div class="lb-crow ${tg("boldNew") && s === "new" ? "bold" : ""}" style="height:${rowH}px" ${bookAttrs(b)}>${check}${I(b.format === "pdf" ? "file-text" : "book", "")}<span class="grow ellipsis"${Lib.lang(b)}>${esc(Lib.file(b))}</span><span class="v num">${s === "new" ? "" : s === "finished" ? "Finished" : Lib.pct(b) + "%"}</span><span class="v num sz">${b.size}</span></div>`;
      const meta = [b.format.toUpperCase(), b.size, `${b.pages} p`].join(" · ");
      if (view === "list") return `<div class="lb-lrow" style="height:${rowH}px" ${bookAttrs(b)}>${check}
          <div class="lb-lcov">${Cover.html(b)}</div>
          <div class="grow"><div class="t ellipsis"${Lib.lang(b)}>${esc(Lib.file(b))}</div>
          <div class="m ellipsis">${meta}${Lib.fav(b) && tg("collMark") ? ` · ${I("heart", "sm")}` : ""}</div>
          ${tg("progList") ? progLine(b) : ""}</div>${sel ? "" : moreBtn(b)}</div>`;
      const img = view === "detail";
      return `<div class="lb-drow ${img ? "" : "noimg"}" style="height:${rowH}px" ${bookAttrs(b)}>${check}
        ${img ? `<div class="lb-dcov">${Cover.html(b)}${collMark(b)}</div>` : `<div class="lb-dfmt"><span>${b.format.toUpperCase()}</span></div>`}
        <div class="grow">
          <div class="t ellipsis"${Lib.lang(b)}>${esc(b.title)}</div>
          <div class="a ellipsis"${Lib.lang(b)}>${esc(Lib.author(b))}</div>
          ${b.series ? `<div class="s ellipsis">${I("library", "sm")} ${esc(b.series[0])} · #${b.series[1]}</div>` : `<div class="s ellipsis">${meta} · ${Lib.year(b)}</div>`}
          ${tg("progList") ? progLine(b) : ""}
        </div>
        <div class="lb-dside"><span class="ko-pill ${{ new: "ko-pill--accent", reading: "ko-pill--current", finished: "ko-pill--soft" }[s] || ""}">${Lib.statusLabel[s]}</span><span class="when">${b.lastRead || "Added " + fmtDate(b.added)}</span>${sel ? "" : moreBtn(b)}</div>
      </div>`;
    });
    return `<div class="lb-rows view-${view}" style="--rh:${rowH}px">${rows.join("")}</div>`;
  }
  const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const fmtDate = (iso) => { const [, m, d] = iso.split("-"); return `${MONTHS[+m - 1]} ${+d}`; };

  function pagerHTML(page, pages, go, left) {
    const p = (n) => `data-go="${go.screen}" data-params='${A.attrs({ ...go.params, page: n })}'`;
    return `<div class="ko-pager lb-pager">
      <div class="lb-pager-l">${left || ""}</div>
      <span class="num lb-pager-c">Page ${page} of ${pages}</span>
      <div class="lb-pager-r">
        <button class="ko-icon-btn" ${page > 1 ? p(page - 1) : "disabled"} aria-label="Previous page">${I("chevron-left")}</button>
        <button class="ko-icon-btn" ${page < pages ? p(page + 1) : "disabled"} aria-label="Next page">${I("chevron-right")}</button>
      </div></div>`;
  }
  /** paginated book area for a set of books (grid or list), returns {body, pager} */
  function bookArea(books, params, screen, chrome, sel) {
    const view = Lib.view(params);
    const isGrid = view === "grid" || view === "textgrid";
    const g = isGrid ? mosaic(chrome) : null;
    const lp = isGrid ? null : listPer(view, chrome);
    const per = isGrid ? g.per : lp.per;
    const pages = Math.max(1, Math.ceil(books.length / per));
    const page = Math.min(pages, Math.max(1, +params.page || 1));
    const slice = books.slice((page - 1) * per, page * per);
    const body = !books.length ? emptyHTML() : isGrid ? gridHTML(slice, g, sel, view === "textgrid") : listHTML(slice, view, lp.rowH, sel);
    const nf = filters().length;
    const left = `<button class="lb-sortinfo" data-open="sort">${I(tg("reverse") ? "arrow-up-narrow-wide" : "arrow-down-narrow-wide", "sm")}<span>${esc(sortLabel())}</span>${nf ? `<span class="dot">· ${nf} filter${nf > 1 ? "s" : ""}</span>` : ""}</button>`;
    return { body, pager: pagerHTML(page, pages, { screen, params: { ...params } }, left) };
  }
  const emptyHTML = () => `<div class="ko-empty lb-empty">${I("book-dashed")}<div class="h">No books here</div><div>Change the book status filter or add books to this folder.</div><button class="ko-btn" data-action="lib-clear-filter">Clear filters</button></div>`;

  /* ------------------------------------------------------------- headers */
  const hdrBtns = (more = "") => `
    <button class="ko-icon-btn" data-go="search" data-params='${A.attrs({ scope: "library" })}' aria-label="Search">${I("search")}</button>
    <button class="ko-icon-btn ${filters().length || sortKey() !== "name" || tg("reverse") ? "active" : ""}" data-open="sort" aria-label="Sort and view">${I("arrow-down-wide-narrow")}</button>
    <button class="ko-icon-btn" data-open="plus" aria-label="Add">${I("plus")}</button>${more}
    <button class="ko-icon-btn" data-open="main-menu" data-params='${A.attrs({ ctx: "fm" })}' aria-label="Menu">${I("menu")}</button>`;
  const selHeader = (n, total) => `<div class="ko-header lb-selhead">
      <button class="ko-icon-btn back" data-action="lib-sel-exit" aria-label="Exit selection">${I("x")}</button>
      <span class="title">${n} selected</span><span class="count">of ${total}</span><span class="spacer"></span>
      <button class="ko-btn ko-btn--ghost" data-action="lib-sel-all">${n === total ? "Deselect all" : "Select all"}</button></div>`;
  const selBar = () => {
    const n = SEL.size, dis = n ? "" : "disabled";
    const b = (op, ic, l, cls = "") => `<button class="${cls}" data-action="lib-sel-op" data-arg="${op}" ${dis}>${I(ic)}<span>${l}</span></button>`;
    return `<nav class="ko-nav lb-selbar">${b("copy", "copy", "Copy")}${b("cut", "scissors", "Cut")}${b("move", "folder-input", "Move")}${b("coll", "library", "Collection")}${b("mark", "bookmark-check", "Mark as…")}${b("delete", "trash-2", "Delete", "danger")}</nav>`;
  };
  const TABS = [["library", "Library"], ["favorites", "Favorites"], ["collections", "Collections"], ["folders", "Folders"]];
  const tabsHTML = (tab, params) => {
    const v = Lib.view(params);
    const quick = [["grid", "layout-grid", "Mosaic"], ["detail", "rows-3", "Detailed list"], ["list", "list", "List"]];
    const isOn = (k) => v === k || (k === "grid" && v === "textgrid") || (k === "detail" && v === "detail-noimg") || (k === "list" && v === "classic");
    return `<div class="ko-tabs lb-tabs">${TABS.map(([k, l]) => `<button class="ko-tab ${tab === k ? "on" : ""}" data-go="library" data-params='${A.attrs({ tab: k })}'>${l}</button>`).join("")}
      ${tab === "library" || tab === "favorites" ? `<span class="lb-viewsw">${quick.map(([k, ic, l]) => `<button class="${isOn(k) ? "on" : ""}" data-action="lib-view" data-arg="${k}" aria-label="${l}" title="${l}">${I(ic, "sm")}</button>`).join("")}</span>` : ""}
    </div>`;
  };

  /* ================================================================ LIBRARY */
  A.screen("library", {
    render(params) {
      const tab = params.tab || "library";
      if (tab === "collections") return collectionsTab(params);
      if (tab === "folders") return folderView(params, true);
      const sel = !!params.select;
      if (sel) selSet(); else SEL = null;
      let books = DB.BOOKS;
      if (tab === "favorites") books = books.filter(Lib.fav);
      books = Lib.sorted(filtered(books));
      const chrome = CHROME.status + CHROME.header + CHROME.tabs + CHROME.pager + CHROME.nav;
      const { body, pager } = bookArea(books, params, "library", chrome, sel);
      const header = sel ? selHeader(SEL.size, books.length) :
        `<div class="ko-header"><span class="title display">${tab === "favorites" ? "Favorites" : "Library"}</span><span class="count">${books.length} book${books.length === 1 ? "" : "s"}</span><span class="spacer"></span>${hdrBtns()}</div>`;
      return `<div class="ko-view lb ${sel ? "selecting" : ""}">${A.statusBar()}${header}${tabsHTML(tab, params)}
        <div class="lb-body">${body}</div>${pager}${sel ? selBar() : A.bottomNav("library")}</div>`;
    },
  });

  /* ---------- collections tab ---------- */
  const stack = (ids) => {
    const bs = ids.slice(0, 3).map((id) => DB.book(id));
    if (!bs.length) return `<div class="lb-stack empty">${I("library")}</div>`;
    return `<div class="lb-stack n${bs.length}">${bs.map((b, i) => `<div class="s s${i}">${Cover.html(b)}</div>`).reverse().join("")}</div>`;
  };
  function collectionsTab(params) {
    const cols = Lib.collections();
    const sortMode = A.get("lib.collSort", "manual");
    const list = sortMode === "name" ? [...cols].sort((a, b) => a.name.localeCompare(b.name)) : sortMode === "size" ? [...cols].sort((a, b) => b.ids.length - a.ids.length) : cols;
    const { w } = Lib.dims();
    const per = w >= 900 ? 8 : 6;
    const pages = Math.max(1, Math.ceil((list.length + 1) / per));
    const page = Math.min(pages, +params.page || 1);
    const cards = list.map((c) => `<div class="ko-card ko-card--flush ko-card--tap lb-ccard" data-go="collection" data-params='${A.attrs({ name: c.name })}'>
        ${stack(c.ids)}
        <div class="lb-cmeta"><div class="grow"><div class="n ellipsis">${c.name === "Favorites" ? I("heart", "sm") + " " : ""}${esc(c.name)}</div>
        <div class="c">${c.ids.length} book${c.ids.length === 1 ? "" : "s"} · ${c.ids.filter((id) => Lib.status(DB.book(id)) === "finished").length} finished</div></div>
        <button class="ko-icon-btn lb-more" data-open="lib-coll-menu" data-params='${A.attrs({ name: c.name, at: "card" })}' aria-label="Manage">${I("ellipsis-vertical")}</button></div>
      </div>`);
    cards.push(`<button class="ko-card ko-card--dashed ko-card--tap lb-ccard new" data-open="lib-coll-new">${I("plus", "lg")}<span>New collection</span><span class="faint">Group books by theme, mood or plan</span></button>`);
    const sortL = { manual: "Manual order", name: "Name", size: "Number of books" }[sortMode];
    return `<div class="ko-view lb">${A.statusBar()}
      <div class="ko-header"><span class="title display">Collections</span><span class="count">${cols.length}</span><span class="spacer"></span>${hdrBtns()}</div>
      ${tabsHTML("collections", params)}
      <div class="lb-subbar"><span class="faint">${cols.reduce((n, c) => n + c.ids.length, 0)} books in ${cols.length} collections</span><span class="spacer"></span>
        <button class="ko-link" data-open="lib-coll-menu" data-params='${A.attrs({ at: "sort" })}'>${I("arrow-down-up", "sm")} ${sortL}</button></div>
      <div class="lb-body"><div class="lb-cgrid ${w >= 900 ? "wide" : ""}">${cards.slice((page - 1) * per, page * per).join("")}</div></div>
      ${pagerHTML(page, pages, { screen: "library", params: { tab: "collections" } }, `<button class="lb-sortinfo" data-open="lib-coll-new">${I("plus", "sm")}<span>New</span></button>`)}
      ${A.bottomNav("library")}</div>`;
  }

  /* ================================================================ COLLECTION */
  A.screen("collection", {
    render(params) {
      const c = Lib.collections().find((x) => x.name === params.name) || Lib.collections()[1];
      const books = Lib.sorted(c.ids.map((id) => DB.book(id)));
      const chrome = CHROME.status + 72 + CHROME.pager + CHROME.nav;
      const { body, pager } = bookArea(books, params, "collection", chrome, false);
      const left = books.reduce((n, b) => n + (Lib.status(b) === "finished" ? 0 : Lib.minLeft(b)), 0);
      return `<div class="ko-view lb">${A.statusBar()}
        <div class="ko-header lb-chead">
          <button class="ko-icon-btn back" data-go="library" data-params='${A.attrs({ tab: "collections" })}' aria-label="Back">${I("chevron-left")}</button>
          <div class="grow"><div class="eyebrow">Collection · ${books.length} books · ${Lib.dur(left)} left</div><div class="title ellipsis">${esc(c.name)}</div></div>
          <button class="ko-icon-btn" data-open="sort" data-params='${A.attrs({ at: "coll" })}' aria-label="Sort">${I("arrow-down-wide-narrow")}</button>
          <button class="ko-icon-btn" data-open="lib-coll-menu" data-params='${A.attrs({ name: c.name })}' aria-label="Manage collection">${I("ellipsis-vertical")}</button>
        </div>
        <div class="lb-body">${body}</div>${pager}${A.bottomNav("library")}</div>`;
    },
  });

  /* ================================================================ FOLDERS */
  const ROOT_DIRS = [
    { name: "Books", count: 28, modified: "today", home: true },
    { name: "Downloads", count: 6, modified: "yesterday" },
    { name: "Articles", count: 14, modified: "3 days ago" },
    { name: "Comics", count: 9, modified: "Oct 21" },
    { name: "Screenshots", count: 31, modified: "Nov 2" },
  ];
  const SHORTCUTS = () => A.get("lib.shortcuts", ["Books", "Books/Classics", "Downloads", "Books/عربي"]);
  const fileIcon = (name) => { const ext = name.split(".").pop(); return { pdf: "file-text", html: "file-code", txt: "file-type", cbz: "file-image", epub: "book", mobi: "book" }[ext] || "file"; };
  function folderContents(path) {
    if (path === "") return { dirs: ROOT_DIRS.map((d) => ({ ...d, path: d.name })), files: [] };
    if (path === "Books") return {
      dirs: DB.FOLDERS.map((f) => ({ ...f, count: DB.BOOKS.filter((b) => b.folder === f.name).length, path: "Books/" + f.name })),
      files: DB.LOOSE_FILES.map((f) => ({ ...f, kind: "loose" })),
    };
    const name = path.split("/").pop();
    const books = DB.BOOKS.filter((b) => b.folder === name);
    if (path.startsWith("Books/")) return { dirs: [], files: Lib.sorted(books).map((b) => ({ book: b, name: Lib.file(b), size: b.size, modified: b.lastRead || fmtDate(b.added) })) };
    return { dirs: [], files: DB.LOOSE_FILES.slice(0, 3).map((f) => ({ ...f, kind: "loose" })) };
  }
  function folderView(params, asTab) {
    const path = String(params.path ?? "Books");
    const { dirs, files } = folderContents(path);
    const segs = path ? path.split("/") : [];
    const scr = asTab ? "library" : "folder";
    const go = (p) => `data-go="${scr}" data-params='${A.attrs(asTab ? { tab: "folders", path: p } : { path: p })}'`;
    const crumbs = [`<button class="lb-crumb ${!segs.length ? "on" : ""}" ${go("")}>${I("hard-drive", "sm")}<span>onboard</span></button>`]
      .concat(segs.map((s, i) => `<span class="sep">${I("chevron-right", "sm")}</span><button class="lb-crumb ${i === segs.length - 1 ? "on" : ""}" ${go(segs.slice(0, i + 1).join("/"))}><span dir="auto">${esc(s)}</span>${i === 0 && s === "Books" ? `<span class="lb-home">${I("house", "sm")}HOME</span>` : ""}</button>`)).join("");
    const items = [];
    if (path && tg("parent")) items.push(`<div class="lb-frow up" ${go(segs.slice(0, -1).join("/"))}><span class="lb-ficon">${I("corner-left-up")}</span><div class="grow"><div class="n">Up</div><div class="m">${esc("/mnt/onboard" + (segs.length > 1 ? "/" + segs.slice(0, -1).join("/") : ""))}</div></div></div>`);
    const dirRow = (d) => `<div class="lb-frow dir" ${go(d.path)} data-folder="${esc(d.path)}"><span class="lb-ficon folder">${I(d.count ? "folder" : "folder-open")}</span>
        <div class="grow"><div class="n ellipsis"><span dir="auto">${esc(d.name)}</span>${d.home ? `<span class="lb-home">${I("house", "sm")}HOME</span>` : ""}</div><div class="m">${d.count} item${d.count === 1 ? "" : "s"} · modified ${esc(d.modified)}</div></div>
        <span class="lb-fcount num">${d.count}</span><button class="ko-icon-btn lb-more" data-open="folder-actions" data-params='${A.attrs({ path: d.path })}' aria-label="Folder actions">${I("ellipsis-vertical")}</button></div>`;
    const fileRow = (f) => f.book
      ? `<div class="lb-frow file" ${bookAttrs(f.book)}><span class="lb-fthumb">${Cover.html(f.book)}</span>
          <div class="grow"><div class="n ellipsis" dir="auto">${esc(f.name)}</div><div class="m">${f.book.format.toUpperCase()} · ${f.size} · ${esc(f.modified)}</div></div>
          <span class="lb-fpct num">${Lib.status(f.book) === "new" ? `<span class="ko-pill ko-pill--accent">New</span>` : Lib.status(f.book) === "finished" ? I("circle-check", "sm") : Lib.pct(f.book) + "%"}</span>${moreBtn(f.book)}</div>`
      : `<div class="lb-frow file" data-toast="Opening ${esc(f.name)}"><span class="lb-ficon file">${I(fileIcon(f.name))}</span>
          <div class="grow"><div class="n ellipsis">${esc(f.name)}</div><div class="m">${f.name.split(".").pop().toUpperCase()} · ${f.size} · modified ${esc(f.modified)}</div></div></div>`;
    let all = tg("mixed") ? [...dirs.map((d) => ({ d, k: d.name })), ...files.map((f) => ({ f, k: f.name }))].sort((a, b) => a.k.localeCompare(b.k)).map((x) => (x.d ? dirRow(x.d) : fileRow(x.f)))
      : [...dirs.map(dirRow), ...files.map(fileRow)];
    all = items.concat(all);
    const chrome = CHROME.status + CHROME.header + (asTab ? CHROME.tabs : 0) + 44 + 52 + CHROME.pager + CHROME.nav;
    const per = Math.max(4, Math.floor((Lib.dims().h - chrome - 8) / 62));
    const pages = Math.max(1, Math.ceil(all.length / per));
    const page = Math.min(pages, +params.page || 1);
    const sc = SHORTCUTS().map((s) => `<button class="ko-chip ${s === path ? "on" : ""}" ${go(s)}>${I(s === "Books" ? "house" : "folder-symlink", "sm")}<span dir="auto">${esc(s.split("/").pop())}</span></button>`).join("");
    const count = `<span class="count">${dirs.length ? `${dirs.length} folders · ` : ""}${files.length} files</span>`;
    const header = asTab
      ? `<div class="ko-header"><span class="title display">Folders</span>${count}<span class="spacer"></span>${hdrBtns()}</div>${tabsHTML("folders", params)}`
      : `<div class="ko-header"><button class="ko-icon-btn back" data-go="library" aria-label="Back">${I("chevron-left")}</button><span class="title">Files</span>${count}<span class="spacer"></span>${hdrBtns()}</div>`;
    return `<div class="ko-view lb lb-folder">${A.statusBar()}${header}
      <div class="lb-crumbs">${crumbs}</div>
      <div class="lb-shortcuts">${sc}<button class="ko-chip ko-chip--add" data-action="lib-add-shortcut" data-arg="${esc(path)}" aria-label="Add to folder shortcuts">${I("plus", "sm")}</button></div>
      <div class="lb-body"><div class="lb-flist">${all.slice((page - 1) * per, page * per).join("")}</div></div>
      ${pagerHTML(page, pages, { screen: scr, params: asTab ? { tab: "folders", path } : { path } }, `<span class="lb-pathinfo">${I("hard-drive", "sm")}3.1 GB free</span>`)}
      ${A.bottomNav("library")}</div>`;
  }
  A.screen("folder", { render: (p) => folderView(p, false) });

  /* ================================================================ HISTORY */
  const WHEN = ["21:10", "08:45", "Tue 22:30", "Mon 19:05", "Sun 11:20", "Sat 23:40", "Nov 9", "Nov 6", "Nov 2", "Oct 28", "Oct 21", "Oct 14", "Sep 30"];
  const DELETED = [
    { id: "x-brave", title: "Brave New World", author: "Aldous Huxley", pages: 311, pct: 12, when: "Oct 3", format: "epub" },
    { id: "x-1984", title: "Nineteen Eighty-Four", author: "George Orwell", pages: 328, pct: 78, when: "Sep 12", format: "epub" },
  ];
  A.screen("history", {
    render(params) {
      const filter = params.filter || "all";
      let items = DB.HISTORY.map((id, i) => ({ b: DB.book(id), i, when: WHEN[i] || "Sep" }));
      const counts = { all: items.length + DELETED.length, reading: 0, onhold: 0, finished: 0, deleted: DELETED.length };
      items.forEach((x) => { const s = Lib.status(x.b); if (counts[s] !== undefined) counts[s]++; });
      if (filter === "deleted") items = [];
      else if (filter !== "all") items = items.filter((x) => Lib.status(x.b) === filter);
      const del = filter === "all" || filter === "deleted" ? DELETED.map((d, k) => ({ d, i: 100 + k, when: d.when })) : [];
      const all = items.concat(del);
      const group = (i) => (i < 2 ? "Today" : i < 6 ? "This week" : "Earlier");
      const chrome = CHROME.status + CHROME.header + 52 + CHROME.pager + CHROME.nav;
      const avail = Lib.dims().h - chrome - 12;
      const RH = 76, GH = 36;
      const pages = []; let cur = [], used = 0, lastG = null;
      all.forEach((x) => {
        const g = group(x.i);
        if (used + RH + (g !== lastG ? GH : 0) > avail && cur.length) { pages.push(cur); cur = []; used = 0; lastG = null; }
        const head = g !== lastG;
        cur.push({ ...x, head: head ? g : null }); used += RH + (head ? GH : 0); lastG = g;
      });
      if (cur.length) pages.push(cur);
      const np = Math.max(1, pages.length), page = Math.min(np, +params.page || 1);
      const rows = (pages[page - 1] || []).map((x) => {
        const head = x.head ? `<div class="ko-eyebrow lb-hgroup">${x.head}</div>` : "";
        if (x.d) return `${head}<div class="lb-hrow deleted" data-toast="File no longer exists">
            <div class="lb-hcov">${Lib.textCover(x.d, "gone")}</div>
            <div class="grow"><div class="t ellipsis">${esc(x.d.title)}</div><div class="a ellipsis">${esc(x.d.author)}</div>
            <div class="lb-prog deleted"><span>${I("trash-2", "sm")} File deleted · was at ${x.d.pct}%</span></div></div>
            <div class="lb-hside"><span class="when">${x.when}</span><button class="ko-link" data-toast="Removed from history">Remove</button></div></div>`;
        const b = x.b, s = Lib.status(b);
        return `${head}<div class="lb-hrow" ${bookAttrs(b)}>
          <div class="lb-hcov">${Cover.html(b)}</div>
          <div class="grow"><div class="t ellipsis"${Lib.lang(b)}>${esc(b.title)}</div><div class="a ellipsis"${Lib.lang(b)}>${esc(Lib.author(b))}</div>
          ${progLine(b)}</div>
          <div class="lb-hside"><span class="when">${x.when}</span><span class="left">${s === "finished" || s === "new" ? "" : Lib.durShort(Lib.minLeft(b)) + " left"}</span></div>
          ${moreBtn(b)}</div>`;
      }).join("");
      const chips = [["all", "All"], ["reading", "Reading"], ["onhold", "On hold"], ["finished", "Finished"], ["deleted", "Deleted"]]
        .map(([k, l]) => `<button class="ko-chip ${filter === k ? "on" : ""}" data-go="history" data-params='${A.attrs({ filter: k })}'>${l}<span class="n num">${counts[k]}</span></button>`).join("");
      return `<div class="ko-view lb">${A.statusBar()}
        <div class="ko-header"><span class="title display">History</span><span class="count">${counts.all} books</span><span class="spacer"></span>
          <button class="ko-icon-btn" data-go="search" data-params='${A.attrs({ scope: "history" })}' aria-label="Search">${I("search")}</button>
          <button class="ko-icon-btn" data-open="lib-hist-menu" aria-label="History options">${I("ellipsis-vertical")}</button>
          <button class="ko-icon-btn" data-open="main-menu" data-params='${A.attrs({ ctx: "fm" })}' aria-label="Menu">${I("menu")}</button></div>
        <div class="lb-chips">${chips}</div>
        <div class="lb-body"><div class="lb-hlist">${rows || `<div class="ko-empty">${I("history")}<div class="h">Nothing here</div><div>Books you open will appear in your history.</div></div>`}</div></div>
        ${pagerHTML(page, np, { screen: "history", params: { filter } }, `<button class="lb-sortinfo danger" data-action="lib-clear-history">${I("eraser", "sm")}<span>Clear history</span></button>`)}
        ${A.bottomNav("history")}</div>`;
    },
  });
  A.overlay("lib-hist-menu", {
    layer: "sheet",
    render: () => `<div class="ko-sheet lbs lb-histsheet">
      <div class="grip"></div>
      <div class="ko-sheet-head"><div class="grow"><span class="title">History</span><span class="sub">${DB.HISTORY.length} books opened on this device</span></div><button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button></div>
      <div class="ko-scroll">
        <div class="ko-section-label">Clean up</div>
        <div class="ko-group">
          <button class="ko-row" data-action="lib-clear-history">${I("eraser")}<span class="label">Clear history</span></button>
          <button class="ko-row" data-action="lib-clear-deleted">${I("trash")}<span class="label">Remove deleted files</span></button>
        </div>
        <div class="ko-section-label">Settings</div>
        <div class="ko-group lb-histset">${["shortDate", "freeze", "autoRemove"].map(toggleRow).join("")}</div>
        <div class="ko-group lb-histset lb-histmore"><button class="ko-row" data-action="lib-sub" data-arg="history">${I("sliders-horizontal")}<span class="label">More history settings<span class="sub">Layout, filenames in menus, hints</span></span>${I("chevron-right", "chev")}</button></div>
      </div>
    </div>`,
  });

  /* ================================================================ BOOK DETAILS */
  A.overlay("book-details", {
    layer: "page",
    render(p) {
      const b = DB.book(p.id), s = Lib.status(b), pct = Lib.pct(b), ar = b.lang === "ar";
      const hl = DB.HIGHLIGHTS.filter((h) => h.book === b.id);
      const bm = (b.pages % 5) + 1;
      const chapters = TextGen.chapters(b.id);
      const ch = chapters[Math.min(chapters.length - 1, Math.floor((pct / 100) * chapters.length))];
      const syn = TextGen.synopsis(b);
      const inColl = Lib.collections().filter((c) => c.ids.includes(b.id));
      const started = s !== "new";
      const seg = ["reading", "onhold", "finished"].map((k) => `<button class="${s === k ? "on" : ""}" data-action="lib-status" data-arg="${b.id}|${k}">${I(Lib.statusIcon[k], "sm")}${Lib.statusLabel[k]}</button>`).join("");
      const facts = [
        ["Author", Lib.author(b), ar], ["Published", Lib.year(b)], ["Pages", b.pages], ["Format", b.format.toUpperCase()], ["Size", b.size],
        ["Language", b.language], ["Publisher", b.publisher], ...(b.series ? [["Series", `${b.series[0]} #${b.series[1]}`]] : []),
        ["Added", fmtDate(b.added) + ", 2026"], ["Last read", b.lastRead || "Never"],
      ];
      return `<div class="ko-page lb-details">${A.statusBar()}
        <div class="ko-header lbd-head">
          <button class="ko-icon-btn back" data-close aria-label="Back">${I("chevron-left")}</button><span class="lbd-crumb">Book details</span><span class="spacer"></span>
          <button class="ko-icon-btn ${Lib.fav(b) ? "active" : ""}" data-action="lib-fav" data-arg="${b.id}" aria-label="Favorite">${I("heart", Lib.fav(b) ? "filled" : "")}</button>
          <button class="ko-icon-btn" data-open="lib-coll-pick" data-params='${A.attrs({ ids: [b.id] })}' aria-label="Collections">${I("library")}</button>
          <button class="ko-icon-btn" data-open="book-actions" data-params='${A.attrs({ id: b.id })}' aria-label="More actions">${I("ellipsis-vertical")}</button>
        </div>
        <div class="ko-scroll"><div class="lbd ${ar ? "ar" : ""}">
          <section class="lbd-hero">
            <div class="lbd-cover">${Cover.html(b)}</div>
            <div class="lbd-info">
              ${b.series ? `<div class="ko-eyebrow ko-eyebrow--accent lbd-eyebrow">${I("library", "sm")}${esc(b.series[0])} · Book ${b.series[1]}</div>` : `<div class="ko-eyebrow ko-eyebrow--accent lbd-eyebrow">${I("folder", "sm")}<span dir="auto">${esc(b.folder)}</span></div>`}
              <h1 class="lbd-title"${Lib.lang(b)}>${esc(b.title)}</h1>
              <div class="lbd-author"${Lib.lang(b)}>${esc(b.author.replace(";", " ·"))}</div>
              <div class="lbd-meta">${[Lib.year(b), `${b.pages} pages`, b.format.toUpperCase(), b.size, b.language].map(esc).join('<span class="d">·</span>')}</div>
              <div class="lbd-rate">${Lib.stars(Lib.rating(b), b.id)}<span class="faint">${Lib.rating(b) ? Lib.rating(b) + ".0" : "Not rated"}</span></div>
              ${inColl.length ? `<div class="lbd-colls">${inColl.map((c) => `<button class="ko-chip" data-go="collection" data-params='${A.attrs({ name: c.name })}'>${I(c.name === "Favorites" ? "heart" : "library", "sm")}${esc(c.name)}</button>`).join("")}</div>` : ""}
            </div>
          </section>

          <section class="lbd-progress ko-card">
            <div class="lbd-prow"><span class="big num">${pct}<small>%</small></span><span class="grow muted">${started ? `Page ${Lib.page(b)} of ${b.pages}<span class="d">·</span>${esc(ch.title)}` : "Not started yet"}</span>
              <span class="faint num">${s === "finished" ? "Finished " + (b.lastRead || "") : started ? Lib.dur(Lib.minLeft(b)) + " left" : "≈ " + Lib.dur(Math.round(b.pages * 1.6)) + " to read"}</span></div>
            ${App.progress(pct)}
            <div class="lbd-segrow"><span class="lbd-seglbl">Status</span><div class="ko-seg ko-seg--block ko-seg--icons lbd-seg">${seg}</div></div>
          </section>

          <section class="lbd-sec">
            <h2 class="ko-eyebrow">About this book</h2>
            <p class="lbd-syn"${ar ? ' dir="auto"' : ""}>${esc(syn)}</p>
          </section>

          <section class="lbd-sec">
            <div class="lbd-h2row"><h2 class="ko-eyebrow">Highlights & notes</h2><span class="faint">${hl.length} highlight${hl.length === 1 ? "" : "s"} · ${bm} bookmarks</span><span class="spacer"></span>
              <button class="ko-link" data-open="annotations" data-params='${A.attrs({ id: b.id })}'>View all${I("chevron-right", "sm")}</button></div>
            ${hl.length ? hl.slice(0, 3).map((h) => `<blockquote class="lbd-hl"><p>${esc(h.text)}</p>${h.note ? `<div class="note">${I("sticky-note", "sm")}${esc(h.note)}</div>` : ""}<div class="src">${esc(h.chapter)} · p. ${h.page} · ${esc(h.date)}</div></blockquote>`).join("")
              : `<div class="lbd-nohl">${I("highlighter")}<span>No highlights yet. Long-press text while reading to highlight a passage.</span></div>`}
          </section>

          <section class="lbd-sec">
            <h2 class="ko-eyebrow">Details</h2>
            <dl class="lbd-facts">${facts.map(([k, v, rtl]) => `<div><dt>${k}</dt><dd${rtl ? ' dir="rtl" lang="ar"' : ""}>${esc(v)}</dd></div>`).join("")}</dl>
            <div class="lbd-path">${I("folder", "sm")}<code dir="auto">${esc(Lib.path(b))}</code></div>
          </section>

          <section class="lbd-sec lbd-more">
            <div class="ko-group">
              <button class="ko-row" data-open="bookmarks" data-params='${A.attrs({ id: b.id })}'>${I("bookmark")}<span class="label">Bookmarks</span><span class="value">${bm}</span>${I("chevron-right", "chev")}</button>
              <button class="ko-row" data-action="lib-fm" data-arg="${hl.length} highlights exported">${I("file-output")}<span class="label">Export highlights</span><span class="value">Markdown</span>${I("chevron-right", "chev")}</button>
              <button class="ko-row" data-open="book-status" data-params='${A.attrs({ id: b.id })}'>${I("message-square-text")}<span class="label">Status, rating & review</span>${I("chevron-right", "chev")}</button>
              <button class="ko-row" data-open="info" data-params='${A.attrs({ title: "Book information", icon: "info", body: Lib.infoBody(b) })}'>${I("info")}<span class="label">Book information</span>${I("chevron-right", "chev")}</button>
            </div>
          </section>
        </div></div>
        <div class="lbd-foot">
          <button class="ko-btn ko-btn--primary lbd-go" data-action="lib-read" data-arg="${b.id}">${I(started ? "book-open" : "play")}<span>${s === "finished" ? "Read again" : started ? "Resume reading" : "Start reading"}</span>${started && s !== "finished" ? `<span class="sub num">${pct}% · ${Lib.durShort(Lib.minLeft(b))} left</span>` : ""}</button>
          <button class="ko-btn lbd-sq" data-open="lib-coll-pick" data-params='${A.attrs({ ids: [b.id] })}' aria-label="Add to collection">${I("list-plus")}</button>
          <button class="ko-btn lbd-sq" data-open="book-actions" data-params='${A.attrs({ id: b.id })}' aria-label="More">${I("ellipsis")}</button>
        </div>
      </div>`;
    },
  });

  /* ================================================================ BOOK ACTIONS */
  A.overlay("book-actions", {
    layer: "sheet",
    render(p) {
      const b = DB.book(p.id), s = Lib.status(b);
      const hl = DB.HIGHLIGHTS.filter((h) => h.book === b.id).length;
      const tool = (ic, l, attrs, cls = "") => `<button class="ko-tool ko-tool--lg ${cls === "danger" ? "ko-tool--danger" : cls}" ${attrs}>${I(ic)}<span>${l}</span></button>`;
      const row = (ic, l, attrs, extra = "", cls = "") => `<button class="ko-row ${cls}" ${attrs}>${I(ic)}<span class="label">${l}</span>${extra}</button>`;
      const chev = I("chevron-right", "chev");
      const ignC = A.get(`bk.${b.id}.ignCover`, false), ignM = A.get(`bk.${b.id}.ignMeta`, false);
      const nColl = Lib.collections().filter((c) => c.ids.includes(b.id)).length;
      return `<div class="ko-sheet lba">
        <div class="grip"></div>
        <div class="ko-sheet-head lba-head">
          <div class="lba-cov">${Cover.html(b)}</div>
          <div class="grow"><div class="title ellipsis"${Lib.lang(b)}>${esc(b.title)}</div>
            <div class="sub ellipsis" dir="auto">${esc(Lib.file(b))}</div>
            <div class="sub">${b.format.toUpperCase()} · ${b.size} · ${Lib.statusLabel[s]}${s === "reading" || s === "onhold" ? ` · ${Lib.pct(b)}%` : ""}</div></div>
          <button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button>
        </div>
        <div class="ko-scroll">
          <div class="lba-tools">
            ${tool("copy", "Copy", `data-action="lib-clip" data-arg="copy|${b.id}"`)}
            ${tool("scissors", "Cut", `data-action="lib-clip" data-arg="cut|${b.id}"`)}
            ${tool("clipboard-paste", "Paste", CLIP ? `data-action="lib-paste"` : "disabled")}
            ${tool("square-check", "Select", `data-action="lib-select-start" data-arg="${b.id}"`)}
            ${tool("pencil-line", "Rename", `data-action="lib-rename" data-arg="${b.id}"`)}
            ${tool("trash-2", "Delete", `data-action="lib-delete" data-arg="${b.id}"`, "danger")}
          </div>

          <div class="ko-section-label">Mark as</div>
          <div class="lba-status">
            <div class="ko-seg ko-seg--block ko-seg--icons">${["reading", "onhold", "finished"].map((k) => `<button class="${s === k ? "on" : ""}" data-action="lib-status" data-arg="${b.id}|${k}">${s === k ? I("check", "sm") : I(Lib.statusIcon[k], "sm")}${Lib.statusLabel[k]}</button>`).join("")}</div>
            <button class="ko-btn ko-btn--ghost lba-reset" data-action="lib-reset" data-arg="${b.id}" ${s === "new" ? "disabled" : ""}>${I("rotate-ccw", "sm")}Reset</button>
          </div>

          <div class="ko-section-label">Book</div>
          <div class="ko-group">
            ${row("info", "Book information", `data-open="info" data-params='${A.attrs({ title: "Book information", icon: "info", body: Lib.infoBody(b) })}'`, chev)}
            ${row("text", "Book description", `data-open="info" data-params='${A.attrs({ title: "Book description", icon: "text", body: TextGen.synopsis(b) })}'`, chev)}
            ${row("image", "Book cover", `data-open="info" data-params='${A.attrs({ title: "Book cover", icon: "image", body: `Cover extracted from ${Lib.file(b)} · 600 × 900 px. Long-press the cover in Book information to set a custom image.` })}'`, chev)}
            ${row("library", "Collections…", `data-action="lib-replace" data-arg="lib-coll-pick" data-params='${A.attrs({ ids: [b.id] })}'`, `<span class="value">${nColl ? nColl + " collection" + (nColl > 1 ? "s" : "") : "None"}</span>${chev}`)}
            ${row("bookmark", "Bookmarks", `data-open="bookmarks" data-params='${A.attrs({ id: b.id })}'`, `<span class="value">${(b.pages % 5) + 1}</span>${chev}`)}
            ${row("file-output", "Export highlights", `data-action="lib-fm" data-arg="${hl} highlights exported to /mnt/onboard/clipboard"`, `<span class="value">${hl}</span>`)}
            ${row("app-window", "Open with…", `data-action="lib-fm" data-arg="Open with: Crengine (default) · MuPDF"`, chev)}
          </div>

          <div class="ko-section-label">Metadata & cache</div>
          <div class="ko-group">
            ${row("image-off", "Ignore cover", `data-action="lib-bk-toggle" data-arg="${b.id}|ignCover"`, App.toggle(ignC))}
            ${row("tag", "Ignore metadata", `data-action="lib-bk-toggle" data-arg="${b.id}|ignMeta"`, App.toggle(ignM))}
            ${row("refresh-cw", "Refresh cached book information", `data-action="lib-fm" data-arg="Book information refreshed"`)}
          </div>
          <div style="height:var(--sp-5)"></div>
        </div>
      </div>`;
    },
  });

  /* ================================================================ PLUS */
  A.overlay("plus", {
    layer: "popover", clear: true,
    render() {
      const r = (ic, l, attrs, sub = "", cls = "") => `<button class="ko-row ${cls}" ${attrs}>${I(ic)}<span class="label">${l}${sub ? `<span class="sub">${sub}</span>` : ""}</span></button>`;
      return `<div class="ko-popover lb-pop" style="top:74px;right:64px;width:300px">
        <div class="ko-section-label">Files</div>
        ${r("square-check", "Select files", `data-action="lib-select-start"`)}
        ${r("folder-plus", "New folder", `data-action="lib-new-folder"`)}
        ${r("clipboard-paste", "Paste", CLIP ? `data-action="lib-paste"` : "", CLIP ? `${CLIP.ids.length} item${CLIP.ids.length > 1 ? "s" : ""} · ${CLIP.op}` : "Clipboard is empty", CLIP ? "" : "disabled")}
        <div class="ko-section-label">Home folder</div>
        ${r("house", "Set as HOME folder", `data-action="lib-fm" data-arg="HOME folder set to /mnt/onboard/Books"`)}
        ${r("folder-root", "Go to HOME folder", `data-action="lib-go-home"`, "/mnt/onboard/Books")}
        ${r("shuffle", "Open random document", `data-action="lib-random"`)}
        <div class="ko-section-label">Shortcuts</div>
        ${r("folder-symlink", "Folder shortcuts", `data-action="lib-replace" data-arg="lib-shortcuts"`, `${SHORTCUTS().length} saved`)}
        ${r("bookmark-plus", "Add to folder shortcuts", `data-action="lib-add-shortcut" data-arg="${esc(String(A.current.params.path ?? "Books"))}"`)}
        <div class="ko-divider"></div>
        ${r("database-zap", "Cache book info", `data-action="lib-fm" data-arg="Extracting metadata · ${DB.BOOKS.length} books"`)}
        ${r("settings", "All settings", `data-action="lib-settings"`)}
      </div>`;
    },
  });

  /* ================================================================ SORT / VIEW / FILTER */
  function toggleRow(k) { return `<button class="ko-row" data-action="lib-tg" data-arg="${k}"><span class="label">${TOGGLES[k][0]}</span>${App.toggle(tg(k))}</button>`; }
  const stepper = (k, v, label, sub = "") => `<div class="ko-row lb-steprow"><span class="label">${label}${sub ? `<span class="sub">${sub}</span>` : ""}</span>
      <span class="ko-stepper"><button data-action="lib-step" data-arg="${k}|-1" aria-label="Less">${I("minus", "sm")}</button><span class="val num">${v}</span><button data-action="lib-step" data-arg="${k}|1" aria-label="More">${I("plus", "sm")}</button></span></div>`;
  const subRow = (ic, label, value, sub) => `<button class="ko-row" data-action="lib-sub" data-arg="${sub}">${ic ? I(ic) : ""}<span class="label">${label}</span>${value ? `<span class="value">${esc(value)}</span>` : ""}${I("chevron-right", "chev")}</button>`;
  const back = (title, to = "") => sheetHead(title, to);
  const radioRows = (list, cur, action) => list.map(([k, l]) => `<button class="ko-row" data-action="${action}" data-arg="${k}">${App.radio(cur === k)}<span class="label">${l}</span></button>`).join("");
  const mosaicSeg = (o, opts, cur) => `<span class="ko-seg lb-miniseg">${opts.map(([c, r]) => `<button class="${cur[0] === c && cur[1] === r ? "on" : ""}" data-action="lib-mosaic" data-arg="${o}|${c}|${r}">${c}×${r}</button>`).join("")}</span>`;
  /* human names for KOReader's six display modes: [layout, variant label, KOReader name] */
  const MODES = {
    grid: ["grid", "Covers", "Mosaic with cover images"], textgrid: ["grid", "Text covers", "Mosaic with text covers"],
    detail: ["list", "Details", "Detailed list with cover images and metadata"], "detail-noimg": ["list", "No covers", "Detailed list with metadata, no images"],
    list: ["list", "Filenames", "Detailed list with cover images and filenames"], classic: ["compact", "", "Classic (filename only)"],
  };
  const LAYOUTS = [["grid", "Grid", "grid"], ["list", "List", "detail"], ["compact", "Compact", "classic"]];
  const modeName = (v) => { const m = MODES[v]; return m[1] ? `${LAYOUTS.find((l) => l[0] === m[0])[1]} · ${m[1]}` : "Compact"; };
  const illo = (k) => k === "grid"
    ? `<span class="lbv-illo g">${"<i><b></b><s></s></i>".repeat(6)}</span>`
    : k === "list" ? `<span class="lbv-illo l">${"<i><b></b><s></s><s></s></i>".repeat(3)}</span>`
    : `<span class="lbv-illo c">${"<i><b></b><s></s></i>".repeat(5)}</span>`;
  const segOpts = (opts, cur, action) => `<div class="ko-seg lbv-seg">${opts.map(([k, l]) => `<button class="${cur === k ? "on" : ""}" data-action="${action}" data-arg="${k}">${cur === k ? I("check", "sm") : ""}${l}</button>`).join("")}</div>`;
  const QUICK_SORTS = [["name", "Name"], ["authors", "Author"], ["access", "Recently read"], ["date", "Added"], ["pct_last", "Progress"]];
  const sheetHead = (title, back, right = "") => `<div class="ko-sheet-head lbv-head">${back !== undefined ? `<button class="ko-icon-btn lbv-back" data-action="lib-sub" data-arg="${back}" aria-label="Back">${I("chevron-left")}</button>` : ""}<span class="title">${title}</span>${right}<button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button></div>`;
  const SUBS = {
    "": () => {
      const v = Lib.view(A.current.params), [lay] = MODES[v], f = filters(), sk = sortKey(), rev = tg("reverse");
      const variants = lay === "grid" ? [["grid", "Covers"], ["textgrid", "Text covers"]] : lay === "list" ? [["detail", "Details"], ["detail-noimg", "No covers"], ["list", "Filenames"]] : null;
      const per = lay === "grid"
        ? `<div class="lbv-row"><span class="label">Covers per page</span>${segOpts([["2x2", "4"], ["3x2", "6"], ["3x3", "9"], ["4x3", "12"]], num("mosaicP").join("x"), "lib-per-grid")}</div>`
        : lay === "list" ? `<div class="lbv-row"><span class="label">Books per page</span>${segOpts([[6, "6"], [8, "8"], [10, "10"], [12, "12"]].map(([a, b]) => [String(a), b]), String(num("listItems")), "lib-per-list")}</div>`
        : `<div class="lbv-row"><span class="label">Files per page</span>${segOpts([[10, "10"], [14, "14"], [18, "18"], [22, "22"]].map(([a, b]) => [String(a), b]), String(num("classicItems")), "lib-per-classic")}</div>`;
      const quickOn = QUICK_SORTS.some((q) => q[0] === sk);
      const chip = (on, attrs, label, extra = "") => `<button class="ko-chip lbv-chip ${on ? "on" : ""}" ${attrs}>${on ? I("check", "sm") : ""}${label}${extra}</button>`;
      return `${sheetHead("View", undefined, `<button class="ko-link" data-action="lib-sort-reset">Reset</button>`)}
      <div class="ko-scroll lbv-body">
        <div class="ko-eyebrow lbv-lbl">Layout</div>
        <div class="lbv-tiles">${LAYOUTS.map(([k, l, def]) => `<button class="ko-card ko-card--tap lbv-tile ${lay === k ? "on" : ""}" data-action="lib-view" data-arg="${lay === k ? v : def}" aria-pressed="${lay === k}">
            ${illo(k)}<span class="n">${l}</span>${lay === k ? `<span class="ko-selmark lbv-badge">${I("check", "sm")}</span>` : ""}</button>`).join("")}</div>
        ${variants ? `<div class="lbv-row">${segOpts(variants, v, "lib-view")}</div>` : `<div class="lbv-help">File names only, the densest view.</div>`}
        ${per}
        <div class="ko-eyebrow lbv-lbl">Sort by</div>
        <div class="lbv-sortrow">
          <div class="lbv-chips">${QUICK_SORTS.map(([k, l]) => chip(sk === k, `data-action="lib-sort" data-arg="${k}"`, l)).join("")}
            ${chip(!quickOn, `data-action="lib-sub" data-arg="sort"`, quickOn ? "More" : esc(sortLabel()), I("chevron-right", "sm"))}</div>
          <button class="lbv-dir" data-action="lib-tg" data-arg="reverse" aria-label="${rev ? "Descending" : "Ascending"}" title="${rev ? "Descending" : "Ascending"}">${I(rev ? "arrow-up-wide-narrow" : "arrow-down-narrow-wide")}<span>${rev ? "Z–A" : "A–Z"}</span></button>
        </div>
        <div class="ko-eyebrow lbv-lbl">Show</div>
        <div class="lbv-chips scroll">${chip(!f.length, `data-action="lib-filter" data-arg="all"`, "All books")}${["new", "reading", "onhold", "finished"].map((k) => chip(f.includes(k), `data-action="lib-filter" data-arg="${k}"`, Lib.statusLabel[k])).join("")}</div>
        <div class="ko-group lbv-group">
          <button class="ko-row" data-action="lib-tg" data-arg="mixed">${I("folders")}<span class="label">Mix folders and files</span>${App.toggle(tg("mixed"))}</button>
          <button class="ko-row" data-action="lib-sub" data-arg="more">${I("sliders-horizontal")}<span class="label">More library settings</span>${I("chevron-right", "chev")}</button>
        </div>
      </div>`;
    },
    more: () => `${sheetHead("Library settings", "")}
      <div class="ko-scroll lbv-body">
        <div class="ko-eyebrow lbv-lbl">Opening</div>
        <div class="ko-group lbv-group">
          ${subRow("door-open", "Start with", STARTS.find((x) => x[0] === A.get("lib.start", "filebrowser"))[1], "start")}
        </div>
        <div class="ko-eyebrow lbv-lbl">Layout in other views</div>
        <div class="ko-group lbv-group">
          <button class="ko-row" data-action="lib-tg" data-arg="everywhere">${I("copy-check")}<span class="label">Use this layout everywhere<span class="sub">${esc(modeName(Lib.view(A.current.params)))} in History and Collections too</span></span>${App.toggle(tg("everywhere"))}</button>
          ${tg("everywhere") ? "" : `${subRow("history", "History layout", modeName(A.get("fb.histView", "grid")), "hist-layout")}${subRow("library", "Collections layout", modeName(A.get("fb.collView", "grid")), "coll-layout")}`}
        </div>
        <div class="ko-eyebrow lbv-lbl">File browser</div>
        <div class="ko-group lbv-group">
          ${subRow("sliders-horizontal", "File browser settings", "", "settings")}
          ${subRow("layout-grid", "Grid and list settings", "", "mosaic")}
          ${subRow("list", "Compact list settings", "", "classic")}
          ${subRow("clock", "History settings", "", "history")}
          ${subRow("house", "Home folder", "", "home")}
        </div>
      </div>`,
    "hist-layout": () => layoutPick("History layout", "fb.histView"),
    "coll-layout": () => layoutPick("Collections layout", "fb.collView"),
    display: () => SUBS["hist-layout"](),
    sort: () => `${back("Sort by")}
      <div class="ko-group lbv-group lbv-top">${toggleRow("reverse")}</div>
      <div class="ko-section-label">File</div>${radioRows(SORTS.filter((s) => !s[2]), sortKey(), "lib-sort")}
      <div class="ko-section-label">Book metadata</div>${radioRows(SORTS.filter((s) => s[2]), sortKey(), "lib-sort")}`,
    start: () => `${back("Start with", "more")}${radioRows(STARTS, A.get("lib.start", "filebrowser"), "lib-start")}`,
    settings: () => `${back("File browser settings", "more")}
      ${toggleRow("subfolders")}${toggleRow("hidden")}${toggleRow("unsupported")}
      <div class="ko-divider"></div>
      ${subRow("layout-grid", "Mosaic and detailed list settings", "", "mosaic")}
      ${subRow("list", "Classic mode settings", "", "classic")}
      ${subRow("history", "History settings", "", "history")}
      ${subRow("house", "Home folder settings", "", "home")}
      <div class="ko-divider"></div>
      ${toggleRow("askOpen")}${toggleRow("parent")}${toggleRow("collMark")}
      ${stepper("infoItems", `${num("infoItems")} / 9`, "Info lists items per page")}`,
    mosaic: () => `${back("Grid and list settings", "more")}
      <div class="ko-section-label">Items per page</div>
      <div class="ko-row lb-steprow"><span class="label">Portrait mosaic</span>${mosaicSeg("P", [[2, 2], [3, 2], [3, 3], [4, 3]], num("mosaicP"))}</div>
      <div class="ko-row lb-steprow"><span class="label">Landscape mosaic</span>${mosaicSeg("L", [[4, 2], [5, 2], [6, 2], [6, 3]], num("mosaicL"))}</div>
      ${stepper("listItems", num("listItems"), "Portrait list mode")}
      <div class="ko-divider"></div>
      ${toggleRow("shrinkMosaic")}${toggleRow("fileProps")}${toggleRow("flash")}
      <div class="ko-section-label">Progress</div>${["progMosaic", "progList", "pagesRead", "pagesLeft"].map(toggleRow).join("")}
      <div class="ko-section-label">Display hints</div>${["hintDesc", "hintHist", "hintColl"].map(toggleRow).join("")}
      <div class="ko-section-label">Series</div>${radioRows([["none", "Do not show series metadata"], ["line", "Show series metadata in separate line"], ["title", "Append series metadata to title"], ["authors", "Append series metadata to authors"]], A.get("fb.series", "line"), "lib-series")}
      <div class="ko-section-label">Book info cache</div>
      <div class="ko-row">${I("database")}<span class="label">Current cache size<span class="sub">561.2 kB · 2 books</span></span></div>
      <button class="ko-row" data-action="lib-fm" data-arg="Cache pruned">${I("scissors")}<span class="label">Prune cache of removed books</span></button>
      <button class="ko-row" data-action="lib-fm" data-arg="Cache database compacted">${I("archive")}<span class="label">Compact cache database</span></button>
      <button class="ko-row lb-danger" data-action="lib-fm" data-arg="Cache database deleted">${I("trash-2")}<span class="label">Delete cache database</span></button>`,
    classic: () => `${back("Compact list (classic mode)", "more")}
      ${stepper("classicItems", num("classicItems"), "Items per page")}
      ${stepper("classicFont", num("classicFont"), "Item font size")}
      ${toggleRow("shrinkClassic")}${toggleRow("boldOpened")}${toggleRow("boldNew")}`,
    history: () => `${back("History settings", "more")}
      ${toggleRow("shortDate")}${toggleRow("freeze")}
      <button class="ko-row" data-action="lib-clear-deleted">${I("trash")}<span class="label">Clear history of deleted files</span></button>
      ${toggleRow("autoRemove")}${toggleRow("showFilename")}`,
    home: () => `${back("Home folder", "more")}
      <button class="ko-row" data-action="lib-fm" data-arg="Choose a folder, then tap “Use this folder”">${I("house")}<span class="label">Set home folder<span class="sub">/mnt/onboard/Books</span></span>${I("chevron-right", "chev")}</button>
      ${toggleRow("shortHome")}${toggleRow("lockHome")}`,
  };
  function layoutPick(title, key) {
    const cur = A.get(key, "grid");
    return `${sheetHead(title, "more")}<div class="ko-scroll lbv-body"><div class="ko-group lbv-group">
      ${Object.entries(MODES).map(([k, m]) => `<button class="ko-row" data-action="lib-setview" data-arg="${key}|${k}">${App.radio(cur === k)}<span class="label">${modeName(k)}<span class="sub">KOReader: ${m[2]}</span></span></button>`).join("")}
    </div></div>`;
  }
  /* sub-pages that still use the older popover markup get wrapped for the sheet */
  A.overlay("sort", {
    layer: "sheet",
    render: (p) => {
      const sub = p.sub || "";
      const html = (SUBS[sub] || SUBS[""])();
      const native = ["", "more", "hist-layout", "coll-layout", "display"].includes(sub);
      const cut = html.indexOf("</div>") + 6;  // legacy pages start with the shared header
      return `<div class="ko-sheet lbv">${native ? `<div class="grip"></div>${html}` : `<div class="grip"></div>${html.slice(0, cut)}<div class="ko-scroll lbv-body lbv-legacy">${html.slice(cut)}</div>`}</div>`;
    },
  });

  /* ================================================================ BOOK STATUS */
  A.overlay("book-status", {
    layer: "sheet",
    render(p) {
      const ids = p.ids || [p.id || "animal-farm"];
      const b = DB.book(ids[0]), s = Lib.status(b), multi = ids.length > 1;
      const review = A.get(`bk.${b.id}.review`, b.id === "dracula" ? "Atmospheric and slow in the middle, but the final chase across the Carpathians is wonderful." : "");
      return `<div class="ko-sheet lbs">
        <div class="grip"></div>
        <div class="ko-sheet-head"><span class="title">${multi ? `Mark ${ids.length} books as…` : "Book status"}</span><button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button></div>
        <div class="lbs-body">
          ${multi ? `<div class="lbs-covers">${ids.slice(0, 6).map((id) => `<div>${Cover.html(DB.book(id))}</div>`).join("")}</div>` : `
          <div class="lba-head flat"><div class="lba-cov">${Cover.html(b)}</div><div class="grow"><div class="t ellipsis"${Lib.lang(b)}>${esc(b.title)}</div><div class="f ellipsis"${Lib.lang(b)}>${esc(Lib.author(b))}</div>
            <div class="m">${Lib.pct(b)}% read · ${b.pages} pages</div></div></div>`}
          <div class="ko-eyebrow lbs-lbl">Status</div>
          <div class="lbs-status">${["new", "reading", "onhold", "finished"].map((k) => `<button class="ko-card ko-card--sm ko-card--tap ${!multi && s === k ? "on" : ""}" data-action="lib-status" data-arg="${ids.join(",")}|${k}">${I(!multi && s === k ? "circle-check" : Lib.statusIcon[k])}<span>${k === "new" ? "Not started" : Lib.statusLabel[k]}</span></button>`).join("")}</div>
          ${multi ? "" : `<div class="ko-eyebrow lbs-lbl">Rating</div>
          <div class="lbs-rate">${Lib.stars(Lib.rating(b), b.id, "lg")}<span class="faint">${["Tap a star to rate", "Didn't like it", "It was OK", "Liked it", "Really liked it", "Loved it"][Lib.rating(b)]}</span></div>
          <div class="ko-eyebrow lbs-lbl">Review</div>
          <button class="lbs-review" data-open="input" data-params='${A.attrs({ title: "Review", hint: "Write a few words about this book…", value: review, ok: "Save", action: "lib-review", arg: b.id })}'>${review ? esc(review) : `<span class="faint">Write a few words about this book…</span>`}${I("pencil-line", "sm")}</button>`}
        </div>
        <div class="lbs-foot"><button class="ko-btn ko-btn--ghost" data-close>Cancel</button><button class="ko-btn ko-btn--primary" data-action="lib-status-done">Done</button></div>
      </div>`;
    },
  });

  /* ================================================================ COLLECTION overlays */
  A.overlay("lib-coll-pick", {
    layer: "sheet",
    render(p) {
      const ids = p.ids || [];
      const cols = Lib.collections();
      return `<div class="ko-sheet lbs">
        <div class="grip"></div>
        <div class="ko-sheet-head"><span class="title">Add to collections</span><span class="faint">${ids.length} book${ids.length === 1 ? "" : "s"}</span><button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button></div>
        <div class="ko-scroll"><div class="ko-group lb-pickgroup">
          ${cols.map((c) => { const on = ids.length && ids.every((id) => c.ids.includes(id)); return `<button class="ko-row" data-action="lib-coll-toggle" data-arg="${esc(c.name)}">${App.check(on)}<span class="lb-pickstack">${stack(c.ids)}</span><span class="label">${esc(c.name)}<span class="sub">${c.ids.length} books</span></span></button>`; }).join("")}
        </div></div>
        <div class="lbs-foot"><button class="ko-btn ko-btn--ghost" data-action="lib-replace" data-arg="lib-coll-new">${I("plus", "sm")}New collection</button><span class="grow"></span><button class="ko-btn ko-btn--primary" data-close>Done</button></div>
      </div>`;
    },
  });
  A.overlay("lib-coll-new", {
    layer: "dialog",
    render: (p) => UI.dialog({
      cls: "lb-dlg", title: p.rename ? "Rename collection" : "New collection",
      bodyHtml: UI.input({ placeholder: "Collection name", value: p.rename || "" }) + (p.rename ? "" : UI.checkRow({ label: "Add books after creating", on: true, attrs: { action: "lib-dlg-check" } })),
      actions: [{ label: "Cancel", kind: "ghost", attrs: "data-close" }, { label: p.rename ? "Rename" : "Create", kind: "primary", attrs: { action: "lib-coll-created", arg: p.rename ? "Collection renamed" : "Collection created" } }],
    }),
  });
  A.overlay("lib-coll-menu", {
    layer: "popover", clear: true,
    render(p) {
      const mode = A.get("lib.collSort", "manual");
      if (p.at === "sort") return `<div class="ko-popover lb-pop" style="top:150px;right:16px;width:270px">
          <div class="ko-section-label">Sort collections</div>
          ${radioRows([["manual", "Manual order"], ["name", "Name"], ["size", "Number of books"]], mode, "lib-coll-sort")}
          <div class="ko-divider"></div>
          <button class="ko-row" data-action="lib-fm" data-arg="Drag the handles to reorder">${I("grip-vertical")}<span class="label">Arrange manually…</span></button></div>`;
      const n = p.name || "To read this winter", fav = n === "Favorites";
      return `<div class="ko-popover lb-pop" style="${p.at === "card" ? "top:50%;left:50%;transform:translate(-50%,-50%)" : "top:74px;right:16px"};width:290px">
        <div class="ko-section-label ellipsis">${esc(n)}</div>
        ${p.at === "card" ? `<button class="ko-row" data-go="collection" data-params='${A.attrs({ name: n })}'>${I("library")}<span class="label">Open collection</span></button>` : ""}
        <button class="ko-row" data-action="lib-fm" data-arg="Pick books to add to “${esc(n)}”">${I("list-plus")}<span class="label">Add books…</span></button>
        <button class="ko-row" data-action="lib-fm" data-arg="Pick a folder to add">${I("folder-plus")}<span class="label">Add a folder…</span></button>
        <button class="ko-row" data-action="lib-fm" data-arg="Tap books to remove them">${I("list-minus")}<span class="label">Remove books…</span></button>
        <div class="ko-section-label">Order of books</div>
        ${radioRows([["manual", "Manual order"], ["name", "Title"], ["read", "Last read"]], A.get("lib.collBookSort", "manual"), "lib-coll-booksort")}
        <div class="ko-divider"></div>
        <button class="ko-row ${fav ? "disabled" : ""}" data-action="lib-replace" data-arg="lib-coll-new" data-params='${A.attrs({ rename: n })}'>${I("pencil-line")}<span class="label">Rename</span></button>
        <button class="ko-row lb-danger ${fav ? "disabled" : ""}" data-action="lib-coll-delete" data-arg="${esc(n)}">${I("trash-2")}<span class="label">Delete collection</span></button>
      </div>`;
    },
  });
  A.overlay("lib-shortcuts", {
    layer: "popover", clear: true,
    render: () => `<div class="ko-popover lb-pop" style="top:74px;right:64px;width:320px">
      <div class="lb-pophead"><span class="t">Folder shortcuts</span><span class="spacer"></span><button class="ko-link" data-action="lib-add-shortcut" data-arg="${esc(String(A.current.params.path ?? "Books/Mystery"))}">${I("plus", "sm")}Add current</button></div>
      ${SHORTCUTS().map((s) => `<div class="ko-row lb-scrow" data-go="folder" data-params='${A.attrs({ path: s })}'>${I(s === "Books" ? "house" : "folder-symlink")}<span class="label"><span dir="auto">${esc(s.split("/").pop())}</span><span class="sub" dir="ltr">/mnt/onboard/${esc(s)}</span></span>
        <button class="ko-icon-btn" data-action="lib-rm-shortcut" data-arg="${esc(s)}" aria-label="Remove">${I("x", "sm")}</button></div>`).join("")}
    </div>`,
  });

  /* ================================================================ ACTIONS */
  const parts = (el) => (el.dataset.arg || "").split("|");
  A.action("lib-book", (el) => {
    const id = el.dataset.arg;
    if (A.current.name === "library" && A.current.params.select) { selSet(); SEL.has(id) ? SEL.delete(id) : SEL.add(id); A.refresh(); return; }
    A.open("book-details", { id });
  });
  A.action("lib-read", (el) => A.go("reader", { id: el.dataset.arg }));
  A.action("lib-view", (el) => {
    const v = el.dataset.arg; A.set("lib.view", v);
    if (A.current.params.view) A.current = { name: A.current.name, params: { ...A.current.params, view: v, page: 1 } };
    A.refresh(); A.syncHash();
  });
  A.action("lib-status", (el) => {
    const [ids, k] = parts(el);
    ids.split(",").forEach((id) => A.set(`bk.${id}.status`, k));
    A.toast(`Marked as ${k === "new" ? "not started" : Lib.statusLabel[k].toLowerCase()}`); A.refresh();
  });
  A.action("lib-status-done", () => { A.close(); if (A.current.params.select) { const p = { ...A.current.params }; delete p.select; SEL = null; A.go("library", p); } });
  A.action("lib-reset", (el) => { const id = el.dataset.arg; A.set(`bk.${id}.status`, "new"); A.set(`bk.${id}.rating`, 0); A.toast("Reading progress reset"); A.refresh(); });
  A.action("lib-rate", (el) => { const [id, n] = parts(el); const b = DB.book(id); A.set(`bk.${id}.rating`, Lib.rating(b) === +n ? 0 : +n); A.refresh(); });
  A.action("lib-fav", (el) => { const b = DB.book(el.dataset.arg); A.set(`bk.${b.id}.fav`, !Lib.fav(b)); A.toast(Lib.fav(b) ? "Added to Favorites" : "Removed from Favorites"); A.refresh(); });
  A.action("lib-bk-toggle", (el) => { const [id, k] = parts(el); A.set(`bk.${id}.${k}`, !A.get(`bk.${id}.${k}`, false)); A.refresh(); });
  A.action("lib-review", (el, val, ctx) => { const id = ctx?.params?.arg || el?.dataset?.arg; if (id && typeof val === "string") A.set(`bk.${id}.review`, val); A.close(); A.toast("Review saved"); A.refresh(); });
  A.action("lib-fm", (el) => { A.closeAll(); A.toast(el.dataset.arg || "Done"); });
  A.action("lib-replace", (el) => { let p = {}; try { p = JSON.parse(el.dataset.params || "{}"); } catch {} A.replaceTop(el.dataset.arg, p); });
  A.action("lib-settings", () => A.go("settings", {}));
  A.action("lib-dlg-check", (el) => { const c = el.querySelector(".ko-check"); const on = !c.classList.contains("on"); c.classList.toggle("on", on); c.innerHTML = on ? I("check", "sm") : ""; A.icons(); });
  A.action("lib-clip", (el) => { const [op, id] = parts(el); CLIP = { op, ids: [id] }; A.closeAll(); A.toast(`${op === "cut" ? "Cut" : "Copied"} · ${Lib.file(DB.book(id))}`); });
  A.action("lib-paste", () => { const n = CLIP?.ids.length || 0; CLIP = null; A.closeAll(); A.toast(`Pasted ${n} item${n > 1 ? "s" : ""} here`); });
  A.action("lib-rename", (el) => { const b = DB.book(el.dataset.arg); A.replaceTop("input", { title: "Rename file", hint: "File name", value: Lib.file(b), ok: "Rename", action: "lib-renamed", arg: b.id }); });
  A.action("lib-renamed", () => { A.closeAll(); A.toast("File renamed"); });
  A.action("lib-delete", (el) => { const b = DB.book(el.dataset.arg); A.replaceTop("confirm", { title: "Delete this book?", body: `“${Lib.file(b)}” and its reading progress, highlights and bookmarks will be permanently removed from the device.`, ok: "Delete", danger: true, action: "lib-deleted", arg: b.id }); });
  A.action("lib-deleted", () => { A.closeAll(); A.toast("Deleted"); });
  A.action("lib-new-folder", () => A.replaceTop("input", { title: "New folder", hint: "Folder name", value: "", ok: "Create", action: "lib-folder-created", checkbox: "Enter folder after creation", checked: true }));
  A.action("lib-folder-created", () => { A.closeAll(); A.toast("Folder created"); });
  A.action("lib-go-home", () => A.go("folder", { path: "Books" }));
  A.action("lib-random", () => { const pool = DB.BOOKS.filter((b) => Lib.status(b) !== "finished"); A.closeAll(); A.open("book-details", { id: pool[Math.floor(Math.random() * pool.length)].id }); });
  A.action("lib-add-shortcut", (el) => { const p = el.dataset.arg || "Books"; const s = SHORTCUTS(); if (!s.includes(p)) A.set("lib.shortcuts", [...s, p]); A.toast(`“${p.split("/").pop() || "onboard"}” is in folder shortcuts`); A.refresh(); });
  A.action("lib-rm-shortcut", (el, ev) => { ev?.stopPropagation(); A.set("lib.shortcuts", SHORTCUTS().filter((s) => s !== el.dataset.arg)); A.refresh(); });
  A.action("lib-clear-history", () => (A.top() ? A.replaceTop : A.open)("confirm", { title: "Clear history?", body: "All books will be removed from your reading history. Reading progress, highlights and bookmarks are kept.", ok: "Clear history", danger: true, action: "lib-history-cleared" }));
  A.action("lib-history-cleared", () => { A.closeAll(); A.toast("History cleared"); });
  A.action("lib-clear-deleted", () => { A.closeAll(); A.toast(`Removed ${DELETED.length} deleted files from history`); });
  A.action("lib-clear-filter", () => { A.set("lib.filter", []); A.refresh(); });
  /* selection */
  A.action("lib-select-start", (el) => { SEL = new Set(el.dataset.arg ? [el.dataset.arg] : []); const p = A.current.name === "library" ? A.current.params : {}; A.go("library", { ...p, tab: p.tab === "favorites" ? "favorites" : "library", select: 1 }); });
  A.action("lib-sel-exit", () => { SEL = null; const p = { ...A.current.params }; delete p.select; A.go("library", p); });
  A.action("lib-sel-all", () => { const all = (A.current.params.tab === "favorites" ? DB.BOOKS.filter(Lib.fav) : filtered(DB.BOOKS)).map((b) => b.id); SEL = SEL.size === all.length ? new Set() : new Set(all); A.refresh(); });
  A.action("lib-sel-op", (el) => {
    const op = el.dataset.arg, ids = [...SEL], n = ids.length;
    if (op === "copy" || op === "cut") { CLIP = { op, ids }; A.toast(`${n} book${n > 1 ? "s" : ""} ${op === "cut" ? "cut" : "copied"} · open a folder and Paste`); }
    else if (op === "delete") A.open("confirm", { title: `Delete ${n} book${n > 1 ? "s" : ""}?`, body: "The files and their reading progress, highlights and bookmarks will be permanently removed.", ok: "Delete", danger: true, action: "lib-deleted" });
    else if (op === "move") { CLIP = { op: "cut", ids }; A.go("folder", { path: "Books" }); A.toast("Open the destination folder, then Paste"); }
    else if (op === "coll") A.open("lib-coll-pick", { ids });
    else if (op === "mark") A.open("book-status", { ids });
  });
  /* sort popover navigation + settings */
  A.action("lib-sub", (el) => { const top = A.top(); const keep = top && top.name === "sort" ? top.params : {}; A.replaceTop("sort", { ...keep, sub: el.dataset.arg }); });
  A.action("lib-sort", (el) => { A.set("lib.sort", el.dataset.arg); A.refresh(); });
  A.action("lib-start", (el) => { A.set("lib.start", el.dataset.arg); A.refresh(); });
  A.action("lib-series", (el) => { A.set("fb.series", el.dataset.arg); A.refresh(); });
  A.action("lib-tg", (el) => { const k = el.dataset.arg; A.set("fb." + k, !tg(k)); A.refresh(); });
  A.action("lib-step", (el) => { const [k, d] = parts(el); const lim = { listItems: [4, 16], classicItems: [6, 30], classicFont: [12, 30], infoItems: [6, 24] }[k]; A.set("fb." + k, Math.max(lim[0], Math.min(lim[1], num(k) + +d))); A.refresh(); });
  A.action("lib-mosaic", (el) => { const [o, c, r] = parts(el); A.set(o === "P" ? "fb.mosaicP" : "fb.mosaicL", [+c, +r]); A.refresh(); });
  A.action("lib-filter", (el) => {
    const k = el.dataset.arg; let f = filters();
    f = k === "all" ? [] : f.includes(k) ? f.filter((x) => x !== k) : [...f, k];
    A.set("lib.filter", f); A.refresh();
  });
  A.action("lib-per-grid", (el) => { A.set("fb.mosaicP", el.dataset.arg.split("x").map(Number)); A.refresh(); });
  A.action("lib-per-list", (el) => { A.set("fb.listItems", +el.dataset.arg); A.refresh(); });
  A.action("lib-per-classic", (el) => { A.set("fb.classicItems", +el.dataset.arg); A.refresh(); });
  A.action("lib-setview", (el) => { const [k, v] = parts(el); A.set(k, v); A.refresh(); });
  A.action("lib-sort-reset", () => { ["lib.sort", "lib.filter", "fb.reverse", "fb.mixed"].forEach((k) => delete A.store[k]); A.save(); A.refresh(); });
  /* collections */
  A.action("lib-coll-toggle", (el) => { const c = el.querySelector(".ko-check"); if (c) { const on = !c.classList.contains("on"); c.classList.toggle("on", on); c.innerHTML = on ? I("check", "sm") : ""; A.icons(); A.toast(`${on ? "Added to" : "Removed from"} “${el.dataset.arg}”`); } });
  A.action("lib-coll-sort", (el) => { A.set("lib.collSort", el.dataset.arg); A.refresh(); });
  A.action("lib-coll-booksort", (el) => { A.set("lib.collBookSort", el.dataset.arg); A.refresh(); });
  A.action("lib-coll-created", (el) => { A.closeAll(); A.toast(el.dataset.arg); });
  A.action("lib-coll-delete", (el) => A.replaceTop("confirm", { title: "Delete collection?", body: `“${el.dataset.arg}” will be removed. The books themselves stay in your library.`, ok: "Delete", danger: true, action: "lib-coll-deleted" }));
  A.action("lib-coll-deleted", () => { A.closeAll(); A.toast("Collection deleted"); });

  /* long-press (contextmenu / touch hold) on any [data-book] opens book-actions */
  let holdT = null, held = false;
  document.addEventListener("contextmenu", (ev) => {
    const el = ev.target.closest("[data-book]"); if (!el || !el.closest(".ko-screen")) return;
    ev.preventDefault(); clearTimeout(holdT); A.open("book-actions", { id: el.dataset.book });
  });
  document.addEventListener("pointerdown", (ev) => {
    const el = ev.target.closest("[data-book]"); if (!el || ev.button !== 0 || !el.closest(".ko-screen") || ev.target.closest(".lb-more")) return;
    held = false; clearTimeout(holdT);
    holdT = setTimeout(() => { held = true; A.open("book-actions", { id: el.dataset.book }); }, 600);
  });
  ["pointerup", "pointercancel"].forEach((t) => document.addEventListener(t, () => clearTimeout(holdT)));
  document.addEventListener("click", (ev) => { if (held) { held = false; ev.stopPropagation(); ev.preventDefault(); } }, true);

  /* ================================================================ DEMOS */
  const G = "Home & Library";
  [
    ["Library · mosaic", "#/library?tab=library&view=grid"],
    ["Library · mosaic page 2", "#/library?tab=library&view=grid&page=2"],
    ["Library · mosaic, text covers", "#/library?tab=library&view=textgrid"],
    ["Library · detailed list", "#/library?tab=library&view=detail"],
    ["Library · detailed list, no images", "#/library?tab=library&view=detail-noimg"],
    ["Library · list with filenames", "#/library?tab=library&view=list"],
    ["Library · classic (filename only)", "#/library?tab=library&view=classic"],
    ["Library · select mode", "#/library?tab=library&view=grid&select=1"],
    ["Favorites tab", "#/library?tab=favorites&view=grid"],
    ["Collections tab", "#/library?tab=collections"],
    ["Collection · To read this winter", "#/collection?name=To%20read%20this%20winter&view=grid"],
    ["Collection · manage menu", "#/collection?name=Sherlock%20Holmes&view=grid&o=lib-coll-menu&o.name=Sherlock%20Holmes"],
    ["Add to collections", "#/library?tab=library&view=grid&o=lib-coll-pick&o.ids=%5B%22frankenstein%22%5D"],
    ["New collection", "#/library?tab=collections&o=lib-coll-new"],
    ["Folders tab", "#/library?tab=folders&path=Books"],
    ["Folder browser · Classics", "#/folder?path=Books%2FClassics"],
    ["Folder browser · storage root", "#/folder?path="],
    ["Folder shortcuts", "#/folder?path=Books&o=lib-shortcuts"],
    ["History", "#/history"],
    ["History · finished", "#/history?filter=finished"],
    ["History · options", "#/history?o=lib-hist-menu"],
    ["Book details · Animal Farm", "#/library?view=grid&o=book-details&o.id=animal-farm"],
    ["Book details · Arabic (Al-Mutanabbi)", "#/library?view=grid&o=book-details&o.id=ar-poems"],
    ["Book details · series, not started", "#/library?view=grid&o=book-details&o.id=sherlock-3"],
    ["Book details · finished", "#/library?view=grid&o=book-details&o.id=dracula"],
    ["Book actions (long-press)", "#/library?view=grid&o=book-actions&o.id=animal-farm"],
    ["Book status", "#/library?view=grid&o=book-status&o.id=dracula"],
    ["Plus menu", "#/library?view=grid&o=plus"],
    ["View sheet · grid", "#/library?view=grid&o=sort"],
    ["View sheet · list", "#/library?view=detail&o=sort"],
    ["View sheet · all sort modes", "#/library?view=grid&o=sort&o.sub=sort"],
    ["View sheet · more library settings", "#/library?view=grid&o=sort&o.sub=more"],
    ["View sheet · history layout", "#/library?view=grid&o=sort&o.sub=hist-layout"],
    ["View sheet · file browser settings", "#/library?view=grid&o=sort&o.sub=settings"],
    ["View sheet · grid & list settings", "#/library?view=grid&o=sort&o.sub=mosaic"],
  ].forEach(([l, h]) => A.demo(G, l, h));
})();
