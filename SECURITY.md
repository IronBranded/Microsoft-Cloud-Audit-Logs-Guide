# Security

## Reporting

If you find credentials, tenant identifiers, customer data, or other sensitive information in this repository, report it privately through GitHub's private vulnerability reporting for this repository instead of opening a public issue.

## What this repository must never contain

- Credentials, keys, tokens, connection strings, or SAS signatures
- Tenant, subscription, workspace, or object identifiers from real environments
- Customer, user, or incident data
- Output from real acquisitions

`scripts/validate-catalog.ps1` scans all data files for GUIDs, email addresses, storage keys, SAS signatures, and secret assignments, and fails on any match.

## Scope of the scripts

The scripts in `scripts/` validate this repository's data and check public Microsoft Learn links. They do not connect to any tenant. PowerShell examples in the catalog are reference material; run them only with authorization, and record the acquisition context (scope, UTC time, collecting identity, permissions, tool version, and file hashes).
