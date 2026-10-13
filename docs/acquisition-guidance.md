# Acquisition and preservation guidance

How to record an acquisition so someone else can tell what was collected, from where, by whom, and how completely. The checklist and format guidance below are the same text shown on Poster 2 and on the site's Acquisition page; both come from `data/presentation.json` (`acquisition_record`, `output_guidance`, `chain_of_custody_note`).

> PowerShell acquisition cannot recreate telemetry that was never generated, enabled, collected, retained, or made accessible to the investigator.

## Record for every acquisition

1. Source system and scope: tenant, subscription, workspace, resource, or device
2. Query or filter used, including the time range
3. UTC acquisition start and end time
4. Collecting account or application identity, and its permission context
5. Tool, module, or API name and version
6. Original output format and any export format
7. How pagination and result limits were handled
8. Errors, throttling, and retries
9. Known completeness limitations
10. Hash of every file produced (for example, SHA-256)

Each evidence source's page on the site (and its card on Poster 2) lists the permission, paging rule, result limits, and known limitations to note for items 4, 7, and 9.

## Output formats

| Format | Use |
|---|---|
| JSON | APIs and structured cloud results; keeps nested properties |
| CSV | Analyst-friendly tables; flatten only after keeping the raw JSON |
| EVTX | Windows event channels in their original form |
| CLIXML | Only when PowerShell object fidelity matters |
| TXT | Human-readable supporting output, never the sole evidence format |

Preserve structured raw results before creating summaries. An export mechanism does not establish legal chain of custody by itself; it is one input to your organization's evidence-handling procedure.

## Completeness checks before you rely on a result

- **Was it collected at the time?** Resource Logs, flow logs, Windows audit subcategories, PowerShell script block logging, and Sysmon exist for a period only if collection was configured during that period. A configuration you find today says nothing about last month unless its change history does (see the Azure Activity Log and Diagnostic Settings entries).
- **Is the window still retained?** Compare the time range with the native retention on the entry and with any retention configured at the destination.
- **Did paging finish?** Use the command's documented paging (`-All`, `NextPageUri`, `@odata.nextLink`, `-SessionCommand ReturnLargeSet`, and so on). Where the catalog says paging is **Verification required**, compare record counts across smaller time windows.
- **Did a limit truncate the result?** Azure Monitor log queries stop at documented row, size, and time limits; narrow the time range or use a search job for large windows.
- **Did the identity see everything?** Missing permissions, scoped roles, or licensing can return partial results without an error.

## Example: write an acquisition manifest

A minimal pattern, run in the same PowerShell 7 session as the acquisition. `Get-FileHash`, `Get-Date`, and `ConvertTo-Json` are built in; `Get-MgContext` (Microsoft Graph PowerShell) and `Get-AzContext` (Az PowerShell) return the signed-in identity and scope for those modules. Keep manifests and evidence in your case store, never in this repository.

```powershell
$started = Get-Date -AsUTC

# ... run the acquisition command from the evidence source's page, writing raw JSON or EVTX to .\evidence\ ...

$finished = Get-Date -AsUTC
$manifest = [ordered]@{
    case_reference   = '<case id>'
    evidence_source  = 'entra-audit-logs'            # catalog entry id
    query            = '<exact filter and time range>'
    started_utc      = $started.ToString('o')
    finished_utc     = $finished.ToString('o')
    identity         = (Get-MgContext | Select-Object Account, AppName, AuthType, Scopes)
    host_powershell  = $PSVersionTable.PSVersion.ToString()
    modules          = Get-Module | Select-Object Name, Version
    paging           = '<how paging was completed, record counts per page or window>'
    errors           = @($Error | Select-Object -First 20 | ForEach-Object { $_.ToString() })
    limitations      = '<known completeness limits>'
    files            = Get-ChildItem .\evidence -File | Get-FileHash -Algorithm SHA256 |
                       Select-Object @{ n = 'file'; e = { Split-Path $_.Path -Leaf } }, Algorithm, Hash
}
$manifest | ConvertTo-Json -Depth 6 | Out-File .\evidence\acquisition-manifest.json -Encoding utf8
Get-FileHash .\evidence\acquisition-manifest.json -Algorithm SHA256
```

For Azure PowerShell acquisitions, record `Get-AzContext | Select-Object Account, Subscription, Tenant` instead of `Get-MgContext`. For a device, record the computer name, the event channel, and the `wevtutil epl` command used.
