/* ==========================================================================
   Folio UI — small HTML helpers that produce the markup of the component library
   (css/components.css). Every helper returns an HTML string; behaviour stays in
   data attributes handled by core.js (data-action / data-open / data-go / data-close).

   `attrs` (every helper): a raw attribute string ('data-action="x" data-arg="1"') or an object
   ({ action: "x", arg: 1, open: "sheet", params: {...}, go: "screen", close: true, id: "..." }).
   `cls`: extra classes for the root element.

   Catalog of every component in every state: #/catalog (designer group "Design system").
   ========================================================================== */
(function () {
  const esc = App.esc;
  const icon = (n, c) => App.icon(n, c);
  const UI = (window.UI = {});

  /** join class names, skipping falsy ones */
  UI.cls = (...parts) => parts.flat().filter(Boolean).join(" ");
  /** attribute string from a string or {action, arg, open, params, go, close, ...} */
  UI.attrs = (a) => {
    if (!a) return "";
    if (typeof a === "string") return a;
    return Object.entries(a).filter(([, v]) => v !== undefined && v !== null && v !== false).map(([k, v]) => {
      if (k === "close") return "data-close";
      if (k === "params") return `data-params="${App.attrs(v)}"`;
      if (["action", "arg", "open", "go", "toast", "id", "k", "dir", "tab"].includes(k)) return `data-${k}="${esc(v)}"`;
      return v === true ? k : `${k}="${esc(v)}"`;
    }).join(" ");
  };

  /* ---------------- buttons ---------------- */
  /** UI.button({label, kind:"primary|secondary|ghost|danger|link", icon, size:"sm", block, square, disabled, cls, attrs})
      40px high in every variant; `square` = icon-only 40x40; kind "link" = accent text button (no box). */
  UI.button = (o = {}) => {
    const kind = o.kind || "secondary";
    const ic = o.icon ? icon(o.icon, o.iconCls ?? "sm") : "";
    if (kind === "link") return `<button class="${UI.cls("ko-link", o.cls)}" ${UI.attrs(o.attrs)}>${ic}${o.html ?? esc(o.label ?? "")}</button>`;
    const c = UI.cls("ko-btn", kind !== "secondary" && `ko-btn--${kind}`, o.size === "sm" && "ko-btn--sm", o.square && "ko-btn--icon", o.block && "ko-btn--block", o.cls);
    return `<button class="${c}" ${UI.attrs(o.attrs)}${o.disabled ? " disabled" : ""}${o.square && o.label ? ` aria-label="${esc(o.label)}"` : ""}>${ic}${o.square ? "" : o.html ?? esc(o.label ?? "")}</button>`;
  };
  /** UI.iconButton({icon, label (aria), size:"md"|"sm", active, disabled, cls, attrs}) — 44px (md 40, sm 32 + hit area) */
  UI.iconButton = (o = {}) => `<button class="${UI.cls("ko-icon-btn", o.size && `ko-icon-btn--${o.size}`, o.active && "active", o.cls)}" ${UI.attrs(o.attrs)}${o.disabled ? " disabled" : ""} aria-label="${esc(o.label || o.icon)}">${icon(o.icon, o.iconCls || "")}</button>`;
  /** the × of every sheet / page header */
  UI.closeButton = (o = {}) => UI.iconButton({ icon: "x", label: "Close", attrs: o.attrs || "data-close", cls: o.cls });

  /* ---------------- selection controls ---------------- */
  UI.toggle = (on) => App.toggle(on);
  UI.check = (on) => App.check(on);
  UI.radio = (on) => App.radio(on);
  /** UI.checkRow({label, on, attrs, cls}) — a check box + label line inside dialogs and cards */
  UI.checkRow = (o) => `<button class="${UI.cls("ko-check-row", o.cls)}" ${UI.attrs(o.attrs)}>${App.check(!!o.on)}<span>${esc(o.label)}</span></button>`;
  /** UI.seg(items [{label, icon, on, attrs, html}], {block, size:"sm"|"roomy", cls, attrs}) — segmented control */
  UI.seg = (items, o = {}) => {
    const icons = items.some((i) => i.icon);
    return `<div class="${UI.cls("ko-seg", o.block && "ko-seg--block", icons && "ko-seg--icons", o.size && `ko-seg--${o.size}`, o.cls)}" ${UI.attrs(o.attrs)}>${items.map((i) =>
      `<button class="${UI.cls(i.on && "on", i.cls)}" ${UI.attrs(i.attrs)}>${i.icon ? icon(i.icon, "sm") : ""}${i.html ?? esc(i.label ?? "")}</button>`).join("")}</div>`;
  };
  /** UI.tabs(items [{label, on, n, attrs}], {cls}) — text tabs with the accent underline */
  UI.tabs = (items, o = {}) => `<div class="${UI.cls("ko-tabs", o.cls)}" role="tablist">${items.map((t) =>
    `<button class="${UI.cls("ko-tab", t.on && "on", t.cls)}" role="tab" aria-selected="${!!t.on}" ${UI.attrs(t.attrs)}>${t.html ?? esc(t.label)}${t.n != null ? `<span class="n">${t.n}</span>` : ""}</button>`).join("")}${o.after || ""}</div>`;
  /** UI.chip({label, icon, on, n, size:"lg", add, attrs, cls}) */
  UI.chip = (o = {}) => `<button class="${UI.cls("ko-chip", o.on && "on", o.size === "lg" && "ko-chip--lg", o.add && "ko-chip--add", o.cls)}" ${UI.attrs(o.attrs)}${o.add ? ` aria-label="${esc(o.label || "Add")}"` : ""}>${o.icon ? icon(o.icon, "sm") : ""}${o.add ? "" : o.html ?? esc(o.label ?? "")}${o.n != null ? `<span class="n">${o.n}</span>` : ""}</button>`;
  /** UI.chipRow(chips (html strings or chip options), {cls}) — single-line scroller, never wraps */
  UI.chipRow = (chips, o = {}) => `<div class="${UI.cls("ko-chips", o.cls)}">${chips.map((c) => (typeof c === "string" ? c : UI.chip(c))).join("")}</div>`;

  /* ---------------- rows and lists ---------------- */
  /** UI.iconTile(name, {size:"lg", accent, raised, cls}) — the 32px (lg 36px) leading icon tile */
  UI.iconTile = (name, o = {}) => `<span class="${UI.cls("ko-icon-tile", o.size === "lg" && "ko-icon-tile--lg", o.accent && "ko-icon-tile--accent", o.raised && "ko-icon-tile--raised", o.cls)}">${icon(name)}</span>`;
  /** UI.row({icon, tile, label, sub, value, trailing:"chevron|toggle|radio|check|stepper|none"|html, on, disabled, danger, sel, tag, cls, attrs, stepper:{value, attrsMinus, attrsPlus}})
      icon = plain leading icon; tile = icon name drawn in an icon tile; `on` drives toggle/radio/check. */
  UI.row = (o = {}) => {
    const tag = o.tag || "button";
    const lead = o.tile ? UI.iconTile(o.tile, { accent: o.tileAccent }) : o.icon ? icon(o.icon) : o.lead || "";
    const t = o.trailing || "none";
    const trail = t === "chevron" ? icon("chevron-right", "chev")
      : t === "toggle" ? App.toggle(!!o.on) : t === "radio" ? App.radio(!!o.on) : t === "check" ? App.check(!!o.on)
      : t === "stepper" ? `<span class="ko-stepper"><button ${UI.attrs(o.stepper?.attrsMinus)} aria-label="Less">${icon("minus", "sm")}</button><span class="val num">${esc(o.stepper?.value ?? o.value ?? "")}</span><button ${UI.attrs(o.stepper?.attrsPlus)} aria-label="More">${icon("plus", "sm")}</button></span>`
      : t === "none" ? "" : t;
    const value = o.value != null && t !== "stepper" ? `<span class="value">${esc(o.value)}</span>` : "";
    const label = o.labelHtml ?? esc(o.label ?? "");
    return `<${tag} class="${UI.cls("ko-row", o.danger && "ko-row--danger", o.disabled && "disabled", o.sel && "sel", o.cls)}" ${UI.attrs(o.attrs)}>${lead}<span class="label">${label}${o.sub ? `<span class="sub">${o.subHtml ?? esc(o.sub)}</span>` : ""}</span>${value}${trail}</${tag}>`;
  };
  /** UI.group(rows, {sunken, cls}) — rows in a rounded card */
  UI.group = (rows, o = {}) => `<div class="${UI.cls("ko-group", o.sunken && "ko-group--sunken", o.cls)}">${[].concat(rows).join("")}</div>`;
  /** UI.list(rows, {inset, cls}) — full-bleed rows with hairlines */
  UI.list = (rows, o = {}) => `<div class="${UI.cls("ko-list", o.inset && "inset", o.cls)}">${[].concat(rows).join("")}</div>`;
  /** UI.sectionLabel(text, {cls, html}) — uppercase label above a group */
  UI.sectionLabel = (text, o = {}) => `<div class="${UI.cls("ko-section-label", o.cls)}">${o.html ?? esc(text)}</div>`;
  /** UI.eyebrow(text, {accent, strong, icon, tag, cls}) — uppercase caption (no padding) */
  UI.eyebrow = (text, o = {}) => `<${o.tag || "div"} class="${UI.cls("ko-eyebrow", o.accent && "ko-eyebrow--accent", o.strong && "ko-eyebrow--strong", o.cls)}">${o.icon ? icon(o.icon, "sm") : ""}${o.html ?? esc(text)}</${o.tag || "div"}>`;

  /* ---------------- headers ---------------- */
  /** UI.screenHead({title, display, plain, count, back:attrs, actions, cls}) — screen header; `display` = Playfair (top-level screens only), default title Inter 17 (`plain`: 18) */
  UI.screenHead = (o = {}) => `<header class="${UI.cls("ko-header", o.cls)}">${o.back ? UI.iconButton({ icon: "arrow-left", label: "Back", attrs: o.back, cls: "back" }) : ""}<span class="${UI.cls("title", o.display ? "display" : !o.plain && "l2", o.titleCls)}">${o.titleHtml ?? esc(o.title)}</span>${o.count != null ? `<span class="count">${esc(o.count)}</span>` : ""}<span class="spacer"></span>${o.actions || ""}</header>`;
  /** UI.pageHead({title, crumbs:[html|{label, attrs}], back:attrs, actions, rule, cls}) — level-2 page header (crumbs over an Inter title) */
  UI.pageHead = (o = {}) => {
    const crumbs = o.crumbs && o.crumbs.length ? `<div class="ko-crumbs">${o.crumbs.map((c) => (typeof c === "string" ? c : `<button ${UI.attrs(c.attrs)}>${esc(c.label)}</button>`)).join('<span class="sep">›</span>')}</div>` : "";
    return `<header class="${UI.cls("ko-header ko-header--page", o.rule && "ko-header--rule", o.cls)}">${o.back !== false ? UI.iconButton({ icon: "arrow-left", label: "Back", attrs: o.back || "data-close" }) : ""}<div class="grow">${crumbs}<div class="${UI.cls("ko-page-title ellipsis", o.titleCls)}">${o.titleHtml ?? esc(o.title)}</div></div>${o.actions || ""}</header>`;
  };
  /** UI.sheetHead({title, sub, lead, actions, close:true, rule, cls}) — THE sheet header: [lead] title/sub … actions [×] */
  UI.sheetHead = (o = {}) => `<div class="${UI.cls("ko-sheet-head", o.rule && "ko-sheet-head--rule", o.cls)}">${o.lead || ""}<div class="grow"><span class="title">${o.titleHtml ?? esc(o.title)}</span>${o.sub || o.subHtml ? `<span class="sub">${o.subHtml ?? esc(o.sub)}</span>` : ""}${o.extra || ""}</div>${o.actions || ""}${o.close === false ? "" : UI.closeButton({ attrs: o.closeAttrs })}</div>`;

  /* ---------------- containers ---------------- */
  /** UI.card(body, {flush, sm, tap, accent, dashed, sunken, on, tag, attrs, cls}) */
  UI.card = (body, o = {}) => {
    const tag = o.tag || (o.tap ? "button" : "div");
    return `<${tag} class="${UI.cls("ko-card", o.flush && "ko-card--flush", o.sm && "ko-card--sm", o.tap && "ko-card--tap", o.accent && "ko-card--accent", o.dashed && "ko-card--dashed", o.sunken && "ko-card--sunken", o.on && "on", o.cls)}" ${UI.attrs(o.attrs)}>${body}</${tag}>`;
  };
  /** UI.dialog({title, icon, danger, sub, body, bodyHtml, actions:[button opts]|html, scroll, cls}) — compact centred dialog */
  UI.dialog = (o = {}) => {
    const acts = Array.isArray(o.actions) ? o.actions.map((a) => (typeof a === "string" ? a : UI.button(a))).join("") : o.actions || "";
    return `<div class="${UI.cls("ko-dialog", o.scroll && "ko-dialog--scroll", o.cls)}" role="dialog">
      ${o.head ?? `<div class="${UI.cls("ko-dialog-title", o.danger && "danger")}">${o.icon ? icon(o.icon) : ""}<span class="grow">${o.titleHtml ?? esc(o.title ?? "")}</span>${o.titleExtra || ""}</div>`}
      ${o.sub ? `<div class="ko-dialog-sub">${esc(o.sub)}</div>` : ""}
      ${o.body ? `<div class="ko-dialog-body">${esc(o.body)}</div>` : ""}${o.bodyHtml || ""}
      ${acts ? `<div class="ko-dialog-actions">${acts}</div>` : ""}
    </div>`;
  };
  /** UI.kv([[key, value], ...]) — key/value list on a sunken surface */
  UI.kv = (list, o = {}) => `<div class="${UI.cls("ko-kv", o.cls)}">${list.map(([a, b]) => `<div><span>${esc(a)}</span><span>${esc(b)}</span></div>`).join("")}</div>`;
  /** UI.empty({icon, title, text, action, cls}) — empty state */
  UI.empty = (o = {}) => `<div class="${UI.cls("ko-empty", o.cls)}">${icon(o.icon || "inbox")}${o.title ? `<div class="h">${esc(o.title)}</div>` : ""}${o.text ? `<div>${esc(o.text)}</div>` : ""}${o.html || ""}${o.action || ""}</div>`;

  /** UI.tool({icon, label, size:"lg", danger, disabled, attrs, cls}) — icon over a short label (action grids, toolbars) */
  UI.tool = (o) => `<button class="${UI.cls("ko-tool", o.size === "lg" && "ko-tool--lg", o.danger && "ko-tool--danger", o.cls)}" ${UI.attrs(o.attrs)}${o.disabled ? " disabled" : ""}>${o.iconHtml ?? icon(o.icon)}<span>${o.html ?? esc(o.label)}</span></button>`;
  /** UI.stars(n, {size:"lg", attrs: (i) => attrs, cls}) — 5-star rating; filled stars = rated */
  UI.stars = (n, o = {}) => `<span class="${UI.cls("ko-stars", o.size === "lg" && "ko-stars--lg", o.cls)}">${[1, 2, 3, 4, 5].map((i) => `<button class="${i <= n ? "on" : ""}" ${o.attrs ? UI.attrs(o.attrs(i)) : ""} aria-label="${i} star${i > 1 ? "s" : ""}">${icon("star")}</button>`).join("")}</span>`;

  /* ---------------- feedback / data ---------------- */
  /** UI.badge(text, {accent}) — % badge over a cover */
  UI.badge = (text, o = {}) => `<span class="${UI.cls("ko-badge", o.accent && "ko-badge--accent", o.cls)}">${o.icon ? icon(o.icon, "sm") : ""}${esc(text)}</span>`;
  /** UI.pill(text, {kind:"accent|current|soft|tint", caps, sm, cls}) — inline status label */
  UI.pill = (text, o = {}) => `<span class="${UI.cls("ko-pill", o.kind && `ko-pill--${o.kind}`, o.caps && "ko-pill--caps", o.sm && "ko-pill--sm", o.cls)}">${esc(text)}</span>`;
  /** UI.progress(pct, {size:"thin"|"md", cls}) — thin accent progress line (default 3px) */
  UI.progress = (pct, o = {}) => App.progress(pct, UI.cls(o.size && `ko-progress--${o.size}`, o.cls));
  /** UI.meter(parts [{pct, kind:1|2|3}], {legend:[{label, value, kind}], head:html, cls}) — stacked usage bar */
  UI.meter = (parts, o = {}) => `${o.head ? `<div class="ko-meter-head">${o.head}</div>` : ""}<div class="${UI.cls("ko-meter", o.cls)}">${parts.map((p) => `<i class="m-${p.kind}" style="width:${p.pct}%"></i>`).join("")}<i class="m-free"></i></div>${o.legend ? `<div class="ko-meter-legend">${o.legend.map((l) => `<span><i class="m-${l.kind}"></i>${esc(l.label)} <b class="num">${esc(l.value)}</b></span>`).join("")}</div>` : ""}`;
  /** UI.statTile({value, unit, label}) — one value + caption tile; UI.stats(tiles, {card, center, cls}) lays them out with dividers */
  UI.statTile = (o) => `<div class="ko-stat"><b class="num">${o.valueHtml ?? esc(o.value)}</b><span>${esc(o.label)}</span></div>`;
  UI.stats = (tiles, o = {}) => `<div class="${UI.cls("ko-stats", o.card && "ko-stats--card", o.center && "ko-stats--center", o.cls)}">${tiles.map((t) => (typeof t === "string" ? t : UI.statTile(t))).join("")}</div>`;
  /** UI.input({icon, placeholder, value, card, attrs, cls}) — text field (static: real typing goes through App.kbField) */
  UI.input = (o = {}) => `<label class="${UI.cls("ko-input", o.card && "ko-input--card", o.cls)}">${o.icon ? icon(o.icon) : ""}<input ${UI.attrs(o.attrs)} placeholder="${esc(o.placeholder || "")}" value="${esc(o.value || "")}"></label>`;
  /** UI.cover(book, {badge, accent, thumb, cls}) — book cover (Cover.html: generated cover art + optional % badge) */
  UI.cover = (book, o = {}) => Cover.html(book, { badge: o.badge, badgeCls: o.accent ? "ko-badge--accent" : "", cls: UI.cls(o.thumb && "ko-cover--thumb", o.cls) });

  /**
   * The ONE slider-setting row. Use it for every numeric slider (brightness, warmth, font size, margins, contrast...).
   * UI.sliderRow({ label, icon, pct: 0..100, value: "62", unit: "%", slide: "actionName", step: "actionName", id, minIcon, maxIcon, cls })
   * - dragging calls App.actions[slide](el, v0to1, done); the −/+ buttons call App.actions[step](el) with el.dataset.dir = "-1"|"1"
   * - minIcon/maxIcon (e.g. "sun-dim"/"sun") replace − and + with meaningful end icons
   * App.sliderRow is the same function (kept as an alias).
   */
  UI.sliderRow = (o) => `<div class="${UI.cls("ko-sr", o.cls)}" ${o.id ? `data-id="${o.id}"` : ""}>
    <span class="lbl">${o.icon ? App.icon(o.icon) : ""}${o.labelHtml ?? esc(o.label)}</span>
    <button class="step" data-action="${o.step || ""}" data-dir="-1" data-id="${o.id || ""}" aria-label="Decrease">${App.icon(o.minIcon || "minus")}</button>
    ${App.slider(o.pct, `data-slide="${o.slide || ""}" data-id="${o.id || ""}"`)}
    <button class="step" data-action="${o.step || ""}" data-dir="1" data-id="${o.id || ""}" aria-label="Increase">${App.icon(o.maxIcon || "plus")}</button>
    <span class="val">${esc(o.value)}${o.unit ? `<small>${esc(o.unit)}</small>` : ""}</span>
  </div>`;
  App.sliderRow = UI.sliderRow;
})();
