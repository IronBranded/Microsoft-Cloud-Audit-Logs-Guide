# Interactive site specification

The interactive site is the detailed version of both posters. It is a static site in `site/`, published with GitHub Pages, and it shows only what `data/` holds. Nothing on the site is typed in by hand except labels, layout, and behavior.

## Data loading

| File | Produced by | Holds |
|---|---|---|
| `site/data/catalog-data.js` | `scripts/build-site.ps1` | `window.GUIDE_DATA`: the five data files embedded as their original JSON text, plus build metadata (catalog phase, schema version, latest verification date, counts) |
| `site/data/*.json` | `scripts/build-site.ps1` | Copies of the data files, linked as downloads |
| `site/css/planes.css` | `scripts/build-site.ps1` | One class per evidence plane (`.plane-1` to `.plane-14`) with its color from `data/presentation.json` |
| `site/index.html`, `site/js/app.js`, `site/js/theme.js`, `site/css/site.css` | Hand-written | Layout, filters, rendering, and accessibility behavior |

The data loads with a `<script>` tag rather than `fetch()`, so the site also works when `site/index.html` is opened straight from disk. The build output is deterministic.

`build-site.ps1` also writes `site/microsoft-cloud-audit-logs-guide-offline.html`, a single self-contained HTML file with styles, scripts, and data inlined, for isolated analysis workstations. The readiness page links to it.

## Publishing

GitHub Pages serves the `gh-pages` branch ("Deploy from a branch", root folder). `scripts/publish-site.ps1` validates the catalog, rebuilds the site, stops if `site/` has uncommitted changes, and pushes `site/` from `main` to `gh-pages` with `git subtree split`. No GitHub Actions workflow is involved. `site/.nojekyll` turns off Jekyll processing so files are served as committed.

## Security and privacy

- No server, no credentials, no tenant identifiers, no customer data, and no authenticated calls.
- No network requests: system fonts only, no CDN, no analytics. `build-site.ps1` fails if `index.html`, `js/`, or `css/` contain an external URL.
- Content Security Policy (meta tag): `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'`. Inline scripts and inline style attributes are blocked; plane colors therefore come from generated classes rather than `style` attributes.
- `referrer` is `no-referrer`. Outbound links open Microsoft Learn in a new tab with `rel="noopener noreferrer"`.
- Every outbound link is rendered from `data/sources.json` by source id, and `build-site.ps1` fails unless every source URL is an `https://learn.microsoft.com/` page.
- The only browser storage is the theme choice (`localStorage`, key `guide-theme`), wrapped so the site works when storage is blocked.

## Routes

Hash routes, so GitHub Pages needs no rewrite rules. A bare fragment such as `#acquisition` is treated as `#/acquisition`.

| Route | Page |
|---|---|
| `#/` | Explore: search, filters, and evidence cards. Filter state is kept in the address (for example `#/?plane=Identity&ps=1`), so a filtered view can be bookmarked or shared. |
| `#/entry/{id}` | Evidence source detail. `?section={key}` scrolls to a section. |
| `#/products` and `#/product/{id}` | Product index and product detail |
| `#/acquisition` | The six acquisition paths with every command, the acquisition warning, the acquisition record checklist, output formats, and command roles |
| `#/tables` | Every Log Analytics table in the catalog, its collection mode, and the evidence sources that use it, with links to Microsoft's full Resource Log category and table catalogs |
| `#/pivots` | Every relationship, grouped by type |
| `#/readiness` | Readiness questions, availability and verification legends, terminology rules, evidence planes with counts, method, and data downloads |
| `#/references` | Every Microsoft Learn reference with how and when it was verified and which entries cite it, with a text filter |
| `#/print` | Every evidence source in full detail, one per printed page |

## Explore page

Layout: readiness banner, then a filter rail (left on wide screens, a collapsible panel above the results on narrow screens) beside the results.

Filters, each counted against the full catalog in its option label:

| Control | Matches |
|---|---|
| Search | All words must appear in the entry's source name, product, description, investigation relevance, where to investigate, preservation options, limitations, table names, modules, cmdlets, KQL titles, or API |
| Evidence plane | `evidence_plane` (all 14 planes listed; planes with no entries show 0) |
| Microsoft product | `product_id` |
| Evidence type | `evidence_type` |
| Automatic or configured | `configuration_required` |
| Availability | `availability` |
| Investigation relevance | `relevance_tags` |
| Acquisition method | The acquisition path of each command, mapped with the same rule as Poster 2, or "No documented PowerShell method" |
| Destination or repository | Patterns in `presentation.json` > `site.destinations`, matched against `preservation_options` |
| Verification status | `verification.status` |
| Publication priority | `priority` |
| PowerShell acquisition documented (checkbox) | `powershell.supported` |
| License-dependent (checkbox) | `LICENSE` flag or a `licensing_dependency` value |

Results group by evidence plane (default), by product, or not at all. With no filters active, planes that have no entries yet are listed as "Not yet catalogued in this release", matching Poster 1. Each active filter appears as a removable button above the results. The result count is a polite live region.

Evidence card: plane number and name, priority, source name (link), product and evidence type, first sentence of the description, availability codes and label, PowerShell method, and verification status. Replaced entries name their successor.

## Evidence source detail

Header: plane, source name, product (link), evidence type, verification status, availability codes, priority. A retiring or replaced entry shows a banner naming the successor.

A facts grid follows (product, type, availability, configuration required, native retention, Log Analytics mode, PowerShell method, acquisition path, last verified), then these sections, each linked from an "On this page" list:

1. About the product: the product summary from `products.json`, its Microsoft Learn link, and product notes
2. What it records: description, evidence documentation link, notes
3. Availability and prerequisites: availability, each code with its meaning, configuration required and notes, licensing and deployment dependencies
4. Where to investigate: where and portal path
5. Preservation and retention: native retention, retention notes, whether a diagnostic setting applies, preservation options, matched destinations
6. Log Analytics tables: mode, then each table with its mode, notes, and sources
7. Investigation relevance: the relevance statements and tags (each tag links to the filtered Explore view)
8. Roles and permissions: context, role or permission, source
9. PowerShell acquisition: method, modules, output formats, the acquisition warning, then every command with its role, API status, acquisition path, purpose, copyable example, interface, paging and limits, notes, and sources. Commands that change configuration are marked as not being acquisition steps.
10. API acquisition: name, status, copyable endpoint, notes, sources
11. Example KQL: copyable queries with their tables and sources
12. Limitations
13. Related evidence: pivots from and into the entry, each with type, description, and pivot fields
14. Verification: status and meaning, last verified date, open gaps, priority and poster placement
15. Official Microsoft references: every source the entry and its pivots cite, with document type, verification method, date, and URL

Any value Microsoft does not document is shown as **Verification required**, never filled in. Unverified commands, tables, permissions, queries, and pivots carry the same marker.

## Relationships

Relationships come only from `data/relationships.json`. Each shows `from`, the relationship type, and `to`, the description, and the fields to pivot on. The pivots page and every entry page repeat that relationships say where to look next and never that one event caused another.

## Accessibility

Target: WCAG 2.2 AA.

- Landmarks (header, navigation, main, footer), a skip link, one `h1` per view, and headings in order. Section regions on detail pages are named by their headings; on the print view they are not, because titles repeat across entries.
- After navigation, focus moves to the page heading and the document title names the page.
- Every filter is a native, labelled form control; hints are tied with `aria-describedby`. Result counts and copy confirmations are announced through live regions.
- Status never relies on color alone: verification status carries a symbol and its name, availability codes are text with distinct border styles (solid, dashed, dotted), and planes show their number and name beside their color.
- Light and dark themes follow the operating system, with a toggle (System, Light, Dark). Both meet AA contrast in automated checks.
- Body text is 16 px; no critical evidence detail is smaller than 14 px. Layout reflows to one column at 390 px with no horizontal page scroll; wide tables and code scroll inside their own containers.
- Visible focus outlines; smooth scrolling only when reduced motion is not requested.
- Print stylesheet removes navigation, filters, and buttons and forces a light palette.

## Testing done for this release

Run locally with Playwright and axe-core against a local server (not committed):

- All 46 tested addresses (every page, every entry, every product, a bare `#acquisition` fragment, and an unknown address) render a heading with no console errors, failed requests, external requests, duplicate ids, or links outside Microsoft Learn.
- Explore shows all 22 entries; each filter option's count matches the cards shown; filter state survives a reload from the address; removing a filter button works.
- axe-core reports no violations on 11 representative views in light and dark at 390 px and 1360 px.
- No horizontal overflow at 390 px on any tested view.
- Skip link moves focus to main content; navigation moves focus to the new heading; the theme toggle cycles System, Light, Dark.
- The print view prints every entry (118 Letter pages for 22 entries).
