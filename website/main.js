// Tabs + scroll reveal, no dependency.
(function () {
  var tabs = Array.prototype.slice.call(document.querySelectorAll('[role="tab"]'));
  var panels = tabs.map(function (t) { return document.getElementById(t.getAttribute("aria-controls")); });

  function select(tab, focus) {
    tabs.forEach(function (t) {
      var on = t === tab;
      t.setAttribute("aria-selected", on ? "true" : "false");
      t.tabIndex = on ? 0 : -1;
      if (focus && on) t.focus();
    });
    panels.forEach(function (p) {
      if (!p) return;
      p.hidden = p.getAttribute("aria-labelledby") !== tab.id;
    });
  }

  tabs.forEach(function (tab, i) {
    tab.addEventListener("click", function () { select(tab, false); });
    tab.addEventListener("keydown", function (e) {
      var next = null;
      if (e.key === "ArrowRight") next = tabs[(i + 1) % tabs.length];
      if (e.key === "ArrowLeft") next = tabs[(i - 1 + tabs.length) % tabs.length];
      if (e.key === "Home") next = tabs[0];
      if (e.key === "End") next = tabs[tabs.length - 1];
      if (next) { e.preventDefault(); select(next, true); }
    });
  });

  // FAQ accordion: single-open, smooth grid-rows animation
  var faqItems = Array.prototype.slice.call(document.querySelectorAll("[data-accordion] .faq-item"));
  faqItems.forEach(function (item) {
    var btn = item.querySelector(".faq-q");
    if (!btn) return;
    btn.addEventListener("click", function () {
      var willOpen = !item.classList.contains("open");
      faqItems.forEach(function (other) {
        other.classList.remove("open");
        var b = other.querySelector(".faq-q");
        if (b) b.setAttribute("aria-expanded", "false");
      });
      if (willOpen) {
        item.classList.add("open");
        btn.setAttribute("aria-expanded", "true");
      }
    });
  });

  // AI chat widget → opens ChatGPT with portfolio + repo context
  var CHAT_BASE = "This is a public portfolio site published by its owner. Start by reading https://hongduc.dev/llms.txt, then tell me about Nguyen Hong Duc (hongducdev), a Front End programmer at PixelArt Team. Other sources: https://hongduc.dev, https://github.com/hongducdev, https://x.com/hongducdev. The user has a question about BooxBook (https://github.com/hongducdev/booxbook.koplugin), a KOReader plugin for offline reading on e-readers: Vietnamese RSS news (17 outlets, 633 feeds), web novels from 6 sources (DocLN, Wattpad, Sangtacviet, MeTruyenCV, TVTruyen, TruyenFull), comic CBZ, EPUB export and Wi-Fi book transfer. Install: download booxbook.koplugin.zip from the Release page, extract and copy the booxbook.koplugin folder to /sdcard/koreader/plugins/, restart KOReader, enable it under Tools, then open Tools - BooxBook. Docs: docs/usage.md and docs/news-categories.md in the repo. Answer concisely in Vietnamese. User question: ";
  var fab = document.getElementById("chat-fab");
  var panel = document.getElementById("chat-panel");
  var closeBtn = document.getElementById("chat-close");
  var input = document.getElementById("chat-input");
  var go = document.getElementById("chat-go");
  function chatUrl(q) {
    return "https://chatgpt.com/?prompt=" + encodeURIComponent(CHAT_BASE + (q || "How do I install and use BooxBook?"));
  }
  function syncGo() { if (go && input) go.href = chatUrl(input.value.trim()); }
  function openChat() {
    if (!fab || !panel) return;
    panel.hidden = false;
    requestAnimationFrame(function () { panel.classList.add("open"); });
    fab.setAttribute("aria-expanded", "true");
    fab.setAttribute("aria-label", "Đóng khung hỏi AI");
    if (input) input.focus();
  }
  function closeChat() {
    if (!fab || !panel) return;
    panel.classList.remove("open");
    fab.setAttribute("aria-expanded", "false");
    fab.setAttribute("aria-label", "Mở khung hỏi AI");
    var hide = function () { panel.hidden = true; };
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) hide();
    else setTimeout(hide, 250);
    fab.focus();
  }
  if (fab && panel) {
    fab.addEventListener("click", function () {
      if (panel.hidden) openChat(); else closeChat();
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && !panel.hidden) closeChat();
    });
    document.addEventListener("click", function (e) {
      if (!panel.hidden && !panel.contains(e.target) && !fab.contains(e.target)) closeChat();
    });
  }
  if (closeBtn) closeBtn.addEventListener("click", closeChat);
  if (input) input.addEventListener("input", syncGo);
  var chips = document.querySelectorAll(".chat-chips button");
  chips.forEach(function (chip) {
    chip.addEventListener("click", function () {
      if (input) { input.value = chip.textContent.trim(); syncGo(); input.focus(); }
    });
  });
  syncGo();

  // Reveal on scroll
  var els = document.querySelectorAll(".feat, .steps li, .release-box, .note, .panels article, .table-wrap, .faq-item, .cta-card");
  els.forEach(function (el) { el.classList.add("reveal"); });
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
      });
    }, { threshold: 0.12 });
    els.forEach(function (el) { io.observe(el); });
  } else {
    els.forEach(function (el) { el.classList.add("in"); });
  }
})();
