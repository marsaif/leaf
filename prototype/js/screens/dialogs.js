/* ==========================================================================
   Tools · dialogs and system sheets
     input      ({title, hint, value, ok, action, checkbox, checked, layout, desc, cancel})
     confirm    ({title, body, ok, danger, icon, id, checkbox, action})
     info       ({title, body, list, ok, toast})  toast:true|"text" -> shown as App.toast instead
     frontlight (sheet)   quick (sheet)   wifi ({connect})   sleep ({preview})   about
   OK buttons call App.actions[params.action](el, value, {value, checked, params}) when given
   (value is the typed string for input, true for confirm); the dialog closes itself afterwards if still open.
   ========================================================================== */
(function () {
  const esc = App.esc;
  const H = App.toolsHash || ((s, p = {}) => `#/${s}${Object.keys(p).length ? "?" + new URLSearchParams(p) : ""}`);
  const G = "Dialogs";
  const topParams = () => App.top()?.params || {};
  /** call params.action as fn(el, value, {checked, params}); el.dataset.value/checked carry the same data.
      The dialog stays open while the action runs and is closed afterwards if it is still on top. */
  const runAction = (el, p, value, checked, name) => {
    const fn = p.action && App.actions[p.action];
    el.dataset.value = value === true ? "true" : String(value ?? "");
    el.dataset.checked = checked ? "true" : "false";
    if (fn) fn(el, value, { value, checked, params: p });
    if (App.top()?.name === name && App.top()?.params === p) App.close();
    return !!fn;
  };

  /* ---------------- input ---------------- */
  App.overlay("input", {
    title: "Input", layer: "dialog",
    render(p) {
      App.kbInit("input", p.value ?? "", p);
      const v = App.kbValue("input");
      const layout = p.layout || "qwerty";
      return UI.dialog({
        cls: UI.cls("dl-input", !v.trim() && "is-empty"), title: p.title || "Input", body: p.text,
        bodyHtml: App.kbField("input", { placeholder: p.hint || "", cls: "kb-field--compact" + (layout === "numeric" ? " num" : "") })
          + (p.desc ? `<div class="kb-field-help">${esc(p.desc)}</div>` : "")
          + (p.checkbox ? UI.checkRow({ label: p.checkbox, on: !!p.checked, attrs: { action: "dl-check" } }) : ""),
        actions: [{ label: p.cancel || "Cancel", kind: "ghost", attrs: "data-close" }, { label: p.ok || "OK", kind: "primary", attrs: 'data-action="dl-ok" data-kb-submit="input"' }],
      }) + `
      <div class="dl-kbdock">${App.keyboardHTML({ layout, target: "input", enter: "Done" })}</div>`;
    },
  });
  App.kbOn("input", { change(v) { document.querySelector(".dl-input")?.classList.toggle("is-empty", !v.trim()); } });
  App.action("dl-check", (el) => {
    const p = topParams(); p.checked = !p.checked;
    el.querySelector(".ko-check").outerHTML = App.check(p.checked); App.icons();
  });
  App.action("dl-ok", (el) => {
    const p = topParams(), v = App.kbValue("input").trim();
    if (!v && !p.allowEmpty && !p.action) {
      const f = document.querySelector(".dl-input .kb-field"); f?.classList.remove("shake"); void f?.offsetWidth; f?.classList.add("shake");
      return;
    }
    if (!runAction(el, p, v, !!p.checked, "input")) App.toast(`${p.ok || "OK"} · ${v}`);
  });

  /* ---------------- confirm ---------------- */
  App.overlay("confirm", {
    title: "Confirm", layer: "dialog",
    render(p) {
      const danger = p.danger === true || p.danger === "true" || p.danger === 1;
      const icon = p.icon || (danger ? "trash-2" : "");
      const b = p.id ? DB.book(p.id) : null;
      return UI.dialog({
        cls: "dl-confirm", title: p.title || "Are you sure?", icon: danger && icon ? icon : "", danger, body: p.body,
        bodyHtml: (b ? `<div class="ko-card ko-card--sunken ko-card--sm dl-item"><div class="dl-item-c">${Cover.html(b)}</div><div class="grow"><div class="ellipsis dl-item-t">${esc(b.title)}</div><div class="dl-item-s">${esc(b.author.split(";")[0])}</div><div class="dl-item-s">${b.format.toUpperCase()} · ${b.size} · 6 highlights</div></div></div>` : "")
          + (p.checkbox ? UI.checkRow({ label: p.checkbox, on: !!p.checked, attrs: { action: "dl-check" } }) : ""),
        actions: [{ label: p.cancel || "Cancel", kind: "ghost", attrs: "data-close" }, { label: p.ok || "OK", kind: danger ? "danger" : "primary", attrs: { action: "dl-confirm" } }],
      });
    },
  });
  App.action("dl-confirm", (el) => {
    const p = topParams();
    if (!runAction(el, p, true, !!p.checked, "confirm")) App.toast(`${p.ok || "Done"}`);
  });

  /* ---------------- info ---------------- */
  App.overlay("info", {
    title: "Info", layer: "dialog",
    // {toast:true|"text"}: the message is a result of something that already happened -> show a toast instead
    mount(el, p) {
      if (!p.toast) return;
      const text = typeof p.toast === "string" ? p.toast : p.title || p.body || "Done";
      setTimeout(() => { if (App.top()?.params === p) App.close(); App.toast(text); }, 0);
    },
    render(p) {
      if (p.toast) return "";
      const list = Array.isArray(p.list) ? p.list : null;
      return UI.dialog({
        cls: "dl-info", title: p.title || "Information", body: p.body, bodyHtml: list ? UI.kv(list, { cls: "dl-list" }) : "",
        actions: [{ label: p.ok || "OK", kind: "primary", attrs: "data-close" }],
      });
    },
  });

  /* ---------------- frontlight ---------------- */
  const FL = () => ({ on: App.get("fl.on", true), b: App.get("fl.b", 62), w: App.get("fl.w", 35), night: App.get("fl.night", false), auto: App.get("fl.auto", true) });
  const lightSliders = (s) => `<div class="fl-sliders ${s.on ? "" : "off"}">
    ${App.sliderRow({ label: "Brightness", pct: s.b, value: s.b, unit: "%", slide: "fl-b", step: "fl-step", id: "fl-b", minIcon: "sun-dim", maxIcon: "sun" })}
    ${App.sliderRow({ label: "Warmth", pct: s.w, value: s.w, unit: "%", slide: "fl-w", step: "fl-step", id: "fl-w", minIcon: "snowflake", maxIcon: "flame" })}
  </div>`;
  App.overlay("frontlight", {
    title: "Frontlight", layer: "sheet",
    render() {
      const s = FL();
      return `<div class="ko-sheet ko-sheet--phone fl">
        <div class="grip"></div>
        ${UI.sheetHead({ title: "Frontlight", sub: s.on ? `${s.b}% brightness · ${s.w}% warmth` : "Off" })}
        <div class="ko-list fl-rows fl-top"><button class="ko-row" data-action="fl-power">${App.icon("lightbulb")}<span class="label">Frontlight</span>${App.toggle(s.on)}</button></div>
        ${lightSliders(s)}
        <div class="ko-list fl-rows">
          <button class="ko-row" data-action="fl-flag" data-arg="night">${App.icon("contrast")}<span class="label">Night mode</span>${App.toggle(s.night)}</button>
          <button class="ko-row" data-action="fl-flag" data-arg="auto">${App.icon("sunset")}<span class="label">Automatic warmth<span class="sub">${s.auto ? "Warmer from sunset to sunrise" : "Off"}</span></span>${App.toggle(s.auto)}</button>
          <button class="ko-row" data-close data-go="settings" data-params='${App.attrs({ section: "frontlight" })}'>${App.icon("settings-2")}<span class="label">Frontlight settings</span>${App.icon("chevron-right", "sm chev")}</button>
        </div>
      </div>`;
    },
  });
  const clamp = (v) => Math.max(0, Math.min(100, Math.round(v)));
  function setLight(k, v, live) {
    v = clamp(v); App.set("fl." + k, v);
    document.querySelectorAll(`.ko-sr[data-id="fl-${k}"] .val`).forEach((e) => (e.innerHTML = `${v}<small>%</small>`));
    document.querySelectorAll(`[data-slide="fl-${k}"]`).forEach((s) => s.style.setProperty("--v", v + "%"));
    if (!live) App.renderLayers(true);
  }
  App.action("fl-b", (s, v, done) => setLight("b", v * 100, !done));
  App.action("fl-w", (s, v, done) => setLight("w", v * 100, !done));
  App.action("fl-step", (el) => { const k = el.dataset.id.slice(3); setLight(k, App.get("fl." + k, k === "b" ? 62 : 35) + Number(el.dataset.dir)); });
  App.action("fl-power", () => { App.set("fl.on", !App.get("fl.on", true)); App.renderLayers(true); });
  App.action("fl-flag", (el) => { const k = "fl." + el.dataset.arg; App.set(k, !App.get(k, el.dataset.arg === "auto")); App.renderLayers(true); });

  /* ---------------- quick settings ---------------- */
  const QK = [
    ["wifi", "wifi", "Wi-Fi", true, (on) => (on ? App.get("wifi.net", "Home-5G") : "Off"), "wifi"],
    ["light", "sun", "Frontlight", true, (on) => (on ? "On" : "Off")],
    ["night", "contrast", "Night mode", false, (on) => (on ? "On" : "Off")],
    ["rotate", "lock-keyhole", "Rotation lock", true, (on) => (on ? "Portrait" : "Auto")],
    ["plane", "plane", "Airplane", false, (on) => (on ? "On" : "Off")],
    ["sync", "refresh-cw", "Sync", true, () => "2 min ago"],
    ["shot", "camera", "Screenshot", null, () => "Capture"],
    ["sleep", "moon", "Sleep", null, () => "Now"],
  ];
  const qkOn = (k, d) => (k === "light" ? App.get("fl.on", true) : k === "night" ? App.get("fl.night", false) : App.get("qk." + k, d));
  App.overlay("quick", {
    title: "Quick settings", layer: "sheet",
    render() {
      const s = FL();
      return `<div class="ko-sheet ko-sheet--phone qk">
        <div class="grip"></div>
        ${UI.sheetHead({ title: "Quick settings", sub: "Thursday, 19 November", cls: "qk-top",
          extra: `<div class="qk-meta">${App.icon("battery-full", "sm")}87% · about 3 weeks left${App.get("qk.wifi", true) ? ` · ${App.icon("wifi", "sm")}${esc(App.get("wifi.net", "Home-5G"))}` : ""}</div>`,
          actions: UI.iconButton({ icon: "settings", label: "All settings", attrs: 'data-close data-go="settings"' }) })}
        <div class="qk-tiles">${QK.map(([k, ic, label, def, sub, more]) => {
          const on = def === null ? false : qkOn(k, def);
          return `<div class="ko-card ko-card--flush qk-tile ${on ? "on" : ""} ${def === null ? "act" : ""}">
            <button class="qk-main" data-action="qk" data-arg="${k}"><span class="qk-ico">${App.icon(ic)}</span><span class="qk-l">${label}</span><span class="qk-s ellipsis">${esc(sub(on))}</span></button>
            ${more ? `<button class="qk-more" data-action="qk-more" data-arg="${more}" aria-label="${label} settings">${App.icon("chevron-right", "sm")}</button>` : ""}
          </div>`;
        }).join("")}</div>
        <div class="qk-sliders">${lightSliders(s)}</div>
      </div>`;
    },
  });
  App.action("qk", (el) => {
    const k = el.dataset.arg;
    if (k === "shot") { App.close(); setTimeout(() => App.toast("Screenshot saved to /screenshots"), 50); return; }
    if (k === "sleep") return App.replaceTop("sleep", { preview: App.get("sleep.kind", "cover") });
    if (k === "sync") return App.toast("Progress synced with KOSync");
    if (k === "light") App.set("fl.on", !App.get("fl.on", true));
    else if (k === "night") App.set("fl.night", !App.get("fl.night", false));
    else {
      const def = QK.find((q) => q[0] === k)[3];
      App.set("qk." + k, !App.get("qk." + k, def));
      if (k === "plane" && App.get("qk.plane")) App.set("qk.wifi", false);
    }
    App.renderLayers(true);
  });
  App.action("qk-more", (el) => App.replaceTop(el.dataset.arg, {}));

  /* ---------------- wifi ---------------- */
  const NETS = [
    { name: "Home-5G", sig: 4, lock: true, sec: "WPA2", saved: true, band: "5 GHz" },
    { name: "Home-2.4G", sig: 3, lock: true, sec: "WPA2", saved: true, band: "2.4 GHz" },
    { name: "Café Lumière", sig: 3, lock: true, sec: "WPA2", band: "2.4 GHz" },
    { name: "Bibliothèque publique", sig: 2, lock: false, sec: "Open", band: "2.4 GHz" },
    { name: "Vodafone-7F21", sig: 2, lock: true, sec: "WPA3", band: "5 GHz" },
    { name: "DIRECT-HP OfficeJet", sig: 1, lock: true, sec: "WPA2", band: "2.4 GHz" },
    { name: "eduroam", sig: 1, lock: true, sec: "WPA2-Enterprise", band: "5 GHz" },
  ];
  const sigIcon = (s) => ["wifi-zero", "wifi-low", "wifi-high", "wifi", "wifi"][s];
  const sigText = (s) => ["No signal", "Weak", "Fair", "Good", "Excellent"][s];
  App.overlay("wifi", {
    title: "Wi-Fi", layer: "sheet",
    render(p) {
      if (p.connect) return wifiConnect(p);
      const on = App.get("qk.wifi", true);
      const cur = App.get("wifi.net", "Home-5G");
      const c = NETS.find((n) => n.name === cur) || NETS[0];
      const scanning = App.state.wifiScan;
      const rows = NETS.filter((n) => n.name !== cur).map((n) => `
        <button class="ko-row wf-row" data-action="wf-pick" data-arg="${esc(n.name)}">
          <span class="ko-icon-tile ko-icon-tile--lg ko-icon-tile--plain wf-sig s${n.sig}">${App.icon(sigIcon(n.sig))}</span>
          <span class="label"><span class="ellipsis wf-name">${esc(n.name)}</span><span class="sub">${n.saved ? "Saved · " : ""}${n.sec} · ${sigText(n.sig)}</span></span>
          ${n.lock ? App.icon("lock", "sm wf-lock") : App.icon("lock-open", "sm wf-lock faint")}
        </button>`).join("");
      return `<div class="ko-sheet ko-sheet--phone wf">
        <div class="grip"></div>
        ${UI.sheetHead({ title: "Wi-Fi", sub: on ? App.get("wifi.net", "Home-5G") : "Off",
          actions: on ? UI.iconButton({ icon: "refresh-cw", iconCls: scanning ? "ko-spin" : "", label: scanning ? "Scanning…" : "Scan", attrs: { action: "wf-scan" }, cls: "wf-scan" }) : "" })}
        <div class="ko-list fl-rows wf-top"><button class="ko-row" data-action="wf-power">${App.icon("wifi")}<span class="label">Wi-Fi</span>${App.toggle(on)}</button></div>
        <div class="ko-scroll wf-body">
        ${on ? `
          <div class="wf-cur">
            <span class="wf-cur-i">${App.icon("wifi")}</span>
            <div class="grow"><div class="wf-cur-n">${esc(c.name)}</div><div class="wf-cur-s">${App.icon("check", "sm")}Connected · ${c.band} · 192.168.1.42</div></div>
          </div>
          <div class="wf-cur-a"><button class="ko-btn ko-btn--sm" data-action="wf-disconnect">Disconnect</button><button class="ko-btn ko-btn--sm" data-open="info" data-params='${App.attrs({ title: c.name, icon: "wifi", list: [["Status", "Connected"], ["Signal", sigText(c.sig)], ["Frequency", c.band], ["Security", c.sec], ["IP address", "192.168.1.42"], ["Gateway", "192.168.1.1"], ["MAC", "a4:5e:60:c2:19:0b"]] })}'>Details</button><button class="ko-btn ko-btn--ghost ko-btn--sm" data-toast="Forgot ${esc(c.name)}">Forget</button></div>
          <div class="ko-section-label">Available networks</div>
          <div class="ko-list wf-list">${rows}</div>
          <button class="ko-row wf-add" data-open="input" data-params='${App.attrs({ title: "Add network", hint: "Network name (SSID)", ok: "Next" })}'><span class="ko-icon-tile ko-icon-tile--lg ko-icon-tile--plain wf-sig">${App.icon("plus")}</span><span class="label">Add network manually</span></button>
          <div class="wf-foot">${App.icon("info", "sm")}Wi-Fi turns off automatically after 5 minutes without network activity.</div>`
        : `<div class="ko-empty wf-off">${App.icon("wifi-off")}<div>Wi-Fi is off</div><div class="faint">Turn it on to sync progress, download books and look up words online.</div><button class="ko-btn ko-btn--primary" data-action="wf-power">Turn on Wi-Fi</button></div>`}
        </div>
      </div>`;
    },
  });
  function wifiConnect(p) {
    const n = NETS.find((x) => x.name === p.connect) || { name: p.connect, sig: 2, sec: "WPA2", band: "2.4 GHz" };
    App.kbInit("wifi-pw", "", p);
    if (p.checked === undefined) p.checked = true;
    const show = !!p.show;
    return UI.dialog({
      cls: "dl-input dl-wifi", title: n.name, icon: sigIcon(n.sig), sub: `${n.sec} · ${sigText(n.sig)} signal · ${n.band}`,
      bodyHtml: App.kbField("wifi-pw", { placeholder: "Password", icon: "lock", mask: !show, cls: "kb-field--compact", trail: `<button class="kb-clear dl-eye" data-action="wf-eye" aria-label="${show ? "Hide" : "Show"} password">${App.icon(show ? "eye-off" : "eye", "sm")}</button>` })
        + `<div class="kb-field-help ${p.err ? "err" : ""}">${p.err ? App.icon("triangle-alert", "sm") + "The password must be at least 8 characters." : "WPA2 passwords are 8–63 characters, case-sensitive."}</div>`
        + UI.checkRow({ label: "Connect automatically", on: !!p.checked, attrs: { action: "dl-check" } }),
      actions: [{ label: "Cancel", kind: "ghost", attrs: "data-close" }, { label: "Connect", kind: "primary", attrs: 'data-action="wf-connect" data-kb-submit="wifi-pw"' }],
    }) + `
    <div class="dl-kbdock">${App.keyboardHTML({ target: "wifi-pw", enter: "Done" })}</div>`;
  }
  App.action("wf-pick", (el) => {
    const n = NETS.find((x) => x.name === el.dataset.arg);
    if (n.lock && !n.saved) return App.open("wifi", { connect: n.name });
    App.set("wifi.net", n.name); App.renderLayers(true); App.toast(`Connected to ${n.name}`);
  });
  App.action("wf-eye", () => { const p = topParams(); p.show = !p.show; App.renderLayers(true); App.kbPaint?.("wifi-pw"); });
  App.action("wf-connect", () => {
    const p = topParams(), v = App.kbValue("wifi-pw");
    if ([...v].length < 8) { p.err = 1; App.renderLayers(true); return; }
    App.set("wifi.net", p.connect); App.set("qk.wifi", true);
    App.closeAll(); App.toast(`Connected to ${p.connect}`);
  });
  App.action("wf-power", () => { App.set("qk.wifi", !App.get("qk.wifi", true)); App.renderLayers(true); });
  App.action("wf-disconnect", () => { App.set("qk.wifi", false); App.renderLayers(true); App.toast("Disconnected"); });
  App.action("wf-scan", () => {
    App.state.wifiScan = true; App.renderLayers(true);
    setTimeout(() => { App.state.wifiScan = false; if (App.top()?.name === "wifi") App.renderLayers(true); }, 1400);
  });

  /* ---------------- sleep screen ---------------- */
  const SLEEP = [
    ["cover", "Book cover", "Current book with progress"],
    ["quote", "Reading quote", "From your highlights"],
    ["sleeping", "Sleeping", "Minimal mark, battery, time"],
    ["custom", "Custom image", "/screensavers, random"],
  ];
  function saver(kind) {
    const b = DB.current();
    if (kind === "cover") return `<div class="ss ss-cover"><div class="ss-book">${Cover.svg(b)}</div>
      <div class="ss-band"><div class="ss-t">${esc(b.title.replace(/\s*\(.*\)/, ""))}</div><div class="ss-a">${esc(b.author.split(";")[0])}</div>
        <div class="ss-p"><span style="width:${b.progress}%"></span></div><div class="ss-m"><span>${b.progress}% · Chapter I</span><span>${Math.floor(b.minutesLeft / 60)}h ${b.minutesLeft % 60}m left</span></div></div></div>`;
    if (kind === "quote") { const h = DB.HIGHLIGHTS[2], hb = DB.book(h.book); return `<div class="ss ss-quote"><div class="ss-qm">“</div><div class="ss-qt">${esc(h.text)}</div><div class="ss-qa">— ${esc(hb.author)}, <i>${esc(hb.title)}</i></div><div class="ss-foot">Highlighted ${esc(h.date)} · p. ${h.page}</div></div>`; }
    if (kind === "sleeping") return `<div class="ss ss-sleep"><div class="ss-moon">${App.icon("moon")}</div><div class="ss-z">Sleeping</div><div class="ss-hint">Press the power button to wake</div><div class="ss-foot"><span>87%</span><span>${esc(DB.current().title.replace(/\s*\(.*\)/, ""))} · ${DB.current().progress}%</span></div></div>`;
    return `<div class="ss ss-custom"><svg viewBox="0 0 300 400" preserveAspectRatio="xMidYMid slice"><rect width="300" height="400" fill="var(--page)"/>
      <circle cx="210" cy="120" r="38" fill="none" stroke="var(--page-ink)" stroke-width="1.5"/>
      ${Array.from({ length: 12 }, (_, i) => `<line x1="${172 + i * 6}" y1="${86 + i * 0}" x2="${172 + i * 6}" y2="154" stroke="var(--page-ink)" stroke-width=".6" opacity=".5" clip-path="url(#ssc)"/>`).join("")}
      <path d="M0 270 L60 200 L105 240 L160 160 L230 250 L300 190 L300 400 L0 400Z" fill="var(--page-2)" opacity=".55"/>
      <path d="M0 310 L80 250 L140 300 L210 240 L300 300 L300 400 L0 400Z" fill="var(--page-ink)"/>
      ${Array.from({ length: 9 }, (_, i) => `<path d="M0 ${330 + i * 8} Q150 ${310 + i * 8} 300 ${330 + i * 8}" stroke="var(--page)" stroke-width=".7" fill="none" opacity=".35"/>`).join("")}
      </svg><div class="ss-file">IMG_0142.png · 1 of 23</div></div>`;
  }
  App.overlay("sleep", {
    title: "Sleep screen", layer: "page",
    render(p) {
      if (p.preview) return `<div class="ss-full" data-close>${saver(p.preview)}<div class="ss-full-hint">Preview · tap anywhere to return</div></div>`;
      const cur = App.get("sleep.kind", "cover");
      const row = (k, icon, label, sub, def) => `<button class="ko-row" data-action="sl-flag" data-arg="${k}" data-def="${def ? 1 : 0}">${App.icon(icon)}<span class="label">${label}<span class="sub">${sub}</span></span>${App.toggle(App.get("sleep." + k, def))}</button>`;
      return `<div class="ko-page sl">
        ${App.statusBar({ left: "Sleep screen" })}
        ${UI.screenHead({ title: "Sleep screen", plain: true, back: "data-close", actions: UI.button({ label: "Preview", icon: "eye", attrs: { action: "sl-preview" } }) })}
        <div class="ko-scroll"><div class="sl-wrap">
          <p class="sl-intro">Shown while the device sleeps. E-ink keeps the image on screen without using power.</p>
          <div class="sl-grid">${SLEEP.map(([k, label, sub]) => `<button class="sl-opt ${cur === k ? "on" : ""}" data-action="sl-pick" data-arg="${k}">
            <div class="sl-frame">${saver(k)}${cur === k ? `<span class="ko-selmark sl-badge">${App.icon("check", "sm")}</span>` : ""}</div>
            <div class="sl-cap">${App.radio(cur === k)}<span class="grow"><b>${label}</b><span>${sub}</span></span></div></button>`).join("")}</div>
          ${UI.sectionLabel("Options")}
          <div class="ko-group">
            ${row("msg", "message-square-text", "Show sleep message", "“Sleeping” over the image", true)}
            ${row("progress", "chart-no-axes-column", "Show book progress", "Percentage and time left on the cover", true)}
            ${row("stretch", "maximize-2", "Stretch cover to fill", "Ignore the cover's aspect ratio", false)}
            ${row("invert", "contrast", "Follow night mode", "Invert the sleep screen when night mode is on", true)}
            <button class="ko-row" data-open="input" data-params='${App.attrs({ title: "Custom images folder", hint: "Folder path", value: "/mnt/onboard/screensavers", ok: "Save" })}'>${App.icon("folder-open")}<span class="label">Custom images folder<span class="sub">/mnt/onboard/screensavers · 23 images</span></span>${App.icon("chevron-right", "sm chev")}</button>
            <button class="ko-row" data-open="input" data-params='${App.attrs({ title: "Sleep message", hint: "Message", value: "Sleeping", ok: "Save" })}'>${App.icon("type")}<span class="label">Sleep message<span class="sub">Sleeping</span></span>${App.icon("chevron-right", "sm chev")}</button>
          </div>
        </div></div>
      </div>`;
    },
  });
  App.action("sl-pick", (el) => { App.set("sleep.kind", el.dataset.arg); App.renderLayers(true); });
  App.action("sl-preview", () => App.open("sleep", { preview: App.get("sleep.kind", "cover") }));
  App.action("sl-flag", (el) => { const k = "sleep." + el.dataset.arg; App.set(k, !App.get(k, el.dataset.def === "1")); App.renderLayers(true); });

  /* ---------------- about ---------------- */
  App.overlay("about", {
    title: "About", layer: "dialog",
    render() {
      const st = App.state.aboutCheck || 0;
      const seg = [["Books", 9.1, 1], ["Cache & covers", 0.8, 2], ["System & other", 2.5, 3]];
      const total = 28.6, used = seg.reduce((a, s) => a + s[1], 0);
      const upd = st === 1 ? `<button class="ko-btn ko-btn--ghost ko-btn--block" disabled>Checking for updates…</button>`
        : st === 2 ? `<div class="ko-card ko-card--sunken ko-card--sm ab-ok">${App.icon("badge-check")}<div><b>You're up to date</b><span>v2026.07.1 is the latest stable release · checked just now</span></div></div>`
        : `<button class="ko-btn ko-btn--primary ko-btn--block" data-action="ab-check">Check for updates</button>`;
      return `<div class="ko-dialog ko-dialog--scroll ab">
        ${UI.closeButton({ cls: "ab-x" })}
        <div class="ab-head">
          <span class="ab-mark serif">K</span>
          <div><div class="ab-name">KOReader</div><div class="ab-ver num">v2026.07.1 · Leaf UI</div></div>
        </div>
        <p class="ab-tag">A document viewer for E Ink devices. Free and open source, made by volunteers since 2012.</p>
        ${UI.kv([["Device", "Kindle Paperwhite"], ["Screen", "1264 × 1680 · 300 ppi"], ["Build", "2026-07-14 · kindlepw2 · armv7"], ["Licence", "AGPL-3.0"]], { cls: "ab-list" })}
        <div class="ab-store">${UI.meter(seg.map(([, v, k]) => ({ pct: (v / total) * 100, kind: k })), {
          head: `<span>${App.icon("hard-drive", "sm")}Storage</span><span class="num"><b>${used.toFixed(1)} GB</b> of ${total} GB used</span>`,
          legend: seg.map(([l, v, k]) => ({ label: l, value: `${v} GB`, kind: k })).concat([{ label: "Free", value: `${(total - used).toFixed(1)} GB`, kind: "free" }]) })}</div>
        ${upd}
        <div class="ab-links">
          <button data-open="info" data-params='${App.attrs({ title: "Open-source licences", icon: "scale", body: "KOReader is free software released under the GNU AGPL v3. It builds on:", list: [["LuaJIT", "MIT"], ["MuPDF", "AGPL-3.0"], ["crengine", "GPL-2.0"], ["FreeType", "FTL"], ["HarfBuzz", "MIT"], ["SQLite", "Public domain"], ["Lucide icons", "ISC"], ["Inter, Literata, Playfair", "OFL-1.1"]] })}'>Licences</button>
          <i></i><button data-toast="koreader.rocks">Website</button>
          <i></i><button data-toast="Opening release notes">Release notes</button>
        </div>
      </div>`;
    },
  });
  App.action("ab-check", () => {
    App.state.aboutCheck = 1; App.renderLayers(true);
    setTimeout(() => { App.state.aboutCheck = 2; if (App.top()?.name === "about") App.renderLayers(true); }, 1300);
  });

  /* ---------------- designer states ---------------- */
  App.demo(G, "Input · New folder", H("home", { o: "input", "o.title": "New folder", "o.hint": "Folder name", "o.ok": "Create", "o.checkbox": "Enter folder after creation", "o.checked": true }));
  App.demo(G, "Input · Rename file", H("home", { o: "input", "o.title": "Rename", "o.value": "Animal Farm (EN-AR).epub", "o.ok": "Rename", "o.desc": "The sidecar folder with highlights is renamed too." }));
  App.demo(G, "Input · Go to page (numeric)", H("home", { o: "input", "o.title": "Go to page", "o.hint": "Page 1–112, or 50%", "o.ok": "Go", "o.layout": "numeric", "o.desc": "Current page 9 of 112. Use +/− for relative jumps." }));
  App.demo(G, "Input · Arabic keyboard", H("home", { o: "input", "o.title": "Rename collection", "o.value": "روايات", "o.ok": "Save", "o.layout": "arabic" }));
  App.demo(G, "Confirm · Delete book", H("home", { o: "confirm", "o.title": "Delete this book?", "o.body": "The file and its highlights, notes and reading progress will be removed from the device.", "o.ok": "Delete", "o.danger": true, "o.id": "dracula" }));
  App.demo(G, "Confirm · Exit", H("home", { o: "confirm", "o.title": "Exit KOReader?", "o.body": "Your reading position is saved. You can come back from the device's home screen.", "o.ok": "Exit", "o.danger": true, "o.icon": "log-out" }));
  App.demo(G, "Confirm · Reset settings", H("home", { o: "confirm", "o.title": "Reset all settings?", "o.body": "Fonts, margins, gestures and menus return to their defaults. Books and highlights are not affected.", "o.ok": "Reset", "o.danger": true, "o.icon": "rotate-ccw" }));
  App.demo(G, "Info · message", H("home", { o: "info", "o.title": "Can't open this file", "o.body": "“comic-chapter-12.cbz” looks damaged or incomplete. Copy it to the device again, then retry." }));
  App.demo(G, "Info · as toast (result)", H("home", { o: "info", "o.toast": "Cache cleared · 142 MB freed" }));
  App.demo(G, "Frontlight", H("home", { o: "frontlight" }));
  App.demo(G, "Quick settings", H("home", { o: "quick" }));
  App.demo(G, "Wi-Fi networks", H("home", { o: "wifi" }));
  App.demo(G, "Wi-Fi password", H("home", { o: "wifi", "o.connect": "Café Lumière" }));
  App.demo(G, "Sleep screen picker", H("home", { o: "sleep" }));
  App.demo(G, "Sleep screen · preview", H("home", { o: "sleep", "o.preview": "cover" }));
  App.demo(G, "About", H("home", { o: "about" }));
})();
