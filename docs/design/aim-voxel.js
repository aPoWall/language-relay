/* AIM voxel · N1 · v2 · model → inline SVG · no dependencies.
   AIMVoxel.render(el, model, opts) · AIMVoxel.replay(el, mode) · AIMVoxel.toSVGString(model, opts) · AIMVoxel.mark(model, {size, mono})
   AIMVoxel.live(el) · AIMVoxel.moveSignal(el)
   model: {name, label, voxels:[[x,y,z,c] | {x,y,z,c}]} · c ∈ ink | mid | light | red
   opts: unit (px, 10) · animate 'assemble'|'scatter'|'none' · duration (ms, ≤2000) · shadow (true) ·
         whenVisible (true) · autoplay (false = build animated, wait for replay) · cull (static export only) · label · pad (units, 1) ·
         interactive (false; or data-interactive on el): hover parallax ±3 px by depth, click / Enter / Space → scatter → assemble ≤2 s
         and the single red signal moves to a neighbour cell of the same layer; reduced motion → only the signal moves.
   projection as VoxelView.swift: (x,y,z) → (ox + (x−y)·u, oy + (x+y)·0.48·u − z·u) */
(function (root) {
  'use strict';
  var K = 0.48, SHADOW = '#e8e9ed', MAX = 2000, PX = 3;
  /* faces: top · left (y+1) · right (x+1) · edge stroke */
  var PALETTE = {
    light: ['#ffffff', '#e8e9ed', '#f2f3f5', '#6b6e75'],
    mid:   ['#e8e9ed', '#6b6e75', '#6b6e75', '#ffffff'],
    ink:   ['#6b6e75', '#202124', '#6b6e75', '#ffffff'],
    red:   ['#db303d', '#db303d', '#db303d', '#ffffff']
  };
  /* mono: currentColor with three alpha levels (top · left · right), template-safe */
  var MONO = { light: [.18, .55, .32], mid: [.32, .72, .5], ink: [.55, 1, .72], red: [.55, 1, .72] };
  function voxels(model) {
    var list = Array.isArray(model) ? model : (model && model.voxels) || [];
    var out = [], seen = {};
    for (var i = 0; i < list.length; i++) {
      var v = list[i], o = Array.isArray(v) ? { x: v[0], y: v[1], z: v[2], c: v[3] } : v;
      var key = o.x + ',' + o.y + ',' + o.z;
      if (seen[key] || !PALETTE[o.c || 'light']) continue;
      seen[key] = 1;
      out.push({ x: +o.x, y: +o.y, z: +o.z, c: o.c || 'light' });
    }
    out.sort(function (a, b) {
      return (a.x + a.y + a.z) - (b.x + b.y + b.z) || (a.x + a.y) - (b.x + b.y) || a.z - b.z;
    });
    return out;
  }
  function pt(x, y, z, u) { return [(x - y) * u, (x + y) * K * u - z * u]; }
  function n(v) { return Math.round(v * 100) / 100; }
  function path(pts) {
    var d = 'M';
    for (var i = 0; i < pts.length; i++) d += (i ? 'L' : '') + n(pts[i][0]) + ' ' + n(pts[i][1]);
    return d + 'Z';
  }
  function faces(v, u) {
    var x = v.x, y = v.y, z = v.z;
    return [
      [pt(x, y, z + 1, u), pt(x + 1, y, z + 1, u), pt(x + 1, y + 1, z + 1, u), pt(x, y + 1, z + 1, u)],
      [pt(x, y + 1, z + 1, u), pt(x + 1, y + 1, z + 1, u), pt(x + 1, y + 1, z, u), pt(x, y + 1, z, u)],
      [pt(x + 1, y, z + 1, u), pt(x + 1, y + 1, z + 1, u), pt(x + 1, y + 1, z, u), pt(x + 1, y, z, u)]
    ];
  }
  function bounds(vs, u, pad, noShadow) {
    var b = { x0: 1e9, y0: 1e9, x1: -1e9, y1: -1e9 };
    function add(p) { if (p[0] < b.x0) b.x0 = p[0]; if (p[0] > b.x1) b.x1 = p[0]; if (p[1] < b.y0) b.y0 = p[1]; if (p[1] > b.y1) b.y1 = p[1]; }
    for (var i = 0; i < vs.length; i++) {
      var f = faces(vs[i], u);
      for (var j = 0; j < 3; j++) for (var k = 0; k < 4; k++) add(f[j][k]);
      if (noShadow) continue;
      add(pt(vs[i].x, vs[i].y, 0, u)); add(pt(vs[i].x + 1, vs[i].y + 1, 0, u));
      add(pt(vs[i].x + 1, vs[i].y, 0, u)); add(pt(vs[i].x, vs[i].y + 1, 0, u));
    }
    if (!vs.length) { b.x0 = -u; b.y0 = -u; b.x1 = u; b.y1 = u; }
    var p = (pad == null ? 1 : pad) * u;
    return { x: n(b.x0 - p), y: n(b.y0 - p), w: n(b.x1 - b.x0 + 2 * p), h: n(b.y1 - b.y0 + 2 * p) };
  }
  function shadowTiles(vs, u) {
    var cols = {}, s = '';
    for (var i = 0; i < vs.length; i++) cols[vs[i].x + ',' + vs[i].y] = vs[i];
    for (var k in cols) {
      var v = cols[k], x = v.x + 0.08, y = v.y + 0.08, e = 0.84;
      s += '<path d="' + path([pt(x, y, 0, u), pt(x + e, y, 0, u), pt(x + e, y + e, 0, u), pt(x, y + e, 0, u)]) + '"/>';
    }
    return s ? '<g fill="' + SHADOW + '">' + s + '</g>' : '';
  }
  function rnd(i) { var t = (i + 1) * 9301 + 49297; return ((t % 233280) / 233280) - 0.5; }
  function build(model, o, animated) {
    var u = +o.unit || 10, vs = voxels(model), b = bounds(vs, u, o.pad), has = {}, i, live = animated || o.interactive;
    var lo = 1e9, hi = -1e9;
    for (i = 0; i < vs.length; i++) { has[vs[i].x + ',' + vs[i].y + ',' + vs[i].z] = 1; var d = vs[i].x + vs[i].y; if (d < lo) lo = d; if (d > hi) hi = d; }
    var cull = animated ? false : o.cull !== false, cx = b.x + b.w / 2, cy = b.y + b.h / 2, span = Math.max(1, hi - lo);
    var T = Math.min(MAX, Math.max(200, +o.duration || 1600)), N = Math.max(1, vs.length), s = '';
    for (i = 0; i < vs.length; i++) {
      var v = vs[i], f = faces(v, u), c = PALETTE[v.c], g = '';
      var show = [!cull || !has[v.x + ',' + v.y + ',' + (v.z + 1)], !cull || !has[v.x + ',' + (v.y + 1) + ',' + v.z], !cull || !has[(v.x + 1) + ',' + v.y + ',' + v.z]];
      for (var j = 0; j < 3; j++) if (show[j]) g += '<path fill="' + c[j] + '" d="' + path(f[j]) + '"/>';
      if (!g) continue;
      var st = '';
      if (live) {
        var px = (v.x - v.y) * u, py = (v.x + v.y) * K * u - v.z * u;
        var tx = (px - cx) * 1.1 + rnd(i) * 6 * u, ty = (py - cy) * 0.9 - 3.5 * u + rnd(i * 7) * 4 * u;
        st = ' style="--tx:' + n(tx) + 'px;--ty:' + n(ty) + 'px;--i:' + n(i / N) + ';--dz:' + n(((v.x + v.y - lo) / span) * 2 - 1) + '"';
      }
      s += '<g class="aimv-c" stroke="' + c[3] + '" stroke-opacity=".35" stroke-width="' + n(u * 0.06) + '" stroke-linejoin="round"' + st + '>' + g + '</g>';
    }
    var label = o.label || (model && (model.label || model.name)) || 'voxel figure';
    var head = '<svg xmlns="http://www.w3.org/2000/svg" class="aimv" viewBox="' + b.x + ' ' + b.y + ' ' + b.w + ' ' + b.h + '" width="' + b.w + '" height="' + b.h + '" role="img" aria-label="' + esc(label) + '"' + (live ? ' style="--aimv-t:' + n(T * 0.45) + 'ms;--aimv-s:' + n(T * 0.55) + 'ms;max-width:100%;height:auto"' : '') + '>';
    return head + '<title>' + esc(label) + '</title>' + (o.shadow === false ? '' : shadowTiles(vs, u)) + '<g class="aimv-cubes">' + s + '</g></svg>';
  }
  /* icon-size export: one character, no shadow, no strokes; mono → currentColor only (template icons, dark favicons) */
  function mark(model, opts) {
    var o = opts || {}, size = +o.size || 32, vs = voxels(model), b = bounds(vs, 10, o.pad == null ? 0.2 : o.pad, true), has = {}, s = '', i;
    for (i = 0; i < vs.length; i++) has[vs[i].x + ',' + vs[i].y + ',' + vs[i].z] = 1;
    for (i = 0; i < vs.length; i++) {
      var v = vs[i], f = faces(v, 10), c = o.mono ? MONO[v.c] : PALETTE[v.c];
      var show = [!has[v.x + ',' + v.y + ',' + (v.z + 1)], !has[v.x + ',' + (v.y + 1) + ',' + v.z], !has[(v.x + 1) + ',' + v.y + ',' + v.z]];
      for (var j = 0; j < 3; j++) if (show[j]) s += '<path ' + (o.mono ? 'fill-opacity="' + c[j] + '"' : 'fill="' + c[j] + '"') + ' d="' + path(f[j]) + '"/>';
    }
    var side = Math.max(b.w, b.h), x = n(b.x - (side - b.w) / 2), y = n(b.y - (side - b.h) / 2);
    return '<svg xmlns="http://www.w3.org/2000/svg" class="aimv-mark" viewBox="' + x + ' ' + y + ' ' + n(side) + ' ' + n(side) + '" width="' + size + '" height="' + size + '" aria-hidden="true"' +
      (o.mono ? ' fill="currentColor"' : '') + ' shape-rendering="geometricPrecision">' + s + '</svg>';
  }
  function esc(t) { return String(t).replace(/[&<>"]/g, function (m) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[m]; }); }
  var CSS = '.aimv .aimv-c{transform:translate(calc(var(--mx,0px) * var(--dz,0)),calc(var(--my,0px) * var(--dz,0)))}' +
    '.aimv[data-live] .aimv-c{transition:transform 160ms ease-out}' +
    '.aimv[data-anim=assemble] .aimv-c{animation:aimv-in var(--aimv-t) cubic-bezier(.2,.8,.2,1) both;animation-delay:calc(var(--aimv-s) * var(--i,0))}' +
    '.aimv[data-anim=scatter] .aimv-c{animation:aimv-out var(--aimv-t) cubic-bezier(.6,0,.8,.4) forwards;animation-delay:calc(var(--aimv-s) * (1 - var(--i,0)))}' +
    '@keyframes aimv-in{from{transform:translate(var(--tx),var(--ty));opacity:0}}' +
    '@keyframes aimv-out{to{transform:translate(var(--tx),var(--ty));opacity:0}}' +
    '[data-aimv-live]{cursor:pointer;outline-offset:4px}' +
    '@media(prefers-reduced-motion:reduce){.aimv .aimv-c{animation:none!important;transition:none!important}}';
  function ensureCSS(doc) {
    if (!doc || doc.getElementById('aimv-style')) return;
    var st = doc.createElement('style'); st.id = 'aimv-style'; st.textContent = CSS; doc.head.appendChild(st);
  }
  function reduced() { return !!(root.matchMedia && root.matchMedia('(prefers-reduced-motion: reduce)').matches); }
  function replay(el, mode) {
    var st = el && el.__aimv; if (!st) return;
    mode = mode || st.mode || 'assemble';
    if (mode === 'none' || reduced()) { st.svg.removeAttribute('data-anim'); return; }
    st.svg.removeAttribute('data-anim'); timing(st.svg, st.T);
    void st.svg.getBoundingClientRect();
    st.svg.setAttribute('data-anim', mode);
  }
  function timing(svg, T) { svg.style.setProperty('--aimv-t', n(T * 0.45) + 'ms'); svg.style.setProperty('--aimv-s', n(T * 0.55) + 'ms'); }
  /* the single red signal steps to a neighbour cell of the same layer (swap colours with an existing visible neighbour) */
  function moveSignal(el) {
    var st = el && el.__aimv; if (!st) return false;
    var vs = voxels(st.model), reds = [], map = {}, i;
    for (i = 0; i < vs.length; i++) { map[vs[i].x + ',' + vs[i].y + ',' + vs[i].z] = vs[i]; if (vs[i].c === 'red') reds.push(vs[i]); }
    if (reds.length !== 1) return false;
    var r = reds[0], dirs = [[1, 0], [0, 1], [-1, 0], [0, -1]], k = st.step || 0, hit = null, j;
    function open(v) { return !map[v.x + ',' + v.y + ',' + (v.z + 1)] || !map[v.x + ',' + (v.y + 1) + ',' + v.z] || !map[(v.x + 1) + ',' + v.y + ',' + v.z]; }
    /* same layer, step 1 then 2 (calendar days sit two cells apart), target must show at least one face */
    for (i = 0; i < 4 && !hit; i++) for (j = 1; j <= 2 && !hit; j++) {
      var d = dirs[(k + i) % 4], nb = map[(r.x + d[0] * j) + ',' + (r.y + d[1] * j) + ',' + r.z];
      if (nb && nb.c !== 'red' && open(nb)) { hit = nb; k = (k + i + 1) % 4; }
    }
    if (!hit) return false;
    var swap = hit.c; hit.c = 'red'; r.c = swap; st.step = k;
    st.model = { name: st.model && st.model.name, label: st.model && st.model.label, voxels: vs.map(function (v) { return [v.x, v.y, v.z, v.c]; }) };
    return true;
  }
  function dress(st) {
    if (!st.opts.interactive) return st.svg;
    st.svg.setAttribute('aria-hidden', 'true');
    if (!reduced()) st.svg.setAttribute('data-live', '');
    return st.svg;
  }
  function rebuild(el, animated) {
    var st = el.__aimv;
    el.innerHTML = build(st.model, st.opts, animated);
    st.svg = el.firstChild;
    return dress(st);
  }
  function pulse(el) {
    var st = el.__aimv; if (!st || st.busy) return;
    if (reduced()) { moveSignal(el); rebuild(el, true); return; }
    var T = Math.min(1000, st.T / 2);
    st.busy = 1; timing(st.svg, T); st.svg.style.removeProperty('--mx'); st.svg.style.removeProperty('--my');
    st.svg.removeAttribute('data-anim'); void st.svg.getBoundingClientRect(); st.svg.setAttribute('data-anim', 'scatter');
    st.tm = setTimeout(function () {
      moveSignal(el);
      var svg = rebuild(el, true); timing(svg, T);
      void svg.getBoundingClientRect(); svg.setAttribute('data-anim', 'assemble');
      st.tm = setTimeout(function () { st.busy = 0; }, T);
    }, T);
  }
  function live(el) {
    var st = el && el.__aimv; if (!st || st.bound) return;
    st.bound = 1;
    var label = st.opts.label || (st.model && (st.model.label || st.model.name)) || 'voxel figure';
    el.setAttribute('role', 'img'); el.setAttribute('aria-label', label);
    if (!el.hasAttribute('tabindex')) el.setAttribute('tabindex', '0');
    el.setAttribute('data-aimv-live', '');
    el.addEventListener('pointermove', function (e) {
      var s = el.__aimv; if (!s || s.busy || reduced()) return;
      var r = s.svg.getBoundingClientRect(); if (!r.width) return;
      var vb = s.svg.viewBox.baseVal, scale = r.width / (vb.width || r.width);
      var nx = ((e.clientX - r.left) / r.width) * 2 - 1, ny = ((e.clientY - r.top) / r.height) * 2 - 1;
      s.svg.style.setProperty('--mx', n(nx * PX / scale) + 'px'); s.svg.style.setProperty('--my', n(ny * PX / scale) + 'px');
    });
    el.addEventListener('pointerleave', function () { var s = el.__aimv; if (s) { s.svg.style.removeProperty('--mx'); s.svg.style.removeProperty('--my'); } });
    el.addEventListener('click', function () { pulse(el); });
    el.addEventListener('keydown', function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pulse(el); } });
  }
  function render(el, model, opts) {
    var o = opts || {}, mode = o.animate || 'none', animated = mode !== 'none';
    if (o.interactive == null && el.hasAttribute && el.hasAttribute('data-interactive')) o = Object.assign({ interactive: true }, o);
    ensureCSS(el.ownerDocument);
    var prev = el.__aimv;
    if (prev && prev.io) prev.io.disconnect();
    if (prev && prev.tm) clearTimeout(prev.tm);
    el.innerHTML = build(model, o, animated || !!o.interactive);
    var svg = el.firstChild;
    el.__aimv = { svg: svg, mode: mode, model: model, opts: o, bound: prev ? prev.bound : 0, step: 0, T: Math.min(MAX, Math.max(200, +o.duration || 1600)) };
    if (o.interactive) { dress(el.__aimv); live(el); }
    if (!animated || reduced() || o.autoplay === false) return svg;
    if (o.whenVisible !== false && 'IntersectionObserver' in root) {
      var io = new IntersectionObserver(function (es) {
        for (var i = 0; i < es.length; i++) if (es[i].isIntersecting) { io.disconnect(); replay(el, mode); }
      }, { threshold: 0.2 });
      io.observe(el); el.__aimv.io = io;
    } else replay(el, mode);
    return svg;
  }
  function toSVGString(model, opts) { return build(model, opts || {}, false); }
  root.AIMVoxel = { render: render, replay: replay, live: live, pulse: pulse, moveSignal: moveSignal, mark: mark, toSVGString: toSVGString, voxels: voxels, project: pt, palette: PALETTE, css: CSS, version: 2 };
})(typeof window !== 'undefined' ? window : globalThis);
