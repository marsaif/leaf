/* ==========================================================================
   Folio core — tiny router + overlay stack + helpers shared by every screen.

   Screens:   App.screen("library", { title, group, render(params) => html })
   Overlays:  App.overlay("plus",   { title, group, render(params) => html, layer: "popover"|"sheet"|"dialog"|"page" })
   Actions:   App.action("name", (el, ev) => {...})   then  <button data-action="name" data-arg="x">
   Built-in data attributes (click delegation):
     data-go="screen" [data-params='{"k":"v"}']   -> navigate
     data-open="overlay" [data-params='{...}']    -> push overlay
     data-close                                   -> pop top overlay
     data-toast="text"                            -> transient message
   Every state is addressable by URL hash so it can be screenshotted:
     #/library?tab=history            screen + params
     #/reader?o=typeset&o.tab=font     + top overlay and its params
   ========================================================================== */
(function () {
  const App = (window.App = {
    screens: {}, overlays: {}, actions: {}, demos: [],
    state: { stack: [] }, // overlay stack: [{name, params}]
    current: { name: "home", params: {} },
    store: JSON.parse(localStorage.getItem("folio.store") || "{}"), // persisted UI prefs
  });

  /* ---------- registry ---------- */
  App.screen = (name, def) => { App.screens[name] = def; };
  App.overlay = (name, def) => { App.overlays[name] = def; };
  App.action = (name, fn) => { App.actions[name] = fn; };
  /** add an entry in the designer's state navigator (left panel) */
  App.demo = (group, label, hash) => { App.demos.push({ group, label, hash }); };

  App.save = () => localStorage.setItem("folio.store", JSON.stringify(App.store));
  App.get = (k, d) => (k in App.store ? App.store[k] : d);
  App.set = (k, v) => { App.store[k] = v; App.save(); };

  /* ---------- helpers ---------- */
  App.esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  App.icon = (name, cls = "") => `<i data-lucide="${name}" class="ko-i ${cls}"></i>`;
  App.attrs = (o) => App.esc(JSON.stringify(o || {}));
  App.toggle = (on) => `<span class="ko-toggle ${on ? "on" : ""}"></span>`;
  App.radio = (on) => `<span class="ko-radio ${on ? "on" : ""}"></span>`;
  App.check = (on) => `<span class="ko-check ${on ? "on" : ""}">${on ? App.icon("check", "sm") : ""}</span>`;
  App.progress = (pct, cls = "") => `<div class="ko-progress ${cls}"><i style="width:${Math.max(0, Math.min(100, pct))}%"></i></div>`;
  App.slider = (pct, attrs = "") => `<div class="ko-slider" style="--v:${pct}%" ${attrs}><span class="track"></span><span class="fill"></span><span class="thumb"></span></div>`;
  /* App.sliderRow (the ONE slider-setting row) lives in js/ui.js as UI.sliderRow; App.sliderRow stays as an alias. */
  App.statusBar = (opts = {}) => {
    const t = new Date(); const hh = String(t.getHours()).padStart(2, "0"), mm = String(t.getMinutes()).padStart(2, "0");
    return `<div class="ko-status"><span></span><span class="right">${App.icon("wifi", "sm")}<span>${hh}:${mm}</span>${App.icon("battery-full", "sm")}<span>87%</span></span></div>`;
  };
  /** the app's bottom navigation; `on` = home|library|history|settings */
  App.bottomNav = (on) => {
    const items = [["home", "house", "Home"], ["library", "library-big", "Library"], ["history", "history", "History"], ["settings", "settings", "Settings"]];
    return `<nav class="ko-nav">${items.map(([k, ic, l]) => `<button class="${on === k ? "on" : ""}" data-go="${k}">${App.icon(ic)}<span>${l}</span></button>`).join("")}</nav>`;
  };

  /* ---------- navigation ---------- */
  App.go = (name, params = {}) => { App.state.stack = []; App.current = { name, params }; App.render(); App.syncHash(); };
  App.open = (name, params = {}) => { App.state.stack.push({ name, params }); App.renderLayers(); App.syncHash(); };
  App.replaceTop = (name, params = {}) => { App.state.stack.pop(); App.open(name, params); };
  App.close = () => { App.state.stack.pop(); App.renderLayers(); App.syncHash(); };
  App.closeAll = () => { App.state.stack = []; App.renderLayers(); App.syncHash(); };
  /** re-render (keeps scroll positions) */
  App.refresh = () => { App.render(true); };
  App.top = () => App.state.stack[App.state.stack.length - 1];

  App.syncHash = () => {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries(App.current.params || {})) q.set(k, typeof v === "object" ? JSON.stringify(v) : v);
    const top = App.top();
    if (top) {
      q.set("o", top.name);
      for (const [k, v] of Object.entries(top.params || {})) q.set("o." + k, typeof v === "object" ? JSON.stringify(v) : v);
    }
    const h = `#/${App.current.name}${[...q].length ? "?" + q.toString() : ""}`;
    if (location.hash !== h) history.replaceState(null, "", h);
    document.dispatchEvent(new CustomEvent("folio:navigate"));
  };
  const parseVal = (v) => { try { return JSON.parse(v); } catch { return v; } };
  App.fromHash = () => {
    const m = location.hash.match(/^#\/([\w-]+)(?:\?(.*))?$/);
    if (!m) return false;
    const params = {}, oparams = {}; let o = null;
    for (const [k, v] of new URLSearchParams(m[2] || "")) {
      if (k === "o") o = v; else if (k.startsWith("o.")) oparams[k.slice(2)] = parseVal(v); else params[k] = parseVal(v);
    }
    App.current = { name: App.screens[m[1]] ? m[1] : "home", params };
    App.state.stack = o && App.overlays[o] ? [{ name: o, params: oparams }] : [];
    return true;
  };

  /* ---------- rendering ---------- */
  let root, layers;
  const keepScroll = (el, fn) => {
    const pos = [...el.querySelectorAll(".ko-scroll")].map((s) => s.scrollTop);
    fn();
    [...el.querySelectorAll(".ko-scroll")].forEach((s, i) => { if (pos[i]) s.scrollTop = pos[i]; });
  };
  App.render = (keep) => {
    const def = App.screens[App.current.name];
    const draw = () => { root.innerHTML = def ? def.render(App.current.params || {}) : `<div class="ko-empty">Unknown screen</div>`; def?.mount?.(root, App.current.params || {}); };
    keep ? keepScroll(root, draw) : draw();
    App.renderLayers(keep);
    App.icons();
    App.hitAreas(root);
  };
  let prevNames = []; // overlays already on screen keep still on re-render (no replayed open animation)
  App.renderLayers = (keep) => {
    const draw = () => {
      const was = prevNames; prevNames = App.state.stack.map((o) => o.name);
      layers.innerHTML = App.state.stack.map((o, i) => {
        const def = App.overlays[o.name];
        if (!def) return "";
        const kind = (def.layer || "popover") + (was[i] === o.name ? " ko-still" : "");
        const scrim = kind === "page" ? "" : `<div class="ko-scrim ${def.clear ? "clear" : ""}" data-close></div>`;
        return `<div class="ko-layer layer-${kind}" data-depth="${i}">${scrim}${def.render(o.params || {})}</div>`;
      }).join("");
      App.state.stack.forEach((o, i) => App.overlays[o.name]?.mount?.(layers.querySelector(`[data-depth="${i}"]`), o.params || {}));
    };
    keep ? keepScroll(layers, draw) : draw();
    App.icons();
    App.hitAreas(layers);
  };
  App.icons = () => { if (window.lucide) lucide.createIcons({ attrs: { "stroke-width": 1.6 } }); };
  /** every control gets a >= --touch (44px) hit area: small ones get .ko-hit (an invisible ::before expander);
      clipping (overflow) or busy ::before ones get extra transparent padding instead */
  const HIT = 'button, a[href], [data-action], [data-go], [data-open], [data-close]:not(.ko-scrim), [role="button"], [data-slide]';
  App.hitAreas = (scope) => {
    if (!scope) return;
    const min = 44;
    scope.querySelectorAll(HIT).forEach((el) => {
      if (el.classList.contains("ko-hit") || el.dataset.hitDone) return;
      const r = el.getBoundingClientRect();
      if (!r.width || !r.height || (r.width >= min && r.height >= min)) return;
      const cs = getComputedStyle(el);
      if (cs.display === "inline" || el.closest(".rd-text")) return;   // words inside the book page
      const before = getComputedStyle(el, "::before").content;
      const clips = cs.overflowX !== "visible" || cs.overflowY !== "visible";
      const plain = (cs.backgroundColor === "rgba(0, 0, 0, 0)" || cs.backgroundColor === "transparent") && parseFloat(cs.borderTopWidth) === 0 && cs.boxShadow === "none";
      if (!clips && (before === "none" || before === "normal")) {
        el.classList.add("ko-hit");
        if (cs.position === "static") el.style.position = "relative";
      } else if (plain) {  // grow the (invisible) box itself with padding, cancel it with negative margins
        const dy = Math.max(0, (min - r.height) / 2), dx = Math.max(0, (min - r.width) / 2);
        if (dy) { el.style.height = `${r.height + 2 * dy}px`; el.style.paddingTop = `calc(${cs.paddingTop} + ${dy}px)`; el.style.paddingBottom = `calc(${cs.paddingBottom} + ${dy}px)`; el.style.marginTop = `calc(${cs.marginTop} - ${dy}px)`; el.style.marginBottom = `calc(${cs.marginBottom} - ${dy}px)`; }
        if (dx) { el.style.width = `${r.width + 2 * dx}px`; el.style.paddingLeft = `calc(${cs.paddingLeft} + ${dx}px)`; el.style.paddingRight = `calc(${cs.paddingRight} + ${dx}px)`; el.style.marginLeft = `calc(${cs.marginLeft} - ${dx}px)`; el.style.marginRight = `calc(${cs.marginRight} - ${dx}px)`; }
      }
      el.dataset.hitDone = "1";
    });
  };

  App.toast = (text) => {
    const screen = document.querySelector(".ko-screen");
    const t = document.createElement("div"); t.className = "ko-toast"; t.textContent = text;
    screen.appendChild(t); setTimeout(() => t.remove(), 1600);
  };

  /* ---------- click delegation ---------- */
  const params = (el) => { try { return JSON.parse(el.dataset.params || "{}"); } catch { return {}; } };
  document.addEventListener("click", (ev) => {
    const el = ev.target.closest("[data-action],[data-go],[data-open],[data-close],[data-toast]");
    if (!el || !el.closest(".ko-screen")) return;
    if (el.dataset.stop !== undefined) ev.stopPropagation();
    if (el.dataset.close !== undefined) App.close();
    if (el.dataset.go) App.go(el.dataset.go, params(el));
    if (el.dataset.open) App.open(el.dataset.open, params(el));
    if (el.dataset.toast) App.toast(el.dataset.toast);
    if (el.dataset.action) {
      const fn = App.actions[el.dataset.action];
      if (fn) fn(el, ev); else console.warn("no action", el.dataset.action);
    }
  });
  /* sliders: drag/click sets --v and fires data-slide action with value 0..1 */
  document.addEventListener("pointerdown", (ev) => {
    const s = ev.target.closest(".ko-slider"); if (!s) return;
    const move = (e) => {
      const r = s.getBoundingClientRect(); const v = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
      s.style.setProperty("--v", v * 100 + "%");
      if (s.dataset.slide && App.actions[s.dataset.slide]) App.actions[s.dataset.slide](s, v, e.type === "pointerup");
    };
    move(ev);
    const up = (e) => { move(e); window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
    window.addEventListener("pointermove", move); window.addEventListener("pointerup", up);
  });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && App.state.stack.length) App.close(); });

  /* ---------- boot ---------- */
  App.boot = () => {
    root = document.getElementById("screen-root");
    layers = document.getElementById("layer-root");
    if (!App.fromHash()) App.current = { name: "home", params: {} };
    App.render();
    window.addEventListener("hashchange", () => { if (App.fromHash()) App.render(); });
  };
})();
