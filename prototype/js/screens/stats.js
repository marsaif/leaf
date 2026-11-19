/* ==========================================================================
   Tools · reading statistics dashboard  (screen "stats", params {range})
   Charts are plain HTML/CSS: solid blocks that survive 16-level grayscale.
   ========================================================================== */
(function () {
  const esc = App.esc, S = DB.STATS;
  const TODAY = new Date(2026, 10, 19);
  const DAY = 864e5;
  const GOAL = 45;                // daily goal, minutes
  const YEAR_GOAL_BOOKS = 24;
  const daily = S.daily.slice(); daily[daily.length - 1] = S.today;
  const hourly = Array(24).fill(0); Object.assign(hourly, { 6: 4, 7: 11, 8: 5, 12: 3, 21: 5, 22: 7 }); // = 35
  const mSum = S.monthly.reduce((a, b) => a + b, 0);
  const yearH = S.monthly.map((v) => Math.round((v * S.totalHours) / mSum));
  const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const booksPerMonth = [1, 2, 1, 2, 1, 2, 2, 1, 2, 1, 2]; // Jan..Nov = 17
  const sum = (a) => a.reduce((x, y) => x + y, 0);
  const dayAt = (back) => new Date(TODAY.getTime() - back * DAY);

  const fmt = (m) => { m = Math.round(m); const h = Math.floor(m / 60), r = m % 60; return h ? (r ? `${h}h ${r}m` : `${h}h`) : `${r}m`; };
  const big = (m) => { m = Math.round(m); const h = Math.floor(m / 60), r = m % 60; return h ? `${h}<small>h</small>${r ? ` ${r}<small>m</small>` : ""}` : `${r}<small>m</small>`; };

  function range(r) {
    if (r === "today") return {
      key: r, label: "Today", sub: "Thursday, 19 November", unit: "m", values: hourly, total: S.today, prev: daily[28], prevLabel: "yesterday",
      labels: hourly.map((_, i) => (i % 6 === 0 ? String(i).padStart(2, "0") + ":00" : "")), hi: 22, goal: null, chart: "By hour of day",
      goalTotal: GOAL, sessions: 4, books: 2, highlights: 1,
    };
    if (r === "month") {
      const total = sum(daily);
      return {
        key: r, label: "Last 30 days", sub: `${dayAt(29).getDate()} Oct – 19 Nov`, unit: "m", values: daily, total, prev: Math.round(total * 0.91), prevLabel: "previous 30 days",
        labels: daily.map((_, i) => { const d = dayAt(29 - i); return (29 - i) % 7 === 0 ? String(d.getDate()) : ""; }), hi: 29, goal: GOAL, chart: "Per day",
        goalTotal: GOAL * 30, sessions: 61, books: 6, highlights: 34,
      };
    }
    if (r === "year") {
      const total = sum(yearH) * 60;
      return {
        key: r, label: "Last 12 months", sub: "Dec 2025 – Nov 2026", unit: "h", values: yearH, total, prev: total * 0.84, prevLabel: "previous year",
        labels: yearH.map((_, i) => MONTHS[(11 + i) % 12][0]), hi: 11, goal: 20, chart: "Per month",
        goalTotal: 240 * 60, sessions: 512, books: 21, highlights: 212,
      };
    }
    const v = daily.slice(-7), total = sum(v);
    return {
      key: "week", label: "This week", sub: "13 – 19 November", unit: "m", values: v, total, prev: sum(daily.slice(-14, -7)), prevLabel: "last week",
      labels: v.map((_, i) => "MTWTFSS"[(dayAt(6 - i).getDay() + 6) % 7]), hi: 6, goal: GOAL, chart: "Per day",
      goalTotal: GOAL * 7, sessions: 14, books: 3, highlights: 9,
    };
  }

  /* ---------- pieces ---------- */
  function ring(pct, label, sub) {
    const r = 38, c = 2 * Math.PI * r, p = Math.max(0, Math.min(1, pct));
    return `<div class="st-ring"><svg viewBox="0 0 96 96"><circle cx="48" cy="48" r="${r}" class="trk"/><circle cx="48" cy="48" r="${r}" class="val" stroke-dasharray="${(c * p).toFixed(1)} ${c.toFixed(1)}" transform="rotate(-90 48 48)"/></svg>
      <div class="st-ring-in"><b class="num">${Math.round(pct * 100)}%</b><span>${label}</span></div></div>`;
  }
  function niceTop(max) {
    const steps = [1, 2, 5, 10, 15, 20, 30, 40, 60, 90, 120];
    const s = steps.find((x) => x * 3 >= max) || 120;
    return s * 3;
  }
  function chart(R) {
    const top = niceTop(Math.max(...R.values, R.goal || 0) * 1.05);
    const ticks = [top, (top * 2) / 3, top / 3, 0];
    const u = R.unit;
    const cols = R.values.map((v, i) => {
      const h = (v / top) * 100;
      const ghost = R.goal && v < R.goal ? `<span class="st-ghost" style="height:${(R.goal / top) * 100}%"></span>` : "";
      const met = R.goal && v >= R.goal;
      return `<div class="st-col ${i === R.hi ? "hi" : ""} ${met ? "met" : ""}" title="${v}${u}">${ghost}<span class="st-bar" style="height:${h}%">${i === R.hi ? `<em class="num">${u === "h" ? v + "h" : fmt(v)}</em>` : ""}</span></div>`;
    }).join("");
    return `<div class="st-chart ${R.values.length > 14 ? "dense" : ""}" style="--n:${R.values.length}">
      <div class="st-y">${ticks.map((t) => `<span class="num">${Math.round(t)}${u}</span>`).join("")}</div>
      <div class="st-plot">
        ${ticks.map((t) => `<i class="st-gl" style="bottom:${(t / top) * 100}%"></i>`).join("")}
        ${R.goal ? `<i class="st-goal" style="bottom:${(R.goal / top) * 100}%"><span>Goal ${R.goal}${u}</span></i>` : ""}
        <div class="st-bars">${cols}</div>
      </div>
      <div></div>
      <div class="st-x">${R.labels.map((l, i) => `<span class="${i === R.hi ? "hi" : ""}">${l}</span>`).join("")}</div>
    </div>`;
  }

  function kpis() {
    const strip = Array.from({ length: 21 }, (_, i) => { const back = 20 - i; return `<i class="${back < S.streak ? "on" : ""} ${back === 0 ? "today" : ""}"></i>`; }).join("");
    const card = (icon, value, label, sub) => `<div class="ko-card st-kpi"><div class="st-kpi-top">${App.icon(icon, "sm")}<span>${label}</span></div><div class="st-kpi-v num">${value}</div><div class="st-kpi-s">${sub}</div></div>`;
    return `<div class="st-kpis">
      <div class="ko-card st-kpi st-streak">
        <div class="st-kpi-top">${App.icon("flame", "sm")}<span>Reading streak</span></div>
        <div class="st-streak-row"><div><div class="st-kpi-v num">${S.streak}<small> days</small></div><div class="st-kpi-s">Longest: ${S.longestStreak} days · keep it going tonight</div></div>
        <div class="st-strip" aria-label="Last 21 days">${strip}</div></div>
      </div>
      ${card("clock", `${S.totalHours}<small>h</small>`, "Total time", "Read in 2026")}
      ${card("book-check", S.booksFinished, "Books finished", `of ${YEAR_GOAL_BOOKS} this year`)}
      ${card("gauge", S.pagesPerHour, "Pages / hour", `≈ ${(60 / S.pagesPerHour).toFixed(1)} min per page`)}
      ${card("calendar-days", `${S.avgPerDay}<small>m</small>`, "Daily average", `Goal ${GOAL}m · ${Math.round((S.avgPerDay / GOAL) * 100)}%`)}
    </div>`;
  }

  // reading calendar: Jan 2026 → today, weeks as columns
  function heatmap() {
    const r = (() => { let s = 7; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296); })();
    const start = new Date(2025, 11, 29); // Monday
    const weeks = Math.ceil((TODAY - start) / DAY / 7 + 1 / 7);
    let cells = "", days = 0, lastMonth = -1;
    const months = [];
    for (let w = 0; w < weeks; w++) {
      for (let d = 0; d < 7; d++) {
        const dt = new Date(start.getTime() + (w * 7 + d) * DAY);
        let cls = "";
        if (dt.getFullYear() < 2026) cls = "out";
        else if (dt > TODAY) cls = "future";
        else {
          const back = Math.round((TODAY - dt) / DAY);
          const m = back < 30 ? daily[29 - back] : (r() < 0.16 ? 0 : Math.round(r() * 75));
          if (m) days++;
          cls = "st-l" + (m === 0 ? 0 : m < 20 ? 1 : m < 35 ? 2 : m < 55 ? 3 : 4);
          if (dt.getDate() <= 7 && d === 0 && dt.getMonth() !== lastMonth) { months.push([w, dt.getMonth()]); lastMonth = dt.getMonth(); }
        }
        cells += `<i class="${cls}"></i>`;
      }
    }
    if (!months.length || months[0][1] !== 0) months.unshift([0, 0]);
    return `<div class="ko-card st-card st-cal">
      <div class="st-card-h"><div><div class="st-card-t">Reading calendar</div><div class="st-card-s">Read on <b>${days}</b> of ${Math.round((TODAY - new Date(2026, 0, 1)) / DAY) + 1} days in 2026</div></div>
        <div class="st-legend"><span>Less</span><i class="st-l0"></i><i class="st-l1"></i><i class="st-l2"></i><i class="st-l3"></i><i class="st-l4"></i><span>More</span></div></div>
      <div class="st-heat" style="--w:${weeks}">
        <div class="st-heat-m">${months.map(([w, m]) => `<span style="grid-column:${w + 1} / span ${Math.max(1, Math.min(4, weeks - w))}">${MONTHS[m]}</span>`).join("")}</div>
        <div class="st-heat-d"><span>M</span><span></span><span>W</span><span></span><span>F</span><span></span><span></span></div>
        <div class="st-heat-g">${cells}</div>
      </div>
    </div>`;
  }

  function booksYear() {
    const max = Math.max(...booksPerMonth);
    const finished = DB.BOOKS.filter((b) => b.progress >= 100);
    const pct = S.booksFinished / YEAR_GOAL_BOOKS;
    const expected = Math.round(YEAR_GOAL_BOOKS * (TODAY.getMonth() + TODAY.getDate() / 30) / 12);
    return `<div class="ko-card st-card st-books">
      <div class="st-card-h"><div><div class="st-card-t">Books this year</div><div class="st-card-s">${S.booksFinished >= expected ? "On track" : `${expected - S.booksFinished} behind`} for your goal of ${YEAR_GOAL_BOOKS}</div></div>
        <button class="ko-chip st-chip" data-open="input" data-params='${App.attrs({ title: "Yearly reading goal", hint: "Books per year", value: String(YEAR_GOAL_BOOKS), ok: "Save", layout: "numeric" })}'>${App.icon("target", "sm")}Goal</button></div>
      <div class="st-books-hero"><span class="st-big num">${S.booksFinished}</span><span class="st-of">of ${YEAR_GOAL_BOOKS}</span>
        <div class="grow"><div class="st-goalbar"><i style="width:${pct * 100}%"></i><b style="left:${(expected / YEAR_GOAL_BOOKS) * 100}%"></b></div>
        <div class="st-goalbar-l"><span>${Math.round(pct * 100)}% done</span><span>${YEAR_GOAL_BOOKS - S.booksFinished} to go · 6 weeks left</span></div></div></div>
      <div class="st-mbars">${MONTHS.map((m, i) => { const v = booksPerMonth[i]; return `<div class="${v == null ? "future" : ""} ${i === 10 ? "hi" : ""}"><span class="st-mbar-v num">${v ?? ""}</span><span class="st-mbar" style="height:${v ? (v / max) * 100 : 0}%"></span><span class="st-mbar-l">${m[0]}</span></div>`; }).join("")}</div>
      <div class="st-finished">${finished.map((b) => `<button data-open="book-details" data-params='${App.attrs({ id: b.id })}'>${Cover.html(b)}</button>`).join("")}<span class="st-more-books">+${S.booksFinished - finished.length}<small>more</small></span></div>
    </div>`;
  }

  function perBook() {
    const rows = DB.HISTORY.map((id) => DB.book(id)).filter((b) => b.progress).slice(0, 7).map((b, i) => {
      const pages = Math.round((b.pages * b.progress) / 100);
      const speed = 38 + ((b.id.length * 7 + i * 5) % 19);
      const mins = Math.round((pages / speed) * 60);
      return { b, pages, speed, mins };
    }).sort((a, b) => b.mins - a.mins);
    const maxM = Math.max(...rows.map((r) => r.mins));
    return `<div class="ko-card st-card st-perbook">
      <div class="st-card-h"><div><div class="st-card-t">Time per book</div><div class="st-card-s">Books opened recently, by time spent</div></div></div>
      <div class="st-pb-head"><span></span><span>Time</span><span>Pages</span><span>Speed</span></div>
      ${rows.map(({ b, pages, speed, mins }) => `<div class="st-pb" role="button" data-open="book-details" data-params='${App.attrs({ id: b.id })}'>
        <div class="st-pb-c">${Cover.html(b)}</div>
        <div class="st-pb-t"><div class="ellipsis st-pb-title" dir="auto">${esc(b.title)}</div>
          <div class="st-pb-bar"><i style="width:${(mins / maxM) * 100}%"></i></div>
          <div class="st-pb-s">${b.progress >= 100 ? "Finished" : b.progress + "% read"} · ${esc((b.lastRead || "").replace(/^1 days/, "1 day"))}</div></div>
        <span class="num st-pb-v"><b>${fmt(mins)}</b></span><span class="num st-pb-v">${pages}</span><span class="num st-pb-v">${speed}<small> p/h</small></span>
      </div>`).join("")}
    </div>`;
  }

  function milestones() {
    const next = [["clock", "250 hours read", S.totalHours, 250, "h"], ["book-check", `${YEAR_GOAL_BOOKS} books this year`, S.booksFinished, YEAR_GOAL_BOOKS, ""], ["flame", "Beat your 31-day streak", S.streak, S.longestStreak + 1, " days"]];
    return `<div class="ko-card st-card st-miles">
      <div class="st-card-h"><div><div class="st-card-t">Recent milestones</div></div></div>
      <div class="st-ms">${S.milestones.map((m) => `<div class="st-m"><span class="st-m-i">${App.icon(m.icon, "sm")}</span><span class="grow">${esc(m.text)}</span><span class="st-m-w">${esc(m.when)}</span></div>`).join("")}</div>
      <div class="ko-eyebrow st-sub-h">Up next</div>
      ${next.map(([ic, t, v, max, u]) => `<div class="st-next"><span class="st-m-i ghost">${App.icon(ic, "sm")}</span><div class="grow"><div class="st-next-t"><span>${t}</span><span class="num">${v}${u} / ${max}${u}</span></div>${App.progress((v / max, "ko-progress--md") * 100)}</div></div>`).join("")}
    </div>`;
  }

  App.screen("stats", {
    title: "Reading stats",
    render(p) {
      const R = range(p.range || "week");
      const delta = Math.round(((R.total - R.prev) / R.prev) * 100);
      const segs = [["today", "Today"], ["week", "Week"], ["month", "Month"], ["year", "Year"]];
      const pages = Math.round((R.total * S.pagesPerHour) / 60);
      return `<div class="ko-view st">
        ${App.statusBar({ left: "Statistics" })}
        <header class="ko-header st-headbar">
          <button class="ko-icon-btn back" data-action="tools-back" aria-label="Back">${App.icon("arrow-left")}</button>
          <span class="title display">Reading stats</span><span class="spacer"></span>
          <button class="ko-icon-btn" data-toast="Statistics synced · just now" aria-label="Sync">${App.icon("refresh-cw")}</button>
          <button class="ko-icon-btn" data-open="stats-menu" aria-label="More">${App.icon("ellipsis-vertical")}</button>
        </header>
        <div class="ko-scroll st-scroll"><div class="st-wrap">
          <div class="st-segbar"><div class="ko-seg ko-seg--block st-seg">${segs.map(([k, l]) => `<button class="${R.key === k ? "on" : ""}" data-go="stats" data-params='${App.attrs({ range: k })}'>${l}</button>`).join("")}</div></div>
          <div class="st-grid">
            <div class="ko-card st-card st-hero">
              <div class="st-hero-top">
                <div class="grow">
                  <div class="ko-eyebrow st-eyebrow">Time read · ${R.label}</div>
                  <div class="st-time serif num">${big(R.total)}</div>
                  <div class="st-delta ${delta >= 0 ? "up" : "down"}">${App.icon(delta >= 0 ? "trending-up" : "trending-down", "sm")}<span><b>${Math.abs(delta)}% ${delta >= 0 ? "more" : "less"}</b> than ${R.prevLabel}</span></div>
                </div>
                ${ring(R.total / R.goalTotal, "of goal", "")}
              </div>
              ${UI.stats([["pages", pages], ["sessions", R.sessions], ["books", R.books], ["highlights", R.highlights]].map(([label, value]) => ({ label, value })), { center: true, cls: "st-mini" })}
              <div class="st-chart-h"><span>${R.chart}</span><span class="st-chart-sub">${esc(R.sub)}</span></div>
              ${chart(R)}
              ${R.goal ? `<div class="st-key"><span><i class="k-read"></i>Read</span><span><i class="k-ghost"></i>Left to ${R.key === "year" ? "monthly" : "daily"} goal</span><span><i class="k-hi"></i>${R.key === "year" ? "This month" : "Today"}</span></div>` : `<div class="st-key"><span>Most reading happens around <b>07:00</b> and <b>22:00</b></span></div>`}
            </div>
            ${kpis()}
          </div>
          ${heatmap()}
          <div class="st-grid2">${booksYear()}${milestones()}</div>
          ${perBook()}
          <p class="st-foot">${App.icon("info", "sm")}Statistics are stored on this device (statistics.sqlite3) and can be synced with KOSync.</p>
        </div></div>
      </div>`;
    },
  });

  /* KOReader's statistics menu, as an anchored panel */
  App.overlay("stats-menu", {
    layer: "popover", clear: true,
    render() {
      const row = (icon, label, attrs, sub) => `<button class="ko-row" ${attrs}>${App.icon(icon)}<span class="label">${label}${sub ? `<span class="sub">${sub}</span>` : ""}</span></button>`;
      return `<div class="ko-popover st-pop">
        <div class="ko-section-label">Statistics</div>
        ${row("book-open", "Current book", `data-close data-toast="Animal Farm · 2h 14m · 9 pages"`)}
        ${row("chart-no-axes-column", "Reading progress", `data-close data-go="stats" data-params='${App.attrs({ range: "week" })}'`)}
        ${row("calendar-range", "Time range", `data-close data-go="stats" data-params='${App.attrs({ range: "month" })}'`)}
        ${row("calendar-days", "Calendar view", `data-close data-go="stats" data-params='${App.attrs({ range: "year" })}'`)}
        ${row("library", "All books", `data-close data-toast="Opening per-book statistics"`)}
        <div class="ko-divider"></div>
        ${row("refresh-cw", "Synchronize now", `data-close data-toast="Statistics synced"`, "Last sync 2 hours ago")}
        ${row("settings-2", "Statistics settings", `data-close data-go="settings" data-params='${App.attrs({ section: "statistics" })}'`)}
        ${row("rotate-ccw", "Reset statistics…", `data-action="st-reset"`)}
      </div>`;
    },
  });
  App.action("st-reset", () => App.replaceTop("confirm", { title: "Reset all statistics?", body: "Reading time, pages and streaks for every book will be deleted. This cannot be undone.", ok: "Reset", danger: true, icon: "rotate-ccw" }));

  const H = App.toolsHash, G = "Search & Stats";
  App.demo(G, "Stats · today", H("stats", { range: "today" }));
  App.demo(G, "Stats · week", H("stats", { range: "week" }));
  App.demo(G, "Stats · month", H("stats", { range: "month" }));
  App.demo(G, "Stats · year", H("stats", { range: "year" }));
  App.demo(G, "Stats · menu", H("stats", { range: "week", o: "stats-menu" }));
})();
