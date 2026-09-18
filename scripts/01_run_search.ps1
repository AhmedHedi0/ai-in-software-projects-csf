<#
.SYNOPSIS
    Executes the six protocol search strings against OpenAlex and writes the
    raw and deduplicated search logs.

.DESCRIPTION
    Reproduces the identification and deduplication stages of the scoped
    systematic literature review reported in Section 3.2 and Figure 1 of the
    seminar paper.

    PROVENANCE NOTE
    ---------------
    The original search was executed on 6 September 2026 as a sequence of
    interactive PowerShell commands, not from this file. This script was written
    afterwards to reproduce those commands exactly: the same six strings, the
    same OpenAlex endpoint, the same filters and the same deduplication rule.
    It is a faithful reproduction of what was run, not the literal artefact that
    produced the committed CSVs.

    WHY OPENALEX
    ------------
    Scopus and Web of Science require institutional subscriptions, and IEEE
    Xplore, the ACM Digital Library, ScienceDirect, SpringerLink and Google
    Scholar block automated querying. OpenAlex aggregates records from those
    publishers and exposes a public REST API, so any reader can replicate this
    search without institutional access.

.OUTPUTS
    searchlog_raw.csv    One row per record returned, tagged with its search string.
    searchlog_dedup.csv  Records remaining after removing duplicate OpenAlex identifiers.

.NOTES
    Counts drift as OpenAlex is updated. The committed CSVs are the 6 September
    2026 snapshot on which the paper's figures are based. Re-running this script
    will not necessarily reproduce 233 records; record the date of any re-run.

    KNOWN PITFALL: some OpenAlex JSON responses contain keys differing only in
    case (for example 'To' and 'to'), which makes PowerShell 5.1's
    ConvertFrom-Json throw. Result counts are therefore extracted by regex from
    the raw response body, and record retrieval uses the 'select' parameter to
    request only the fields needed, which avoids the offending fields.
#>

[CmdletBinding()]
param(
    # OpenAlex asks for a contact address so it can route you to the polite pool.
    [string]$MailTo = 'seminar@example.org',

    [string]$OutputDirectory = (Split-Path -Parent $PSScriptRoot),

    [string]$FromDate = '2019-01-01',
    [string]$ToDate   = '2026-12-31'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# --- The six protocol search strings, exactly as stated in Table 3 -------------
$SearchStrings = [ordered]@{
    'S1' = '"artificial intelligence" AND "project success" AND "software project"'
    'S2' = '"project management" AND "critical success factors" AND "artificial intelligence"'
    'S3' = '"machine learning" AND "software project management" AND success'
    'S4' = '"generative artificial intelligence" AND "software development" AND productivity'
    'S5' = '"artificial intelligence" AND "software project planning"'
    'S6' = '"artificial intelligence" AND "software project" AND "risk management"'
}

$DateFilter    = "from_publication_date:$FromDate,to_publication_date:$ToDate,"
$SelectFields  = 'id,doi,display_name,publication_year,type,primary_location'

function Get-OpenAlexPage {
    param(
        [Parameter(Mandatory)][string]$Query,
        [int]$Page = 1,
        [int]$PerPage = 200
    )
    $filter = $DateFilter + [uri]::EscapeDataString("title_and_abstract.search:$Query")
    $uri    = "https://api.openalex.org/works" +
              "?per-page=$PerPage&page=$Page&mailto=$MailTo&select=$SelectFields&filter=$filter"
    return (Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 120).Content
}

Write-Host "Search executed: $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host "Window: $FromDate to $ToDate`n"

$all = New-Object System.Collections.Generic.List[object]

foreach ($id in $SearchStrings.Keys) {
    $query = $SearchStrings[$id]
    $page  = 1
    $count = -1
    $retrieved = 0

    do {
        $body = Get-OpenAlexPage -Query $query -Page $page

        # Total hits: read by regex, because ConvertFrom-Json can fail on this payload.
        if ($count -lt 0 -and $body -match '"count"\s*:\s*(\d+)') {
            $count = [int]$Matches[1]
        }

        $json = $body | ConvertFrom-Json
        foreach ($r in $json.results) {
            $all.Add([pscustomobject]@{
                query = $id
                id    = ($r.id  -replace 'https://openalex.org/', '')
                doi   = ($r.doi -replace 'https://doi.org/',      '')
                year  = $r.publication_year
                type  = $r.type
                venue = $r.primary_location.source.display_name
                title = $r.display_name
            })
        }
        $retrieved += $json.results.Count
        $page++
    } while ($json.results.Count -eq 200)

    '{0}  yield={1,5}  retrieved={2,5}   {3}' -f $id, $count, $retrieved, $query | Write-Host
}

$rawPath = Join-Path $OutputDirectory 'searchlog_raw.csv'
$all | Export-Csv -Path $rawPath -NoTypeInformation -Encoding UTF8
Write-Host "`nTotal records identified : $($all.Count)"

# --- Deduplication stage 1: identical OpenAlex identifiers --------------------
# Stage 2 (duplicate titles under different identifiers) is handled during
# screening and recorded as reason code E6 in the screening CSVs.
$dedup = $all | Group-Object id | ForEach-Object { $_.Group[0] }

$dedupPath = Join-Path $OutputDirectory 'searchlog_dedup.csv'
$dedup | Export-Csv -Path $dedupPath -NoTypeInformation -Encoding UTF8
Write-Host "Unique after ID deduplication : $($dedup.Count)"
Write-Host "`nWrote:`n  $rawPath`n  $dedupPath"
