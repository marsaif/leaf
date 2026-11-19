/* ==========================================================================
   Design system catalog — every token and every component of css/components.css,
   in its states, with the js/ui.js helper call that produces it.
   Screen: catalog ({page: tokens|controls|rows|containers|feedback})
   ========================================================================== */
(function () {
  const A = window.App, esc = A.esc, I = A.icon;
  const G = "Design system";
  const PAGES = [["tokens", "Tokens"], ["controls", "Controls"], ["rows", "Rows & lists"], ["containers", "Containers & overlays"], ["feedback", "Feedback"]];
  const noop = 'data-toast="Catalog sample"';

  /* a component sample: preview + the helper call that produces it */
  const ex = (title, html, code, cls = "") => `<div class="ct-ex ${cls}"><div class="ct-ex-h">${esc(title)}</div><div class="ct-ex-v">${html}</div>${code ? `<code class="ct-code">${esc(code)}</code>` : ""}</div>`;
  const sec = (title, body) => `${UI.sectionLabel(title)}<div class="ct-sec">${body}</div>`;
  const css = (name) => getComputedStyle(document.getElementById("screen") || document.body).getPropertyValue(name).trim();

  /* ---------------- tokens ---------------- */
  const COLOURS = ["--bg", "--bg-raised", "--surface", "--surface-2", "--surface-3", "--border", "--border-strong", "--text", "--text-2", "--text-3", "--disabled",
    "--accent", "--accent-ink", "--accent-soft", "--accent-tint", "--danger", "--danger-ink", "--scrim", "--page", "--page-ink", "--page-2"];
  const BLENDS = ["--heat-0", "--heat-1", "--heat-2", "--heat-3", "--heat-4", "--page-tint", "--page-scan", "--sel", "--hl-eink", "--hl-swatch-yellow"];
  const HL = ["yellow", "green", "blue", "red", "purple", "gray"];
  const swatch = (t) => `<div class="ct-sw"><i style="background:var(${t})"></i><span>${t}</span></div>`;
  const themePanel = (theme, label) => `<div class="ct-theme theme-${theme}"><div class="ko-eyebrow">${label}</div>
      <div class="ct-sws">${COLOURS.map(swatch).join("")}</div>
      <div class="ko-eyebrow ct-sub">Named blends</div><div class="ct-sws">${BLENDS.map(swatch).join("")}</div>
      <div class="ko-eyebrow ct-sub">Highlights (--hl-c-* · page tint --hl-*)</div>
      <div class="ct-sws">${HL.map((c) => `<div class="ct-sw"><i style="background:var(--hl-c-${c})"></i><span>--hl-c-${c}</span></div>`).join("")}</div>
      <div class="ct-hlrow">${HL.map((c) => `<mark class="hl s-lighten c-${c}">${c}</mark>`).join(" ")}</div></div>`;
  const TYPE = [["--fs-2xs", "Badge · nav label"], ["--fs-xs", "Caption · section label"], ["--fs-sm", "Metadata · secondary"], ["--fs-md", "Row · body UI"],
    ["--fs-head", "Sheet / dialog title"], ["--fs-lg", "Card title"], ["--fs-xl", "Large glyph"], ["--fs-glyph", "App mark"], ["--fs-display", "Screen title"], ["--fs-2xl", "30"], ["--fs-3xl", "40"], ["--fs-hero", "44"], ["--fs-jumbo", "52"]];
  function tokens() {
    return `${sec("Colour · per theme", `<div class="ct-themes">${themePanel("dark", "Dark")}${themePanel("paper", "Paper")}</div>
        <p class="ct-note">Turn on the E-ink preview in the designer panel: every pair above must stay distinguishable in grayscale (highlights get an underline in e-ink).</p>`)}
      ${sec("Type scale", `<div class="ct-type">${TYPE.map(([t, l]) => `<div class="ct-type-row"><code class="ct-code">${t} · ${esc(css(t))}</code><span style="font-size:var(${t})${t === "--fs-display" ? ";font-family:var(--font-display)" : ""}">${l}</span></div>`).join("")}</div>
        <div class="ct-weights">${["--fw-regular", "--fw-medium", "--fw-semibold", "--fw-bold"].map((w) => `<span style="font-weight:var(${w})">${w}</span>`).join("")}</div>
        <div class="ct-weights"><span style="font-family:var(--font-ui)">--font-ui Inter</span><span style="font-family:var(--font-display)">--font-display Playfair</span><span style="font-family:var(--font-book)">--font-book Literata</span><span lang="ar" dir="rtl">--font-arabic نسخ</span><span style="font-family:var(--font-mono)">--font-mono</span></div>`)}
      ${sec("Spacing (--sp-*)", `<div class="ct-bars">${["half", "1", "1h", "2", "2h", "3", "3h", "4", "5", "6", "8", "10"].map((k) => `<div class="ct-bar"><i style="width:var(--sp-${k})"></i><code class="ct-code">--sp-${k} · ${css("--sp-" + k)}</code></div>`).join("")}</div>`)}
      ${sec("Radii (--r-*)", `<div class="ct-radii">${["tick", "thumb", "cover", "check", "sm", "inner", "md", "mark", "lg", "xl", "pill"].map((k) => `<div class="ct-radius"><i style="border-radius:var(--r-${k})"></i><code class="ct-code">--r-${k}</code></div>`).join("")}</div>`)}
      ${sec("Control heights", `<div class="ct-bars">${[["--h-control", "button"], ["--h-row", "list row"], ["--h-row-compact", "popover row"], ["--h-chip", "chip"], ["--h-seg", "segment"], ["--h-input", "input"], ["--hit", "touch target"], ["--h-header", "header"], ["--h-nav", "bottom nav"]].map(([t, l]) => `<div class="ct-bar"><i class="v" style="height:var(${t})"></i><code class="ct-code">${t} · ${css(t)} · ${l}</code></div>`).join("")}</div>`)}
      ${sec("Icons (--icon-*, --stroke-*)", `<div class="ct-icons">${["2xs", "xs", "sm", "tile", "md", "key", "lg", "xl", "2xl"].map((k) => `<div class="ct-icon"><span class="ct-ic" style="--s:var(--icon-${k})">${I("book-open")}</span><code class="ct-code">--icon-${k}</code></div>`).join("")}</div>`)}
      ${sec("Borders, rings and shadows", `<div class="ct-radii">${["--ring", "--ring-strong", "--ring-accent", "--ring-eink", "--bar-accent", "--shadow-sm", "--shadow", "--shadow-cover"].map((t) => `<div class="ct-radius"><i style="box-shadow:var(${t})"></i><code class="ct-code">${t}</code></div>`).join("")}</div>`)}`;
  }

  /* ---------------- controls ---------------- */
  function controls() {
    const kinds = ["primary", "secondary", "ghost", "danger"];
    return `${sec("Buttons · 40px in every variant", `<div class="ct-grid">
        ${kinds.map((k) => ex(k, UI.button({ label: k[0].toUpperCase() + k.slice(1), kind: k, attrs: noop }), `UI.button({label, kind:"${k}"})`)).join("")}
        ${ex("with icon", UI.button({ label: "Resume", icon: "play", kind: "primary", attrs: noop }), `UI.button({label, icon:"play", kind:"primary"})`)}
        ${ex("small label", UI.button({ label: "Details", size: "sm", attrs: noop }), `UI.button({label, size:"sm"})`)}
        ${ex("icon only", UI.button({ label: "Bookmark", icon: "bookmark", square: true, attrs: noop }), `UI.button({label, icon, square:true})`)}
        ${ex("disabled", UI.button({ label: "Save", kind: "primary", disabled: true }), `UI.button({…, disabled:true})`)}
        ${ex("link", UI.button({ label: "See all", kind: "link", attrs: noop }), `UI.button({label, kind:"link"})`)}
        ${ex("block", UI.button({ label: "Check for updates", kind: "primary", block: true, attrs: noop }), `UI.button({…, block:true})`, "wide")}
      </div>`)}
      ${sec("Icon buttons", `<div class="ct-grid">
        ${ex("default", UI.iconButton({ icon: "search", label: "Search", attrs: noop }), `UI.iconButton({icon, label})`)}
        ${ex("active", UI.iconButton({ icon: "heart", label: "Favourite", active: true, attrs: noop }), `UI.iconButton({…, active:true})`)}
        ${ex("pressed (on)", UI.iconButton({ icon: "keyboard", label: "Keyboard", cls: "on", attrs: noop }), `UI.iconButton({…, cls:"on"})`)}
        ${ex("md · sm", UI.iconButton({ icon: "chevron-left", label: "Previous", size: "md", attrs: noop }) + UI.iconButton({ icon: "x", label: "Remove", size: "sm", attrs: noop }), `UI.iconButton({…, size:"md"|"sm"})`)}
        ${ex("disabled", UI.iconButton({ icon: "chevron-right", label: "Next", disabled: true }), `UI.iconButton({…, disabled:true})`)}
        ${ex("help", `<button class="ko-help-btn" ${noop} aria-label="Help">${I("circle-help", "sm")}</button><button class="ko-help-btn on" ${noop} aria-label="Help">${I("circle-help", "sm")}</button>`, `.ko-help-btn (.on)`)}
      </div>`)}
      ${sec("Segmented control", `<div class="ct-grid">
        ${ex("default", UI.seg([{ label: "Off", attrs: noop }, { label: "On", on: true, attrs: noop }, { label: "Auto", attrs: noop }]), `UI.seg([{label, on}])`)}
        ${ex("block + icons", UI.seg([{ label: "Reading", icon: "book-open", on: true, attrs: noop }, { label: "On hold", icon: "pause", attrs: noop }, { label: "Finished", icon: "circle-check", attrs: noop }], { block: true }), `UI.seg(items, {block:true})`, "wide")}
        ${ex("sm", UI.seg([{ label: "4", attrs: noop }, { label: "6", on: true, attrs: noop }, { label: "9", attrs: noop }], { size: "sm" }), `UI.seg(items, {size:"sm"})`)}
        ${ex("roomy", UI.seg([{ label: "Fast", attrs: noop }, { label: "Full", on: true, attrs: noop }], { size: "roomy" }), `UI.seg(items, {size:"roomy"})`)}
      </div>`)}
      ${sec("Tabs", `${UI.tabs([{ label: "Library", on: true, attrs: noop }, { label: "Favorites", attrs: noop }, { label: "Collections", n: 4, attrs: noop }])}
        <code class="ct-code ct-pad">UI.tabs([{label, on, n}])</code>
        ${UI.tabs([{ label: "Oxford", on: true, attrs: noop }, { label: "Wikipedia", attrs: noop }, { label: "Webster", attrs: noop }], { cls: "ko-tabs--sm" })}
        <code class="ct-code ct-pad">UI.tabs(items, {cls:"ko-tabs--sm"})</code>`)}
      ${sec("Chips · single-line scroller", `<div class="ct-grid">
        ${ex("row", UI.chipRow([{ label: "All", n: 24, on: true, attrs: noop }, { label: "Reading", n: 3, attrs: noop }, { label: "Finished", icon: "circle-check", attrs: noop }, { label: "Add", add: true, icon: "plus", attrs: noop }]), `UI.chipRow([{label, n, on, icon, add}])`, "wide")}
        ${ex("large (recent searches)", UI.chip({ label: "animal farm", icon: "history", size: "lg", attrs: noop }), `UI.chip({label, icon, size:"lg"})`)}
      </div>`)}
      ${sec("Toggle · check · radio · stars", `<div class="ct-grid">
        ${ex("toggle", UI.toggle(false) + UI.toggle(true), `UI.toggle(on)`)}
        ${ex("check", UI.check(false) + UI.check(true), `UI.check(on)`)}
        ${ex("radio", UI.radio(false) + UI.radio(true), `UI.radio(on)`)}
        ${ex("check row", UI.checkRow({ label: "Connect automatically", on: true, attrs: noop }), `UI.checkRow({label, on})`)}
        ${ex("stars", UI.stars(3, { attrs: () => noop }), `UI.stars(n)`)}
        ${ex("stars lg", UI.stars(4, { size: "lg", attrs: () => noop }), `UI.stars(n, {size:"lg"})`)}
      </div>`)}
      ${sec("Slider row · the one numeric setting", `${UI.sliderRow({ label: "Brightness", pct: 62, value: 62, unit: "%", minIcon: "sun-dim", maxIcon: "sun" })}
        <code class="ct-code ct-pad">UI.sliderRow({label, pct, value, unit, slide, step, minIcon, maxIcon})  ·  alias App.sliderRow</code>`)}
      ${sec("Inputs", `<div class="ct-grid">
        ${ex("input", UI.input({ icon: "search", placeholder: "Search all options" }), `UI.input({icon, placeholder})`, "wide")}
        ${ex("on the page background", UI.input({ icon: "search", placeholder: "Search highlights", card: true }), `UI.input({…, card:true})`, "wide")}
        ${ex("keyboard field", `<div class="kb-field kb-field--compact empty"><span class="kb-text"><span class="kb-val"></span><span class="kb-ph">Folder name</span></span></div><div class="kb-field-help">The sidecar folder is renamed too.</div>`, `App.kbField(target, {placeholder, cls:"kb-field--compact"})`, "wide")}
      </div>`)}`;
  }

  /* ---------------- rows & lists ---------------- */
  function rows() {
    return `${sec("Rows in a group (UI.group)", UI.group([
        UI.row({ tile: "sun", label: "Frontlight", sub: "62% · warm 35%", trailing: "chevron", attrs: noop }),
        UI.row({ tile: "moon", label: "Night mode", trailing: "toggle", on: true, attrs: noop }),
        UI.row({ tile: "type", label: "Default font", value: "Literata", trailing: "chevron", attrs: noop }),
        UI.row({ tile: "list-ordered", label: "Items per page", trailing: "stepper", stepper: { value: 14, attrsMinus: noop, attrsPlus: noop }, tag: "div" }),
        UI.row({ tile: "lock", label: "Locked option", sub: "disabled", disabled: true }),
        UI.row({ tile: "trash-2", label: "Delete all history", danger: true, attrs: noop }),
      ]))}
      <code class="ct-code ct-pad">UI.row({tile|icon, label, sub, value, trailing:"chevron|toggle|radio|check|stepper|none", on, disabled, danger, sel})</code>
      ${sec("Radio and check rows", UI.group([
        UI.row({ label: "Portrait", trailing: "radio", on: true, attrs: noop }),
        UI.row({ label: "Landscape", trailing: "radio", attrs: noop }),
        UI.row({ label: "Show page numbers", trailing: "check", on: true, attrs: noop }),
      ]))}
      ${sec("List (UI.list) and labels", UI.list([
        UI.row({ icon: "lightbulb", label: "Frontlight", trailing: "toggle", on: true, attrs: noop }),
        UI.row({ icon: "settings-2", label: "Frontlight settings", trailing: "chevron", attrs: noop }),
      ]) + `<div class="ct-grid">
        ${ex("section label", UI.sectionLabel("Available networks"), `UI.sectionLabel(text)`, "wide")}
        ${ex("eyebrows", UI.eyebrow("Time read · this week") + UI.eyebrow("Continue reading", { accent: true, icon: "book-open" }) + UI.eyebrow("New version", { strong: true }), `UI.eyebrow(text, {accent, strong, icon})`, "wide")}
        ${ex("icon tiles", UI.iconTile("book-open") + UI.iconTile("settings", { size: "lg" }) + UI.iconTile("info", { accent: true }), `UI.iconTile(name, {size:"lg", accent, raised})`)}
      </div>`)}
      ${sec("Tool grid (UI.tool)", `<div class="ct-tools">${[["copy", "Copy"], ["scissors", "Cut"], ["clipboard-paste", "Paste"], ["pencil", "Rename"]].map(([ic, l]) => UI.tool({ icon: ic, label: l, size: "lg", attrs: noop })).join("")}${UI.tool({ icon: "trash-2", label: "Delete", size: "lg", danger: true, attrs: noop })}${UI.tool({ icon: "share", label: "Disabled", size: "lg", disabled: true })}</div>
        <code class="ct-code ct-pad">UI.tool({icon, label, size:"lg", danger, disabled})</code>`)}`;
  }

  /* ---------------- containers & overlays ---------------- */
  function containers() {
    const b = DB.book("animal-farm") || DB.BOOKS[0];
    return `${sec("Cards (UI.card)", `<div class="ct-grid">
        ${ex("card", UI.card(`<div class="ko-card-title">Books this year</div><div class="faint">On track for your goal</div>`), `UI.card(html)`)}
        ${ex("tap · selected", UI.card(`<b>Default</b><div>Literata · 22 pt</div>`, { tap: true, on: true, attrs: noop }), `UI.card(html, {tap:true, on:true})`)}
        ${ex("accent (shortcut)", UI.card(`<b>Reading statistics</b>`, { accent: true }), `UI.card(html, {accent:true})`)}
        ${ex("dashed (add)", UI.card(`${I("plus")} New collection`, { dashed: true, tap: true, attrs: noop }), `UI.card(html, {dashed:true})`)}
        ${ex("sunken", UI.card(`You're up to date`, { sunken: true, sm: true }), `UI.card(html, {sunken:true, sm:true})`)}
      </div>`)}
      ${sec("Headers", `<div class="ct-stage ct-flat">${UI.screenHead({ title: "Library", display: true, count: "24 books", actions: UI.iconButton({ icon: "search", label: "Search", attrs: noop }) })}</div>
        <code class="ct-code ct-pad">UI.screenHead({title, display:true, count, actions}) — Playfair only for top-level screens</code>
        <div class="ct-stage ct-flat">${UI.pageHead({ title: "Screen", crumbs: ["Settings", "Display & E-ink"], back: noop, rule: true })}</div>
        <code class="ct-code ct-pad">UI.pageHead({title, crumbs, back, rule}) — level-2 pages, Inter</code>`)}
      ${sec("Bottom sheet head (UI.sheetHead)", `<div class="ct-stage"><div class="ko-sheet ct-static"><div class="grip"></div>
        ${UI.sheetHead({ title: "Frontlight", sub: "62% brightness · 35% warmth", closeAttrs: noop })}
        ${UI.sliderRow({ label: "Warmth", pct: 35, value: 35, unit: "%", minIcon: "snowflake", maxIcon: "flame" })}</div></div>
        <code class="ct-code ct-pad">UI.sheetHead({title, sub, lead, actions}) — the × is always on the right</code>`)}
      ${sec("Dialog (UI.dialog)", `<div class="ct-stage">${UI.dialog({ cls: "ct-static", title: "Delete this book?", icon: "trash-2", danger: true,
          body: "The file and its highlights, notes and reading progress will be removed.",
          bodyHtml: UI.kv([["Format", "EPUB"], ["Size", "412 KB"]]) + UI.checkRow({ label: "Also delete highlights", attrs: noop }),
          actions: [{ label: "Cancel", kind: "ghost", attrs: noop }, { label: "Delete", kind: "danger", attrs: noop }] })}</div>
        <code class="ct-code ct-pad">UI.dialog({title, icon, danger, body, bodyHtml, actions:[button opts]}) · UI.kv([[k, v]])</code>`)}
      ${sec("Popover", `<div class="ct-stage"><div class="ko-popover ct-static">${UI.sectionLabel("Sort by")}${UI.row({ icon: "a-large-small", label: "Title", trailing: "radio", on: true, attrs: noop })}${UI.row({ icon: "user", label: "Author", trailing: "radio", attrs: noop })}</div></div>
        <code class="ct-code ct-pad">&lt;div class="ko-popover"&gt; + UI.row(…) — 44px rows, anchored to the button that opened it</code>`)}
      ${sec("Cover, badge, pills", `<div class="ct-grid">
        ${ex("cover + badge", `<div class="ct-cover">${UI.cover(b, { badge: "8%" })}</div><div class="ct-cover">${UI.cover(b, { badge: "New", accent: true })}</div>`, `UI.cover(book, {badge, accent})`)}
        ${ex("pills", UI.pill("New", { kind: "accent" }) + UI.pill("Reading", { kind: "current" }) + UI.pill("Finished", { kind: "soft" }) + UI.pill("Edited", { kind: "tint" }) + UI.pill("Beta", { caps: true }), `UI.pill(text, {kind:"accent|current|soft|tint", caps})`, "wide")}
      </div>`)}`;
  }

  /* ---------------- feedback ---------------- */
  function feedback() {
    return `${sec("Progress", `<div class="ct-grid">
        ${ex("thin · 2px", UI.progress(35, { size: "thin" }), `UI.progress(pct, {size:"thin"})`, "wide")}
        ${ex("default · 3px", UI.progress(62), `UI.progress(pct)`, "wide")}
        ${ex("md · 4px", UI.progress(80, { size: "md" }), `UI.progress(pct, {size:"md"})`, "wide")}
      </div>`)}
      ${sec("Meter (stacked usage)", `<div class="ct-pad">${UI.meter([{ pct: 32, kind: 1 }, { pct: 8, kind: 2 }, { pct: 9, kind: 3 }], {
          head: `<span>${I("hard-drive", "sm")}Storage</span><span class="num"><b>12.4 GB</b> of 28.6 GB used</span>`,
          legend: [{ label: "Books", value: "9.1 GB", kind: 1 }, { label: "Cache", value: "0.8 GB", kind: 2 }, { label: "System", value: "2.5 GB", kind: 3 }, { label: "Free", value: "16.2 GB", kind: "free" }] })}</div>
        <code class="ct-code ct-pad">UI.meter(parts, {head, legend})</code>`)}
      ${sec("Stat tiles", `<div class="ct-pad">${UI.stats([{ value: "412", label: "pages" }, { value: "9", label: "sessions" }, { value: "3", label: "books" }, { value: "14", label: "highlights" }], { card: true, center: true })}</div>
        <code class="ct-code ct-pad">UI.stats([{value, label}], {card, center}) · UI.statTile({value, label})</code>`)}
      ${sec("Selection mark · spinner · toast", `<div class="ct-grid">
        ${ex("selection mark", `<div class="ct-selhost"><span class="ko-selmark">${I("check", "sm")}</span></div>`, `.ko-selmark`)}
        ${ex("busy", `${I("loader-circle", "ko-spin")}`, `App.icon(name, "ko-spin")`)}
        ${ex("toast", `<div class="ko-toast ct-static">Cache cleared · 142 MB freed</div>`, `App.toast(text)`, "wide")}
      </div>`)}
      ${sec("Empty state (UI.empty)", UI.empty({ icon: "highlighter", title: "Nothing here yet", text: "Long-press a word, then drag to select text.", action: UI.button({ label: "Open a book", kind: "primary", attrs: noop }) }))}`;
  }

  const RENDER = { tokens, controls, rows, containers, feedback };
  A.screen("catalog", {
    title: "Design system",
    render(p) {
      const page = RENDER[p.page] ? p.page : "tokens";
      return `<div class="ko-view ct">${A.statusBar()}
        ${UI.screenHead({ title: "Design system", back: 'data-go="settings"' })}
        ${UI.tabs(PAGES.map(([k, l]) => ({ label: l, on: k === page, attrs: `data-go="catalog" data-params='${A.attrs({ page: k })}'` })), { cls: "ko-tabs--sm ct-tabs" })}
        <div class="ko-scroll ct-body">${RENDER[page]()}<div class="ct-end"></div></div>
      </div>`;
    },
  });
  PAGES.forEach(([k, l]) => A.demo(G, l, `#/catalog?page=${k}`));
})();
