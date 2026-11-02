/* Tags solid dark panels so azurify-glass.css can turn them into frosted glass.
   Pterodactyl's UI uses hashed class names, so we look at computed colours instead. */
(function () {
  'use strict';
  var seen = new WeakSet();
  var queued = false;

  function dark(rgb) {
    var m = rgb.match(/rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)/);
    if (!m) return null;
    var a = m[4] === undefined ? 1 : parseFloat(m[4]);
    if (a < 0.9) return null;
    var lum = (0.2126 * m[1] + 0.7152 * m[2] + 0.0722 * m[3]) / 255;
    return lum < 0.32 ? lum : null;
  }

  function scan(root) {
    var list = (root.querySelectorAll ? root.querySelectorAll('div,nav,section,aside,form,table,header,ul') : []);
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      if (seen.has(el)) continue;
      seen.add(el);
      var r = el.getBoundingClientRect();
      if (r.width < 90 || r.height < 28) continue;
      if (r.width > innerWidth * 0.98 && r.height > innerHeight * 0.9) continue; /* page wrapper */
      var lum = dark(getComputedStyle(el).backgroundColor);
      if (lum === null) continue;
      el.classList.add('az-g');
      if (lum > 0.16) el.classList.add('az-g-strong');
    }
  }

  function schedule() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(function () { queued = false; scan(document.body); addLogo(); });
  }

  function addLogo() {
    var f = document.querySelector('form[action*="login"], form');
    if (!f || document.querySelector('.az-login-logo') || !/login|password/i.test(location.pathname + f.innerHTML.slice(0, 600))) return;
    if (location.pathname.indexOf('/auth') !== 0) return;
    var img = document.createElement('img');
    img.className = 'az-login-logo';
    img.src = '/azurify/logo.png';
    img.alt = 'AZURIFY';
    f.parentNode.insertBefore(img, f);
  }

  function start() {
    scan(document.body);
    new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true });
    addLogo();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
