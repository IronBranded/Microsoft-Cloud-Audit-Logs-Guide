# Contributing

Contributions are welcome when they keep the catalog accurate and traceable.

## Rules

- **Official Microsoft documentation only.** Every claim needs a source in `data/sources.json`. Microsoft Q&A answers, blogs, and community posts are not accepted as authority.
- **Do not guess.** Write `Verification required` and add a gap instead of filling a field from memory.
- **Microsoft-only scope.** Third-party products never appear as evidence sources.
- **One source of truth.** Change facts in `data/`, never directly in poster or site files.
- **No tenant data.** No tenant IDs, subscription IDs, real GUIDs, email addresses, keys, SAS tokens, or customer information. Use placeholders such as `<workspace-id>`. The validator scans for these.
- **Neutral relevance.** Describe what evidence can show; never infer intent, compromise, or maliciousness from an event alone.

## Before opening a pull request

```powershell
pwsh ./scripts/validate-catalog.ps1
```

Commit the regenerated `reports/validation-report.md`. CI runs the same check and the weekly link check.

See [docs/verification.md](docs/verification.md) and [docs/terminology.md](docs/terminology.md).
