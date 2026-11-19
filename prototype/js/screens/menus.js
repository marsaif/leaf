/* ==========================================================================
   Folio — Menus & Settings (owned by the Menus agent)

   One menu engine renders any node list from KO_MENUS (the real KOReader
   option trees) in the Folio design. It powers:
     overlay "main-menu"  {ctx:"fm"|"reader"|"reader-pdf", tab, path:[i,j,..]}
     screen  "settings"   {section, path:[sourceIdx, i, j, ..], hl, q, find}
     overlay "menu-help"  {ctx, tab, path, i}  or  {section, path, i}

   A "locator" ({ctx,tab,path} or {section,path}) addresses any node list.
   Rows carry data-i (index in that list); the list wrapper carries data-loc.
   Toggle / radio / value state lives in memory (window.MenuState), keyed by
   the tab icon + the chain of raw texts, so the top menu and the Settings
   app share state for the same option.

   window.Menus exposes the engine (used by the coverage check).
   ========================================================================== */
(function () {
  const KM = window.KO_MENUS || {};
  const SHARED = KM.shared || {};
  const esc = App.esc, icon = App.icon;

  /* ---------------------------------------------------------------- data */
  const TREES = { fm: "fm_menu", reader: "reader_menu", "reader-pdf": "reader_menu_pdf" };
  const treeOf = (ctx) => KM[TREES[ctx] || "reader_menu"] || [];
  const TAB_META = {
    "appbar.filebrowser": { key: "library", label: "Library", icon: "library-big", blurb: "Browse, sort and filter your books" },
    "appbar.navigation": { key: "navigation", label: "Navigation", icon: "compass", blurb: "Move around this book" },
    "appbar.typeset": { key: "typeset", label: "Typesetting", icon: "type", blurb: "Styles, fonts and typography" },
    "appbar.settings": { key: "settings", label: "Settings", icon: "settings-2", blurb: "Screen, gestures, device and more" },
    "appbar.tools": { key: "tools", label: "Tools", icon: "wrench", blurb: "Plugins, sync and utilities" },
    "appbar.search": { key: "search", label: "Search", icon: "search", blurb: "Dictionaries, Wikipedia, full text" },
    "appbar.menu": { key: "menu", label: "Main menu", icon: "menu", blurb: "History, help and exit" },
  };
  const tabsOf = (ctx) => treeOf(ctx).map((t) => ({ ...(TAB_META[t.icon] || { key: t.icon, label: t.icon, icon: "circle" }), id: t.icon, items: t.items }));
  const isRef = (it) => it && !Array.isArray(it) && typeof it === "object";
  const kids = (n) => { const it = n && n.items; if (!it) return []; if (Array.isArray(it)) return it; return it.ref && SHARED[it.ref] ? SHARED[it.ref] : []; };
  const isSub = (n) => n.kind === "submenu" || "items" in n;
  const normPath = (p) => {
    if (Array.isArray(p)) return p.map(Number).filter((x) => !isNaN(x));
    if (typeof p === "number") return [p];
    if (typeof p === "string" && p !== "") return p.split(/[.,\s]+/).map(Number).filter((x) => !isNaN(x));
    return [];
  };

  /* ---------------------------------------------------------- label parse */
  const PUA = /[\ue000-\uf8ff\ufffd\u2066-\u2069]/g;
  /** engineering labels shown with a human name; the KOReader name stays visible as small help text */
  const HUMAN = {
    "Speed reading module - perception expander": "Speed-reading guide",
    "Cloud storage+": "Cloud storage (extended)",
    "Hide non-linear fragments": "Skip non-linear sections",
    "Screen DPI": "Screen density",
    "Panel zoom (manga/comic)": "Zoom into comic panels",
  };
  const parseCache = new WeakMap();
  /** KOReader uses lowercase choice labels ("name", "last read date"); Folio capitalises them */
  const cap = (s) => (/^[a-z][a-z' ]*(\(|$|[ -])/.test(s) && !/\.[a-z]/.test(s) ? s[0].toUpperCase() + s.slice(1) : s);
  /** "Sort by: name" -> {label:"Sort by", value:"name"}; gestures "Top left   (Pass through)" -> value */
  function parse(n) {
    if (parseCache.has(n)) return parseCache.get(n);
    const raw = String(n.text ?? "");
    const star = raw.includes("★");
    const t = raw.replace(/★/g, "").replace(PUA, "").replace(/\s*\(\s*\)/g, "");  // KOReader icon-font glyphs (and the "()" they leave)
    let label = t, value = "", glyph = "";
    const sub = isSub(n), plain = !n.kind || sub;
    const g = sub && t.match(/^(.+?)\s{3,}\((.+)\)\s*$/);
    if (g) { label = g[1]; value = g[2]; }
    else {
      const m = t.match(/^(.+?)\s{3,}(.*)$/); // trailing marker glyphs (hyphenation etc.)
      if (m) { label = m[1]; if (/‐/.test(m[2])) glyph = "hyphenation"; }
      if (plain) {
        const k = label.indexOf(": ");
        if (k > 0 && k < 42) { value = label.slice(k + 2); label = label.slice(0, k); }
        else if (/\S:\s*$/.test(label)) label = label.replace(/:\s*$/, "");
        const c = sub && !value && label.match(/^(.*\S) \((\d+)\)$/);
        if (c) { label = c[1]; value = c[2] + " active"; }
      }
    }
    value = value.replace(/^\((.*)\)$/, "$1").replace(/\s+/g, " ").trim();
    label = cap(label.replace(/\s+/g, " ").trim() || raw.trim() || "(untitled)");
    value = cap(value);
    const r = { label, value, star, glyph, display: HUMAN[label] || label, ko: HUMAN[label] ? label : "" };
    parseCache.set(n, r);
    return r;
  }

  /* --------------------------------------------------------------- state */
  const ST = (window.MenuState = window.MenuState || new Map());
  const keyOf = (keyBase, n) => keyBase.concat(n.text).join("›");
  const isNightNode = (n) => n.kind === "check" && /^night mode$/i.test(String(n.text).trim());
  const themeIsDark = () => !!document.querySelector(".ko-screen.theme-dark");
  function checked(n, key) {
    if (isNightNode(n)) return themeIsDark();
    return ST.has(key) ? ST.get(key) : !!n.checked;
  }
  /** current value of a "Label: value" node: user override, else parsed */
  function valueOf(n, key) {
    if (!n) return "";
    if (ST.has(key + "#v")) return ST.get(key + "#v");
    return parse(n).value;
  }

  /* ------------------------------------------------------------- icons */
  const ICONS = {
    "night mode": "moon", network: "globe", screen: "monitor", "taps and gestures": "hand", navigation: "compass", document: "file-text",
    language: "languages", device: "tablet-smartphone", "status bar": "panel-bottom", "display mode": "layout-grid", settings: "settings-2",
    "book status": "bookmark-check", "sort by": "arrow-up-down", "reverse sorting": "arrow-down-up", "folders and files mixed": "folders",
    "start with": "play", "read timer": "timer", calibre: "library", "export highlights": "highlighter", "reading statistics": "chart-column",
    "cloud storage": "cloud", "cloud storage+": "cloud-cog", "move to archive": "archive", wallabag: "newspaper", "news downloader (rss/atom)": "rss",
    "text editor": "file-pen-line", profiles: "user-cog", "qr from clipboard": "qr-code", "more tools": "ellipsis", "progress sync": "refresh-cw",
    "dictionary lookup": "book-a", "dictionary lookup history": "history", "vocabulary builder": "graduation-cap", "wikipedia lookup": "book-open-text",
    "wikipedia history": "history", "translate current page": "languages", "fulltext search": "text-search", "last fulltext search results": "list",
    "bookmark search": "bookmark", "file search": "file-search", "last file search results": "list", "calibre metadata search": "database",
    "opds catalog": "rss", history: "history", "open last document": "book-open", "open previous document": "book-open", favorites: "star",
    collections: "layers", "bookmark browser": "bookmark", "book information": "info", help: "life-buoy", exit: "power",
    "table of contents": "list-tree", bookmarks: "bookmark", "book map": "map", "page browser": "layout-grid", "go to page": "hash",
    "skim document": "gallery-horizontal", autoturn: "timer-reset", "hide non-linear fragments": "eye-off", "go back to previous location": "undo-2",
    "go forward to next location": "redo-2", "bookmark browsing mode": "bookmark", "document settings": "file-cog", style: "palette",
    "style tweaks": "wand-sparkles", font: "type", "typography rules": "pilcrow", "page overlap": "copy",
    "speed reading module - perception expander": "zap", highlights: "highlighter", "text selection tools": "text-cursor",
    "panel zoom (manga/comic)": "zoom-in", rotation: "rotate-cw", "screen dpi": "scan", "e-ink settings": "monitor-dot",
    "auto night mode": "sunset", "color rendering": "palette", fullscreen: "maximize", notifications: "bell", "gesture manager": "hand",
    "gesture overview": "list", "gesture intervals": "timer", links: "link", "activate menu": "menu", "page turns": "book-open",
    scrolling: "mouse", "long-press on text": "text-select", keyboard: "keyboard", "time and date": "clock", "dimension units": "ruler",
    "device status alerts": "battery-warning", "screenshot folder": "camera", "alt status bar": "panel-top", "progress bar": "minus",
    "status bar items": "list-checks", "configure items": "sliders-horizontal", "status bar presets": "bookmark-plus",
    "book metadata location": "folder-cog", "save book metadata": "save", "book metadata archive": "archive", "end of document action": "flag",
    "language support plugins": "puzzle", "enable partial renderings": "layers", "additional ui fallback fonts": "a-large-small",
    "back to exit": "log-out", "back in file browser": "arrow-left", "back in reader": "arrow-left", "backspace works as back button": "delete",
    "physical buttons": "keyboard", "add opening page to location history": "map-pin", "skim dialog position": "panel-top",
    "classic mode settings": "list", "history settings": "history", "home folder settings": "house", "ask to open files": "circle-help",
    "show parent folder": "folder-up", "show collection mark": "layers", "http proxy": "server", "network info": "info",
    "plugin management": "puzzle", "patch management": "file-code", "developer options": "code", "advanced settings": "sliders-horizontal",
    "restart koreader": "rotate-ccw", "quickstart guide": "graduation-cap", "menu search": "search", "report a bug": "bug",
    version: "tag", about: "info", "system statistics": "cpu", "battery statistics": "battery", "terminal emulator": "terminal",
  };
  const iconFor = (label) => ICONS[label.toLowerCase()] || null;

  /* ------------------------------------------------------ settings model */
  const S_ = (ctx, tab, at, extra = {}) => ({ ctx, tab, at: at || [], ...extra });
  const SECTIONS = {
    display: { title: "Display & E-ink", icon: "monitor", desc: "Frontlight, contrast, refresh, rotation, DPI",
      sources: [S_("reader", "appbar.settings", [], { only: ["Night mode"], title: "Appearance" }), S_("reader", "appbar.settings", ["Screen"], { title: "Screen" })] },
    reading: { title: "Reading", icon: "book-open", desc: "Document, status bar, navigation, page turns",
      sources: [S_("reader", "appbar.settings", ["Document"], { title: "Document" }), S_("reader", "appbar.settings", ["Status bar"], { title: "Status bar" }),
        S_("reader", "appbar.settings", ["Navigation"], { title: "Navigation" }), S_("fm", "appbar.settings", ["Navigation", "Physical buttons"], { title: "Buttons in the library" }),
        S_("reader", "appbar.navigation", [], { title: "In the book" }),
        S_("reader-pdf", "appbar.navigation", [], { only: ["Bookmark browsing mode", "Settings"], title: "PDF & comics" })] },
    gestures: { title: "Taps and gestures", icon: "hand", desc: "Gesture manager, tap zones, links, long-press",
      sources: [S_("reader", "appbar.settings", ["Taps and gestures"], { title: "While reading" }), S_("fm", "appbar.settings", ["Taps and gestures"], { title: "In the library" })] },
    typography: { title: "Typography and fonts", icon: "type", desc: "Fonts, style tweaks, hyphenation, highlights",
      sources: [S_("reader", "appbar.typeset", [], { title: "Reflowable books (EPUB, FB2, TXT)" }), S_("reader-pdf", "appbar.typeset", [], { title: "Fixed layout (PDF, DjVu, comics)" })] },
    search: { title: "Search & dictionaries", icon: "book-a", desc: "Dictionaries, Wikipedia, translation, full text",
      sources: [S_("reader", "appbar.search", [], { title: "While reading" }), S_("fm", "appbar.search", [], { title: "In the library" })] },
    library: { title: "Library", icon: "library-big", desc: "Display mode, sorting, book status, start screen",
      sources: [S_("fm", "appbar.filebrowser", [], { title: "File browser" }), S_("fm", "appbar.menu", [], { only: ["History", "Favorites", "Collections", "Bookmark browser"], title: "Shortcuts" }),
        S_("reader", "appbar.menu", [], { only: ["Open previous document", "Book status", "Book information"], title: "Current book" })] },
    network: { title: "Network", icon: "wifi", desc: "Wi-Fi, proxy, network info",
      sources: [S_("reader", "appbar.settings", ["Network"], { title: "Connection" })] },
    language: { title: "Language", icon: "languages", desc: "Interface language",
      sources: [S_("reader", "appbar.settings", ["Language"], { title: "Interface language", filter: true })] },
    device: { title: "Device", icon: "tablet-smartphone", desc: "Keyboard, time, units, alerts, sleep screen",
      sources: [S_("reader", "appbar.settings", ["Device"], { title: "Device" })] },
    tools: { title: "Tools & plugins", icon: "wrench", desc: "Statistics, sync, Calibre, Wallabag, plugins",
      sources: [S_("reader", "appbar.tools", [], { title: "While reading" }), S_("fm", "appbar.tools", [], { title: "In the library" }), S_("reader-pdf", "appbar.tools", [], { title: "With a PDF open" })] },
    help: { title: "Help & about", icon: "life-buoy", desc: "Guides, bug reports, version, exit",
      sources: [S_("fm", "appbar.menu", [], { except: ["History", "Favorites", "Collections", "Bookmark browser"], title: "Folio" }), S_("reader", "appbar.menu", [], { only: ["Help", "Exit"], title: "While reading" })] },
  };
  const CLUSTERS = [
    ["Reading", ["reading", "typography", "gestures", "search"]],
    ["Device", ["display", "network", "device", "language"]],
    ["More", ["library", "tools", "help"]],
  ];
  const findChild = (items, label) => items.findIndex((n) => parse(n).label === label || String(n.text).trim() === label);
  const srcCache = new Map();
  function resolveSource(src) {
    if (srcCache.has(src)) return srcCache.get(src);
    const tab = treeOf(src.ctx).find((t) => t.icon === src.tab);
    let items = tab ? (Array.isArray(tab.items) ? tab.items : kids(tab)) : [], keyBase = [src.tab];
    for (const lbl of src.at) {
      const i = findChild(items, lbl); if (i < 0) { items = []; break; }
      keyBase = keyBase.concat(items[i].text); items = kids(items[i]);
    }
    if (src.only) items = items.filter((n) => src.only.includes(parse(n).label));
    if (src.except) items = items.filter((n) => !src.except.includes(parse(n).label));
    const r = { items, keyBase, ctx: src.ctx };
    srcCache.set(src, r);
    return r;
  }

  /* ------------------------------------------------------------ locate */
  /** loc -> {items, keyBase, chain:[{node,label}], path, crumbs, title, node} */
  function locate(loc) {
    const path = normPath(loc.path);
    let items, keyBase;
    const crumbs = [], chain = [];
    const descend = (ps) => { for (const i of ps) { const n = items[i]; if (!n) break; chain.push({ node: n, label: parse(n).display }); keyBase = keyBase.concat(n.text); items = kids(n); } };
    if (loc.section) {
      const sec = SECTIONS[loc.section] || SECTIONS.display;
      crumbs.push({ label: "Settings", depth: -2 }, { label: sec.title, depth: -1 });
      if (!path.length) return { section: sec, items: [], keyBase: [], chain, path, crumbs, title: sec.title, node: null };
      const src = sec.sources[path[0]] || sec.sources[0];
      ({ items, keyBase } = resolveSource(src));
      crumbs.push({ label: src.title || sec.title, depth: "src" });
      descend(path.slice(1));
      chain.forEach((c, d) => crumbs.push({ label: c.label, depth: d }));
      return { section: sec, src, items, keyBase, chain, path: path.slice(0, chain.length + 1), crumbs, title: chain.length ? chain[chain.length - 1].label : src.title || sec.title, node: chain.length ? chain[chain.length - 1].node : null };
    }
    const ctx = TREES[loc.ctx] ? loc.ctx : "fm";
    const tabs = tabsOf(ctx);
    const t = tabs.find((x) => x.key === loc.tab) || tabs.find((x) => kids({ items: x.items }).length) || tabs[0];
    items = kids({ items: t.items }); keyBase = [t.id];
    crumbs.push({ label: t.label, depth: -1 });
    descend(path);
    chain.forEach((c, d) => crumbs.push({ label: c.label, depth: d }));
    return { ctx, tab: t, tabs, items, keyBase, chain, path: path.slice(0, chain.length), crumbs, title: chain.length ? chain[chain.length - 1].label : t.label, node: chain.length ? chain[chain.length - 1].node : null };
  }
  const locOf = (el) => { const w = el.closest("[data-loc]"); if (!w) return null; try { return JSON.parse(w.dataset.loc); } catch { return null; } };

  /* ------------------------------------------------------------- rows */
  const NUM = /^(-?\d+(?:\.\d+)?)(\s?[^\d\s/,–×-][^/,–×]*)?$/;
  const groupsOf = (items) => {
    const groups = [[]];
    items.forEach((n, i) => { groups[groups.length - 1].push(i); if (n.separator && i < items.length - 1) groups.push([]); });
    return groups.filter((g) => g.length);
  };
  const summary = (n) => {
    const ks = kids(n); if (!ks.length) return "";
    const names = ks.slice(0, 3).map((c) => parse(c).label);
    return names.join(", ") + (ks.length > 3 ? ` +${ks.length - 3}` : "");
  };
  function rowHTML(n, i, keyBase, o) {
    const p = parse(n), key = keyOf(keyBase, n);
    const dis = n.disabled && !special(p.label, n) ? " dim" : "";
    const ic = o.icons ? iconFor(p.label) : null;
    const lead = ic ? `<span class="ko-icon-tile">${icon(ic)}</span>` : "";
    const star = p.star ? `<span class="mn-star" title="Default">${icon("star", "sm")}</span>` : "";
    const glyph = p.glyph ? `<span class="ko-pill ko-pill--caps">hyph</span>` : "";
    const help = n.help ? `<button class="ko-help-btn mn-help" data-action="mnHelp" data-i="${i}" data-stop aria-label="About this option">${icon("info", "sm")}</button>` : "";
    const hl = o.hl === i ? " hl" : "";
    const dl = `data-i="${i}" data-label="${esc((p.display + " " + p.label + " " + p.value).toLowerCase())}"`;
    const lbl = (sub) => { sub = [sub, p.ko ? `KOReader: ${p.ko}` : ""].filter(Boolean).join(" · "); return `<span class="label"><span class="t">${esc(p.display)}${star}${glyph}</span>${sub ? `<span class="sub">${esc(sub)}</span>` : ""}</span>`; };
    if (isSub(n)) {
      const v = valueOf(n, key), cnt = kids(n).length;
      const sub = o.summaries && !v ? summary(n) : "";
      return `<div class="ko-row mn-row is-sub${dis}${hl}" role="button" ${dl} data-action="mnDrill">${lead}${lbl(sub)}${help}${v ? `<span class="value">${esc(v)}</span>` : cnt === 0 ? `<span class="value">Empty</span>` : ""}${icon("chevron-right", "chev sm")}</div>`;
    }
    if (n.kind === "check") {
      const on = checked(n, key);
      return `<div class="ko-row mn-row is-check${dis}${hl}" role="switch" aria-checked="${on}" ${dl} data-action="mnCheck">${lead}${lbl()}${help}${App.toggle(on)}</div>`;
    }
    if (n.kind === "radio") {
      const on = checked(n, key);
      return `<div class="ko-row mn-row is-radio${dis}${hl}${on ? " on" : ""}" role="radio" aria-checked="${on}" ${dl} data-action="mnRadio">${App.radio(on)}${lbl()}${help}</div>`;
    }
    const v = ST.has(key + "#v") ? ST.get(key + "#v") : p.value;
    const m = v && String(v).match(NUM);
    if (m && !n.disabled && !special(p.label, n)) {
      return `<div class="ko-row mn-row is-num${hl}" ${dl}>${lead}${lbl()}${help}<span class="ko-stepper mn-step"><button data-action="mnStep" data-i="${i}" data-d="-1" aria-label="Decrease">${icon("minus", "sm")}</button><span class="val num">${esc(v)}</span><button data-action="mnStep" data-i="${i}" data-d="1" aria-label="Increase">${icon("plus", "sm")}</button></span></div>`;
    }
    const sp = special(p.label, n);
    const tail = sp ? icon("arrow-up-right", "chev sm") : v ? `<span class="value">${esc(v)}</span>${icon("pencil", "chev sm")}` : "";
    const lead2 = lead || (/^about\b/i.test(p.label) && o.icons !== false ? `<span class="ko-icon-tile">${icon("info")}</span>` : "");
    return `<div class="ko-row mn-row is-leaf${dis}${hl}" role="button" ${dl} data-action="mnLeaf">${lead2}${lbl()}${help}${tail}</div>`;
  }
  /** renders a node list as grouped cards (separators = group breaks) */
  function listHTML(items, keyBase, loc, o = {}) {
    if (!items.length) return `<div class="ko-empty mn-empty">${icon("inbox")}<div>Nothing here yet</div><div class="faint">KOReader lists this entry, but it has no options in the current state.</div></div>`;
    const filter = o.filter ?? items.length > 14;
    return `<div class="mn-list" data-loc="${App.attrs(loc)}">${filter ? `<label class="ko-input mn-filter">${icon("search", "sm")}<input type="search" placeholder="Filter ${items.length} options…" data-mn-filter></label>` : ""}${groupsOf(items).map((g) =>
      `<div class="ko-group mn-group">${g.map((i) => rowHTML(items[i], i, keyBase, o)).join("")}</div>`).join("")}<div class="mn-nores faint" hidden>No option matches.</div></div>`;
  }
  /** synthetic shortcut cards for well-known menus (Reading statistics -> stats screen, ...) */
  function heroFor(title) {
    const t = String(title).toLowerCase();
    const card = (ic, a, b, attrs) => `<button class="ko-card ko-card--accent mn-hero" ${attrs}><span class="ko-icon-tile">${icon(ic)}</span><span class="grow"><b>${a}</b><span>${b}</span></span>${icon("arrow-up-right", "sm")}</button>`;
    if (t === "reading statistics") return card("chart-column", "Open reading statistics", "Today, calendar, timeline and per-book stats", `data-go="stats"`);
    if (t === "network") return card("wifi", "Wi-Fi", "Connected · Home network", `data-open="wifi"`);
    if (t === "screen") return card("sun", "Frontlight & warmth", `Brightness ${fl()}% · Warmth ${warm()}%`, `data-open="frontlight"`);
    if (t === "device") return card("moon-star", "Sleep screen", "Shows the cover of the current book", `data-open="sleep"`);
    return "";
  }

  /* ------------------------------------------------------ leaf behaviour */
  const bookId = () => (App.current.name === "reader" && App.current.params.id) || "animal-farm";
  const inReader = (name, params = {}) => () => {
    const id = bookId(); App.closeAll();
    if (App.current.name !== "reader") App.go("reader", { id });
    App.open(name, { id, ...params });
  };
  const go = (name, params) => () => App.go(name, params || {});
  const open = (name, params) => () => { App.closeAll(); App.open(name, params || {}); };
  const SPECIAL = {
    "open last document": go("reader", { id: "animal-farm" }), "open previous document": go("reader", { id: "animal-farm" }),
    exit: () => App.open("confirm", { title: "Exit Folio?", body: "Your reading position is saved. You can reopen the last book from the home screen.", ok: "Exit", danger: true }),
    "restart koreader": () => App.open("confirm", { title: "Restart Folio?", body: "The app restarts and reopens where you left off.", ok: "Restart" }),
    "network info": () => App.open("wifi"),
    "table of contents": inReader("toc"), bookmarks: inReader("bookmarks"), "go to page": inReader("goto"), "skim document": inReader("skim"),
    "book map": inReader("bookmap"), "page browser": inReader("pagebrowser"), "bookmark browser": inReader("annotations"),
    "dictionary lookup": inReader("dict"), "translate current page": inReader("translate"), "wikipedia lookup": inReader("wiki"),
    history: go("history"), favorites: go("library", { tab: "favorites" }), collections: go("library", { tab: "collections" }),
    "book information": () => { App.closeAll(); App.open("book-details", { id: bookId() }); },
    "book status": () => { App.closeAll(); App.open("book-status", { id: bookId() }); },
    "fulltext search": go("search", { scope: "book" }), "last fulltext search results": go("search", { scope: "book" }),
    "bookmark search": go("search", { scope: "bookmarks" }), "file search": go("search", { scope: "library" }),
    "last file search results": go("search", { scope: "library" }), "calibre metadata search": go("search", { scope: "calibre" }),
    "menu search": go("settings", { find: 1 }), version: open("about"), "current book": go("stats"), "reading progress": go("stats"),
    "time range": go("stats"), "calendar view": go("stats"), "today's timeline": go("stats"),
  };
  /* other files can link menu items to their screens: App.menuSpecial["vocabulary builder"] = () => ... */
  App.menuSpecial = SPECIAL;
  function special(label, n) {
    const l = label.toLowerCase();
    if (l === "about" && n && !n.kind) return { fn: open("about") };
    const fn = SPECIAL[l];
    return fn ? { fn } : null;
  }

  /* -------------------------------------------------------- actions */
  let animDir = "";
  function setTop(params, dir) {
    animDir = dir || "";
    const t = App.top();
    if (t && t.name === "main-menu") { t.params = params; App.renderLayers(); App.syncHash(); }
    else App.open("main-menu", params);
  }
  function navTo(loc, path, dir) {
    if (loc.section) { animDir = dir; App.go("settings", { section: loc.section, path }); }
    else setTop({ ctx: loc.ctx, tab: loc.tab, path }, dir);
  }
  const nodeAt = (el) => {
    const loc = locOf(el); if (!loc) return {};
    const L = locate(loc), i = Number(el.dataset.i), n = L.items[i];
    return { loc, L, i, n, key: n ? keyOf(L.keyBase, n) : "" };
  };

  App.action("mnDrill", (el) => {
    const { loc, L, i, n } = nodeAt(el); if (!n) return;
    if (n.disabled) App.toast("Inactive in KOReader right now — shown for reference");
    navTo(loc, L.path.concat(i), "fwd");
  });
  App.action("mnBack", (el) => {
    const loc = JSON.parse(el.dataset.loc || "{}"); const p = normPath(loc.path);
    if (loc.section) { animDir = "back"; if (p.length <= 1) App.go("settings", p.length ? { section: loc.section } : {}); else App.go("settings", { section: loc.section, path: p.slice(0, -1) }); }
    else if (p.length) navTo(loc, p.slice(0, -1), "back"); else App.close();
  });
  App.action("mnCrumb", (el) => {
    const loc = JSON.parse(el.dataset.loc || "{}"), d = Number(el.dataset.depth), p = normPath(loc.path);
    if (loc.section) {
      animDir = "back";
      if (el.dataset.depth === "src") return App.go("settings", { section: loc.section, path: p.slice(0, 1) });
      if (d === -2) return App.go("settings", {});
      if (d === -1) return App.go("settings", { section: loc.section });
      return App.go("settings", { section: loc.section, path: p.slice(0, d + 2) });
    }
    navTo(loc, d < 0 ? [] : p.slice(0, d + 1), "back");
  });
  App.action("mnTab", (el) => { const t = App.top(); setTop({ ctx: (t && t.params.ctx) || "fm", tab: el.dataset.tab }, "tab"); });
  App.action("mnCheck", (el) => {
    const { n, key } = nodeAt(el); if (!n) return;
    const label = parse(n).label;
    if (n.disabled) return App.toast(`“${label}” is unavailable right now`);
    const on = !checked(n, key);
    if (isNightNode(n)) { if (App.setTheme) App.setTheme(on ? "dark" : "paper"); }
    else ST.set(key, on);
    el.querySelector(".ko-toggle")?.classList.toggle("on", on);
    el.setAttribute("aria-checked", on);
    App.toast(`${label} · ${on ? "On" : "Off"}`);
  });
  App.action("mnRadio", (el) => {
    const { L, i, n } = nodeAt(el); if (!n) return;
    const label = parse(n).label;
    if (n.disabled) return App.toast(`“${label}” is unavailable right now`);
    let a = i, b = i; const it = L.items;
    while (a > 0 && it[a - 1].kind === "radio" && !it[a - 1].separator) a--;
    while (b < it.length - 1 && it[b + 1].kind === "radio" && !it[b].separator) b++;
    const wrap = el.closest(".mn-list");
    for (let k = a; k <= b; k++) {
      ST.set(keyOf(L.keyBase, it[k]), k === i);
      const r = wrap.querySelector(`.mn-row[data-i="${k}"]`);
      if (r) { r.classList.toggle("on", k === i); r.querySelector(".ko-radio")?.classList.toggle("on", k === i); r.setAttribute("aria-checked", k === i); }
    }
    // keep the parent's "Label: value" in sync (Sort by: name -> date ...)
    const parent = L.node;
    if (parent && parse(parent).value) {
      ST.set(L.keyBase.join("›") + "#v", label);
      const val = document.querySelector(".mn-value[data-live]"); if (val) val.textContent = label;
    }
    App.toast(`${label} selected`);
  });
  App.action("mnStep", (el) => {
    const row = el.closest(".mn-row"); const { n, key } = nodeAt(row); if (!n) return;
    const cur = ST.has(key + "#v") ? ST.get(key + "#v") : parse(n).value;
    const m = String(cur).match(NUM); if (!m) return;
    const dec = (m[1].split(".")[1] || "").length, step = dec ? Math.pow(10, -dec) * (dec === 2 ? 5 : 1) : Math.abs(Number(m[1])) >= 100 ? 10 : 1;
    const nv = Math.max(0, Number(m[1]) + Number(el.dataset.d) * step).toFixed(dec) + (m[2] || "");
    ST.set(key + "#v", nv);
    row.querySelector(".val").textContent = nv;
  });
  let pendingKey = null;
  App.action("mnLeaf", (el) => {
    const { n, key } = nodeAt(el); if (!n) return;
    const p = parse(n);
    const sp = special(p.label, n);   // Folio links (dictionary manager, version → update…) win over KOReader's state
    if (sp) return sp.fn();
    if (n.disabled) return App.toast(`“${p.label}” is unavailable right now`);
    const v = ST.has(key + "#v") ? ST.get(key + "#v") : p.value;
    if (v || /folder|location|server|address|password|hostname|filename|text$|tags|port/i.test(p.label)) {
      pendingKey = key;
      return App.open("input", { title: p.label, hint: p.label, value: /^not set$|^default$/.test(v) ? "" : v, ok: "Save", action: "mnInputOk" });
    }
    if (/^about\b/i.test(p.label) || /^(info|help)$/i.test(p.label)) return App.open("menu-help", { ...locOf(el), i: Number(el.dataset.i) });
    App.toast(`${p.label}${/[.…!]$/.test(p.label) ? "" : " …"}`);
  });
  App.action("mnInputOk", (el, val) => {
    const v = typeof el === "string" ? el : typeof val === "string" ? val : document.querySelector("#layer-root .ko-layer:last-child input")?.value;
    if (pendingKey && v != null) ST.set(pendingKey + "#v", v || "not set");
    App.close(); App.refresh(); App.toast("Saved");
  });
  App.action("mnHelp", (el) => { const loc = locOf(el); App.open("menu-help", { ...loc, i: Number(el.dataset.i) }); });

  /* filter fields (delegated, works on screens & overlays) */
  document.addEventListener("input", (e) => {
    const f = e.target.closest && e.target.closest("[data-mn-filter]"); if (!f) return;
    const q = f.value.trim().toLowerCase(), wrap = f.closest(".mn-list");
    let shown = 0;
    wrap.querySelectorAll(".mn-group").forEach((g) => {
      let any = 0;
      g.querySelectorAll(".mn-row").forEach((r) => { const ok = !q || r.dataset.label.includes(q); r.hidden = !ok; if (ok) any++; });
      g.hidden = !any; shown += any;
    });
    wrap.querySelector(".mn-nores").hidden = !!shown;
  });

  /* ======================================================= main-menu */
  const ctxLabel = (ctx) => {
    if (ctx === "fm") return "Library";
    const b = window.DB && DB.book && DB.book(bookId());
    return (ctx === "reader-pdf" ? "Reading a PDF · " : "Reading · ") + ((b && b.title) || "Animal Farm").replace(/\s*\(.*\)$/, "");
  };
  function libraryPane() {
    const link = (ic, a, b, attrs) => `<button class="ko-row mn-row is-leaf" ${attrs}><span class="ko-icon-tile">${icon(ic)}</span><span class="label"><span class="t">${a}</span><span class="sub">${b}</span></span>${icon("arrow-up-right", "chev sm")}</button>`;
    return `<div class="mn-list"><button class="ko-card ko-card--accent mn-hero" data-go="library"><span class="ko-icon-tile">${icon("library-big")}</span><span class="grow"><b>Back to library</b><span>Close the book and browse your shelves</span></span>${icon("arrow-up-right", "sm")}</button>
      <div class="ko-group mn-group">${link("house", "Home", "Continue reading, recent books", `data-go="home"`)}${link("history", "History", "Recently opened books", `data-go="history"`)}${link("star", "Favorites", "Books you starred", `data-go="library" data-params='{"tab":"favorites"}'`)}${link("layers", "Collections", "Your shelves", `data-go="library" data-params='{"tab":"collections"}'`)}</div></div>`;
  }
  const crumbsHTML = (L, loc) => L.crumbs.slice(0, -1).map((c) => `<button data-action="mnCrumb" data-depth="${c.depth}" data-loc="${App.attrs(loc)}">${esc(c.label)}</button>`).join(`<span class="sep">›</span>`);
  App.overlay("main-menu", {
    layer: "sheet",
    render(params) {
      const L = locate({ ctx: params.ctx || "fm", tab: params.tab, path: params.path });
      const loc = { ctx: L.ctx, tab: L.tab.key, path: L.path };
      const deep = L.path.length > 0;
      const still = animDir ? " mn-still" : "";
      const anim = animDir ? ` mn-anim-${animDir}` : "";
      animDir = "";
      const val = deep ? valueOf(L.node, L.keyBase.join("›")) : "";
      // same structure as before (tabs → items → drill-down); only the frame follows the shared sheet design
      const head = deep
        ? UI.sheetHead({
            cls: "mn-head deep",
            lead: `<button class="ko-icon-btn mn-back" data-action="mnBack" data-loc="${App.attrs(loc)}" aria-label="Back">${icon("arrow-left")}</button>`,
            titleHtml: `<span class="mn-title">${esc(L.title)}</span>${val ? ` <span class="mn-value" data-live>${esc(val)}</span>` : ""}`,
            subHtml: L.crumbs.length > 1 ? `<span class="ko-crumbs mn-crumbs">${crumbsHTML(L, loc)}</span>` : "",
          })
        : UI.sheetHead({
            cls: "mn-head",
            titleHtml: `<span class="mn-title">Menu</span>`,
            sub: ctxLabel(L.ctx),
            actions: UI.iconButton({ icon: "sliders-horizontal", label: "Quick settings", attrs: 'data-open="quick"' })
              + UI.iconButton({ icon: "settings", label: "All settings", attrs: 'data-go="settings"' }),
          });
      const tabs = deep ? "" : UI.tabs(L.tabs.map((t) => ({ label: t.label, on: t.key === L.tab.key, cls: "mn-tab", attrs: `data-action="mnTab" data-tab="${t.key}"` })), { cls: "mn-tabs" });
      const body = !L.items.length && L.tab.key === "library" && !deep ? libraryPane()
        : heroFor(deep ? L.title : "") + listHTML(L.items, L.keyBase, loc, { icons: L.path.length <= 1, hl: params.hl != null ? Number(params.hl) : undefined });
      return `<div class="ko-sheet ko-sheet--phone mn-sheet mn-pane${still}" role="dialog" aria-label="Menu">
        <div class="grip"></div>${head}${tabs}
        <div class="ko-scroll mn-body${anim}">${body}</div>
      </div>`;
    },
  });

  /* ========================================================= menu-help */
  App.overlay("menu-help", {
    layer: "dialog",
    render(params) {
      const loc = params.section ? { section: params.section, path: params.path } : { ctx: params.ctx, tab: params.tab, path: params.path };
      const L = locate(loc), i = Number(params.i), n = L.items[i];
      if (!n) return UI.dialog({ cls: "mn-helpbox", title: params.title || "Help", body: params.text || "", actions: [{ label: "Got it", kind: "primary", attrs: "data-close" }] });
      const p = parse(n), key = keyOf(L.keyBase, n);
      const text = n.help || `“${p.label}” lives in ${L.crumbs.map((c) => c.label).join(" › ")}. KOReader gives no further description for it.`;
      const ctl = n.kind === "check" ? `<div class="mn-list mn-help-ctl" data-loc="${App.attrs(loc)}"><div class="ko-group mn-group">${rowHTML({ ...n, help: undefined }, i, L.keyBase, {})}</div></div>`
        : n.kind === "radio" ? `<div class="mn-help-state">${App.radio(checked(n, key))}<span>${checked(n, key) ? "Currently selected" : "Not selected"}</span></div>` : "";
      return UI.dialog({
        cls: "mn-helpbox",
        head: `<div class="mn-help-head">${UI.iconTile("info")}<div class="grow"><div class="ko-crumbs ko-crumbs static">${L.crumbs.map((c) => `<span>${esc(c.label)}</span>`).join(`<span class="sep">›</span>`)}</div><div class="ko-dialog-title">${esc(p.label)}${p.value ? ` <span class="mn-value">${esc(valueOf(n, key))}</span>` : ""}</div></div></div>`,
        bodyHtml: `<div class="ko-dialog-body mn-help-text">${esc(text.trim()).split(/\n{2,}/).map((para) => `<p>${para.replace(/\n/g, "<br>")}</p>`).join("")}</div>${ctl}`,
        actions: [{ label: "Got it", kind: "primary", attrs: "data-close" }],
      });
    },
  });

  /* ========================================================== settings */
  let IDX = null;
  function buildIndex() {
    IDX = []; const seen = new Set();
    const walk = (items, sk, path, crumbs, depth) => items.forEach((n, i) => {
      const p = parse(n);
      IDX.push({ t: (p.label + " " + p.value).toLowerCase(), n, p, sk, path, i, crumbs, depth });
      if (!isSub(n)) return;
      if (isRef(n.items) && n.items.ref) { if (seen.has(n.items.ref)) return; seen.add(n.items.ref); }
      walk(kids(n), sk, path.concat(i), crumbs.concat(p.label), depth + 1);
    });
    for (const [sk, sec] of Object.entries(SECTIONS)) sec.sources.forEach((src, si) => walk(resolveSource(src).items, sk, [si], [sec.title, src.title], 0));
  }
  const reEsc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  function searchAll(q) {
    if (!IDX) buildIndex();
    const words = q.toLowerCase().split(/\s+/).filter(Boolean); if (!words.length) return { hits: [], total: 0 };
    const wb = new RegExp("\\b" + reEsc(words[0]));
    const byLabel = new Map();
    for (const e of IDX) {
      if (!words.every((w) => e.t.includes(w))) continue;
      const lt = e.p.label.toLowerCase();
      const gest = e.crumbs.includes("Gesture manager") ? 40 : 0; // gesture action lists repeat every action: rank them last
      const score = gest + (lt.startsWith(words[0]) ? 0 : wb.test(lt) ? 1 : 2) * 10 + Math.min(e.depth, 9);
      const k = lt + "|" + (isSub(e.n) ? "s" : e.n.kind);
      const prev = byLabel.get(k);
      if (!prev) byLabel.set(k, { e, score, more: 0 }); else { prev.more++; if (score < prev.score) { prev.e = e; prev.score = score; } }
    }
    const hits = [...byLabel.values()].sort((a, b) => a.score - b.score || a.e.p.label.length - b.e.p.label.length);
    return { hits: hits.slice(0, 60), total: hits.length };
  }
  function resultsHTML(q) {
    const { hits, total } = searchAll(q);
    if (!hits.length) return `<div class="ko-empty">${icon("search-x")}<div>No option matches “${esc(q)}”</div><div>Try a shorter word, like “font” or “refresh”.</div></div>`;
    const re = new RegExp("(" + q.trim().split(/\s+/).map(reEsc).join("|") + ")", "ig");
    const mark = (s) => esc(s).replace(re, "<mark>$1</mark>");
    const kindIc = { check: "toggle-right", radio: "circle-dot", submenu: "chevron-right" };
    return `<div class="ko-section-label set-res-count">${total} matching option${total === 1 ? "" : "s"}${total > hits.length ? ` · top ${hits.length}` : ""}</div><div class="ko-group set-results">${hits.map(({ e, more }) => {
      const sec = SECTIONS[e.sk];
      const target = { section: e.sk, path: e.path, hl: e.i };
      return `<button class="ko-row set-hit" data-go="settings" data-params="${App.attrs(target)}"><span class="ko-icon-tile">${icon(sec.icon)}</span><span class="label"><span class="t">${mark(e.p.label)}${e.p.value ? ` <span class="faint">· ${mark(e.p.value)}</span>` : ""}</span><span class="sub set-crumbline"><span class="set-crumb">${e.crumbs.concat(e.path.length > 1 ? [] : []).filter(Boolean).map(esc).join(" › ")}</span>${more ? `<span class="set-more-n">+${more} more</span>` : ""}</span></span><span class="set-kind">${icon(kindIc[isSub(e.n) ? "submenu" : e.n.kind] || "corner-down-right", "sm")}</span></button>`;
    }).join("")}</div>`;
  }

  const fl = () => App.get("fl.brightness", 42), warm = () => App.get("fl.warmth", 30), contrast = () => App.get("eink.contrast", 55);
  /* numeric settings use the shared App.sliderRow (label · − · slider · + · value on one line) */
  const SLIDERS = { fl: ["fl.brightness", 42, "%"], warm: ["fl.warmth", 30, "%"], contrast: ["eink.contrast", 55, ""] };
  function setSlider(el, id, pct) {
    const [key, , unit] = SLIDERS[id]; pct = Math.max(0, Math.min(100, Math.round(pct)));
    App.set(key, pct);
    const row = el.closest(".ko-sr");
    if (row) {
      row.querySelector(".ko-slider")?.style.setProperty("--v", pct + "%");
      const v = row.querySelector(".val"); if (v) v.innerHTML = pct + (unit ? `<small>${unit}</small>` : "");
    }
    if (id === "contrast") document.querySelectorAll(".set-ramp").forEach((r) => r.style.setProperty("--c", (0.6 + pct / 100 * 0.9).toFixed(2)));
  }
  App.action("stSlide", (s, v) => { const id = s.dataset.id; if (SLIDERS[id]) setSlider(s, id, v * 100); });
  App.action("stStep", (el) => { const id = el.dataset.id; if (!SLIDERS[id]) return; setSlider(el, id, App.get(SLIDERS[id][0], SLIDERS[id][1]) + 5 * Number(el.dataset.dir)); });
  const sr = (id, label, extra = {}) => { const [key, def, unit] = SLIDERS[id]; const v = App.get(key, def); return App.sliderRow({ id, label, pct: v, value: String(v), unit, slide: "stSlide", step: "stStep", ...extra }); };
  App.action("stSeg", (el) => {
    App.set(el.dataset.key, el.dataset.v);
    el.parentElement.querySelectorAll("button").forEach((b) => b.classList.toggle("on", b === el));
    App.toast(`${el.dataset.name}: ${el.textContent}`);
  });
  App.action("stNight", (el) => {
    const on = !themeIsDark(); if (App.setTheme) App.setTheme(on ? "dark" : "paper");
    el.querySelector(".ko-toggle")?.classList.toggle("on", on); el.classList.toggle("on", on);
    const v = el.querySelector(".v"); if (v) v.textContent = on ? "On" : "Off";
    App.toast(`Night mode · ${on ? "On" : "Off"}`);
  });
  const seg = (key, name, opts, def) => { const cur = String(App.get(key, def)); return `<div class="ko-seg set-seg">${opts.map(([v, l]) => `<button class="${String(v) === cur ? "on" : ""}" data-action="stSeg" data-key="${key}" data-name="${name}" data-v="${v}">${l}</button>`).join("")}</div>`; };
  function einkPanel() {
    const ramp = Array.from({ length: 16 }, (_, k) => `<i style="--k:${(k / 15 * 100).toFixed(1)}%"></i>`).join("");
    return `<div class="ko-section-label">E-ink panel</div>
    <div class="set-eink">
      <div class="ko-card set-card">
        <div class="set-card-head"><span class="ko-icon-tile">${icon("sun")}</span><b class="grow">Frontlight</b><button class="set-more" data-open="frontlight">Schedule ${icon("chevron-right", "sm")}</button></div>
        ${sr("fl", "Brightness", { minIcon: "sun-dim", maxIcon: "sun" })}
        ${sr("warm", "Warmth", { minIcon: "snowflake", maxIcon: "flame" })}
      </div>
      <div class="ko-card set-card">
        <div class="set-card-head"><span class="ko-icon-tile">${icon("contrast")}</span><b class="grow">Contrast</b><span class="set-note">Text &amp; UI darkness</span></div>
        ${sr("contrast", "Level")}
        <div class="set-ramp" style="--c:${(0.6 + contrast() / 100 * 0.9).toFixed(2)}">${ramp}</div>
        <div class="set-ramp-cap"><span>16-level grayscale test</span><span>paper → ink</span></div>
      </div>
      <div class="ko-card set-card">
        <div class="set-card-head"><span class="ko-icon-tile">${icon("refresh-cw")}</span><b class="grow">Refresh</b><span class="set-note">Full refresh clears ghosting</span></div>
        <div class="set-field"><span>Full refresh every</span>${seg("eink.refresh", "Full refresh", [["1", "Page"], ["6", "6"], ["12", "12"], ["24", "24"], ["0", "Never"]], "6")}</div>
        <div class="set-field"><span>Waveform</span>${seg("eink.wave", "Waveform", [["fast", "Fast"], ["auto", "Balanced"], ["hq", "Quality"]], "auto")}</div>
        <div class="set-field"><span>On chapter start</span>${seg("eink.chap", "On chapter start", [["on", "Refresh"], ["off", "Skip"]], "on")}</div>
      </div>
    </div>`;
  }

  function sectionHeader(L, loc) {
    const deep = L.path.length > 0;
    const val = L.node ? valueOf(L.node, L.keyBase.join("›")) : "";
    return `<header class="ko-header ko-header--page ko-header--rule set-head"><button class="ko-icon-btn mn-back" data-action="mnBack" data-loc="${App.attrs(loc)}" aria-label="Back">${icon("arrow-left")}</button>
      <div class="grow"><div class="ko-crumbs">${crumbsHTML(L, loc)}</div><div class="ko-page-title">${esc(L.title)}${val ? ` <span class="mn-value" data-live>${esc(val)}</span>` : ""}</div>${deep ? "" : `<div class="set-desc">${esc(L.section.desc)}</div>`}</div>
      <button class="ko-icon-btn" data-go="settings" data-params='{"find":1}' aria-label="Search settings">${icon("search")}</button></header>`;
  }
  function sectionPage(params) {
    const loc = { section: params.section, path: normPath(params.path) };
    const L = locate(loc); loc.path = L.path;
    const anim = animDir ? ` mn-anim-${animDir}` : ""; animDir = "";
    let body;
    if (!L.path.length) {
      const sec = L.section, k = params.section;
      body = (k === "display" ? einkPanel() : "") + (k === "network" ? `<div class="ko-section-label">Wireless</div>${heroFor("network")}` : "") + (k === "device" ? `<div class="ko-section-label">Sleep</div>${heroFor("device")}` : "")
        + sec.sources.map((src, si) => {
          const r = resolveSource(src);
          return `<div class="ko-section-label">${esc(src.title || "")}</div>${listHTML(r.items, r.keyBase, { section: k, path: [si] }, { icons: true, summaries: true, filter: src.filter || r.items.length > 24 })}`;
        }).join("");
    } else {
      body = heroFor(L.title) + listHTML(L.items, L.keyBase, loc, { icons: L.path.length <= 2, summaries: true, hl: params.hl != null ? Number(params.hl) : undefined });
    }
    return `<div class="ko-view set-view">${App.statusBar({ left: "Settings" })}${sectionHeader(L, loc)}<div class="ko-scroll set-body${anim}">${body}<div class="set-end"></div></div>${App.bottomNav("settings")}</div>`;
  }
  function homePage(params) {
    const q = params.q ? String(params.q) : "";
    const cards = CLUSTERS.map(([name, keys]) => `<div class="ko-section-label">${name}</div><div class="ko-group set-secs">${keys.map((k) => {
      const s = SECTIONS[k];
      return `<button class="ko-row set-sec" data-go="settings" data-params='{"section":"${k}"}'><span class="ko-icon-tile ko-icon-tile--lg">${icon(s.icon)}</span><span class="label"><span class="t">${s.title}</span><span class="sub">${s.desc}</span></span>${icon("chevron-right", "chev sm")}</button>`;
    }).join("")}</div>`).join("");
    const quick = (ic, l, v, attrs, on) => `<button class="ko-card set-q ${on ? "on" : ""}" ${attrs}>${icon(ic)}<span class="t">${l}</span><span class="v">${v}</span></button>`;
    const home = `<div class="set-device ko-card"><div class="set-dev-ic">${icon("tablet-smartphone", "lg")}</div><div class="grow"><b>Kindle Paperwhite</b><span>Folio on KOReader 2026.07.1</span><div class="set-batt">${App.progress(87, "ko-progress--thin")}<span class="num">87% · 3.1 GB free</span></div></div><button class="ko-btn ko-btn--ghost" data-open="about">About</button></div>
      <div class="set-quick">${quick("moon", "Night mode", themeIsDark() ? "On" : "Off", 'data-action="stNight"', themeIsDark())}${quick("wifi", "Wi-Fi", "Home", 'data-open="wifi"', true)}${quick("sun", "Frontlight", fl() + "%", 'data-open="frontlight"', fl() > 0)}${quick("moon-star", "Sleep screen", "Cover", 'data-open="sleep"', false)}</div>${cards}`;
    return `<div class="ko-view set-view set-home">${App.statusBar({ left: "Settings" })}
      <header class="set-hero"><div class="set-title serif big">Settings</div><div class="set-desc">Every KOReader option, organised.</div></header>
      <div class="set-search"><label class="ko-input ko-input--card">${icon("search", "sm")}<input type="search" id="set-q" placeholder="Search all options — “refresh”, “hyphen”…" value="${esc(q)}" autocomplete="off"></label></div>
      <div class="ko-scroll set-body"><div id="set-res" ${q ? "" : "hidden"}>${q ? resultsHTML(q) : ""}</div><div id="set-home" ${q ? "hidden" : ""}>${home}</div><div class="set-end"></div></div>
      ${App.bottomNav("settings")}</div>`;
  }
  App.screen("settings", {
    title: "Settings",
    render: (params) => (params.section && SECTIONS[params.section] ? sectionPage(params) : homePage(params)),
    mount(root, params) {
      const hl = root.querySelector(".mn-row.hl"); if (hl) hl.scrollIntoView({ block: "center" });
      const inp = root.querySelector("#set-q"); if (!inp) return;
      if (params.find || params.q) { inp.focus(); inp.setSelectionRange(inp.value.length, inp.value.length); }
      inp.addEventListener("input", () => {
        const q = inp.value.trim(), res = root.querySelector("#set-res"), home = root.querySelector("#set-home");
        res.hidden = !q; home.hidden = !!q; res.innerHTML = q ? resultsHTML(q) : "";
        App.current.params = q ? { q } : {}; App.syncHash(); App.icons();
      });
    },
  });

  /* ============================================================= demos */
  const hashFor = (screen, params, ov, op) => {
    const q = new URLSearchParams(); const put = (k, v) => q.set(k, typeof v === "object" ? JSON.stringify(v) : v);
    for (const [k, v] of Object.entries(params || {})) put(k, v);
    if (ov) { q.set("o", ov); for (const [k, v] of Object.entries(op || {})) put("o." + k, v); }
    return `#/${screen}${[...q].length ? "?" + q.toString() : ""}`;
  };
  /** label chain -> index path inside a menu tab */
  function pathOf(ctx, tabKey, labels) {
    const t = tabsOf(ctx).find((x) => x.key === tabKey); if (!t) return [];
    let items = kids({ items: t.items }); const p = [];
    for (const l of labels) { const i = items.findIndex((n) => parse(n).label === l || String(n.text).startsWith(l)); if (i < 0) break; p.push(i); items = kids(items[i]); }
    return p;
  }
  const spath = (sk, si, labels) => { let items = resolveSource(SECTIONS[sk].sources[si]).items; const p = [si]; for (const l of labels) { const i = findChild(items, l); if (i < 0) break; p.push(i); items = kids(items[i]); } return p; };
  const G = "Menus & Settings";
  const base = { fm: ["library", {}], reader: ["reader", { id: "animal-farm" }], "reader-pdf": ["reader", { id: "animal-farm" }] };
  const mm = (ctx, tab, path, ov = "main-menu", extra = {}) => hashFor(base[ctx][0], base[ctx][1], ov, { ctx, tab, ...(path && path.length ? { path } : {}), ...extra });
  tabsOf("fm").forEach((t) => App.demo(G, `Library menu · ${t.label}`, mm("fm", t.key)));
  tabsOf("reader").forEach((t) => App.demo(G, `Reader menu · ${t.label}`, mm("reader", t.key)));
  App.demo(G, "PDF reader menu · Typesetting", mm("reader-pdf", "typeset"));
  App.demo(G, "Drill · Sort by (radio + value)", mm("fm", "library", pathOf("fm", "library", ["Sort by"])));
  App.demo(G, "Drill · Screen › E-ink settings", mm("reader", "settings", pathOf("reader", "settings", ["Screen", "E-ink settings"])));
  App.demo(G, "Drill · Gesture manager", mm("reader", "settings", pathOf("reader", "settings", ["Taps and gestures", "Gesture manager"])));
  App.demo(G, "Drill · Tap corner › Top left (actions)", mm("reader", "settings", pathOf("reader", "settings", ["Taps and gestures", "Gesture manager", "Tap corner", "Top left"])));
  App.demo(G, "Drill · … › Top left › Reader actions", mm("reader", "settings", pathOf("reader", "settings", ["Taps and gestures", "Gesture manager", "Tap corner", "Top left", "Reader"])));
  App.demo(G, "Drill · Style tweaks › Text", mm("reader", "typeset", pathOf("reader", "typeset", ["Style tweaks", "Text"])));
  App.demo(G, "Drill · Fonts list (filter)", mm("reader", "typeset", pathOf("reader", "typeset", ["Font"])));
  App.demo(G, "Settings · home", "#/settings");
  App.demo(G, "Settings · search “font”", hashFor("settings", { q: "font" }));
  App.demo(G, "Settings · search “refresh”", hashFor("settings", { q: "refresh" }));
  Object.entries(SECTIONS).forEach(([k, s]) => App.demo(G, `Settings · ${s.title}`, hashFor("settings", { section: k })));
  App.demo(G, "Settings · Screen", hashFor("settings", { section: "display", path: [1] }));
  App.demo(G, "Settings · Status bar", hashFor("settings", { section: "reading", path: [1] }));
  App.demo(G, "Settings · Status bar items", hashFor("settings", { section: "reading", path: spath("reading", 1, ["Status bar items"]) }));
  App.demo(G, "Settings · Fonts", hashFor("settings", { section: "typography", path: spath("typography", 0, ["Font"]) }));
  App.demo(G, "Settings · Typography language", hashFor("settings", { section: "typography", path: spath("typography", 0, ["Typography rules", "Typography rules"]) }));
  App.demo(G, "Settings · Gesture manager", hashFor("settings", { section: "gestures", path: spath("gestures", 0, ["Gesture manager"]) }));
  App.demo(G, "Settings · Dictionary settings", hashFor("settings", { section: "search", path: spath("search", 0, ["Settings", "Dictionary settings"]) }));
  const cm = spath("library", 0, ["Settings", "Classic mode settings"]);
  App.demo(G, "Menu help · Items per page", hashFor("settings", { section: "library", path: cm }, "menu-help", { section: "library", path: cm, i: 0 }));
  App.demo(G, "Menu help · Multiswipes", mm("reader", "settings", pathOf("reader", "settings", ["Taps and gestures", "Gesture manager"]), "menu-help", { i: 0 }));

  window.Menus = { KM, kids, parse, locate, listHTML, rowHTML, tabsOf, treeOf, SECTIONS, resolveSource, searchAll, normPath, isSub, pathOf, hashFor };
})();
