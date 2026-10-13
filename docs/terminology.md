# Terminology

These rules apply to the catalog, both posters, and the site. Rules marked (checked) are enforced by `scripts/validate-catalog.ps1`.

| Term | Use | Avoid |
|---|---|---|
| Azure Activity Log | Azure management (control-plane) evidence, collected automatically, 90-day native retention. | Describing it as a record of every operation inside a resource. It does not typically capture reads. |
| Azure Resource Logs | "Azure resources generate Resource Logs, but Azure Monitor does not collect them by default. A Diagnostic Setting or another documented collection configuration must exist for historical collection." | "Diagnostic logs" as the primary name, except to explain that Microsoft renamed them. (checked) |
| Diagnostic Settings | A collection and routing configuration. | Calling it a log or an evidence source. (checked) |
| Platform metrics | Automatically collected numeric time series; supporting timeline context. | Treating metrics as audit evidence. |
| Log Analytics | A storage, query, and investigation environment for collected Azure Monitor Logs. | Assuming every Resource Log is in `AzureDiagnostics`; most services use resource-specific tables. (checked) |
| Microsoft Sentinel | SIEM, investigation, analytics, and correlation layer. | Presenting Sentinel as the original producer of evidence. (checked) |
| Defender evidence | Security telemetry, alerts, incidents, advanced hunting data, detection evidence, endpoint telemetry. | Calling all Defender evidence an audit log. |
| Defender Antivirus vs Defender for Endpoint | Separate products and separate evidence planes. | Merging them. (checked) |
| Support diagnostics | On-demand troubleshooting packages, such as the Defender Antivirus support package. | Treating them as equivalent to continuous event channels. |
| Windows Security log | Audit depth is policy dependent. (checked) | Implying events exist regardless of audit policy. |
| Sysmon | Configuration required. (checked once Sysmon entries are added) | Implying it is present by default. |
