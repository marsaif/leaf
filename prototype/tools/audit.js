/* Folio design linter — in-page part. Evaluated by tools/audit.py once per state.
   (cfg) => { issues: [...], metrics: [...], sizes: {fs: count}, owner }
   cfg carries the explicit allow-lists defined at the top of audit.py. */
(cfg) => {
  const scr = document.getElementById("screen");
  const SR = scr.getBoundingClientRect();
  const issues = [], metrics = [], sizes = {};
  const CS = new Map();
  const cs = (el) => { let s = CS.get(el); if (!s) { s = getComputedStyle(el); CS.set(el, s); } return s; };
  const any = (el, sels) => sels.length && sels.some((s) => { try { return el.matches(s); } catch { return false; } });
  const within = (el, sels) => sels.length && sels.some((s) => { try { return !!el.closest(s); } catch { return false; } });
  const STATE = new Set(["on", "sel", "active", "selected", "current", "open", "lucide", "ko-hit"]);

  /* ---------- colour maths ---------- */
  const probe = document.createElement("span"); scr.appendChild(probe);
  const PC = new Map();
  const parse = (s) => {
    if (!s) return null;
    if (PC.has(s)) return PC.get(s);
    let m, out = null;
    const str = s.trim();
    if ((m = str.match(/^rgba?\(([^)]+)\)$/))) {
      const p = m[1].split(/[\s,\/]+/).filter(Boolean).map(Number);
      out = [p[0], p[1], p[2], p.length > 3 ? p[3] : 1];
    } else if ((m = str.match(/^color\(srgb ([^)]+)\)$/))) {
      const p = m[1].split(/[\s\/]+/).filter(Boolean).map(Number);
      out = [p[0] * 255, p[1] * 255, p[2] * 255, p.length > 3 ? p[3] : 1];
    } else if (str === "transparent") out = [0, 0, 0, 0];
    else {
      probe.style.color = ""; probe.style.color = str;
      const c = getComputedStyle(probe).color;
      if (c !== str) out = parse(c);
    }
    PC.set(s, out); return out;
  };
  const over = (top, bot) => { // alpha composite top over opaque-ish bottom
    const a = top[3] + bot[3] * (1 - top[3]);
    if (a <= 0) return [0, 0, 0, 0];
    return [0, 1, 2].map((i) => (top[i] * top[3] + bot[i] * bot[3] * (1 - top[3])) / a).concat([a]);
  };
  const lin = (c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  const lum = (c) => 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]);
  const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  // E-ink preview = CSS grayscale(1) contrast(1.05), applied in gamma space
  const gray = (c) => { let g = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; g = Math.max(0, Math.min(255, ((g / 255 - 0.5) * 1.05 + 0.5) * 255)); return [g, g, g, c[3]]; };
  const hex = (c) => c ? "#" + c.slice(0, 3).map((v) => Math.round(v).toString(16).padStart(2, "0")).join("") + (c[3] < 0.999 ? "/" + (+c[3].toFixed(2)) : "") : "?";
  const sameRGB = (a, b, tol = 3) => Math.abs(a[0] - b[0]) <= tol && Math.abs(a[1] - b[1]) <= tol && Math.abs(a[2] - b[2]) <= tol;
  const same = (a, b) => sameRGB(a, b) && Math.abs(a[3] - b[3]) < 0.03;

  /* ---------- token palette for the current theme ---------- */
  const sst = getComputedStyle(scr);
  const palette = [];
  for (const t of cfg.tokens) { const v = sst.getPropertyValue(t).trim(); const c = v && parse(v); if (c) palette.push([t, c]); }
  const tok = (name) => (palette.find((p) => p[0] === name) || [])[1];
  const ACC = tok("--accent"), BG = tok("--bg");
  const isAccent = (c) => c && c[3] > 0.05 && sameRGB(c, ACC, 6);
  const inPalette = (c, el) => palette.some(([, p]) => same(c, p)) || (el ? nestedPalette(el).some(([, p]) => same(c, p)) : false);
  // previews drawn in the other theme (Welcome theme picker) resolve tokens against their own .theme-* scope
  const NP = new Map();
  const nestedPalette = (el) => {
    const t = el.closest("[class*='theme-']");
    if (!t || t === scr) return [];
    if (!NP.has(t)) { const st = getComputedStyle(t); NP.set(t, cfg.tokens.map((n) => [n, parse(st.getPropertyValue(n).trim())]).filter(([, c]) => c)); }
    return NP.get(t);
  };
  const tokenName = (c) => (palette.find(([, p]) => same(c, p)) || [])[0];

  /* ---------- element helpers ---------- */
  const visible = (el) => {
    if (!el.checkVisibility({ opacityProperty: true, visibilityProperty: true })) return false;
    const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0;
  };
  const clsOf = (el) => [...(el.classList || [])].filter((c) => !STATE.has(c) && !c.startsWith("lucide"));
  const part = (el) => {
    const t = el.tagName.toLowerCase();
    const c = clsOf(el).slice(0, 2);
    return c.length ? (["div", "span", "svg"].includes(t) ? "" : t) + "." + c.join(".") : t;
  };
  const sel = (el) => {
    const parts = []; let cur = el, n = 0;
    while (cur && cur !== scr && cur.id !== "screen-root" && cur.id !== "layer-root" && parts.length < 3 && n < 8) {
      if (cur === el || clsOf(cur).length) parts.unshift(part(cur));
      cur = cur.parentElement; n++;
    }
    return parts.join(" ");
  };
  const loc = (el) => { // unique path for re-finding the element later (screenshots)
    const p = []; let cur = el;
    while (cur && cur !== scr) { const i = [...cur.parentElement.children].indexOf(cur) + 1; p.unshift(`${cur.tagName.toLowerCase()}:nth-child(${i})`); cur = cur.parentElement; }
    return "#screen > " + p.join(" > ");
  };
  const stack = App.state.stack;
  const ownerOf = (el) => {
    const L = el.closest(".ko-layer");
    if (L) { const o = stack[+L.dataset.depth]; return { owner: o ? o.name : "?", layer: [...L.classList].find((c) => c.startsWith("layer-"))?.slice(6) || "?" }; }
    return { owner: App.current.name, layer: "screen" };
  };
  const ctxOf = (el) => ownerOf(el).layer;
  const directText = (el) => { let s = ""; for (const n of el.childNodes) if (n.nodeType === 3) s += n.nodeValue; return s.replace(/\s+/g, " ").trim(); };
  const textOf = (el) => (el.innerText || el.textContent || "").replace(/\s+/g, " ").trim().slice(0, 60);
  const book = (el) => within(el, cfg.book);
  const push = (rule, sev, el, msg, extra = {}) => {
    const o = ownerOf(el);
    issues.push({ rule, sev, sel: sel(el), loc: loc(el), owner: o.owner, layer: o.layer, msg, text: textOf(el), ...extra });
  };
  const metric = (kind, el, key, ctx) => { const o = ownerOf(el); metrics.push({ kind, ctx: ctx ?? o.layer, key, sel: sel(el), loc: loc(el), owner: o.owner }); };
  const px = (v) => Math.round(parseFloat(v) * 10) / 10;

  // effective background behind an element: ancestors first, then whatever is painted below
  const bgOf = (el) => {
    let layers = [], cur = el, img = false;
    while (cur && cur !== document.body) {
      const s = cs(cur);
      if (s.backgroundImage !== "none" && !/^none$/.test(s.backgroundImage)) { img = true; }
      const c = parse(s.backgroundColor);
      if (c && c[3] > 0) { layers.push(c); if (c[3] >= 0.999) break; }
      if (cur === scr) break;
      cur = cur.parentElement;
    }
    let out = layers.length && layers[layers.length - 1][3] >= 0.999 ? layers.pop() : [BG[0], BG[1], BG[2], 1];
    for (let i = layers.length - 1; i >= 0; i--) out = over(layers[i], out);
    return { c: out, img };
  };
  const opacityChain = (el) => { let o = 1, cur = el; while (cur && cur !== scr) { o *= parseFloat(cs(cur).opacity); cur = cur.parentElement; } return o; };

  /* ---------- collect elements ---------- */
  // audit only the subject of the state: the top overlay if one is open, else the screen
  const layersEls = [...document.querySelectorAll("#layer-root > .ko-layer")];
  const subject = layersEls.length ? layersEls[layersEls.length - 1] : document.getElementById("screen-root");
  const all = [...subject.querySelectorAll("*")].filter((el) => el !== probe && !(el instanceof SVGElement && el.tagName !== "svg") && visible(el));
  const leaves = all.filter((el) => directText(el).length > 0 && !["SCRIPT", "STYLE"].includes(el.tagName));

  /* ---------- text: size, weight, family, contrast ---------- */
  // a "card heading": semibold, at most --fs-lg, the heading of a card / hero / empty state
  const cardHeading = (el) => { const q = cs(el); return +q.fontWeight >= 600 && parseFloat(q.fontSize) <= 18.5 && !!el.closest(cfg.cards.join(",")); };
  const isTitle = (el) => any(el, cfg.titles) || (el.parentElement && any(el.parentElement, cfg.titles)) || cardHeading(el);
  const isHero = (el) => any(el, cfg.hero) || (el.parentElement && any(el.parentElement, cfg.hero));
  const isInput = (el) => within(el, cfg.inputs);
  for (const el of leaves) {
    const s = cs(el), fs = parseFloat(s.fontSize), fw = parseInt(s.fontWeight), txt = directText(el);
    const inBook = book(el);
    if (!inBook && !isInput(el) && !isTitle(el) && !isHero(el)) sizes[px(fs)] = (sizes[px(fs)] || 0) + 1;  // body-text sizes only
    if (!inBook && !isInput(el)) {
      const title = isTitle(el), hero = isHero(el);
      const arabic = /[\u0600-\u06FF]/.test(txt) && fs <= cfg.maxArabic;  // Arabic script needs ~1.2x to match Latin x-height
      if (fs > cfg.maxText && !title && !hero && !arabic)
        push("text-size", fs >= 21 ? "high" : "medium", el, `${px(fs)}px text (max ${cfg.maxText}px outside titles/hero metrics)`, { value: px(fs) });
      if (fs > cfg.maxTitle && title && !hero)
        push("text-size", "medium", el, `${px(fs)}px title is above the title cap ${cfg.maxTitle}px`, { value: px(fs) });
      if (!cfg.scale.includes(px(fs)) && !title && !hero)
        push("off-scale-size", "low", el, `${px(fs)}px is not on the type scale (${cfg.scale.join("/")})`, { value: px(fs) });
      if (fw >= 700 && !title && !hero && !within(el, cfg.boldOk))
        push("weight-bold", "medium", el, `bold (${fw}) UI text at ${px(fs)}px`);
      if (fw >= 600 && txt.length > 50 && !title)
        push("weight-semibold-long", "low", el, `semibold (${fw}) on a ${txt.length}-char run`);
      const fam = s.fontFamily.split(",")[0].replace(/["']/g, "").trim();
      const serif = cfg.serifFamilies.includes(fam);
      if (serif && !title && !hero && !within(el, cfg.serifOk) && !el.closest('[style*="font-family"]'))
        push("serif-ui", txt.length > 60 || el.tagName === "P" ? "low" : "medium", el, txt.length > 60 || el.tagName === "P" ? `serif "${fam}" on reading-style content (confirm it is meant as book-like text)` : `serif "${fam}" on UI text`);
      if (s.fontStyle === "italic" && !within(el, cfg.serifOk) && !el.closest('[style*="font-family"]'))
        push("italic-ui", "low", el, `italic UI text (${fam})`);
    }
    // contrast (book page included)
    if (el.closest(".disabled,[disabled],[aria-disabled='true']")) continue;
    let fg = parse(s.color); if (!fg || fg[3] === 0) continue;
    if (cfg.disabledToken && same(fg, tok("--disabled") || [0, 0, 0, -1])) continue;
    const { c: bg, img } = bgOf(el);
    if (img || within(el, cfg.contrastOk)) continue;
    const op = opacityChain(el);
    if (op < 0.6) continue; // dimmed = disabled
    if (!/[\p{L}\p{N}]/u.test(txt)) continue; // separators / decorative glyphs
    const fga = over([fg[0], fg[1], fg[2], fg[3] * op], bg);
    const large = fs >= 24 || (fs >= 18.66 && fw >= 700);
    const need = large ? 3 : 4.5;
    const r = ratio(fga, bg), re = ratio(gray(fga), gray(bg));
    const det = { value: +r.toFixed(2), eink: +re.toFixed(2), fg: hex(fga), bg: hex(bg), fgTok: tokenName(fg) || "", bgTok: tokenName(bg) || "" };
    if (r < need) push("contrast", r < need * 0.67 ? "high" : "medium", el, `contrast ${r.toFixed(2)}:1 (needs ${need}) · e-ink ${re.toFixed(2)}:1 · ${det.fgTok || det.fg} on ${det.bgTok || det.bg}`, det);
    else if (re < need) push("contrast-eink", re < need * 0.67 ? "high" : "medium", el, `e-ink grayscale contrast ${re.toFixed(2)}:1 (colour ${r.toFixed(2)}:1) · ${det.fgTok || det.fg} on ${det.bgTok || det.bg}`, det);
  }

  /* ---------- per-state font-size budget ---------- */
  const distinct = Object.keys(sizes).length;

  /* ---------- rows: values larger than the label ---------- */
  const rowLike = (el) => any(el, cfg.rows) || (cs(el).display.includes("flex") && el.getBoundingClientRect().height <= 64 && [...el.children].some((c) => any(c, cfg.rowLabels)));
  for (const row of all.filter((el) => rowLike(el) && !within(el, cfg.notRows))) {
    const ls = [...row.querySelectorAll("*")].filter((e) => leaves.includes(e) && !book(e) && ![...row.querySelectorAll(cfg.rows.join(","))].some((r2) => r2.contains(e)));
    if (ls.length < 2) continue;
    const letters = (e) => (directText(e).match(/\p{L}/gu) || []).length;
    let named = null;
    for (const q of cfg.rowLabels) { named = ls.find((e) => e.matches(q) || (e.parentElement?.matches(q) && e.parentElement !== row)); if (named) break; }
    const lab = named || ls.reduce((a, b) => (letters(b) > letters(a) ? b : a), ls[0]);
    if (!letters(lab)) continue;
    const lfs = parseFloat(cs(lab).fontSize), lfw = parseInt(cs(lab).fontWeight);
    for (const e of ls) {
      if (e === lab || e.contains(lab) || lab.contains(e) || isHero(e)) continue;
      const t = directText(e);
      const valueLike = any(e, cfg.rowValues) || /^[\s·•\-–(]*[\d.,:\/]+\s*(px|pt|%|°|×|x|min|h|s|m|GB|MB|KB|days?|pages?)?[\s)]*$/i.test(t);
      if (!valueLike) continue;
      const efs = parseFloat(cs(e).fontSize);
      if (efs > lfs + 0.5 && /\d|px|%/.test(directText(e)))
        push("row-value-size", "high", e, `value "${directText(e).slice(0, 20)}" is ${px(efs)}px, larger than its row label (${px(lfs)}px)`, { value: px(efs) });
      else if (efs >= lfs - 0.5 && parseInt(cs(e).fontWeight) > lfw + 100 && /\d/.test(directText(e)))
        push("row-value-size", "medium", e, `value "${directText(e).slice(0, 20)}" is heavier (${cs(e).fontWeight}) than its row label (${lfw})`);
    }
  }

  /* ---------- labels wrapping inside controls; chip rows wrapping ---------- */
  const lines = (node) => { const r = document.createRange(); r.selectNodeContents(node); const tops = new Set(); for (const q of r.getClientRects()) if (q.width > 1) tops.add(Math.round(q.top / 3)); return tops.size; };
  const controls = all.filter((el) => any(el, cfg.controls) && !any(el, cfg.notControls) && !book(el));
  for (const el of controls) {
    const r = el.getBoundingClientRect(); if (r.height > 90 || textOf(el).length > 32) continue;
    const tw = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let n; while ((n = tw.nextNode())) {
      if (!n.nodeValue.trim() || n.parentElement.closest(".sub")) continue;
      if (lines(n) > 1) { push("label-wrap", "high", el, `label "${n.nodeValue.trim().slice(0, 30)}" wraps onto ${lines(n)} lines in a ${Math.round(r.width)}px control`); break; }
    }
  }
  // row labels wrapping (dense popovers/sheets) — measured on the label's own text node
  for (const row of all.filter((el) => el.matches(".ko-row"))) {
    const lab = row.querySelector(".label") || row;
    const n = [...lab.childNodes].find((c) => c.nodeType === 3 && c.nodeValue.trim()) || [...lab.querySelectorAll(":scope > span:not(.sub)")].flatMap((e) => [...e.childNodes]).find((c) => c.nodeType === 3 && c.nodeValue.trim());
    if (!n) continue;
    const k = lines(n);
    if (k > 1) { const L = ctxOf(row); push("row-label-wrap", L === "popover" ? "medium" : "low", row, `row label "${n.nodeValue.trim().slice(0, 40)}" wraps onto ${k} lines in a ${L}`); }
  }
  // rows in one group whose labels start at different x (some rows have a leading icon, some don't)
  const rowParents = new Set(all.filter((el) => el.matches(".ko-row")).map((el) => el.parentElement));
  const runs = [];
  for (const p of rowParents) {  // a group = a contiguous run of rows (section labels / dividers split groups)
    let run = [];
    for (const k of p.children) { if (k.matches(".ko-row") && visible(k)) run.push(k); else if (visible(k)) { if (run.length) runs.push([p, run]); run = []; } }
    if (run.length) runs.push([p, run]);
  }
  for (const [p, rows] of runs) {
    if (rows.length < 3) continue;
    const textX = (r) => { const tw = document.createTreeWalker(r, NodeFilter.SHOW_TEXT); let n; while ((n = tw.nextNode())) { if (!n.nodeValue.trim()) continue; const g = document.createRange(); g.selectNodeContents(n); const q = g.getClientRects()[0]; if (q) return Math.round(q.left); } return null; };
    const rtl = (r) => cs(r).direction === "rtl";
    const xs = rows.filter((r) => !rtl(r)).map(textX).filter((x) => x !== null);
    if (xs.length < 3) continue;
    const uniq = [...new Set(xs)].sort((a, b) => a - b);
    if (uniq.length > 1 && uniq[uniq.length - 1] - uniq[0] > 12) {
      const withIcon = rows.filter((r) => r.querySelector(":scope > svg, :scope > .ko-i, :scope > .ko-radio, :scope > .ko-check")).length;
      push("mixed-row-icons", "medium", p, `${rows.length} rows in one group start their text at ${uniq.length} x-positions (${uniq.map((x) => x - Math.round(SR.left)).join("/")}px); ${withIcon} have a leading icon/control, ${rows.length - withIcon} don't`);
    }
  }
  // glyphs that need KOReader's private icon font, or empty "()" left behind
  for (const el of leaves) {
    const t = directText(el);
    if (/[\uE000-\uF8FF]/.test(t) || /\(\s*\)/.test(t)) push("missing-glyph", "medium", el, `text contains a private-use / missing glyph: "${t.slice(0, 40)}"`);
  }
  const chipSel = cfg.chips.join(",");
  const chipParents = new Set(all.filter((el) => el.matches(chipSel)).map((el) => el.parentElement));
  for (const p of chipParents) {
    const kids = [...p.children].filter((k) => k.matches(chipSel) && visible(k));
    if (kids.length < 3) continue;
    const ps = cs(p); if (/auto|scroll/.test(ps.overflowX)) continue;
    const tops = new Set(kids.map((k) => Math.round(k.getBoundingClientRect().top / 4)));
    if (tops.size > 1) push("chip-row-wrap", "medium", p, `${kids.length} chips wrap onto ${tops.size} lines`);
  }

  /* ---------- overflow / clipping / truncation ---------- */
  const scroller = (el) => { let c = el.parentElement; while (c && c !== scr) { if (/auto|scroll/.test(cs(c).overflowX)) return true; c = c.parentElement; } return false; };
  for (const el of all) {
    if (book(el) || within(el, cfg.overflowOk)) continue;
    const r = el.getBoundingClientRect(), s = cs(el);
    const parentOut = (() => { const p = el.parentElement; if (!p || p === scr) return false; const q = p.getBoundingClientRect(); return q.right > SR.right + 1 || q.left < SR.left - 1; })();
    if ((r.right > SR.right + 1 || r.left < SR.left - 1) && !parentOut && !scroller(el) && s.position !== "fixed")
      push("offscreen", "high", el, `extends ${Math.round(Math.max(r.right - SR.right, SR.left - r.left))}px beyond the ${Math.round(SR.width)}px screen`);
    const hasText = directText(el).length > 0;
    const ox = s.overflowX;
    if (el.scrollWidth > el.clientWidth + 1 && el.clientWidth > 0 && !el.querySelector(".ko-hit") && !el.classList.contains("ko-hit")) {  // hit expanders inflate scrollWidth
      if (/hidden|clip/.test(ox) && hasText && s.textOverflow !== "ellipsis" && !el.closest("[class*='ellipsis']"))
        push("clipped-text", "medium", el, `text clipped without ellipsis (${el.scrollWidth}px in ${el.clientWidth}px)`);
      else if (ox === "visible" && hasText && s.display !== "inline" && s.whiteSpace.includes("nowrap"))
        push("overflow-text", "medium", el, `nowrap text spills ${el.scrollWidth - el.clientWidth}px out of its box`);
    }
    if (s.textOverflow === "ellipsis" && el.scrollWidth > el.clientWidth + 1) {
      const inRowValue = !!el.closest(".value, [class*='val']") || !!el.closest(cfg.rows.join(",")) && !el.closest(".label");
      push("truncated", inRowValue ? "medium" : "low", el, `truncated: "${textOf(el).slice(0, 50)}"`);
    }
    if (ox === "visible" && s.display !== "inline" && el.children.length && !scroller(el) && el.clientWidth > 0) {
      for (const k of el.children) {
        const ks = cs(k); if (/absolute|fixed/.test(ks.position) || !visible(k)) continue;
        const kr = k.getBoundingClientRect();
        const over_r = kr.right - r.right, over_l = r.left - kr.left;
        const mr = -parseFloat(ks.marginRight) || 0, ml = -parseFloat(ks.marginLeft) || 0; // deliberate negative margins (optical alignment)
        if ((over_r > 2 && over_r > mr + 1) || (over_l > 2 && over_l > ml + 1)) { push("overflow-child", "medium", k, `pokes ${Math.round(Math.max(kr.right - r.right, r.left - kr.left))}px out of ${part(el)}`); break; }
      }
    }
  }

  /* ---------- touch targets ---------- */
  const inter = all.filter((el) => any(el, cfg.interactive) && !within(el, cfg.touchOk) && !book(el) && !el.disabled && el.getAttribute("aria-disabled") !== "true");
  const hit = (el) => {
    const r = el.getBoundingClientRect(); let w = r.width, h = r.height;
    for (const ps of ["::before", "::after"]) {
      const p = getComputedStyle(el, ps);
      if (p.content === "none" || p.content === "normal" || !/absolute|fixed/.test(p.position) || p.pointerEvents === "none") continue;
      const pw = parseFloat(p.width), ph = parseFloat(p.height);
      if (pw > 0 && ph > 0) { w = Math.max(w, pw); h = Math.max(h, ph); }
    }
    return { width: w, height: h };
  };
  for (const el of inter) {
    const r = hit(el);
    const m = Math.min(r.width, r.height);
    if (m >= cfg.minTouch) continue;
    const lab = el.matches("input, select, textarea") && el.closest("label");
    if (lab) { const q = lab.getBoundingClientRect(); if (Math.min(q.width, q.height) >= cfg.minTouch) continue; }
    // nested controls (a help button inside a row) need their own hit area too; only pure wrappers are exempt
    const anc = el.parentElement?.closest(cfg.interactive.join(","));
    if (anc && scr.contains(anc) && anc.querySelectorAll(cfg.interactive.join(",")).length === 1 && Math.min(hit(anc).width, hit(anc).height) >= cfg.minTouch) continue;
    if (cs(el).display === "inline") continue;
    push("touch-target", m < 32 ? "high" : "medium", el, `${Math.round(r.width)}x${Math.round(r.height)} hit area (min ${cfg.minTouch}x${cfg.minTouch})`, { value: Math.round(m) });
  }

  /* ---------- selected states ---------- */
  const COLPROPS = ["color", "backgroundColor", "borderTopColor", "borderBottomColor", "borderLeftColor", "borderRightColor", "outlineColor", "textDecorationColor", "fill", "stroke"];
  const accentIn = (s) => COLPROPS.some((p) => {
    if (p.startsWith("border") && parseFloat(s[p.replace("Color", "Width")]) === 0) return false;
    if (p === "outlineColor" && s.outlineStyle === "none") return false;
    return isAccent(parse(s[p]));
  }) || (s.boxShadow && s.boxShadow !== "none" && /rgba?\([^)]*\)/g.test(s.boxShadow) && (s.boxShadow.match(/rgba?\([^)]*\)/g) || []).some((c) => isAccent(parse(c))));
  const usesAccent = (el) => {
    const els = [el, ...[...el.querySelectorAll("*")].slice(0, 60)];
    for (const e of els) {
      if (!visible(e) && e !== el) continue;
      if (accentIn(cs(e))) return true;
      for (const ps of ["::before", "::after"]) { const p = getComputedStyle(e, ps); if (p.content !== "none" && p.content !== "normal" && accentIn(p)) return true; }
    }
    return false;
  };
  const sig = (el) => {
    const s = cs(el), b = getComputedStyle(el, "::after"), a = getComputedStyle(el, "::before");
    const ps = (p) => p.content !== "none" && p.content !== "normal" ? `${p.width}x${p.height}:${hex(gray(parse(p.backgroundColor) || [0, 0, 0, 0]))}:${p.borderTopWidth}` : "-";
    const k = [...el.querySelectorAll("*")].slice(0, 30).filter(visible).map((e) => { const q = cs(e); const pa = getComputedStyle(e, "::after"); const bgc = parse(q.backgroundColor) || [0, 0, 0, 0];
      return `${q.fontWeight}|${Math.round(gray(over(parse(q.color) || [0, 0, 0, 0], [0, 0, 0, 1]))[0] / 12)}|${bgc[3] > 0.05 ? Math.round(gray(bgc)[0] / 16) : "-"}|${q.opacity}|${q.strokeWidth}|${q.display}|${q.fill === "none" ? "" : "f"}|${pa.content === "none" ? "" : pa.transform + pa.width}`; }).join(",");
    return { bg: gray(bgOf(el).c)[0], fg: gray(parse(s.color))[0], fw: s.fontWeight, bw: [s.borderTopWidth, s.borderBottomWidth, s.borderLeftWidth, s.outlineStyle, s.textDecorationLine, s.boxShadow === "none" ? "" : "sh"].join(" "), ps: ps(a) + ps(b), k };
  };
  const selEls = all.filter((el) => any(el, cfg.selected) && !book(el) && !within(el, cfg.selectedOk));
  const pairs = [];
  for (const el of selEls) {
    if (!usesAccent(el)) push("selected-no-accent", "high", el, `selected state (${[...el.classList].filter((c) => STATE.has(c)).join(",") || "aria"}) doesn't use --accent anywhere`);
    const base = clsOf(el).join(".");
    const sib = [...(el.parentElement?.children || [])].find((k) => k !== el && k.tagName === el.tagName && clsOf(k).join(".") === base && !any(k, cfg.selected) && visible(k));
    if (sib) pairs.push([el, sib]);
  }
  // e-ink phase: evaluate with the designer's .eink class applied (e-ink-only styles count)
  const hadEink = document.body.classList.contains("eink");
  document.body.classList.add("eink"); CS.clear();
  for (const [el, sib] of pairs) {
    const A = sig(el), B = sig(sib);
    const diff = Math.abs(A.bg - B.bg) >= 14 || Math.abs(A.fg - B.fg) >= 30 || A.fw !== B.fw || A.bw !== B.bw || A.ps !== B.ps || A.k !== B.k;
    if (!diff) push("selected-eink", "high", el, `selected and unselected look the same in e-ink grayscale (bg Δ${Math.round(Math.abs(A.bg - B.bg))}, text Δ${Math.round(Math.abs(A.fg - B.fg))}/255, no weight/border/shape difference)`);
  }
  for (const el of all.filter((e) => e.matches("mark, .hl, [class*='hl-']") && book(e))) {
    const q = cs(el), c = parse(q.backgroundColor); if (!c || c[3] < 0.05) continue;
    const under = bgOf(el.parentElement).c, mixed = over(c, under);
    const dg = Math.abs(gray(mixed)[0] - gray(under)[0]);
    const marked = q.textDecorationLine !== "none" || parseFloat(q.borderBottomWidth) > 0 || (q.boxShadow && q.boxShadow !== "none");
    if (dg < 20 && !marked)
      push("highlight-eink", "high", el, `highlight ${hex(mixed)} on page ${hex(under)} differs by only ${Math.round(dg)}/255 grey in e-ink and has no underline/border`);
  }
  if (!hadEink) document.body.classList.remove("eink");
  CS.clear();

  /* ---------- colour swatches collapsing in grayscale ---------- */
  const swatches = [];
  for (const el of all) {
    const r = el.getBoundingClientRect();
    if (r.width < 8 || r.height < 8 || r.width > 80 || r.height > 80 || directText(el)) continue;
    const c = parse(cs(el).backgroundColor); if (!c || c[3] < 0.2) continue;
    if (inPalette(c) || book(el) && !el.closest(cfg.swatchScope)) continue;
    swatches.push([el, over(c, bgOf(el.parentElement).c)]);
  }
  const swParents = new Map();
  for (const sw of swatches) {
    let p = sw[0].parentElement;
    for (let k = 0; k < 3 && p; k++, p = p.parentElement) if (swatches.filter((o) => o !== sw && p.contains(o[0])).length >= 1) break;
    if (!p) continue;
    if (!swParents.has(p)) swParents.set(p, []); swParents.get(p).push(sw);
  }
  for (const [p, list] of swParents) {
    if (list.length < 2) continue;
    const bad = [];
    for (let i = 0; i < list.length; i++) for (let j = i + 1; j < list.length; j++) {
      const [a, ca] = list[i], [b, cb] = list[j];
      const dc = Math.hypot(ca[0] - cb[0], ca[1] - cb[1], ca[2] - cb[2]);
      const dg = Math.abs(gray(ca)[0] - gray(cb)[0]);
      if (dc > 30 && dg < 12) bad.push(`${hex(ca)}≈${hex(cb)} (Δgray ${Math.round(dg)})`);
    }
    if (bad.length) {
      const named = (e) => { const c = e.closest("button, [role='button'], .ko-chip, label, [data-action]"); return c && c !== e && /\p{L}{3,}/u.test(c.textContent || "") && c.contains(e); };
      if (list.every(([e]) => named(e))) continue;
      push("swatch-eink", "high", p, `${list.length} colour swatches; ${bad.length} pair(s) collapse to the same grey in e-ink: ${bad.slice(0, 4).join(", ")}`);
    }
  }

  /* ---------- computed colours outside the token palette ---------- */
  for (const el of all) {
    if (book(el) || within(el, cfg.colourOk) || el.tagName === "svg") continue;
    const s = cs(el);
    const check = [];
    if (directText(el)) check.push(["color", s.color]);
    const bgc = parse(s.backgroundColor); if (bgc && bgc[3] > 0) check.push(["background", s.backgroundColor]);
    for (const side of ["Top", "Bottom", "Left", "Right"]) if (parseFloat(s[`border${side}Width`]) > 0 && s[`border${side}Style`] !== "none") { check.push(["border", s[`border${side}Color`]]); break; }
    for (const [prop, v] of check) {
      const c = parse(v); if (!c || c[3] === 0) continue;
      if (!inPalette(c, el)) push("offpalette", "low", el, `${prop} ${hex(c)} is not a theme token`, { value: hex(c) });
    }
  }

  /* ---------- mixed button sizes inside one popup / one row ---------- */
  const boxed = (el) => { const s = cs(el); const b = parse(s.backgroundColor); return (b && b[3] > 0.05) || parseFloat(s.borderTopWidth) > 0; };
  const btns = all.filter((el) => any(el, cfg.buttons) && !any(el, cfg.notButtons) && !book(el) && boxed(el) && textOf(el).length > 0 && textOf(el).length < 32 && el.getBoundingClientRect().height <= 56);
  const byRow = new Map(), byLayer = new Map();
  for (const b of btns) {
    const h = Math.round(b.getBoundingClientRect().height);
    const p = b.parentElement; if (!byRow.has(p)) byRow.set(p, []); byRow.get(p).push([b, h]);
    const L = b.closest(".ko-layer"); if (L) { if (!byLayer.has(L)) byLayer.set(L, []); byLayer.get(L).push([b, h]); }
    if (b.matches(".ko-btn") && !b.disabled && !within(b, cfg.buttonHeightOk)) metric("button", b, `h${h}`, "all");  // the shared .ko-btn: one height everywhere
  }
  for (const [p, list] of byRow) {
    const hs = [...new Set(list.map((x) => x[1]))];
    if (hs.length > 1 && list.length > 1) push("mixed-button-size", "high", p, `buttons side by side with different heights: ${list.map(([b, h]) => `"${textOf(b).slice(0, 14)}" ${h}px`).join(", ")}`);
  }
  for (const [L, list] of byLayer) {
    const hs = [...new Set(list.map((x) => x[1]))].sort((a, b) => a - b);
    if (hs.length > 1) push("mixed-button-size", "low", L.lastElementChild || L, `${list.length} buttons in one ${ownerOf(L.lastElementChild || L).owner} panel use ${hs.length} heights: ${hs.map((h) => `${h}px×${list.filter((x) => x[1] === h).length}`).join(", ")}`);
  }

  /* ---------- sliders: the ONE pattern is App.sliderRow (.ko-sr: label, −, slider, +, value on one line) ---------- */
  for (const el of all.filter((e) => e.matches(".ko-slider"))) {
    if (el.closest(".ko-sr") || within(el, cfg.scrubbers)) continue;
    push("slider-pattern", "high", el, "standalone .ko-slider — numeric settings use App.sliderRow (label, −, slider, +, value on one line); only page-position scrubbers may stand alone");
  }

  /* ---------- sheet headers ---------- */
  const fam = (e) => cs(e).fontFamily.split(",")[0].replace(/["']/g, "").trim();
  const subjOwner = ownerOf(subject.firstElementChild || subject);
  if (subject.classList.contains("layer-sheet") && !cfg.sheetHeadOk.includes(subjOwner.owner)) {
    const sheet = subject.querySelector(".ko-sheet");
    const head = sheet && sheet.querySelector(".ko-sheet-head");
    if (sheet && !head) push("sheet-head", "medium", sheet, "sheet doesn't use the shared .ko-sheet-head header");
    if (head) {
      const t = head.querySelector(".title");
      const close = head.querySelector("[data-close], [aria-label='Close'], .lucide-x");
      if (!close) push("sheet-head", "medium", head, "sheet header has no close button");
      if (!t) push("sheet-head", "medium", head, "sheet header has no .title");
      else {
        const ts = cs(t);
        if (Math.abs(parseFloat(ts.fontSize) - 17) > 0.5 || +ts.fontWeight !== 600 || fam(t) !== "Inter")
          push("sheet-head", "medium", t, `sheet title is ${px(ts.fontSize)}px/${ts.fontWeight} ${fam(t)} (expected 17px/600 Inter)`);
      }
    }
  }
  /* ---------- title / metric fonts ---------- */
  const isPlayfair = (e) => fam(e) === "Playfair Display";
  if (subject.id === "screen-root") {
    const t = subject.querySelector(".ko-header:not([class*='selhead']) .title, header:not([class*='selhead']) .title, .ko-header h1, header h1");
    if (t && visible(t)) {
      const nm = App.current.name, prm = App.current.params || {};
      const top = cfg.topLevel.includes(nm) && !(nm === "settings" && prm.section);
      if (top && !isPlayfair(t)) push("title-font", "medium", t, `top-level screen title should be Playfair (is ${fam(t)})`);
      if (!top && isPlayfair(t)) push("title-font", "medium", t, `level-2 screen title should be Inter 17–18px semibold (is Playfair)`);
    }
  } else if (!cfg.playfairOk.includes(subjOwner.owner)) {
    for (const t of subject.querySelectorAll(".title, [class*='head'] [class*='title'], [class*='head'] .t, h1, h2")) {
      if (!visible(t) || book(t) || !directText(t) && !t.textContent.trim()) continue;
      if (isPlayfair(t) && !within(t, cfg.playfairElOk)) push("title-font", "medium", t, `panel header in Playfair — level-2 pages, sheets and drawers use Inter 17–18px semibold`);
    }
  }
  for (const el of leaves) {
    if ((isHero(el)) && isPlayfair(el) && !within(el, cfg.playfairMetricOk) && /\d/.test(directText(el)))
      push("metric-font", "medium", el, `metric "${directText(el).slice(0, 12)}" in Playfair — metrics use Inter (only the Stats hero may be Playfair)`);
  }

  /* ---------- component consistency metrics ---------- */
  const R = (el) => el.getBoundingClientRect();
  const D = (el) => `${Math.round(R(el).width)}x${Math.round(R(el).height)}`;
  for (const el of all) {
    if (book(el)) continue;
    const s = cs(el);
    const isSvg = el.tagName === "svg";
    if (!isSvg && any(el, cfg.toggles) && R(el).width < 72 && R(el).height < 44) metric("toggle", el, D(el), "all");
    else if (!isSvg && el.matches(".ko-check, .ko-radio") && R(el).width < 40) metric(el.matches(".ko-radio,[class*='radio']") ? "radio" : "checkbox", el, D(el), "all");
    if (!isSvg && any(el, cfg.segs)) {
      const kids = [...el.children].filter(visible);
      if (el.matches(".ko-seg")) metric("segmented", el, `btn-h${kids[0] ? Math.round(R(kids[0]).height) : "?"}`, "all");
    }
    if (el.matches(".ko-row") && !el.querySelector(".sub, .ko-seg, .ko-stepper, .ko-btn, .mn-step") && R(el).height <= 60) metric("row-height", el, `h${Math.round(R(el).height)}`, el.closest(".ko-popover") ? "popover" : "list");
    if (!isSvg && any(el, cfg.sheetHeads) && el.querySelector(".title")) { const t = el.querySelector(".title"); metric("sheet-header", el, `title ${px(cs(t).fontSize)}/${cs(t).fontWeight} ${cs(t).fontFamily.split(",")[0].replace(/"/g, "")}`, ctxOf(el)); }
    if (el.matches(".ko-header") && ctxOf(el) !== "screen" && el.querySelector(".title")) { const t = el.querySelector(".title"); metric("screen-header", el, `title ${px(cs(t).fontSize)}/${cs(t).fontWeight} ${cs(t).fontFamily.split(",")[0].replace(/"/g, "")}`, ctxOf(el)); }
    if (el.tagName === "svg" && el.classList.contains("lucide")) {
      const inBtn = el.closest(".ko-header, [class*='head']") ? "header" : el.closest(".ko-row") ? "row" : el.closest(".ko-nav") ? "nav" : "other";
      metric("icon", el, `${Math.round(R(el).width)}px sw${s.strokeWidth}`, inBtn);
    }
    if (!isSvg && any(el, cfg.sliders)) metric("slider", el, `h${Math.round(R(el).height)}`, "all");
    if (!isSvg && el.matches(".ko-chip")) metric("chip", el, `h${Math.round(R(el).height)} fs${px(s.fontSize)}`, "all");
    if (s.textTransform === "uppercase" && directText(el) && !book(el)) metric("section-label", el, `fs${px(s.fontSize)} fw${s.fontWeight} ls${s.letterSpacing}`, "all");
    if (!isSvg && el.matches(".ko-progress")) metric("progress", el, `h${Math.round(R(el).height)}`, "all");
    if (!el.disabled && !el.matches(".kb-key") && (el.matches(".ko-icon-btn") || (el.tagName === "BUTTON" && el.children.length === 1 && el.firstElementChild.tagName === "svg" && !directText(el)))) metric("icon-button", el, (() => { const h = hit(el); return Math.min(h.width, h.height) >= 44 ? ">=44 hit" : `${Math.round(h.width)}x${Math.round(h.height)} hit`; })(), ctxOf(el));
  }

  probe.remove();
  return { issues, metrics, sizes, distinct, owner: (stack[stack.length - 1] || App.current).name, screen: App.current.name };
}
