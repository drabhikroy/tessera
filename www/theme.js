/* theme.js
   Dark and light are handled entirely by bslib's native toggle, which
   sets data-bs-theme on the document and persists the choice. This file
   now owns only the colorblind palette overlay, applied as a class on
   the body so the map's group colors shift without touching anything
   bslib manages. */

(function () {
  "use strict";

  function applyPalette(name) {
    ["cb-deutan", "cb-tritan", "cb-mono"].forEach(function (cls) {
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
