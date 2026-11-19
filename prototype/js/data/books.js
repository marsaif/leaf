/* ==========================================================================
   Fake library for the prototype: books, folders, collections, history,
   reading stats, highlights, and a seeded random-prose generator.
   window.DB  — data           window.Cover.svg(book) — generated cover art
   window.TextGen.chapter(bookId, chapterIndex) — deterministic random prose
   ========================================================================== */
(function () {
  // seeded RNG so every reload looks the same
  function rng(seed) { let s = 0; for (const c of String(seed)) s = (s * 31 + c.charCodeAt(0)) >>> 0; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296); }

  const BOOKS = [
    // id, title, author, year, pages, progress(0-100 or null), status, folder, series, palette, style, lang
    ["animal-farm", "Animal Farm (EN-AR)", "George Orwell; Russell Translation", 1945, 112, 8, "reading", "Classics", null, ["#7a2e1f", "#f1e3c6", "#2b1a12"], "band", "en"],
    ["frankenstein", "Frankenstein", "Mary Shelley", 1818, 280, 90, "reading", "Classics", null, ["#1d2a2e", "#c9d6cf", "#0e1517"], "frame", "en"],
    ["gatsby", "The Great Gatsby", "F. Scott Fitzgerald", 1925, 180, 0, "new", "Classics", null, ["#14213d", "#fca311", "#0b1224"], "deco", "en"],
    ["pride", "Pride and Prejudice", "Jane Austen", 1813, 432, 45, "reading", "Classics", null, ["#e9dcc9", "#5a3e36", "#c4a78f"], "oval", "en"],
    ["moby", "Moby-Dick", "Herman Melville", 1851, 635, 12, "reading", "Classics", null, ["#0f3b57", "#e6eef2", "#0a2537"], "wave", "en"],
    ["dracula", "Dracula", "Bram Stoker", 1897, 418, 100, "finished", "Horror", null, ["#2a0b0f", "#d8c3a5", "#120406"], "frame", "en"],
    ["meditations", "Meditations", "Marcus Aurelius", 180, 254, 64, "reading", "Philosophy", null, ["#c8b88a", "#2f2a1f", "#a99766"], "column", "en"],
    ["walden", "Walden", "Henry David Thoreau", 1854, 352, 0, "new", "Philosophy", null, ["#2f4a35", "#e7e3cf", "#1d2f22"], "leaf", "en"],
    ["odyssey", "The Odyssey", "Homer", -700, 541, 27, "onhold", "Classics", null, ["#1e3d59", "#f5f0e1", "#ff6e40"], "sun", "en"],
    ["crime", "Crime and Punishment", "Fyodor Dostoevsky", 1866, 671, 0, "new", "Classics", null, ["#3b3b3b", "#e2d6c2", "#8c1c13"], "band", "en"],
    ["jane-eyre", "Jane Eyre", "Charlotte Brontë", 1847, 507, 0, "new", "Classics", null, ["#4a3b52", "#efe6f0", "#2b2030"], "oval", "en"],
    ["middlemarch", "Middlemarch", "George Eliot", 1871, 880, 3, "reading", "Classics", null, ["#6b4e2e", "#f3e9d8", "#3c2b18"], "column", "en"],
    ["dune-notes", "Notes on Deserts", "A. Khalil", 2019, 214, 0, "new", "Essays", null, ["#c9853f", "#fbf1e3", "#7a4615"], "sun", "en"],
    ["kafka", "The Metamorphosis", "Franz Kafka", 1915, 96, 100, "finished", "Classics", null, ["#d9d4c5", "#1f1f1f", "#9b9583"], "deco", "en"],
    ["art-of-war", "The Art of War", "Sun Tzu", -500, 112, 0, "new", "Philosophy", null, ["#8b1e1e", "#f2e8d5", "#4a0f0f"], "column", "en"],
    ["ar-poems", "ديوان المتنبي", "أبو الطيب المتنبي", 965, 390, 18, "reading", "عربي", null, ["#123c3a", "#e9dfc9", "#0a2321"], "arabesque", "ar"],
    ["ar-ayam", "الأيام", "طه حسين", 1929, 240, 0, "new", "عربي", null, ["#5c2a1b", "#f0e2c8", "#2e140c"], "arabesque", "ar"],
    ["sherlock-1", "A Study in Scarlet", "Arthur Conan Doyle", 1887, 188, 100, "finished", "Mystery", ["Sherlock Holmes", 1], ["#5b1416", "#efe2c9", "#2d0a0b"], "frame", "en"],
    ["sherlock-2", "The Sign of the Four", "Arthur Conan Doyle", 1890, 176, 34, "reading", "Mystery", ["Sherlock Holmes", 2], ["#1f3b2c", "#efe2c9", "#0f1e16"], "frame", "en"],
    ["sherlock-3", "The Hound of the Baskervilles", "Arthur Conan Doyle", 1902, 256, 0, "new", "Mystery", ["Sherlock Holmes", 3], ["#2c2c44", "#efe2c9", "#16162a"], "frame", "en"],
    ["time-machine", "The Time Machine", "H. G. Wells", 1895, 118, 0, "new", "Science Fiction", null, ["#0d1b2a", "#e0e1dd", "#415a77"], "rings", "en"],
    ["war-worlds", "The War of the Worlds", "H. G. Wells", 1898, 287, 56, "onhold", "Science Fiction", null, ["#3d0c02", "#f4d6a0", "#9c2f0a"], "rings", "en"],
    ["little-women", "Little Women", "Louisa May Alcott", 1868, 759, 0, "new", "Classics", null, ["#f2d0c9", "#5e3a3a", "#d9a5a0"], "oval", "en"],
    ["siddhartha", "Siddhartha", "Hermann Hesse", 1922, 152, 77, "reading", "Philosophy", null, ["#e0b04a", "#2b1e08", "#b5861f"], "sun", "en"],
  ].map(([id, title, author, year, pages, progress, status, folder, series, palette, style, lang], i) => ({
    id, title, author, year, pages, progress, status, folder, series, palette, style, lang,
    format: i % 7 === 3 ? "pdf" : i % 9 === 4 ? "mobi" : "epub",
    size: (0.3 + ((i * 37) % 50) / 10).toFixed(1) + " MB",
    added: `2026-${String(1 + (i % 10)).padStart(2, "0")}-${String(3 + ((i * 7) % 25)).padStart(2, "0")}`,
    lastRead: progress ? (i % 9 === 0 ? "yesterday" : `${1 + (i % 9)} days ago`) : null,
    rating: status === "finished" ? 4 + (i % 2) : 0,
    favorite: [0, 1, 4, 6, 15, 23].includes(i),
    minutesLeft: progress ? Math.round(((100 - progress) / 100) * pages * 1.6) : null,
    chapterMinutes: 4 + (i % 9),
    language: lang === "ar" ? "Arabic" : "English",
    publisher: ["Penguin Classics", "Standard Ebooks", "Project Gutenberg", "Oxford World's Classics", "Vintage"][i % 5],
    synopsis: null,
  }));

  const FOLDERS = [
    { name: "Classics", count: BOOKS.filter((b) => b.folder === "Classics").length, modified: "2 days ago" },
    { name: "Philosophy", count: BOOKS.filter((b) => b.folder === "Philosophy").length, modified: "1 week ago" },
    { name: "Mystery", count: 3, modified: "3 weeks ago" },
    { name: "Science Fiction", count: 2, modified: "1 month ago" },
    { name: "Horror", count: 1, modified: "2 months ago" },
    { name: "Essays", count: 1, modified: "5 days ago" },
    { name: "عربي", count: 2, modified: "today" },
    { name: "News", count: 0, modified: "never" },
  ];
  const LOOSE_FILES = [
    { name: "Kindle_User_Guide.pdf", size: "2.4 MB", modified: "Jan 3" },
    { name: "article-longread.html", size: "180 KB", modified: "yesterday" },
    { name: "notes.txt", size: "4 KB", modified: "today" },
    { name: "comic-chapter-12.cbz", size: "38 MB", modified: "Oct 21" },
  ];

  const COLLECTIONS = [
    { name: "Favorites", ids: BOOKS.filter((b) => b.favorite).map((b) => b.id) },
    { name: "To read this winter", ids: ["walden", "crime", "jane-eyre", "middlemarch", "little-women"] },
    { name: "Sherlock Holmes", ids: ["sherlock-1", "sherlock-2", "sherlock-3"] },
    { name: "Arabic", ids: ["ar-poems", "ar-ayam", "animal-farm"] },
  ];

  const HISTORY = ["animal-farm", "frankenstein", "pride", "meditations", "siddhartha", "sherlock-2", "moby", "ar-poems", "war-worlds", "odyssey", "dracula", "kafka", "middlemarch"];

  // reading statistics (minutes per day, last 30 days, newest last)
  const r = rng("stats");
  const DAILY = Array.from({ length: 30 }, (_, i) => Math.round((i % 7 === 5 ? 8 : 18) + r() * 52));
  const STATS = {
    today: 35, streak: 12, longestStreak: 31, totalHours: 214, booksFinished: 17, pagesThisWeek: 412, avgPerDay: 38,
    pagesPerHour: 46, daily: DAILY, weekdays: ["M", "T", "W", "T", "F", "S", "S"],
    monthly: [11, 14, 9, 19, 23, 17, 21, 26, 18, 24, 29, 12],
    milestones: [
      { icon: "trophy", text: "Finished Dracula", when: "3 days ago" },
      { icon: "flame", text: "12-day reading streak", when: "today" },
      { icon: "book-open-check", text: "200 hours of reading", when: "last week" },
      { icon: "highlighter", text: "100th highlight", when: "Oct 30" },
    ],
  };

  const HIGHLIGHTS = [
    { book: "animal-farm", chapter: "Chapter I", page: 4, text: "Man is the only creature that consumes without producing.", note: "", color: "yellow", date: "Nov 18" },
    { book: "animal-farm", chapter: "Chapter II", page: 15, text: "The animals were happy as they had never conceived it possible to be.", note: "irony starts here", color: "yellow", date: "Nov 18" },
    { book: "meditations", chapter: "Book IV", page: 61, text: "Very little is needed to make a happy life; it is all within yourself, in your way of thinking.", note: "", color: "yellow", date: "Nov 12" },
    { book: "frankenstein", chapter: "Letter 4", page: 22, text: "Nothing is so painful to the human mind as a great and sudden change.", note: "", color: "yellow", date: "Nov 2" },
    { book: "siddhartha", chapter: "The River", page: 103, text: "Wisdom cannot be imparted. Wisdom that a wise man attempts to impart always sounds like foolishness.", note: "re-read", color: "yellow", date: "Oct 28" },
  ];

  const QUOTES = [
    ["The best books are those that tell you what you know already.", "George Orwell"],
    ["A reader lives a thousand lives before he dies.", "George R. R. Martin"],
    ["Until I feared I would lose it, I never loved to read.", "Harper Lee"],
    ["There is no friend as loyal as a book.", "Ernest Hemingway"],
  ];

  const SEARCH_HISTORY = ["Orwell", "Brave", "gothic", "stoic", "Holmes"];
  const DICTIONARIES = ["Oxford Dictionary of English", "Wiktionary EN→AR (offline)", "WordNet 3.1", "Al-Mawrid Mini"];

  window.DB = { BOOKS, FOLDERS, LOOSE_FILES, COLLECTIONS, HISTORY, STATS, HIGHLIGHTS, QUOTES, SEARCH_HISTORY, DICTIONARIES,
    book: (id) => BOOKS.find((b) => b.id === id) || BOOKS[0],
    current: () => BOOKS[0],
  };

  /* ---------------- random prose ---------------- */
  const W = ("the of and to in a was that he it his with as had for on at by her she but not they which be from this were all one so their them " +
    "there would been when what if into out no up its more about some time could who said only now than then like other over such our " +
    "night house field morning window long old little great light dark water road hand voice heart door silence wind evening farm " +
    "remembered walked turned looked believed wondered carried watched opened followed waited listened answered seemed began " +
    "quiet heavy distant narrow pale bright cold slow sudden careful strange familiar gentle tired restless golden hollow").split(" ");
  const NAMES = ["Mr. Jones", "Clover", "Benjamin", "Elena", "the old major", "Marguerite", "Tomas", "the stranger", "Ada", "the miller"];
  function sentence(rand) {
    const n = 8 + Math.floor(rand() * 18);
    const words = [];
    for (let i = 0; i < n; i++) words.push(rand() < 0.05 ? NAMES[Math.floor(rand() * NAMES.length)] : W[Math.floor(Math.pow(rand(), 1.6) * W.length)]);
    if (n > 12 && rand() < 0.5) words[Math.floor(n / 2)] += ",";
    let s = words.join(" ");
    return s.charAt(0).toUpperCase() + s.slice(1) + (rand() < 0.08 ? "?" : ".");
  }
  function paragraph(rand) {
    const n = 2 + Math.floor(rand() * 5);
    let p = Array.from({ length: n }, () => sentence(rand)).join(" ");
    if (rand() < 0.18) p = `“${sentence(rand)}” ${p}`;
    return p;
  }
  const ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"];
  window.TextGen = {
    chapters: (bookId) => { const n = 6 + (bookId.length % 6); return Array.from({ length: n }, (_, i) => ({ title: `Chapter ${ROMAN[i]}`, page: 1 + i * 11 })); },
    /** array of paragraphs for a chapter */
    chapter: (bookId, idx = 0, count = 14) => { const rand = rng(bookId + ":" + idx); return Array.from({ length: count }, () => paragraph(rand)); },
    paragraph: (seed) => paragraph(rng(seed)),
    synopsis: (book) => { const rand = rng("syn" + book.id); return [sentence(rand), sentence(rand), sentence(rand)].join(" "); },
  };

  /* ---------------- generated covers (original typographic art) ---------------- */
  const wrap = (text, max) => { const out = []; let line = ""; for (const w of text.split(" ")) { if ((line + " " + w).trim().length > max) { out.push(line.trim()); line = w; } else line += " " + w; } if (line.trim()) out.push(line.trim()); return out; };
  function cover(b) {
    const [bg, fg, ac] = b.palette;
    const lines = wrap(b.title.replace(/\s*\(.*\)/, ""), b.lang === "ar" ? 10 : 11).slice(0, 4);
    const author = b.author.split(";")[0];
    const ff = b.lang === "ar" ? "'Noto Naskh Arabic', serif" : "'Playfair Display', Georgia, serif";
    const t0 = 118 - lines.length * 13;
    const title = lines.map((l, i) => `<text x="100" y="${t0 + i * 27}" font-family="${ff}" font-size="${l.length > 9 ? 21 : 25}" font-weight="600" fill="${fg}" text-anchor="middle">${App.esc(l)}</text>`).join("");
    const by = `<text x="100" y="266" font-family="Inter, sans-serif" font-size="${author.length > 16 ? 8 : 10}" letter-spacing="${author.length > 16 ? 1.2 : 2}" fill="${fg}" opacity=".85" text-anchor="middle">${App.esc(author.toUpperCase())}</text>`;
    const art = {
      band: `<rect y="168" width="200" height="56" fill="${ac}"/><rect y="170" width="200" height="2" fill="${fg}" opacity=".5"/><rect y="220" width="200" height="2" fill="${fg}" opacity=".5"/>`,
      frame: `<rect x="12" y="12" width="176" height="276" fill="none" stroke="${fg}" stroke-width="1.2" opacity=".7"/><rect x="18" y="18" width="164" height="264" fill="none" stroke="${fg}" stroke-width=".6" opacity=".5"/><circle cx="100" cy="196" r="22" fill="none" stroke="${fg}" opacity=".6"/><circle cx="100" cy="196" r="3" fill="${fg}"/>`,
      deco: `${Array.from({ length: 9 }, (_, i) => `<line x1="100" y1="300" x2="${i * 25}" y2="150" stroke="${fg}" stroke-width=".8" opacity=".55"/>`).join("")}<circle cx="100" cy="300" r="60" fill="${ac}" opacity=".9"/>`,
      oval: `<ellipse cx="100" cy="112" rx="78" ry="64" fill="none" stroke="${ac}" stroke-width="2"/><path d="M60 200 q40 -22 80 0" stroke="${fg}" fill="none" opacity=".6"/><circle cx="100" cy="206" r="2.5" fill="${fg}"/>`,
      wave: `${Array.from({ length: 6 }, (_, i) => `<path d="M0 ${180 + i * 14} q25 -10 50 0 t50 0 t50 0 t50 0" stroke="${fg}" fill="none" opacity="${0.7 - i * 0.1}"/>`).join("")}`,
      column: `<rect x="86" y="160" width="28" height="80" fill="${fg}" opacity=".18"/><rect x="78" y="154" width="44" height="8" fill="${fg}" opacity=".3"/><rect x="78" y="238" width="44" height="8" fill="${fg}" opacity=".3"/>`,
      leaf: `<path d="M100 240 C60 200 70 160 100 150 C130 160 140 200 100 240 Z" fill="${ac}" stroke="${fg}" stroke-width=".8" opacity=".9"/><line x1="100" y1="150" x2="100" y2="244" stroke="${fg}" opacity=".6"/>`,
      sun: `<circle cx="100" cy="200" r="34" fill="${ac}"/>${Array.from({ length: 12 }, (_, i) => { const a = (i / 12) * Math.PI * 2; return `<line x1="${100 + Math.cos(a) * 42}" y1="${200 + Math.sin(a) * 42}" x2="${100 + Math.cos(a) * 54}" y2="${200 + Math.sin(a) * 54}" stroke="${fg}" stroke-width="1.4" opacity=".7"/>`; }).join("")}`,
      rings: `${[52, 40, 28, 16].map((r, i) => `<circle cx="100" cy="200" r="${r}" fill="none" stroke="${i % 2 ? ac : fg}" stroke-width="1.4" opacity=".75"/>`).join("")}`,
      arabesque: `<g transform="translate(100 200)" fill="none" stroke="${fg}" opacity=".65">${Array.from({ length: 8 }, (_, i) => `<rect x="-26" y="-26" width="52" height="52" transform="rotate(${i * 11.25})"/>`).join("")}</g>`,
    }[b.style] || "";
    return `<svg viewBox="0 0 200 300" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMidYMid slice"><rect width="200" height="300" fill="${bg}"/>${art}${title}${by}<rect width="6" height="300" fill="#000" opacity=".12"/></svg>`;
  }
  window.Cover = {
    svg: cover,
    /** full cover element with optional badge */
    html: (b, opts = {}) => `<div class="ko-cover ${opts.cls || ""}">${cover(b)}${opts.badge ? `<span class="badge ko-badge ${opts.badgeCls || ""}">${opts.badge}</span>` : ""}</div>`,
  };
})();
