// Pages: lays the rendered document out on fixed-size pages (US Letter or A4), with numbered
// thumbnails on the left, the way Preview shows a PDF. Markdown has no pages, so pages are derived
// from the current content, font size and page size; nothing is ever written back to the source.
(function (root) {
  "use strict";
  if (typeof document === "undefined") return;

  var SIZES = { letter: { w: 816, h: 1056, name: "US Letter" }, a4: { w: 794, h: 1123, name: "A4" } };
  var MARGIN = 96; // one inch on every side
  var GUTTER = 24; // space around pages on the desk
  var MIN_ZOOM = 0.25, MAX_ZOOM = 4;
  var ZOOM_STEPS = [0.25, 0.33, 0.5, 0.67, 0.75, 0.85, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4];

  var state = {
    paged: true, size: "letter", sidebar: true, sidebarWidth: 168,
    spread: false, // two pages side by side, like an open book
    tab: "pages", // what the left sidebar shows: "pages" (thumbnails) or "notes" 
    zoomMode: "auto", // auto (the whole page, or both pages, fit in the window), fitWidth, fitPage, manual
    zoom: 1
  };
  var pages = [];       // .page elements in order
  var current = 0;      // index of the current page
  var zoom = 1;         // the zoom actually applied
  var docHeight = 0;    // unscaled height of the page stack
  var layoutRevision = 0;
  var imgSizes = {};    // natural sizes of images already loaded, so relayout doesn't loop
  var thumbObserver = null;
  var rerenderTimer = 0;

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function post(msg) {
    if (root.webkit && root.webkit.messageHandlers && root.webkit.messageHandlers.review) {
      root.webkit.messageHandlers.review.postMessage(msg);
    } else if (root.mdTestLog) {
      root.mdTestLog.push(msg);
    }
  }

  function size() { return SIZES[state.size] || SIZES.letter; }
  function contentHeight() { return size().h - 2 * MARGIN; }
  function sidebarShown() { return state.sidebar && window.innerWidth >= 640 && (state.paged || state.tab === "notes"); }
  function tab() { return state.paged ? state.tab : "notes"; }

  // ---------------------------------------------------------------------------------------------
  // Splitting blocks that don't fit on the rest of a page

  var ATOMIC = /^(H[1-6]|HR|IMG|TR|SVG|INPUT|BUTTON|VIDEO|IFRAME)$/;
  var BLOCKISH = /^(P|UL|OL|LI|PRE|BLOCKQUOTE|DIV|TABLE|THEAD|TBODY|TR|H[1-6]|HR)$/;

  function lineHeight(e) {
    var lh = parseFloat(getComputedStyle(e).lineHeight);
    return isFinite(lh) && lh > 0 ? lh : 24;
  }

  function hasBlockChildren(e) {
    for (var i = 0; i < e.children.length; i++) if (BLOCKISH.test(e.children[i].tagName)) return true;
    return false;
  }

  function bottomOf(node) {
    if (node.nodeType === 1) return node.getBoundingClientRect().bottom;
    var r = document.createRange();
    r.selectNodeContents(node);
    return r.getBoundingClientRect().bottom;
  }

  function meaningful(node) {
    return node.nodeType === 1 || (node.nodeType === 3 && /\S/.test(node.data));
  }

  function continuation(e) {
    var rest = e.cloneNode(false);
    rest.removeAttribute("id");
    rest.classList.add("pg-cont");
    rest.setAttribute("data-cont", "1");
    return rest;
  }

  /** Keeps what fits above `limit` in `e` and returns a new element with the rest, or null. */
  function trySplit(e, limit) {
    if (ATOMIC.test(e.tagName) || e.classList.contains("md-removed-tools")) return null;
    var top = e.getBoundingClientRect().top;
    var cs = getComputedStyle(e);
    // The kept part keeps its bottom padding and border (a code block's box, say), so leave room.
    limit -= (parseFloat(cs.paddingBottom) || 0) + (parseFloat(cs.borderBottomWidth) || 0);
    if (limit - top < 2 * lineHeight(e)) return null;
    return hasBlockChildren(e) ? splitChildren(e, limit) : splitText(e, limit);
  }

  function splitChildren(e, limit) {
    var nodes = Array.prototype.slice.call(e.childNodes);
    var seen = false;
    for (var k = 0; k < nodes.length; k++) {
      var n = nodes[k];
      if (!meaningful(n)) continue;
      if (bottomOf(n) <= limit) { seen = true; continue; }
      var restChild = n.nodeType === 1 ? trySplit(n, limit) : null;
      if (!restChild && !seen) return null; // nothing of this element fits
      var rest = continuation(e);
      if (e.tagName === "OL") {
        var before = 0;
        for (var j = 0; j < k; j++) if (nodes[j].nodeType === 1 && nodes[j].tagName === "LI") before++;
        rest.start = (e.start || 1) + before;
      }
      if (restChild) rest.appendChild(restChild);
      for (var m = restChild ? k + 1 : k; m < nodes.length; m++) rest.appendChild(nodes[m]);
      if (e.tagName === "TABLE") {
        var head = e.querySelector(":scope > thead");
        if (head && !rest.querySelector(":scope > thead")) rest.insertBefore(head.cloneNode(true), rest.firstChild);
      }
      return rest;
    }
    return null;
  }

  function textNodesIn(e) {
    var out = [];
    var w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT, null);
    var n;
    while ((n = w.nextNode())) if (n.data.length) out.push(n);
    return out;
  }

  /** Bottom of the line holding the character at `i` (glyph box plus half the line's leading),
      skipping collapsed whitespace, which has no box. */
  function charBottom(range, n, i, lh) {
    for (var j = i; j < n.data.length && j < i + 4; j++) {
      range.setStart(n, j);
      range.setEnd(n, j + 1);
      var r = range.getBoundingClientRect();
      if (r.height > 0) return r.bottom + Math.max(0, (lh - r.height) / 2);
    }
    return -Infinity;
  }

  function splitText(e, limit) {
    var nodes = textNodesIn(e);
    var range = document.createRange();
    var lh = lineHeight(e);
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      if (bottomOf(n) <= limit) continue;
      var lo = 0, hi = n.data.length - 1, at = n.data.length;
      while (lo <= hi) {
        var mid = (lo + hi) >> 1;
        if (charBottom(range, n, mid, lh) > limit) { at = mid; hi = mid - 1; } else lo = mid + 1;
      }
      if (at >= n.data.length) continue;
      if (i === 0 && at === 0) return null; // not even the first line fits
      var cut = document.createRange();
      cut.setStart(n, at);
      cut.setEnd(e, e.childNodes.length);
      var rest = continuation(e);
      rest.appendChild(cut.extractContents());
      var first = textNodesIn(rest)[0];
      if (first && !/^pre/.test(getComputedStyle(e).whiteSpace)) first.data = first.data.replace(/^[ \t]+/, "");
      if (!/\S/.test(rest.textContent || "") && !rest.querySelector("img")) return null;
      return rest;
    }
    return null;
  }

  // ---------------------------------------------------------------------------------------------
  // Pagination

  function newPage(doc) {
    var page = el("div", "page");
    var body = el("div", "page-body");
    var num = el("div", "page-num no-find");
    num.setAttribute("aria-hidden", "true");
    page.appendChild(body);
    page.appendChild(num);
    doc.appendChild(page);
    pages.push(page);
    num.textContent = String(pages.length);
    page.dataset.page = String(pages.length);
    return page;
  }

  function paginate(doc) {
    var queue = Array.prototype.slice.call(doc.childNodes).filter(function (n) { return n.nodeType === 1; });
    doc.textContent = "";
    pages = [];
    var page = newPage(doc);
    var guard = 0;
    while (queue.length && guard++ < 200000) {
      var b = queue.shift();
      var body = page.firstChild;
      body.appendChild(b);
      var limit = body.getBoundingClientRect().top + contentHeight();
      if (b.getBoundingClientRect().bottom <= limit + 0.5) continue;
      var isFirst = body.firstElementChild === b;
      var rest = trySplit(b, limit);
      if (rest) {
        queue.unshift(rest);
        page = newPage(doc);
        continue;
      }
      if (!isFirst) {
        body.removeChild(b);
        queue.unshift(b);
        // Keep a heading with the text that follows it.
        var prev = body.lastElementChild;
        if (prev && /^H[1-6]$/.test(prev.tagName) && body.firstElementChild !== prev) {
          body.removeChild(prev);
          queue.unshift(prev);
        }
        page = newPage(doc);
        continue;
      }
      // Too big for any page and can't be split (a huge table row, say): the page grows to fit
      // it rather than hiding anything.
      page.classList.add("page-tall");
      if (queue.length) page = newPage(doc);
    }
    var last = pages[pages.length - 1];
    if (pages.length > 1 && last && !last.firstChild.firstChild) { last.remove(); pages.pop(); }
  }

  // ---------------------------------------------------------------------------------------------
  // Zoom: scale the laid-out pages without changing them

  function availableWidth() {
    return Math.max(200, window.innerWidth - (sidebarShown() ? state.sidebarWidth : 0) - 2 * GUTTER);
  }

  /** Width of what's shown side by side: one page, or two with a gap. */
  function spreadWidth() { return state.spread ? 2 * size().w + GUTTER : size().w; }

  function topInsetForZoom() {
    var bar = document.getElementById("review-bar");
    return bar && !bar.hidden ? bar.offsetHeight : 0;
  }

  function computeZoom() {
    var s = size();
    var fitW = availableWidth() / spreadWidth();
    var fitP = Math.min(fitW, (window.innerHeight - topInsetForZoom() - 2 * GUTTER) / s.h);
    var z;
    switch (state.zoomMode) {
      case "fitWidth": z = fitW; break;
      case "manual": z = state.zoom; break;
      default: z = fitP; // "auto" and "fitPage": the whole page (or both pages) in view
    }
    return Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, z));
  }

  function applyZoom() {
    var doc = document.getElementById("doc");
    if (!doc || !state.paged) return;
    zoom = computeZoom();
    var w = spreadWidth();
    doc.classList.toggle("spread", state.spread);
    doc.style.width = w + "px";
    doc.style.transform = zoom === 1 ? "" : "scale(" + zoom + ")";
    docHeight = doc.offsetHeight;
    var left = Math.max(GUTTER, (availableWidth() + 2 * GUTTER - w * zoom) / 2);
    doc.style.marginLeft = left + "px";
    doc.style.marginRight = (w * (zoom - 1) + GUTTER) + "px";
    doc.style.marginBottom = (docHeight * (zoom - 1) + GUTTER) + "px";
    updateBar();
  }

  function clearPagedStyles(doc) {
    doc.style.width = doc.style.transform = doc.style.marginLeft = doc.style.marginRight = doc.style.marginBottom = "";
  }

  // ---------------------------------------------------------------------------------------------
  // Thumbnails

  function sidebar() {
    var nav = document.getElementById("thumbs");
    if (nav) return nav;
    nav = el("nav", "thumbs no-find");
    nav.id = "thumbs";
    nav.setAttribute("aria-label", "Sidebar");
    var tabs = el("div", "side-tabs");
    tabs.setAttribute("role", "tablist");
    [["pages", "Pages"], ["notes", "Notes"]].forEach(function (t) {
      var b = el("button", "side-tab", t[1]);
      b.type = "button";
      b.id = "side-tab-" + t[0];
      b.setAttribute("role", "tab");
      b.addEventListener("click", function () { root.mdShowSidebarTab(t[0]); });
      tabs.appendChild(b);
    });
    nav.appendChild(tabs);
    var list = el("ol", "thumb-list");
    list.setAttribute("aria-label", "Page thumbnails");
    list.id = "thumb-list";
    nav.appendChild(list);
    var grip = el("div", "thumb-grip");
    grip.setAttribute("aria-hidden", "true");
    nav.appendChild(grip);
    grip.addEventListener("pointerdown", function (ev) {
      ev.preventDefault();
      grip.setPointerCapture(ev.pointerId);
      function move(e) { setSidebarWidth(e.clientX); }
      function up() {
        grip.removeEventListener("pointermove", move);
        grip.removeEventListener("pointerup", up);
        saveLayout();
        applyZoom();
      }
      grip.addEventListener("pointermove", move);
      grip.addEventListener("pointerup", up);
    });
    list.addEventListener("keydown", function (e) {
      var buttons = Array.prototype.slice.call(list.querySelectorAll("button.thumb"));
      var i = buttons.indexOf(document.activeElement);
      if (i < 0) return;
      var to = -1;
      if (e.key === "ArrowDown" || e.key === "ArrowRight" || e.key === "PageDown") to = Math.min(buttons.length - 1, i + 1);
      else if (e.key === "ArrowUp" || e.key === "ArrowLeft" || e.key === "PageUp") to = Math.max(0, i - 1);
      else if (e.key === "Home") to = 0;
      else if (e.key === "End") to = buttons.length - 1;
      else if (e.key === "Escape") { e.preventDefault(); focusDocument(); return; }
      if (to < 0) return;
      e.preventDefault();
      buttons[to].focus();
      goTo(to, true);
    });
    document.body.appendChild(nav);
    return nav;
  }

  function showTab() {
    var nav = sidebar();
    var t = tab();
    nav.dataset.tab = t;
    ["pages", "notes"].forEach(function (name) {
      var b = document.getElementById("side-tab-" + name);
      if (!b) return;
      b.setAttribute("aria-selected", name === t ? "true" : "false");
      b.disabled = name === "pages" && !state.paged;
    });
  }

  function setSidebarWidth(w) {
    state.sidebarWidth = Math.round(Math.min(320, Math.max(110, w)));
    document.documentElement.style.setProperty("--thumbs-w", state.sidebarWidth + "px");
    document.documentElement.style.setProperty("--thumb-scale", String((state.sidebarWidth - 56) / size().w));
  }

  function focusDocument() {
    var page = pages[current];
    if (page) { page.tabIndex = -1; page.focus({ preventScroll: true }); }
  }

  function fillThumb(li) {
    if (li.dataset.rev === String(layoutRevision)) return;
    var i = Number(li.dataset.index);
    var page = pages[i];
    var inner = li.querySelector(".thumb-inner");
    if (!page || !inner) return;
    var copy = page.cloneNode(true);
    copy.removeAttribute("tabindex");
    var withIds = copy.querySelectorAll("[id]");
    for (var k = 0; k < withIds.length; k++) withIds[k].removeAttribute("id");
    var focusable = copy.querySelectorAll("a, button, input");
    for (var f = 0; f < focusable.length; f++) focusable[f].setAttribute("tabindex", "-1");
    inner.textContent = "";
    inner.appendChild(copy);
    li.dataset.rev = String(layoutRevision);
    li.classList.remove("thumb-pending");
  }

  function buildThumbs() {
    var nav = sidebar();
    var list = document.getElementById("thumb-list");
    // Rebuilding (after an edit or an image loads) shouldn't throw keyboard focus out of the list.
    var hadFocus = list.contains(document.activeElement);
    if (thumbObserver) thumbObserver.disconnect();
    list.textContent = "";
    if (!state.paged) return;
    thumbObserver = "IntersectionObserver" in root ? new IntersectionObserver(function (entries) {
      entries.forEach(function (en) { if (en.isIntersecting) fillThumb(en.target); });
    }, { root: nav, rootMargin: "400px 0px" }) : null;
    pages.forEach(function (p, i) {
      var li = el("li", "thumb-item thumb-pending");
      li.dataset.index = String(i);
      var b = el("button", "thumb");
      b.type = "button";
      b.setAttribute("aria-label", "Page " + (i + 1));
      var frame = el("div", "thumb-frame");
      frame.setAttribute("aria-hidden", "true");
      frame.appendChild(el("div", "thumb-inner"));
      b.appendChild(frame);
      var label = el("span", "thumb-num", String(i + 1));
      label.setAttribute("aria-hidden", "true");
      b.appendChild(label);
      b.addEventListener("click", function () {
        // WebKit doesn't focus a button on click, so the arrow keys wouldn't reach the list. Focus it.
        b.focus({ preventScroll: true });
        goTo(i, true);
      });
      li.appendChild(b);
      list.appendChild(li);
      if (thumbObserver) thumbObserver.observe(li); else fillThumb(li);
    });
    markCurrent(false);
    if (hadFocus) {
      var again = list.querySelectorAll("button.thumb")[current];
      if (again) again.focus({ preventScroll: true });
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Page bar: thumbnails toggle, previous / next, "Page 3 of 12", zoom

  function barButton(label, aria, onClick, cls) {
    var b = el("button", "pb-button" + (cls ? " " + cls : ""), label);
    b.type = "button";
    b.setAttribute("aria-label", aria);
    b.title = aria;
    b.addEventListener("click", onClick);
    return b;
  }

  function pageBar() {
    var bar = document.getElementById("page-bar");
    if (bar) return bar;
    bar = el("div", "page-bar no-find");
    bar.id = "page-bar";
    bar.setAttribute("role", "toolbar");
    bar.setAttribute("aria-label", "Pages");
    bar.appendChild(barButton("▤", "Show or hide page thumbnails", function () { root.mdPagesToggleSidebar(); }, "pb-thumbs"));
    var two = barButton("▯▯", "Show two pages side by side", function () { root.mdPagesSpread(!state.spread); }, "pb-spread");
    bar.appendChild(two);
    bar.appendChild(barButton("‹", "Previous page", function () { root.mdPageStep(-1); }));
    var label = el("label", "pb-label");
    label.appendChild(document.createTextNode("Page "));
    var input = el("input", "pb-input");
    input.id = "page-input";
    input.type = "text";
    input.inputMode = "numeric";
    input.setAttribute("aria-label", "Page number");
    input.autocomplete = "off";
    label.appendChild(input);
    var of = el("span", "pb-of");
    of.id = "page-of";
    label.appendChild(of);
    bar.appendChild(label);
    bar.appendChild(barButton("›", "Next page", function () { root.mdPageStep(1); }));
    var sep = el("span", "pb-sep");
    sep.setAttribute("aria-hidden", "true");
    bar.appendChild(sep);
    bar.appendChild(barButton("−", "Zoom out", function () { root.mdPagesZoom("out"); }));
    var z = barButton("100%", "Fit the page in the window", function () { root.mdPagesZoom("fitPage"); }, "pb-zoom");
    z.id = "page-zoom";
    bar.appendChild(z);
    bar.appendChild(barButton("+", "Zoom in", function () { root.mdPagesZoom("in"); }));
    input.addEventListener("keydown", function (e) {
      if (e.key === "Enter") {
        e.preventDefault();
        var n = parseInt(input.value, 10);
        if (!(n >= 1 && n <= pages.length)) {
          input.classList.add("pb-bad");
          announce("Enter a page number from 1 to " + pages.length);
          setTimeout(function () { input.classList.remove("pb-bad"); input.value = String(current + 1); input.select(); }, 900);
          return;
        }
        goTo(n - 1, true);
        focusDocument();
      } else if (e.key === "Escape") {
        e.preventDefault();
        e.stopPropagation();
        input.value = String(current + 1);
        focusDocument();
      }
    });
    input.addEventListener("blur", function () { input.value = String(current + 1); });
    document.body.appendChild(bar);
    return bar;
  }

  function updateBar() {
    var bar = pageBar();
    bar.hidden = !state.paged;
    if (!state.paged) return;
    var input = document.getElementById("page-input");
    if (document.activeElement !== input) input.value = String(current + 1);
    input.style.width = (String(pages.length).length + 1) + "ch";
    document.getElementById("page-of").textContent = " of " + pages.length;
    var z = document.getElementById("page-zoom");
    z.textContent = Math.round(zoom * 100) + "%";
    bar.querySelector(".pb-thumbs").setAttribute("aria-pressed", sidebarShown() ? "true" : "false");
    var two = bar.querySelector(".pb-spread");
    two.setAttribute("aria-pressed", state.spread ? "true" : "false");
    two.textContent = state.spread ? "▯▯" : "▯";
    two.title = state.spread ? "Show one page at a time" : "Show two pages side by side";
    two.setAttribute("aria-label", two.title);
  }

  var live = null;
  function announce(text) {
    if (!live) {
      live = el("div", "sr-only");
      live.setAttribute("aria-live", "polite");
      document.body.appendChild(live);
    }
    live.textContent = text;
  }

  // ---------------------------------------------------------------------------------------------
  // Current page and navigation

  /** The page holding the middle of the window, or the nearest one at the ends. */
  function pageAtCenter() {
    if (!pages.length) return 0;
    var mid = window.innerHeight / 2;
    var lo = 0, hi = pages.length - 1, ans = pages.length - 1;
    while (lo <= hi) {
      var m = (lo + hi) >> 1;
      if (pages[m].getBoundingClientRect().bottom >= mid) { ans = m; hi = m - 1; } else lo = m + 1;
    }
    if (window.scrollY <= 1) return 0;
    if (window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2) return pages.length - 1;
    return ans;
  }

  function markCurrent(scrollSidebar) {
    var items = document.querySelectorAll("#thumb-list button.thumb");
    var partner = state.spread ? (current % 2 === 0 ? current + 1 : current - 1) : -1;
    for (var i = 0; i < items.length; i++) {
      var on = i === current || i === partner; // both pages of a spread
      items[i].classList.toggle("thumb-current", on);
      if (on) items[i].setAttribute("aria-current", "page"); else items[i].removeAttribute("aria-current");
    }
    if (scrollSidebar && items[current] && sidebarShown()) {
      var nav = document.getElementById("thumbs");
      var r = items[current].getBoundingClientRect();
      var nr = nav.getBoundingClientRect();
      if (r.top < nr.top + 8 || r.bottom > nr.bottom - 8) {
        nav.scrollTop += r.top - nr.top - (nr.height - r.height) / 2;
      }
    }
    updateBar();
  }

  function goTo(i, announceIt) {
    if (!pages.length) return;
    current = Math.max(0, Math.min(pages.length - 1, i));
    var top = pages[current].getBoundingClientRect().top + window.scrollY - GUTTER;
    if (current === 0) top = 0;
    window.scrollTo(0, Math.max(0, top));
    markCurrent(true);
    if (announceIt) announce("Page " + (current + 1) + " of " + pages.length);
  }

  var scrollQueued = false;
  window.addEventListener("scroll", function () {
    if (!state.paged || scrollQueued) return;
    scrollQueued = true;
    requestAnimationFrame(function () {
      scrollQueued = false;
      var c = pageAtCenter();
      if (c !== current) { current = c; markCurrent(true); }
    });
  }, { passive: true });

  window.addEventListener("resize", function () {
    if (!state.paged) return;
    document.body.classList.toggle("thumbs-open", sidebarShown());
    if (state.zoomMode !== "manual") {
      var a = captureAnchor();
      applyZoom();
      restoreAnchor(a);
    } else applyZoom();
  });

  // ---------------------------------------------------------------------------------------------
  // Reading position, kept by text rather than by page number

  function captureAnchor() {
    var doc = document.getElementById("doc");
    if (!doc) return null;
    var top = topInset();
    var els = doc.querySelectorAll("[data-line]");
    var best = null, bestTop = Infinity;
    for (var i = 0; i < els.length; i++) {
      var r = els[i].getBoundingClientRect();
      if (r.height === 0 || r.bottom < top) continue;
      if (r.top >= top - 2 && r.top < bestTop) { best = els[i]; bestTop = r.top; }
      if (r.top > window.innerHeight) break;
    }
    if (!best) return { y: window.scrollY };
    var line = best.getAttribute("data-line");
    var same = doc.querySelectorAll('[data-line="' + line + '"]');
    return {
      y: window.scrollY, line: line, nth: Array.prototype.indexOf.call(same, best),
      text: (best.textContent || "").trim().slice(0, 60), dy: bestTop
    };
  }

  function restoreAnchor(a) {
    if (!a) return false;
    // At the very top, stay at the top (the change bar may have just appeared above the text).
    if (a.y <= 1) { window.scrollTo(0, 0); return true; }
    var doc = document.getElementById("doc");
    var target = null;
    if (a.line) {
      var same = doc.querySelectorAll('[data-line="' + a.line + '"]');
      var cand = same[Math.min(a.nth, same.length - 1)];
      if (cand && (cand.textContent || "").trim().slice(0, 60) === a.text) target = cand;
      if (!target && a.text) {
        var all = doc.querySelectorAll("[data-line]");
        for (var i = 0; i < all.length; i++) {
          if ((all[i].textContent || "").trim().slice(0, 60) === a.text) { target = all[i]; break; }
        }
      }
    }
    if (target) {
      window.scrollBy(0, target.getBoundingClientRect().top - a.dy);
      return true;
    }
    window.scrollTo(0, a.y);
    return false;
  }

  function topInset() {
    var bar = document.getElementById("review-bar");
    return bar && !bar.hidden ? bar.getBoundingClientRect().bottom : 0;
  }

  // ---------------------------------------------------------------------------------------------
  // Images: reserve their space once known, so a late-loading image doesn't push text off a page

  /** Returns false when this image is already known to be missing, so the caller can show its notice right away. */
  function prepareImage(img, key) {
    var known = imgSizes[key];
    if (known && known.failed) return false;
    if (known) {
      img.setAttribute("width", String(known.w));
      img.setAttribute("height", String(known.h));
    }
    img.addEventListener("load", function () {
      if (imgSizes[key]) return;
      imgSizes[key] = { w: img.naturalWidth, h: img.naturalHeight };
      if (state.paged) scheduleRerender();
    });
    img.addEventListener("error", function () {
      if (imgSizes[key]) return;
      imgSizes[key] = { failed: true };
      if (state.paged) scheduleRerender();
    });
    return true;
  }

  function scheduleRerender() {
    clearTimeout(rerenderTimer);
    rerenderTimer = setTimeout(function () { if (root.mdRerender) root.mdRerender(); }, 60);
  }

  // ---------------------------------------------------------------------------------------------
  // Settings

  function saveLayout() {
    post({ action: "layout", paged: state.paged, size: state.size, sidebar: state.sidebar, sidebarWidth: state.sidebarWidth, zoomMode: state.zoomMode, zoom: state.zoom, tab: state.tab, spread: state.spread });
  }

  // ---------------------------------------------------------------------------------------------
  // Public

  root.MDPages = {
    captureAnchor: captureAnchor,
    restoreAnchor: restoreAnchor,
    prepareImage: prepareImage,
    /** Called by the preview after each render (content, review marks and all). */
    layout: function (doc) {
      layoutRevision++;
      document.documentElement.style.setProperty("--page-w", size().w + "px");
      document.documentElement.style.setProperty("--page-h", size().h + "px");
      document.documentElement.style.setProperty("--page-content-h", contentHeight() + "px");
      setSidebarWidth(state.sidebarWidth);
      document.body.classList.toggle("paged", state.paged);
      showTab();
      document.body.classList.toggle("thumbs-open", sidebarShown());
      doc.classList.toggle("paged", state.paged);
      if (!state.paged) {
        pages = [];
        clearPagedStyles(doc);
        buildThumbs();
        updateBar();
        return;
      }
      doc.style.transform = "";
      doc.style.width = size().w + "px";
      paginate(doc);
      applyZoom();
      if (current >= pages.length) current = pages.length - 1;
      buildThumbs();
    },
    afterScroll: function () { if (state.paged) { current = pageAtCenter(); markCurrent(true); } },
    isPaged: function () { return state.paged; }
  };

  /** Settings from the app (or a test). Re-lays out only when something that affects pages changed. */
  root.mdSetLayout = function (prefs) {
    var relayout = false;
    if (prefs && typeof prefs === "object") {
      if (typeof prefs.paged === "boolean" && prefs.paged !== state.paged) { state.paged = prefs.paged; relayout = true; }
      if (prefs.size && SIZES[prefs.size] && prefs.size !== state.size) { state.size = prefs.size; relayout = true; }
      if (typeof prefs.sidebar === "boolean") state.sidebar = prefs.sidebar;
      if (typeof prefs.sidebarWidth === "number") state.sidebarWidth = prefs.sidebarWidth;
      if (typeof prefs.zoomMode === "string") state.zoomMode = prefs.zoomMode;
      if (typeof prefs.zoom === "number") state.zoom = prefs.zoom;
      if (prefs.tab === "pages" || prefs.tab === "notes") state.tab = prefs.tab;
      if (typeof prefs.spread === "boolean") state.spread = prefs.spread;
    }
    setSidebarWidth(state.sidebarWidth);
    if (relayout && root.mdRerender) root.mdRerender();
    else {
      document.body.classList.toggle("thumbs-open", sidebarShown());
      var a = captureAnchor();
      applyZoom();
      restoreAnchor(a);
    }
  };

  /** Next or previous page; with two pages side by side, the next or previous pair. */
  root.mdPageStep = function (dir) {
    if (!state.spread) { goTo(current + dir, true); return; }
    var left = current - (current % 2);
    goTo(left + 2 * dir, true);
  };

  /** One page at a time, or two side by side like a book. */
  root.mdPagesSpread = function (on) {
    if (!state.paged) return;
    var a = captureAnchor();
    state.spread = !!on;
    applyZoom();
    restoreAnchor(a);
    current = pageAtCenter();
    markCurrent(true);
    saveLayout();
  };
  root.mdGoToPage = function (n) { goTo(n - 1, true); };
  root.mdFocusPageInput = function () {
    if (!state.paged) return;
    var input = document.getElementById("page-input");
    input.focus();
    input.select();
  };
  /** Shows the sidebar on "pages" (thumbnails) or "notes" (notes and highlights). */
  root.mdShowSidebarTab = function (t) {
    state.tab = t === "notes" ? "notes" : "pages";
    state.sidebar = true;
    var a = captureAnchor();
    showTab();
    document.body.classList.toggle("thumbs-open", sidebarShown());
    applyZoom();
    restoreAnchor(a);
    markCurrent(true);
    saveLayout();
    if (root.MDAnnotations) root.MDAnnotations.redraw();
  };

  root.mdPagesToggleSidebar = function () {
    state.sidebar = !sidebarShown();
    showTab();
    var a = captureAnchor();
    document.body.classList.toggle("thumbs-open", sidebarShown());
    applyZoom();
    restoreAnchor(a);
    markCurrent(true);
    saveLayout();
  };

  /** "in", "out", "actual" (100%), "fit" (fit width), "fitPage". */
  root.mdPagesZoom = function (how) {
    if (!state.paged) return;
    var a = captureAnchor();
    if (how === "in" || how === "out") {
      var z = zoom, next = z;
      for (var i = 0; i < ZOOM_STEPS.length; i++) {
        if (how === "in" && ZOOM_STEPS[i] > z + 0.001) { next = ZOOM_STEPS[i]; break; }
        if (how === "out" && ZOOM_STEPS[i] < z - 0.001) next = ZOOM_STEPS[i];
      }
      state.zoomMode = "manual";
      state.zoom = next;
    } else if (how === "actual") {
      state.zoomMode = "manual";
      state.zoom = 1;
    } else if (how === "fitPage") {
      state.zoomMode = "fitPage";
    } else {
      state.zoomMode = "fitWidth";
    }
    applyZoom();
    restoreAnchor(a);
    saveLayout();
  };

  root.mdPagesState = function () {
    return {
      paged: state.paged, size: state.size, count: pages.length, current: current + 1, zoom: zoom,
      zoomMode: state.zoomMode, sidebar: sidebarShown(), sidebarWidth: state.sidebarWidth, revision: layoutRevision, tab: tab(), spread: state.spread
    };
  };
})(typeof window !== "undefined" ? window : globalThis);
