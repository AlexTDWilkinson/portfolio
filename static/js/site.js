// Theme toggle and the hold-to-reveal email address.
//
// This file is loaded twice on purpose: once in <head> with the theme applied
// immediately (so the page never flashes the wrong colours), and the rest
// wired up on DOMContentLoaded.

(function () {
  "use strict";

  // ---- theme -------------------------------------------------------------
  // Stored choice wins; with nothing stored we follow the OS. The class goes
  // on <html> because Tailwind's `dark:` variants are configured for the class
  // strategy (see tailwind.config.js).
  var STORAGE_KEY = "theme";

  function storedTheme() {
    try {
      return window.localStorage.getItem(STORAGE_KEY);
    } catch (err) {
      // Private mode / storage disabled - fall back to the OS preference.
      return null;
    }
  }

  function applyTheme(theme) {
    document.documentElement.classList.toggle("dark", theme === "dark");
  }

  function systemTheme() {
    return window.matchMedia &&
      window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light";
  }

  applyTheme(storedTheme() || systemTheme());

  // The OS preference keeps driving the page until the visitor picks a side.
  if (window.matchMedia) {
    window
      .matchMedia("(prefers-color-scheme: dark)")
      .addEventListener("change", function (event) {
        if (!storedTheme()) {
          applyTheme(event.matches ? "dark" : "light");
        }
      });
  }

  function toggleTheme() {
    var next = document.documentElement.classList.contains("dark")
      ? "light"
      : "dark";
    applyTheme(next);
    try {
      window.localStorage.setItem(STORAGE_KEY, next);
    } catch (err) {
      // Nothing to do - the choice just will not survive a reload.
    }
  }

  // ---- email -------------------------------------------------------------
  // The address is never in the HTML and never in this file as a readable
  // string: it is assembled from character codes, and only after a deliberate
  // two-second press. A scraper would have to run the page and hold a button.
  var HOLD_MS = 2000;
  var LOCAL_CODES = [97, 108, 101, 120];
  var DOMAIN_CODES = [104, 111, 117, 115, 107, 105, 46, 99, 97];

  function buildAddress() {
    var parts = [];
    var index = 0;
    for (index = 0; index < LOCAL_CODES.length; index += 1) {
      parts.push(String.fromCharCode(LOCAL_CODES[index]));
    }
    parts.push(String.fromCharCode(64));
    for (index = 0; index < DOMAIN_CODES.length; index += 1) {
      parts.push(String.fromCharCode(DOMAIN_CODES[index]));
    }
    return parts.join("");
  }

  function setUpEmail() {
    var button = document.getElementById("email-hold");
    var fill = document.getElementById("email-fill");
    var label = document.getElementById("email-label");
    var result = document.getElementById("email-result");
    var link = document.getElementById("email-link");
    var copy = document.getElementById("email-copy");
    var copyState = document.getElementById("email-copy-state");
    if (!button || !fill || !label || !result || !link || !copy) {
      return;
    }

    var timer = null;
    var revealed = false;

    function reveal() {
      if (revealed) {
        return;
      }
      revealed = true;
      var address = buildAddress();
      link.textContent = address;
      link.href = String.fromCharCode(109, 97, 105, 108, 116, 111, 58) + address;
      button.classList.add("hidden");
      result.classList.remove("hidden");
      link.focus();
    }

    function startHold() {
      if (revealed || timer) {
        return;
      }
      // The bar is a CSS transition, so the browser animates it off the main
      // thread and a busy page cannot make the hold look stuck.
      fill.style.transition = "width " + HOLD_MS + "ms linear";
      fill.style.width = "100%";
      label.textContent = "Keep holding...";
      timer = window.setTimeout(function () {
        timer = null;
        reveal();
      }, HOLD_MS);
    }

    function cancelHold() {
      if (timer) {
        window.clearTimeout(timer);
        timer = null;
      }
      if (revealed) {
        return;
      }
      fill.style.transition = "width 150ms ease-out";
      fill.style.width = "0%";
      label.textContent = "Hold to reveal my email";
    }

    button.addEventListener("pointerdown", function (event) {
      event.preventDefault();
      startHold();
    });
    button.addEventListener("pointerup", cancelHold);
    button.addEventListener("pointerleave", cancelHold);
    button.addEventListener("pointercancel", cancelHold);
    // Keyboard: space or enter held down repeats keydown, which is fine - the
    // guard in startHold() means only the first one starts the timer.
    button.addEventListener("keydown", function (event) {
      if (event.key === " " || event.key === "Enter") {
        event.preventDefault();
        startHold();
      }
    });
    button.addEventListener("keyup", function (event) {
      if (event.key === " " || event.key === "Enter") {
        cancelHold();
      }
    });
    button.addEventListener("blur", cancelHold);
    // Touch browsers pop a text-selection callout on a long press; this is a
    // button, so there is nothing worth selecting.
    button.addEventListener("contextmenu", function (event) {
      event.preventDefault();
    });

    copy.addEventListener("click", function () {
      var address = buildAddress();
      if (!navigator.clipboard) {
        return;
      }
      navigator.clipboard.writeText(address).then(function () {
        if (copyState) {
          copyState.textContent = "Copied";
          window.setTimeout(function () {
            copyState.textContent = "Copy";
          }, 1500);
        }
      });
    });
  }

  // ---- wiring ------------------------------------------------------------
  function ready() {
    var toggle = document.getElementById("theme-toggle");
    if (toggle) {
      toggle.addEventListener("click", toggleTheme);
    }
    setUpEmail();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ready);
  } else {
    ready();
  }
})();
