# Microsoft Cloud Audit Logs Guide

A reference that helps cloud DFIR learners and defenders find their way around Microsoft cloud evidence: which log or data source answers a question, whether it exists by default or had to be turned on before the incident, where to look for it, and how to retrieve it with PowerShell. It is built on Microsoft Learn documentation, and every fact links to the Microsoft Learn page it comes from.

**[Open the interactive guide](https://ironbranded.github.io/Microsoft-Cloud-Audit-Logs-Guide/)** · [Offline copy (one HTML file)](https://ironbranded.github.io/Microsoft-Cloud-Audit-Logs-Guide/microsoft-cloud-audit-logs-guide-offline.html) · [Poster 1 (PDF)](posters/poster-1-evidence-map/poster-1-evidence-map.pdf) · Poster 2 [Sheet A (PDF)](posters/poster-2-powershell-acquisition/poster-2a-powershell-acquisition.pdf) and [Sheet B (PDF)](posters/poster-2-powershell-acquisition/poster-2b-powershell-acquisition.pdf)

## Who it is for

- **Cloud DFIR learners** who want a structured view of Microsoft's evidence sources and the Microsoft Learn pages that explain each one.
- **Defenders** (incident responders, threat hunters, SOC analysts, and security engineers) who need to know quickly where evidence lives, whether it should exist, and how to collect it.

## What it helps you answer

For each evidence source:

1. What is it, and which Microsoft product produces it?
2. When is it relevant to an investigation?
3. Is it available automatically, or did collection, auditing, licensing, or deployment have to be in place before the activity?
4. Where do you look for it, and how do you acquire it with PowerShell or another Microsoft interface?

> **No evidence does not automatically mean no activity occurred.** Before drawing a conclusion, establish whether the evidence was generated, whether collection or auditing needed configuration, whether it was configured at the time, where it was routed, what retention applied, whether it still exists, and whether you had permission to retrieve it.

## What the project contains

| Item | What you get |
|---|---|
| [Interactive guide](https://ironbranded.github.io/Microsoft-Cloud-Audit-Logs-Guide/) | Search and filter every evidence source by product, evidence plane, evidence type, availability, investigation relevance, acquisition method, destination, and licensing. Each source has its own page: what the product is, what the evidence records, prerequisites, where to investigate, retention, Log Analytics tables, required permissions, PowerShell and API acquisition with copyable examples, example KQL, limitations, related evidence to pivot to, and its Microsoft Learn references. |
| [Poster 1: Microsoft Cloud Forensic Evidence Map](posters/poster-1-evidence-map/poster-1-evidence-map.pdf) | One 48 x 36 in sheet: which evidence to examine, whether it should exist, and when it is relevant. |
| Poster 2: Microsoft Cloud Forensic Evidence Acquisition, [Sheet A](posters/poster-2-powershell-acquisition/poster-2a-powershell-acquisition.pdf) and [Sheet B](posters/poster-2-powershell-acquisition/poster-2b-powershell-acquisition.pdf) | Two 48 x 36 in sheets: how PowerShell reaches each evidence source, with permissions, prerequisites, output formats, and limits. Sheet A covers Azure PowerShell and Azure Monitor; Sheet B covers Microsoft Graph, Windows event logs, Defender, and Microsoft 365. |
| [Acquisition guidance](docs/acquisition-guidance.md) | What to record for every acquisition, which output formats to keep, and how to check that a result is complete. |
| [Terminology](docs/terminology.md) | How the guide uses terms such as Activity Log, Resource Logs, diagnostic settings, and Microsoft Sentinel, so evidence types are not confused. |
| [Evidence catalog (JSON)](data/evidence-catalog.json) | The data behind everything above, for your own tools and notebooks. |

The interactive guide also works offline: open `site/index.html` from this repository, or save the single-file offline copy.

## Built on Microsoft Learn

- Product descriptions, availability, retention, table names, cmdlets, permissions, and limitations all come from Microsoft Learn, and each links to its page. The guide's [References page](https://ironbranded.github.io/Microsoft-Cloud-Audit-Logs-Guide/#/references) lists every page used and the date it was checked.
- Where Microsoft Learn does not document a detail, the guide says **Verification required** instead of guessing.
- Each evidence source shows its verification status: **Verified**, **Conditional** (usable, with the open gaps listed), or **Retiring or replaced** (with its successor).
- Evidence is labeled by type. Audit logs are kept distinct from sign-in logs, resource logs, Windows events, security telemetry, alerts and incidents, platform metrics, and collection or correlation layers such as diagnostic settings, Log Analytics, and Microsoft Sentinel.
- Microsoft products only. Third-party tools are not listed.

## Evidence sources and Microsoft Learn references

<!-- BEGIN evidence-sources: generated by scripts/update-readme.ps1 from data/. Do not edit by hand. -->
22 evidence sources from 14 Microsoft products, grouped by evidence plane. Each row links to the product's Microsoft Learn overview (**What is**) and to the Microsoft Learn page that documents the evidence itself (**Evidence**). Catalog last checked against Microsoft Learn on 2026-10-13.

**Availability** says whether the evidence exists without preparation. Anything other than "Automatic" means something had to be configured, licensed, deployed, or requested before the activity happened.

### 01. Identity

| Evidence source | Product | Evidence type | Availability | Microsoft Learn |
|---|---|---|---|---|
| Audit logs | Microsoft Entra ID | Audit | Automatic with limited native retention | What is: [What is Microsoft Entra?](https://learn.microsoft.com/entra/fundamentals/what-is-entra)<br>Evidence: [Audit logs in Microsoft Entra ID](https://learn.microsoft.com/entra/identity/monitoring-health/concept-audit-logs) |
| Sign-in logs | Microsoft Entra ID | Sign-in | Automatic with limited native retention | What is: [What is Microsoft Entra?](https://learn.microsoft.com/entra/fundamentals/what-is-entra)<br>Evidence: [What are Microsoft Entra sign-in logs?](https://learn.microsoft.com/entra/identity/monitoring-health/concept-sign-ins) |

### 02. Azure Control Plane

| Evidence source | Product | Evidence type | Availability | Microsoft Learn |
|---|---|---|---|---|
| Azure Activity Log | Azure Monitor | Control plane | Automatic with limited native retention | What is: [Azure Monitor overview](https://learn.microsoft.com/azure/azure-monitor/fundamentals/overview)<br>Evidence: [Activity log in Azure Monitor](https://learn.microsoft.com/azure/azure-monitor/platform/activity-log) |

### 03. Azure Resource and Data Plane

| Evidence source | Product | Evidence type | Availability | Microsoft Learn |
|---|---|---|---|---|
| Azure Resource Logs | Azure Monitor | Resource/data plane | Configuration required | What is: [Azure Monitor overview](https://learn.microsoft.com/azure/azure-monitor/fundamentals/overview)<br>Evidence: [Resource logs in Azure Monitor](https://learn.microsoft.com/azure/azure-monitor/platform/resource-logs) |
| Key Vault resource logs (AuditEvent) | Azure Key Vault | Resource/data plane | Configuration required | What is: [About Azure Key Vault](https://learn.microsoft.com/azure/key-vault/general/overview)<br>Evidence: [Azure Key Vault logging](https://learn.microsoft.com/azure/key-vault/general/logging) |
| Storage resource logs (StorageRead, StorageWrite, StorageDelete) | Azure Storage | Resource/data plane | Configuration required | What is: [Introduction to Azure Storage](https://learn.microsoft.com/azure/storage/common/storage-introduction)<br>Evidence: [Monitor Azure Blob Storage](https://learn.microsoft.com/azure/storage/blobs/monitor-blob-storage) |
| Platform metrics | Azure Monitor | Platform metric | Automatic with limited native retention | What is: [Azure Monitor overview](https://learn.microsoft.com/azure/azure-monitor/fundamentals/overview)<br>Evidence: [Azure Monitor Metrics overview](https://learn.microsoft.com/azure/azure-monitor/metrics/data-platform-metrics) |

### 04. Azure Network and Remote Access

| Evidence source | Product | Evidence type | Availability | Microsoft Learn |
|---|---|---|---|---|
| Azure Firewall resource logs | Azure Firewall | Network | Configuration required | What is: [What is Azure Firewall?](https://learn.microsoft.com/azure/firewall/overview)<br>Evidence: [Monitor Azure Firewall](https://learn.microsoft.com/azure/firewall/monitor-firewall) |
| Virtual network flow logs | Azure Network Watcher | Network | Configuration required | What is: [What is Azure Network Watcher?](https://learn.microsoft.com/azure/network-watcher/network-watcher-overview)<br>Evidence: [Virtual network flow logs](https://learn.microsoft.com/azure/network-watcher/vnet-flow-logs-overview) |
| Application Gateway WAF firewall log | Azure Web Application Firewall on Azure Application Gateway | Network | Configuration required | What is: [What is Azure Web Application Firewall on Azure Application Gateway?](https://learn.microsoft.com/azure/web-application-firewall/ag/ag-overview)<br>Evidence: [Diagnostic logs for Application Gateway](https://learn.microsoft.com/azure/application-gateway/application-gateway-diagnostics) |
| Network security group (NSG) flow logs (retiring; use Virtual network flow logs) | Azure Network Watcher | Network | Configuration required | What is: [What is Azure Network Watcher?](https://learn.microsoft.com/azure/network-watcher/network-watcher-overview)<br>Evidence: [Flow logging for network security groups](https://learn.microsoft.com/azure/network-watcher/nsg-flow-logs-overview) |

### 05. Windows and Compute

| Evidence source | Product | Evidence type | Availability | Microsoft Learn |
|---|---|---|---|---|
| PowerShell Operational logs (script block and module logging) | PowerShell (Windows PowerShell 5.1 and PowerShell 7) | Windows event | Auditing policy dependent | What is: [PowerShell security features](https://learn.microsoft.com/powershell/scripting/security/security-features)<br>Evidence: [about_Logging (Windows PowerShell 5.1)](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_logging?view=powershell-5.1) |
| Security event log | Windows (Windows Event Log) | Windows event | Auditing policy dependent | What is: [Advanced Audit Policy Configuration](https://learn.microsoft.com/windows-server/identity/ad-ds/plan/security-best-practices/advanced-audit-policy-configuration)<br>Evidence: [Advanced Audit Policy Configuration](https://learn.microsoft.com/windows-server/identity/ad-ds/plan/security-best-practices/advanced-audit-policy-configuration) |

### 07. Microsoft Defender Antivirus

| Evidence source | Product | Evidence type | Availability | Microsoft Learn |
|---|---|---|---|---|
| Microsoft-Windows-Windows Defender/Operational event log | Microsoft Defender Antivirus | Security telemetry | Automatic | What is: [Microsoft Defender Antivirus in Windows Overview](https://learn.microsoft.com/defender-endpoint/microsoft-defender-antivirus-windows)<br>Evidence: [Review event logs and error codes to troubleshoot issues with Microsoft Defender Antivirus](https://learn.microsoft.com/defender-endpoint/troubleshoot-microsoft-defender-antivirus) |
| Defender Antivirus diagnostic support package (MpSupportFiles.cab) | Microsoft Defender Antivirus | Support diagnostic | On demand | What is: [Microsoft Defender Antivirus in Windows Overview](https://learn.microsoft.com/defender-endpoint/microsoft-defender-antivirus-windows)<br>Evidence: [Collect Microsoft Defender Antivirus diagnostic data](https://learn.microsoft.com/defender-endpoint/collect-diagnostic-data) |

### 08. Microsoft Defender for Endpoint

| Evidence source | Product | Evidence type | Availability | Microsoft Learn |
|---|---|---|---|---|
| Advanced hunting device tables (endpoint telemetry) | Microsoft Defender for Endpoint | Security telemetry | Deployment dependent | What is: [Microsoft Defender for Endpoint overview](https://learn.microsoft.com/defender-endpoint/microsoft-defender-endpoint)<br>Evidence: [Proactively hunt for threats with advanced hunting in Microsoft Defender](https://learn.microsoft.com/defender-xdr/advanced-hunting-overview) |
| Microsoft-Windows-SENSE/Operational event log | Microsoft Defender for Endpoint | Windows event | Deployment dependent | What is: [Microsoft Defender for Endpoint overview](https://learn.microsoft.com/defender-endpoint/microsoft-defender-endpoint)<br>Evidence: [Review events and errors using Event Viewer](https://learn.microsoft.com/defender-endpoint/event-error-codes) |

### 10. Microsoft 365 and Purview Audit

| Evidence source | Product | Evidence type | Availability | Microsoft Learn |
|---|---|---|---|---|
| Unified audit log | Microsoft Purview Audit | Audit | Automatic | What is: [Learn about auditing solutions in Microsoft Purview](https://learn.microsoft.com/purview/audit-solutions-overview)<br>Evidence: [Search the audit log](https://learn.microsoft.com/purview/audit-search) |

### 13. Microsoft Security and Defender XDR

| Evidence source | Product | Evidence type | Availability | Microsoft Learn |
|---|---|---|---|---|
| Incidents and alerts | Microsoft Defender XDR | Incident | Licensing dependent | What is: [What is Microsoft Defender XDR?](https://learn.microsoft.com/defender-xdr/microsoft-365-defender)<br>Evidence: [List incidents](https://learn.microsoft.com/graph/api/security-list-incidents?view=graph-rest-1.0) |

### 14. Correlation, Collection, and Preservation

| Evidence source | Product | Evidence type | Availability | Microsoft Learn |
|---|---|---|---|---|
| Diagnostic Settings | Azure Monitor | Collection configuration | Configuration required | What is: [Azure Monitor overview](https://learn.microsoft.com/azure/azure-monitor/fundamentals/overview)<br>Evidence: [Diagnostic settings in Azure Monitor](https://learn.microsoft.com/azure/azure-monitor/platform/diagnostic-settings) |
| Log Analytics workspace (Azure Monitor Logs) | Azure Monitor | Repository | Configuration required | What is: [Azure Monitor overview](https://learn.microsoft.com/azure/azure-monitor/fundamentals/overview)<br>Evidence: [Log Analytics workspace overview](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-workspace-overview) |
| Microsoft Sentinel analytics, alerts, and incidents | Microsoft Sentinel | Correlation layer | Deployment dependent | What is: [What is Microsoft Sentinel security information and event management (SIEM)?](https://learn.microsoft.com/azure/sentinel/overview)<br>Evidence: [What is Microsoft Sentinel security information and event management (SIEM)?](https://learn.microsoft.com/azure/sentinel/overview) |

**Not yet covered:** Enhanced Windows Telemetry, Containers and Applications, Power Platform and Dynamics 365, Microsoft Intune. No entry is published until it is checked against Microsoft Learn documentation.
<!-- END evidence-sources -->

## Disclaimer

This is an independent investigator-focused reference based on publicly available Microsoft documentation. It is not an official Microsoft publication. Microsoft product capabilities, licensing, APIs, retention, and log schemas can change. Always verify current behavior in official Microsoft documentation.

To update or rebuild the guide, see [docs/maintaining.md](docs/maintaining.md) and [CONTRIBUTING.md](CONTRIBUTING.md).
