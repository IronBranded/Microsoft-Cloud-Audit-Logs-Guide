# Maintaining the guide

How the catalog is organized, checked, rebuilt, and published. For the rules every change must follow, see [CONTRIBUTING.md](../CONTRIBUTING.md) and [verification.md](verification.md).

## One source of truth

The posters, the interactive site, and the evidence list in the README are all generated from `data/`. Facts are never written directly into a poster, the site, or the README.

| File | Holds |
|---|---|
| `data/evidence-catalog.json` | One entry per evidence source: availability, configuration, licensing, retention, Log Analytics tables, investigation relevance, PowerShell and API acquisition, permissions, limitations, verification status, and open gaps |
| `data/products.json` | Microsoft products, their primary evidence plane, a summary of what each product is (from its Microsoft Learn overview), and the Microsoft Learn link printed on Poster 1 |
| `data/sources.json` | Every Microsoft Learn URL used anywhere, with how and when it was verified |
| `data/relationships.json` | Evidence pivots between entries (for example, Activity Log to Resource Logs on resource ID) |
| `data/presentation.json` | Titles, legends, plane colors, acquisition paths, site destination groupings, and methodology statements shared by the posters and the site. No product facts. |
| `schema/evidence-catalog.schema.json` | JSON Schema (2020-12) for the data files |

An entry is **Verified** only when it has no open gaps. **Conditional** entries list exactly what is still unconfirmed; that list is the verification backlog.

## Scripts

Requires PowerShell 7.4 or later. No third-party modules.

```powershell
pwsh ./scripts/validate-catalog.ps1   # schema, accuracy gates, terminology rules, sensitive-data scan; writes reports/validation-report.md
pwsh ./scripts/check-links.ps1        # every source URL resolves on Microsoft Learn and still matches its title
pwsh ./scripts/build-posters.ps1 -Pdf # builds Poster 1 and both Poster 2 sheets, checks them against the catalog, prints single-page PDFs
pwsh ./scripts/build-site.ps1         # regenerates site/data, site/css/planes.css, and the offline single-file copy
pwsh ./scripts/update-readme.ps1      # regenerates the evidence list in README.md
pwsh ./scripts/publish-site.ps1       # validates, rebuilds, and pushes the committed site/ to the gh-pages branch
```

- `build-posters.ps1` fails if a poster is missing a flagged entry or command, links to a URL that is not in `data/sources.json`, or overflows its 48 x 36 in page. `-Pdf` and `-Png` need a Chromium-based browser (Edge or Chrome); pass `-BrowserPath` if it is not found. The posters use the Inter typeface when it is installed.
- `build-site.ps1` fails if a reference is not a Microsoft Learn URL, a command has no acquisition path, a destination pattern is broken, or the site's own HTML, JavaScript, or CSS contains an external URL. Its output is deterministic.
- `update-readme.ps1` rewrites only the section between the evidence-sources markers in `README.md`.

## Update workflow

1. Change `data/` and add any new Microsoft Learn URL to `data/sources.json`.
2. Rebuild and check:

   ```powershell
   pwsh ./scripts/validate-catalog.ps1
   pwsh ./scripts/build-posters.ps1 -Pdf -Png
   pwsh ./scripts/build-site.ps1
   pwsh ./scripts/update-readme.ps1
   ```

3. Commit and push to `main`.
4. Publish the site: `pwsh ./scripts/publish-site.ps1`.

## Publishing the site

The site is published with GitHub Pages from the `gh-pages` branch, without GitHub Actions.

- `publish-site.ps1` validates the catalog, rebuilds the site, refuses to continue if `site/` has uncommitted changes, and force-pushes the `site/` folder of `main` to `gh-pages` with `git subtree split`. Never edit `gh-pages` by hand.
- One-time repository setting: **Settings > Pages > Build and deployment > Source: Deploy from a branch**, branch `gh-pages`, folder `/ (root)`. GitHub Pages on a free plan needs a public repository.
- `site/.nojekyll` turns off Jekyll processing so files are served as committed.
- `.gitattributes` keeps LF line endings on every platform, so a rebuild on Windows matches what is committed.

The site makes no network requests, uses no cookies or analytics, and stores only the light or dark theme choice in the browser. Its design and behavior are specified in [site-spec.md](site-spec.md).

## Optional GitHub Actions

`.github/workflows/` holds three checks: data validation on changes, a weekly Microsoft Learn link check, and poster builds. None of them publishes anything. Delete the folder if you do not want Actions.
