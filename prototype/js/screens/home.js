/* ==========================================================================
   Library agent — Home dashboard (screen "home").  Prefix: hm-
   Uses window.Lib helpers from library.js (resolved at render time).
   ========================================================================== */
(function () {
  const A = App, esc = App.esc, I = App.icon;
  const DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
  const WD = ["S", "M", "T", "W", "T", "F", "S"];

  function greeting() { const h = new Date().getHours(); return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"; }

  function hero(b) {
    const L = window.Lib, pct = L.pct(b), chs = TextGen.chapters(b.id);
    const ch = chs[Math.min(chs.length - 1, Math.floor((pct / 100) * chs.length))];
    const chLeft = b.chapterMinutes;
    return `<section class="hm-hero ko-card">
      <button class="hm-hero-cover" data-open="book-details" data-params='${A.attrs({ id: b.id })}' data-book="${b.id}" aria-label="Book details">${Cover.html(b)}</button>
      <div class="hm-hero-body">
        <div class="ko-eyebrow ko-eyebrow--accent hm-eyebrow">${I("book-open", "sm")}Continue reading</div>
        <h2 class="hm-hero-title"${L.lang(b)}>${esc(b.title)}</h2>
        <div class="hm-hero-author"${L.lang(b)}>${esc(L.author(b))}</div>
        <div class="hm-hero-ch">${esc(ch.title)}<span class="d">·</span>Page ${L.page(b)} of ${b.pages}</div>
        <div class="hm-hero-prog">${A.progress(pct, "ko-progress--md")}<span class="num">${pct}%</span></div>
        <div class="hm-hero-left"><span>${I("clock", "sm")}${L.dur(L.minLeft(b))} left in book</span><span>${I("bookmark", "sm")}${chLeft} min left in chapter</span></div>
        <div class="hm-hero-actions">
          <button class="ko-btn ko-btn--primary hm-resume" data-go="reader" data-params='${A.attrs({ id: b.id })}'>${I("play", "sm")}Resume</button>
          <button class="ko-btn ko-btn--ghost" data-open="book-details" data-params='${A.attrs({ id: b.id })}'>Details</button>
          <span class="spacer"></span>
          <button class="ko-icon-btn" data-open="book-actions" data-params='${A.attrs({ id: b.id })}' aria-label="More">${I("ellipsis-vertical")}</button>
        </div>
      </div>
    </section>`;
  }

  function stats() {
    const S = DB.STATS, goal = A.get("home.goal", 45);
    const week = S.daily.slice(-7); week[6] = S.today;
    const max = Math.max(goal, ...week);
    const today = new Date().getDay();
    const labels = week.map((_, i) => WD[(today - 6 + i + 7) % 7]);
    const bars = week.map((m, i) => `<div class="hm-bar ${i === 6 ? "today" : ""} ${m >= goal ? "met" : ""}" title="${m} min"><i style="height:${Math.max(6, (m / max) * 100)}%"></i><span>${labels[i]}</span></div>`).join("");
    const pct = Math.min(100, Math.round((S.today / goal) * 100));
    const dots = Array.from({ length: 7 }, (_, i) => `<span class="${i <= (today + 6) % 7 ? "on" : ""}"></span>`).join("");
    return `<div class="hm-stats">
      <button class="hm-today ko-card ko-card--tap" data-go="stats" aria-label="Reading statistics">
        <div class="ko-eyebrow hm-card-h"><span>Today</span>${I("chevron-right", "sm")}</div>
        <div class="hm-today-main">
          <div><div class="hm-big num">${S.today}<small>m</small></div><div class="hm-sub">of ${goal} min goal · ${pct}%</div></div>
          <div class="hm-bars" style="--goal:${(goal / max) * 100}%">${bars}<span class="hm-goal"></span></div>
        </div>
        <div class="hm-today-foot"><span>${I("file-text", "sm")}${S.pagesThisWeek} pages this week</span><span>${I("gauge", "sm")}${S.pagesPerHour} pages/h</span></div>
      </button>
      <button class="hm-streak ko-card ko-card--tap" data-go="stats" aria-label="Reading streak">
        <div class="ko-eyebrow hm-card-h"><span>Streak</span>${I("flame", "sm")}</div>
        <div class="hm-big num">${S.streak}<small> days</small></div>
        <div class="hm-dots">${dots}</div>
        <div class="hm-sub">Best ${S.longestStreak} days · ${S.booksFinished} books this year</div>
      </button>
    </div>`;
  }

  function recent(cur) {
    const L = window.Lib;
    const ids = DB.HISTORY.filter((id) => id !== cur.id).slice(0, 5);
    return `<section class="hm-sec hm-recent">
      <div class="hm-sec-h"><h3>Recently read</h3><button class="ko-link" data-go="history">History${I("chevron-right", "sm")}</button></div>
      <div class="hm-shelf">${ids.map((id) => { const b = DB.book(id), s = L.status(b);
        return `<button class="hm-book" data-open="book-details" data-params='${A.attrs({ id })}' data-book="${id}">
          <div class="hm-book-cov">${Cover.html(b, s === "finished" ? { badge: I("check", "sm") } : { badge: L.pct(b) + "%" })}</div>
          <div class="t ellipsis"${L.lang(b)}>${esc(b.title)}</div>
          ${s === "finished" ? `<div class="hm-mini done">Finished</div>` : `<div class="hm-mini">${A.progress(L.pct(b), "ko-progress--thin")}</div>`}
        </button>`; }).join("")}</div>
    </section>`;
  }

  function shelves() {
    const L = window.Lib, cols = L.collections();
    return `<section class="hm-sec hm-shelves">
      <div class="hm-sec-h"><h3>Shelves</h3><button class="ko-link" data-go="library" data-params='${A.attrs({ tab: "collections" })}'>All collections${I("chevron-right", "sm")}</button></div>
      <div class="hm-shelf-grid">${cols.map((c) => `<button class="ko-card ko-card--tap hm-coll" data-go="collection" data-params='${A.attrs({ name: c.name })}'>
          <div class="hm-coll-covers">${c.ids.slice(0, 3).map((id) => `<div>${Cover.html(DB.book(id))}</div>`).join("")}</div>
          <div class="grow"><div class="n ellipsis">${c.name === "Favorites" ? I("heart", "sm") : ""}${esc(c.name)}</div><div class="c">${c.ids.length} books</div></div>
        </button>`).join("")}</div>
    </section>`;
  }

  function quote() {
    const i = A.get("home.quote", new Date().getDate() % DB.QUOTES.length) % DB.QUOTES.length;
    const [q, who] = DB.QUOTES[i];
    return `<section class="hm-quote ko-card">
      <div class="ko-eyebrow hm-card-h"><span>Quote of the day</span><button class="ko-icon-btn ko-icon-btn--sm" data-action="home-quote" aria-label="Another quote">${I("refresh-cw", "sm")}</button></div>
      <blockquote>“${esc(q)}”</blockquote>
      <div class="who">— ${esc(who)}</div>
    </section>`;
  }

  function added() {
    const L = window.Lib;
    const list = [...DB.BOOKS].sort((a, b) => b.added.localeCompare(a.added)).slice(0, 6);
    return `<section class="hm-sec hm-added">
      <div class="hm-sec-h"><h3>Recently added</h3><button class="ko-link" data-action="home-added">Library${I("chevron-right", "sm")}</button></div>
      <div class="hm-added-row">${list.map((b) => `<button class="hm-arow" data-open="book-details" data-params='${A.attrs({ id: b.id })}' data-book="${b.id}">
          <div class="hm-arow-cov">${Cover.html(b)}</div>
          <div class="grow"><div class="t ellipsis"${L.lang(b)}>${esc(b.title)}</div><div class="a ellipsis"${L.lang(b)}>${esc(L.author(b))}</div>
          <div class="m">${b.format.toUpperCase()} · ${b.pages} p ${L.status(b) === "new" ? `<span class="ko-pill ko-pill--accent ko-pill--sm">New</span>` : ""}</div></div>
        </button>`).join("")}</div>
    </section>`;
  }

  A.screen("home", {
    render() {
      const cur = DB.current();
      const d = new Date();
      return `<div class="ko-view hm">${A.statusBar()}
        <div class="ko-header hm-head">
          <div class="grow"><div class="ko-eyebrow hm-date">${DAYS[d.getDay()]}, ${d.getDate()} ${MONTHS[d.getMonth()]}</div><div class="title display">${greeting()}</div></div>
          <button class="ko-icon-btn" data-go="search" aria-label="Search">${I("search")}</button>
          <button class="ko-icon-btn" data-open="frontlight" aria-label="Frontlight">${I("sun-medium")}</button>
          <button class="ko-icon-btn" data-open="main-menu" data-params='${A.attrs({ ctx: "fm" })}' aria-label="Menu">${I("menu")}</button>
        </div>
        <div class="ko-scroll"><div class="hm-grid">
          ${hero(cur)}
          ${stats()}
          ${recent(cur)}
          ${shelves()}
          ${quote()}
          ${added()}
        </div></div>
        ${A.bottomNav("home")}</div>`;
    },
  });

  A.action("home-quote", () => { A.set("home.quote", (A.get("home.quote", new Date().getDate() % DB.QUOTES.length) + 1) % DB.QUOTES.length); A.refresh(); });
  A.action("home-added", () => { A.set("lib.sort", "date"); A.go("library", { tab: "library" }); });

  A.demo("Home & Library", "Home dashboard", "#/home");
})();
