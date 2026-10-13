# Verification method

Every fact in the catalog must trace to official Microsoft documentation through `data/sources.json`. Nothing is inferred to fill a gap; an unconfirmed detail is written as `Verification required` and recorded as a gap.

## Accepted sources

Microsoft Learn (including Microsoft Graph, PowerShell, Azure Monitor reference, Purview, Defender, and Windows documentation). Microsoft Q&A answers, blogs, and community posts are not used as authority, even when they are hosted on a Microsoft domain.

## How a URL was verified

| `verification_method` | Meaning |
|---|---|
| Fetched page | The full page was retrieved and read. |
| Search result | The URL is the canonical address of an official Microsoft Learn search hit whose content was read. |
| Linked from verified page | The URL was taken from a link on a verified official page. Its title and reachability are confirmed by `scripts/check-links.ps1`. An entry that relies on such a source cannot be marked Verified. |

## Entry statuses

| Status | Rule enforced by `validate-catalog.ps1` |
|---|---|
| Verified | No open gaps; no `Verification required` text anywhere in the entry; every command, permission, table, and KQL example is marked verified; no link-only sources. |
| Conditional | At least one documented gap. Everything stated is sourced; the gaps list what is not yet confirmed. |
| Verification required | The entry is a placeholder with gaps that block use. |
| Deprecated or replaced | The feature is retiring or replaced; `replaced_by` names the successor entry. |

## Accuracy gates and where they are checked

| Gate | Checked by |
|---|---|
| Product: current name, overview URL | `products.json` `what_is_source_id`; reference check |
| Evidence: documented, correctly typed, not a configuration mechanism | Schema enums; terminology rules |
| Availability: automatic vs configured, licensing, deployment, policy | Availability-label consistency check |
| Investigation: relevance supported by documented fields or purpose | Reviewer; every relevance line must be sourced from the entry's references |
| Location: portal path, Log Analytics table, legacy vs resource-specific | Table `verified` flags; collection-mode consistency check |
| Acquisition: cmdlet, module, API status, permissions, paging | Command and permission `verified` flags; retired-interface check |
| Retention: only when explicitly documented | Reviewer; `native_retention` states "not documented" when no value is published |
| Publication: no guessed URLs, no duplicates, no third-party products, dates present | URL pattern; duplicate checks; link check; freshness warning |

## Adding or updating an entry

1. Add every new URL to `data/sources.json` with its verification method and date.
2. Fill every required field. Use `Verification required` rather than a guess, and add a matching gap.
3. Set `verification.status` honestly; the validator rejects a Verified entry with open items.
4. Run `pwsh ./scripts/validate-catalog.ps1` and commit the regenerated report.
5. Run `pwsh ./scripts/build-posters.ps1 -Pdf` and commit the rebuilt posters.
6. Run `pwsh ./scripts/build-site.ps1` and commit the regenerated `site/`. Then run `pwsh ./scripts/publish-site.ps1`, which refuses to publish while `site/` has uncommitted changes.
7. For a new product, add a `summary` to `data/products.json` that paraphrases the opening of its Microsoft Learn overview (the page named by `what_is_source_id`), and nothing beyond it.

## Poster checks

`scripts/build-posters.ps1` checks its own output against the catalog on every build:

- Every entry flagged `publication.poster_1` appears on Poster 1 exactly once, and no unflagged entry appears.
- Every command of every entry flagged `publication.poster_2` appears exactly once across the Poster 2 sheets.
- Every link on either poster is a URL registered in `data/sources.json`.
- With `-Pdf`, each poster is laid out in a headless browser and must fit one 48 x 36 in page; the build fails on overflow instead of silently clipping content.

Facts never come from the build script. It reads only `data/`, and `data/presentation.json` holds presentation copy (titles, legends, colors, path names), not product facts.

## Site checks

`scripts/build-site.ps1` checks the data the site depends on before writing anything:

- Every reference in `data/sources.json` is an `https://learn.microsoft.com/` URL. The site renders outbound links only from this list, by source id.
- Every evidence plane used by a site entry has a presentation entry with a valid color.
- Every command maps to one of the six acquisition paths, with the same rule as Poster 2.
- Every destination pattern in `presentation.json` compiles, names only existing entries, and matches at least one entry (a warning otherwise).
- Every relationship endpoint exists and every product has a summary.
- `site/index.html`, `site/js/`, and `site/css/` contain no external URL, so the site makes no network requests.

The output is deterministic, so rebuilding unchanged data leaves `site/` unchanged.
