/* ==========================================================================
   Folio — Reader (owned by the Reader agent)
   - window.RD: book model, Arabic text, typesetting config, pagination engine
   - screen  `reader`        ({id, page, ch, y})
   - overlay `reader-chrome` (centre tap)
   - overlay `typeset`       (bottom sheet, {tab}) — driven by KO_MENUS.reader_config / reader_config_pdf
   Panels (toc, dict, translate, …) live in reader-panels.js.
   ========================================================================== */
(function () {
  const RD = (window.RD = {});
  const E = App.esc, I = App.icon;

  /* ---------------------------------------------------------------- utils */
  function rng(seed) { let s = 0; for (const c of String(seed)) s = (s * 31 + c.charCodeAt(0)) >>> 0; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296); }
  RD.rng = rng;
  const pick = (r, a) => a[Math.floor(r() * a.length)];
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  RD.clamp = clamp;
  const tpl = document.createElement("template");
  const mk = (html) => { tpl.innerHTML = html; return tpl.content.firstElementChild; };
  const screenEl = () => document.querySelector(".ko-screen");
  RD.screenSize = () => { const s = screenEl(); return { w: s ? s.clientWidth : 600, h: s ? s.clientHeight : 800 }; };

  /* ------------------------------------------------------- Arabic prose */
  const AR_W = ("في من على إلى عن مع كان قد لم ما لا هذا ذلك التي الذي حين بين حتى ثم كل بعد قبل عند " +
    "الليل النهار القلب الريح الماء الطريق البيت الباب الصمت الضوء السماء الأرض الحقل الصباح المساء النافذة اليد الصوت " +
    "الحلم الزمن البحر الرمل النخيل الغيم الشمس القمر النجوم المدينة القرية الشيخ الفتى الحصان الطير الخيل السيف القلم " +
    "الكتاب الشعر الحب الشوق الصبر المجد العزم الكرم الدهر الأيام الليالي المزرعة الحيوانات الحظيرة " +
    "قال رأى مشى عاد سمع انتظر نظر حمل فتح تذكر بدا ظن يمشي يرى يقول يعود أصغى أجاب تبع راقب " +
    "طويل قديم صغير بعيد بارد هادئ غريب جميل حزين ثقيل واسع ضيق ذهبي شاحب مألوف متعب").split(" ");
  const AR_RHYME = ["العزائمُ", "المكارمُ", "الصوارمُ", "الغمائمُ", "العظائمُ", "المعالمُ", "الحمائمُ", "القوادمُ", "الهزائمُ", "المواسمُ", "الدعائمُ", "الملاحمُ"];
  function arSentence(r, min = 6, max = 15) {
    const n = min + Math.floor(r() * (max - min));
    const w = []; for (let i = 0; i < n; i++) w.push(AR_W[Math.floor(Math.pow(r(), 1.5) * AR_W.length)]);
    if (n > 10 && r() < 0.6) w[Math.floor(n / 2)] += "،";
    return w.join(" ") + (r() < 0.07 ? "؟" : ".");
  }
  RD.arParagraph = (seed, words = 40) => { const r = rng(seed); const out = []; let n = 0; while (n < words) { const s = arSentence(r); out.push(s); n += s.split(" ").length; } return out.join(" "); };
  function arHemi(r, n) { const w = []; for (let i = 0; i < n; i++) w.push(AR_W[20 + Math.floor(r() * (AR_W.length - 20))]); return w; }
  const AR_POEMS = ["على قدر أهل العزم", "لكل امرئ من دهره ما تعودا", "الخيل والليل والبيداء", "واحرّ قلباه", "عيدٌ بأية حال عدت", "أنا الذي نظر الأعمى", "إذا غامرت في شرف مروم", "بم التعلل", "فراق ومن فارقت", "لهوى النفوس سريرة", "ملومكما يجل عن الملام"];
  const AR_NUM = (n) => String(n).replace(/\d/g, (d) => "٠١٢٣٤٥٦٧٨٩"[d]);
  RD.arNum = AR_NUM;

  /* ------------------------------------------------------------ chapters */
  const EN_TITLES = ["A Quiet Evening", "The Meeting in the Barn", "Morning Light", "The Long Field", "Distant Voices", "The Narrow Road", "Harvest", "Cold Water", "The Golden Hour", "Familiar Strangers", "The Hollow", "Silence"];
  const ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"];
  const AR_ORD = ["الأول", "الثاني", "الثالث", "الرابع", "الخامس", "السادس", "السابع", "الثامن", "التاسع", "العاشر", "الحادي عشر", "الثاني عشر"];
  const AR_CH = ["الطفولة", "الكتّاب", "الأزهر", "القرية", "الشيخ", "السفر", "الليل", "العودة", "الصبر", "الذكرى", "الرحيل", "الفجر"];
  RD.book = (id) => DB.book(id);
  RD.isAr = (b) => b.lang === "ar";
  RD.isPdf = (b) => b.format === "pdf";
  RD.bilingual = (b) => b.id === "animal-farm";
  RD.short = (b) => b.title.replace(/\s*\(.*\)/, "");
  const chCache = {};
  /** [{title, label, num, sections:[{title, frac}]}] */
  RD.chapters = (id) => {
    if (chCache[id]) return chCache[id];
    const b = RD.book(id), n = TextGen.chapters(id).length, r = rng("toc" + id);
    return (chCache[id] = Array.from({ length: n }, (_, i) => {
      if (b.id === "ar-poems") return { num: AR_NUM(i + 1), label: `القصيدة ${AR_NUM(i + 1)}`, title: AR_POEMS[i % AR_POEMS.length], sections: [] };
      if (RD.isAr(b)) return { num: AR_NUM(i + 1), label: `الفصل ${AR_ORD[i]}`, title: AR_CH[i % AR_CH.length], sections: [] };
      const t = EN_TITLES[(i + id.length) % EN_TITLES.length];
      const secs = r() < 0.45 ? [{ title: "i. " + pick(r, ["The barn", "At the gate", "Night watch", "Letters", "The orchard", "Before dawn"]), frac: 0.34 }, { title: "ii. " + pick(r, ["Return", "The vote", "Rain", "A promise", "The well", "Smoke"]), frac: 0.67 }] : [];
      return { num: ROMAN[i], label: `Chapter ${ROMAN[i]}`, title: t, sections: secs };
    }));
  };
  RD.parts = (id) => { const n = RD.chapters(id).length; if (RD.isAr(RD.book(id))) return []; const h = Math.ceil(n / 2); return [{ title: "Part One", from: 0, to: h - 1 }, { title: "Part Two", from: h, to: n - 1 }]; };

  /* ---------------------------------------------------------- text blocks */
  // block: {t:"p"|"ar"|"v", pid, w:[words], split?(verse)}
  const blkCache = {};
  RD.blocks = (id, ch, inline) => {
    const k = id + ":" + ch + ":" + (inline ? 1 : 0);
    if (blkCache[k]) return blkCache[k];
    const b = RD.book(id); const out = [];
    if (b.id === "ar-poems") {
      const r = rng("verse" + id + ch), n = 22 + Math.floor(r() * 14), rh = AR_RHYME;
      for (let i = 0; i < n; i++) { const h1 = arHemi(r, 3 + Math.floor(r() * 2)), h2 = arHemi(r, 2 + Math.floor(r() * 2)).concat(rh[Math.floor(r() * rh.length)]); out.push({ t: "v", pid: i, w: h1.concat(h2), split: h1.length }); }
    } else if (RD.isAr(b)) {
      const r = rng("arp" + id + ch), n = 14 + Math.floor(r() * 6);
      for (let i = 0; i < n; i++) out.push({ t: "p", ar: true, pid: i, w: RD.arParagraph(id + ch + "p" + i, 25 + Math.floor(r() * 50)).split(" ") });
    } else {
      const paras = TextGen.chapter(id, ch, 15 + ((ch * 7) % 8));
      paras.forEach((p, i) => {
        out.push({ t: "p", pid: i, w: p.split(" ") });
        if (inline) out.push({ t: "ar", pid: "t" + i, src: i, w: RD.arFor(id, ch, i).split(" ") });
      });
    }
    return (blkCache[k] = out);
  };
  RD.para = (id, ch, pid) => RD.blocks(id, ch, false).find((x) => x.pid === pid);
  RD.arFor = (id, ch, pid) => { const p = RD.para(id, ch, pid); return RD.arParagraph("tr" + id + ch + ":" + pid, Math.round((p ? p.w.length : 40) * 0.85)); };

  /* ---------------------------------------------------- typeset settings */
  const KM = () => window.KO_MENUS || {};
  RD.cfgGroups = (pdf) => (pdf ? KM().reader_config_pdf : KM().reader_config) || [];
  const H_MARGINS = ["5", "10", "15", "20", "30", "50", "70", "100", "140"];
  // fix-ups for options whose values were not serialisable in the dump
  RD.optValues = (o) => {
    if (o.name === "h_page_margins") return H_MARGINS;
    if (Array.isArray(o.values) && o.values.length) return o.values.map(String);
    if (Array.isArray(o.labels) && o.labels.length) return o.labels.map(String);
    return [];
  };
  RD.optLabels = (o) => (Array.isArray(o.labels) && o.labels.length ? o.labels : RD.optValues(o));
  const EXTRA_DEF = {
    epub: { h_page_margins: "20", word_spacing: "medium", font_face: "Literata", text_align: "justify", para_indent: "1.2", para_space: "0", hyphenation: "1", tr_marks: "1", tr_inline: "0", style_sheet: "auto", visible_pages: "auto" },
    pdf: {},
  };
  RD.factory = (kind) => {
    const d = { ...EXTRA_DEF[kind] };
    RD.cfgGroups(kind === "pdf").forEach((g) => g.options.forEach((o) => { if (!(o.name in d) && o.default != null && !/^table:/.test(o.default)) d[o.name] = String(o.default); }));
    return d;
  };
  RD.kind = (b) => (RD.isPdf(b) ? "pdf" : "epub");
  RD.defaults = (kind) => ({ ...RD.factory(kind), ...App.get("rd.def." + kind, {}) });
  RD.cfg = (id) => {
    const b = RD.book(id), c = { ...RD.defaults(RD.kind(b)), ...App.get("rd.doc." + b.id, {}) };
    const q = App.current && App.current.name === "reader" && App.current.params; // demo override: #/reader?id=animal-farm&inline=1
    if (q && q.inline != null && RD.bilingual(b)) c.tr_inline = String(q.inline);
    return c;
  };
  RD.setCfg = (id, k, v) => {
    RD.keepAnchor(id);
    const d = App.get("rd.doc." + id, {}); d[k] = String(v); delete App.current.params.y;
    const sync = (d.sync_t_b_page_margins ?? RD.cfg(id).sync_t_b_page_margins) === "1";
    if (sync && k === "t_page_margin") d.b_page_margin = String(v);
    if (sync && k === "b_page_margin") d.t_page_margin = String(v);
    if (k === "sync_t_b_page_margins" && v === "1") d.b_page_margin = RD.cfg(id).t_page_margin;
    App.set("rd.doc." + id, d);
    RD.quietRefresh();
  };
  RD.applyCfg = (id, obj) => { RD.keepAnchor(id); App.set("rd.doc." + id, { ...obj }); RD.quietRefresh(); };
  /** re-render everything without replaying the open animations of overlays */
  RD.quietRefresh = () => RD.quiet(() => App.refresh());
  /** run a re-render without replaying overlay open animations */
  RD.quiet = (fn) => {
    const s = screenEl(); s && s.classList.add("rd-quiet");
    fn();
    // freeze the freshly rendered overlay nodes so removing the class does not replay their open animation
    document.querySelectorAll("#layer-root .ko-layer, #layer-root .ko-layer > *, #layer-root .rd-chrome > *").forEach((el) => { el.style.animation = "none"; });
    s && s.classList.remove("rd-quiet");
  };

  /* ------------------------------------------------------------- fonts */
  RD.FONTS = [
    { name: "Literata", css: "'Literata', serif", cat: "serif", note: "Default · variable" },
    { name: "Source Serif 4", css: "'Source Serif 4', serif", cat: "serif", note: "Variable" },
    { name: "Noto Serif", css: "'Noto Serif', serif", cat: "serif", note: "KOReader default" },
    { name: "EB Garamond", css: "'EB Garamond', serif", cat: "serif", note: "Old-style" },
    { name: "Merriweather", css: "'Merriweather', serif", cat: "serif", note: "Screen serif" },
    { name: "Bitter", css: "'Bitter', serif", cat: "serif", note: "Slab" },
    { name: "Atkinson Hyperlegible Next", css: "'Atkinson Hyperlegible Next', 'Atkinson Hyperlegible', sans-serif", cat: "sans", note: "High legibility" },
    { name: "Source Sans 3", css: "'Source Sans 3', sans-serif", cat: "sans", note: "Variable" },
    { name: "Noto Sans", css: "'Noto Sans', sans-serif", cat: "sans", note: "Humanist" },
    { name: "Inter", css: "'Inter', sans-serif", cat: "sans", note: "UI font" },
    { name: "Droid Sans Mono", css: "'Droid Sans Mono', 'Noto Sans Mono', monospace", cat: "mono", note: "Monospace" },
    { name: "Noto Naskh Arabic", css: "'Noto Naskh Arabic', serif", cat: "arabic", note: "Arabic · fallback" },
  ];
  RD.font = (name) => RD.FONTS.find((f) => f.name === name) || RD.FONTS[0];

  /** CSS custom properties for the reflowable page */
  RD.style = (b, c) => {
    const pdf = RD.isPdf(b), ar = RD.isAr(b);
    let fs, lh, mx, mt, mb, align, ws;
    if (pdf) { // reflow mode of a PDF
      fs = 18.5 * parseFloat(c.font_size || 1); lh = { 1: 1.32, 1.2: 1.5, 1.4: 1.75 }[c.line_spacing] || 1.5;
      mx = mt = mb = 10 + parseFloat(c.page_margin || 0.1) * 60;
      align = { "-1": "justify", 0: "left", 1: "center", 2: "right", 3: "justify" }[c.justification] || "justify";
      ws = { "0.05": "-.04em", "-0.2": "0", "0.375": ".12em" }[c.word_spacing] || "0";
    } else {
      fs = parseFloat(c.font_size) * 0.86; lh = (ar ? 1.85 : 1.48) * (parseFloat(c.line_spacing) / 100);
      mx = 10 + parseFloat(c.h_page_margins) * 1.2; mt = 6 + parseFloat(c.t_page_margin) * 0.8; mb = 6 + parseFloat(c.b_page_margin) * 0.8;
      align = c.text_align === "left" ? "start" : "justify";
      ws = { small: "-.05em", medium: "0", large: ".1em" }[c.word_spacing] || "0";
    }
    const gi = pdf ? 1 : Math.max(0, ["10", "15", "25", "30", "36", "43", "49", "56"].indexOf(c.font_gamma));
    const ink = gi === 0 ? "color-mix(in srgb, var(--page-ink) 74%, var(--page))" : "var(--page-ink)";
    const stroke = gi > 1 ? ((gi - 1) * 0.09).toFixed(2) + "px" : "0px";
    const fw = 400 + (pdf ? 0 : parseFloat(c.font_base_weight || 0) * 100);
    const ff = ar ? "'Noto Naskh Arabic', serif" : RD.font(c.font_face).css;
    const vars = { "--rd-fs": fs.toFixed(2) + "px", "--rd-lh": lh.toFixed(3), "--rd-mx": mx.toFixed(1) + "px", "--rd-mt": mt.toFixed(1) + "px", "--rd-mb": mb.toFixed(1) + "px",
      "--rd-ff": ff, "--rd-fw": fw, "--rd-ws": ws, "--rd-align": align, "--rd-ink": ink, "--rd-stroke": stroke,
      "--rd-indent": (pdf ? (c.detect_indent === "0" ? 0 : 1.2) : c.para_indent) + "em", "--rd-pspace": (pdf ? 0 : c.para_space) + "em",
      "--rd-hyph": !ar && (pdf || c.hyphenation === "1") ? "auto" : "manual", "--rd-wx": { 0: "0", 5: ".01em", 15: ".02em" }[c.word_expansion] || "0" };
    return Object.entries(vars).map(([k, v]) => `${k}:${v}`).join(";");
  };
  RD.twoCols = (c) => { const { w, h } = RD.screenSize(); return c.view_mode !== "1" && (c.visible_pages === "2" || (c.visible_pages === "auto" && w > h)); };

  /* ---------------------------------------------------- annotations data */
  RD.today = "Nov 19";
  RD.hls = (id) => {
    const v = App.get("rd.hl." + id, null);
    if (v) return v;
    const notes = DB.HIGHLIGHTS.filter((h) => h.book === id).map((h) => h.note).filter(Boolean);
    return [
      { hid: "s1", ch: 0, pid: 1, a: 3, b: 16, style: "lighten", color: "yellow", note: "", date: "Nov 18" },
      { hid: "s2", ch: 0, pid: 4, a: 0, b: 11, style: "underscore", color: "blue", note: notes[0] || "Echoes the opening — come back to this.", date: "Nov 18" },
      { hid: "s3", ch: 1, pid: 2, a: 5, b: 19, style: "lighten", color: "green", note: "", date: "Nov 17" },
      { hid: "s4", ch: 2, pid: 3, a: 2, b: 12, style: "strikeout", color: "red", note: "", date: "Nov 15" },
      { hid: "s5", ch: 3, pid: 0, a: 0, b: 14, style: "invert", color: "gray", note: "Key passage for the essay.", date: "Nov 12" },
    ];
  };
  RD.saveHls = (id, v) => App.set("rd.hl." + id, v);
  RD.hlText = (id, h) => { const p = RD.blocks(id, h.ch, false).find((x) => x.pid === h.pid); return p ? p.w.slice(h.a, h.b).join(" ").replace(/[,;]$/, "") : ""; };
  RD.bms = (id) => App.get("rd.bm." + id, [{ ch: 0, pid: 6, a: 0, date: "Nov 18", note: "" }, { ch: 2, pid: 0, a: 0, date: "Nov 16", note: "Start of the vote" }, { ch: 4, pid: 5, a: 0, date: "Nov 10", note: "" }]);
  RD.saveBms = (id, v) => App.set("rd.bm." + id, v);

  /* ------------------------------------------------------ pagination */
  RD.L = null; RD.fontGen = 0;
  RD.layoutKey = (id) => { const { w, h } = RD.screenSize(); return JSON.stringify([id, RD.cfg(id), w, h, RD.fontGen]); };
  RD.layout = (id) => (RD.L && RD.L.key === RD.layoutKey(id) ? RD.L : null);
  const fits = (box) => box.scrollHeight <= box.clientHeight + 1 && box.scrollWidth <= box.clientWidth + 1;

  /** block → HTML. o: {spans, dc, marks:[{a,b,cls,attr}], handles, trMark} */
  RD.blockHTML = (blk, a, b, o = {}) => {
    const n = blk.w.length;
    const txt = (i) => (o.dc && i === 0 ? blk.w[0].replace(/^[“"‘]+/, "") : blk.w[i]); // no quote mark before a drop cap
    const wordHTML = (i) => {
      const pre = o.handles && i === o.handles.a ? `<span class="rd-hdl s"></span>` : "", post = o.handles && i === o.handles.b - 1 ? `<span class="rd-hdl e"></span>` : "";
      return o.spans ? `<span class="w" data-i="${i}">${pre}${E(txt(i))}${post}</span>` : E(txt(i));
    };
    const range = (from, to) => {
      // group consecutive words that share the same set of marks
      let out = "", cur = null, buf = [];
      const flush = () => {
        if (!buf.length) return;
        const html = buf.join(" ");
        out += (out ? " " : "") + (cur && cur.length ? `<mark class="${cur.map((m) => m.cls).join(" ")}" ${cur.map((m) => m.attr || "").join(" ")}>${html}</mark>` : html);
        buf = [];
      };
      for (let i = from; i < to; i++) {
        const act = (o.marks || []).filter((m) => i >= m.a && i < m.b);
        const sig = act.map((m) => m.cls).join("|");
        if (cur === null || sig !== cur.map((m) => m.cls).join("|")) { flush(); cur = act; }
        buf.push(wordHTML(i));
      }
      flush(); return out;
    };
    const data = `data-p="${blk.pid}" data-o="${a}"`;
    if (blk.t === "v") return `<div class="rd-verse" ${data}><span class="h1">${range(Math.max(a, 0), blk.split)}</span><span class="h2">${range(blk.split, n)}</span></div>`;
    const cls = ["rd-p", blk.t === "ar" ? "rd-artr" : "", blk.ar ? "rd-arp" : "", a > 0 ? "cont" : "", b < n ? "split" : "", o.dc && a === 0 ? "dc" : ""].filter(Boolean).join(" ");
    const dir = blk.t === "ar" ? ` dir="rtl" lang="ar"` : "";
    const mark = o.trMark && blk.t === "p" && a === 0 ? `<button class="rd-trmark" data-action="rdTrMark" data-p="${blk.pid}" aria-label="Translation">ع</button>` : "";
    return `<p class="${cls}" ${data}${dir}>${mark}${range(a, b)}</p>`;
  };
  RD.headHTML = (b, ch, scan) => {
    const c = RD.chapters(b.id)[ch];
    if (RD.isAr(b)) return `<div class="rd-chead ar" dir="rtl"><div class="lbl">${E(c.label)}</div><div class="ttl">${E(c.title)}</div><div class="orn"><i></i><b></b><i></i></div></div>`;
    return `<div class="rd-chead${scan ? " scan" : ""}"><div class="lbl">${E(c.label)}</div><div class="ttl">${E(c.title)}</div><div class="orn"><i></i><b></b><i></i></div></div>`;
  };

  function paginateChapter(box, b, ch, blocks, scan, trMark) {
    const pages = []; let bi = 0, wi = 0, first = true;
    while (bi < blocks.length) {
      box.innerHTML = first ? RD.headHTML(b, ch, scan) : "";
      const items = first ? [{ head: 1 }] : [];
      let guard = 0;
      while (bi < blocks.length && guard++ < 400) {
        const blk = blocks[bi], n = blk.w.length, dc = first && bi === 0;
        let el = mk(RD.blockHTML(blk, wi, n, { dc, trMark }));
        box.appendChild(el);
        if (fits(box)) { items.push({ bi, a: wi, b: n }); bi++; wi = 0; continue; }
        const hasText = items.some((x) => !x.head);
        if (blk.t === "v" || n - wi <= 3) {
          el.remove();
          if (!hasText) { box.appendChild(mk(RD.blockHTML(blk, wi, n, { dc, trMark }))); items.push({ bi, a: wi, b: n }); bi++; wi = 0; }
          break;
        }
        let lo = wi + 1, hi = n - 1, best = wi;
        while (lo <= hi) {
          const mid = (lo + hi) >> 1;
          const nel = mk(RD.blockHTML(blk, wi, mid, { dc, trMark })); el.replaceWith(nel); el = nel;
          if (fits(box)) { best = mid; lo = mid + 1; } else hi = mid - 1;
        }
        el.remove();
        if (best - wi >= 4 || (!hasText && best > wi)) { box.appendChild(mk(RD.blockHTML(blk, wi, best, { dc, trMark }))); items.push({ bi, a: wi, b: best }); wi = best; }
        else if (!hasText) { items.push({ bi, a: wi, b: n }); bi++; wi = 0; }
        break;
      }
      pages.push(items); first = false;
    }
    return pages;
  }

  /** compute (or reuse) the layout. box = live element with the page text box */
  RD.ensureLayout = (id, box) => {
    const key = RD.layoutKey(id);
    if (RD.L && RD.L.key === key) return RD.L;
    const b = RD.book(id), c = RD.cfg(id), scan = RD.isPdf(b) && c.text_wrap !== "1";
    const inline = RD.bilingual(b) && c.tr_inline === "1", trMark = RD.bilingual(b) && c.tr_marks === "1" && !inline;
    const chs = RD.chapters(id), pages = [], chStart = [];
    const saved = box.innerHTML;
    chs.forEach((_, ch) => {
      const blocks = RD.blocks(id, ch, inline);
      chStart.push(pages.length);
      paginateChapter(box, b, ch, blocks, scan, trMark).forEach((items, k) => {
        const words = items.reduce((s, it) => s + (it.head ? 0 : it.b - it.a), 0);
        pages.push({ ch, k, items, words });
      });
    });
    box.innerHTML = saved;
    RD.L = { key, id, pages, chStart, total: pages.length, scan, inline, trMark };
    return RD.L;
  };
  /** page index (0-based) containing the anchor {ch, pid, a} */
  RD.pageOf = (L, an) => {
    if (!an || L.chStart[an.ch] == null) return 0;
    const blocks = RD.blocks(L.id, an.ch, L.inline);
    let best = L.chStart[an.ch];
    for (let i = L.chStart[an.ch]; i < L.total && L.pages[i].ch === an.ch; i++) {
      for (const it of L.pages[i].items) {
        if (it.head) continue; const blk = blocks[it.bi];
        if (blk.pid === an.pid && an.a >= it.a && an.a < it.b) return i;
        if (blk.t !== "ar" && +blk.pid <= an.pid) best = i;
      }
    }
    return best;
  };
  RD.anchorOf = (L, pi) => {
    const p = L.pages[clamp(pi, 0, L.total - 1)]; const it = p.items.find((x) => !x.head); if (!it) return { ch: p.ch, pid: 0, a: 0 };
    const blk = RD.blocks(L.id, p.ch, L.inline)[it.bi]; const pid = blk.t === "ar" ? blk.src : blk.pid;
    return { ch: p.ch, pid, a: blk.t === "ar" ? 0 : it.a };
  };
  RD.keepAnchor = (id) => { const L = RD.layout(id); const pg = +App.current.params.page || 1; if (L && App.current.name === "reader") RD.pendingAnchor = RD.anchorOf(L, pg - 1); };
  RD.cur = () => { const p = App.current.params || {}; return { id: p.id || "animal-farm", page: +p.page || 1 }; };

  const hlMarks = (hls, blk) => hls.filter((h) => h.pid === blk.pid && blk.t !== "ar").map((h) => ({ a: h.a, b: h.b, cls: `hl s-${h.style} c-${h.color}${h.note ? " has-note" : ""}`, attr: `data-hid="${h.hid}"` }));
  /** re-render one block element in place with a live selection (continuous band while dragging) */
  RD.paintLive = (id, pEl, sa, sb) => {
    const L = RD.layout(id), p = L && L.pages[RD.cur().page - 1]; if (!p) return pEl;
    const pid = isNaN(+pEl.dataset.p) ? pEl.dataset.p : +pEl.dataset.p;
    const blk = RD.blocks(id, p.ch, L.inline).find((x) => x.pid === pid); if (!blk) return pEl;
    const a = +pEl.dataset.o, b = a + pEl.querySelectorAll(".w").length;
    const marks = hlMarks(RD.hls(id).filter((h) => h.ch === p.ch), blk).concat(sa != null ? [{ a: sa, b: sb, cls: "rd-sel" }] : []);
    const el = mk(RD.blockHTML(blk, a, b, { spans: true, dc: pEl.classList.contains("dc"), marks, trMark: L.trMark }));
    pEl.replaceWith(el); return el;
  };
  /** render one page's text. opts: {spans, sel:{ch,pid,a,b}, thumb} */
  RD.pageHTML = (L, pi, opts = {}) => {
    const p = L.pages[pi]; if (!p) return "";
    const b = RD.book(L.id), blocks = RD.blocks(L.id, p.ch, L.inline);
    const hls = opts.thumb ? [] : RD.hls(L.id).filter((h) => h.ch === p.ch);
    return p.items.map((it) => {
      if (it.head) return RD.headHTML(b, p.ch, L.scan);
      const blk = blocks[it.bi];
      const marks = hlMarks(hls, blk);
      let handles = null;
      if (opts.sel && opts.sel.ch === p.ch && opts.sel.pid === blk.pid && blk.t !== "ar") {
        marks.push({ a: opts.sel.a, b: opts.sel.b, cls: opts.sel.para ? "rd-sel para" : "rd-sel" });
        if (opts.sel.handles !== false) handles = { a: Math.max(opts.sel.a, it.a), b: Math.min(opts.sel.b, it.b) };
      }
      return RD.blockHTML(blk, it.a, it.b, { spans: opts.spans, dc: p.k === 0 && it.bi === 0, marks, handles, trMark: L.trMark && !opts.thumb });
    }).join("");
  };
  RD.pageInfo = (L, pi) => {
    const p = L.pages[pi], ch = RD.chapters(L.id)[p.ch];
    const end = p.ch + 1 < L.chStart.length ? L.chStart[p.ch + 1] : L.total;
    let left = 0; for (let i = pi + 1; i < end; i++) left += L.pages[i].words;
    const mins = Math.max(1, Math.round((left + p.words * 0.5) / 230));
    return { ch: p.ch, chapter: ch, pct: Math.max(1, Math.round(((pi + 1) / L.total) * 100)), mins, end, inCh: pi - L.chStart[p.ch] + 1, chPages: end - L.chStart[p.ch] };
  };
  RD.isBookmarked = (L, pi) => RD.bms(L.id).some((m) => RD.pageOf(L, m) === pi);

  /* --------------------------------------------- PDF: scanned page model */
  const SCAN = { w: 420, h: 594, cx: 46, cy: 40, cw: 328, ch: 516 }; // content box (running head → folio)
  RD.SCAN = SCAN;
  RD.scanHTML = (L, pi, opts = {}) => {
    const b = RD.book(L.id), c = RD.cfg(L.id), r = rng("scan" + L.id + pi), num = pi + 1;
    const tilt = c.auto_straighten !== "0" || opts.thumb ? 0 : ((r() - 0.5) * 1.1).toFixed(2);
    const wm = c.page_opt === "1" ? "" : `<div class="wm">ARCHIVE COPY</div>`;
    const dirt = c.background_cleanup === "1" ? "" : `<svg class="dirt" viewBox="0 0 420 594" aria-hidden="true">${Array.from({ length: 26 }, () => `<circle cx="${(r() * 420).toFixed(0)}" cy="${(r() * 594).toFixed(0)}" r="${(0.4 + r() * 1.1).toFixed(1)}"/>`).join("")}<rect x="${num % 2 ? 0 : 400}" y="0" width="20" height="594" class="gut"/></svg>`;
    const run = num % 2 ? E(RD.short(b).toUpperCase()) : E(RD.chapters(L.id)[L.pages[pi].ch].title.toUpperCase());
    return `<div class="rd-scan ${num % 2 ? "odd" : "even"}" style="--tilt:${tilt}deg">${dirt}${wm}
      <div class="run"><span>${num % 2 ? "" : num}</span><span>${run}</span><span>${num % 2 ? num : ""}</span></div>
      <div class="rd-text rd-scantext" lang="en">${RD.pageHTML(L, pi, opts)}</div></div>`;
  };
  /** geometry for the scanned page given the viewport */
  RD.scanGeo = (c, vw, vh) => {
    let crop = c.trim_page === "3" ? { x: 0, y: 0, w: SCAN.w, h: SCAN.h } : { x: SCAN.cx - 8, y: SCAN.cy - 8, w: SCAN.cw + 16, h: SCAN.ch + 16 };
    const m = parseFloat(c.page_margin || 0.1) * 40;
    const fit = { 2: "full", 1: "width", 0: "height" }[c.zoom_mode_type] || "width";
    const genus = c.zoom_mode_genus || "4", n = +c.zoom_range_number || 2;
    if (genus === "3") crop = { x: SCAN.cx - 8, y: SCAN.cy - 8, w: SCAN.cw + 16, h: SCAN.ch + 16 };
    const sw = (vw - 2 * m) / crop.w, sh = (vh - 2 * m) / crop.h;
    let s;
    if (genus === "4" || genus === "3") s = fit === "full" ? Math.min(sw, sh) : fit === "height" ? sh : sw;
    else if (genus === "2") s = (vw - 2 * m) / (crop.w / n);
    else if (genus === "1") s = sw * Math.max(1, n / 2);
    else s = sw * parseFloat(c.zoom_factor || 1.5);
    const ph = crop.h * s + 2 * m, pw = crop.w * s;
    const x0 = pw <= vw ? (vw - pw) / 2 : m;
    return { s, m, crop, ph, pw, x0, gap: c.page_scroll === "1" ? +c.page_gap_height : 0, cont: c.page_scroll === "1", step: Math.max(80, vh - +c.zoom_overlap_v * 1.2) };
  };
  RD.measureScan = (id, host) => {
    if (RD.layout(id)) return RD.L;
    const m = mk(`<div class="rd-scan rd-measure"><div class="rd-text rd-scantext" lang="en"></div></div>`);
    host.appendChild(m);
    const L = RD.ensureLayout(id, m.firstElementChild);
    m.remove(); return L;
  };

  /* ------------------------------------------------------------ screen */
  function headerHTML(b, L, pi, c) {
    if (!L) return `<header class="rd-head"></header>`;
    const inf = RD.pageInfo(L, pi);
    const alt = c.status_line === "0";
    const t = new Date(), hh = String(t.getHours()).padStart(2, "0"), mm = String(t.getMinutes()).padStart(2, "0");
    return `<header class="rd-head${alt ? " alt" : ""}">
      <span class="t ellipsis">${E(RD.short(b))}</span>
      ${alt ? `<span class="mid num">${hh}:${mm}<span class="dot">·</span>87%</span>` : ""}
      <span class="c ellipsis" ${RD.isAr(b) ? 'dir="rtl"' : ""}>${E(inf.chapter.label)} · ${E(inf.chapter.title)}</span></header>`;
  }
  function footerHTML(b, L, pi) {
    if (!L) return `<footer class="rd-foot"></footer>`;
    const inf = RD.pageInfo(L, pi);
    const ticks = L.chStart.slice(1).map((s) => `<i style="left:${(s / L.total) * 100}%"></i>`).join("");
    return `<footer class="rd-foot">
      <div class="rd-line"><span class="fill" style="width:${((pi + 1) / L.total) * 100}%"></span>${ticks}</div>
      <div class="rd-foot-row"><span class="num">${inf.pct}%<span class="dot">·</span>${inf.mins} min${inf.mins > 1 ? "s" : ""} left in chapter</span><span class="num pg">${pi + 1}<span class="of"> / ${L.total}</span></span></div>
    </footer>`;
  }
  const num = (v) => (v == null || v === "" || isNaN(+v) ? v : +v);
  function selFromStack(L) {
    const top = App.top(); if (!top) return null;
    const p = top.params || {};
    const pg = (+App.current.params.page || 1) - 1;
    if (["hl-popup", "dict", "wiki"].includes(top.name) && p.pid != null && p.ch != null && p.a != null) return { ch: +p.ch, pid: num(p.pid), a: +p.a, b: +p.b, handles: top.name === "hl-popup" };
    if (top.name === "hl-popup" && p.demo) return RD.demoSel(L, pg, "range");
    if ((top.name === "dict" || top.name === "wiki") && p.demo) return { ...RD.demoSel(L, pg, "word"), handles: false };
    if (top.name === "translate" && RD.trTarget) { const t = RD.trTarget(L, p); return t ? { ch: t.ch, pid: t.pid, a: 0, b: RD.para(L.id, t.ch, t.pid).w.length, handles: false, para: true } : null; }
    return null;
  }
  RD.selFromStack = selFromStack;
  /** a believable selection on the given page (for demos) */
  RD.demoSel = (L, pi, kind) => {
    const p = L.pages[pi]; if (!p) return null;
    const blocks = RD.blocks(L.id, p.ch, L.inline);
    let its = p.items.filter((x) => !x.head && blocks[x.bi].t !== "ar" && x.b - x.a > 14);
    if (!its.length) { its = p.items.filter((x) => !x.head && x.b - x.a >= 4); const it = its[Math.min(2, its.length - 1)]; if (!it) return null; return { ch: p.ch, pid: blocks[it.bi].pid, a: it.a + 1, b: kind === "word" ? it.a + 2 : it.a + 4 }; }
    const it = its[Math.min(1, its.length - 1)]; if (!it) return null;
    const blk = blocks[it.bi];
    let a = it.a + 3;
    for (let i = it.a + 2; i < it.b - 9; i++) if (RD.goodWord(blk.w[i])) { a = i; break; }
    return { ch: p.ch, pid: blk.pid, a, b: kind === "word" ? a + 1 : Math.min(it.b, a + 7) };
  };
  RD.goodWord = (w) => /^[a-z]{5,}[,.]?$/i.test(w); // refined by reader-panels.js

  App.screen("reader", {
    title: "Reader",
    render(params) {
      const id = params.id || "animal-farm", b = RD.book(id), c = RD.cfg(id), L = RD.layout(id);
      const pi = L ? clamp((+params.page || 1) - 1, 0, L.total - 1) : 0;
      const ar = RD.isAr(b), pdf = RD.isPdf(b), scan = pdf && c.text_wrap !== "1";
      const sel = L ? selFromStack(L) : null;
      RD.selSig = JSON.stringify(sel);
      const bm = L && RD.isBookmarked(L, pi);
      const cls = ["ko-view", "rd-screen", ar ? "is-ar" : "", RD.twoCols(c) && !pdf ? "two" : "", scan ? "is-scan" : "", pdf ? "is-pdf" : "", c.nightmode_document === "1" && scan ? "inv" : "", "rot-" + (c.rotation_mode || "0")].filter(Boolean).join(" ");
      const body = scan
        ? `<div class="rd-body rd-scanview" data-action="rdTap">${L ? scanViewHTML(L, pi, params, c, sel) : ""}</div>`
        : `<div class="rd-body" data-action="rdTap"><div class="rd-text" lang="${ar ? "ar" : "en"}" ${ar ? 'dir="rtl"' : ""}>${L ? RD.pageHTML(L, pi, { spans: true, sel }) : ""}</div></div>`;
      return `<div class="${cls}" style="${RD.style(b, c)}" data-id="${E(id)}">
        ${scan ? "" : headerHTML(b, L, pi, c)}
        ${body}
        ${footerHTML(b, L, pi)}
        ${bm ? `<span class="rd-dogear" aria-label="Bookmarked"></span>` : ""}
      </div>`;
    },
    mount(root, params) {
      const id = params.id || "animal-farm", b = RD.book(id), c = RD.cfg(id);
      if (!RD.layout(id)) {
        if (RD.isPdf(b) && c.text_wrap !== "1") RD.measureScan(id, root.querySelector(".rd-screen"));
        else { const box = root.querySelector(".rd-text"); if (!box) return; RD.ensureLayout(id, box); }
        const L = RD.L; let page = +params.page || 0;
        if (RD.pendingAnchor) { page = RD.pageOf(L, RD.pendingAnchor) + 1; RD.pendingAnchor = null; }
        if (params.hl) { const h = RD.hls(id).find((x) => x.hid === params.hl); if (h) page = RD.pageOf(L, h) + 1; delete params.hl; }
        if (params.ch != null) { page = (L.chStart[clamp(+params.ch, 0, L.chStart.length - 1)] || 0) + 1; delete params.ch; }
        if (!page) { const an = App.get("rd.pos." + id, null); page = an ? RD.pageOf(L, an) + 1 : Math.max(1, Math.round(((b.progress || 0) / 100) * L.total)); }
        params.page = clamp(page, 1, L.total); params.id = id;
        root.innerHTML = App.screens.reader.render(params);
        App.icons(); App.syncHash();
      }
      attachSelection(root, id);
      if (params.chrome && !App.state.stack.length) { delete params.chrome; setTimeout(() => App.open("reader-chrome", {}), 0); }
    },
  });

  function scanViewHTML(L, pi, params, c, sel) {
    const { w, h } = RD.screenSize(); const vh = h - 30;
    const g = RD.scanGeo(c, w, vh);
    const y = (parseFloat(params.y) || 0) * g.ph;
    const tf = `transform:translate(${(g.x0 - g.crop.x * g.s).toFixed(1)}px, ${(g.m - g.crop.y * g.s).toFixed(1)}px) scale(${g.s.toFixed(4)})`;
    const con = 0.85 + Math.log2(1 + parseFloat(c.contrast || 1)) * 0.15;
    const filt = [`contrast(${Math.min(2.2, con).toFixed(2)})`, c.white_threshold && c.white_threshold !== "255" ? `brightness(${(1 + (255 - c.white_threshold) / 900).toFixed(3)})` : "", c.quality === "0.5" ? "blur(.3px)" : "", `saturate(${c.saturation || 1})`].join(" ");
    let out = "", top = -y, i = pi;
    while (i < L.total && top < vh) {
      out += `<div class="rd-scanpage" style="height:${g.ph.toFixed(1)}px;top:${top.toFixed(1)}px;--filt:${filt}"><div class="rd-scanpos" style="${tf}">${RD.scanHTML(L, i, { spans: true, sel })}</div></div>`;
      if (!g.cont) break;
      top += g.ph + g.gap; i++;
    }
    return out;
  }

  /* -------------------------------------------------------- navigation */
  RD.goPage = (id, page, extra = {}) => {
    const L = RD.layout(id); if (!L) return;
    if (page > L.total) { App.go("reader", { id, page: L.total }); App.open("book-end", { id }); return; }
    page = clamp(page, 1, L.total);
    App.set("rd.pos." + id, RD.anchorOf(L, page - 1));
    App.go("reader", { id, page, ...extra });
  };
  RD.turn = (dir) => {
    const { id, page } = RD.cur(); const L = RD.layout(id); if (!L) return;
    const b = RD.book(id), c = RD.cfg(id);
    if (RD.isPdf(b) && c.text_wrap !== "1") {
      const { w, h } = RD.screenSize(); const vh = h - 30, g = RD.scanGeo(c, w, vh);
      const y0 = (parseFloat(App.current.params.y) || 0) * g.ph;
      let y = y0, pg = page;
      if (g.cont) {
        y += dir * g.step;
        while (y >= g.ph + g.gap && pg < L.total) { y -= g.ph + g.gap; pg++; }
        while (y < 0 && pg > 1) { y += g.ph + g.gap; pg--; }
        if (y < 0) y = 0;
        if (pg >= L.total) { const maxY = Math.max(0, g.ph - vh); if (dir > 0 && y0 >= maxY - 1 && page >= L.total) return RD.goPage(id, L.total + 1); y = Math.min(y, maxY); }
      } else {
        if (dir > 0) { if (y + vh < g.ph - 2) y = Math.min(y + g.step, g.ph - vh); else { pg++; y = 0; } }
        else if (y > 1) y = Math.max(0, y - g.step);
        else { pg--; y = pg >= 1 ? Math.max(0, g.ph - vh) : 0; }
        if (pg < 1) { pg = 1; y = 0; }
      }
      return RD.goPage(id, pg, y > 0 ? { y: +(y / g.ph).toFixed(4) } : {});
    }
    RD.goPage(id, page + dir);
  };
  App.action("rdTap", (el, ev) => {
    if (RD.suppressClick) { RD.suppressClick = false; return; }
    if (ev.target.closest(".rd-trmark")) return;
    const hl = ev.target.closest("mark.hl");
    if (hl) { const { id } = RD.cur(); return App.open("hl-popup", { id, hid: hl.dataset.hid }); }
    const r = el.getBoundingClientRect(), x = (ev.clientX - r.left) / r.width;
    const rtl = RD.isAr(RD.book(RD.cur().id));
    if (x < 1 / 3) RD.turn(rtl ? 1 : -1);
    else if (x > 2 / 3) RD.turn(rtl ? -1 : 1);
    else App.open("reader-chrome", {});
  });
  App.action("rdTrMark", (el) => { const { id, page } = RD.cur(); const L = RD.layout(id); App.open("translate", { id, ch: L.pages[page - 1].ch, pid: +el.dataset.p }); });
  document.addEventListener("keydown", (e) => {
    if (App.current.name !== "reader" || App.state.stack.length || (e.target.closest && e.target.closest("input"))) return;
    const rtl = RD.isAr(RD.book(RD.cur().id));
    if (e.key === "ArrowRight" || e.key === "PageDown" || e.key === " ") { e.preventDefault(); RD.turn(rtl ? -1 : 1); }
    if (e.key === "ArrowLeft" || e.key === "PageUp") { e.preventDefault(); RD.turn(rtl ? 1 : -1); }
    if (e.key === "Enter" || e.key === "m") App.open("reader-chrome", {});
  });
  // the page shows the selection of the top overlay (hl-popup, dict, translate…): redraw it when that changes
  document.addEventListener("folio:navigate", () => {
    if (App.current.name !== "reader" || RD._redrawing) return;
    const L = RD.layout(RD.cur().id); if (!L) return;
    if (JSON.stringify(selFromStack(L)) === RD.selSig) return;
    RD._redrawing = true;
    const root = document.getElementById("screen-root");
    root.innerHTML = App.screens.reader.render(App.current.params); App.screens.reader.mount(root, App.current.params); App.icons();
    RD._redrawing = false;
    const top = App.top(); if (top && top.name === "hl-popup") RD.quiet(() => App.renderLayers(true)); // re-anchor the popup to the new marks
  });
  // re-paginate once web fonts arrive
  if (document.fonts) document.fonts.addEventListener("loadingdone", () => {
    clearTimeout(RD._f); RD._f = setTimeout(() => {
      if (App.current.name !== "reader") { RD.L = null; return; }
      const { id } = RD.cur(); RD.keepAnchor(id); RD.fontGen++; RD.quietRefresh();
    }, 60);
  });

  /* ------------------------------------------- long-press text selection */
  function attachSelection(root, id) {
    const text = root.querySelector(".rd-body"); if (!text) return;
    let timer = null, st = null;
    const wordAt = (x, y) => { const el = document.elementFromPoint(x, y); const w = el && el.closest(".w"); const p = w && w.closest("[data-p]"); return w && p ? { w, p, pid: num(p.dataset.p), i: +w.dataset.i } : null; };
    const clean = (w) => (w ? w.textContent.replace(/[^\p{L}'-]/gu, "") : "");
    const paint = () => {
      const pEl = text.querySelector(`[data-p="${st.pid}"]`); if (!pEl) return;
      RD.paintLive(id, pEl, Math.min(st.a, st.b), Math.max(st.a, st.b) + 1);
    };
    text.addEventListener("pointerdown", (ev) => {
      const hit = wordAt(ev.clientX, ev.clientY); if (!hit || ev.target.closest(".rd-trmark")) return;
      timer = setTimeout(() => { st = { pid: hit.pid, a: hit.i, b: hit.i }; paint(); }, 420);
    });
    text.addEventListener("pointermove", (ev) => {
      if (!st) return; const hit = wordAt(ev.clientX, ev.clientY);
      if (hit && hit.pid === st.pid) { st.b = hit.i; paint(); }
    });
    text.addEventListener("pointerup", () => {
      clearTimeout(timer);
      if (!st) return;
      const L = RD.layout(id), ch = L.pages[RD.cur().page - 1].ch;
      const a = Math.min(st.a, st.b), b = Math.max(st.a, st.b) + 1, pid = st.pid;
      const word = clean(text.querySelector(`[data-p="${pid}"] .w[data-i="${a}"]`));
      st = null; RD.suppressClick = true;
      App.open(b - a === 1 ? "dict" : "hl-popup", { id, ch, pid, a, b, word });
    });
    text.addEventListener("pointerleave", () => { if (!st) clearTimeout(timer); });
    text.addEventListener("dblclick", (ev) => {
      const hit = wordAt(ev.clientX, ev.clientY); if (!hit) return;
      const L = RD.layout(id), ch = L.pages[RD.cur().page - 1].ch;
      App.open("dict", { id, ch, pid: hit.pid, a: hit.i, b: hit.i + 1, word: clean(hit.w) });
    });
  }

  /* ------------------------------------------------------- reader chrome */
  App.overlay("reader-chrome", {
    layer: "popover", clear: true,
    render() {
      const { id, page } = RD.cur(), b = RD.book(id), L = RD.layout(id);
      if (!L) return "";
      const pi = page - 1, inf = RD.pageInfo(L, pi), bm = RD.isBookmarked(L, pi);
      const ticks = L.chStart.slice(1).map((s) => `<i style="left:${(s / Math.max(1, L.total - 1)) * 100}%"></i>`).join("");
      const pct = L.total > 1 ? (pi / (L.total - 1)) * 100 : 0;
      const tool = (ic, label, attrs) => `<button class="rd-tool" ${attrs}>${ic}<span>${label}</span></button>`;
      return `<div class="rd-chrome">
        <div class="rd-ctop">
          ${App.statusBar({ left: "" })}
          <div class="rd-ctop-row">
            <button class="ko-icon-btn" data-go="library" aria-label="Back to library">${I("arrow-left")}</button>
            <div class="rd-ctitle grow"><b class="ellipsis">${E(RD.short(b))}</b><span class="ellipsis">${E(b.author.split(";")[0])}</span></div>
            <button class="ko-icon-btn ${bm ? "active" : ""}" data-action="rdBookmark" aria-label="Bookmark">${I(bm ? "bookmark-check" : "bookmark")}</button>
            <button class="ko-icon-btn" data-go="search" data-params='${App.attrs({ scope: "book", id })}' aria-label="Search in book">${I("search")}</button>
            <button class="ko-icon-btn" data-action="rdMenu" aria-label="Menu">${I("menu")}</button>
          </div>
        </div>
        <div class="rd-cbot">
          <div class="rd-scrub">
            <button class="ko-icon-btn" data-action="rdChapter" data-d="-1" aria-label="Previous chapter">${I("skip-back")}</button>
            <div class="grow">
              <div class="rd-scrub-lbl"><span class="ellipsis" id="rd-scrub-ch">${E(inf.chapter.label)} · ${E(inf.chapter.title)}</span><span class="num" id="rd-scrub-pg">${page} / ${L.total}</span></div>
              <div class="rd-scrub-track"><div class="rd-scrub-ticks">${ticks}</div>${App.slider(pct, 'data-slide="rdScrub"')}</div>
            </div>
            <button class="ko-icon-btn" data-action="rdChapter" data-d="1" aria-label="Next chapter">${I("skip-forward")}</button>
          </div>
          <div class="rd-tools">
            ${tool(I("list-tree"), "Contents", `data-action="rdSwap" data-o="toc"`)}
            ${tool(`<span class="rd-aa">Aa</span>`, RD.isPdf(b) ? "Page" : "Typeset", `data-action="rdSwap" data-o="typeset"`)}
            ${tool(I("sun"), "Light", `data-action="rdSwap" data-o="frontlight"`)}
            ${tool(I("highlighter"), "Notes", `data-action="rdSwap" data-o="annotations"`)}
            ${tool(I("ellipsis"), "More", `data-open="reader-more"`)}
          </div>
        </div>
      </div>`;
    },
  });
  App.action("rdSwap", (el) => { const { id } = RD.cur(); App.replaceTop(el.dataset.o, { id }); });
  App.action("rdMenu", () => { const { id } = RD.cur(); const b = RD.book(id); App.replaceTop("main-menu", { ctx: "reader", id, format: b.format }); });
  App.action("rdChapter", (el) => {
    const { id, page } = RD.cur(), L = RD.layout(id), ch = L.pages[page - 1].ch, d = +el.dataset.d;
    let t = d > 0 ? ch + 1 : page - 1 > L.chStart[ch] ? ch : ch - 1;
    t = clamp(t, 0, L.chStart.length - 1);
    RD.quiet(() => { RD.goPage(id, L.chStart[t] + 1); App.open("reader-chrome", {}); });
  });
  App.action("rdScrub", (el, v, done) => {
    const { id } = RD.cur(), L = RD.layout(id); const pi = Math.round(v * (L.total - 1)); const inf = RD.pageInfo(L, pi);
    const a = document.getElementById("rd-scrub-ch"), b = document.getElementById("rd-scrub-pg");
    if (a) a.textContent = `${inf.chapter.label} · ${inf.chapter.title}`; if (b) b.textContent = `${pi + 1} / ${L.total}`;
    if (done) RD.quiet(() => { RD.goPage(id, pi + 1); App.open("reader-chrome", {}); });
  });
  App.action("rdBookmark", () => {
    const { id, page } = RD.cur(), L = RD.layout(id);
    let v = RD.bms(id); const on = v.some((m) => RD.pageOf(L, m) === page - 1);
    if (on) v = v.filter((m) => RD.pageOf(L, m) !== page - 1); else v = [...v, { ...RD.anchorOf(L, page - 1), date: RD.today, note: "" }];
    RD.saveBms(id, v); RD.quietRefresh(); App.toast(on ? "Bookmark removed" : "Page bookmarked");
  });

  /* --------------------------------------------------------- typeset sheet */
  const TAB_META = {
    epub: { "appbar.rotation": ["layout", "Layout", "smartphone"], "appbar.crop": ["margins", "Margins", "square-dashed"], "appbar.pageview": ["page", "Page", "book-open"],
      "appbar.textsize": ["text", "Text", "case-sensitive"], "appbar.contrast": ["contrast", "Contrast", "contrast"], "appbar.settings": ["style", "Style", "sliders-horizontal"] },
    pdf: { "appbar.rotation": ["rotate", "Rotate", "smartphone"], "appbar.crop": ["crop", "Crop", "crop"], "appbar.pagefit": ["zoom", "Zoom", "scan"], "appbar.pageview": ["page", "Page", "book-open"],
      "appbar.textsize": ["reflow", "Reflow", "wrap-text"], "appbar.contrast": ["contrast", "Contrast", "contrast"], "appbar.settings": ["doc", "Document", "file-cog"] },
  };
  // options moved to a friendlier tab (EPUB only). Every option is still shown exactly once.
  const MOVE = { line_spacing: "text", font_base_weight: "text" };
  RD.tsTabs = (b) => {
    const kind = RD.kind(b), pdf = kind === "pdf";
    const tabs = [];
    if (!pdf) tabs.push({ key: "presets", label: "Presets", icon: "sparkles", opts: [] }, { key: "font", label: "Font", icon: "type", opts: [] });
    const meta = (g) => TAB_META[kind][g.icon] || [g.icon.replace("appbar.", ""), g.icon.replace("appbar.", ""), "settings"];
    RD.cfgGroups(pdf).forEach((g) => { const m = meta(g); if (!tabs.some((t) => t.key === m[0])) tabs.push({ key: m[0], label: m[1], icon: m[2], opts: [] }); });
    RD.cfgGroups(pdf).forEach((g) => g.options.forEach((o) => {
      if (o.name === "font_fine_tune" || o.name === "hw_dithering") return; // merged into font size / single dithering control
      const key = (!pdf && MOVE[o.name]) || meta(g)[0];
      tabs.find((t) => t.key === key).opts.push(o);
    }));
    if (pdf) {
      const pri = ["text_wrap", "zoom_mode_genus", "zoom_mode_type", "zoom_range_number", "zoom_factor", "zoom_direction", "zoom_overlap_h", "zoom_overlap_v"];
      tabs.forEach((t) => t.opts.sort((a, b2) => (pri.indexOf(a.name) + 1 || 99) - (pri.indexOf(b2.name) + 1 || 99)));
    }
    if (!pdf) {
      const pri = ["font_size", "line_spacing", "font_base_weight", "word_spacing", "word_expansion", "cjk_width_scaling"];
      const tt = tabs.find((t) => t.key === "text"); if (tt) tt.opts.sort((a, b2) => pri.indexOf(a.name) - pri.indexOf(b2.name));
      const order = ["presets", "text", "font", "margins", "page", "layout", "contrast", "style"];
      tabs.sort((a, b2) => order.indexOf(a.key) - order.indexOf(b2.key));
    }
    return tabs;
  };
  const TITLES = { font_size: "Font size", cjk_width_scaling: "CJK width scaling", zoom_range_number: "Columns / rows", visible_pages: "Two columns", status_line: "Alt status bar", font_gamma: "Contrast", sw_dithering: "Dithering", h_page_margins: "Side margins", t_page_margin: "Top margin", b_page_margin: "Bottom margin", sync_t_b_page_margins: "Sync top & bottom" };
  const UNITS = { font_size: (pdf) => (pdf ? "×" : "pt"), line_spacing: (pdf) => (pdf ? "" : "%"), h_page_margins: () => "px", t_page_margin: () => "px", b_page_margin: () => "px", cjk_width_scaling: () => "%", page_gap_height: () => "px", zoom_overlap_h: () => "px", zoom_overlap_v: () => "px" };
  const OPT_ICONS = { font_size: "a-large-small", line_spacing: "rows-3", font_base_weight: "bold", word_spacing: "space", word_expansion: "move-horizontal", cjk_width_scaling: "languages",
    h_page_margins: "move-horizontal", t_page_margin: "arrow-up-to-line", b_page_margin: "arrow-down-to-line", sync_t_b_page_margins: "link", view_mode: "scroll-text", block_rendering_mode: "layers", render_dpi: "zoom-in",
    font_gamma: "contrast", font_hinting: "grid-3x3", font_kerning: "baseline", status_line: "panel-top", embedded_css: "file-code", embedded_fonts: "type", smooth_scaling: "image", nightmode_images: "image-off",
    visible_pages: "columns-2", trim_page: "crop", page_margin: "square-dashed", auto_straighten: "ruler", zoom_overlap_h: "move-horizontal", zoom_overlap_v: "move-vertical", zoom_mode_type: "maximize",
    zoom_range_number: "columns-3", zoom_factor: "zoom-in", zoom_mode_genus: "scan", zoom_direction: "route", page_scroll: "scroll-text", page_gap_height: "separator-horizontal", justification: "align-justify",
    text_wrap: "wrap-text", contrast: "contrast", saturation: "palette", white_threshold: "sun-dim", page_opt: "eraser", background_cleanup: "sparkles", hw_dithering: "grip", sw_dithering: "grip",
    quality: "gauge", doc_language: "languages", forced_ocr: "scan-text", writing_direction: "arrow-left-right", defect_size: "sparkle", detect_indent: "indent-increase", nightmode_document: "moon", max_columns: "columns-3" };

  const ico = (n) => `<span class="ko-icon-tile">${I(n)}</span>`;
  const helpBtn = (o) => (o.help ? `<button class="ko-help-btn rd-help-btn ${RD.helpOpen === o.name ? "on" : ""}" data-action="tsHelp" data-k="${o.name}" aria-label="About this option">${I("info", "sm")}</button>` : "");
  const helpBody = (o) => (o.help && RD.helpOpen === o.name ? `<div class="rd-help">${E(o.help).replace(/\n/g, "<br>")}</div>` : "");
  const sentence = (t) => t.split(" ").map((w, i) => (i === 0 || /^[A-Z/]{2,}$/.test(w) ? w : w.toLowerCase())).join(" ");
  /** engineering names -> human names; the KOReader name is shown as small help text under the label */
  const HUMAN = {
    block_rendering_mode: ["Layout engine", ["Simple", "Flat", "Book", "Web"]],
    render_dpi: ["Content zoom", ["Device", "½×", "1×", "1.7×", "2.2×", "3×"]],
    font_hinting: ["Sharpen text", ["Off", "Font's own", "Auto"]],
    font_kerning: ["Letter fitting", ["Off", "Fast", "Good", "Best"]],
    smooth_scaling: ["Image quality", ["Fast", "Smooth"]],
    writing_direction: ["Writing direction", ["Left to right", "Right to left", "Vertical (CJK)"]],
    defect_size: ["Ignore specks smaller than", ["Small", "Medium", "Large"]],
    page_opt: ["Remove watermarks"],
    forced_ocr: ["Always use OCR"],
  };
  const optTitle = (o) => (HUMAN[o.name] && HUMAN[o.name][0]) || TITLES[o.name] || sentence(o.title || o.name);
  const koName = (o) => (HUMAN[o.name] ? `KOReader: ${o.title || o.name}` : "");
  const capWord = (l) => (typeof l === "string" && /^[a-z]/.test(l) ? l[0].toUpperCase() + l.slice(1) : l);
  const humanLabels = (o) => (HUMAN[o.name] && HUMAN[o.name][1]) || RD.optLabels(o).map(capWord);
  const isOnOff = (o) => { const l = RD.optLabels(o); return l.length === 2 && l[0] === "off" && l[1] === "on"; };

  /** numeric option → shared App.sliderRow (label, −, slider, +, value on one line) */
  function numControl(b, o, c, opts = {}) {
    const vals = RD.optValues(o), labels = RD.optLabels(o), pdf = RD.isPdf(b);
    const cur = parseFloat(c[o.name]);
    const nums = vals.map(parseFloat);
    const asc = nums[nums.length - 1] >= nums[0];
    const norm = (v) => (asc ? v : -v);
    let pct = 0;
    for (let i = 0; i < nums.length - 1; i++) {
      const lo = norm(nums[i]), hi = norm(nums[i + 1]);
      if (norm(cur) >= lo && norm(cur) <= hi) { pct = ((i + (norm(cur) - lo) / (hi - lo || 1)) / (nums.length - 1)) * 100; break; }
      if (i === nums.length - 2) pct = norm(cur) > hi ? 100 : 0;
    }
    const vi = vals.indexOf(String(c[o.name]));
    const shown = vi >= 0 ? labels[vi] : String(Number.isInteger(cur) ? cur : +cur.toFixed(2));
    const unit = UNITS[o.name] ? UNITS[o.name](pdf) : "";
    let row = App.sliderRow({ label: optTitle(o), icon: OPT_ICONS[o.name] || "sliders-horizontal", pct, value: shown, unit, slide: "tsSlide", step: "tsStep", id: o.name, minIcon: opts.minIcon, maxIcon: opts.maxIcon });
    if (o.help) row = row.replace("</span>", `</span>`).replace(/(<span class="lbl">[\s\S]*?)(<\/span>)/, `$1${helpBtn(o)}$2`);
    return `<div class="rd-num" data-k="${o.name}">${row}${helpBody(o)}</div>`;
  }
  function segControl(o, c, opts = {}) {
    const vals = RD.optValues(o), labels = opts.labels || humanLabels(o);
    const long = labels.join("").length > 30 || labels.length > 6 || (opts.icons && !opts.iconOnly && labels.length >= 5);
    const btns = vals.map((v, i) => `<button class="${String(c[o.name]) === String(v) ? "on" : ""}" data-action="tsSet" data-k="${o.name}" data-v="${E(v)}" ${opts.icons ? `title="${E(labels[i])}"` : ""}>${opts.icons ? I(opts.icons[i], "sm") : ""}${opts.iconOnly ? "" : `<span>${E(labels[i] ?? v)}</span>`}</button>`).join("");
    return `<div class="rd-opt ${long ? "stack" : ""}" data-k="${o.name}">
      <div class="rd-opt-head">${ico(OPT_ICONS[o.name] || "sliders-horizontal")}<span class="lbl">${E(optTitle(o))}${koName(o) ? `<small class="rd-ko">${E(koName(o))}</small>` : ""}</span>${helpBtn(o)}</div>
      ${helpBody(o)}
      <div class="ko-seg rd-seg ${long ? "wrap" : ""}">${btns}</div></div>`;
  }
  function switchRow(o, c, onVal, sub) {
    const vals = RD.optValues(o), labels = RD.optLabels(o);
    const on = String(c[o.name]) === String(onVal);
    const offVal = vals[labels.indexOf("off")] ?? vals[0];
    return `<div class="rd-switch" data-k="${o.name}"><button class="rd-switch-main" data-action="tsSet" data-k="${o.name}" data-v="${E(on ? offVal : onVal)}">
      ${ico(OPT_ICONS[o.name] || "toggle-right")}<span class="lbl">${E(optTitle(o))}${sub || koName(o) ? `<small>${E([sub, koName(o)].filter(Boolean).join(" · "))}</small>` : ""}</span>${App.toggle(on)}</button>${helpBtn(o)}</div>${helpBody(o)}`;
  }
  const SUBS = { embedded_css: "Publisher stylesheets", embedded_fonts: "Publisher fonts", nightmode_images: "Invert images in night mode", sync_t_b_page_margins: "Keep text vertically centred",
    text_wrap: "Extract the text and reflow it to the screen", page_opt: "Remove watermarks and grey backgrounds", background_cleanup: "Black & white essentials only", sw_dithering: "Smoother greys on e-ink",
    forced_ocr: "OCR even when a text layer exists", detect_indent: "Keep paragraph indents when reflowing", nightmode_document: "Invert pages in night mode" };

  function optionHTML(b, o, c) {
    const labels = RD.optLabels(o), vals = RD.optValues(o);
    switch (o.name) {
      case "font_size": return numControl(b, o, c, { minIcon: "a-arrow-down", maxIcon: "a-arrow-up" });
      case "rotation_mode": {
        const deg = { 3: -90, 0: 0, 1: 90, 2: 180 };
        return `<div class="rd-opt" data-k="rotation_mode"><div class="rd-opt-head">${ico("rotate-cw")}<span class="lbl">Rotation</span><span class="rd-opt-val">${RD.isPdf(b) ? "Page orientation" : "Screen orientation"}</span></div>
          <div class="rd-rots">${vals.map((v, i) => `<button class="ko-card ko-card--tap rd-rot ${String(c.rotation_mode) === v ? "on" : ""}" data-action="tsSet" data-k="rotation_mode" data-v="${v}"><span class="dev" style="transform:rotate(${deg[v]}deg)"><i></i></span><b>${["90°", "0°", "90°", "180°"][i]}</b><small>${["Left", "Upright", "Right", "Flipped"][i]}</small></button>`).join("")}</div></div>`;
      }
      case "visible_pages": {
        const on = RD.twoCols(c);
        return `<div class="rd-switch" data-k="visible_pages"><button class="rd-switch-main" data-action="tsSet" data-k="visible_pages" data-v="${on ? "1" : "2"}">${ico("columns-2")}<span class="lbl">Two columns<small>${c.view_mode === "1" ? "Not available in continuous mode" : c.visible_pages === "auto" ? "Automatic: on in landscape" : on ? "Two pages side by side" : "Single page"}</small></span>${App.toggle(on)}</button>${helpBtn(o)}</div>${helpBody(o)}`;
      }
      case "status_line": return switchRow(o, c, "0", "Time and battery in the page header");
      case "justification": return segControl(o, c, { icons: ["wand-sparkles", "align-left", "align-center", "align-right", "align-justify"] });
      case "zoom_direction": {
        const vi = vals.indexOf(String(c.zoom_direction));
        return `<div class="rd-opt" data-k="zoom_direction"><div class="rd-opt-head">${ico("route")}<span class="lbl">Direction</span>${helpBtn(o)}</div>${helpBody(o)}
          <div class="rd-dirs">${vals.map((v, i) => `<button class="${i === vi ? "on" : ""}" data-action="tsSet" data-k="zoom_direction" data-v="${v}" title="${E(labels[i])}" aria-label="${E(labels[i])}">${dirGlyph(i)}</button>`).join("")}</div>
          <div class="rd-opt-cap">${E(labels[vi] || "")}</div></div>`;
      }
      case "max_columns": return segControl({ ...o, labels: ["1 column", "2 columns", "3 columns"] }, c);
      case "doc_language":
        return `<button class="rd-linkrow" data-toast="No OCR languages installed">${ico("languages")}<span class="lbl">Document language<small>Used by OCR · ${E(labels[0] || "")}</small></span><span class="val">${E(c.doc_language || "eng")}</span>${I("chevron-right", "sm")}</button>`;
    }
    if (o.kind === "spin" && vals.length > 3) return numControl(b, o, c);
    if (isOnOff(o)) return switchRow(o, c, vals[1], SUBS[o.name]);
    return segControl(o, c);
  }
  function dirGlyph(i) { // small page diagram showing the reading path
    const paths = ["M5 6h14l-14 6h14l-14 6h14", "M6 5v14l6-14v14l6-14v14", "M5 18h14l-14-6h14l-14-6h14", "M6 19V5l6 14V5l6 14V5",
      "M18 19V5l-6 14V5l-6 14V5", "M19 18H5l14-6H5l14-6H5", "M18 5v14l-6-14v14l-6-14v14", "M19 6H5l14 6H5l14 6H5"];
    return `<svg viewBox="0 0 24 24" class="rd-dirsvg" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><rect x="1.5" y="1.5" width="21" height="21" rx="3" stroke-width="1.2" opacity=".5"/><path d="${paths[i]}"/></svg>`;
  }

  /* ---- extra (non-KO_MENUS) controls, merged into the relevant EPUB tabs ---- */
  function extraText(b, c) {
    const ar = RD.isAr(b);
    const seg = (k, title, icon, opts) => `<div class="rd-opt"><div class="rd-opt-head">${ico(icon)}<span class="lbl">${title}</span></div><div class="ko-seg rd-seg">${opts.map(([v, l, ic]) => `<button class="${c[k] === v ? "on" : ""}" data-action="tsSet" data-k="${k}" data-v="${v}">${ic ? I(ic, "sm") : ""}<span>${l}</span></button>`).join("")}</div></div>`;
    return `<div class="rd-ts-sep">Paragraphs</div>
      ${seg("text_align", "Alignment", "align-justify", [["justify", "Justified", "align-justify"], ["left", "Ragged", ar ? "align-right" : "align-left"]])}
      ${seg("para_indent", "First-line indent", "indent-increase", [["0", "None"], ["1", "1 em"], ["1.2", "1.2 em"], ["2", "2 em"]])}
      ${seg("para_space", "Space between paragraphs", "between-horizontal-start", [["0", "None"], ["0.5", "½ line"], ["1", "1 line"]])}
      <div class="rd-switch"><button class="rd-switch-main" data-action="tsSet" data-k="hyphenation" data-v="${c.hyphenation === "1" ? "0" : "1"}">${ico("scissors")}<span class="lbl">Hyphenation<small>${ar ? "Not used for Arabic" : "English (US) · typography rules"}</small></span>${App.toggle(c.hyphenation === "1")}</button></div>
      ${RD.bilingual(b) ? `<div class="rd-ts-sep">Bilingual edition</div>
      <div class="rd-switch"><button class="rd-switch-main" data-action="tsSet" data-k="tr_inline" data-v="${c.tr_inline === "1" ? "0" : "1"}">${ico("languages")}<span class="lbl">Arabic under each paragraph<small>Otherwise tap ع in the margin</small></span>${App.toggle(c.tr_inline === "1")}</button></div>
      <div class="rd-switch"><button class="rd-switch-main" data-action="tsSet" data-k="tr_marks" data-v="${c.tr_marks === "1" ? "0" : "1"}">${ico("message-square-quote")}<span class="lbl">Translation marks in the margin</span>${App.toggle(c.tr_marks === "1")}</button></div>` : ""}`;
  }
  function extraStyle(c) {
    const sheets = [["none", "None"], ["auto", "Auto"], ["epub", "Traditional book look (epub.css)"], ["html5", "HTML Standard rendering (html5.css)"], ["fb2", "FictionBook (fb2.css)"]];
    return `<div class="rd-ts-sep">Style sheet</div><div class="rd-radios">${sheets.map(([v, l]) => `<button class="rd-radio-row" data-action="tsSet" data-k="style_sheet" data-v="${v}">${App.radio(c.style_sheet === v)}<span>${l}</span></button>`).join("")}</div>
      <button class="rd-linkrow" data-action="rdMenuTypeset">${ico("wand-sparkles")}<span class="lbl">Style tweaks<small>Pages, paragraphs, footnotes, images…</small></span><span class="val">3 active</span>${I("chevron-right", "sm")}</button>`;
  }
  function fontTab(b, c) {
    const f = RD.fontFilter || "all";
    const list = RD.FONTS.filter((x) => f === "all" || x.cat === f);
    const own = c.font_own_face !== "0";
    const cats = [["all", "All"], ["serif", "Serif"], ["sans", "Sans"], ["mono", "Mono"], ["arabic", "Arabic"]];
    return `<div class="rd-fontcats">${cats.map(([k, l]) => `<button class="ko-chip ${f === k ? "on" : ""}" data-action="tsFontCat" data-v="${k}">${l}</button>`).join("")}</div>
      <div class="rd-fonts">${list.map((x) => `<button class="rd-font ${c.font_face === x.name ? "on" : ""}" data-action="tsSet" data-k="font_face" data-v="${E(x.name)}">
        ${App.radio(c.font_face === x.name)}<span class="txt"><span class="nm" style="${own ? `font-family:${E(x.css)}` : ""}">${E(x.name)}</span><small>${E(x.note)}</small></span><span class="smp" style="font-family:${E(x.css)}">${x.cat === "arabic" ? "أبجد" : "Ag"}</span></button>`).join("")}</div>
      <div class="rd-ts-sep">Font settings</div>
      <div class="rd-switch"><button class="rd-switch-main" data-action="tsSet" data-k="font_own_face" data-v="${own ? "0" : "1"}">${ico("type")}<span class="lbl">Display font names with their own font</span>${App.toggle(own)}</button></div>
      <div class="rd-switch"><button class="rd-switch-main" data-action="tsSet" data-k="font_fallback" data-v="${c.font_fallback === "0" ? "1" : "0"}">${ico("layers")}<span class="lbl">Use additional fallback fonts<small>Noto Sans CJK, Noto Naskh Arabic…</small></span>${App.toggle(c.font_fallback !== "0")}</button></div>
      <button class="rd-linkrow" data-toast="Fonts folder: koreader/fonts">${ico("folder-open")}<span class="lbl">Open fonts folder<small>Add .ttf / .otf files</small></span>${I("chevron-right", "sm")}</button>`;
  }
  const PRESETS = {
    Default: () => ({}),
    Comfort: () => ({ font_size: "24", line_spacing: "115", h_page_margins: "30", t_page_margin: "20", b_page_margin: "20", font_face: "Literata" }),
    Compact: () => ({ font_size: "20", line_spacing: "90", h_page_margins: "10", t_page_margin: "10", b_page_margin: "10", font_face: "Source Serif 4", word_spacing: "small" }),
    "Large print": () => ({ font_size: "34", line_spacing: "110", h_page_margins: "15", font_face: "Atkinson Hyperlegible Next", font_base_weight: "0.5", text_align: "left", hyphenation: "0", font_gamma: "25" }),
  };
  RD.PRESETS = PRESETS;
  function presetsTab(b, c) {
    const doc = App.get("rd.doc." + b.id, {});
    const def = RD.defaults("epub");
    const matches = (p) => { const full = { ...def, ...p }; return Object.keys(full).every((k) => String(full[k]) === String(c[k])); };
    const mine = App.get("rd.presets", []);
    const card = (name, p, attrs) => {
      const full = { ...def, ...p }, f = RD.font(full.font_face), on = matches(p);
      return `<button class="ko-card ko-card--tap rd-preset ${on ? "on" : ""}" ${attrs}>
        <span class="pv" style="--pm:${(4 + parseFloat(full.h_page_margins) / 5).toFixed(0)}px">
          <span class="smp" style="font-family:${E(f.css)};font-size:${(parseFloat(full.font_size) * 1.1).toFixed(0)}px;font-weight:${400 + parseFloat(full.font_base_weight || 0) * 100}">Aa</span>
          <span class="lines" style="--g:${((parseFloat(full.line_spacing) / 100) * 4 + parseFloat(full.font_size) / 12).toFixed(1)}px">${"<i></i>".repeat(4)}</span></span>
        <b>${E(name)}</b><small>${E(`${f.name.split(" ")[0]} · ${full.font_size} pt · ${full.line_spacing}%`)}</small>${on ? `<span class="ko-selmark tick">${I("check", "sm")}</span>` : ""}</button>`;
    };
    const n = Object.keys(doc).length;
    return `<div class="rd-presets">${Object.keys(PRESETS).map((k) => card(k, PRESETS[k](), `data-action="tsPreset" data-v="${E(k)}"`)).join("")}
      ${mine.map((p, i) => card(p.name, p.cfg, `data-action="tsMyPreset" data-i="${i}"`)).join("")}</div>
      <div class="rd-ts-actions">
        <button class="ko-btn ko-btn--primary" data-action="tsSaveDefault" ${n ? "" : "disabled"}>${I("save", "sm")}Save as default</button>
        <button class="ko-btn" data-action="tsSavePreset">${I("plus", "sm")}Save as preset</button>
        <button class="ko-btn ko-btn--ghost" data-action="tsReset" ${n ? "" : "disabled"}>${I("rotate-ccw", "sm")}Reset</button>
      </div>
      <p class="rd-ts-foot">${n ? `${n} setting${n > 1 ? "s" : ""} in this book differ from your default. <b>Save as default</b> applies them to every book.` : "This book follows your default settings. Changes you make apply to this book only, until you save them as the default."}</p>`;
  }

  App.overlay("typeset", {
    layer: "sheet", clear: true,
    render(params) {
      const id = params.id || RD.cur().id, b = RD.book(id), c = RD.cfg(id);
      const tabs = RD.tsTabs(b);
      const kind = RD.kind(b), last = App.get("rd.tstab." + kind, kind === "pdf" ? "zoom" : "text");
      const tab = tabs.find((t) => t.key === params.tab) || tabs.find((t) => t.key === last) || tabs[0];
      let body;
      if (tab.key === "presets") body = presetsTab(b, c);
      else if (tab.key === "font") body = fontTab(b, c);
      else {
        body = tab.opts.map((o) => optionHTML(b, o, c)).join("");
        if (tab.key === "text") body = `<button class="rd-fontrow" data-action="tsTab" data-v="font">${ico("type")}<span class="faint">Font</span><span class="nm" style="font-family:${E(RD.font(c.font_face).css)}">${E(c.font_face)}</span>${I("chevron-right", "sm")}</button>` + body + extraText(b, c);
        if (tab.key === "style") body += extraStyle(c);
        if (tab.key === "margins" || tab.key === "crop") body = marginDiagram(b, c) + body;
        if (RD.isPdf(b) && c.text_wrap !== "1" && tab.key === "reflow") body = `<div class="rd-note">${I("info", "sm")}<span>Font size, word gap, line spacing and alignment take effect when <b>Reflow</b> is on.</span></div>` + body;
      }
      if (tab.key !== "presets") body = `<div class="rd-card">${body.replace(/<div class="rd-ts-sep">(.*?)<\/div>/g, '</div><div class="rd-ts-sep">$1</div><div class="rd-card">')}</div>`;
      const n = Object.keys(App.get("rd.doc." + id, {})).length;
      return `<div class="ko-sheet rd-ts ${RD.isPdf(b) ? "pdf" : ""}" data-tab="${tab.key}">
        <div class="grip"></div>
        <div class="ko-sheet-head rd-ts-head">
          <div class="grow"><div class="title">${E(tab.key === "text" ? "Text & spacing" : tab.label)}</div><div class="sub">${RD.isPdf(b) ? "PDF · fixed layout" : "EPUB · reflowable"}<span class="dot">·</span>${n ? `${n} custom for this book` : "using your defaults"}</div></div>
          <button class="ko-icon-btn" data-close aria-label="Close">${I("x")}</button>
        </div>
        <div class="ko-scroll rd-ts-body">${body}</div>
        <nav class="rd-ts-tabs" style="--n:${tabs.length}">${tabs.map((t) => `<button class="${t.key === tab.key ? "on" : ""}" data-action="tsTab" data-v="${t.key}">${t.key === "text" ? `<span class="rd-aa">Aa</span>` : I(t.icon)}<span>${E(t.label)}</span></button>`).join("")}</nav>
      </div>`;
    },
  });
  RD.mdiaVars = (c) => { const s = 0.14; return `--l:${((10 + c.h_page_margins * 1.2) * s).toFixed(1)}px;--t:${((6 + c.t_page_margin * 0.8) * s + 2).toFixed(1)}px;--b:${((6 + c.b_page_margin * 0.8) * s + 2).toFixed(1)}px`; };
  function marginDiagram(b, c) {
    if (RD.isPdf(b)) {
      const crop = c.trim_page !== "3";
      return `<div class="rd-mdia pdf"><div class="pg ${crop ? "crop" : ""}" style="--m:${(parseFloat(c.page_margin) * 12).toFixed(1)}px"><div class="txt">${"<i></i>".repeat(10)}</div></div></div>`;
    }
    return `<div class="rd-mdia"><div class="pg" id="rd-mdia" style="${RD.mdiaVars(c)}"><div class="txt">${"<i></i>".repeat(8)}</div></div></div>`;
  }
  const findOpt = (b, k) => { for (const g of RD.cfgGroups(RD.isPdf(b))) for (const o of g.options) if (o.name === k) return o; return null; };
  const tsId = () => (App.top() && App.top().params && App.top().params.id) || RD.cur().id;
  App.action("tsTab", (el) => { const t = App.top(); App.set("rd.tstab." + RD.kind(RD.book(tsId())), el.dataset.v); RD.quiet(() => App.replaceTop("typeset", { ...t.params, tab: el.dataset.v })); });
  App.action("tsHelp", (el) => { RD.helpOpen = RD.helpOpen === el.dataset.k ? null : el.dataset.k; RD.quiet(() => App.renderLayers(true)); });
  App.action("tsFontCat", (el) => { RD.fontFilter = el.dataset.v; RD.quiet(() => App.renderLayers(true)); });
  App.action("tsSet", (el) => {
    const id = tsId(); let { k, v } = el.dataset;
    if (k === "visible_pages") { const { w, h } = RD.screenSize(); v = (v === "2") === w > h ? "auto" : v; }
    RD.setCfg(id, k, v);
  });
  App.action("tsStep", (el) => {
    const id = tsId(), b = RD.book(id), c = RD.cfg(id), k = el.dataset.id || el.dataset.k, d = +(el.dataset.dir || el.dataset.d), o = findOpt(b, k);
    const vals = RD.optValues(o), nums = vals.map(parseFloat), cur = parseFloat(c[k]);
    let nv;
    if (k === "font_size") { const fine = RD.isPdf(b) ? 0.05 : 0.5; nv = String(+clamp(cur + d * fine, Math.min(...nums), Math.max(...nums)).toFixed(2)); }
    else {
      let i = vals.indexOf(String(c[k]));
      if (i < 0) { i = nums.findIndex((x) => x > cur); if (i < 0) i = nums.length; if (d > 0) i--; }
      nv = vals[clamp(i + d, 0, vals.length - 1)];
    }
    RD.setCfg(id, k, nv);
  });
  App.action("tsSlide", (el, v, done) => {
    const id = tsId(), b = RD.book(id), k = el.dataset.id || el.dataset.k, o = findOpt(b, k);
    const vals = RD.optValues(o), labels = RD.optLabels(o), i = Math.round(v * (vals.length - 1));
    const row = el.closest(".ko-sr"), out = row && row.querySelector(".val");
    if (out) { const u = out.querySelector("small"); out.textContent = labels[i]; if (u) out.appendChild(u); }
    const scr = document.querySelector(".rd-screen");
    if (scr && !done) scr.setAttribute("style", RD.style(b, { ...RD.cfg(id), [k]: vals[i] })); // instant preview, re-paginated on release
    const md = document.getElementById("rd-mdia"); if (md && !done) md.setAttribute("style", RD.mdiaVars({ ...RD.cfg(id), [k]: vals[i] }));
    if (done) { el.style.setProperty("--v", (i / (vals.length - 1)) * 100 + "%"); RD.setCfg(id, k, vals[i]); }
  });
  App.action("tsPreset", (el) => { RD.applyCfg(tsId(), PRESETS[el.dataset.v]()); App.toast(`${el.dataset.v} applied`); });
  App.action("tsMyPreset", (el) => { const p = App.get("rd.presets", [])[+el.dataset.i]; RD.applyCfg(tsId(), p.cfg); App.toast(`${p.name} applied`); });
  App.action("tsSaveDefault", () => { const id = tsId(), k = RD.kind(RD.book(id)); App.set("rd.def." + k, { ...App.get("rd.def." + k, {}), ...App.get("rd.doc." + id, {}) }); App.set("rd.doc." + id, {}); RD.quietRefresh(); App.toast("Saved as default for all books"); });
  App.action("tsSavePreset", () => { const id = tsId(); const mine = App.get("rd.presets", []); mine.push({ name: `My preset ${mine.length + 1}`, cfg: { ...App.get("rd.doc." + id, {}) } }); App.set("rd.presets", mine); RD.quiet(() => App.renderLayers(true)); App.toast("Preset saved"); });
  App.action("tsReset", () => { RD.applyCfg(tsId(), {}); App.toast("Book reset to your defaults"); });
  App.action("rdMenuTypeset", () => { const { id } = RD.cur(); App.replaceTop("main-menu", { ctx: "reader", tab: "typeset", id, format: RD.book(id).format }); });

  /* ------------------------------------------------------------- demos */
  const D = (label, hash) => App.demo("Reader", label, hash);
  D("Reading page", "#/reader?id=animal-farm");
  D("Chapter start (drop cap)", "#/reader?id=animal-farm&ch=1");
  D("Arabic poetry (RTL)", "#/reader?id=ar-poems");
  D("Arabic prose (RTL)", "#/reader?id=ar-ayam&ch=0");
  D("Bilingual · Arabic under each paragraph", "#/reader?id=animal-farm&inline=1");
  D("Reader chrome", "#/reader?id=animal-farm&o=reader-chrome");
  ["presets", "text", "font", "margins", "page", "layout", "contrast", "style"].forEach((t) => D(`Typeset · ${t[0].toUpperCase() + t.slice(1)}`, `#/reader?id=animal-farm&o=typeset&o.tab=${t}`));
  D("PDF · scanned page", "#/reader?id=pride&page=3");
  D("PDF · chrome", "#/reader?id=pride&page=3&o=reader-chrome");
  ["rotate", "crop", "zoom", "page", "reflow", "contrast", "doc"].forEach((t) => D(`PDF typeset · ${t[0].toUpperCase() + t.slice(1)}`, `#/reader?id=pride&page=3&o=typeset&o.tab=${t}`));
})();
