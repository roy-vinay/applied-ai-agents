// Renders Markdown for the preview and shows what changed since the reader last looked.
// No raw HTML from documents is rendered, so scripts in a document never run. Links, images and
// review actions are routed through the app (see the message handlers below).
(function (root) {
  "use strict";
  var md = root.markdownit({ html: false, linkify: true, typographer: false });

  function slugify(s) {
    return s.trim().toLowerCase()
      .replace(/[^\p{L}\p{N}\s_-]/gu, "")
      .replace(/\s+/g, "-");
  }

  // Heading ids (GitHub style, unique), task-list checkboxes (display only), and source line
  // numbers on every block so changes can be matched to what's on screen.
  md.core.ruler.push("headings_tasks_lines", function (state) {
    var used = {};
    var tokens = state.tokens;
    for (var i = 0; i < tokens.length; i++) {
      var t = tokens[i];
      if (t.map && (t.nesting === 1 || t.type === "fence" || t.type === "code_block" || t.type === "hr")) {
        t.attrSet("data-line", String(t.map[0] + 1));
      }
      if (t.type === "heading_open" && tokens[i + 1] && tokens[i + 1].type === "inline") {
        var base = slugify(tokens[i + 1].content) || "section";
        var id = base;
        if (used[base] !== undefined) { used[base] += 1; id = base + "-" + used[base]; } else { used[base] = 0; }
        // Prefixed so a heading named "history" or "doc" can never take over an id the app uses.
        t.attrSet("id", "sec-" + id);
      }
      if (t.type === "list_item_open" && tokens[i + 2] && tokens[i + 2].type === "inline") {
        var inline = tokens[i + 2];
        var m = /^\[([ xX])\][ \t]/.exec(inline.content);
        if (m && inline.children && inline.children.length && inline.children[0].type === "text") {
          var first = inline.children[0];
          first.content = first.content.replace(/^\[[ xX]\][ \t]/, "");
          inline.content = inline.content.replace(/^\[[ xX]\][ \t]/, "");
          var box = new state.Token("html_inline", "", 0);
          box.content = '<input type="checkbox" disabled' + (m[1] === " " ? "" : " checked") + ' aria-label="' + (m[1] === " " ? "Not done" : "Done") + '"> ';
          inline.children.unshift(box);
          t.attrJoin("class", "task-list-item");
        }
      }
    }
  });

  // Wrap tables so wide ones scroll sideways.
  var tableOpen = md.renderer.rules.table_open || function (tokens, idx, options, env, self) { return self.renderToken(tokens, idx, options); };
  var tableClose = md.renderer.rules.table_close || function (tokens, idx, options, env, self) { return self.renderToken(tokens, idx, options); };
  md.renderer.rules.table_open = function (tokens, idx, options, env, self) { return '<div class="table-wrap">' + tableOpen(tokens, idx, options, env, self); };
  md.renderer.rules.table_close = function (tokens, idx, options, env, self) { return tableClose(tokens, idx, options, env, self) + "</div>"; };

  root.mdRenderHTML = function (src) { return md.render(src); };

  if (typeof document === "undefined") return;

  // ---------------------------------------------------------------------------------------------
  // State

  var source = "";
  var review = null;      // { mode: "unread" | "compare" | "conflict", baseText, title?, revisions? }
  var changes = [];       // from MDDiff.diffMarkdown(review.baseText, source)
  var changeEls = [];     // elements on screen, in document order
  var current = -1;

  function post(msg) {
    if (root.webkit && root.webkit.messageHandlers && root.webkit.messageHandlers.review) {
      root.webkit.messageHandlers.review.postMessage(msg);
    } else if (root.mdTestLog) {
      root.mdTestLog.push(msg); // used by tests outside the app
    }
  }

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function notice(img, text) {
    var span = el("span", "notice", text);
    span.setAttribute("role", "note");
    img.replaceWith(span);
  }

  // ---------------------------------------------------------------------------------------------
  // Rendering

  function render() {
    var pager = root.MDPages;
    var anchor = pager ? pager.captureAnchor() : null;
    var y = window.scrollY;
    var doc = document.getElementById("doc");
    doc.innerHTML = md.render(source);
    var imgs = doc.querySelectorAll("img");
    for (var i = 0; i < imgs.length; i++) {
      (function (img) {
        var s = img.getAttribute("src") || "";
        if (/^data:/i.test(s)) return;
        if (/^[a-z][a-z0-9+.-]*:/i.test(s) && !/^file:/i.test(s)) {
          notice(img, "Remote image not loaded: " + (img.getAttribute("alt") || s));
          return;
        }
        img.onerror = function () { notice(img, "Image not found: " + s); };
        if (pager && pager.prepareImage(img, s) === false) { notice(img, "Image not found: " + s); return; }
        img.src = "mdeditdiff-res://image/?p=" + encodeURIComponent(s);
      })(imgs[i]);
    }
    changes = [];
    changeEls = [];
    if (review && root.MDDiff) applyReview(doc);
    if (current >= changeEls.length) current = -1;
    updateBar();
    if (pager) pager.layout(doc);
    if (find.open && find.query) runFind(false);
    if (pager) { pager.restoreAnchor(anchor); pager.afterScroll(); } else window.scrollTo(0, y);
  }

  /** Lay the current text out again (after an image loads or the page size changes). */
  root.mdRerender = function () { render(); };

  root.mdRender = function (src) {
    source = src;
    render();
  };

  root.mdSetFontSize = function (px) {
    var before = document.documentElement.style.getPropertyValue("--size");
    document.documentElement.style.setProperty("--size", px + "px");
    // Pages depend on the font size, so lay them out again.
    if (before && before !== px + "px" && root.MDPages && root.MDPages.isPaged() && source) render();
  };

  /** Show changes against a base text, or pass null to stop. */
  root.mdSetReview = function (r) {
    review = r;
    current = -1;
    render();
  };

  // ---------------------------------------------------------------------------------------------
  // Matching changes to what's on screen

  var SELECTORS = {
    heading: "h1,h2,h3,h4,h5,h6", paragraph: "p", "list-item": "li", "table-row": "tr",
    code: "pre,code", quote: "blockquote", rule: "hr", "front-matter": "hr,p"
  };

  function blockAt(doc, kind, line) {
    var found = doc.querySelectorAll('[data-line="' + line + '"]');
    if (!found.length) return null;
    var pick = found[0];
    if (kind) {
      for (var i = 0; i < found.length; i++) {
        if (found[i].matches(SELECTORS[kind] || "*")) { pick = found[i]; break; }
      }
    }
    if (pick.tagName === "CODE" && pick.parentElement && pick.parentElement.tagName === "PRE") pick = pick.parentElement;
    if (pick.tagName === "TABLE") pick = pick.closest(".table-wrap") || pick;
    return pick;
  }

  function plainText(kind, mdText) {
    if (kind === "table-row") {
      return mdText.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map(function (c) { return c.trim(); }).join(" ");
    }
    var tmp = document.createElement("div");
    tmp.innerHTML = md.render(mdText);
    return tmp.textContent || "";
  }

  var TOKEN = /[\p{L}\p{N}_'’-]+(?:[.,:]\p{N}+)*|[^\s\p{L}\p{N}_]/gu;

  function joinWords(words) {
    return words.join(" ").replace(/ ([.,;:!?)\]}%…])/g, "$1").replace(/([(\[{$“‘"]) /g, "$1");
  }

  /** Text nodes of a block, skipping nested lists and tables (they are separate blocks). */
  function textNodes(block) {
    var out = [];
    var walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        var p = n.parentElement;
        while (p && p !== block) {
          if (/^(UL|OL|TABLE)$/.test(p.tagName) && block.tagName === "LI") return NodeFilter.FILTER_REJECT;
          p = p.parentElement;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var n;
    while ((n = walker.nextNode())) out.push(n);
    return out;
  }

  /** Marks inserted words with <ins> and shows removed words with <del>, keeping links and formatting. */
  function markWords(block, change) {
    var nodes = textNodes(block);
    var toks = [];
    nodes.forEach(function (node) {
      var m;
      TOKEN.lastIndex = 0;
      while ((m = TOKEN.exec(node.data))) toks.push({ node: node, start: m.index, end: m.index + m[0].length, text: m[0] });
    });
    var oldToks = root.MDDiff.tokenize(plainText(change.kind, change.old));
    var ops = root.MDDiff.diffSeq(oldToks, toks.map(function (t) { return t.text; }));

    var edits = []; // { node, at, kind: "ins" | "del", end?, text? }
    var pending = [];
    function flushDel(beforeTok) {
      if (!pending.length) return;
      var text = joinWords(pending);
      pending = [];
      if (beforeTok) edits.push({ node: beforeTok.node, at: beforeTok.start, kind: "del", text: text });
      else edits.push({ node: null, kind: "del", text: text });
    }
    ops.forEach(function (o) {
      if (o.op === "delete") { pending.push(oldToks[o.a]); return; }
      flushDel(toks[o.b]);
      if (o.op === "insert") {
        var t = toks[o.b];
        var last = edits[edits.length - 1];
        if (last && last.kind === "ins" && last.node === t.node && last.lastTok === o.b - 1) {
          last.end = t.end;
          last.lastTok = o.b;
        } else {
          edits.push({ node: t.node, at: t.start, end: t.end, kind: "ins", lastTok: o.b });
        }
      }
    });
    flushDel(null);

    // Apply from the end of each text node backwards, so earlier offsets stay valid.
    // At the same offset, wrap the insertion first, then put the deletion in front of it.
    var byNode = new Map();
    edits.forEach(function (e) {
      var key = e.node || block;
      if (!byNode.has(key)) byNode.set(key, []);
      byNode.get(key).push(e);
    });
    byNode.forEach(function (list) {
      list.sort(function (a, b) { return (b.at || 0) - (a.at || 0) || (a.kind === "ins" ? -1 : 1); });
      list.forEach(function (e) {
        if (e.kind === "del") {
          var del = el("del", "md-del", e.text);
          if (e.node) {
            var r = document.createRange();
            r.setStart(e.node, e.at);
            r.collapse(true);
            r.insertNode(del);
            del.after(document.createTextNode(" "));
          } else {
            var nested = block.tagName === "LI" ? block.querySelector(":scope > ul, :scope > ol") : null;
            block.insertBefore(document.createTextNode(" "), nested);
            block.insertBefore(del, nested);
          }
        } else {
          var range = document.createRange();
          range.setStart(e.node, e.at);
          range.setEnd(e.node, e.end);
          range.surroundContents(el("ins", "md-ins"));
        }
      });
    });
  }

  function removalNode(change, anchor, index) {
    var tag = "div";
    if (anchor && change.kind === "list-item" && anchor.tagName === "LI") tag = "li";
    if (anchor && change.kind === "table-row" && anchor.tagName === "TR") tag = "tr";
    var box = el(tag, "md-change md-removed");
    var content;
    if (tag === "tr") {
      content = el("td", "md-removed-body", plainText("table-row", change.old));
      content.colSpan = anchor.children.length || 1;
    } else {
      content = el("div", "md-removed-body");
      var html = md.render(change.old);
      if (change.kind === "list-item") {
        var tmp = document.createElement("div");
        tmp.innerHTML = html;
        var li = tmp.querySelector("li");
        html = li ? li.innerHTML : html;
      }
      content.innerHTML = html;
    }
    var bar = el("span", "md-removed-tools");
    bar.appendChild(el("span", "md-tag", "Removed"));
    var btn = el("button", "md-restore", "Restore");
    btn.type = "button";
    btn.setAttribute("aria-label", "Restore this removed passage");
    btn.addEventListener("click", function () {
      post({ action: "restoreBlock", text: change.old, beforeLine: change.at_line || 0, kind: change.kind });
    });
    bar.appendChild(btn);
    if (tag === "tr") content.prepend(bar); else box.appendChild(bar);
    box.appendChild(content);
    box.dataset.change = String(index);
    return box;
  }

  function applyReview(doc) {
    var result = root.MDDiff.diffMarkdown(review.baseText, source);
    changes = result.changes;
    changes.forEach(function (c, i) {
      if (c.type === "removed") {
        var anchor = c.at_line ? blockAt(doc, c.kind, c.at_line) : null;
        var node = removalNode(c, anchor, i);
        if (anchor && anchor.parentNode) {
          anchor.parentNode.insertBefore(node, anchor);
        } else {
          doc.appendChild(node);
        }
        node.setAttribute("aria-label", "Removed since " + baseName());
        return;
      }
      var block = blockAt(doc, c.kind, c.line);
      if (!block) return;
      block.classList.add("md-change", c.type === "added" ? "md-added" : "md-modified");
      block.dataset.change = String(i);
      block.setAttribute("aria-description", (c.type === "added" ? "Added" : "Changed") + " since " + baseName());
      if (c.type === "modified" && c.kind !== "code") {
        try { markWords(block, c); } catch (e) { /* keep the block highlight even if word marking fails */ }
      }
    });
    changeEls = Array.prototype.slice.call(doc.querySelectorAll(".md-change"));
    changeEls.forEach(function (e) { e.tabIndex = -1; });
    post({ action: "count", n: changes.length, mode: review.mode });
  }

  function baseName() {
    if (!review) return "";
    if (review.mode === "unread") return "you last read";
    if (review.mode === "conflict") return "the version on disk";
    return review.title || "the selected version";
  }

  // ---------------------------------------------------------------------------------------------
  // Review bar

  function button(label, aria, onClick) {
    var b = el("button", "rb-button", label);
    b.type = "button";
    if (aria) b.setAttribute("aria-label", aria);
    b.addEventListener("click", onClick);
    return b;
  }

  function authorsLine() {
    var revs = (review && review.revisions) || [];
    var parts = [];
    var unreported = 0;
    revs.forEach(function (r) {
      if (r.source === "checkpoint" && r.author) parts.push(r.author + (r.note ? ": “" + r.note + "”" : ""));
      else unreported++;
    });
    var shown = parts.slice(-3);
    if (parts.length > 3) shown.unshift((parts.length - 3) + " more");
    if (unreported) shown.push(unreported + " not reported");
    return shown.join(" · ");
  }

  function updateBar() {
    var bar = document.getElementById("review-bar");
    bar.innerHTML = "";
    var show = review && (changes.length > 0 || review.mode !== "unread");
    bar.hidden = !show;
    document.body.classList.toggle("reviewing", !!show);
    if (!show) return;
    var n = changes.length;
    var title;
    if (review.mode === "unread") title = n + (n === 1 ? " change" : " changes") + " since you last read";
    else if (review.mode === "conflict") title = n + (n === 1 ? " difference" : " differences") + " between your unsaved edits and the version on disk";
    else title = n + (n === 1 ? " change" : " changes") + " since " + (review.title || "the selected version");
    var text = el("div", "rb-text");
    text.appendChild(el("strong", "rb-title", title));
    var who = authorsLine();
    if (who) text.appendChild(el("span", "rb-who", who));
    bar.appendChild(text);
    var tools = el("div", "rb-tools");
    if (n > 0) {
      tools.appendChild(button("‹ Prev", "Previous change", function () { root.mdNav(-1); }));
      tools.appendChild(button("Next ›", "Next change", function () { root.mdNav(1); }));
    }
    if (review.mode === "unread") {
      var mark = button("Mark as read", null, function () { post({ action: "markRead" }); });
      mark.classList.add("primary");
      tools.appendChild(mark);
    }
    else tools.appendChild(button("Done", "Stop comparing", function () { post({ action: "endCompare" }); }));
    tools.appendChild(button("History", "Show version history", function () { post({ action: "history" }); }));
    bar.appendChild(tools);
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

  /** Move to the next (1) or previous (-1) change. */
  root.mdNav = function (dir) {
    if (!changeEls.length) return;
    current = (current + dir + changeEls.length) % changeEls.length;
    changeEls.forEach(function (e) { e.classList.remove("md-current"); });
    var target = changeEls[current];
    target.classList.add("md-current");
    target.scrollIntoView({ block: "center", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
    target.focus({ preventScroll: true });
    var c = changes[Number(target.dataset.change)];
    var what = c ? (c.type === "added" ? "Added" : c.type === "removed" ? "Removed" : "Changed") + " in " + c.section : "";
    announce("Change " + (current + 1) + " of " + changeEls.length + (what ? ": " + what : ""));
  };

  // ---------------------------------------------------------------------------------------------
  // History panel

  function localTime(iso) {
    try {
      var d = new Date(iso);
      return d.toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
    } catch (e) { return iso; }
  }

  /** list: revisions newest first ({ revision, time, source, author?, note? }); readerAt: "r3" or null. */
  root.mdShowHistory = function (list, readerAt) {
    var panel = document.getElementById("history");
    panel.innerHTML = "";
    var head = el("div", "hp-head");
    head.appendChild(el("h2", "hp-title", "Version history"));
    var close = button("Close", "Close version history", function () { root.mdHideHistory(); });
    head.appendChild(close);
    panel.appendChild(head);
    if (!list || !list.length) {
      panel.appendChild(el("p", "hp-empty", "No history yet. Versions are recorded when this file is opened, saved, or checked in by an agent."));
    }
    var ol = el("ol", "hp-list");
    (list || []).forEach(function (r, i) {
      var li = el("li", "hp-item");
      var top = el("div", "hp-row");
      top.appendChild(el("span", "hp-rev", r.revision));
      top.appendChild(el("span", "hp-who", r.source === "checkpoint" && r.author ? r.author : "Changed outside, not reported"));
      li.appendChild(top);
      if (r.note) li.appendChild(el("div", "hp-note", r.note));
      var meta = localTime(r.time) + (i === 0 ? " · latest" : "") + (readerAt === r.revision ? " · you last read this" : "");
      li.appendChild(el("div", "hp-meta", meta));
      if (i > 0) {
        var row = el("div", "hp-actions");
        row.appendChild(button("Compare", "Compare the current text with " + r.revision, function () { post({ action: "compare", revision: r.revision }); }));
        row.appendChild(button("Restore", "Restore " + r.revision + " as an unsaved edit", function () { post({ action: "restoreVersion", revision: r.revision }); }));
        li.appendChild(row);
      }
      ol.appendChild(li);
    });
    panel.appendChild(ol);
    panel.hidden = false;
    document.body.classList.add("history-open");
    close.focus();
  };

  root.mdHideHistory = function () {
    var panel = document.getElementById("history");
    panel.hidden = true;
    document.body.classList.remove("history-open");
  };

  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape") return;
    if (find.open) { root.mdFindClose(); return; }
    if (!document.getElementById("history").hidden) root.mdHideHistory();
  });

  // ---------------------------------------------------------------------------------------------
  // Find in the rendered document. Matches are case-insensitive, can cross formatting
  // (bold, links, code) but never cross from one block into the next.

  var find = { open: false, query: "", hits: [], index: -1, timer: 0 };
  var MAX_HITS = 2000;
  var BLOCK_TAGS = /^(P|LI|H[1-6]|TD|TH|PRE|BLOCKQUOTE|DIV|TR|MAIN|DEL|UL|OL|TABLE)$/;

  function findBar() {
    var bar = document.getElementById("find-bar");
    if (bar) return bar;
    bar = el("div", "find-bar");
    bar.id = "find-bar";
    bar.setAttribute("role", "search");
    bar.hidden = true;
    var input = el("input", "fb-input");
    input.id = "find-input";
    input.type = "search";
    input.placeholder = "Find";
    input.setAttribute("aria-label", "Find in document");
    input.autocomplete = "off";
    input.spellcheck = false;
    var count = el("span", "fb-count");
    count.id = "find-count";
    count.setAttribute("aria-live", "polite");
    var prev = button("‹", "Previous match", function () { root.mdFindStep(-1); });
    var next = button("›", "Next match", function () { root.mdFindStep(1); });
    var done = button("Done", "Close find", function () { root.mdFindClose(); });
    prev.classList.add("fb-step");
    next.classList.add("fb-step");
    bar.appendChild(input);
    bar.appendChild(count);
    bar.appendChild(prev);
    bar.appendChild(next);
    bar.appendChild(done);
    input.addEventListener("input", function () {
      clearTimeout(find.timer);
      find.timer = setTimeout(function () { find.query = input.value; find.index = -1; runFind(true); }, 90);
    });
    input.addEventListener("keydown", function (e) {
      if (e.key === "Enter") {
        e.preventDefault();
        clearTimeout(find.timer);
        if (find.query !== input.value) { find.query = input.value; find.index = -1; runFind(false); }
        root.mdFindStep(e.shiftKey ? -1 : 1);
      }
    });
    document.body.appendChild(bar);
    return bar;
  }

  function clearFindMarks() {
    var marks = document.querySelectorAll("#doc mark.find-hit");
    var parents = new Set();
    for (var i = 0; i < marks.length; i++) {
      var m = marks[i];
      parents.add(m.parentNode);
      while (m.firstChild) m.parentNode.insertBefore(m.firstChild, m);
      m.remove();
    }
    parents.forEach(function (p) { if (p) p.normalize(); });
    find.hits = [];
  }

  function blockOf(node) {
    var p = node.parentElement;
    while (p && !BLOCK_TAGS.test(p.tagName)) p = p.parentElement;
    return p;
  }

  /** Text of the document as one string, with a NUL between blocks so no match spans two. */
  function collectText(scope) {
    var map = []; // { node, start } in order
    var text = "";
    var lastBlock = null;
    var walker = document.createTreeWalker(scope, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        var p = n.parentElement;
        if (!p || p.closest(".md-removed-tools, .no-find, script, style")) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var n;
    while ((n = walker.nextNode())) {
      var b = blockOf(n);
      // A block continued on the next page is still one block, so matches can cross the page break.
      var continued = b && lastBlock && b.classList.contains("pg-cont") && b.getAttribute("data-line") === lastBlock.getAttribute("data-line");
      if (b !== lastBlock && !continued) text += "\u0000";
      lastBlock = b;
      map.push({ node: n, start: text.length });
      text += n.data;
    }
    return { text: text, map: map };
  }

  function escapeRe(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }

  function runFind(scrollToFirst) {
    clearFindMarks();
    var q = find.query;
    var count = document.getElementById("find-count");
    if (!q) { find.index = -1; if (count) count.textContent = ""; post({ action: "findCount", n: 0 }); return; }
    var doc = document.getElementById("doc");
    var all = collectText(doc);
    var re = new RegExp(escapeRe(q).replace(/\s+/g, "\\s+"), "giu");
    var ranges = [];
    var m;
    while ((m = re.exec(all.text)) && ranges.length < MAX_HITS) {
      if (!m[0].length) { re.lastIndex++; continue; }
      ranges.push([m.index, m.index + m[0].length]);
    }
    // Split each match into per-text-node segments, then wrap from the end backwards.
    var segs = [];
    var j = 0;
    ranges.forEach(function (r, hit) {
      while (j < all.map.length - 1 && all.map[j + 1].start <= r[0]) j++;
      for (var k = j; k < all.map.length && all.map[k].start < r[1]; k++) {
        var e = all.map[k];
        var s = Math.max(r[0], e.start) - e.start;
        var t = Math.min(r[1], e.start + e.node.data.length) - e.start;
        if (t > s) segs.push({ k: k, s: s, t: t, hit: hit });
      }
    });
    segs.sort(function (a, b) { return b.k - a.k || b.s - a.s; });
    var hits = ranges.map(function () { return []; });
    segs.forEach(function (g) {
      var node = all.map[g.k].node;
      var range = document.createRange();
      range.setStart(node, g.s);
      range.setEnd(node, g.t);
      var mark = el("mark", "find-hit");
      mark.dataset.hit = String(g.hit);
      range.surroundContents(mark);
      hits[g.hit].unshift(mark);
    });
    find.hits = hits;
    if (!hits.length) find.index = -1;
    else if (find.index >= hits.length) find.index = hits.length - 1;
    if (scrollToFirst && hits.length) {
      find.index = firstHitBelowTop();
    }
    showCurrentHit(scrollToFirst);
    post({ action: "findCount", n: hits.length });
  }

  /** The first match at or below the top of the visible area, so typing doesn't jump backwards. */
  function firstHitBelowTop() {
    for (var i = 0; i < find.hits.length; i++) {
      if (find.hits[i][0].getBoundingClientRect().bottom > 0) return i;
    }
    return 0;
  }

  function showCurrentHit(scroll) {
    var count = document.getElementById("find-count");
    var all = document.querySelectorAll("#doc mark.find-current");
    for (var i = 0; i < all.length; i++) all[i].classList.remove("find-current");
    var n = find.hits.length;
    var label = !find.query ? "" : n === 0 ? "Not found" : (find.index >= 0 ? (find.index + 1) + " of " : "") + n + (n >= MAX_HITS ? "+" : "") + (find.index >= 0 ? "" : n === 1 ? " match" : " matches");
    if (count) count.textContent = label;
    var bar = document.getElementById("find-bar");
    if (bar) bar.classList.toggle("fb-none", !!find.query && n === 0);
    if (find.index < 0 || !n) return;
    var marks = find.hits[find.index];
    marks.forEach(function (mk) { mk.classList.add("find-current"); });
    if (scroll) {
      marks[0].scrollIntoView({ block: "center", behavior: "auto" });
    }
  }

  /** Show the find bar. Passing text (Use Selection for Find) searches for it right away. */
  root.mdFindOpen = function (text) {
    var bar = findBar();
    var input = document.getElementById("find-input");
    bar.hidden = false;
    find.open = true;
    document.body.classList.add("finding");
    if (typeof text === "string" && text) {
      input.value = text;
      find.query = text;
      find.index = -1;
      runFind(true);
    }
    input.focus();
    input.select();
  };

  /** Next (1) or previous (-1) match. Opens the bar if it's closed. */
  root.mdFindStep = function (dir) {
    if (!find.open) { root.mdFindOpen(); if (!find.query) return; }
    var n = find.hits.length;
    if (!n) return;
    find.index = find.index < 0 ? (dir > 0 ? firstHitBelowTop() : n - 1) : (find.index + dir + n) % n;
    showCurrentHit(true);
  };

  /** Search for the current selection (⌘E). */
  root.mdFindSelection = function () {
    var s = String(window.getSelection() || "").trim();
    if (s) root.mdFindOpen(s);
  };

  root.mdFindClose = function () {
    var bar = document.getElementById("find-bar");
    if (!bar) return;
    clearTimeout(find.timer);
    clearFindMarks();
    find.open = false;
    find.index = -1;
    bar.hidden = true;
    document.body.classList.remove("finding");
    post({ action: "findClosed" });
  };

  root.mdFindState = function () {
    return { open: find.open, query: find.query, count: find.hits.length, index: find.index };
  };

  // ---------------------------------------------------------------------------------------------
  // Links

  document.addEventListener("click", function (e) {
    var a = e.target.closest ? e.target.closest("a") : null;
    if (!a) return;
    e.preventDefault();
    var href = a.getAttribute("href") || "";
    if (href.charAt(0) === "#") {
      var name = decodeURIComponent(href.slice(1));
      var target = document.getElementById("sec-" + name) || document.getElementById("sec-" + slugify(name));
      if (target) target.scrollIntoView();
      return;
    }
    if (root.webkit && root.webkit.messageHandlers && root.webkit.messageHandlers.link) {
      root.webkit.messageHandlers.link.postMessage(href);
    }
  });
})(typeof window !== "undefined" ? window : globalThis);
