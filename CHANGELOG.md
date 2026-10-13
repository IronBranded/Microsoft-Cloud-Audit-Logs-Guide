# Changelog

## 0.3.4 (2026-10-13): README start section and fixes

- README opens with a "Start here" section: a prominent link to the interactive guide, how to use the offline copy, and clickable previews of the three posters.
- `build-posters.ps1 -Png` also writes an 864 x 648 px preview of each poster (`*-thumb.png`) for the README, and no longer deletes the current Poster 2 PDFs and previews when it runs without `-Pdf` or `-Png`.
- `publish-site.ps1` stops with a clear message when the folder is not a Git repository or has no remote.
- `build-site.ps1` writes LF line endings on every platform, so a rebuild on Windows produces the same files as on Linux.

## 0.3.3 (2026-10-13): README focused on purpose

- README rewritten for cloud DFIR learners and defenders: what the guide is for, what it helps answer, what the project contains, how it relies on Microsoft Learn, and every evidence source with its Microsoft Learn "What is" and evidence documentation links.
- The evidence list in the README is generated from the catalog by `scripts/update-readme.ps1`, so it cannot drift from the posters and the site.
- Build, validation, and publishing instructions moved to `docs/maintaining.md`.

## 0.3.2 (2026-10-13): Renamed to Microsoft Cloud Audit Logs Guide

- Project renamed from Microsoft Cloud Forensics Map to Microsoft Cloud Audit Logs Guide, matching the repository https://github.com/IronBranded/Microsoft-Cloud-Audit-Logs-Guide. The site, poster mastheads, README, schema id, and scripts use the new name; poster titles are unchanged.
- The offline single-file copy is now `site/microsoft-cloud-audit-logs-guide-offline.html`. The site's data global is `window.GUIDE_DATA` and its theme storage key is `guide-theme`.
- README states the scope: audit logs plus the sign-in, resource, endpoint, telemetry, metric, and correlation evidence that investigators pair with them, each labeled by evidence type.

## 0.3.1 (2026-10-13): Publish without GitHub Actions

- The site now publishes from the `gh-pages` branch with `scripts/publish-site.ps1` (validate, rebuild, refuse uncommitted `site/` changes, `git subtree split`, push). Removed the `deploy-pages.yml` workflow.
- `build-site.ps1` writes the offline single-file copy into `site/` by default, so GitHub Pages serves it and the readiness page links to it.
- Added `site/.nojekyll`.

## 0.3.0 (2026-10-13): Phase 3, interactive map

- Interactive map in `site/` for GitHub Pages: search and 12 filters (plane, product, type, automatic or configured, availability, relevance, acquisition method, destination, verification status, priority, PowerShell documented, license-dependent), grouping by plane or product, shareable filtered addresses, and full detail pages for every evidence source and product. Further pages cover the six acquisition paths, Log Analytics tables, pivots, readiness and legends, every Microsoft Learn reference, and a print view.
- `scripts/build-site.ps1` generates the site's data layer from `data/` and checks it: Microsoft Learn URLs only, an acquisition path for every command, valid destination patterns, and no external URLs in the site's code. `-Bundle` writes one offline HTML file.
- Products now carry a one- or two-sentence summary of what each product is, paraphrased from its Microsoft Learn overview (`products.json` `summary`, required by the schema).
- `data/presentation.json` gains a `site` section: title, tagline, and the destination groupings used by the destination filter.
- New workflow `deploy-pages.yml`; new docs `docs/site-spec.md` (interactive map specification) and `docs/acquisition-guidance.md`.
- Accessibility: keyboard and screen reader support, focus management, light and dark themes, no color-only status, 390 px layout without horizontal scrolling. No axe-core violations on the tested views in either theme.

## 0.2.1 (2026-10-13): Poster 2 split into two sheets

- Poster 2 is now two 48 x 36 in sheets, split by API family so both are equally full (about 91%): Sheet A, Azure PowerShell and Azure Monitor (paths 1 and 3); Sheet B, Microsoft Graph, endpoints, and Microsoft 365 (paths 2, 4, 5, 6). The split and each sheet's side panels are set in `data/presentation.json` (`posters.poster_2.sheets`).
- Body text on Poster 2 rises from about 10 pt to 13.5 pt and code from 8.6 pt to 11.4 pt. Each sheet repeats the acquisition warning and legends so it stands alone; cross-references name the other sheet.
- The build now checks that every Poster 2 command appears exactly once across both sheets, reports how full each sheet's columns are, and warns when a sheet passes 95%.

## 0.2.0 (2026-10-13): Phase 2, gaps closed and posters

- Verification gaps cut from 42 to 9; 13 of 22 entries are now Verified. The remaining gaps are undocumented paging behavior (beta sign-ins, Activity Log REST, Graph audit records, Get-AzSentinelIncident), whether diagnostic-setting changes reach the Activity Log, a Key Vault documentation contradiction, flow-log blob permissions and schema, and one coverage query that is not from Microsoft documentation.
- Added Azure RBAC read roles (Monitoring Reader, Microsoft Sentinel Reader), the Logs query and Metrics REST endpoints, Azure Monitor query limits, central Windows event collection (Azure Monitor Agent to Event; Sentinel connector to SecurityEvent), verified Windows Security event IDs, Graph directory audit filters and paging, the Graph Audit Search API and its cmdlets, the Management Activity API workflow, Exchange Online connection, flow-log blob download, Sentinel incident tables and cmdlets, and Defender for Endpoint plan requirements.
- Replaced the archived Windows auditing overview with the current Advanced Audit Policy Configuration page. Corrected the canonical URLs of the diagnostic settings and service limits articles.
- 153 official Microsoft Learn sources; none rely on a link alone.
- `data/presentation.json` and `scripts/build-posters.ps1`: Poster 1 and Poster 2 generated from the catalog as HTML and single-page 48 x 36 in PDFs, with consistency, link, and fit checks. New workflow: `build-posters.yml`.

## 0.1.0 (2026-10-13): Phase 1, catalog foundation

- JSON Schema (2020-12) for the evidence catalog, products, sources, and relationships.
- 22 evidence entries across 10 evidence planes and 14 products, checked against Microsoft Learn on 2026-10-13: 18 Core, 4 Extended. Status: 1 Verified, 20 Conditional (42 documented gaps), 1 Deprecated or replaced.
- 109 official Microsoft Learn sources, each recorded with how it was verified.
- 22 evidence relationships.
- `scripts/validate-catalog.ps1`: schema validation, reference integrity, accuracy gates, availability-label consistency, publication rules, terminology rules, retired-interface check, sensitive-data scan; generates `reports/validation-report.md`.
- `scripts/check-links.ps1` and GitHub Actions workflows for validation and weekly link checks.
