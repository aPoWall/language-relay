/* AIM i18n · one language switch for every apps page · no dependencies.
   markup: <html lang="en" data-lang="en"> · text nodes <span class="i18n" data-en="…" data-ru="…"> · button #lang-toggle (en ⇄ ру)
   order: ?lang=ru|en → localStorage 'aim-apps-lang' (try/catch, page works without it) → <html data-i18n-auto> browser language → 'en'
   sets <html lang> + data-lang, keeps data-switching for 240 ms (relay glitch css), emits 'aim:lang' on document.
   api: AIMi18n.lang · AIMi18n.set('ru') · AIMi18n.toggle() · AIMi18n.apply() (after inserting new .i18n nodes) */
(function (root, doc) {
  'use strict';
  var KEY = 'aim-apps-lang', LANGS = { en: 1, ru: 1 }, html = doc.documentElement, lang = 'en', reduce = false;
  function stored() { try { return root.localStorage.getItem(KEY); } catch (e) { return null; } }
  function store(v) { try { root.localStorage.setItem(KEY, v); } catch (e) { /* storage unavailable: page still works */ } }
  function param() { try { return new URLSearchParams(root.location.search).get('lang'); } catch (e) { return null; } }
  function pick() {
    var q = param(); if (LANGS[q]) return q;
    var s = stored(); if (LANGS[s]) return s;
    if (html.hasAttribute('data-i18n-auto')) { var nav = String(root.navigator && root.navigator.language || '').toLowerCase(); return nav.indexOf('ru') === 0 ? 'ru' : 'en'; }
    var d = html.getAttribute('data-lang'); return LANGS[d] ? d : 'en';
  }
  function apply() {
    html.setAttribute('data-lang', lang); html.lang = lang;
    var nodes = doc.querySelectorAll('.i18n'), i, t;
    for (i = 0; i < nodes.length; i++) {
      t = nodes[i].getAttribute('data-' + lang);
      if (t != null) nodes[i].textContent = t;
    }
    nodes = doc.querySelectorAll('[data-' + lang + '-attr]');
    for (i = 0; i < nodes.length; i++) {
      /* data-en-attr="aria-label" + data-en="…": translate one attribute instead of the text */
      var a = nodes[i].getAttribute('data-' + lang + '-attr'), v = nodes[i].getAttribute('data-' + lang);
      if (a && v != null) nodes[i].setAttribute(a, v);
    }
    var btn = doc.getElementById('lang-toggle');
    if (btn) { btn.setAttribute('aria-label', lang === 'en' ? 'переключить на русский' : 'switch to english'); btn.setAttribute('data-lang', lang); }
  }
  function set(next, animate) {
    if (!LANGS[next]) return;
    lang = next; store(lang);
    var anim = animate !== false && !reduce;
    if (anim) html.setAttribute('data-switching', 'true');
    setTimeout(function () {
      apply();
      try { doc.dispatchEvent(new CustomEvent('aim:lang', { detail: { lang: lang } })); } catch (e) { /* old engine */ }
    }, anim ? 90 : 0);
    setTimeout(function () { html.removeAttribute('data-switching'); }, 240);
    if (param()) { try { var u = new URL(root.location.href); u.searchParams.set('lang', lang); root.history.replaceState(null, '', u); } catch (e) { /* keep url */ } }
  }
  function toggle() { set(lang === 'en' ? 'ru' : 'en'); }
  function bind() {
    var btn = doc.getElementById('lang-toggle');
    if (btn && !btn.__aimi18n) { btn.__aimi18n = 1; btn.addEventListener('click', toggle); }
    apply();
  }
  reduce = !!(root.matchMedia && root.matchMedia('(prefers-reduced-motion: reduce)').matches);
  lang = pick();
  html.setAttribute('data-lang', lang); html.lang = lang;
  if (doc.readyState === 'loading') doc.addEventListener('DOMContentLoaded', bind); else bind();
  root.AIMi18n = { get lang() { return lang; }, set: set, toggle: toggle, apply: apply, key: KEY };
})(window, document);
