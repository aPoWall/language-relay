/* aim-app-mark.js · N1 · v1 · the product mark on the web (AIM apps rule 39) · no dependencies.
   One source: `aim-app-marks.svg`, the same file `build-marks.mjs` turns into `AIMAppMarks.swift`.
   The sprite is fetched once and injected into the page, so the symbols are available locally and
   work inside a browser extension, where a cross-document `<use href="file.svg#id">` does not. The
   injection prefixes every symbol id and tags the filled rectangle `aim-mark-signal`. A mark is drawn
   by cloning the symbol children into its own svg, so the signal sits in the light DOM of the page and
   `.aim-mark[data-mono] .aim-mark-signal` in `aim-app-shell.css` reaches it; a `<use>` reference puts the
   drawing in a shadow tree, where that rule selects nothing and the bar keeps the red. The reference is
   kept only as the fallback for a mark built before `install()` resolves, where there is nothing to clone.
   `data-mono` stays an attribute, so a surface can flip the mark both ways without rebuilding it.

     AIMAppMark.install('assets/aim-app-marks.svg')            // page
     AIMAppMark.install(chrome.runtime.getURL('aim-app-marks.svg'))  // extension
     AIMAppMark.el('prism', { size: 40 })                      // <span class="aim-mark">…</span>
     AIMAppMark.upgrade(document)                              // fills every [data-aim-mark]

   markup: <span class="aim-shell-mark" data-aim-mark="relay"></span>
           <span data-aim-mark="relay" data-aim-mark-size="18" data-mono></span>
   names: family · relay · aside · prism · calendar. `relay` is the arch glyph `relay-arch`;
   the first relay glyph keeps its retired id and is not a product mark (rule 4). */
(function (root, doc) {
  'use strict';
  var PREFIX = 'aim-mark-';
  var HOST_ID = 'aim-mark-sprite';
  /* case name -> symbol id in aim-app-marks.svg; the same map AIMAppMark.swift is generated with */
  var SYMBOLS = { family: 'family', relay: 'relay-arch', aside: 'aside', prism: 'prism', calendar: 'calendar' };
  /* symbol ids kept in the drawing by rule 4 but shipped by nothing; a reference to one is a defect */
  var RETIRED = ['relay'];
  var LABELS = {
    family: 'ai mindset', relay: 'language relay', aside: 'aside tweaks',
    prism: 'mem prism', calendar: 'calendar control'
  };
  var pending = null;
  var NODES = {};

  function installed() { return !!doc.getElementById(HOST_ID); }

  /* Injects the sprite once. Returns a promise that resolves with true when the marks are usable. */
  function install(url) {
    if (installed()) return Promise.resolve(true);
    if (pending) return pending;
    pending = root.fetch(url).then(function (r) {
      if (!r.ok) throw new Error('aim-app-mark: ' + r.status + ' for ' + url);
      return r.text();
    }).then(function (text) {
      var parsed = new root.DOMParser().parseFromString(text, 'image/svg+xml');
      var host = doc.createElementNS('http://www.w3.org/2000/svg', 'svg');
      host.id = HOST_ID;
      host.setAttribute('aria-hidden', 'true');
      host.setAttribute('focusable', 'false');
      host.style.position = 'absolute';
      host.style.width = '0';
      host.style.height = '0';
      host.style.overflow = 'hidden';
      var symbols = parsed.querySelectorAll('symbol'), i, symbol, rects, j, id;
      for (i = 0; i < symbols.length; i++) {
        symbol = doc.importNode(symbols[i], true);
        id = symbol.id;
        symbol.id = PREFIX + id;
        rects = symbol.querySelectorAll('rect');
        for (j = 0; j < rects.length; j++) {
          /* the frame and the glyph are drawn with `fill="none"`; the one filled rectangle is the signal,
             so the class is found by the drawing itself and no colour is repeated here */
          if ((rects[j].getAttribute('fill') || 'none').toLowerCase() !== 'none') rects[j].setAttribute('class', 'aim-mark-signal');
        }
        host.appendChild(symbol);
        NODES[id] = symbol;
      }
      (doc.body || doc.documentElement).appendChild(host);
      return true;
    }).catch(function (e) {
      pending = null;
      /* the page keeps working without the mark; the caller decides whether to retry */
      if (root.console) root.console.warn(String(e));
      return false;
    });
    return pending;
  }

  /* One mark element. `size` in px (default 40), `mono` drops the red signal, `title` overrides the name. */
  function el(name, options) {
    options = options || {};
    var symbol = SYMBOLS[name];
    if (!symbol) throw new Error('aim-app-mark: unknown mark ' + name);
    var size = options.size || 40;
    var span = doc.createElement('span');
    span.className = 'aim-mark';
    span.style.width = size + 'px';
    span.style.height = size + 'px';
    if (options.mono) span.setAttribute('data-mono', '');
    var svg = doc.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 48 48');
    svg.setAttribute('role', 'img');
    svg.setAttribute('aria-label', options.title || LABELS[name] || name);
    var source = NODES[symbol], kids, k, child, use;
    if (source) {
      kids = source.childNodes;
      for (k = 0; k < kids.length; k++) {
        child = kids[k];
        if (child.nodeType !== 1) continue;
        svg.appendChild(child.cloneNode(true));
      }
    } else {
      /* before install() resolves there is nothing to clone; the reference fills in once the sprite lands */
      use = doc.createElementNS('http://www.w3.org/2000/svg', 'use');
      use.setAttribute('href', '#' + PREFIX + symbol);
      svg.appendChild(use);
    }
    span.appendChild(svg);
    return span;
  }

  /* Fills every empty [data-aim-mark] under `scope`; returns how many were filled. */
  function upgrade(scope) {
    var nodes = (scope || doc).querySelectorAll('[data-aim-mark]'), n = 0, i, node, mark;
    for (i = 0; i < nodes.length; i++) {
      node = nodes[i];
      if (node.querySelector('svg')) continue;
      try { mark = el(node.getAttribute('data-aim-mark'), {
        size: Number(node.getAttribute('data-aim-mark-size')) || undefined,
        mono: node.hasAttribute('data-mono'),
        title: node.getAttribute('data-aim-mark-title') || undefined
      }); } catch (e) { continue; }
      node.appendChild(mark.firstChild);
      node.classList.add('aim-mark');
      /* the svg fills its box, so the size the caller asked for has to reach the box it is asked on */
      node.style.width = mark.style.width;
      node.style.height = mark.style.height;
      n += 1;
    }
    return n;
  }

  root.AIMAppMark = {
    names: Object.keys(SYMBOLS),
    symbols: SYMBOLS,
    retired: RETIRED,
    labels: LABELS,
    prefix: PREFIX,
    installed: installed,
    install: install,
    el: el,
    upgrade: upgrade
  };
}(typeof window !== 'undefined' ? window : this, typeof document !== 'undefined' ? document : null));
