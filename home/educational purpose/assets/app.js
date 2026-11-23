/* W8 teardown — interactions */
(function () {
  "use strict";

  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const header = $(".site-header");
  const docEl = document.documentElement;

  /* ---------------- theme ---------------- */
  const themeBtn = $("#themeToggle");
  function applyTheme(theme) {
    docEl.dataset.theme = theme;
    try { localStorage.setItem("w8-theme", theme); } catch (e) {}
    if (themeBtn) {
      const next = theme === "dark" ? "light" : "dark";
      themeBtn.setAttribute("aria-label", "Switch to " + next + " theme");
      themeBtn.setAttribute("title", "Switch to " + next + " theme");
    }
  }
  if (themeBtn) {
    themeBtn.addEventListener("click", () => {
      applyTheme(docEl.dataset.theme === "dark" ? "light" : "dark");
    });
    applyTheme(docEl.dataset.theme || "dark");
  }

  /* ---------------- mobile nav ---------------- */
  const menuBtn = $("#menuToggle");
  const mobileNav = $("#mobileNav");
  function setMenu(open) {
    if (!menuBtn || !mobileNav) return;
    menuBtn.setAttribute("aria-expanded", String(open));
    mobileNav.hidden = !open;
  }
  if (menuBtn && mobileNav) {
    menuBtn.addEventListener("click", () => setMenu(mobileNav.hidden));
    $$("a", mobileNav).forEach((a) => a.addEventListener("click", () => setMenu(false)));
    window.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && !mobileNav.hidden) { setMenu(false); menuBtn.focus(); }
    });
    window.addEventListener("resize", () => {
      if (window.innerWidth > 1080) setMenu(false);
    });
  }

  /* ---------------- header + progress ---------------- */
  const progress = $("#progressBar");
  let ticking = false;
  function onScroll() {
    const y = window.scrollY || docEl.scrollTop;
    if (header) header.classList.toggle("is-scrolled", y > 6);
    if (progress) {
      const max = docEl.scrollHeight - window.innerHeight;
      progress.style.width = (max > 0 ? Math.min(100, (y / max) * 100) : 0) + "%";
    }
    updateActiveSection();
    ticking = false;
  }
  window.addEventListener("scroll", () => {
    if (!ticking) { ticking = true; requestAnimationFrame(onScroll); }
  }, { passive: true });

  /* ---------------- table of contents ---------------- */
  const sections = $$("main section[id]").filter((s) => $("h2", s));
  const toc = $("#toc");
  const tocMobile = $("#tocMobile");
  const tocLinks = [];

  function buildToc() {
    if (!toc || !sections.length) return;
    sections.forEach((section, i) => {
      const h2 = $("h2", section);
      const num = section.dataset.num || String(i + 1).padStart(2, "0");
      const title = h2.textContent.trim();
      const link = document.createElement("a");
      link.href = "#" + section.id;
      link.innerHTML = '<span class="toc-num">' + num + "</span><span>" + escapeHtml(title) + "</span>";
      toc.appendChild(link);
      tocLinks.push({ link, section });
      if (tocMobile) {
        const clone = link.cloneNode(true);
        tocMobile.appendChild(clone);
      }
    });
    if (!tocLinks.length) {
      toc.innerHTML = '<p class="toc-empty">No sections on this page.</p>';
    }
    updateActiveSection();
  }

  function updateActiveSection() {
    if (!tocLinks.length) return;
    const offset = (header ? header.offsetHeight : 64) + 56;
    const y = (window.scrollY || docEl.scrollTop) + offset;
    let current = tocLinks[0];
    for (const item of tocLinks) {
      if (item.section.getBoundingClientRect().top + window.scrollY <= y) current = item;
    }
    if ((window.innerHeight + window.scrollY) >= docEl.scrollHeight - 8) {
      current = tocLinks[tocLinks.length - 1];
    }
    tocLinks.forEach(({ link }) => {
      const active = link.getAttribute("href") === "#" + current.section.id;
      link.classList.toggle("is-active", active);
      if (active) link.setAttribute("aria-current", "location");
      else link.removeAttribute("aria-current");
    });
    if (tocMobile) {
      $$("a", tocMobile).forEach((a) => {
        a.classList.toggle("is-active", a.getAttribute("href") === "#" + current.section.id);
      });
    }
  }

  function escapeHtml(str) {
    return String(str).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }

  /* ---------------- copy buttons ---------------- */
  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise((resolve, reject) => {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand("copy") ? resolve() : reject(new Error("copy failed")); }
      catch (e) { reject(e); }
      finally { ta.remove(); }
    });
  }

  function flashButton(btn, label) {
    const original = btn.dataset.label || btn.textContent;
    btn.dataset.label = original;
    btn.textContent = label;
    btn.classList.add("is-copied");
    window.setTimeout(() => {
      btn.textContent = original;
      btn.classList.remove("is-copied");
    }, 1400);
  }

  $$("[data-copy-code]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const box = btn.closest(".code");
      const pre = box && $("pre", box);
      if (!pre) return;
      copyText(pre.innerText.replace(/\n$/, "")).then(() => flashButton(btn, "Copied")).catch(() => flashButton(btn, "Failed"));
    });
  });

  $$("[data-copy-row]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const row = btn.closest(".ioc");
      const value = row && $(".ioc-value", row);
      if (!value) return;
      copyText(value.textContent.trim()).then(() => flashButton(btn, "Copied")).catch(() => flashButton(btn, "Failed"));
    });
  });

  /* ---------------- sequence player ---------------- */
  $$("[data-seq]").forEach((seq) => {
    const tabs = $$('[role="tab"]', seq);
    const panels = $$('[role="tabpanel"]', seq);
    const prev = $("[data-seq-prev]", seq);
    const next = $("[data-seq-next]", seq);
    let index = 0;
    function show(i) {
      index = Math.max(0, Math.min(tabs.length - 1, i));
      tabs.forEach((tab, ti) => {
        const selected = ti === index;
        tab.setAttribute("aria-selected", String(selected));
        tab.tabIndex = selected ? 0 : -1;
      });
      panels.forEach((panel, pi) => { panel.hidden = pi !== index; });
      if (prev) prev.disabled = index === 0;
      if (next) next.disabled = index === tabs.length - 1;
    }
    tabs.forEach((tab, i) => {
      tab.addEventListener("click", () => show(i));
      tab.addEventListener("keydown", (e) => {
        if (e.key === "ArrowDown" || e.key === "ArrowRight") { e.preventDefault(); show(i + 1); tabs[Math.min(tabs.length - 1, i + 1)].focus(); }
        if (e.key === "ArrowUp" || e.key === "ArrowLeft") { e.preventDefault(); show(i - 1); tabs[Math.max(0, i - 1)].focus(); }
        if (e.key === "Home") { e.preventDefault(); show(0); tabs[0].focus(); }
        if (e.key === "End") { e.preventDefault(); show(tabs.length - 1); tabs[tabs.length - 1].focus(); }
      });
    });
    if (prev) prev.addEventListener("click", () => show(index - 1));
    if (next) next.addEventListener("click", () => show(index + 1));
    show(0);
  });

  /* ---------------- responsive table labels ---------------- */
  document.querySelectorAll(".table-wrap table").forEach((table) => {
    const heads = Array.from(table.querySelectorAll("thead th")).map((th) => th.textContent.trim());
    if (!heads.length) return;
    table.querySelectorAll("tbody tr").forEach((tr) => {
      Array.from(tr.children).forEach((td, i) => {
        if (heads[i]) td.setAttribute("data-label", heads[i]);
      });
    });
  });

  /* ---------------- table keyboard scroll ---------------- */
  $$(".table-wrap").forEach((wrap) => {
    if (wrap.scrollWidth > wrap.clientWidth + 4) {
      wrap.tabIndex = 0;
      wrap.setAttribute("role", "region");
      const caption = $("caption", wrap);
      wrap.setAttribute("aria-label", caption ? caption.textContent.trim() : "Scrollable table");
    }
  });

  /* ---------------- search ---------------- */
  const searchBtn = $("#searchOpen");
  const index = Array.isArray(window.SEARCH_INDEX) ? window.SEARCH_INDEX : [];
  let modal, input, resultsBox, selected = 0, currentResults = [];

  function buildSearch() {
    if (!searchBtn) return;
    modal = document.createElement("div");
    modal.className = "search-modal";
    modal.id = "searchModal";
    modal.hidden = true;
    modal.innerHTML =
      '<div class="search-panel" role="dialog" aria-modal="true" aria-labelledby="searchLabel">' +
        '<div class="search-bar">' +
          '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><circle cx="11" cy="11" r="7"></circle><path d="m20 20-3.5-3.5"></path></svg>' +
          '<label class="sr-only" id="searchLabel" for="searchInput">Search the teardown</label>' +
          '<input id="searchInput" type="text" placeholder="Search sections, endpoints, IOCs…" autocomplete="off" spellcheck="false">' +
          '<kbd>Esc</kbd>' +
        '</div>' +
        '<div class="search-results" id="searchResults" role="listbox" aria-label="Search results"></div>' +
        '<div class="search-foot"><span>W8 teardown index</span><span class="keys"><kbd>↑</kbd><kbd>↓</kbd> navigate <kbd>↵</kbd> open</span></div>' +
      '</div>';
    document.body.appendChild(modal);
    input = $("#searchInput", modal);
    resultsBox = $("#searchResults", modal);

    modal.addEventListener("click", (e) => { if (e.target === modal) closeSearch(); });
    input.addEventListener("input", () => renderSearch(input.value));
    input.addEventListener("keydown", onSearchKey);
    searchBtn.addEventListener("click", openSearch);
  }

  function openSearch() {
    if (!modal) return;
    modal.hidden = false;
    document.body.style.overflow = "hidden";
    input.value = "";
    renderSearch("");
    window.setTimeout(() => input.focus(), 20);
  }
  function closeSearch() {
    if (!modal) return;
    modal.hidden = true;
    document.body.style.overflow = "";
    if (searchBtn) searchBtn.focus();
  }

  function scoreEntry(entry, tokens) {
    const hay = (entry.t + " " + entry.d + " " + entry.k + " " + entry.p).toLowerCase();
    for (const t of tokens) if (!hay.includes(t)) return -1;
    let score = 0;
    const title = entry.t.toLowerCase();
    const keys = entry.k.toLowerCase();
    for (const t of tokens) {
      if (title.startsWith(t)) score += 14;
      else if (title.includes(t)) score += 9;
      if (keys.includes(t)) score += 4;
      if (entry.d.toLowerCase().includes(t)) score += 2;
      if (entry.p.toLowerCase().includes(t)) score += 1;
    }
    return score;
  }

  function highlight(text, tokens) {
    let out = escapeHtml(text);
    tokens.forEach((t) => {
      if (!t) return;
      const safe = t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      out = out.replace(new RegExp("(" + safe + ")", "ig"), "<mark>$1</mark>");
    });
    return out;
  }

  function renderSearch(query) {
    if (!resultsBox) return;
    const q = query.trim().toLowerCase();
    const tokens = q ? q.split(/\s+/).filter(Boolean) : [];
    currentResults = index
      .map((entry) => ({ entry, score: tokens.length ? scoreEntry(entry, tokens) : 1 }))
      .filter((r) => r.score >= 0)
      .sort((a, b) => b.score - a.score || a.entry.t.localeCompare(b.entry.t))
      .slice(0, 14)
      .map((r) => r.entry);

    if (!currentResults.length) {
      resultsBox.innerHTML = '<div class="search-empty">No matches for “' + escapeHtml(query) + '”. Try “apk”, “login”, “telegram”, “IOC”.</div>';
      selected = 0;
      return;
    }
    selected = 0;
    resultsBox.innerHTML = currentResults.map((entry, i) =>
      '<a class="search-result' + (i === 0 ? " is-selected" : "") + '" role="option" aria-selected="' + (i === 0) + '" href="' + entry.p + "#" + entry.h + '">' +
        '<span class="sr-meta">' + escapeHtml(entry.page) + " · " + escapeHtml(entry.h) + "</span>" +
        '<span class="sr-title">' + highlight(entry.t, tokens) + "</span>" +
        '<span class="sr-desc">' + highlight(entry.d, tokens) + "</span>" +
      "</a>"
    ).join("");
    $$(".search-result", resultsBox).forEach((a) => {
      a.addEventListener("mousemove", () => {
        const all = $$(".search-result", resultsBox);
        selected = all.indexOf(a);
        all.forEach((x, i) => { x.classList.toggle("is-selected", i === selected); x.setAttribute("aria-selected", String(i === selected)); });
      });
      a.addEventListener("click", () => { modal.hidden = true; document.body.style.overflow = ""; });
    });
  }

  function moveSelection(delta) {
    const all = $$(".search-result", resultsBox);
    if (!all.length) return;
    selected = (selected + delta + all.length) % all.length;
    all.forEach((a, i) => { a.classList.toggle("is-selected", i === selected); a.setAttribute("aria-selected", String(i === selected)); });
    all[selected].scrollIntoView({ block: "nearest" });
  }

  function onSearchKey(e) {
    if (e.key === "Escape") { e.preventDefault(); closeSearch(); return; }
    if (e.key === "ArrowDown") { e.preventDefault(); moveSelection(1); return; }
    if (e.key === "ArrowUp") { e.preventDefault(); moveSelection(-1); return; }
    if (e.key === "Enter") {
      const all = $$(".search-result", resultsBox);
      if (all[selected]) { e.preventDefault(); window.location.href = all[selected].href; }
    }
  }

  buildSearch();

  const initialQuery = new URLSearchParams(location.search).get("q");
  if (initialQuery && modal) {
    openSearch();
    input.value = initialQuery;
    renderSearch(initialQuery);
  }

  window.addEventListener("keydown", (e) => {
    const tag = (e.target.tagName || "").toLowerCase();
    const typing = tag === "input" || tag === "textarea" || e.target.isContentEditable;
    if ((e.key === "k" || e.key === "K") && (e.metaKey || e.ctrlKey)) {
      e.preventDefault(); if (modal) { if (modal.hidden) openSearch(); else input.focus(); }
      return;
    }
    if (e.key === "/" && !typing && modal && modal.hidden) {
      e.preventDefault(); openSearch();
    }
    if (e.key === "Escape" && modal && !modal.hidden) closeSearch();
  });

  /* ---------------- init ---------------- */
  buildToc();
  onScroll();
})();
