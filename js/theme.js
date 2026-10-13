// Applies a saved theme choice before the page paints. "system" (no attribute) follows the OS setting.
(function () {
  'use strict';
  try {
    var saved = window.localStorage.getItem('guide-theme');
    if (saved === 'light' || saved === 'dark') {
      document.documentElement.setAttribute('data-theme', saved);
    }
  } catch (e) {
    // Storage can be blocked (private windows, file:// in some browsers). The OS setting applies.
  }
})();
