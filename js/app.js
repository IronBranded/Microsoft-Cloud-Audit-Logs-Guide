/*
 * Microsoft Cloud Audit Logs Guide: interactive site.
 * Renders data/catalog-data.js (window.GUIDE_DATA), which scripts/build-site.ps1 generates from the
 * repository's data files. Every product fact shown here comes from that catalog; this script only
 * filters, groups, and lays it out. No network requests, no storage beyond the theme choice.
 */
(function () {
  'use strict';

  var appEl = document.getElementById('app');
  var D = window.GUIDE_DATA;
  if (!D || !D.catalog) {
    appEl.innerHTML = '<p class="error">The catalog data (data/catalog-data.js) did not load. ' +
      'Run scripts/build-site.ps1, then reload this page.</p>';
    return;
  }

  // ---------------------------------------------------------------- indexes
  var P = D.presentation;
  var SITE = P.site;
  var ENTRIES = D.catalog.entries.filter(function (e) { return e.publication.site; });
  var PRODUCTS = D.products.products;
  var SOURCES = D.sources.sources;
  var RELS = D.relationships.relationships.filter(function (r) {
    return ENTRIES.some(function (e) { return e.id === r.from; }) && ENTRIES.some(function (e) { return e.id === r.to; });
  });

  function mapBy(list, key) { var m = new Map(); list.forEach(function (x) { m.set(x[key], x); }); return m; }
  var entryById = mapBy(ENTRIES, 'id');
  var productById = mapBy(PRODUCTS, 'id');
  var sourceById = mapBy(SOURCES, 'id');
  var planeByName = mapBy(P.planes, 'name');
  var pathByNumber = mapBy(P.acquisition_paths, 'number');
  var statusInfo = mapBy(P.verification_legend, 'status');
  var flagMeaning = {};
  P.availability_legend.forEach(function (a) { flagMeaning[a.code] = a.meaning; });
  var roleTag = {};
  P.command_roles.forEach(function (r) { roleTag[r.role] = r.tag; });
  var pathByCommand = new Map();
  P.acquisition_paths.forEach(function (p) { p.commands.forEach(function (c) { pathByCommand.set(c, p.number); }); });
  var PRIORITY_ORDER = { Core: 0, Extended: 1, Specialized: 2 };
  var destinations = SITE.destinations.map(function (d) {
    return { id: d.id, label: d.label, rx: new RegExp(d.pattern, 'i'), entryIds: d.entry_ids || [] };
  });

  // ---------------------------------------------------------------- small helpers
  function esc(value) {
    return String(value === null || value === undefined ? '' : value).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function slug(text) { return String(text).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, ''); }
  function pad2(n) { return String(n).padStart(2, '0'); }
  function uniq(list) { return Array.from(new Set(list)); }
  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : many); }
  function planeOf(name) { return planeByName.get(name) || { number: 0, name: name }; }
  function planeClass(name) { return 'plane-' + planeOf(name).number; }
  function firstSentence(text) {
    if (!text) { return ''; }
    var parts = String(text).split(/(?<=[.!?])\s+(?=[A-Z])/);
    return parts[0];
  }
  function vr(text) {
    if (text === 'Verification required') { return '<span class="vr">Verification required</span>'; }
    return esc(text);
  }
  function unverifiedMark(verified) { return verified ? '' : ' <span class="vr">Verification required</span>'; }
  function list(items, cls) {
    items = (items || []).filter(Boolean);
    if (!items.length) { return ''; }
    return '<ul' + (cls ? ' class="' + cls + '"' : '') + '>' + items.map(function (i) { return '<li>' + esc(i) + '</li>'; }).join('') + '</ul>';
  }
  function hTag(level, text, attrs) { return '<h' + level + (attrs || '') + '>' + text + '</h' + level + '>'; }

  function srcLink(id, label) {
    var s = sourceById.get(id);
    if (!s) { return esc(label || id); }
    return '<a href="' + esc(s.url) + '" target="_blank" rel="noopener noreferrer">' + esc(label || s.title) +
      '<span class="visually-hidden"> (opens Microsoft Learn in a new tab)</span><span class="ext-mark" aria-hidden="true">↗</span></a>';
  }
  function srcLinks(ids) {
    ids = uniq(ids || []);
    if (!ids.length) { return ''; }
    return '<span class="muted">Source: </span>' + ids.map(function (id) { return srcLink(id); }).join('; ');
  }
  function entryLink(id) {
    var e = entryById.get(id);
    return e ? '<a href="#/entry/' + esc(id) + '">' + esc(e.evidence_source) + '</a>' : esc(id);
  }
  function productLink(id, label) {
    var p = productById.get(id);
    return p ? '<a href="#/product/' + esc(id) + '">' + esc(label || p.name) + '</a>' : esc(id);
  }

  function planeTag(name) {
    var p = planeOf(name);
    return '<span class="plane-tag"><span class="plane-no" aria-hidden="true">' + pad2(p.number) + '</span>' + esc(p.name) + '</span>';
  }
  function chips(flags) {
    return '<span class="chips">' + flags.map(function (f) {
      return '<abbr class="chip chip-' + slug(f) + '" title="' + esc(flagMeaning[f] || f) + '">' + esc(f) + '</abbr>';
    }).join('') + '</span>';
  }
  function statusClass(status) {
    return { 'Verified': 'ok', 'Conditional': 'cond', 'Deprecated or replaced': 'dep' }[status] || 'req';
  }
  function statusBadge(e) {
    var s = e.verification.status;
    var info = statusInfo.get(s) || { symbol: '?' };
    var gaps = (e.verification.gaps || []).length;
    var suffix = s === 'Conditional' ? ' · ' + plural(gaps, 'open gap', 'open gaps') : '';
    return '<span class="status status-' + statusClass(s) + '"><span aria-hidden="true">' + esc(info.symbol) + '</span> ' + esc(s) + suffix + '</span>';
  }
  function apiStatus(status) {
    return '<span class="api-status is-' + slug(status) + '">' + esc(status) + '</span>';
  }
  function roleTagHtml(role) {
    var tag = roleTag[role] || role;
    return '<span class="tag tag-' + slug(tag) + '" title="' + esc(role) + '">' + esc(tag) + '</span>';
  }

  var codeCounter = 0;
  function codeBlock(text, label) {
    var id = 'code-' + (++codeCounter);
    return '<div class="code-block"><pre id="' + id + '"><code>' + esc(text) + '</code></pre>' +
      '<button type="button" class="copy-btn" data-copy="' + id + '" aria-label="Copy ' + esc(label) + '">Copy</button></div>';
  }

  // ---------------------------------------------------------------- derived entry facts
  function commandPath(entry, index) {
    var cmds = entry.powershell.commands;
    var c = cmds[index];
    if (pathByCommand.has(c.command)) { return pathByCommand.get(c.command); }
    if (c.role === 'Authenticates session') {
      for (var j = index + 1; j < cmds.length; j++) {
        if (pathByCommand.has(cmds[j].command)) { return pathByCommand.get(cmds[j].command); }
      }
    }
    return P.acquisition_type_paths[entry.powershell.acquisition_type] || null;
  }
  var pathsCache = new Map();
  function entryPaths(entry) {
    if (pathsCache.has(entry.id)) { return pathsCache.get(entry.id); }
    var set = new Set();
    if (entry.powershell.supported) {
      entry.powershell.commands.forEach(function (c, i) { var p = commandPath(entry, i); if (p) { set.add(String(p)); } });
    }
    if (!set.size) { set.add('none'); }
    pathsCache.set(entry.id, set);
    return set;
  }
  var destCache = new Map();
  function entryDestinations(entry) {
    if (destCache.has(entry.id)) { return destCache.get(entry.id); }
    var set = new Set();
    destinations.forEach(function (d) {
      if (d.entryIds.indexOf(entry.id) !== -1 || entry.preservation_options.some(function (o) { return d.rx.test(o); })) { set.add(d.id); }
    });
    destCache.set(entry.id, set);
    return set;
  }
  function isLicenseDependent(e) { return e.availability_flags.indexOf('LICENSE') !== -1 || !!e.licensing_dependency; }

  var searchCache = new Map();
  function searchText(e) {
    if (searchCache.has(e.id)) { return searchCache.get(e.id); }
    var p = productById.get(e.product_id) || {};
    var parts = [e.id, e.evidence_source, e.evidence_type, e.evidence_plane, p.name, p.short_name, e.description,
      e.where_to_investigate, e.portal_path, e.configuration_notes, e.licensing_dependency, e.deployment_dependency, e.notes,
      e.api.name, e.api.endpoint, e.availability, e.availability_flags.join(' ')]
      .concat(e.investigation_relevance, e.relevance_tags, e.preservation_options, e.limitations, e.powershell.modules,
        e.log_analytics_tables.map(function (t) { return t.table; }),
        e.powershell.commands.map(function (c) { return c.command + ' ' + c.interface + ' ' + c.purpose; }),
        e.kql_examples.map(function (k) { return k.title; }));
    var text = parts.filter(Boolean).join(' \n ').toLowerCase();
    searchCache.set(e.id, text);
    return text;
  }

  function sortEntries(list) {
    return list.slice().sort(function (a, b) {
      return planeOf(a.evidence_plane).number - planeOf(b.evidence_plane).number ||
        PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority] ||
        a.evidence_source.localeCompare(b.evidence_source);
    });
  }

  // ---------------------------------------------------------------- filters
  function presentValues(getter) {
    return uniq(ENTRIES.map(getter)).sort(function (a, b) { return String(a).localeCompare(String(b)); });
  }
  var FILTERS = [
    { key: 'plane', label: 'Evidence plane',
      options: function () { return P.planes.map(function (p) { return [p.name, pad2(p.number) + ' ' + p.name]; }); },
      test: function (e, v) { return e.evidence_plane === v; }, chip: function (v) { return v; } },
    { key: 'product', label: 'Microsoft product',
      options: function () { return PRODUCTS.map(function (p) { return [p.id, p.name]; }); },
      test: function (e, v) { return e.product_id === v; }, chip: function (v) { return (productById.get(v) || {}).short_name || v; } },
    { key: 'type', label: 'Evidence type',
      options: function () { return presentValues(function (e) { return e.evidence_type; }).map(function (v) { return [v, v]; }); },
      test: function (e, v) { return e.evidence_type === v; } },
    { key: 'collection', label: 'Automatic or configured',
      options: function () { return [['auto', 'Available without prior configuration'], ['config', 'Configuration required beforehand']]; },
      test: function (e, v) { return v === 'auto' ? !e.configuration_required : e.configuration_required; },
      chip: function (v) { return v === 'auto' ? 'No prior configuration' : 'Configuration required'; } },
    { key: 'availability', label: 'Availability',
      options: function () { return presentValues(function (e) { return e.availability; }).map(function (v) { return [v, v]; }); },
      test: function (e, v) { return e.availability === v; } },
    { key: 'relevance', label: 'Investigation relevance',
      options: function () {
        return uniq([].concat.apply([], ENTRIES.map(function (e) { return e.relevance_tags; }))).sort().map(function (v) { return [v, v]; });
      },
      test: function (e, v) { return e.relevance_tags.indexOf(v) !== -1; } },
    { key: 'path', label: 'Acquisition method',
      options: function () {
        return P.acquisition_paths.map(function (p) { return [String(p.number), p.number + '. ' + p.name]; })
          .concat([['none', 'No documented PowerShell method']]);
      },
      test: function (e, v) { return entryPaths(e).has(v); },
      chip: function (v) { return v === 'none' ? 'No PowerShell method' : 'Path ' + v + ': ' + pathByNumber.get(Number(v)).name; } },
    { key: 'destination', label: 'Destination or repository', hint: SITE.destinations_note,
      options: function () { return destinations.map(function (d) { return [d.id, d.label]; }); },
      test: function (e, v) { return entryDestinations(e).has(v); },
      chip: function (v) { var d = destinations.find(function (x) { return x.id === v; }); return d ? d.label : v; } },
    { key: 'status', label: 'Verification status',
      options: function () { return P.verification_legend.map(function (s) { return [s.status, s.symbol + ' ' + s.status]; }); },
      test: function (e, v) { return e.verification.status === v; } },
    { key: 'priority', label: 'Publication priority',
      options: function () { return ['Core', 'Extended', 'Specialized'].map(function (v) { return [v, v]; }); },
      test: function (e, v) { return e.priority === v; } }
  ];
  var TOGGLES = [
    { key: 'ps', label: 'PowerShell acquisition documented', test: function (e) { return e.powershell.supported; } },
    { key: 'license', label: 'License-dependent', test: isLicenseDependent }
  ];
  var GROUPS = [['plane', 'Evidence plane'], ['product', 'Microsoft product'], ['none', 'No grouping']];

  function emptyState() {
    var s = { q: '', group: 'plane' };
    FILTERS.forEach(function (f) { s[f.key] = ''; });
    TOGGLES.forEach(function (t) { s[t.key] = false; });
    return s;
  }
  function stateFromParams(params) {
    var s = emptyState();
    s.q = params.get('q') || '';
    var g = params.get('group');
    if (g && GROUPS.some(function (x) { return x[0] === g; })) { s.group = g; }
    FILTERS.forEach(function (f) {
      var v = params.get(f.key);
      if (v && f.options().some(function (o) { return o[0] === v; })) { s[f.key] = v; }
    });
    TOGGLES.forEach(function (t) { s[t.key] = params.get(t.key) === '1'; });
    return s;
  }
  function stateToQuery(s) {
    var params = new URLSearchParams();
    if (s.q) { params.set('q', s.q); }
    FILTERS.forEach(function (f) { if (s[f.key]) { params.set(f.key, s[f.key]); } });
    TOGGLES.forEach(function (t) { if (s[t.key]) { params.set(t.key, '1'); } });
    if (s.group !== 'plane') { params.set('group', s.group); }
    var q = params.toString();
    return q ? '?' + q : '';
  }
  function activeCount(s) {
    var n = s.q ? 1 : 0;
    FILTERS.forEach(function (f) { if (s[f.key]) { n++; } });
    TOGGLES.forEach(function (t) { if (s[t.key]) { n++; } });
    return n;
  }
  function matches(e, s) {
    if (s.q) {
      var text = searchText(e);
      var terms = s.q.toLowerCase().split(/\s+/).filter(Boolean);
      if (!terms.every(function (t) { return text.indexOf(t) !== -1; })) { return false; }
    }
    for (var i = 0; i < FILTERS.length; i++) {
      var f = FILTERS[i];
      if (s[f.key] && !f.test(e, s[f.key])) { return false; }
    }
    for (var j = 0; j < TOGGLES.length; j++) {
      if (s[TOGGLES[j].key] && !TOGGLES[j].test(e)) { return false; }
    }
    return true;
  }

  // ---------------------------------------------------------------- cards
  function entryCard(e, headingLevel) {
    var p = productById.get(e.product_id) || { name: e.product_id };
    var replaced = e.replaced_by ? '<p class="desc"><strong>Replaced by:</strong> ' + entryLink(e.replaced_by) + '</p>' : '';
    return '<article class="card ' + planeClass(e.evidence_plane) + '">' +
      '<div class="card-top">' + planeTag(e.evidence_plane) + '<span class="prio' + (e.priority === 'Core' ? ' prio-core' : '') + '">' + esc(e.priority) + '</span></div>' +
      hTag(headingLevel || 3, '<a href="#/entry/' + esc(e.id) + '">' + esc(e.evidence_source) + '</a>') +
      '<p class="product-line">' + esc(p.name) + ' · ' + esc(e.evidence_type) + '</p>' +
      '<p class="desc">' + esc(firstSentence(e.description)) + '</p>' + replaced +
      '<dl class="facts">' +
      '<div><dt>Availability</dt><dd>' + chips(e.availability_flags) + ' ' + esc(e.availability) + '</dd></div>' +
      '<div><dt>Acquisition</dt><dd>' + esc(e.powershell.acquisition_type) + '</dd></div>' +
      '<div><dt>Status</dt><dd>' + statusBadge(e) + '</dd></div>' +
      '</dl></article>';
  }

  // ---------------------------------------------------------------- page: explore
  var exploreState = emptyState();
  var searchTimer = null;

  function renderExplore(params) {
    exploreState = stateFromParams(params);
    var s = exploreState;
    var counts = function (f, value) { return ENTRIES.filter(function (e) { return f.test(e, value); }).length; };
    var selects = FILTERS.map(function (f) {
      var hintId = f.hint ? ' aria-describedby="hint-' + f.key + '"' : '';
      return '<div class="field"><label for="f-' + f.key + '">' + esc(f.label) + '</label>' +
        '<select id="f-' + f.key + '" name="' + f.key + '"' + hintId + '><option value="">All</option>' +
        f.options().map(function (o) {
          return '<option value="' + esc(o[0]) + '"' + (s[f.key] === o[0] ? ' selected' : '') + '>' + esc(o[1]) + ' (' + counts(f, o[0]) + ')</option>';
        }).join('') + '</select>' +
        (f.hint ? '<p class="field-hint" id="hint-' + f.key + '">' + esc(f.hint) + '</p>' : '') + '</div>';
    }).join('');
    var toggles = '<fieldset class="checks"><legend>Only show evidence that is</legend>' + TOGGLES.map(function (t) {
      return '<label class="check" for="f-' + t.key + '"><input type="checkbox" id="f-' + t.key + '" name="' + t.key + '"' + (s[t.key] ? ' checked' : '') + '> ' + esc(t.label) + '</label>';
    }).join('') + '</fieldset>';

    appEl.innerHTML =
      '<div class="page-head"><p class="eyebrow">Explore</p>' +
      '<h1 tabindex="-1">Microsoft cloud evidence sources</h1>' +
      '<p class="lede">' + esc(SITE.tagline) + '</p></div>' +
      '<div class="readiness-banner"><div><strong>' + esc(P.readiness.headline) + '</strong>' +
      '<p>Check whether the evidence was generated, configured, routed, retained, and reachable before drawing a conclusion.</p></div>' +
      '<a href="#/readiness">Readiness questions and legend</a></div>' +
      '<div class="explore">' +
      '<aside class="filters" aria-label="Filters"><details id="filters-panel"><summary>Filters <span class="count" id="filter-count"></span></summary>' +
      '<form id="filter-form" role="search" novalidate>' +
      '<div class="field"><label for="f-q">Search</label><input type="search" id="f-q" name="q" value="' + esc(s.q) + '" autocomplete="off" spellcheck="false" aria-describedby="hint-q">' +
      '<p class="field-hint" id="hint-q">Matches names, descriptions, tables, cmdlets, and relevance. All words must match.</p></div>' +
      selects + toggles +
      '<div><button type="button" class="button" id="reset-filters">Clear all filters</button></div>' +
      '</form></details></aside>' +
      '<section class="results" aria-labelledby="results-title"><h2 id="results-title" class="visually-hidden">Results</h2>' +
      '<div class="results-head"><p id="results-status" role="status"></p>' +
      '<div class="field"><label for="f-group">Group by</label><select id="f-group" name="group">' +
      GROUPS.map(function (g) { return '<option value="' + g[0] + '"' + (s.group === g[0] ? ' selected' : '') + '>' + esc(g[1]) + '</option>'; }).join('') +
      '</select></div></div>' +
      '<ul class="active-filters" id="active-filters" aria-label="Active filters"></ul>' +
      '<div id="results"></div></section></div>';

    var panel = document.getElementById('filters-panel');
    var wide = window.matchMedia('(min-width: 60.0625rem)');
    panel.open = wide.matches || activeCount(s) > 0;

    var form = document.getElementById('filter-form');
    form.addEventListener('submit', function (ev) { ev.preventDefault(); });
    form.addEventListener('change', function (ev) {
      var t = ev.target;
      if (t.type === 'checkbox') { exploreState[t.name] = t.checked; }
      else if (t.name && t.name !== 'q') { exploreState[t.name] = t.value; }
      updateResults();
    });
    document.getElementById('f-q').addEventListener('input', function (ev) {
      var value = ev.target.value;
      clearTimeout(searchTimer);
      searchTimer = setTimeout(function () { exploreState.q = value.trim(); updateResults(); }, 160);
    });
    document.getElementById('f-group').addEventListener('change', function (ev) { exploreState.group = ev.target.value; updateResults(); });
    document.getElementById('reset-filters').addEventListener('click', function () {
      var group = exploreState.group;
      exploreState = emptyState();
      exploreState.group = group;
      syncForm();
      updateResults();
      document.getElementById('f-q').focus();
    });
    document.getElementById('active-filters').addEventListener('click', function (ev) {
      var btn = ev.target.closest('button[data-key]');
      if (!btn) { return; }
      var key = btn.getAttribute('data-key');
      exploreState[key] = (key === 'q') ? '' : (TOGGLES.some(function (t) { return t.key === key; }) ? false : '');
      syncForm();
      updateResults();
      var control = document.getElementById(key === 'q' ? 'f-q' : 'f-' + key);
      if (control) { control.focus(); }
    });
    updateResults(true);
  }

  function syncForm() {
    var s = exploreState;
    document.getElementById('f-q').value = s.q;
    FILTERS.forEach(function (f) { document.getElementById('f-' + f.key).value = s[f.key]; });
    TOGGLES.forEach(function (t) { document.getElementById('f-' + t.key).checked = !!s[t.key]; });
    document.getElementById('f-group').value = s.group;
  }

  function updateResults(initial) {
    var s = exploreState;
    var found = sortEntries(ENTRIES.filter(function (e) { return matches(e, s); }));
    var n = activeCount(s);
    var html = '';

    if (s.group === 'plane') {
      P.planes.forEach(function (pl) {
        var items = found.filter(function (e) { return e.evidence_plane === pl.name; });
        if (!items.length && n > 0) { return; }
        html += '<section class="group plane-' + pl.number + '" aria-labelledby="g-plane-' + pl.number + '">' +
          '<div class="group-head"><span class="plane-no" aria-hidden="true">' + pad2(pl.number) + '</span>' +
          '<h2 id="g-plane-' + pl.number + '">' + esc(pl.name) + '</h2>' +
          '<span class="group-count">' + plural(items.length, 'evidence source', 'evidence sources') + '</span></div>' +
          (items.length ? '<div class="cards">' + items.map(function (e) { return entryCard(e, 3); }).join('') + '</div>'
            : '<p class="group-empty">Not yet catalogued in this release.</p>') +
          '</section>';
      });
    } else if (s.group === 'product') {
      PRODUCTS.forEach(function (p) {
        var items = found.filter(function (e) { return e.product_id === p.id; });
        if (!items.length) { return; }
        html += '<section class="group ' + planeClass(p.primary_plane) + '" aria-labelledby="g-prod-' + esc(p.id) + '">' +
          '<div class="group-head"><h2 id="g-prod-' + esc(p.id) + '">' + productLink(p.id) + '</h2>' +
          '<span class="group-count">' + plural(items.length, 'evidence source', 'evidence sources') + '</span></div>' +
          '<div class="cards">' + items.map(function (e) { return entryCard(e, 3); }).join('') + '</div></section>';
      });
    } else {
      html = found.length ? '<div class="cards">' + found.map(function (e) { return entryCard(e, 2); }).join('') + '</div>' : '';
    }
    if (!found.length) {
      html = '<p class="empty">No evidence source matches these filters. Remove a filter or clear them all.</p>';
    }
    document.getElementById('results').innerHTML = html;

    var statusText = n === 0
      ? 'Showing all ' + plural(ENTRIES.length, 'evidence source', 'evidence sources') + '.'
      : 'Showing ' + found.length + ' of ' + plural(ENTRIES.length, 'evidence source', 'evidence sources') + '.';
    var statusEl = document.getElementById('results-status');
    if (statusEl.textContent !== statusText) { statusEl.textContent = statusText; }
    document.getElementById('filter-count').textContent = n ? n + ' active' : '';

    var chipsHtml = '';
    if (s.q) { chipsHtml += activeChip('q', 'Search: ' + s.q); }
    FILTERS.forEach(function (f) {
      if (s[f.key]) { chipsHtml += activeChip(f.key, f.label + ': ' + (f.chip ? f.chip(s[f.key]) : s[f.key])); }
    });
    TOGGLES.forEach(function (t) { if (s[t.key]) { chipsHtml += activeChip(t.key, t.label); } });
    var af = document.getElementById('active-filters');
    af.innerHTML = chipsHtml;
    af.hidden = !chipsHtml;

    var target = '#/' + stateToQuery(s);
    if (location.hash !== target && !(initial && location.hash === '' && target === '#/')) {
      history.replaceState(null, '', target);
    }
  }
  function activeChip(key, label) {
    return '<li><button type="button" data-key="' + esc(key) + '" aria-label="Remove filter ' + esc(label) + '">' + esc(label) + ' <span aria-hidden="true">✕</span></button></li>';
  }

  // ---------------------------------------------------------------- entry detail
  var SECTIONS = [
    ['about', 'About the product'],
    ['records', 'What it records'],
    ['availability', 'Availability and prerequisites'],
    ['where', 'Where to investigate'],
    ['preservation', 'Preservation and retention'],
    ['tables', 'Log Analytics tables'],
    ['relevance', 'Investigation relevance'],
    ['permissions', 'Roles and permissions'],
    ['powershell', 'PowerShell acquisition'],
    ['api', 'API acquisition'],
    ['kql', 'Example KQL'],
    ['limitations', 'Limitations'],
    ['related', 'Related evidence'],
    ['verification', 'Verification'],
    ['references', 'Official Microsoft references']
  ];

  function entrySourceIds(e) {
    var ids = [e.evidence_doc_source_id];
    var p = productById.get(e.product_id);
    if (p) { ids.push(p.what_is_source_id); }
    ids = ids.concat(e.verification.source_ids, e.api.source_ids);
    e.log_analytics_tables.forEach(function (t) { ids = ids.concat(t.source_ids); });
    e.required_permissions.forEach(function (x) { ids = ids.concat(x.source_ids); });
    e.powershell.commands.forEach(function (c) { ids = ids.concat(c.source_ids); });
    e.kql_examples.forEach(function (k) { ids = ids.concat(k.source_ids); });
    RELS.forEach(function (r) { if (r.from === e.id || r.to === e.id) { ids = ids.concat(r.source_ids); } });
    return uniq(ids.filter(Boolean));
  }

  function relItem(r) {
    return '<li class="rel"><div class="rel-line">' + entryLink(r.from) + ' <span class="rel-type">' + esc(r.type) + '</span> ' + entryLink(r.to) +
      unverifiedMark(r.verified) + '</div><p>' + esc(r.description) + '</p>' +
      (r.pivot_on && r.pivot_on.length ? '<ul class="pivot-on" aria-label="Pivot on">' + r.pivot_on.map(function (x) { return '<li>' + vr(x) + '</li>'; }).join('') + '</ul>' : '') +
      '<p class="ref-meta">' + srcLinks(r.source_ids) + '</p></li>';
  }

  function commandHtml(e, c, i) {
    var path = commandPath(e, i);
    var pathObj = path ? pathByNumber.get(Number(path)) : null;
    var changes = c.role === 'Changes configuration';
    return '<div class="cmd' + (changes ? ' changes-config' : '') + '">' +
      '<div class="cmd-head"><span class="cmd-name">' + esc(c.command) + '</span>' + roleTagHtml(c.role) + apiStatus(c.api_status) +
      (pathObj ? '<span class="muted">Path ' + pathObj.number + ': <a href="#/acquisition?section=path-' + pathObj.number + '">' + esc(pathObj.name) + '</a></span>' : '') +
      unverifiedMark(c.verified) + '</div>' +
      (changes ? '<p><strong>Changes configuration.</strong> Not an acquisition step; it affects collection from now on, not past evidence.</p>' : '') +
      '<p>' + esc(c.purpose) + '</p>' +
      codeBlock(c.example, c.command + ' example') +
      '<p class="meta"><strong>Interface:</strong> ' + esc(c.interface) + '</p>' +
      '<p class="meta"><strong>Paging and limits:</strong> ' + vr(c.pagination) + '</p>' +
      (c.notes ? '<p class="meta"><strong>Notes:</strong> ' + esc(c.notes) + '</p>' : '') +
      '<p class="meta">' + srcLinks(c.source_ids) + '</p></div>';
  }

  function entryBody(e, opts) {
    opts = opts || {};
    var L = opts.level || 2;
    var idp = e.id + '--';
    var p = productById.get(e.product_id) || {};
    var out = [];
    function section(key, title, body) {
      if (!body) { return; }
      // On the print view many entries share section titles, so sections there are not named landmarks.
      var named = opts.print ? '' : ' aria-labelledby="' + idp + key + '-h"';
      out.push('<section class="section" id="' + idp + key + '"' + named + '>' +
        hTag(L, esc(title), ' id="' + idp + key + '-h"') + body + '</section>');
    }

    section('about', 'About the product',
      '<div class="product-box"><p><strong>' + productLink(e.product_id) + '.</strong> ' + esc(p.summary) + '</p>' +
      '<p>' + srcLink(p.what_is_source_id, p.learn_label) + '</p>' +
      (p.notes ? '<p class="muted">' + esc(p.notes) + '</p>' : '') + '</div>');

    section('records', 'What it records',
      '<p class="prose">' + esc(e.description) + '</p>' +
      '<p class="ref-meta">' + srcLink(e.evidence_doc_source_id) + '</p>' +
      (e.notes ? '<p class="prose muted">' + esc(e.notes) + '</p>' : ''));

    section('availability', 'Availability and prerequisites',
      '<dl class="kv">' +
      '<dt>Availability</dt><dd>' + esc(e.availability) + '</dd>' +
      '<dt>Legend codes</dt><dd><ul>' + e.availability_flags.map(function (f) {
        return '<li>' + chips([f]) + ' ' + esc(flagMeaning[f] || '') + '</li>';
      }).join('') + '</ul></dd>' +
      '<dt>Configuration required</dt><dd>' + (e.configuration_required ? 'Yes' : 'No') + (e.configuration_notes ? '. ' + esc(e.configuration_notes) : '') + '</dd>' +
      '<dt>Licensing dependency</dt><dd>' + (e.licensing_dependency ? esc(e.licensing_dependency) : 'None documented') + '</dd>' +
      '<dt>Deployment dependency</dt><dd>' + (e.deployment_dependency ? esc(e.deployment_dependency) : 'None documented') + '</dd>' +
      '</dl>');

    section('where', 'Where to investigate',
      '<dl class="kv"><dt>Where</dt><dd>' + esc(e.where_to_investigate) + '</dd>' +
      (e.portal_path ? '<dt>Portal path</dt><dd>' + esc(e.portal_path) + '</dd>' : '') + '</dl>');

    var dests = Array.from(entryDestinations(e)).map(function (id) { return destinations.find(function (d) { return d.id === id; }).label; });
    section('preservation', 'Preservation and retention',
      '<dl class="kv">' +
      '<dt>Native retention</dt><dd>' + vr(e.native_retention) + '</dd>' +
      (e.retention_notes ? '<dt>Retention notes</dt><dd>' + esc(e.retention_notes) + '</dd>' : '') +
      '<dt>Diagnostic setting applies</dt><dd>' + (e.diagnostic_setting_applicable ? 'Yes' : 'No') + '</dd>' +
      '<dt>Preservation options</dt><dd>' + (list(e.preservation_options) || 'None documented') + '</dd>' +
      (dests.length ? '<dt>Destinations</dt><dd>' + esc(dests.join(', ')) + '</dd>' : '') +
      '</dl>');

    var tables = e.log_analytics_tables;
    section('tables', 'Log Analytics tables',
      '<p><strong>Mode:</strong> ' + vr(e.log_analytics_mode) + '</p>' +
      (tables.length ? '<div class="table-wrap"><table><thead><tr><th scope="col">Table</th><th scope="col">Mode</th><th scope="col">Notes</th></tr></thead><tbody>' +
        tables.map(function (t) {
          return '<tr><th scope="row"><code>' + esc(t.table) + '</code>' + unverifiedMark(t.verified) + '</th><td>' + esc(t.mode) + '</td><td>' +
            (t.notes ? esc(t.notes) : '') + (t.source_ids.length ? '<span class="ref-meta">' + srcLinks(t.source_ids) + '</span>' : '') + '</td></tr>';
        }).join('') + '</tbody></table></div>'
        : '<p class="muted">No Log Analytics table is documented for this evidence source.</p>'));

    section('relevance', 'Investigation relevance',
      list(e.investigation_relevance) +
      '<p><span class="muted">Tags:</span> ' + e.relevance_tags.map(function (t) {
        return '<a href="#/?relevance=' + encodeURIComponent(t) + '">' + esc(t) + '</a>';
      }).join(', ') + '</p>');

    section('permissions', 'Roles and permissions',
      e.required_permissions.length
        ? '<div class="table-wrap"><table><thead><tr><th scope="col">Context</th><th scope="col">Role or permission</th><th scope="col">Source</th></tr></thead><tbody>' +
          e.required_permissions.map(function (x) {
            return '<tr><td>' + esc(x.context) + '</td><td>' + esc(x.value) + unverifiedMark(x.verified) + '</td><td>' + (srcLinks(x.source_ids) || '') + '</td></tr>';
          }).join('') + '</tbody></table></div>'
        : '<p class="muted">No permission is documented for this evidence source.</p>');

    var ps = e.powershell;
    section('powershell', 'PowerShell acquisition',
      '<dl class="kv"><dt>Method</dt><dd>' + esc(ps.acquisition_type) + '</dd>' +
      (ps.modules.length ? '<dt>Modules or interfaces</dt><dd>' + ps.modules.map(function (m) { return '<code>' + esc(m) + '</code>'; }).join(', ') + '</dd>' : '') +
      '<dt>Output formats</dt><dd><span class="chips">' + e.output_formats.map(function (f) { return '<span class="chip chip-fmt">' + esc(f) + '</span>'; }).join('') + '</span></dd>' +
      '</dl>' +
      '<p class="muted">' + esc(P.acquisition_warning) + '</p>' +
      (ps.commands.length ? ps.commands.map(function (c, i) { return commandHtml(e, c, i); }).join('') : '<p>No documented PowerShell method.</p>'));

    var api = e.api;
    section('api', 'API acquisition',
      api.supported
        ? '<dl class="kv"><dt>API</dt><dd>' + esc(api.name) + ' ' + apiStatus(api.status) + '</dd>' +
          (api.endpoint ? '<dt>Endpoint</dt><dd>' + codeBlock(api.endpoint, (api.name || 'API') + ' endpoint') + '</dd>' : '') +
          (api.notes ? '<dt>Notes</dt><dd>' + esc(api.notes) + '</dd>' : '') +
          '</dl><p class="ref-meta">' + srcLinks(api.source_ids) + '</p>'
        : '<p>No documented API for this evidence source.' + (api.notes ? ' ' + esc(api.notes) : '') + '</p>');

    section('kql', 'Example KQL',
      e.kql_examples.length
        ? e.kql_examples.map(function (k) {
          return '<div class="cmd"><div class="cmd-head"><strong>' + esc(k.title) + '</strong>' + unverifiedMark(k.verified) + '</div>' +
            codeBlock(k.query, k.title) +
            (k.tables.length ? '<p class="meta"><strong>Tables:</strong> ' + k.tables.map(function (t) { return '<code>' + esc(t) + '</code>'; }).join(', ') + '</p>' : '') +
            '<p class="meta">' + srcLinks(k.source_ids) + '</p></div>';
        }).join('')
        : '<p class="muted">No example query in this release.</p>');

    section('limitations', 'Limitations', e.limitations.length ? list(e.limitations) : '<p class="muted">None documented.</p>');

    var out1 = RELS.filter(function (r) { return r.from === e.id; });
    var in1 = RELS.filter(function (r) { return r.to === e.id; });
    section('related', 'Related evidence',
      '<p class="muted">Pivots say where to look next and on which fields. They never assert that one event caused another.</p>' +
      (out1.length ? hTag(L + 1, 'From this evidence source', ' class="sub"') + '<ul class="rel-list">' + out1.map(relItem).join('') + '</ul>' : '') +
      (in1.length ? hTag(L + 1, 'Into this evidence source', ' class="sub"') + '<ul class="rel-list">' + in1.map(relItem).join('') + '</ul>' : '') +
      (!out1.length && !in1.length ? '<p>No pivot is catalogued yet.</p>' : ''));

    var v = e.verification;
    section('verification', 'Verification',
      '<dl class="kv"><dt>Status</dt><dd>' + statusBadge(e) + ' ' + esc((statusInfo.get(v.status) || {}).meaning || '') + '</dd>' +
      '<dt>Last verified</dt><dd><time datetime="' + esc(v.last_verified) + '">' + esc(v.last_verified) + '</time></dd>' +
      '<dt>Open gaps</dt><dd>' + (v.gaps.length ? list(v.gaps) : 'None') + '</dd>' +
      '<dt>Priority</dt><dd>' + esc(e.priority) + ' (Poster 1: ' + (e.publication.poster_1 ? 'yes' : 'no') + '; Poster 2: ' + (e.publication.poster_2 ? 'yes' : 'no') + ')</dd>' +
      '</dl>');

    var refs = entrySourceIds(e).map(function (id) { return sourceById.get(id); }).filter(Boolean);
    section('references', 'Official Microsoft references',
      '<ul class="refs">' + refs.map(refItem).join('') + '</ul>');

    return out.join('');
  }

  function refItem(s) {
    return '<li>' + srcLink(s.id) + '<span class="ref-meta">' + esc(s.doc_type) + ' · ' + esc(s.verification_method) +
      ' · checked <time datetime="' + esc(s.verified_date) + '">' + esc(s.verified_date) + '</time></span>' +
      '<span class="ref-url">' + esc(s.url) + '</span></li>';
  }

  function entryHead(e, level, headingId) {
    var p = productById.get(e.product_id) || {};
    var attrs = (level === 1 ? ' tabindex="-1"' : '') + (headingId ? ' id="' + esc(headingId) + '"' : '');
    return '<div class="detail-head ' + planeClass(e.evidence_plane) + '">' +
      planeTag(e.evidence_plane) +
      hTag(level, esc(e.evidence_source), attrs) +
      '<p class="product-line">' + productLink(e.product_id, p.name) + ' · ' + esc(e.evidence_type) + '</p>' +
      '<div class="badges">' + statusBadge(e) + chips(e.availability_flags) + '<span class="prio' + (e.priority === 'Core' ? ' prio-core' : '') + '">' + esc(e.priority) + '</span></div>' +
      '</div>' +
      (e.replaced_by ? '<p class="banner"><strong>Retiring or replaced.</strong> Use ' + entryLink(e.replaced_by) + ' for new collection. Existing data stays subject to its configured retention.</p>' : '');
  }

  function glance(e) {
    var p = productById.get(e.product_id) || {};
    var paths = Array.from(entryPaths(e)).map(function (x) { return x === 'none' ? 'No PowerShell method' : 'Path ' + x + ': ' + pathByNumber.get(Number(x)).name; });
    return '<dl class="glance">' +
      '<div><dt>Product</dt><dd>' + productLink(e.product_id, p.name) + '</dd></div>' +
      '<div><dt>Evidence type</dt><dd>' + esc(e.evidence_type) + '</dd></div>' +
      '<div><dt>Availability</dt><dd>' + esc(e.availability) + '</dd></div>' +
      '<div><dt>Configuration required</dt><dd>' + (e.configuration_required ? 'Yes' : 'No') + '</dd></div>' +
      '<div><dt>Native retention</dt><dd>' + vr(e.native_retention) + '</dd></div>' +
      '<div><dt>Log Analytics</dt><dd>' + vr(e.log_analytics_mode) + '</dd></div>' +
      '<div><dt>PowerShell</dt><dd>' + esc(e.powershell.acquisition_type) + '</dd></div>' +
      '<div><dt>Acquisition path</dt><dd>' + esc(paths.join('; ')) + '</dd></div>' +
      '<div><dt>Last verified</dt><dd>' + esc(e.verification.last_verified) + '</dd></div>' +
      '</dl>';
  }

  function renderEntry(id, params) {
    var e = entryById.get(id);
    if (!e) { return renderNotFound('No evidence source has the id "' + id + '".'); }
    var toc = '<nav class="toc" aria-label="On this page"><h2>On this page</h2><ul>' + SECTIONS.map(function (s) {
      return '<li><a href="#/entry/' + esc(e.id) + '?section=' + s[0] + '" data-scroll="' + esc(e.id) + '--' + s[0] + '">' + esc(s[1]) + '</a></li>';
    }).join('') + '</ul></nav>';
    appEl.innerHTML =
      '<p class="breadcrumb"><a href="#/">Explore</a> / <a href="#/?plane=' + encodeURIComponent(e.evidence_plane) + '">' + esc(e.evidence_plane) + '</a></p>' +
      entryHead(e, 1) +
      '<div class="detail"><div>' + glance(e) + entryBody(e, { level: 2 }) + '</div>' + toc + '</div>';
    setTitle(e.evidence_source + ' (' + ((productById.get(e.product_id) || {}).short_name || e.product_id) + ')');
    var section = params.get('section');
    if (section) {
      var target = document.getElementById(e.id + '--' + section);
      if (target) { return { scrollTo: target }; }
    }
    return null;
  }

  // ---------------------------------------------------------------- products
  function renderProducts() {
    var sorted = PRODUCTS.slice().sort(function (a, b) {
      return planeOf(a.primary_plane).number - planeOf(b.primary_plane).number || a.name.localeCompare(b.name);
    });
    appEl.innerHTML =
      '<div class="page-head"><p class="eyebrow">Products</p><h1 tabindex="-1">Microsoft products in the catalog</h1>' +
      '<p class="lede">What each product is, according to its Microsoft Learn overview, and which of its evidence sources the catalog covers.</p></div>' +
      '<div class="product-cards">' + sorted.map(function (p) {
        var items = sortEntries(ENTRIES.filter(function (e) { return e.product_id === p.id; }));
        return '<article class="product-card ' + planeClass(p.primary_plane) + '">' + planeTag(p.primary_plane) +
          '<h2><a href="#/product/' + esc(p.id) + '">' + esc(p.name) + '</a></h2>' +
          '<p>' + esc(p.summary) + '</p>' +
          '<p><span class="muted">Evidence sources:</span> ' + (items.length ? items.map(function (e) { return entryLink(e.id); }).join(', ') : 'none yet') + '</p>' +
          '<div class="foot">' + srcLink(p.what_is_source_id, p.learn_label) + (p.status !== 'Current' ? '<span>Status: ' + esc(p.status) + '</span>' : '') + '</div>' +
          '</article>';
      }).join('') + '</div>';
    setTitle('Products');
  }

  function renderProduct(id) {
    var p = productById.get(id);
    if (!p) { return renderNotFound('No product has the id "' + id + '".'); }
    var items = sortEntries(ENTRIES.filter(function (e) { return e.product_id === id; }));
    var ids = items.map(function (e) { return e.id; });
    var rels = RELS.filter(function (r) { return ids.indexOf(r.from) !== -1 || ids.indexOf(r.to) !== -1; });
    appEl.innerHTML =
      '<p class="breadcrumb"><a href="#/products">Products</a></p>' +
      '<div class="detail-head ' + planeClass(p.primary_plane) + '">' + planeTag(p.primary_plane) +
      '<h1 tabindex="-1">' + esc(p.name) + '</h1>' +
      '<p class="product-line">' + plural(items.length, 'evidence source', 'evidence sources') + ' in this release' + (p.status !== 'Current' ? ' · ' + esc(p.status) : '') + '</p></div>' +
      '<section class="section" aria-labelledby="p-what"><h2 id="p-what">What it is</h2><div class="product-box"><p>' + esc(p.summary) + '</p>' +
      '<p>' + srcLink(p.what_is_source_id, p.learn_label) + '</p>' + (p.notes ? '<p class="muted">' + esc(p.notes) + '</p>' : '') + '</div></section>' +
      '<section class="section" aria-labelledby="p-ev"><h2 id="p-ev">Evidence sources</h2>' +
      (items.length ? '<div class="cards">' + items.map(function (e) { return entryCard(e, 3); }).join('') + '</div>' : '<p>None catalogued yet.</p>') + '</section>' +
      (rels.length ? '<section class="section" aria-labelledby="p-rel"><h2 id="p-rel">Pivots to and from this product’s evidence</h2><ul class="rel-list">' + rels.map(relItem).join('') + '</ul></section>' : '');
    setTitle(p.name);
  }

  // ---------------------------------------------------------------- acquisition
  function renderAcquisition(params) {
    var byPath = new Map();
    P.acquisition_paths.forEach(function (p) { byPath.set(p.number, []); });
    var noMethod = [];
    sortEntries(ENTRIES).forEach(function (e) {
      if (!e.powershell.supported || !e.powershell.commands.length) { noMethod.push(e); return; }
      e.powershell.commands.forEach(function (c, i) {
        var path = commandPath(e, i);
        if (path && byPath.has(Number(path))) { byPath.get(Number(path)).push({ e: e, c: c }); }
      });
    });
    var paths = P.acquisition_paths.map(function (p) {
      var rows = byPath.get(p.number);
      return '<section class="path section" id="path-' + p.number + '" aria-labelledby="path-' + p.number + '-h">' +
        '<div class="path-head"><h2 id="path-' + p.number + '-h"><span class="no" aria-hidden="true">' + p.number + '</span>' + esc(p.name) + '</h2><p>' + esc(p.description) + '</p></div>' +
        (rows.length ? '<div class="table-wrap"><table><caption class="visually-hidden">Commands for ' + esc(p.name) + '</caption><thead><tr>' +
          '<th scope="col">Command</th><th scope="col">Role</th><th scope="col">Evidence source</th><th scope="col">Purpose</th><th scope="col">Status</th></tr></thead><tbody>' +
          rows.map(function (r) {
            return '<tr><th scope="row"><code>' + esc(r.c.command) + '</code></th><td>' + roleTagHtml(r.c.role) + '</td><td>' + entryLink(r.e.id) +
              '</td><td>' + esc(r.c.purpose) + unverifiedMark(r.c.verified) + '</td><td>' + apiStatus(r.c.api_status) + '</td></tr>';
          }).join('') + '</tbody></table></div>' : '<p class="muted">No command in this release.</p>') +
        '</section>';
    }).join('');
    appEl.innerHTML =
      '<div class="page-head"><p class="eyebrow">Acquisition</p><h1 tabindex="-1">' + esc(P.posters.poster_2.subtitle) + '</h1>' +
      '<p class="lede">' + esc(P.posters.poster_2.question) + ' Open an evidence source for full examples, paging limits, and permissions.</p></div>' +
      '<div class="panel warning" role="note"><p><strong>' + esc(P.acquisition_warning) + '</strong></p></div>' +
      '<div class="stack-top">' + paths + '</div>' +
      (noMethod.length ? '<section class="section" aria-labelledby="nomethod-h"><h2 id="nomethod-h">No documented PowerShell method</h2><ul>' +
        noMethod.map(function (e) { return '<li>' + entryLink(e.id) + '</li>'; }).join('') + '</ul></section>' : '') +
      '<div class="panel-grid">' +
      '<section class="panel" aria-labelledby="rec-h"><h2 id="rec-h">Record for every acquisition</h2><ul>' + P.acquisition_record.map(function (x) { return '<li>' + esc(x) + '</li>'; }).join('') + '</ul></section>' +
      '<section class="panel" aria-labelledby="fmt-h"><h2 id="fmt-h">Output formats</h2><dl class="legend">' + P.output_guidance.map(function (o) {
        return '<div><dt><span class="chip chip-fmt">' + esc(o.format) + '</span></dt><dd>' + esc(o.use) + '</dd></div>';
      }).join('') + '</dl><p class="spaced-sm">' + esc(P.chain_of_custody_note) + '</p></section>' +
      '<section class="panel" aria-labelledby="roles-h"><h2 id="roles-h">Command roles</h2><dl class="legend">' + P.command_roles.map(function (r) {
        return '<div><dt>' + roleTagHtml(r.role) + '</dt><dd>' + esc(r.role) + '</dd></div>';
      }).join('') + '</dl></section>' +
      '</div>';
    setTitle('Acquisition');
    var section = params.get('section');
    if (section) { var t = document.getElementById(section); if (t) { return { scrollTo: t }; } }
    return null;
  }

  // ---------------------------------------------------------------- tables
  function renderTables() {
    var byTable = new Map();
    ENTRIES.forEach(function (e) {
      e.log_analytics_tables.forEach(function (t) {
        if (!byTable.has(t.table)) { byTable.set(t.table, []); }
        byTable.get(t.table).push({ e: e, t: t });
      });
    });
    var names = Array.from(byTable.keys()).sort(function (a, b) { return a.localeCompare(b); });
    var modeCounts = {};
    ENTRIES.forEach(function (e) { modeCounts[e.log_analytics_mode] = (modeCounts[e.log_analytics_mode] || 0) + 1; });
    var mixed = ENTRIES.filter(function (e) { return e.log_analytics_mode === 'AzureDiagnostics or resource-specific'; });
    var termNotes = P.terminology_notes.filter(function (n) { return /AzureDiagnostics|Resource Logs|Diagnostic settings/i.test(n); });

    appEl.innerHTML =
      '<div class="page-head"><p class="eyebrow">Log Analytics tables</p><h1 tabindex="-1">Where collected evidence lands in Log Analytics</h1>' +
      '<p class="lede">Tables are documented per evidence source. A table only holds data that was routed to the workspace while collection was configured.</p></div>' +
      '<div class="panel-grid">' +
      '<section class="panel" aria-labelledby="t-rules"><h2 id="t-rules">Read this first</h2>' + list(termNotes) + '</section>' +
      '<section class="panel" aria-labelledby="t-modes"><h2 id="t-modes">Collection modes in this release</h2><dl class="legend">' +
      Object.keys(modeCounts).sort().map(function (m) { return '<div><dt>' + plural(modeCounts[m], 'source', 'sources') + '</dt><dd>' + esc(m) + '</dd></div>'; }).join('') +
      '</dl>' + (mixed.length ? '<p>The diagnostic setting decides between <code>AzureDiagnostics</code> and resource-specific tables for: ' +
        mixed.map(function (e) { return entryLink(e.id); }).join(', ') + '.</p>' : '') + '</section>' +
      '<section class="panel" aria-labelledby="t-more"><h2 id="t-more">Every Resource Log category</h2><p>This site does not list every Azure service’s Resource Log categories. Use the official catalogs:</p><ul>' +
      '<li>' + srcLink('src-resource-logs-categories') + '</li><li>' + srcLink('src-la-tables-category') + '</li></ul></section>' +
      '</div>' +
      '<section class="section" aria-labelledby="t-list"><h2 id="t-list">Tables referenced by the catalog</h2>' +
      '<div class="table-wrap"><table><thead><tr><th scope="col">Table</th><th scope="col">Mode</th><th scope="col">Evidence sources and notes</th></tr></thead><tbody>' +
      names.map(function (name) {
        var rows = byTable.get(name);
        var modes = uniq(rows.map(function (r) { return r.t.mode; }));
        var allVerified = rows.every(function (r) { return r.t.verified; });
        return '<tr><th scope="row"><code>' + esc(name) + '</code>' + unverifiedMark(allVerified) + '</th><td>' + esc(modes.join('; ')) + '</td><td><ul>' +
          rows.map(function (r) { return '<li>' + entryLink(r.e.id) + (r.t.notes ? ': ' + esc(r.t.notes) : '') + '</li>'; }).join('') + '</ul></td></tr>';
      }).join('') + '</tbody></table></div></section>';
    setTitle('Log Analytics tables');
  }

  // ---------------------------------------------------------------- pivots
  function renderPivots() {
    var types = uniq(RELS.map(function (r) { return r.type; }));
    appEl.innerHTML =
      '<div class="page-head"><p class="eyebrow">Pivots</p><h1 tabindex="-1">Where to look next</h1>' +
      '<p class="lede">' + esc(D.relationships.notes) + '</p></div>' +
      types.map(function (t) {
        var rs = RELS.filter(function (r) { return r.type === t; });
        return '<section class="section" aria-labelledby="pv-' + slug(t) + '"><h2 id="pv-' + slug(t) + '">' + esc(t) + ' <span class="muted">(' + rs.length + ')</span></h2>' +
          '<ul class="rel-list">' + rs.map(relItem).join('') + '</ul></section>';
      }).join('');
    setTitle('Pivots');
  }

  // ---------------------------------------------------------------- readiness and legend
  function readinessPanels() {
    return '<div class="panel-grid">' +
      '<section class="panel alert" aria-labelledby="r-head"><h2 id="r-head">' + esc(P.readiness.headline) + '</h2><p>' + esc(P.readiness.intro) + '</p><ol>' +
      P.readiness.questions.map(function (q) { return '<li>' + esc(q) + '</li>'; }).join('') + '</ol></section>' +
      '<section class="panel" aria-labelledby="r-avail"><h2 id="r-avail">Availability legend</h2><dl class="legend">' + P.availability_legend.map(function (a) {
        return '<div><dt>' + chips([a.code]) + '</dt><dd>' + esc(a.meaning) + '</dd></div>';
      }).join('') + '</dl></section>' +
      '<section class="panel" aria-labelledby="r-ver"><h2 id="r-ver">Verification status</h2><dl class="legend">' + P.verification_legend.map(function (v) {
        return '<div><dt><span class="status status-' + statusClass(v.status) + '"><span aria-hidden="true">' + esc(v.symbol) + '</span> ' + esc(v.status) + '</span></dt><dd>' + esc(v.meaning) + '</dd></div>';
      }).join('') + '</dl></section>' +
      '</div>';
  }

  function renderReadiness() {
    var m = D.meta;
    appEl.innerHTML =
      '<div class="page-head"><p class="eyebrow">Readiness and legend</p><h1 tabindex="-1">Forensic readiness and how to read this guide</h1>' +
      '<p class="lede">' + esc(SITE.tagline) + '</p></div>' +
      readinessPanels() +
      '<div class="panel-grid spaced">' +
      '<section class="panel" aria-labelledby="r-term"><h2 id="r-term">Terminology rules</h2>' + list(P.terminology_notes) + '</section>' +
      '<section class="panel" aria-labelledby="r-planes"><h2 id="r-planes">Evidence planes</h2><ul class="plane-list">' + P.planes.map(function (pl) {
        var n = ENTRIES.filter(function (e) { return e.evidence_plane === pl.name; }).length;
        return '<li class="plane-' + pl.number + '"><span class="plane-no" aria-hidden="true">' + pad2(pl.number) + '</span>' +
          '<a href="#/?plane=' + encodeURIComponent(pl.name) + '">' + esc(pl.name) + '</a><span class="muted">' + (n ? n : 'not yet catalogued') + '</span></li>';
      }).join('') + '</ul></section>' +
      '<section class="panel" aria-labelledby="r-method"><h2 id="r-method">How the data is kept honest</h2>' +
      '<p>One catalog drives both posters and this site. Each entry is checked against official Microsoft documentation, and anything that could not be confirmed is marked <span class="vr">Verification required</span> instead of guessed.</p>' +
      '<p>Each reference records how its URL was confirmed (fetched page or official search result) and when.</p>' +
      (m.bundle
        ? '<p>This single-file copy embeds the full catalog. The JSON data files are in the data folder of the project repository.</p>'
        : '<p><strong>Download the data:</strong> <a href="data/evidence-catalog.json">evidence catalog</a>, <a href="data/products.json">products</a>, ' +
          '<a href="data/relationships.json">relationships</a>, <a href="data/sources.json">Microsoft references</a>, <a href="data/presentation.json">legends and labels</a> (JSON).</p>' +
          '<p><strong>Offline copy:</strong> <a href="microsoft-cloud-audit-logs-guide-offline.html">the whole guide as one HTML file</a> for workstations without network access.</p>') +
      '<p class="muted">' + esc(m.catalog_phase) + ' · schema ' + esc(m.schema_version) + ' · last verified ' + esc(m.last_verified) + '</p></section>' +
      '</div>';
    setTitle('Readiness and legend');
  }

  // ---------------------------------------------------------------- references
  function renderReferences() {
    var cites = new Map();
    function cite(id, label) { if (!cites.has(id)) { cites.set(id, new Set()); } cites.get(id).add(label); }
    ENTRIES.forEach(function (e) { entrySourceIds(e).forEach(function (id) { cite(id, e.id); }); });
    var types = uniq(SOURCES.map(function (s) { return s.doc_type; })).sort();
    appEl.innerHTML =
      '<div class="page-head"><p class="eyebrow">References</p><h1 tabindex="-1">Official Microsoft references</h1>' +
      '<p class="lede">' + plural(SOURCES.length, 'Microsoft Learn page', 'Microsoft Learn pages') + ' back the catalog. Every link on this site comes from this list.</p></div>' +
      '<div class="field ref-filter"><label for="ref-q">Filter references</label><input type="search" id="ref-q" autocomplete="off" spellcheck="false"></div>' +
      '<p id="ref-status" role="status" class="muted"></p>' +
      types.map(function (t) {
        var items = SOURCES.filter(function (s) { return s.doc_type === t; }).sort(function (a, b) { return a.title.localeCompare(b.title); });
        return '<section class="section ref-group" aria-labelledby="ref-' + slug(t) + '"><h2 id="ref-' + slug(t) + '">' + esc(t) + ' <span class="muted">(' + items.length + ')</span></h2><ul class="refs">' +
          items.map(function (s) {
            var by = Array.from(cites.get(s.id) || []).map(entryLink);
            return '<li data-text="' + esc((s.title + ' ' + s.url + ' ' + s.doc_type).toLowerCase()) + '">' + srcLink(s.id) +
              '<span class="ref-meta">' + esc(s.verification_method) + ' · checked ' + esc(s.verified_date) + (by.length ? ' · cited by ' + by.join(', ') : '') + '</span>' +
              '<span class="ref-url">' + esc(s.url) + '</span></li>';
          }).join('') + '</ul></section>';
      }).join('');
    var input = document.getElementById('ref-q');
    var status = document.getElementById('ref-status');
    input.addEventListener('input', function () {
      var terms = input.value.toLowerCase().split(/\s+/).filter(Boolean);
      var shown = 0;
      appEl.querySelectorAll('.refs li[data-text]').forEach(function (li) {
        var text = li.getAttribute('data-text');
        var ok = terms.every(function (t) { return text.indexOf(t) !== -1; });
        li.hidden = !ok;
        if (ok) { shown++; }
      });
      appEl.querySelectorAll('.ref-group').forEach(function (g) { g.hidden = !g.querySelector('li:not([hidden])'); });
      status.textContent = terms.length ? 'Showing ' + shown + ' of ' + SOURCES.length + ' references.' : '';
    });
    setTitle('References');
  }

  // ---------------------------------------------------------------- print view
  function renderPrint() {
    var list2 = sortEntries(ENTRIES);
    appEl.innerHTML =
      '<div class="page-head"><p class="eyebrow">Print view</p><h1 tabindex="-1">All evidence sources, full detail</h1>' +
      '<p class="print-note">This page holds every evidence source with all its fields, one per printed page. Use your browser’s Print command (Ctrl+P or Cmd+P) to print it or save it as PDF. Navigation, filters, and copy buttons are left out of the printout.</p></div>' +
      readinessPanels() +
      list2.map(function (e) {
        return '<article class="print-entry" aria-labelledby="pe-' + esc(e.id) + '">' +
          entryHead(e, 2, 'pe-' + e.id) +
          glance(e) + entryBody(e, { level: 3, print: true }) + '</article>';
      }).join('');
    setTitle('Print view');
  }

  function renderNotFound(message) {
    appEl.innerHTML = '<div class="page-head"><h1 tabindex="-1">Page not found</h1><p class="lede">' + esc(message || 'This address does not match a page.') +
      '</p><p><a href="#/">Go to Explore</a></p></div>';
    setTitle('Page not found');
    return null;
  }

  // ---------------------------------------------------------------- router
  function setTitle(text) { document.title = text + ' · ' + SITE.title; }
  function setNav(key) {
    document.querySelectorAll('.site-nav a[data-nav]').forEach(function (a) {
      if (a.getAttribute('data-nav') === key) { a.setAttribute('aria-current', 'page'); } else { a.removeAttribute('aria-current'); }
    });
  }

  var firstRender = true;
  function route() {
    var rawFull = location.hash.replace(/^#/, '');
    if (rawFull && rawFull.charAt(0) !== '/') {
      // A bare fragment that names an element on the page (for example #main) is an in-page jump, not a route.
      var el = document.getElementById(decodeURIComponent(rawFull));
      if (el && !appEl.contains(el) || el === document.getElementById('main')) { if (el.focus) { el.focus(); } return; }
    }
    if (rawFull && rawFull.charAt(0) !== '/') { rawFull = '/' + rawFull; }
    var qIndex = rawFull.indexOf('?');
    var path = qIndex === -1 ? rawFull : rawFull.slice(0, qIndex);
    var params = new URLSearchParams(qIndex === -1 ? '' : rawFull.slice(qIndex + 1));
    path = decodeURIComponent(path || '/').replace(/\/+$/, '') || '/';
    var parts = path.split('/').filter(Boolean);
    codeCounter = 0;
    var result = null;
    var nav = 'explore';
    if (!parts.length) { renderExplore(params); setTitle('Explore'); }
    else if (parts[0] === 'entry' && parts[1]) { result = renderEntry(parts[1], params); nav = ''; }
    else if (parts[0] === 'product' && parts[1]) { renderProduct(parts[1]); nav = 'products'; }
    else if (parts[0] === 'products') { renderProducts(); nav = 'products'; }
    else if (parts[0] === 'acquisition') { result = renderAcquisition(params); nav = 'acquisition'; }
    else if (parts[0] === 'tables') { renderTables(); nav = 'tables'; }
    else if (parts[0] === 'pivots') { renderPivots(); nav = 'pivots'; }
    else if (parts[0] === 'readiness') { renderReadiness(); nav = 'readiness'; }
    else if (parts[0] === 'references') { renderReferences(); nav = 'references'; }
    else if (parts[0] === 'print') { renderPrint(); nav = 'print'; }
    else { renderNotFound(); nav = ''; }
    setNav(nav);

    if (result && result.scrollTo) {
      result.scrollTo.scrollIntoView();
      var h = result.scrollTo.querySelector('h2, h3');
      if (h) { h.setAttribute('tabindex', '-1'); h.focus({ preventScroll: true }); }
    } else if (!firstRender) {
      window.scrollTo(0, 0);
      var h1 = appEl.querySelector('h1');
      if (h1) { h1.focus({ preventScroll: true }); }
    }
    firstRender = false;
  }

  // ---------------------------------------------------------------- global events
  document.addEventListener('click', function (ev) {
    var copyBtn = ev.target.closest('button[data-copy]');
    if (copyBtn) {
      var pre = document.getElementById(copyBtn.getAttribute('data-copy'));
      if (!pre) { return; }
      var text = pre.textContent;
      var done = function (ok) {
        copyBtn.textContent = ok ? 'Copied' : 'Selected';
        announce(ok ? 'Copied to the clipboard.' : 'Copy is blocked here. The text is selected; press Ctrl+C or Cmd+C.');
        setTimeout(function () { copyBtn.textContent = 'Copy'; }, 1800);
      };
      var selectText = function () {
        var range = document.createRange();
        range.selectNodeContents(pre);
        var sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        done(false);
      };
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(function () { done(true); }, selectText);
        } else { selectText(); }
      } catch (e) { selectText(); }
      return;
    }
    var scrollLink = ev.target.closest('a[data-scroll]');
    if (scrollLink) {
      var target = document.getElementById(scrollLink.getAttribute('data-scroll'));
      if (target) {
        ev.preventDefault();
        target.scrollIntoView();
        var h = target.querySelector('h2, h3');
        if (h) { h.setAttribute('tabindex', '-1'); h.focus({ preventScroll: true }); }
      }
      return;
    }
    var skip = ev.target.closest('a.skip-link');
    if (skip) {
      ev.preventDefault();
      document.getElementById('main').focus();
    }
  });

  var announcer = document.getElementById('announcer');
  function announce(text) {
    announcer.textContent = '';
    setTimeout(function () { announcer.textContent = text; }, 50);
  }

  // Theme: system (no attribute) -> light -> dark -> system.
  var themeBtn = document.getElementById('theme-toggle');
  function currentTheme() { return document.documentElement.getAttribute('data-theme') || 'system'; }
  function paintThemeButton() {
    var t = currentTheme();
    themeBtn.textContent = 'Theme: ' + t.charAt(0).toUpperCase() + t.slice(1);
    themeBtn.setAttribute('aria-label', 'Theme: ' + t + '. Select to change.');
  }
  themeBtn.addEventListener('click', function () {
    var next = { system: 'light', light: 'dark', dark: 'system' }[currentTheme()];
    if (next === 'system') { document.documentElement.removeAttribute('data-theme'); }
    else { document.documentElement.setAttribute('data-theme', next); }
    try {
      if (next === 'system') { window.localStorage.removeItem('guide-theme'); } else { window.localStorage.setItem('guide-theme', next); }
    } catch (e) { /* storage unavailable: the choice lasts for this page view */ }
    paintThemeButton();
    announce('Theme set to ' + next + '.');
  });
  paintThemeButton();

  // Footer
  document.getElementById('disclaimer').textContent = P.disclaimer + ' Not an official Microsoft publication.';
  document.getElementById('build-info').textContent =
    plural(ENTRIES.length, 'evidence source', 'evidence sources') + ' · ' + plural(SOURCES.length, 'Microsoft reference', 'Microsoft references') +
    ' · catalog last verified ' + D.meta.last_verified + ' · site data built ' + D.meta.generated_utc + ' (UTC)';

  window.addEventListener('hashchange', route);
  route();
})();
