// Graph explorer: drill down an aggregated tsibble one disaggregation at a
// time, with time plots of everything reached.
//
// graph_explore() in graph-explore.R serves this page, the structure
// (api/spec) and the series on request (api/series). The left column holds the
// series graph above the dimension graph; the right column the focused series
// above a view (grid of small multiples, overlay, stacked or season plots) of
// either its last chosen children or the pinned series.
//
// Clicking a node opens a menu of its dimension-graph node's out-edges, and
// choosing one draws that group of children. The dimension graph has one node
// per key combination given to aggregate_key(), so any structure works; chains
// of nested keys, when the combinations cross them, only colour and label it.
// Right-clicking a node collapses its children; shift-clicking pins it.
// Hovering a node highlights its time plot wherever it is drawn, or previews
// it beside the node when it isn't.
//
// render functions are pure functions of the state, and handlers only change
// the state, so CSS transitions animate every change.
(function () {
  'use strict';

  // Depth palette (level_colours), one edge colour per chain of the structure
  // (constraint_colours), forecast models, series within a group, the
  // children merged into "Other" when there are more than CAT colours, and
  // the ends of the season plots' gradient. They are CSS tokens of the theme,
  // read again whenever it changes.
  var LEVEL, CHAIN, MODEL, CAT, OTHER, INK, SEASON, BAND_OP;
  function readPalette() {
    var cs = getComputedStyle(document.documentElement);
    var tok = function (n) { return cs.getPropertyValue('--' + n).trim(); };
    var list = function (n, k) { var out = []; for (var i = 0; i < k; i++) out.push(tok(n + '-' + i)); return out; };
    LEVEL = list('level', 5);
    CHAIN = list('chain', 4);
    MODEL = list('model', 5);
    CAT = list('cat', 8);
    OTHER = tok('other');
    INK = tok('ink');
    SEASON = [hexRgb(tok('season-old')), hexRgb(tok('season-new'))];
    BAND_OP = parseFloat(tok('band-op')) || 1;
  }
  function hexRgb(h) { var n = parseInt(h.replace('#', ''), 16); return [n >> 16 & 255, n >> 8 & 255, n & 255]; }
  // Themes cycle system → light → dark; system follows prefers-color-scheme
  var THEMES = [['system', 'Theme: system'], ['light', 'Theme: light'], ['dark', 'Theme: dark']];
  // Icons on a 16px grid, drawn in the text colour: [stroked path, filled path]
  var ICONS = {
    system: ['M8 2a6 6 0 1 0 0 12A6 6 0 1 0 8 2z', 'M8 2a6 6 0 0 0 0 12z'],
    light: ['M8 5a3 3 0 1 0 0 6 3 3 0 1 0 0-6zM8 1v2M8 13v2M1 8h2M13 8h2M3 3l1.4 1.4M11.6 11.6L13 13M3 13l1.4-1.4M11.6 4.4L13 3', ''],
    dark: ['', 'M13.5 10A6 6 0 0 1 6 2.5 6 6 0 1 0 13.5 10z'],
    reset: ['M3 8a5 5 0 1 0 1.6-3.7M3 2v3h3', ''],
    fork: ['M4 2v2c0 2.5 4 3 4 6v4M12 2v2c0 2.5-4 3-4 6', '']
  };
  // The series graph's gestures, for its help card
  var HELP = [['Click', 'split'], ['Right-click', 'collapse'], ['Shift-click', 'pin'], ['Drag', 'pan'], ['Scroll', 'zoom'], ['Double-click', 'reset view']];
  function icon(parent, name) {
    parent.textContent = '';
    var svg = svgEl('svg', parent, { width: 16, height: 16, viewBox: '0 0 16 16', 'aria-hidden': 'true' });
    if (ICONS[name][0]) svgEl('path', svg, { d: ICONS[name][0], fill: 'none', stroke: 'currentColor', 'stroke-width': 1.5, 'stroke-linecap': 'round' });
    if (ICONS[name][1]) svgEl('path', svg, { d: ICONS[name][1], fill: 'currentColor' });
    return svg;
  }
  var THEME = 'graph-explore-theme';
  var darkQuery = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  function applyTheme(t) {
    if (t === 'light' || t === 'dark') document.documentElement.setAttribute('data-theme', t);
    else document.documentElement.removeAttribute('data-theme');
  }
  var SVGNS = 'http://www.w3.org/2000/svg';
  // Groups wider than this show their first CAP children and a "+k more" chip
  var CAP = 12;
  // Left margin of a compact plot, room for its y labels
  var YLAB = 34;
  var STORE = 'graph-explore-layout';
  var TABS = [['grid', 'Grid'], ['overlay', 'Overlay'], ['stacked', 'Stacked'], ['season', 'Season']];
  // Y scale options of each view tab for each set of series, the first being
  // the default. Pinned series don't add up to a whole, so they don't stack.
  var FREE = [['free', 'Free y'], ['shared', 'Shared y']], OVERLAY = [['values', 'Values'], ['indexed', 'Indexed']];
  var SCALES = {
    children: { grid: FREE.concat([['log', 'Log y'], ['parent', 'Share of parent']]), overlay: OVERLAY, stacked: [['total', 'Totals'], ['share', 'Shares']], season: FREE },
    pinned: { grid: FREE.concat([['log', 'Log y'], ['parent', 'Share of total']]), overlay: OVERLAY, season: FREE }
  };
  // Orders of the series in the views that don't stack them
  var SORTS = [['key', 'Key'], ['size', 'Size'], ['growth', 'Growth']];

  function el(tag, cls, parent, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (parent) parent.appendChild(e);
    if (text != null) e.textContent = text;
    return e;
  }
  function svgEl(tag, parent, attrs) {
    var e = document.createElementNS(SVGNS, tag);
    for (var k in attrs || {}) if (attrs[k] != null) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }
  function css(e, s) { for (var k in s) e.style[k] = s[k]; return e; }
  function px(x) { return x.toFixed(1) + 'px'; }
  function level(d) { return LEVEL[Math.min(d, LEVEL.length - 1)]; }
  function clamp(x, lo, hi) { return Math.max(lo, Math.min(hi, x)); }
  function load(key) { try { return JSON.parse(localStorage.getItem(key)); } catch (e) { return null; } }
  function save(key, v) { try { localStorage.setItem(key, JSON.stringify(v)); } catch (e) { /* storage blocked */ } }

  // A line from (x1, y1) to (x2, y2), drawn as a rotated box so it can be animated
  function lineStyle(x1, y1, x2, y2) {
    var dx = x2 - x1, dy = y2 - y1, len = Math.sqrt(dx * dx + dy * dy);
    return { left: px(x1), top: px(y1), width: px(len), transform: 'rotate(' + (Math.atan2(dy, dx) * 180 / Math.PI).toFixed(2) + 'deg)' };
  }

  // ---- Time plots ------------------------------------------------------------

  // The widest 1, 2, 5 step that still puts at least n ticks inside the range
  function niceStep(r, n) {
    var count = function (s) { return Math.floor(r[1] / s) - Math.ceil(r[0] / s) + 1; };
    for (var e = Math.ceil(Math.log10(r[1] - r[0])); ; e--) {
      var m = Math.pow(10, e);
      for (var f = 0; f < 3; f++) { var s = [5, 2, 1][f] * m; if (count(s) >= n) return s; }
    }
  }
  function pctLabel(v) { return +(100 * v).toFixed(1) + '%'; }
  function tickLabel(v) {
    var r = function (x) { return String(+x.toFixed(2)); }, a = Math.abs(v);
    return a >= 1e9 ? r(v / 1e9) + 'B' : a >= 1e6 ? r(v / 1e6) + 'M' : a >= 1e3 ? r(v / 1e3) + 'k' : r(v);
  }
  // The range of every value, padded so lines clear the edges
  function extent(arrays) {
    var lo = Infinity, hi = -Infinity;
    arrays.forEach(function (a) {
      for (var i = 0; i < a.length; i++) if (a[i] != null) { if (a[i] < lo) lo = a[i]; if (a[i] > hi) hi = a[i]; }
    });
    if (lo === Infinity) return [0, 1];
    var pad = (hi - lo) * 0.06 || Math.abs(hi) * 0.1 || 1;
    return [lo >= 0 ? Math.max(0, lo - pad) : lo - pad, hi + pad];
  }
  // A path through (x, y), broken at missing values
  function pathD(xs, ys, X, Y) {
    var d = '', pen = false;
    for (var i = 0; i < ys.length; i++) {
      if (ys[i] == null) { pen = false; continue; }
      d += (pen ? 'L' : 'M') + X(xs[i]).toFixed(1) + ',' + Y(ys[i]).toFixed(1);
      pen = true;
    }
    return d;
  }
  function areaD(xs, lo, hi, X, Y) {
    var top = [], bottom = [];
    for (var i = 0; i < xs.length; i++) {
      if (lo[i] == null || hi[i] == null) continue;
      top.push(X(xs[i]).toFixed(1) + ',' + Y(hi[i]).toFixed(1));
      bottom.unshift(X(xs[i]).toFixed(1) + ',' + Y(lo[i]).toFixed(1));
    }
    return top.length ? 'M' + top.concat(bottom).join('L') + 'Z' : '';
  }
  // Mean of the values present, NaN when there are none
  function meanOf(y) {
    var t = 0, k = 0;
    for (var i = 0; i < y.length; i++) if (y[i] != null) { t += y[i]; k++; }
    return k ? t / k : NaN;
  }
  // Indices of `ds` by their mean over the history, largest first
  function bySize(ds) {
    var m = ds.map(function (d) { return Math.abs(meanOf(d.y)) || 0; });
    return ds.map(function (_, i) { return i; }).sort(function (a, b) { return m[b] - m[a] || a - b; });
  }
  // The largest `ds` that get their own colour, and the rest to merge. All
  // keep their own colour when they fit in CAT.
  function topN(ds) {
    var order = bySize(ds), cut = ds.length > CAT.length ? CAT.length - 1 : ds.length;
    return { top: order.slice(0, cut), rest: order.slice(cut), color: function (i, r) { return cut < ds.length ? CAT[r] : CAT[i]; } };
  }
  // A series with f applied to its values and its forecasts'
  function mapValues(d, f) {
    var k = function (a) { return a.map(function (v) { return v == null ? null : f(v); }); };
    var fc = {};
    Object.keys(d.fc || {}).forEach(function (m) {
      var q = d.fc[m];
      fc[m] = { x: q.x, mean: k(q.mean), lo: q.lo.map(k), hi: q.hi.map(k) };
    });
    var out = {};
    for (var key in d) out[key] = d[key];
    out.y = k(d.y);
    out.fc = d.fc ? fc : d.fc;
    return out;
  }
  // A series and its forecasts as an index, its first value = 100
  function indexTo100(d) {
    var b = d.y.filter(function (v) { return v != null && isFinite(v); })[0];
    return mapValues(d, function (v) { return b ? v / b * 100 : null; });
  }
  // A series and its forecasts on a log10 scale, leaving out values <= 0
  function log10Of(d) {
    return mapValues(d, function (v) { return v > 0 ? Math.log10(v) : null; });
  }
  // History values that a log scale leaves out
  function nonPositive(ds) {
    return ds.reduce(function (t, d) { return t + (d ? d.y.filter(function (v) { return v != null && v <= 0; }).length : 0); }, 0);
  }
  // Ticks of a log10 axis over r: 1, 2 and 5 × 10^k, or powers of ten alone
  // when those crowd it. A range too narrow for any falls back to linear steps.
  function logTicks(r, n) {
    var all = [], tens = [];
    for (var k = Math.floor(r[0]); k <= Math.ceil(r[1]); k++) {
      [1, 2, 5].forEach(function (m) {
        var v = k + Math.log10(m);
        if (v < r[0] || v > r[1]) return;
        all.push(v);
        if (m === 1) tens.push(v);
      });
    }
    if (all.length < 2) {
      var lo = Math.pow(10, r[0]), hi = Math.pow(10, r[1]), step = niceStep([lo, hi], n);
      all = [];
      for (var u = Math.ceil(lo / step) * step; u <= hi; u += step) all.push(Math.log10(u));
      return all;
    }
    return all.length > n + 1 && tens.length >= 2 ? tens : all;
  }
  function logLabel(v) { return tickLabel(Math.pow(10, v)); }
  // A full series as a share of its parent's at each time, with each model's
  // forecast mean divided by the parent's (no intervals)
  function shareOf(d, p) {
    var div = function (a, b) { return a == null || b == null || !b ? null : a / b; };
    var fc = {};
    Object.keys(d.fc || {}).forEach(function (m) {
      var f = d.fc[m], q = p.fc && p.fc[m], at = {};
      if (!q) return;
      q.x.forEach(function (x, i) { at[x] = q.mean[i]; });
      fc[m] = { x: f.x, mean: f.mean.map(function (v, i) { return div(v, at[f.x[i]]); }), lo: [], hi: [] };
    });
    return { y: d.y.map(function (v, t) { return div(v, p.y[t]); }), sum: d.sum, fc: d.fc ? fc : d.fc };
  }
  // Times of a series' values. A reduced series holds the minimum and maximum
  // of each block of `step` times, placed at the block's first and last time.
  function xsOf(d) {
    return d.y.map(function (_, i) { return d.step ? Math.min((i >> 1) * d.step + (i & 1) * (d.step - 1), d.n - 1) : i; });
  }

  // ---- Explorer ----------------------------------------------------------------

  function Explorer(root, spec) {
    var self = this;
    this.root = root;
    this.spec = spec;
    this.keys = spec.keys;
    this.theme = load(THEME) || 'system';
    applyTheme(this.theme);
    readPalette();
    // Without chains, each key is its own
    this.chains = spec.chains || this.keys.map(function (k) { return [k]; });
    this.varCol = {};
    this.chains.forEach(function (vars, i) { vars.forEach(function (v) { self.varCol[v] = CHAIN[i % CHAIN.length]; }); });
    this.series = spec.series.map(function (r, i) {
      var s = { id: i, depth: 0 };
      self.keys.forEach(function (k, j) { s[k] = r[j]; if (r[j] != null) s.depth++; });
      s.dim = self.keys.map(function (k) { return s[k] != null ? 1 : 0; }).join('');
      return s;
    });
    this.ROOT = this.series.reduce(function (a, s) { return s.depth < a.depth ? s : a; }).id;
    this.maxDepth = Math.max.apply(null, this.series.map(function (s) { return s.depth; }));
    this.dims = {};
    spec.dims.nodes.forEach(function (d) {
      d.key = self.keys.map(function (k) { return d.keys.indexOf(k) > -1 ? 1 : 0; }).join('');
      d.out = [];
      self.dims[d.key] = d;
    });
    spec.dims.edges.forEach(function (e, i) {
      e.id = i;
      e.name = e.vars.join(' × ');
      spec.dims.nodes[e.from].out.push(e);
    });
    this.fc = spec.forecast;
    this.cache = {};
    this.pending = {};
    this.state = this.initial();
    var models = {};
    (this.fc ? this.fc.models : []).forEach(function (m) { models[m] = true; });
    // Each set of series keeps its own scales, sort and overlay axis
    this.ui = { measure: spec.measure, tab: 'grid', set: 'children', sets: {}, models: models, intervals: true, cell: 210 };
    var saved = load(STORE) || {}, su = saved.ui || {}, sc = su.scales || {};
    ['tab', 'set', 'intervals', 'cell'].forEach(function (k) { if (su[k] != null) self.ui[k] = su[k]; });
    if (this.ui.tab === 'children') this.ui.tab = 'grid';
    if (!TABS.some(function (t) { return t[0] === self.ui.tab; })) this.ui.tab = 'grid';
    if (!SCALES[this.ui.set]) this.ui.set = 'children';
    // Older saves kept the children's settings at the top, and the tray's scale
    var old = {
      children: { scales: { grid: sc.children || su.scale, overlay: sc.overlay, stacked: sc.stacked || su.stack, season: sc.season }, sort: su.sort, overlayLog: su.overlayLog },
      pinned: { scales: { grid: su.trayScale } }
    };
    Object.keys(SCALES).forEach(function (set) {
      var mine = su.sets ? su.sets[set] || {} : old[set], o = self.ui.sets[set] = { scales: {}, sort: 'key', overlayLog: false };
      Object.keys(SCALES[set]).forEach(function (t) {
        var v = (mine.scales || {})[t];
        o.scales[t] = SCALES[set][t].some(function (x) { return x[0] === v; }) ? v : SCALES[set][t][0][0];
      });
      if (SORTS.some(function (x) { return x[0] === mine.sort; })) o.sort = mine.sort;
      if (typeof mine.overlayLog === 'boolean') o.overlayLog = mine.overlayLog;
    });
    this.size = saved.size || null;
    this.build();
    this.render();
  }

  // Full name: every fixed key, leaving out keys implied by a deeper key of the same chain
  Explorer.prototype.fullLabel = function (s) {
    if (!s.depth) return 'Total';
    var out = [];
    this.chains.forEach(function (vars) {
      var fixed = vars.filter(function (k) { return s[k] != null; });
      if (fixed.length) out.push(s[fixed[fixed.length - 1]]);
    });
    return out.join(' · ');
  };
  // Children of s along dimension edge e: the series of e's target that share s's keys
  Explorer.prototype.children = function (s, e) {
    var self = this, to = this.spec.dims.nodes[e.to].key;
    return this.series.filter(function (c) {
      return c.dim === to && self.keys.every(function (k) { return s[k] == null || c[k] === s[k]; });
    }).sort(function (a, b) {
      for (var i = 0; i < e.vars.length; i++) { var v = e.vars[i]; if (a[v] !== b[v]) return a[v] < b[v] ? -1 : 1; }
      return 0;
    });
  };
  // A child's name within its group: its values of the edge's keys
  Explorer.prototype.partLabel = function (c, e) {
    return e.vars.map(function (v) { return c[v]; }).join(' · ');
  };
  Explorer.prototype.dimOf = function (s) { return this.dims[s.dim]; };
  // Colours that come from the theme's palettes, set again when it changes
  Explorer.prototype.recolour = function () {
    var self = this, chains = this.chains;
    this.varCol = {};
    chains.forEach(function (vars, i) { vars.forEach(function (v) { self.varCol[v] = CHAIN[i % CHAIN.length]; }); });
    this.spec.dims.edges.forEach(function (e) { e.col = self.varCol[e.vars[0]]; });
    (this.modelBtns || []).forEach(function (x, i) { x.b.style.color = MODEL[i % MODEL.length]; });
  };
  Explorer.prototype.setTheme = function (t) {
    this.theme = t;
    save(THEME, t);
    this.restyle();
  };
  Explorer.prototype.restyle = function () {
    applyTheme(this.theme);
    readPalette();
    this.recolour();
    var b = this.themeBtn, th = THEMES.filter(function (x) { return x[0] === this.theme; }, this)[0];
    if (b) { icon(b, th[0]); b.title = th[1]; b.setAttribute('aria-label', th[1]); }
    if (this.nodeEls) this.render();
  };
  // The ways the series can be split: its dimension node's out-edges
  Explorer.prototype.splits = function (s) { return this.dimOf(s).out; };

  // ---- State -----------------------------------------------------------------

  Explorer.prototype.initial = function () {
    return { focus: this.ROOT, groups: [], menu: null, last: null, showAll: {}, collapseTo: null, hover: null, hoverFrom: null, pins: [] };
  };
  Explorer.prototype.findGroup = function (key) {
    return this.state.groups.filter(function (g) { return g.key === key; })[0];
  };
  Explorer.prototype.visibleKids = function (g) {
    return this.state.showAll[g.key] || g.kids.length <= CAP + 1 ? g.kids : g.kids.slice(0, CAP);
  };
  Explorer.prototype.visibleSet = function () {
    var self = this, vis = {};
    vis[this.ROOT] = true;
    this.state.groups.forEach(function (g) { self.visibleKids(g).forEach(function (id) { vis[id] = true; }); });
    return vis;
  };
  // The focus's children: the last group chosen at it
  Explorer.prototype.focusGroup = function () {
    var g = this.state.last ? this.findGroup(this.state.last) : null;
    return g && g.parent === this.state.focus ? g : null;
  };
  // The set of series the view draws: the focus's children, or the pinned
  // series while there are any
  Explorer.prototype.set = function () { return this.ui.set === 'pinned' && this.state.pins.length ? 'pinned' : 'children'; };
  Explorer.prototype.opts = function () { return this.ui.sets[this.set()]; };
  // The tab drawn: pinned series don't stack, so they show the grid instead
  Explorer.prototype.tab = function () { return this.set() === 'pinned' && this.ui.tab === 'stacked' ? 'grid' : this.ui.tab; };
  // The group the view draws. The pinned series are a group under the total,
  // so their shares are of the total, and with no edge they go by full names.
  Explorer.prototype.viewGroup = function () {
    if (this.set() === 'children') return this.focusGroup();
    return { key: 'pins', parent: this.ROOT, e: null, kids: this.state.pins.slice(), shared: [] };
  };
  Explorer.prototype.memberLabel = function (id, g) {
    return g.e ? this.partLabel(this.series[id], g.e) : this.fullLabel(this.series[id]);
  };

  Explorer.prototype.choose = function (id, e) {
    var st = this.state, key = id + '~' + e.id, g = this.findGroup(key);
    if (!g) {
      var before = this.visibleSet();
      var kids = this.children(this.series[id], e).map(function (c) { return c.id; });
      if (!kids.length) return;
      g = { key: key, parent: id, e: e, kids: kids, shared: kids.filter(function (k) { return before[k]; }) };
      st.groups.push(g);
    }
    st.focus = id;
    st.last = key;
    st.menu = null;
    this.render();
  };

  // Drop the node's groups, then any group whose parent is no longer drawn.
  // Shared descendants survive while another path still reaches them.
  Explorer.prototype.collapse = function (id) {
    var st = this.state;
    st.collapseTo = id;
    st.groups = st.groups.filter(function (g) { return g.parent !== id; });
    for (var n = -1; n !== st.groups.length;) {
      var vis = this.visibleSet();
      n = st.groups.length;
      st.groups = st.groups.filter(function (g) { return vis[g.parent]; });
    }
    if (!this.visibleSet()[st.focus]) st.focus = id;
    if (st.last && !this.findGroup(st.last)) {
      var mine = st.groups.filter(function (g) { return g.parent === st.focus; });
      st.last = mine.length ? mine[mine.length - 1].key : null;
    }
    st.menu = null;
    this.render();
  };

  Explorer.prototype.togglePin = function (id) { this.setPins([id], this.state.pins.indexOf(id) < 0); };
  Explorer.prototype.setPins = function (ids, on) {
    var pins = this.state.pins, added = false;
    ids.forEach(function (id) {
      var i = pins.indexOf(id);
      if (on && i < 0) { pins.push(id); added = true; }
      if (!on && i > -1) pins.splice(i, 1);
    });
    if (added && this.set() === 'children') this.flashPins();
    this.renderGraph();
    this.renderRight();
  };
  // Focus a series drawn in the view, as choosing it in the graph would. Its
  // last chosen split comes with it, and a child hidden behind its group's
  // "+k more" chip is shown.
  Explorer.prototype.focusOn = function (id) {
    var self = this, st = this.state;
    if (id === st.focus) return;
    st.groups.forEach(function (g) { if (self.visibleKids(g).indexOf(id) < 0 && g.kids.indexOf(id) > -1) st.showAll[g.key] = true; });
    var mine = st.groups.filter(function (g) { return g.parent === id; });
    st.focus = id;
    if (mine.length) st.last = mine[mine.length - 1].key;
    st.menu = null;
    this.render();
  };
  // Pinning while the children are drawn flashes the Pinned count instead
  Explorer.prototype.flashPins = function () {
    var b = this.setBtns[1].b;
    b.classList.remove('gx-flash');
    void b.offsetWidth;
    b.classList.add('gx-flash');
  };

  // Hovering a node (or a plot) highlights the series everywhere it is drawn
  Explorer.prototype.setHover = function (id, from) {
    if (this.state.hover === id && this.state.hoverFrom === from) return;
    this.state.hover = id;
    this.state.hoverFrom = from;
    var self = this;
    Object.keys(this.nodeEls).forEach(function (k) { self.nodeEls[k].box.classList.toggle('gx-hover', +k === id); });
    this.renderPeek();
    this.applyHighlight();
  };

  // ---- Data --------------------------------------------------------------------

  Explorer.prototype.ckey = function (id, raw) { return this.ui.measure + '|' + (raw ? 1 : 0) + '|' + id; };
  // A series' data, or undefined while it loads. Raw data serves either request.
  Explorer.prototype.data = function (id, raw) {
    return this.cache[this.ckey(id, true)] || (raw ? undefined : this.cache[this.ckey(id, false)]);
  };
  // Fetch whatever isn't cached, 200 series a request, then draw the right column again
  Explorer.prototype.need = function (ids, raw) {
    var self = this, ckey = this.ckey.bind(this), measure = this.ui.measure;
    var miss = ids.filter(function (id, i) {
      return ids.indexOf(id) === i && self.data(id, raw) === undefined && !self.pending[ckey(id, raw)];
    });
    var get = function (chunk) {
      var keys = chunk.map(function (id) { return ckey(id, raw); });
      keys.forEach(function (k) { self.pending[k] = true; });
      fetch('api/series?measure=' + encodeURIComponent(measure) + '&raw=' + (raw ? 1 : 0) + '&ids=' + chunk.join(','))
        .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
        .then(function (d) {
          keys.forEach(function (k, j) { delete self.pending[k]; self.cache[k] = d[chunk[j]]; });
          self.scheduleRight();
        })
        .catch(function (err) { self.status('Could not load series: ' + err.message); });
    };
    for (var i = 0; i < miss.length; i += 200) get(miss.slice(i, i + 200));
  };
  Explorer.prototype.scheduleRight = function () {
    var self = this;
    if (this.frame) return;
    this.frame = requestAnimationFrame(function () { self.frame = null; self.renderRight(); });
  };

  // Forecasts are drawn when the measure has them and a model is switched on
  Explorer.prototype.showFc = function () {
    var ui = this.ui;
    return !!this.fc && this.fc.measure === ui.measure && Object.keys(ui.models).some(function (m) { return ui.models[m]; });
  };
  Explorer.prototype.xMax = function () { return (this.showFc() ? this.spec.times.length : this.spec.history) - 1; };
  Explorer.prototype.models = function () {
    var ui = this.ui;
    return this.showFc() ? this.fc.models.filter(function (m) { return ui.models[m]; }) : [];
  };

  // ---- Build -----------------------------------------------------------------

  Explorer.prototype.build = function () {
    var self = this, spec = this.spec, root = this.root;
    root.textContent = '';

    // Columns
    var main = this.main = el('div', 'gx-main', root);
    var left = el('div', 'gx-col gx-left', main);
    var colSplit = el('div', 'gx-split gx-split-col', main);
    var right = el('div', 'gx-col gx-right', main);

    // The series graph, with the layout and theme buttons in its header and
    // the count of series drawn in a corner
    var gp = el('section', 'gx-pane gx-graph-pane', left);
    var gh = el('div', 'gx-pane-head', gp, 'Series graph');
    var tools = el('div', 'gx-tools', gh);
    var help = el('button', 'gx-btn gx-icon', tools, '?');
    help.type = 'button';
    help.title = 'Shortcuts';
    help.setAttribute('aria-label', 'Shortcuts');
    help.setAttribute('aria-expanded', 'false');
    help.addEventListener('click', function () { self.toggleHelp(); });
    var reset = el('button', 'gx-btn gx-icon', tools);
    reset.type = 'button';
    reset.title = 'Reset layout';
    reset.setAttribute('aria-label', 'Reset layout');
    icon(reset, 'reset');
    reset.addEventListener('click', function () { self.size = null; self.persist(); self.applySize(); });
    var theme = this.themeBtn = el('button', 'gx-btn gx-icon', tools);
    theme.type = 'button';
    theme.addEventListener('click', function () {
      var i = THEMES.map(function (x) { return x[0]; }).indexOf(self.theme);
      self.setTheme(THEMES[(i + 1) % THEMES.length][0]);
    });
    if (darkQuery) darkQuery.addEventListener('change', function () { if (self.theme === 'system') self.restyle(); });
    this.graph = el('div', 'gx-pane-body', gp);
    this.layer = el('div', 'gx-layer', this.graph);
    this.world = el('div', 'gx-world', this.layer);
    this.peek = el('div', 'gx-peek', this.graph);
    this.peek.setAttribute('aria-hidden', 'true');
    this.countEl = el('div', 'gx-count', this.graph);
    this.countEl.title = 'Series drawn';
    this.startEl = el('div', 'gx-start', this.graph, 'Click a node to split it');
    var card = this.helpCard = el('dl', 'gx-help', this.graph);
    HELP.forEach(function (h) { el('dt', null, card, h[0]); el('dd', null, card, h[1]); });
    this.helpBtn = help;
    var zoom = el('div', 'gx-zoom', this.graph);
    [['+', 'Zoom in', function () { self.zoomBy(1.25); }], ['−', 'Zoom out', function () { self.zoomBy(0.8); }],
      ['⤢', 'Reset view', function () { self.resetCam(); }]].forEach(function (z) {
      var b = el('button', 'gx-btn', zoom, z[0]);
      b.type = 'button';
      b.title = z[1];
      b.setAttribute('aria-label', z[1]);
      b.addEventListener('click', z[2]);
    });

    // The dimension graph, headed by the structure
    var dimSplit = el('div', 'gx-split gx-split-row', left);
    var dp = el('section', 'gx-pane', left);
    var dh = el('div', 'gx-pane-head', dp);
    var structure = el('div', 'gx-structure', dh);
    structure.title = 'Structure';
    this.terms = {};
    spec.structure.split(/([A-Za-z_.][A-Za-z0-9_.]*)/).forEach(function (t) {
      if (!t) return;
      var span = el('span', null, structure, t);
      if (self.keys.indexOf(t) > -1) { span.className = 'gx-term'; self.terms[t] = span; }
    });
    var db = this.dimsBody = el('div', 'gx-pane-body gx-dims-body', dp);
    this.dimsSvg = svgEl('svg', db, { class: 'gx-dims-svg', role: 'img', 'aria-label': 'Dimension graph' });

    // The focused series, headed by the measure and the forecast models,
    // whose chips are their legend and switches
    var fp = this.focusPane = el('section', 'gx-pane gx-focus-pane', right);
    var fh = el('div', 'gx-pane-head', fp);
    if (spec.measures.length > 1) {
      var select = el('select', 'gx-measure', fh);
      select.setAttribute('aria-label', 'Measure');
      spec.measures.forEach(function (m) { el('option', null, select, m).value = m; });
      select.value = this.ui.measure;
      select.addEventListener('change', function () { self.ui.measure = select.value; self.render(); });
    } else {
      el('span', 'gx-measure', fh, this.ui.measure);
    }
    this.focusHead = el('div', 'gx-series-head', fh);
    if (this.fc) {
      var models = this.modelsEl = el('div', 'gx-models', fh);
      this.modelBtns = this.fc.models.map(function (m, i) {
        var b = el('button', 'gx-model', models);
        b.type = 'button';
        b.title = m + ' forecasts of ' + self.fc.measure;
        b.style.color = MODEL[i % MODEL.length];
        el('span', 'gx-model-key', b);
        el('span', null, b, m).style.color = 'var(--ink)';
        b.addEventListener('click', function () { self.ui.models[m] = !self.ui.models[m]; self.renderControls(); self.renderRight(); });
        return { b: b, m: m };
      });
      var iv = this.intervalBtn = el('button', 'gx-model gx-iv', models);
      iv.type = 'button';
      iv.title = 'Forecast intervals';
      el('span', 'gx-iv-key', iv);
      el('span', null, iv, spec.forecast.level.join('/') + '%');
      iv.addEventListener('click', function () { self.ui.intervals = !self.ui.intervals; self.persist(); self.renderControls(); self.renderRight(); });
    }
    this.focusBody = el('div', 'gx-pane-body', fp);
    var focusSplit = el('div', 'gx-split gx-split-row', right);
    var vp = el('section', 'gx-pane', right);
    var vh = el('div', 'gx-pane-head', vp);
    // Which series the view draws. Disabled buttons stay focusable and keep
    // their tooltips, so they say why.
    var sets = el('div', 'gx-seg gx-set', vh);
    sets.setAttribute('role', 'group');
    sets.setAttribute('aria-label', 'Series to draw');
    this.setBtns = ['children', 'pinned'].map(function (v) {
      var b = el('button', null, sets);
      b.type = 'button';
      b.addEventListener('click', function () {
        if (b.getAttribute('aria-disabled') === 'true') return;
        self.ui.set = v; self.persist(); self.renderRight();
      });
      b.addEventListener('animationend', function () { b.classList.remove('gx-flash'); });
      return { b: b, v: v };
    });
    var tabs = el('div', 'gx-tabs', vh);
    tabs.setAttribute('role', 'tablist');
    this.tabBtns = TABS.map(function (t) {
      var b = el('button', null, tabs, t[1]);
      b.type = 'button';
      b.setAttribute('role', 'tab');
      b.addEventListener('click', function () {
        if (b.getAttribute('aria-disabled') === 'true') return;
        self.ui.tab = t[0]; self.persist(); self.renderRight();
      });
      return { b: b, v: t[0] };
    });
    // Each set's and tab's own y scale, shown only on that tab
    this.scaleSegs = {};
    Object.keys(SCALES).forEach(function (set) {
      self.scaleSegs[set] = {};
      Object.keys(SCALES[set]).forEach(function (t) {
        self.scaleSegs[set][t] = self.segmented(vh, SCALES[set][t], function () { return self.ui.sets[set].scales[t]; },
          function (v) { self.ui.sets[set].scales[t] = v; self.persist(); self.renderRight(); }, 'y scale');
      });
    });
    // The overlay's log scale works with values or indexes alike
    this.logSeg = this.segmented(vh, [[false, 'Linear'], [true, 'Log y']], function () { return self.opts().overlayLog; },
      function (v) { self.opts().overlayLog = v; self.persist(); self.renderRight(); }, 'Overlay y axis');
    var sort = this.sortEl = el('span', 'gx-sort', vh, 'Sort');
    this.sortSeg = this.segmented(sort, SORTS, function () { return self.opts().sort; },
      function (v) { self.opts().sort = v; self.persist(); self.renderRight(); }, 'Sort series');
    var end = el('div', 'gx-head-end', vh);
    var size = this.sizeEl = el('label', 'gx-size', end, 'Plot size');
    var slider = el('input', null, size);
    slider.type = 'range'; slider.min = 120; slider.max = 420; slider.step = 10; slider.value = this.ui.cell;
    slider.addEventListener('input', function () { self.ui.cell = +slider.value; self.persist(); self.renderRight(); });
    var pinAll = this.pinAllBtn = el('button', 'gx-btn gx-pin-all', end);
    pinAll.type = 'button';
    pinAll.addEventListener('click', function () {
      var g = self.focusGroup();
      if (g) self.setPins(g.kids, !self.allPinned(g));
    });
    this.view = el('div', 'gx-pane-body gx-view', vp);

    // Splitters: drag to resize, double-click to reset that pane
    var mainBox = function () { return main.getBoundingClientRect(); };
    this.splitter(colSplit, 'x', function (p, s) { s.left = p.x - mainBox().left - 6; }, 'left');
    this.splitter(dimSplit, 'y', function (p, s) { s.dims = mainBox().bottom - 6 - p.y; }, 'dims');
    this.splitter(focusSplit, 'y', function (p, s) { s.focus = p.y - mainBox().top - 6; }, 'focus');
    this.applySize();
    this.cam = { k: 1, x: 0, y: 0 };
    this.panZoom();

    this.layer.addEventListener('click', function () {
      if (self.helpOpen) self.toggleHelp(false);
      if (self.state.menu != null) { self.state.menu = null; self.renderGraph(); self.renderDims(); }
    });
    document.addEventListener('keydown', function (ev) {
      if (ev.key !== 'Escape') return;
      if (self.helpOpen) self.toggleHelp(false);
      if (self.state.menu != null) { self.state.menu = null; self.renderGraph(); self.renderDims(); }
    });
    // Leaving a plot clears its hover
    right.addEventListener('mouseover', function (ev) {
      var t = ev.target.closest && ev.target.closest('[data-sid]');
      if (t) self.setHover(+t.getAttribute('data-sid'), 'plot');
      else if (self.state.hoverFrom === 'plot') self.setHover(null, null);
    });
    right.addEventListener('mouseleave', function () { if (self.state.hoverFrom === 'plot') self.setHover(null, null); });

    this.toastEl = el('div', 'gx-toast', root);
    this.toastEl.setAttribute('role', 'status');

    var resized = null;
    new ResizeObserver(function () {
      clearTimeout(resized);
      resized = setTimeout(function () { self.applySize(true); self.renderGraph(); self.renderDims(); self.renderRight(); }, 60);
    }).observe(main);

    this.restyle();
    this.nodeEls = {};
    this.edgeEls = {};
    this.moreEls = {};
    this.menuEl = null;
    this.chipHover = null;
  };

  Explorer.prototype.segmented = function (parent, opts, get, set, label) {
    var seg = el('div', 'gx-seg', parent);
    seg.setAttribute('role', 'group');
    seg.setAttribute('aria-label', label);
    var btns = opts.map(function (o) {
      var b = el('button', null, seg, o[1]);
      b.type = 'button';
      b.addEventListener('click', function () { set(o[0]); sync(); });
      return { b: b, v: o[0] };
    });
    var sync = function () { btns.forEach(function (x) { x.b.setAttribute('aria-pressed', String(x.v === get())); }); };
    sync();
    return { el: seg, sync: sync };
  };

  Explorer.prototype.splitter = function (handle, axis, move, name) {
    var self = this;
    handle.addEventListener('pointerdown', function (ev) {
      ev.preventDefault();
      handle.setPointerCapture(ev.pointerId);
      handle.classList.add('gx-on');
      self.root.classList.add('gx-dragging');
      var onMove = function (e) { move({ x: e.clientX, y: e.clientY }, self.size); self.applySize(); };
      var onUp = function () {
        handle.removeEventListener('pointermove', onMove);
        handle.removeEventListener('pointerup', onUp);
        handle.classList.remove('gx-on');
        self.root.classList.remove('gx-dragging');
        self.persist();
        self.renderGraph();
      };
      handle.addEventListener('pointermove', onMove);
      handle.addEventListener('pointerup', onUp);
    });
    handle.addEventListener('dblclick', function () { delete self.size[name]; self.applySize(); self.persist(); });
    handle.setAttribute('role', 'separator');
    handle.setAttribute('aria-orientation', axis === 'x' ? 'vertical' : 'horizontal');
  };

  // Pan and zoom the series graph: the layout fills the pane at zoom 1, and the
  // camera moves the world under it. Drag the background (or two fingers) to pan,
  // scroll or pinch to zoom; a drag doesn't count as a click that closes the menu.
  Explorer.prototype.panZoom = function () {
    var self = this, layer = this.layer, pts = {}, moved = 0;
    var local = function (p) { var r = layer.getBoundingClientRect(); return { x: p.x - r.left, y: p.y - r.top }; };
    var pinch = function () {
      var ids = Object.keys(pts), a = pts[ids[0]], b = pts[ids[1]];
      return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, d: Math.hypot(a.x - b.x, a.y - b.y) || 1 };
    };
    layer.addEventListener('wheel', function (ev) {
      ev.preventDefault();
      var p = local({ x: ev.clientX, y: ev.clientY });
      self.zoomBy(Math.exp(-ev.deltaY * (ev.deltaMode ? 0.05 : 0.002)), p.x, p.y);
    }, { passive: false });
    layer.addEventListener('pointerdown', function (ev) {
      if (!Object.keys(pts).length) moved = 0;
      if (ev.button !== 0 || ev.target.closest('.gx-node, .gx-more, .gx-menu')) return;
      pts[ev.pointerId] = { x: ev.clientX, y: ev.clientY };
      layer.setPointerCapture(ev.pointerId);
      layer.classList.add('gx-panning');
    });
    layer.addEventListener('pointermove', function (ev) {
      var p = pts[ev.pointerId];
      if (!p) return;
      var two = Object.keys(pts).length > 1, before = two && pinch();
      moved += Math.abs(ev.clientX - p.x) + Math.abs(ev.clientY - p.y);
      var dx = ev.clientX - p.x, dy = ev.clientY - p.y;
      p.x = ev.clientX; p.y = ev.clientY;
      if (two) {
        var after = pinch(), c = local(after);
        dx = after.x - before.x; dy = after.y - before.y;
        self.zoomBy(after.d / before.d, c.x, c.y);
      }
      self.cam.x += dx; self.cam.y += dy;
      self.applyCam();
    });
    var up = function (ev) {
      if (!pts[ev.pointerId]) return;
      delete pts[ev.pointerId];
      if (!Object.keys(pts).length) layer.classList.remove('gx-panning');
    };
    layer.addEventListener('pointerup', up);
    layer.addEventListener('pointercancel', up);
    layer.addEventListener('click', function (ev) { if (moved > 4) { ev.stopImmediatePropagation(); moved = 0; } }, true);
    layer.addEventListener('dblclick', function (ev) {
      if (!ev.target.closest('.gx-node, .gx-more, .gx-menu')) self.resetCam();
    });
  };
  // Zoom by f about (cx, cy) in pane px, the pane's centre by default
  Explorer.prototype.zoomBy = function (f, cx, cy) {
    var c = this.cam, k = clamp(c.k * f, 0.25, 6);
    if (cx == null) { cx = this.layer.clientWidth / 2; cy = this.layer.clientHeight / 2; }
    c.x = cx - (cx - c.x) * k / c.k;
    c.y = cy - (cy - c.y) * k / c.k;
    c.k = k;
    this.applyCam();
  };
  Explorer.prototype.resetCam = function () { this.cam = { k: 1, x: 0, y: 0 }; this.applyCam(); };
  Explorer.prototype.applyCam = function () {
    var c = this.cam;
    this.world.style.transform = 'translate(' + px(c.x) + ',' + px(c.y) + ') scale(' + c.k + ')';
    this.placeMenu();
    this.placePeek();
  };

  // Pane sizes in px, kept inside the window
  Explorer.prototype.applySize = function (quiet) {
    var r = this.main.getBoundingClientRect(), W = r.width - 12, H = r.height - 12;
    var s = this.size = this.size || {};
    s.left = clamp(s.left == null ? W * 0.5 : s.left, Math.min(260, W / 2), Math.max(W - 320, W / 2));
    s.dims = clamp(s.dims == null ? H * 0.28 : s.dims, 32, Math.max(32, H - 150));
    delete s.tray;
    s.focus = clamp(s.focus == null ? H * 0.32 : s.focus, 80, Math.max(80, H - 120));
    var st = this.root.style;
    st.setProperty('--left', px(s.left));
    st.setProperty('--dims', px(s.dims));
    st.setProperty('--focus', px(s.focus));
  };
  Explorer.prototype.persist = function () {
    var ui = this.ui;
    save(STORE, { size: this.size, ui: { tab: ui.tab, set: ui.set, sets: ui.sets, intervals: ui.intervals, cell: ui.cell } });
  };
  Explorer.prototype.toggleHelp = function (on) {
    this.helpOpen = on == null ? !this.helpOpen : on;
    this.helpCard.classList.toggle('gx-on', this.helpOpen);
    this.helpBtn.setAttribute('aria-expanded', String(this.helpOpen));
  };
  // A message that shows for a few seconds
  Explorer.prototype.status = function (msg) {
    var t = this.toastEl;
    t.textContent = msg;
    t.classList.add('gx-on');
    clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(function () { t.classList.remove('gx-on'); }, 4000);
  };

  // ---- Render ----------------------------------------------------------------

  Explorer.prototype.render = function () {
    this.renderControls();
    this.renderGraph();
    this.renderDims();
    this.renderRight();
  };

  Explorer.prototype.renderControls = function () {
    var self = this, lastG = this.state.last ? this.findGroup(this.state.last) : null;
    // Underline the variables last split by, in the colour of their chain
    Object.keys(this.terms).forEach(function (t) {
      var on = !!lastG && lastG.e.vars.indexOf(t) > -1;
      self.terms[t].classList.toggle('gx-active', on);
      self.terms[t].style.textDecorationColor = on ? self.varCol[t] : 'transparent';
    });
    this.countEl.textContent = Object.keys(this.visibleSet()).length + ' / ' + this.series.length;
    // The models only forecast their own measure
    if (this.modelsEl) this.modelsEl.style.display = this.ui.measure === this.fc.measure ? '' : 'none';
    (this.modelBtns || []).forEach(function (x) { x.b.setAttribute('aria-pressed', String(!!self.ui.models[x.m])); });
    if (this.intervalBtn) this.intervalBtn.setAttribute('aria-pressed', String(this.ui.intervals));
  };

  Explorer.prototype.makeNode = function (id) {
    var self = this, s = this.series[id];
    var b = el('button', 'gx-node', this.world);
    b.type = 'button';
    b.title = this.fullLabel(s);
    b.setAttribute('aria-label', this.fullLabel(s));
    var ring = el('div', 'gx-ring', b);
    el('div', 'gx-halo', ring);
    var dot = el('div', 'gx-dot', ring);
    var label = el('div', 'gx-label', b);
    b.addEventListener('click', function (ev) {
      ev.stopPropagation();
      if (ev.shiftKey) { self.togglePin(id); return; }
      self.state.menu = self.state.menu === id ? null : id;
      self.renderGraph();
      self.renderDims();
    });
    b.addEventListener('contextmenu', function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      self.collapse(id);
    });
    b.addEventListener('mouseenter', function () { self.setHover(id, 'graph'); });
    b.addEventListener('mouseleave', function () { if (self.state.hover === id) self.setHover(null, null); });
    b.addEventListener('focus', function () { self.setHover(id, 'graph'); });
    b.addEventListener('blur', function () { if (self.state.hover === id) self.setHover(null, null); });
    return { box: b, label: label, dot: dot };
  };

  // Layered layout: each group centres under its parent, then groups push apart.
  // A node is placed by the first group that reached it; later groups only add edges.
  // A node with a second parent moves to the end of its group nearest that
  // parent, and takes its full name, so the extra edge doesn't cross the group.
  Explorer.prototype.layout = function () {
    var self = this, st = this.state, byId = this.series, GW = this.GW;
    var pos = {}, claimed = {}, tilt = {}, labelOf = {}, more = [];
    pos[this.ROOT] = { x: GW / 2, y: this.rowY(0) };
    claimed[this.ROOT] = true;
    labelOf[this.ROOT] = 'Total';
    var parents = {};
    st.groups.forEach(function (g) {
      self.visibleKids(g).forEach(function (id) { (parents[id] = parents[id] || []).push(g.parent); });
    });
    var placedBy = st.groups.map(function (g) {
      return self.visibleKids(g).filter(function (id) {
        if (claimed[id]) return false;
        claimed[id] = true;
        labelOf[id] = parents[id].length > 1 ? self.fullLabel(byId[id]) : self.partLabel(byId[id], g.e);
        return true;
      });
    });
    for (var d = 1; d <= this.maxDepth; d++) {
      var groups = [];
      st.groups.forEach(function (g, j) {
        if (byId[g.kids[0]].depth !== d) return;
        var px0 = pos[g.parent].x;
        var side = function (id) {
          var other = parents[id].filter(function (p) { return p !== g.parent; })[0];
          return other == null ? 0 : pos[other].x < px0 ? -1 : 1;
        };
        var items = placedBy[j].map(function (id, i) { return { id: id, i: i, side: side(id) }; })
          .sort(function (a, b) { return a.side - b.side || a.i - b.i; });
        var hidden = g.kids.length - self.visibleKids(g).length;
        if (hidden > 0) items.push({ more: g.key, n: hidden });
        if (items.length) groups.push({ j: j, items: items, cx: pos[g.parent].x });
      });
      if (!groups.length) continue;
      groups.sort(function (a, b) { return a.cx - b.cx || a.j - b.j; });
      var ML = 36, MR = 36, gap = 16, avail = GW - ML - MR - gap * (groups.length - 1);
      var nw = function (it) { return it.more ? 64 : Math.max(46, labelOf[it.id].length * 7.2 + 18); };
      var total = function () {
        return groups.reduce(function (t, g) { return t + g.items.reduce(function (u, it) { return u + nw(it); }, 0); }, 0);
      };
      var raw = total();
      // Too wide for upright labels: tilt the row and pack its nodes tightly
      if (raw > avail) {
        tilt[d] = true;
        nw = function (it) { return it.more ? 40 : 30; };
        raw = total();
      }
      var sc = Math.min(1, avail / raw), end = ML - gap;
      groups.forEach(function (g) {
        g.w = g.items.reduce(function (u, it) { return u + nw(it) * sc; }, 0);
        g.start = Math.max(g.cx - g.w / 2, end + gap);
        end = g.start + g.w;
      });
      var over = Math.max(0, end - (GW - MR));
      groups.forEach(function (g) {
        var x = Math.max(ML, g.start - over);
        g.items.forEach(function (it) {
          var w = nw(it) * sc, p = { x: x + w / 2, y: self.rowY(d) };
          if (it.more) more.push({ key: it.more, n: it.n, x: p.x, y: p.y });
          else pos[it.id] = p;
          x += w;
        });
      });
    }
    return { pos: pos, tilt: tilt, labelOf: labelOf, more: more };
  };
  Explorer.prototype.rowY = function (d) { return 34 + d * this.rowGap; };

  Explorer.prototype.renderGraph = function () {
    var self = this, st = this.state, byId = this.series, layer = this.world;
    this.GW = this.layer.clientWidth || 600;
    this.LH = this.layer.clientHeight || 400;
    this.rowGap = Math.max(48, Math.min(120, (this.LH - 100) / Math.max(1, this.maxDepth)));
    var vis = this.visibleSet(), L = this.layout(), pos = this.pos = L.pos;

    var parents = {};
    st.groups.forEach(function (g) {
      self.visibleKids(g).forEach(function (id) { (parents[id] = parents[id] || []).push(g); });
    });

    // New nodes grow out of their first parent; leaving ones shrink into the collapsed node
    var leaving = [], leavingEdges = [];
    Object.keys(vis).forEach(function (id) {
      if (self.nodeEls[id]) return;
      var e = self.nodeEls[id] = self.makeNode(+id);
      var from = parents[id] ? pos[parents[id][0].parent] : pos[id];
      css(e.box, { left: px(from.x - 18), top: px(from.y - 18), opacity: 0, transform: 'scale(.2)' });
    });
    Object.keys(this.nodeEls).forEach(function (id) {
      if (vis[id]) return;
      leaving.push(self.nodeEls[id].box);
      delete self.nodeEls[id];
    });

    // Edges, one per (group, visible child)
    var want = {};
    st.groups.forEach(function (g) {
      self.visibleKids(g).forEach(function (id) { want[g.parent + '>' + id] = { g: g, child: id }; });
    });
    Object.keys(want).forEach(function (k) {
      if (self.edgeEls[k]) return;
      var w = want[k], a = pos[w.g.parent];
      var box = el('div', 'gx-edge', layer), line = el('div', 'gx-line', box);
      css(box, lineStyle(a.x, a.y + 30, a.x, a.y + 31));
      line.style.transform = 'scaleX(0)';
      self.edgeEls[k] = { box: box, line: line, parent: w.g.parent };
    });
    Object.keys(this.edgeEls).forEach(function (k) {
      if (want[k]) return;
      leavingEdges.push(self.edgeEls[k]);
      delete self.edgeEls[k];
    });

    void layer.offsetWidth;

    var to = pos[st.collapseTo] || pos[this.ROOT];
    leaving.forEach(function (box) {
      box.style.pointerEvents = 'none';
      box.tabIndex = -1;
      css(box, { left: px(to.x - 18), top: px(to.y - 18), opacity: 0, transform: 'scale(.2)' });
      setTimeout(function () { box.remove(); }, 650);
    });
    leavingEdges.forEach(function (e) {
      var a = pos[e.parent] || to;
      css(e.box, lineStyle(a.x, a.y + 36, to.x, to.y + 36));
      e.line.style.transform = 'scaleX(0)';
      e.box.style.opacity = 0;
      setTimeout(function () { e.box.remove(); }, 650);
    });
    st.collapseTo = null;

    Object.keys(this.nodeEls).forEach(function (id) {
      var e = self.nodeEls[id], p = pos[id];
      css(e.box, { left: px(p.x - 18), top: px(p.y - 18), opacity: 1, transform: 'scale(1)' });
      e.label.textContent = L.labelOf[id];
      e.dot.style.background = level(byId[id].depth);
      e.box.classList.toggle('gx-tilt', !!L.tilt[byId[id].depth]);
      e.box.classList.toggle('gx-focus', +id === st.focus);
      e.box.classList.toggle('gx-menu-on', +id === st.menu);
      e.box.classList.toggle('gx-multi', (parents[id] || []).length > 1);
      e.box.classList.toggle('gx-pinned', st.pins.indexOf(+id) > -1);
      e.box.classList.toggle('gx-hover', +id === st.hover);
    });

    // Edges leave the parent below its label and arrive at the top of the child's dot
    Object.keys(this.edgeEls).forEach(function (k) {
      var e = self.edgeEls[k], w = want[k], a = pos[w.g.parent], b = pos[w.child];
      css(e.box, lineStyle(a.x, a.y + (L.tilt[byId[w.g.parent].depth] ? 16 : 34), b.x, b.y - 14));
      e.line.style.transform = 'scaleX(1)';
      e.line.style.borderTopColor = w.g.e.col;
      e.box.classList.toggle('gx-second', (parents[w.child] || []).length > 1);
    });

    // "+k more" chips for wide groups
    var moreWant = {};
    L.more.forEach(function (m) { moreWant[m.key] = m; });
    Object.keys(this.moreEls).forEach(function (k) {
      if (moreWant[k]) return;
      var m = self.moreEls[k];
      css(m, { opacity: 0, pointerEvents: 'none' });
      setTimeout(function () { m.remove(); }, 450);
      delete self.moreEls[k];
    });
    L.more.forEach(function (m) {
      var e = self.moreEls[m.key];
      if (!e) {
        e = self.moreEls[m.key] = el('button', 'gx-more', layer);
        e.type = 'button';
        e.addEventListener('click', function (ev) { ev.stopPropagation(); st.showAll[m.key] = true; self.render(); });
      }
      e.textContent = '+' + m.n;
      e.title = 'Show ' + m.n + ' more';
      css(e, { left: px(m.x), top: px(m.y) });
    });

    this.startEl.classList.toggle('gx-on', !st.groups.length);
    this.renderMenu(pos, L);
    this.renderPeek();
  };

  Explorer.prototype.renderMenu = function (pos, L) {
    var self = this, st = this.state;
    if (this.menuEl) { this.menuEl.remove(); this.menuEl = null; }
    if (st.menu == null || !pos[st.menu]) { st.menu = null; return; }
    var s = this.series[st.menu], p = pos[st.menu], splits = this.splits(s);
    var menu = this.menuEl = el('div', 'gx-menu', this.layer);
    menu.addEventListener('click', function (ev) { ev.stopPropagation(); });
    if (!splits.length) el('span', 'gx-tag', menu, 'no further split');
    splits.forEach(function (e) {
      var done = !!self.findGroup(s.id + '~' + e.id), n = self.children(s, e).length;
      var c = el('button', 'gx-chip' + (done ? ' gx-done' : ''), menu);
      c.type = 'button';
      c.disabled = !n;
      css(el('span', 'gx-key', c), { color: e.col });
      el('span', null, c, e.name);
      el('span', 'gx-n', c, done ? '✓ shown' : String(n));
      c.addEventListener('click', function () { self.chipHover = null; self.choose(s.id, e); });
      var hot = function (on) { return function () { self.chipHover = on ? e.id : null; self.renderDims(); }; };
      c.addEventListener('mouseenter', hot(true));
      c.addEventListener('focus', hot(true));
      c.addEventListener('mouseleave', hot(false));
    });
    menu.style.maxWidth = px(this.GW - 20);
    this.menuAt = { x: p.x, y: p.y + (L.tilt[s.depth] ? 22 : 56) };
    this.placeMenu();
  };
  // The menu sits in the pane, not the zoomed world, so its chips stay full size
  // and inside the pane wherever the camera is
  Explorer.prototype.placeMenu = function () {
    var menu = this.menuEl, a = this.menuAt, c = this.cam;
    if (!menu) return;
    var w = menu.offsetWidth, x = a.x * c.k + c.x, top = a.y * c.k + c.y;
    css(menu, { left: px(Math.min(Math.max(x, w / 2 + 10), this.GW - w / 2 - 10)), top: px(Math.min(top, this.LH - menu.offsetHeight - 8)) });
  };

  // A sparkline beside the hovered node, when its series isn't drawn on the
  // right. Like the menu, it sits in the pane and follows the camera.
  Explorer.prototype.renderPeek = function () {
    var st = this.state, id = st.hover, peek = this.peek;
    peek.textContent = '';
    this.peekAt = null;
    var on = id != null && st.hoverFrom === 'graph' && st.menu !== id && !!this.pos && !!this.pos[id] && !this.shown()[id];
    peek.classList.toggle('gx-on', on);
    if (!on) return;
    var s = this.series[id], d = this.data(id, false);
    if (d === undefined) this.need([id], false);
    var head = el('div', 'gx-cell-head', peek);
    css(el('span', 'gx-swatch', head), { background: level(s.depth) });
    el('span', 'gx-cell-label', head, this.fullLabel(s));
    this.timePlot(el('div', 'gx-peek-plot', peek), 200, 64, [{ id: id, d: d }], { fc: true, compact: true, noX: true });
    this.peekAt = this.pos[id];
    this.placePeek();
  };
  // Right of the node, or left of it near the pane's right edge, and inside the pane
  Explorer.prototype.placePeek = function () {
    var a = this.peekAt, c = this.cam, peek = this.peek;
    if (!a) return;
    var w = peek.offsetWidth, h = peek.offsetHeight, x = a.x * c.k + c.x, y = a.y * c.k + c.y, r = 18 * c.k + 8;
    var left = x + r + w > this.GW - 4 ? x - r - w : x + r;
    css(peek, { left: px(clamp(left, 4, this.GW - w - 4)), top: px(clamp(y - h / 2, 4, this.LH - h - 4)) });
  };

  // The Hasse diagram, scaled to its pane. The focus (or open menu) fills its
  // node, and its out-edges are the menu.
  Explorer.prototype.renderDims = function () {
    var self = this, svg = this.dimsSvg, nodes = this.spec.dims.nodes, st = this.state;
    svg.textContent = '';
    var bw = this.dimsBody.clientWidth - 24, bh = this.dimsBody.clientHeight - 16;
    if (bh < 30) return;
    var maxY = Math.max.apply(null, nodes.map(function (d) { return d.y; })) || 1;
    var xs = nodes.map(function (d) { return d.x; }), span = (Math.max.apply(null, xs) - Math.min.apply(null, xs)) || 1;
    var V = Math.min(48, (bh - 20) / maxY), U = Math.min(120, Math.max(40, (bw - 200) / span));
    var lab = function (d) {
      if (d.x < 0) return [-10, 0, 'end'];
      if (d.y === maxY) return [12, 12, 'start'];
      if (d.x === 0 && d.y > 0) return [-12, 14, 'end'];
      return [10, 0, 'start'];
    };
    var x0 = 0, x1 = 0;
    nodes.forEach(function (d) {
      var l = lab(d), w = (d.name.length + String(d.n).length + 1) * 7, x = d.x * U + l[0];
      x0 = Math.min(x0, l[2] === 'end' ? x - w : x);
      x1 = Math.max(x1, l[2] === 'end' ? x : x + w);
    });
    var h = maxY * V + 26;
    svg.setAttribute('viewBox', [x0 - 4, -12, x1 - x0 + 8, h + 12].join(' '));
    svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
    var active = this.dimOf(this.series[st.menu != null ? st.menu : st.focus]);
    var seen = {};
    Object.keys(this.visibleSet()).forEach(function (id) { seen[self.dimOf(self.series[id]).key] = true; });
    this.spec.dims.edges.forEach(function (e) {
      var a = nodes[e.from], b = nodes[e.to], out = a === active;
      svgEl('line', svg, {
        class: 'gx-de' + (out ? ' gx-out' : '') + (out && self.chipHover === e.id ? ' gx-hot' : ''),
        x1: a.x * U, y1: a.y * V, x2: b.x * U, y2: b.y * V, stroke: e.col
      });
    });
    nodes.forEach(function (d) {
      var g = svgEl('g', svg, { class: 'gx-dn' + (seen[d.key] ? ' gx-seen' : '') + (d === active ? ' gx-on' : '') }), l = lab(d);
      svgEl('circle', g, { cx: d.x * U, cy: d.y * V, r: 6 });
      var t = svgEl('text', g, { x: d.x * U + l[0], y: d.y * V + l[1] + 4, 'text-anchor': l[2] });
      t.appendChild(document.createTextNode(d.name + ' '));
      svgEl('tspan', t, { class: 'gx-dn-n' }).textContent = d.n;
    });
  };

  // ---- Right column ------------------------------------------------------------

  Explorer.prototype.renderRight = function () {
    var set = this.set(), tab = this.tab(), g = this.viewGroup(), kids = this.focusGroup(), pins = this.state.pins.length;
    this.setBtns[0].b.textContent = kids ? 'Children of ' + this.fullLabel(this.series[kids.parent]) + ' (' + kids.kids.length + ')' : 'Children';
    this.setBtns[1].b.textContent = 'Pinned (' + pins + ')';
    this.setBtns[1].b.setAttribute('aria-disabled', String(!pins));
    this.setBtns[1].b.title = pins ? '' : 'Nothing pinned';
    this.setBtns.forEach(function (x) { x.b.setAttribute('aria-pressed', String(x.v === set)); });
    this.tabBtns.forEach(function (t) {
      var off = set === 'pinned' && !SCALES.pinned[t.v];
      t.b.setAttribute('aria-selected', String(t.v === tab));
      t.b.setAttribute('aria-disabled', String(off));
      t.b.title = off ? 'Pinned series don\'t add up' : '';
    });
    Object.keys(this.scaleSegs).forEach(function (s) {
      Object.keys(this.scaleSegs[s]).forEach(function (t) {
        this.scaleSegs[s][t].el.style.display = s === set && t === tab && (t !== 'season' || g) ? '' : 'none';
        this.scaleSegs[s][t].sync();
      }, this);
    }, this);
    this.sizeEl.style.display = tab === 'grid' || tab === 'season' && g ? '' : 'none';
    this.sortEl.style.display = tab !== 'stacked' && g ? '' : 'none';
    this.sortSeg.sync();
    this.logSeg.el.style.display = tab === 'overlay' ? '' : 'none';
    this.logSeg.sync();
    var showPin = set === 'children' && !!g;
    this.pinAllBtn.style.display = showPin ? '' : 'none';
    if (showPin) this.pinAllBtn.textContent = this.allPinned(g) ? 'Unpin all' : 'Pin all';
    this.renderFocus();
    this.renderView();
    this.renderPeek();
    this.applyHighlight();
  };

  // Series drawn in the current view
  Explorer.prototype.shown = function () {
    var out = {}, g = this.viewGroup();
    out[this.state.focus] = true;
    if (g) g.kids.forEach(function (id) { out[id] = true; });
    return out;
  };

  Explorer.prototype.seriesHead = function (head, s) {
    head.textContent = '';
    css(el('span', 'gx-swatch', head), { background: level(s.depth) });
    el('span', 'gx-series-label', head, this.fullLabel(s));
  };

  // A time plot of `lines` ({id, d, color, width, dash}), each with forecasts
  // when `fc` is set. `noY` keeps the gridlines but drops their labels. Returns
  // false while any series is still loading.
  Explorer.prototype.timePlot = function (box, w, h, lines, o) {
    var self = this;
    o = o || {};
    if (lines.some(function (l) { return !l.d; })) {
      el('div', 'gx-empty', box, 'Loading…');
      return false;
    }
    var models = o.fc ? this.models() : [], levels = this.fc ? this.fc.level : [];
    var x1 = o.xMax != null ? o.xMax : this.xMax(), xMin = o.xMin || 0;
    var dom = o.y || extent(this.valuesOf(lines.map(function (l) { return l.d; }), models, o.fc && this.ui.intervals));
    var ml = o.noY ? 6 : o.compact ? YLAB : 44, mb = o.noX ? 4 : 18, mt = 6, mr = 6;
    var X = function (x) { return ml + (x - xMin) / ((x1 - xMin) || 1) * (w - ml - mr); };
    var Y = function (v) { return h - mb - (v - dom[0]) / ((dom[1] - dom[0]) || 1) * (h - mt - mb); };
    var svg = svgEl('svg', box, { class: 'gx-plot', width: Math.max(0, w).toFixed(0), height: Math.max(0, h).toFixed(0) });
    var g = svgEl('g', svg), ph = h - mt - mb;
    // A tick every 45px, but three on a percent axis with room, so 0–100% gets its middle
    var nt = clamp(Math.floor(ph / 45), o.pct && ph >= 60 ? 3 : 2, 5);
    this.yAxis(g, dom, Y, ml, w - mr, nt, o.noY ? null : o.pct ? pctLabel : o.log ? logLabel : tickLabel, o.log ? logTicks(dom, nt) : null);
    if (!o.noX) this.xAxis(g, xMin, x1, X, h - mb, o.xTicks);
    if ((models.length || o.now) && x1 >= this.spec.history) svgEl('line', g, { class: 'gx-now', x1: X(this.spec.history - 0.5), x2: X(this.spec.history - 0.5), y1: mt, y2: h - mb });
    lines.forEach(function (l) {
      var gs = svgEl('g', svg, { 'data-sid': l.id });
      if (l.area) {
        svgEl('path', gs, { class: 'gx-band', d: areaD(l.area.x, l.area.lo, l.area.hi, X, Y), fill: l.color, 'fill-opacity': l.area.op || .85 });
        return;
      }
      models.forEach(function (m) {
        var f = l.d.fc && l.d.fc[m];
        if (!f) return;
        var col = l.fcColor || MODEL[self.fc.models.indexOf(m) % MODEL.length];
        if (self.ui.intervals && !o.noBands) {
          levels.forEach(function (_, k) {
            svgEl('path', gs, { class: 'gx-band', d: areaD(f.x, f.lo[k], f.hi[k], X, Y), fill: col, 'fill-opacity': BAND_OP * (0.12 + 0.12 * (levels.length - 1 - k)) });
          });
        }
        svgEl('path', gs, { class: 'gx-fc', d: pathD(f.x, f.mean, X, Y), stroke: col, 'stroke-dasharray': l.fcColor ? '4 2' : null });
      });
      var p = svgEl('path', gs, { class: 'gx-y', d: pathD(l.xs || xsOf(l.d), l.ys || l.d.y, X, Y) });
      if (l.color) p.style.stroke = l.color;
      if (l.width) p.style.strokeWidth = l.width;
      if (l.dash) p.setAttribute('stroke-dasharray', l.dash);
    });
    return true;
  };
  // Every value a plot of these series draws, for its y range
  Explorer.prototype.valuesOf = function (ds, models, bands) {
    var out = [];
    ds.forEach(function (d) {
      if (!d) return;
      out.push(d.y);
      models.forEach(function (m) {
        var f = d.fc && d.fc[m];
        if (!f) return;
        out.push(f.mean);
        if (bands) out.push(f.lo[f.lo.length - 1], f.hi[f.hi.length - 1]);
      });
    });
    return out;
  };
  // Gridlines at `ticks`, or at nice steps when there are none
  Explorer.prototype.yAxis = function (g, r, Y, x0, x1, n, fmt, ticks) {
    if (!ticks) {
      var step = niceStep(r, n);
      ticks = [];
      for (var u = Math.ceil(r[0] / step) * step; u <= r[1]; u += step) ticks.push(u);
    }
    ticks.forEach(function (v) {
      var y = Y(v);
      svgEl('line', g, { class: 'gx-tick-line', x1: x0, x2: x1, y1: y, y2: y });
      if (fmt) svgEl('text', g, { class: 'gx-tick', x: x0 - 4, y: y + 3.5, 'text-anchor': 'end' }).textContent = fmt(v);
    });
  };
  // Ticks at the start of seasonal cycles where there are any, else evenly spaced times
  Explorer.prototype.xAxis = function (g, x0, x1, X, y, ticks) {
    var spec = this.spec, season = spec.season, max = Math.max(2, Math.floor((X(x1) - X(x0)) / 64)), at = [];
    if (ticks) {
      at = ticks;
    } else if (season) {
      for (var i = Math.ceil(x0); i <= x1; i++) if (i === 0 || season.cycle[i] !== season.cycle[i - 1]) at.push({ x: i, label: season.cycle[i] });
      var every = Math.ceil(at.length / max);
      at = at.filter(function (_, k) { return k % every === 0; });
    } else {
      var step = Math.max(1, Math.ceil((x1 - x0) / max));
      for (var j = Math.ceil(x0); j <= x1; j += step) at.push({ x: j, label: spec.times[j] });
    }
    at.forEach(function (t) {
      svgEl('text', g, { class: 'gx-tick', x: X(t.x), y: y + 13, 'text-anchor': 'middle' }).textContent = t.label;
    });
  };

  Explorer.prototype.renderFocus = function () {
    var s = this.series[this.state.focus];
    this.seriesHead(this.focusHead, s);
    var body = this.focusBody;
    body.textContent = '';
    var box = el('div', 'gx-plot-box', body);
    var d = this.data(s.id, false);
    if (d === undefined) this.need([s.id], false);
    this.timePlot(box, box.clientWidth, box.clientHeight, [{ id: s.id, d: d }], { fc: true });
  };

  Explorer.prototype.renderView = function () {
    var view = this.view, g = this.viewGroup(), s = this.series[this.state.focus], tab = this.tab();
    view.textContent = '';
    if (tab === 'season' && !g) return this.renderSeason(s);
    if (!g) {
      el('div', 'gx-empty', view, this.splits(s).length ? 'Click the node to split it' : 'No children: every key is fixed');
      return;
    }
    if (tab === 'stacked') return this.renderStacked(g);
    g = this.sorted(g);
    if (tab === 'grid') this.renderGrid(g);
    else if (tab === 'overlay') this.renderOverlay(g);
    else this.renderSeasons(g);
  };

  Explorer.prototype.allPinned = function (g) {
    var pins = this.state.pins;
    return g.kids.every(function (id) { return pins.indexOf(id) > -1; });
  };

  // g with its series in the chosen order: as split (or pinned), by size
  // (their history totals, largest first) or by growth. Split order until
  // every series is loaded, and `base` keeps the split order for colours.
  Explorer.prototype.sorted = function (g) {
    var self = this, by = this.opts().sort;
    var out = { key: g.key, parent: g.parent, e: g.e, kids: g.kids, shared: g.shared, base: g };
    if (by === 'key') return out;
    var ds = g.kids.map(function (id) { return self.data(id, false) || self.data(id, true); });
    if (ds.some(function (d) { return !d; })) return out;
    var v = ds.map(function (d) { return by === 'size' ? d.sum : self.growth(d); });
    var rank = function (i) { return isFinite(v[i]) ? v[i] : -Infinity; };
    out.kids = g.kids.map(function (_, i) { return i; })
      .sort(function (a, b) { return rank(b) - rank(a) || a - b; })
      .map(function (i) { return g.kids[i]; });
    return out;
  };
  // Growth of a series: the last cycle's mean over the one before's, or the
  // last third's over the first third's when there is no season (or too
  // little history for two cycles)
  Explorer.prototype.growth = function (d) {
    var n = this.spec.history, xs = xsOf(d), P = this.spec.season ? this.spec.season.period : 0;
    var cyc = P > 0 && 2 * P <= n, k = cyc ? P : Math.max(1, Math.floor(n / 3));
    var mean = function (lo, hi) { return meanOf(d.y.map(function (v, i) { return xs[i] >= lo && xs[i] < hi ? v : null; })); };
    var now = mean(n - k, n), then = cyc ? mean(n - 2 * k, n - k) : mean(0, k);
    return then ? (now - then) / Math.abs(then) : NaN;
  };

  // Small multiples of g's series, sized by the plot size slider, each with
  // its share of the parent's total and a pin. A shared y is labelled on the
  // first column only, and the others take its room. Clicking a cell focuses
  // its series. `plot(c, i, w, h, noY)` draws series i.
  Explorer.prototype.childGrid = function (g, shares, shared, plot) {
    var self = this, W = this.view.clientWidth - 24, cw = this.ui.cell, ch = Math.round(cw * 0.5);
    var cols = Math.max(1, Math.floor((W + 12) / (cw + 12)));
    var box = el('div', 'gx-cells', this.view);
    var once = !!shared && cols > 1, room = once ? YLAB - 6 : 0;
    var w = (W - (cols - 1) * 12 - room) / cols, w0 = w + room;
    box.style.gridTemplateColumns = 'minmax(0, ' + w0.toFixed(1) + 'fr)' + (cols > 1 ? ' repeat(' + (cols - 1) + ', minmax(0, ' + w.toFixed(1) + 'fr))' : '');
    g.kids.forEach(function (id, i) {
      var k = self.series[id];
      var c = el('div', 'gx-cell', box);
      c.setAttribute('data-sid', id);
      c.addEventListener('click', function (ev) { if (!ev.target.closest('.gx-pin')) self.focusOn(id); });
      var chd = el('div', 'gx-cell-head', c);
      css(el('span', 'gx-swatch', chd), { background: level(k.depth) });
      var label = el('button', 'gx-cell-label', chd, self.memberLabel(id, g));
      label.type = 'button';
      label.title = self.fullLabel(k);
      label.setAttribute('aria-label', 'Focus ' + self.fullLabel(k));
      if (shares[i] != null) self.shareBar(chd, shares[i], g.parent);
      if (g.shared.indexOf(id) > -1) {
        var second = el('span', 'gx-fork', chd);
        second.title = 'Second parent';
        second.setAttribute('role', 'img');
        second.setAttribute('aria-label', 'Second parent');
        icon(second, 'fork');
      }
      var on = self.state.pins.indexOf(id) > -1, pin = el('button', 'gx-pin', chd, '📌');
      pin.type = 'button';
      pin.setAttribute('aria-pressed', String(on));
      pin.setAttribute('aria-label', (on ? 'Unpin ' : 'Pin ') + self.fullLabel(k));
      pin.title = on ? 'Unpin' : 'Pin';
      pin.addEventListener('click', function () { self.togglePin(id); });
      var first = i % cols === 0;
      plot(c, i, (first ? w0 : w) - 6, ch, once && !first);
    });
  };
  // Shares of the parent's total, where the parent and child are loaded
  function sharesOf(ds, parent) {
    return ds.map(function (d) { return parent && d ? d.sum / parent.sum : null; });
  }

  // Small multiples of the series. Share of parent (or of the total, for
  // pinned series) divides full series, so every block of time lines up.
  Explorer.prototype.renderGrid = function (g) {
    var self = this;
    var mode = this.opts().scales.grid, ratio = mode === 'parent';
    var ds = g.kids.map(function (id) { return self.data(id, ratio); });
    var parent = this.data(g.parent, ratio);
    var missing = g.kids.concat([g.parent]).filter(function (id) { return self.data(id, ratio) === undefined; });
    if (missing.length) this.need(missing, ratio);
    if (ratio && !missing.length) ds = ds.map(function (d) { return shareOf(d, parent); });
    var log = mode === 'log', dropped = log ? nonPositive(ds) : 0;
    if (log) ds = ds.map(function (d) { return d && log10Of(d); });
    var shared = null;
    if ((mode === 'shared' || log) && !missing.length) shared = extent(this.valuesOf(ds, this.models(), this.ui.intervals));
    if (ratio && !missing.length) {
      var r = extent(this.valuesOf(ds, this.models(), false));
      shared = [Math.min(0, r[0]), Math.max(1, r[1])];
    }
    this.childGrid(g, sharesOf(ds, parent), shared, function (c, i, w, h, noY) {
      self.timePlot(c, w, h, [{ id: g.kids[i], d: ds[i] }],
        { fc: true, y: shared, compact: true, noX: h < 70, noY: noY, noBands: ratio, pct: ratio, log: log });
    });
    if (dropped) this.legend([logChip(dropped)]);
  };
  // A legend chip of the values a log scale leaves out
  function logChip(k) { return { chip: true, label: k + ' ≤ 0 hidden', title: 'Left off the log scale' }; }

  // A thin bar of a child's share of its parent's history total, so free scales keep a sense of size
  Explorer.prototype.shareBar = function (head, share, pid) {
    var bar = el('span', 'gx-share', head);
    var pct = isFinite(share) ? share : 0;
    css(el('i', null, bar), { width: (100 * clamp(pct, 0, 1)).toFixed(1) + '%' });
    bar.title = isFinite(share) ? +(100 * share).toFixed(1) + '% of ' + this.fullLabel(this.series[pid]) : 'Parent sums to zero';
  };

  // Every child on one plot, coloured in turn, with forecast means dashed.
  // Beyond the colours, the largest keep one and the rest are thin grey lines
  // under them. Indexed needs full series, so each starts from its first period.
  Explorer.prototype.renderOverlay = function (g) {
    var self = this, W = this.view.clientWidth - 24, H = Math.max(120, this.view.clientHeight - 110);
    var indexed = this.opts().scales.overlay === 'indexed';
    // Colours follow the split order, or size, so they stay put when the children are sorted
    var base = g.base.kids, raw = base.map(function (id) { return self.data(id, indexed); }), col = {};
    var loaded = raw.every(function (d) { return d; }), split = loaded ? topN(raw) : null;
    if (split) split.top.forEach(function (i, r) { col[base[i]] = split.color(i, r); });
    var log = this.opts().overlayLog, dropped = log ? nonPositive(raw) : 0;
    var lines = g.kids.map(function (id) {
      var d = self.data(id, indexed), c = col[id] || OTHER;
      if (d && indexed) d = indexTo100(d);
      return { id: id, d: d && log ? log10Of(d) : d, color: c, width: col[id] ? 1.4 : 1, fcColor: c };
    });
    var missing = lines.filter(function (l) { return l.d === undefined; }).map(function (l) { return l.id; });
    if (missing.length) this.need(missing, indexed);
    var box = el('div', null, this.view);
    var grey = lines.filter(function (l) { return !col[l.id]; });
    this.timePlot(box, W, H, grey.concat(lines.filter(function (l) { return col[l.id]; })), { fc: true, noBands: true, log: log });
    var label = function (id) { return self.memberLabel(id, g); };
    var keys = lines.filter(function (l) { return col[l.id]; }).map(function (l) { return { id: l.id, label: label(l.id), color: l.color }; });
    if (split && split.rest.length) {
      keys.push({ label: 'Other (' + grey.length + ')', color: OTHER, title: grey.map(function (l) { return label(l.id); }).join(', ') });
    }
    if (dropped) keys.push(logChip(dropped));
    this.legend(keys);
  };

  // Children stacked to their parent, or as shares of it, with the parent
  // dashed. Totals carry on with the first shown model's forecast means, when
  // every series has them. Needs full series, so every block of time lines up.
  Explorer.prototype.renderStacked = function (g) {
    var self = this, W = this.view.clientWidth - 24, H = Math.max(120, this.view.clientHeight - 130);
    var ds = g.kids.map(function (id) { return self.data(id, true); });
    var parent = this.data(g.parent, true);
    var missing = g.kids.concat([g.parent]).filter(function (id) { return self.data(id, true) === undefined; });
    if (missing.length) {
      this.need(missing, true);
      el('div', 'gx-empty', this.view, 'Loading…');
      return;
    }
    var n = this.spec.history, share = this.ui.sets.children.scales.stacked === 'share';
    var m = share ? null : this.models()[0];
    if (m && !ds.concat([parent]).every(function (d) { return d.fc && d.fc[m]; })) m = null;
    var N = m ? this.spec.times.length : n, xs = [];
    for (var t = 0; t < N; t++) xs.push(t);
    // History, then the forecast means of model m
    var ext = function (d) {
      var y = xs.map(function (t) { return t < n ? d.y[t] : null; });
      if (m) d.fc[m].x.forEach(function (x, j) { y[x] = d.fc[m].mean[j]; });
      return y;
    };
    // Shares of the parent, not of the children's sum, so incoherent data show
    var whole = xs.map(function (t) { return parent.y[t] || null; });
    // The largest children nearest zero, and any beyond the colours merged
    // into "Other" on top
    var ys = ds.map(ext), split = topN(ds), bands = split.top.map(function (i, r) {
      return { id: g.kids[i], d: ds[i], y: ys[i], label: self.partLabel(self.series[g.kids[i]], g.e), color: split.color(i, r) };
    });
    if (split.rest.length) {
      bands.push({
        id: 'other', d: parent, color: OTHER, label: 'Other (' + split.rest.length + ')',
        title: split.rest.map(function (i) { return self.partLabel(self.series[g.kids[i]], g.e); }).join(', '),
        y: xs.map(function (t) { return split.rest.reduce(function (a, i) { return a + (ys[i][t] || 0); }, 0); })
      });
    }
    // Positive values stack up from zero and negative values down from it,
    // fainter over the forecasts
    var pos = xs.map(function () { return 0; }), neg = pos.slice(), keys = [], lines = [];
    var area = function (b, lo, hi) {
      lines.push({ id: b.id, d: b.d, color: b.color, area: { x: xs.slice(0, n), lo: lo.slice(0, n), hi: hi.slice(0, n) } });
      if (m) lines.push({ id: b.id, d: b.d, color: b.color, area: { x: xs.slice(n - 1), lo: lo.slice(n - 1), hi: hi.slice(n - 1), op: 0.45 } });
    };
    bands.forEach(function (b) {
      keys.unshift(b);
      var v = xs.map(function (t) { var u = b.y[t] || 0; return share ? (whole[t] ? u / whole[t] : 0) : u; });
      var up = xs.map(function (t) { return pos[t] + Math.max(0, v[t]); });
      var down = xs.map(function (t) { return neg[t] + Math.min(0, v[t]); });
      area(b, pos, up);
      if (v.some(function (u) { return u < 0; })) area(b, down, neg);
      pos = up;
      neg = down;
    });
    var top = share ? whole.map(function (u) { return u && 1; }) : ext(parent);
    lines.push({ id: g.parent, d: parent, xs: xs, ys: top.map(function (u, t) { return t < n ? u : null; }), color: INK, width: 1.6, dash: '5 3' });
    if (m) {
      lines.push({ id: g.parent, d: parent, xs: xs, ys: top.map(function (u, t) { return t < n - 1 ? null : u; }),
        color: MODEL[this.fc.models.indexOf(m) % MODEL.length], width: 1.8, dash: '5 3' });
    }
    var y = extent([pos, neg, top]);
    var box = el('div', null, this.view);
    this.timePlot(box, W, H, lines, { y: [Math.min(0, y[0]), y[1]], xMax: N - 1, pct: share, now: !!m });
    // The parent's line, the forecasts and negative values join the key
    var whom = this.fullLabel(this.series[g.parent]);
    keys.push({ id: g.parent, label: share ? '100% of ' + whom : whom, dash: INK, title: 'Coherent children stack to it' });
    if (m) keys.push({ label: m, dash: MODEL[this.fc.models.indexOf(m) % MODEL.length], title: 'Forecast means, after the line' });
    if (neg.some(function (u) { return u < 0; })) keys.push({ chip: true, label: 'Negatives below 0', title: 'Negative values stack below zero' });
    this.legend(keys);
  };

  // A key of {id, label, color, title} items, in the order given. Items with
  // `dash` are dashed lines, and `chip` ones are notes with no swatch.
  Explorer.prototype.legend = function (items) {
    var box = el('div', 'gx-legend', this.view);
    items.forEach(function (it) {
      var s = el('span', it.chip ? 'gx-note' : null, box);
      if (it.id != null) s.setAttribute('data-sid', it.id);
      if (it.title) s.title = it.title;
      if (it.dash) css(el('i', 'gx-dash', s), { borderTopColor: it.dash });
      else if (!it.chip) css(el('i', null, s), { background: it.color });
      s.appendChild(document.createTextNode(it.label));
    });
  };

  // One line per seasonal cycle of a full series, oldest faintest, and the cycles' labels
  Explorer.prototype.seasonLines = function (d, id) {
    var season = this.spec.season, cycles = [], cur = null;
    for (var t = 0; t < d.y.length; t++) {
      if (!cur || season.cycle[t] !== cur.label) { cur = { label: season.cycle[t], xs: [], ys: [] }; cycles.push(cur); }
      cur.xs.push(season.pos[t] - 1);
      cur.ys.push(d.y[t]);
    }
    var n = cycles.length;
    return cycles.map(function (c, i) {
      var f = n > 1 ? i / (n - 1) : 1;
      var col = 'rgb(' + SEASON[0].map(function (a, j) { return Math.round(a + (SEASON[1][j] - a) * f); }).join(',') + ')';
      return { id: id, d: d, xs: c.xs, ys: c.ys, color: col, width: i === n - 1 ? 2.2 : 1.2, label: c.label };
    });
  };
  // Seasons along the x axis, at most one label per `room` pixels of width w
  Explorer.prototype.seasonTicks = function (w, room) {
    var season = this.spec.season, P = season.period, ticks = [];
    var step = Math.max(1, Math.ceil(P / 12), Math.ceil(P / Math.max(2, Math.floor(w / room))));
    for (var p = 0; p < P; p += step) ticks.push({ x: p, label: season.labels ? season.labels[p] : String(p + 1) });
    return ticks;
  };
  // A key of the oldest and newest cycles
  Explorer.prototype.seasonKey = function (lines) {
    var n = lines.length;
    if (n) this.legend((n > 1 ? [lines[0], lines[n - 1]] : lines).map(function (l) { return { label: l.label, color: l.color }; }));
  };
  Explorer.prototype.noSeason = function () {
    if (this.spec.season) return false;
    el('div', 'gx-empty', this.view, 'No seasonal period');
    return true;
  };

  // The focus's season plot, before it is split
  Explorer.prototype.renderSeason = function (s) {
    var season = this.spec.season, view = this.view;
    if (this.noSeason()) return;
    var d = this.data(s.id, true);
    if (d === undefined) {
      this.need([s.id], true);
      el('div', 'gx-empty', view, 'Loading…');
      return;
    }
    var lines = this.seasonLines(d, s.id);
    var W = view.clientWidth - 24, H = Math.max(120, view.clientHeight - 60);
    var box = el('div', null, view);
    this.timePlot(box, W, H, lines, { xMax: season.period - 1, y: extent([d.y]), xTicks: this.seasonTicks(W, 48) });
    this.seasonKey(lines);
  };

  // Season plots of the children as small multiples, from full series
  Explorer.prototype.renderSeasons = function (g) {
    var self = this, season = this.spec.season;
    if (this.noSeason()) return;
    var ds = g.kids.map(function (id) { return self.data(id, true); });
    var parent = this.data(g.parent, true);
    var missing = g.kids.concat([g.parent]).filter(function (id) { return self.data(id, true) === undefined; });
    if (missing.length) this.need(missing, true);
    var shared = this.opts().scales.season === 'shared' && !missing.length ? extent(ds.map(function (d) { return d.y; })) : null;
    var key = [];
    // The cell carries the series id, so its cycles are left unmarked
    this.childGrid(g, sharesOf(ds, parent), shared, function (c, i, w, h, noY) {
      var d = ds[i], lines = d ? self.seasonLines(d, null) : [{ id: null, d: d }];
      if (d && lines.length > key.length) key = lines;
      self.timePlot(c, w, h, lines, { xMax: season.period - 1, y: shared || (d ? extent([d.y]) : null),
        xTicks: self.seasonTicks(w, 40), compact: true, noX: h < 70, noY: noY });
    });
    this.seasonKey(key);
  };

  // The hovered series stands out wherever it is drawn
  Explorer.prototype.applyHighlight = function () {
    var id = this.state.hover, right = this.focusPane.parentNode;
    right.querySelectorAll('.gx-hl').forEach(function (e) { e.classList.remove('gx-hl'); });
    right.querySelectorAll('.gx-has-hl').forEach(function (e) { e.classList.remove('gx-has-hl'); });
    this.focusPane.classList.toggle('gx-hl', id != null && id === this.state.focus);
    if (id == null) return;
    right.querySelectorAll('[data-sid="' + id + '"]').forEach(function (e) {
      e.classList.add('gx-hl');
      var plot = e.closest('.gx-plot');
      if (plot && plot.querySelectorAll('g[data-sid]').length > 1 && e.tagName.toLowerCase() === 'g') plot.classList.add('gx-has-hl');
    });
    // Thicken the hovered line, not just its group
    right.querySelectorAll('g.gx-hl > path.gx-y').forEach(function (p) { p.classList.add('gx-hl'); });
  };

  // ---- Start -------------------------------------------------------------------

  var root = document.getElementById('gx');
  fetch('api/spec')
    .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
    .then(function (spec) { window.explorer = new Explorer(root, spec); })
    .catch(function (err) {
      root.textContent = '';
      el('p', 'gx-error', root, 'Could not load the series graph: ' + err.message);
    });
})();
