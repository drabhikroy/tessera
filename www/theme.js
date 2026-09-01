/* theme.js
   Dark and light are handled entirely by bslib's native toggle, which
   sets data-bs-theme on the document and persists the choice. This file
   now owns only the colorblind palette overlay, applied as a class on
   the body so the map's group colors shift without touching anything
   bslib manages. */

(function () {
  "use strict";

  /* The five color settings. Standard needs no class, since the base
     stylesheet is the standard palette; the other four each add one.
     The list is written out rather than derived, so a setting cannot be
     added to the app without also being removed here on the way out,
     which is how two palettes end up applied at once. */
  var PALETTE_CLASSES = ["cb-deutan", "cb-protan", "cb-tritan", "cb-mono"];

  function applyPalette(name) {
    PALETTE_CLASSES.forEach(function (cls) {
      document.body.classList.remove(cls);
    });
    if (name && name !== "standard") {
      document.body.classList.add("cb-" + name);
    }
  }

  /* Reports whether the stylesheet in this browser understands both
     modes. A stale cached stylesheet is the usual reason it does not. */
  function themeStylesheetLive() {
    var probe = document.createElement("div");
    probe.style.display = "none";
    probe.style.color = "var(--bg)";
    document.body.appendChild(probe);
    var root = document.documentElement;
    var was = root.getAttribute("data-bs-theme");
    root.setAttribute("data-bs-theme", "dark");
    var dark = window.getComputedStyle(probe).color;
    root.setAttribute("data-bs-theme", "light");
    var light = window.getComputedStyle(probe).color;
    root.setAttribute("data-bs-theme", was || "dark");
    probe.remove();
    return dark !== light;
  }

  function warnStale() {
    if (document.getElementById("stale-css-warning")) return;
    var bar = document.createElement("div");
    bar.id = "stale-css-warning";
    bar.setAttribute("role", "alert");
    bar.textContent = "This browser is using an older copy of the style " +
      "sheet, so the appearance toggle cannot take effect. Reload the " +
      "page holding Shift to fetch the current one.";
    document.body.appendChild(bar);
  }

  var TOUR_KEY = "tessera-tour-seen";

  function tourSeen() {
    try {
      return window.localStorage.getItem(TOUR_KEY) === "yes";
    } catch (e) {
      return false;
    }
  }

  if (window.Shiny) {
    /* Scrolls one element into view inside whatever is scrolling around
     it. Used after a model answers.

     The first version looked once on the next animation frame and gave
     up. That was too early: the message and the rendered answer arrive
     in the same flush, and the browser has not necessarily put the new
     markup in the document by the time the handler runs, so it found
     nothing and did nothing. This one looks for up to two seconds.

     It also scrolls the ancestor itself rather than relying on
     scrollIntoView, which walks up to the window and can move the page
     behind the panel instead of the panel. */
  function scrollWithin(target) {
    var parent = target.parentElement;
    while (parent && parent !== document.body) {
      var style = window.getComputedStyle(parent);
      var scrolls = /(auto|scroll)/.test(style.overflowY);
      if (scrolls && parent.scrollHeight > parent.clientHeight + 4) {
        var offset = target.offsetTop - parent.offsetTop;
        var still = window.matchMedia &&
          window.matchMedia("(prefers-reduced-motion: reduce)").matches;
        var top = Math.max(0, offset - 12);
        if (still || !parent.scrollTo) {
          parent.scrollTop = top;
        } else {
          parent.scrollTo({ top: top, behavior: "smooth" });
        }
        return true;
      }
      parent = parent.parentElement;
    }
    return false;
  }

  Shiny.addCustomMessageHandler("scroll-to", function (id) {
    var tries = 0;
    function look() {
      tries += 1;
      var target = document.getElementById(id);
      if (target) {
        if (!scrollWithin(target)) {
          var still = window.matchMedia &&
            window.matchMedia("(prefers-reduced-motion: reduce)").matches;
          target.scrollIntoView({
            behavior: still ? "auto" : "smooth",
            block: "nearest"
          });
        }
        return;
      }
      if (tries < 40) window.setTimeout(look, 50);
    }
    look();
  });

  Shiny.addCustomMessageHandler("set-palette", applyPalette);
    Shiny.addCustomMessageHandler("tour-seen", function (unused) {
      try { window.localStorage.setItem(TOUR_KEY, "yes"); } catch (e) {}
    });
    /* Told once per session, after the connection opens, so the server
       knows whether this is a first visit. */
    $(document).on("shiny:connected", function () {
      Shiny.setInputValue("tour_seen", tourSeen());
    });
  }

  /* Restore the mode chosen on a previous visit, then make sure the
     toggle label matches whatever is actually on screen. */
  function restoreTheme() {
    var saved = null;
    try { saved = window.localStorage.getItem("tessera-theme"); } catch (e) {}
    var mode = saved === "light" || saved === "dark" ? saved : "dark";
    document.documentElement.setAttribute("data-bs-theme", mode);
    var btn = document.querySelector(".theme-toggle");
    if (btn) {
      btn.textContent = mode === "dark" ? "Light mode" : "Dark mode";
      btn.setAttribute("aria-label", mode === "dark" ?
        "Switch to light mode" : "Switch to dark mode");
    }
  }

  function ready() {
    restoreTheme();
    applyPalette("standard");
    if (!themeStylesheetLive()) warnStale();
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ready);
  } else {
    ready();
  }
})();
