/* AZURIFY Host - turns any remaining solid dark panel into glass.
   Most of the app is themed by class in azurify-glass.css; this catches the rest. */
(function () {
  'use strict';
  var seen = new WeakSet();
  var queued = false;
  var SKIP = /xterm|CodeMirror|cm-|Tooltip|tippy/;
  var GLASS = '.az-g, [class*="GreyRowBox"], [class*="TitledGreyBox___StyledDiv"], [class*="ContentBox___StyledDiv"], ' +
    '[class*="LoginFormContainer___StyledDiv"], [class*="Modal___StyledDiv"], [class*="Modal__ModalContainer"]';

  function darkLum(rgb) {
    var m = rgb.match(/rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)/);
    if (!m) return null;
    if ((m[4] === undefined ? 1 : parseFloat(m[4])) < 0.85) return null;
    // only neutral greys; coloured banners/badges keep their colour
    if (Math.max(m[1], m[2], m[3]) - Math.min(m[1], m[2], m[3]) > 40) return null;
    var lum = (0.2126 * m[1] + 0.7152 * m[2] + 0.0722 * m[3]) / 255;
    return lum < 0.42 ? lum : null;
  }

  function scan(root) {
    var list = root.querySelectorAll ? root.querySelectorAll('div,nav,section,aside,form,table,header,ul') : [];
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      if (seen.has(el)) continue;
      seen.add(el);
      if (SKIP.test(String(el.className))) continue;
      if (el.closest('.xterm, .CodeMirror, .cm-editor')) continue;
      var r = el.getBoundingClientRect();
      if (r.width < 80 || r.height < 24) continue;
      if (r.width > innerWidth * 0.98 && r.height > innerHeight * 0.9) { el.style.background = 'transparent'; continue; }
      var lum = darkLum(getComputedStyle(el).backgroundColor);
      if (lum === null) continue;
      // inside another glass surface: a flat chip, not glass-on-glass
      if (el.parentElement && el.parentElement.closest(GLASS)) { el.classList.add('az-chip'); continue; }
      el.classList.add('az-g');
      if (lum > 0.2) el.classList.add('az-g-strong');
    }
  }

  function schedule() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(function () { queued = false; scan(document.body); });
  }

  function start() {
    scan(document.body);
    new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
