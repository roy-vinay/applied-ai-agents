// Renders Markdown for the preview. No raw HTML from documents is rendered, so scripts in a
// document never run. Links and images are routed through the app (see mdRender below).
(function (root) {
  "use strict";
  var md = root.markdownit({ html: false, linkify: true, typographer: false });

  function slugify(s) {
    return s.trim().toLowerCase()
      .replace(/[^\p{L}\p{N}\s_-]/gu, "")
      .replace(/\s+/g, "-");
  }

  // Heading ids (GitHub style, unique) and task-list checkboxes (display only).
  md.core.ruler.push("headings_and_tasks", function (state) {
    var used = {};
    var tokens = state.tokens;
    for (var i = 0; i < tokens.length; i++) {
      var t = tokens[i];
      if (t.type === "heading_open" && tokens[i + 1] && tokens[i + 1].type === "inline") {
        var base = slugify(tokens[i + 1].content) || "section";
        var id = base;
        if (used[base] !== undefined) { used[base] += 1; id = base + "-" + used[base]; } else { used[base] = 0; }
        t.attrSet("id", id);
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

  function notice(el, text) {
    var span = document.createElement("span");
    span.className = "notice";
    span.setAttribute("role", "note");
    span.textContent = text;
    el.replaceWith(span);
  }

  root.mdRender = function (src) {
    var y = window.scrollY;
    var doc = document.getElementById("doc");
    doc.innerHTML = md.render(src);
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
        img.src = "mdeditdiff-res://image/?p=" + encodeURIComponent(s);
      })(imgs[i]);
    }
    window.scrollTo(0, y);
  };

  root.mdSetFontSize = function (px) {
    document.documentElement.style.setProperty("--size", px + "px");
  };

  document.addEventListener("click", function (e) {
    var a = e.target.closest ? e.target.closest("a") : null;
    if (!a) return;
    e.preventDefault();
    var href = a.getAttribute("href") || "";
    if (href.charAt(0) === "#") {
      var target = document.getElementById(decodeURIComponent(href.slice(1)));
      if (target) target.scrollIntoView();
      return;
    }
    if (root.webkit && root.webkit.messageHandlers && root.webkit.messageHandlers.link) {
      root.webkit.messageHandlers.link.postMessage(href);
    }
  });
})(typeof window !== "undefined" ? window : globalThis);
