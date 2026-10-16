// Personal highlights and notes on the rendered document.
//
// Anchors are stored as offsets into the Markdown source, in UTF-16 code units (the unit of
// JavaScript strings and NSString), plus the exact source quote and some context on either side.
// Nothing is ever written into the Markdown: annotations live in the app's own storage
// (see docs/ANNOTATIONS.md).
//
// When the text changes, each anchor is carried through the edit; if that doesn't give the same
// text, the exact quote is searched for, using its context to tell repeated passages apart. If it
// can't be placed without guessing, it is kept under "Needs Reattachment" instead.
(function (root) {
  "use strict";

  var FORMAT = "mdeditdiff-annotations";
  var VERSION = 1;
  var COLORS = ["yellow", "green", "blue", "pink", "purple"];
  var COLOR_NAMES = { yellow: "Yellow", green: "Green", blue: "Blue", pink: "Pink", purple: "Purple" };
  var CONTEXT = 32;

  // ---------------------------------------------------------------------------------------------
  // Pure helpers (also used by tests outside the browser)

  /** FNV-1a over UTF-16 code units: identifies the source text the offsets refer to. */
  function hash(s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = Math.imul(h, 0x01000193) >>> 0;
    }
    return ("00000000" + h.toString(16)).slice(-8);
  }

  /** One replacement that turns `a` into `b`: everything between the common prefix and suffix. */
  function diffEdit(a, b) {
    var max = Math.min(a.length, b.length);
    var p = 0;
    while (p < max && a.charCodeAt(p) === b.charCodeAt(p)) p++;
    var s = 0;
    while (s < max - p && a.charCodeAt(a.length - 1 - s) === b.charCodeAt(b.length - 1 - s)) s++;
    return { start: p, oldEnd: a.length - s, newEnd: b.length - s };
  }

  /** Carries a range through an edit. Text inserted exactly at either edge stays outside. */
  function transform(start, end, e) {
    var delta = e.newEnd - e.oldEnd;
    var s = start < e.start ? start : start >= e.oldEnd ? start + delta : e.newEnd;
    var t = end <= e.start ? end : end >= e.oldEnd ? end + delta : e.start;
    return [s, t];
  }

  /** Whitespace runs become one space, with a map back to source offsets. */
  function normalize(s) {
    var out = "";
    var map = [];
    var inSpace = false;
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i);
      if (/\s/.test(c)) {
        if (!inSpace) { out += " "; map.push(i); inSpace = true; }
      } else {
        out += c;
        map.push(i);
        inSpace = false;
      }
    }
    map.push(s.length);
    return { text: out, map: map };
  }

  function commonSuffix(a, b) {
    var n = 0;
    while (n < a.length && n < b.length && a.charAt(a.length - 1 - n) === b.charAt(b.length - 1 - n)) n++;
    return n;
  }

  function commonPrefix(a, b) {
    var n = 0;
    while (n < a.length && n < b.length && a.charAt(n) === b.charAt(n)) n++;
    return n;
  }

  /**
   * Finds `quote` in `source` (ignoring differences in whitespace, so rewrapped paragraphs still
   * match) and picks the occurrence whose surrounding text matches. Returns [start, end] or null
   * when it's missing or can't be told apart from another occurrence.
   */
  function locate(source, quote, prefix, suffix, norm) {
    var q = normalize(quote).text.trim();
    if (!q) return null;
    var n = norm || normalize(source);
    var pre = normalize(prefix || "").text;
    var suf = normalize(suffix || "").text;
    var found = [];
    var from = 0;
    while (found.length < 200) {
      var i = n.text.indexOf(q, from);
      if (i < 0) break;
      var before = n.text.slice(Math.max(0, i - pre.length - 1), i);
      var after = n.text.slice(i + q.length, i + q.length + suf.length + 1);
      found.push({ i: i, score: commonSuffix(before.replace(/ $/, ""), pre.replace(/ $/, "")) + commonPrefix(after.replace(/^ /, ""), suf.replace(/^ /, "")) });
      from = i + 1;
    }
    if (!found.length) return null;
    found.sort(function (a, b) { return b.score - a.score; });
    var best = found[0];
    if (found.length === 1) {
      if (q.length < 12 && best.score < 8) return null; // a short, common quote needs its context
    } else if (best.score < 8 || best.score - found[1].score < 4) {
      return null; // repeated text: context doesn't say which one
    }
    return [n.map[best.i], n.map[best.i + q.length - 1] + 1];
  }

  function excerpt(s, n) {
    s = String(s || "").replace(/\s+/g, " ").trim();
    return s.length > n ? s.slice(0, n - 1) + "…" : s;
  }

  var core = { hash: hash, diffEdit: diffEdit, transform: transform, normalize: normalize, locate: locate };
  root.MDAnnotationsCore = core;
  if (typeof document === "undefined") return;

  // ---------------------------------------------------------------------------------------------
  // State

  var items = [];           // annotations, any order
  var source = "";          // the source the offsets refer to
  var sourceKnown = false;  // whether `source` has been set by a render yet
  var loadedHash = null;    // hash stored in the file, for the first render after loading
  var saveTimer = 0;
  var saveFailed = false;
  var srcMap = null;        // WeakMap text node -> Int32Array of source offsets (lazy)
  var popover = null;
  var lineStarts = [0];

  function post(msg) {
    if (root.webkit && root.webkit.messageHandlers && root.webkit.messageHandlers.review) {
      root.webkit.messageHandlers.review.postMessage(msg);
    } else if (root.mdTestLog) {
      root.mdTestLog.push(msg);
    }
  }

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function newId() {
    var a = new Uint8Array(8);
    (root.crypto || {}).getRandomValues ? root.crypto.getRandomValues(a) : a.forEach(function (_, i) { a[i] = Math.random() * 256; });
    return Array.prototype.map.call(a, function (b) { return ("0" + b.toString(16)).slice(-2); }).join("");
  }

  function now() { return new Date().toISOString(); }

  function byId(id) {
    for (var i = 0; i < items.length; i++) if (items[i].id === id) return items[i];
    return null;
  }

  function snapshot() {
    return JSON.stringify({ format: FORMAT, version: VERSION, sourceHash: hash(source), items: items });
  }

  function scheduleSave() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(function () { post({ action: "annotations", json: snapshot() }); }, 250);
  }

  function lineOf(offset) {
    var lo = 0, hi = lineStarts.length - 1;
    while (lo < hi) {
      var m = (lo + hi + 1) >> 1;
      if (lineStarts[m] <= offset) lo = m; else hi = m - 1;
    }
    return lo + 1;
  }

  function sectionOf(offset) {
    var before = source.slice(0, offset).split("\n");
    for (var i = before.length - 1; i >= 0; i--) {
      var m = /^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$/.exec(before[i]);
      if (m) return m[1];
    }
    return "";
  }

  function setContext(a) {
    a.sourceQuote = source.slice(a.start, a.end);
    a.prefix = source.slice(Math.max(0, a.start - CONTEXT), a.start);
    a.suffix = source.slice(a.end, a.end + CONTEXT);
    a.lastLine = lineOf(a.start);
    a.section = sectionOf(a.start);
  }

  // ---------------------------------------------------------------------------------------------
  // Keeping anchors on their text when the source changes

  function reconcile(next) {
    // Nothing rendered yet: wait for the real text rather than detaching everything.
    if (!sourceKnown && !next && items.length) return;
    var changed = false;
    var edit = sourceKnown && source !== next ? diffEdit(source, next) : null;
    var unchanged = sourceKnown ? source === next : loadedHash === hash(next);
    var norm = null;
    var prevLen = source.length;
    lineStarts = [0];
    for (var i = 0; i < next.length; i++) if (next.charCodeAt(i) === 10) lineStarts.push(i + 1);
    items.forEach(function (a) {
      if (a.detached) return;
      var start = a.start, end = a.end;
      if (unchanged && next.slice(start, end) === a.sourceQuote) return;
      var placed = null;
      var t = edit ? transform(start, end, edit) : null;
      if (t && t[0] < t[1] && next.slice(t[0], t[1]) === a.sourceQuote) placed = t;
      if (!placed) {
        norm = norm || normalize(next);
        placed = locate(next, a.sourceQuote, a.prefix, a.suffix, norm);
      }
      if (!placed && t && t[0] < t[1] && /\S/.test(next.slice(t[0], t[1]))) {
        // Edited inside or partly deleted: keep the surviving text, unless the edit is a large
        // rewrite (then the passage may not be what the person meant).
        var small = edit.oldEnd - edit.start <= 400 && edit.newEnd - edit.start <= 400;
        if (small) placed = t;
      }
      if (placed) {
        a.start = placed[0];
        a.end = placed[1];
      } else {
        a.detached = true;
        a.detachedAt = now();
      }
      changed = true;
    });
    source = next;
    sourceKnown = true;
    items.forEach(function (a) {
      if (a.detached) return;
      var q = source.slice(a.start, a.end);
      if (q !== a.sourceQuote || !a.prefix && a.start > 0 || !a.suffix && a.end < source.length) {
        setContext(a);
        changed = true;
      }
    });
    if (changed && (items.length || prevLen)) scheduleSave();
  }

  // ---------------------------------------------------------------------------------------------
  // Mapping rendered text to source offsets

  function blockSpan(e) {
    var line = Number(e.getAttribute("data-line"));
    var endLine = Number(e.getAttribute("data-line-end")) || line;
    var start = lineStarts[line - 1] !== undefined ? lineStarts[line - 1] : 0;
    var end = endLine < lineStarts.length + 1 && lineStarts[endLine - 1] !== undefined ? lineStarts[endLine - 1] : source.length;
    if (endLine > lineStarts.length) end = source.length;
    if (e.tagName === "PRE" && /^\s{0,3}(```|~~~)/.test(source.slice(start, start + 8))) {
      var nl = source.indexOf("\n", start);
      start = nl < 0 ? end : nl + 1;
    }
    return [start, Math.max(start, end)];
  }

  function skipNode(n, owner) {
    var p = n.parentElement;
    while (p && p !== owner) {
      if (p.hasAttribute("data-line")) return true; // a nested block maps on its own
      if (p.classList.contains("md-removed") || p.classList.contains("notice") || p.classList.contains("md-del") || p.classList.contains("no-find") || p.classList.contains("no-anno") || p.tagName === "INPUT") return true;
      p = p.parentElement;
    }
    return false;
  }

  /** Text nodes of each source block (with any parts continued on later pages), aligned to the source. */
  function buildMap() {
    var map = new WeakMap();
    var doc = document.getElementById("doc");
    if (!doc) return map;
    var groups = new Map();
    var blocks = doc.querySelectorAll("[data-line]");
    for (var b = 0; b < blocks.length; b++) {
      var e = blocks[b];
      if (e.closest(".md-removed")) continue;
      var key = e.tagName + ":" + e.getAttribute("data-line");
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(e);
    }
    groups.forEach(function (els) {
      var span = blockSpan(els[0]);
      var ptr = span[0], end = span[1];
      els.forEach(function (owner) {
        var w = document.createTreeWalker(owner, NodeFilter.SHOW_TEXT, null);
        var n;
        while ((n = w.nextNode())) {
          if (skipNode(n, owner)) continue;
          var offs = new Int32Array(n.data.length);
          for (var i = 0; i < n.data.length; i++) {
            var c = n.data.charAt(i);
            var ws = /\s/.test(c);
            var j = ptr, limit = Math.min(end, ptr + 4000), hit = -1;
            while (j < limit) {
              var sc = source.charAt(j);
              if (ws ? /\s/.test(sc) : sc === c) { hit = j; break; }
              j++;
            }
            if (hit >= 0) { offs[i] = hit; ptr = hit + 1; } else offs[i] = ws ? -2 : -1;
          }
          map.set(n, offs);
        }
      });
    });
    return map;
  }

  function mapped() {
    if (!srcMap) srcMap = buildMap();
    return srcMap;
  }

  /** Source offset for a boundary point of a selection. */
  function pointToSource(node, offset, isEnd) {
    var map = mapped();
    var doc = document.getElementById("doc");
    var walker = document.createTreeWalker(doc, NodeFilter.SHOW_TEXT, null);
    var start = node;
    if (node.nodeType !== 3) {
      // Boundary between children: use the next text node (for a start) or the previous one (for an end).
      var child = node.childNodes[offset] || null;
      walker.currentNode = child || node;
      if (isEnd) {
        if (child) { walker.currentNode = child; start = walker.previousNode(); } else { start = lastText(node) || walker.previousNode(); }
        offset = start ? start.data.length : 0;
      } else {
        start = child && child.nodeType === 3 ? child : (child ? firstText(child) || nextTextAfter(child) : nextTextAfter(node));
        offset = 0;
      }
      if (!start) return -1;
    }
    var n = start;
    var guard = 0;
    walker.currentNode = n;
    while (n && guard++ < 5000) {
      var offs = map.get(n);
      if (offs && offs.length) {
        if (isEnd) {
          for (var i = Math.min(offset, offs.length) - 1; i >= 0; i--) if (offs[i] >= 0) return offs[i] + 1;
        } else {
          for (var k = Math.max(0, offset); k < offs.length; k++) if (offs[k] >= 0) return offs[k];
        }
      }
      n = isEnd ? walker.previousNode() : walker.nextNode();
      offset = isEnd ? (n ? n.data.length : 0) : 0;
    }
    return -1;
  }

  function firstText(e) {
    var w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT, null);
    return w.nextNode();
  }

  function lastText(e) {
    var w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT, null);
    var n, last = null;
    while ((n = w.nextNode())) last = n;
    return last;
  }

  function nextTextAfter(e) {
    var doc = document.getElementById("doc");
    var w = document.createTreeWalker(doc, NodeFilter.SHOW_TEXT, null);
    w.currentNode = e;
    var n;
    while ((n = w.nextNode())) if (!e.contains(n)) return n;
    return null;
  }

  /** The current selection as a source range, or a reason it can't be used. */
  function selectionRange() {
    var sel = window.getSelection();
    if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return { error: "Select some text first." };
    var r = sel.getRangeAt(0);
    var doc = document.getElementById("doc");
    if (!doc.contains(r.commonAncestorContainer)) return { error: "Select text in the document." };
    var s = pointToSource(r.startContainer, r.startOffset, false);
    var e = pointToSource(r.endContainer, r.endOffset, true);
    if (s < 0 || e < 0 || e <= s) return { error: "This text can't be matched to the Markdown source, so it can't be highlighted." };
    return { start: s, end: e, quote: sel.toString() };
  }

  // ---------------------------------------------------------------------------------------------
  // Drawing highlights, markers and note cards

  function clearDrawn(doc) {
    var marks = doc.querySelectorAll("mark.anno");
    var parents = new Set();
    for (var i = 0; i < marks.length; i++) {
      var m = marks[i];
      parents.add(m.parentNode);
      while (m.firstChild) m.parentNode.insertBefore(m.firstChild, m);
      m.remove();
    }
    parents.forEach(function (p) { if (p) p.normalize(); });
    var ui = doc.querySelectorAll(".anno-marker, .anno-card");
    for (var k = 0; k < ui.length; k++) ui[k].remove();
  }

  function attached() {
    return items.filter(function (a) { return !a.detached && a.end > a.start; })
      .sort(function (a, b) { return a.start - b.start || a.end - b.end; });
  }

  function drawHighlights(doc) {
    var list = attached();
    if (!list.length) return;
    var map = buildMap();
    var walker = document.createTreeWalker(doc, NodeFilter.SHOW_TEXT, null);
    var jobs = []; // { node, s, t, ids }
    var n;
    while ((n = walker.nextNode())) {
      var offs = map.get(n);
      if (!offs) continue;
      var lo = -1, hi = -1;
      for (var i = 0; i < offs.length; i++) if (offs[i] >= 0) { if (lo < 0) lo = offs[i]; hi = offs[i]; }
      if (lo < 0) continue;
      var cover = list.filter(function (a) { return a.start <= hi && a.end > lo; });
      if (!cover.length) continue;
      // Split the node into pieces where the set of covering annotations changes.
      var cur = null, from = 0;
      for (var c = 0; c <= offs.length; c++) {
        var ids = null;
        if (c < offs.length) {
          var o = offs[c];
          if (o < 0) {
            // Whitespace or unmatched: belongs to the piece on both sides if they agree.
            ids = cur;
          } else {
            var inside = cover.filter(function (a) { return o >= a.start && o < a.end; }).map(function (a) { return a.id; });
            ids = inside.length ? inside.join(" ") : null;
          }
        }
        if (ids !== cur) {
          if (cur) jobs.push({ node: n, s: from, t: c, ids: cur });
          cur = ids;
          from = c;
        }
      }
    }
    // Wrap from the end backwards so earlier offsets stay valid.
    for (var j = jobs.length - 1; j >= 0; j--) {
      var job = jobs[j];
      var txt = job.node.data.slice(job.s, job.t);
      if (!/\S/.test(txt)) continue;
      var range = document.createRange();
      range.setStart(job.node, job.s);
      range.setEnd(job.node, job.t);
      var ids = job.ids.split(" ");
      var top = byId(ids[ids.length - 1]);
      var colored = ids.map(byId).filter(function (a) { return a && a.color; });
      var color = colored.length ? colored[colored.length - 1].color : null;
      var mark = el("mark", "anno " + (color ? "anno-" + color : "anno-plain") + (ids.length > 1 ? " anno-overlap" : ""));
      mark.dataset.anno = job.ids;
      mark.setAttribute("aria-label", (color ? COLOR_NAMES[color] + " highlight" : "Note") + (top && top.note ? ", has a note" : ""));
      range.surroundContents(mark);
    }
  }

  function zoomFactor() {
    var st = root.mdPagesState ? root.mdPagesState() : null;
    return st && st.paged ? st.zoom || 1 : 1;
  }

  /** Where the first highlighted piece of an annotation is, inside its page (or the sheet). */
  function anchorBox(a) {
    var doc = document.getElementById("doc");
    var marks = doc.querySelectorAll("mark.anno");
    for (var i = 0; i < marks.length; i++) {
      if ((" " + marks[i].dataset.anno + " ").indexOf(" " + a.id + " ") >= 0) {
        var host = marks[i].closest(".page") || doc;
        return { mark: marks[i], host: host };
      }
    }
    return null;
  }

  function drawNotes(doc) {
    var z = zoomFactor();
    var placed = new Map(); // host -> last marker top
    attached().filter(function (a) { return a.note !== null && a.note !== undefined; }).forEach(function (a) {
      var box = anchorBox(a);
      if (!box) return;
      var hr = box.host.getBoundingClientRect();
      var mr = box.mark.getBoundingClientRect();
      var top = (mr.top - hr.top) / z;
      var hostW = box.host.offsetWidth;
      var margin = box.host.classList.contains("page") ? 96 : parseFloat(getComputedStyle(box.host).paddingRight) || 72;
      var last = placed.has(box.host) ? placed.get(box.host) : -Infinity;
      if (top < last + 28) top = last + 28;
      placed.set(box.host, top);

      var marker = el("button", "anno-marker no-find no-anno");
      marker.type = "button";
      marker.dataset.anno = a.id;
      marker.style.top = (top - 2) + "px";
      marker.style.left = (hostW - margin + Math.min(20, margin / 4)) + "px";
      marker.setAttribute("aria-expanded", a.collapsed ? "false" : "true");
      marker.setAttribute("aria-label", "Note on “" + excerpt(a.quote, 60) + "”, " + (a.collapsed ? "collapsed" : "expanded"));
      marker.title = excerpt(a.note, 120) || "Empty note";
      if (a.color) marker.classList.add("anno-m-" + a.color);
      marker.addEventListener("click", function (e) { e.stopPropagation(); toggle(a.id); });
      box.host.appendChild(marker);

      var card = el("div", "anno-card no-find no-anno");
      card.dataset.anno = a.id;
      card.hidden = !!a.collapsed;
      card.setAttribute("role", "group");
      card.setAttribute("aria-label", "Note on “" + excerpt(a.quote, 60) + "”");
      var cardW = 280;
      var contentRight = hostW - margin;
      card.style.width = cardW + "px";
      card.style.left = Math.max(8, contentRight - cardW + 24) + "px";
      card.style.top = ((mr.bottom - hr.top) / z + 8) + "px";
      var head = el("div", "anno-card-head");
      var q = el("span", "anno-card-quote", "“" + excerpt(a.quote, 70) + "”");
      head.appendChild(q);
      var collapse = el("button", "anno-icon", "▾");
      collapse.type = "button";
      collapse.title = "Collapse note";
      collapse.setAttribute("aria-label", "Collapse note");
      collapse.addEventListener("click", function () { toggle(a.id, true); });
      head.appendChild(collapse);
      card.appendChild(head);
      var text = el("textarea", "anno-text");
      text.value = a.note || "";
      text.placeholder = "Write a note";
      text.setAttribute("aria-label", "Note text");
      text.rows = 3;
      text.addEventListener("input", function () {
        a.note = text.value;
        a.updated = now();
        marker.title = excerpt(a.note, 120) || "Empty note";
        autosize(text);
        scheduleSave();
        refreshSidebar();
      });
      text.addEventListener("keydown", function (e) {
        if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); toggle(a.id, true); }
      });
      card.appendChild(text);
      var foot = el("div", "anno-card-foot");
      foot.appendChild(el("span", "anno-card-meta", a.updated ? new Date(a.updated).toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }) : ""));
      var del = el("button", "anno-link", "Delete note");
      del.type = "button";
      del.addEventListener("click", function () { confirmThen(del, a.note, function () { removeNote(a.id); }); });
      foot.appendChild(del);
      card.appendChild(foot);
      box.host.appendChild(card);
      if (!card.hidden) autosize(text);
    });
  }

  function autosize(t) {
    t.style.height = "auto";
    t.style.height = Math.min(240, t.scrollHeight + 2) + "px";
  }

  function confirmThen(button, text, action) {
    if (!text || button.dataset.confirm === "1") { action(); return; }
    button.dataset.confirm = "1";
    var label = button.textContent;
    button.textContent = "Delete? Click again";
    button.classList.add("anno-danger");
    setTimeout(function () {
      if (!button.isConnected) return;
      button.dataset.confirm = "";
      button.textContent = label;
      button.classList.remove("anno-danger");
    }, 3000);
  }

  function marker(id) { return document.querySelector('#doc .anno-marker[data-anno="' + id + '"]'); }
  function card(id) { return document.querySelector('#doc .anno-card[data-anno="' + id + '"]'); }

  /** Expand or collapse a note. Never changes the document or its pages. */
  function toggle(id, collapse) {
    var a = byId(id);
    if (!a) return;
    a.collapsed = collapse === undefined ? !a.collapsed : collapse;
    var c = card(id), m = marker(id);
    if (c) c.hidden = a.collapsed;
    if (m) {
      m.setAttribute("aria-expanded", a.collapsed ? "false" : "true");
      m.setAttribute("aria-label", "Note on “" + excerpt(a.quote, 60) + "”, " + (a.collapsed ? "collapsed" : "expanded"));
    }
    if (!a.collapsed && c) {
      var t = c.querySelector("textarea");
      autosize(t);
      t.focus({ preventScroll: true });
    } else if (m) m.focus({ preventScroll: true });
    scheduleSave();
  }

  // ---------------------------------------------------------------------------------------------
  // Creating and changing annotations

  function create(kind, color) {
    var r = selectionRange();
    if (r.error) { flash(r.error); return null; }
    var a = {
      id: newId(), start: r.start, end: r.end, quote: r.quote.replace(/\s+/g, " ").trim(),
      color: kind === "note" ? null : (COLORS.indexOf(color) >= 0 ? color : "yellow"),
      note: kind === "note" ? "" : null, collapsed: false, detached: false,
      created: now(), updated: now()
    };
    setContext(a);
    items.push(a);
    var sel = window.getSelection();
    if (sel) sel.removeAllRanges();
    hidePopover();
    redraw();
    scheduleSave();
    if (kind === "note") toggle(a.id, false);
    announce(kind === "note" ? "Note added" : COLOR_NAMES[a.color] + " highlight added");
    return a;
  }

  function setColor(id, color) {
    var a = byId(id);
    if (!a) return;
    a.color = color;
    a.updated = now();
    if (!a.color && (a.note === null || a.note === undefined)) { remove(id); return; }
    redraw();
    scheduleSave();
  }

  function addNote(id) {
    var a = byId(id);
    if (!a) return;
    if (a.note === null || a.note === undefined) { a.note = ""; a.updated = now(); }
    a.collapsed = false;
    redraw();
    scheduleSave();
    toggle(id, false);
  }

  function removeNote(id) {
    var a = byId(id);
    if (!a) return;
    if (!a.color) { remove(id); return; }
    a.note = null;
    a.updated = now();
    redraw();
    scheduleSave();
  }

  function remove(id) {
    items = items.filter(function (a) { return a.id !== id; });
    hidePopover();
    redraw();
    scheduleSave();
    announce("Removed");
  }

  function reattach(id) {
    var a = byId(id);
    if (!a) return;
    var r = selectionRange();
    if (r.error) { flash("Select the text this note belongs to, then choose Reattach."); return; }
    a.start = r.start;
    a.end = r.end;
    a.quote = r.quote.replace(/\s+/g, " ").trim();
    a.detached = false;
    delete a.detachedAt;
    a.updated = now();
    setContext(a);
    var sel = window.getSelection();
    if (sel) sel.removeAllRanges();
    redraw();
    scheduleSave();
    announce("Reattached");
  }

  function redraw() {
    var doc = document.getElementById("doc");
    if (!doc) return;
    var focusId = null, caret = null;
    var active = document.activeElement;
    if (active && active.classList && active.classList.contains("anno-text")) {
      focusId = active.closest(".anno-card").dataset.anno;
      caret = [active.selectionStart, active.selectionEnd];
    }
    clearDrawn(doc);
    drawHighlights(doc);
    srcMap = null;
    drawNotes(doc);
    refreshSidebar();
    if (focusId) {
      var c = card(focusId);
      var t = c && !c.hidden ? c.querySelector("textarea") : null;
      if (t) { t.focus({ preventScroll: true }); try { t.setSelectionRange(caret[0], caret[1]); } catch (e) { /* ignore */ } }
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Popover: shown over a selection (to highlight or add a note) or over a highlight (to change it)

  function hidePopover() {
    if (popover) { popover.remove(); popover = null; }
  }

  function colorButton(color, pressed, onClick) {
    var b = el("button", "anno-swatch anno-s-" + color);
    b.type = "button";
    b.setAttribute("aria-label", COLOR_NAMES[color] + " highlight");
    b.title = COLOR_NAMES[color];
    if (pressed) b.setAttribute("aria-pressed", "true");
    b.addEventListener("mousedown", function (e) { e.preventDefault(); });
    b.addEventListener("click", onClick);
    return b;
  }

  function textButton(label, onClick, cls) {
    var b = el("button", "anno-pop-btn" + (cls ? " " + cls : ""), label);
    b.type = "button";
    b.addEventListener("mousedown", function (e) { e.preventDefault(); });
    b.addEventListener("click", onClick);
    return b;
  }

  function showPopoverAt(rect, build) {
    hidePopover();
    popover = el("div", "anno-pop no-find no-anno");
    popover.setAttribute("role", "toolbar");
    build(popover);
    document.body.appendChild(popover);
    var w = popover.offsetWidth, h = popover.offsetHeight;
    var x = Math.min(window.innerWidth - w - 8, Math.max(8, rect.left + rect.width / 2 - w / 2));
    var y = rect.top - h - 8;
    if (y < 8) y = rect.bottom + 8;
    popover.style.left = x + "px";
    popover.style.top = y + "px";
  }

  function selectionPopover() {
    var sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.rangeCount) { hidePopover(); return; }
    var r = sel.getRangeAt(0);
    var doc = document.getElementById("doc");
    if (!doc.contains(r.commonAncestorContainer)) return;
    if (r.commonAncestorContainer.parentElement && r.commonAncestorContainer.parentElement.closest(".no-anno")) return;
    showPopoverAt(r.getBoundingClientRect(), function (p) {
      p.setAttribute("aria-label", "Highlight or add a note");
      COLORS.forEach(function (c) { p.appendChild(colorButton(c, false, function () { create("highlight", c); })); });
      p.appendChild(el("span", "anno-pop-sep"));
      p.appendChild(textButton("Add Note", function () { create("note"); }));
    });
  }

  function highlightPopover(mark) {
    var ids = mark.dataset.anno.split(" ");
    var a = byId(ids[ids.length - 1]);
    if (!a) return;
    showPopoverAt(mark.getBoundingClientRect(), function (p) {
      p.setAttribute("aria-label", "Change highlight");
      COLORS.forEach(function (c) { p.appendChild(colorButton(c, a.color === c, function () { setColor(a.id, c); hidePopover(); })); });
      p.appendChild(el("span", "anno-pop-sep"));
      if (a.note === null || a.note === undefined) p.appendChild(textButton("Add Note", function () { hidePopover(); addNote(a.id); }));
      else p.appendChild(textButton(a.collapsed ? "Show Note" : "Hide Note", function () { hidePopover(); toggle(a.id); }));
      if (a.color) p.appendChild(textButton("Remove Highlight", function () { setColor(a.id, null); hidePopover(); }));
      var del = textButton("Delete", function () { confirmThen(del, a.note, function () { remove(a.id); }); }, "anno-pop-danger");
      p.appendChild(del);
      if (ids.length > 1) p.appendChild(el("span", "anno-pop-note", ids.length + " overlap · see Notes"));
    });
  }

  document.addEventListener("mouseup", function (e) {
    if (e.button !== 0) return; // the right-click menu has its own Highlight and Add Note
    if (popover && popover.contains(e.target)) return;
    if (e.target.closest && e.target.closest(".anno-card, .anno-marker, .find-bar, .page-bar, .thumbs, #history, #review-bar")) return;
    setTimeout(function () {
      var sel = window.getSelection();
      if (sel && !sel.isCollapsed) { selectionPopover(); return; }
      var mark = e.target.closest ? e.target.closest("#doc mark.anno") : null;
      if (mark) highlightPopover(mark); else hidePopover();
    }, 0);
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && popover) { hidePopover(); e.stopPropagation(); }
  }, true);
  window.addEventListener("scroll", function () { hidePopover(); }, { passive: true });
  window.addEventListener("resize", function () {
    var st = root.mdPagesState ? root.mdPagesState() : null;
    if (!st || !st.paged) redraw(); // continuous text reflows with the window
  });

  // ---------------------------------------------------------------------------------------------
  // Notes and Highlights sidebar

  function sidebarPanel() {
    var panel = document.getElementById("notes-panel");
    if (panel) return panel;
    var nav = document.getElementById("thumbs");
    if (!nav) return null;
    panel = el("div", "notes-panel");
    panel.id = "notes-panel";
    panel.setAttribute("role", "region");
    panel.setAttribute("aria-label", "Notes and highlights");
    nav.appendChild(panel);
    return panel;
  }

  function entry(a) {
    var li = el("li", "notes-item");
    var b = el("button", "notes-entry");
    b.type = "button";
    var sw = el("span", "notes-swatch " + (a.color ? "anno-s-" + a.color : "notes-swatch-note"));
    sw.setAttribute("aria-hidden", "true");
    b.appendChild(sw);
    var body = el("span", "notes-body");
    body.appendChild(el("span", "notes-quote", "“" + excerpt(a.quote, 90) + "”"));
    if (a.note) body.appendChild(el("span", "notes-note", excerpt(a.note, 120)));
    var meta = (a.color ? COLOR_NAMES[a.color] + " highlight" : "Note") + (a.section ? " · " + a.section : "");
    body.appendChild(el("span", "notes-meta", meta));
    b.appendChild(body);
    b.setAttribute("aria-label", meta + ": " + excerpt(a.quote, 90) + (a.note ? ". Note: " + excerpt(a.note, 120) : ""));
    li.appendChild(b);
    return { li: li, button: b };
  }

  function refreshSidebar() {
    var panel = sidebarPanel();
    if (!panel) return;
    panel.textContent = "";
    var list = attached();
    var lost = items.filter(function (a) { return a.detached; });
    if (!list.length && !lost.length) {
      panel.appendChild(el("p", "notes-empty", "Select text, then pick a color to highlight it or choose Add Note. Highlights and notes stay on this Mac and never change the file."));
      return;
    }
    var ol = el("ol", "notes-list");
    list.forEach(function (a) {
      var en = entry(a);
      en.button.addEventListener("click", function () { root.mdShowAnnotation(a.id); });
      ol.appendChild(en.li);
    });
    panel.appendChild(ol);
    if (lost.length) {
      var h = el("h3", "notes-group", "Needs Reattachment (" + lost.length + ")");
      panel.appendChild(h);
      panel.appendChild(el("p", "notes-help", "The text these belonged to was removed, rewritten, or now appears more than once. Select the right text in the document and choose Reattach."));
      var ol2 = el("ol", "notes-list");
      lost.forEach(function (a) {
        var en = entry(a);
        en.button.disabled = true;
        en.li.classList.add("notes-lost");
        var meta = en.button.querySelector(".notes-meta");
        meta.textContent += " · was near line " + (a.lastLine || "?");
        var row = el("div", "notes-actions");
        var re = el("button", "anno-link", "Reattach to Selection");
        re.type = "button";
        re.addEventListener("mousedown", function (e) { e.preventDefault(); });
        re.addEventListener("click", function () { reattach(a.id); });
        row.appendChild(re);
        var del = el("button", "anno-link anno-danger-text", "Delete");
        del.type = "button";
        del.addEventListener("click", function () { confirmThen(del, a.note, function () { remove(a.id); }); });
        row.appendChild(del);
        en.li.appendChild(row);
        ol2.appendChild(en.li);
      });
      panel.appendChild(ol2);
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Messages

  var live = null;
  function announce(text) {
    if (!live) {
      live = el("div", "sr-only");
      live.setAttribute("aria-live", "polite");
      document.body.appendChild(live);
    }
    live.textContent = text;
  }

  var flashTimer = 0;
  function flash(text) {
    var f = document.getElementById("anno-flash");
    if (!f) {
      f = el("div", "anno-flash no-find");
      f.id = "anno-flash";
      f.setAttribute("role", "status");
      document.body.appendChild(f);
    }
    f.textContent = text;
    f.hidden = false;
    clearTimeout(flashTimer);
    flashTimer = setTimeout(function () { f.hidden = true; }, 3500);
    announce(text);
  }

  // ---------------------------------------------------------------------------------------------
  // Public

  root.MDAnnotations = {
    /** Called by the preview after each render (and after pages are laid out). */
    apply: function (doc, text) {
      reconcile(text);
      srcMap = null;
      drawHighlights(doc);
      srcMap = null;
      drawNotes(doc);
      refreshSidebar();
    },
    redraw: redraw
  };

  /** Loads saved annotations (a JSON string or object), or clears them with null. */
  root.mdSetAnnotations = function (data) {
    var obj = data;
    if (typeof data === "string") { try { obj = JSON.parse(data); } catch (e) { obj = null; } }
    if (obj && obj.format === FORMAT && Array.isArray(obj.items)) {
      items = obj.items.filter(function (a) { return a && typeof a.id === "string" && typeof a.start === "number" && typeof a.end === "number"; });
      loadedHash = obj.sourceHash || null;
    } else {
      items = [];
      loadedHash = null;
    }
    var rendered = sourceKnown;
    sourceKnown = false;
    if (rendered && root.mdRerender) root.mdRerender();
  };

  /** From the menu or context menu: "highlight" (optionally a color) or "note". */
  root.mdAnnotateSelection = function (kind, color) { return create(kind === "note" ? "note" : "highlight", color); };

  /** Removes highlights and notes that touch the selection (Edit > Remove Highlight). */
  root.mdRemoveAnnotationsInSelection = function () {
    var r = selectionRange();
    if (r.error) { flash(r.error); return; }
    var hit = items.filter(function (a) { return !a.detached && a.start < r.end && a.end > r.start; });
    if (!hit.length) { flash("No highlight in the selection."); return; }
    hit.forEach(function (a) { setColor(a.id, null); });
  };

  /** Scrolls to an annotation and opens its note (from the sidebar). */
  root.mdShowAnnotation = function (id) {
    var a = byId(id);
    if (!a || a.detached) return;
    var box = anchorBox(a);
    if (!box) return;
    box.mark.scrollIntoView({ block: "center" });
    if (a.note !== null && a.note !== undefined) toggle(id, false);
    else {
      box.mark.classList.add("anno-flash-mark");
      setTimeout(function () { box.mark.classList.remove("anno-flash-mark"); }, 1200);
    }
  };

  root.mdAnnotationsSaved = function (ok) {
    saveFailed = !ok;
    var f = document.getElementById("anno-error");
    if (!ok) {
      if (!f) {
        f = el("div", "anno-error no-find");
        f.id = "anno-error";
        f.setAttribute("role", "alert");
        document.body.appendChild(f);
      }
      f.textContent = "Highlights and notes couldn't be saved. They're kept while this window is open; the app will try again on the next change.";
      f.hidden = false;
    } else if (f) f.hidden = true;
  };

  root.mdAnnotationsState = function () {
    return { items: JSON.parse(JSON.stringify(items)), json: snapshot(), saveFailed: saveFailed };
  };

  root.mdAnnotationsFlushSave = function () {
    clearTimeout(saveTimer);
    post({ action: "annotations", json: snapshot() });
  };
})(typeof window !== "undefined" ? window : globalThis);
