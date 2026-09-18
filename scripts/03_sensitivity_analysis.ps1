<#
.SYNOPSIS
    Reproduces the search-sensitivity analysis reported in Table 2.

.DESCRIPTION
    Treats the AI-focused studies cited in references.bib as a quasi-gold
    standard, following Zhang, Babar and Tell (2011), and measures how many of
    them each search-string set retrieves.

    Two string sets are compared:
      1. The six protocol strings (Table 3), measured against the committed
         search log rather than by re-querying.
      2. Four broader, category-aligned strings, queried live against OpenAlex.
         These were piloted but never screened; they exist to show the trade-off
         between recall and screening volume.

    A study counts as retrieved if its DOI matches, or if its normalised title
    matches. Title matching is needed because the two remaining preprints carry
    no DOI.

.NOTES
    Live queries mean the broader-string figures will drift as OpenAlex is
    updated. The paper reports the 17 September 2026 snapshot: 5,816 records and
    15 of 34 studies recovered.
#>

[CmdletBinding()]
param(
    [string]$DataDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$MailTo = 'seminar@example.org',
    [string]$FromDate = '2019-01-01',
    [string]$ToDate   = '2026-12-31',
    [switch]$SkipLiveQueries
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$DateFilter = "from_publication_date:$FromDate,to_publication_date:$ToDate,"

function Get-NormalisedTitle {
    param([string]$Text)
    return (($Text -replace '[^a-zA-Z0-9 ]', '' -replace '\s+', ' ').ToLower().Trim())
}

# --- Build the quasi-gold standard from the AI-focused half of references.bib --
$bibLines = Get-Content (Join-Path $DataDirectory 'references.bib')
$marker   = ($bibLines | Select-String -Pattern 'AI in project and software project management' |
             Select-Object -First 1).LineNumber
if (-not $marker) { throw "Could not locate the AI-focused section header in references.bib" }

$aiSection = ($bibLines[($marker - 1)..($bibLines.Count - 1)]) -join "`n"

$known = @()
foreach ($entry in [regex]::Matches($aiSection, '(?s)@(\w+)\{([^,]+),(.*?)\n\}')) {
    $body  = $entry.Groups[3].Value

    # One entry in this block is a supporting, non-AI source (Appendix B marks it
    # with an asterisk). It is tagged in references.bib and excluded here so the
    # gold standard matches the 34 AI-focused studies reported in Section 3.1.
    if ($body -match 'keywords\s*=\s*\{[^}]*supporting-not-ai') { continue }

    $title = if ($body -match 'title\s*=\s*\{(.+?)\},?\s*\n') { $Matches[1] -replace '[{}]', '' } else { '' }
    $doi   = if ($body -match 'doi\s*=\s*\{([^}]+)\}') { $Matches[1].ToLower() } else { '' }
    $known += [pscustomobject]@{
        Key             = $entry.Groups[2].Value
        NormalisedTitle = Get-NormalisedTitle $title
        Doi             = $doi
    }
}
Write-Host "Quasi-gold standard: $($known.Count) AI-focused studies" -ForegroundColor Cyan
Write-Host "(one supporting non-AI source in the same bibliography block is excluded)`n" -ForegroundColor DarkGray

function Test-IsKnown {
    param([string]$Doi, [string]$Title)
    $d = ($Doi -replace 'https://doi.org/', '').ToLower()
    $t = Get-NormalisedTitle $Title
    foreach ($k in $known) {
        if (($k.Doi -and $k.Doi -eq $d) -or ($k.NormalisedTitle -and $k.NormalisedTitle -eq $t)) {
            return $k.Key
        }
    }
    return $null
}

# --- Set 1: the protocol strings, measured against the committed search log ----
$log  = Import-Csv (Join-Path $DataDirectory 'searchlog_dedup.csv')
$hits = @()
foreach ($row in $log) {
    $k = Test-IsKnown -Doi $row.doi -Title $row.title
    if ($k -and $hits -notcontains $k) { $hits += $k }
}
'{0,-52}{1,7}  {2,3} of {3}' -f 'Protocol strings S1-S6 (from committed log)', $log.Count, $hits.Count, $known.Count |
    Write-Host
if ($hits) { Write-Host "    retrieved: $($hits -join ', ')" -ForegroundColor DarkGray }

if ($SkipLiveQueries) {
    Write-Host "`nSkipping live broader-string queries (-SkipLiveQueries)." -ForegroundColor Yellow
    return
}

# --- Set 2: the four broader, category-aligned strings (piloted, not screened) --
$broad = [ordered]@{
    'Effort and cost estimation with ML' =
        '("software effort estimation" OR "software cost estimation" OR "software development effort") AND ("machine learning" OR "artificial intelligence" OR "neural network")'
    'Generative AI and developer productivity' =
        '("Copilot" OR "code generation" OR "AI pair programmer" OR "AI coding assistant" OR "generative AI") AND (productivity OR "developer") AND ("software engineering" OR "software development")'
    'Software defect prediction with ML' =
        '"software defect prediction" AND ("machine learning" OR "deep learning")'
    'AI in project management, success and decisions' =
        '("artificial intelligence" OR "machine learning") AND ("project management" OR "software project") AND (success OR "success factors" OR "decision making" OR scheduling OR risk)'
}

Write-Host ""
$totalYield = 0
$allBroadHits = @()

foreach ($label in $broad.Keys) {
    $query = $broad[$label]
    $yield = -1
    $found = @()

    # Four pages of 200 is enough to cover the recall these strings achieve;
    # the point of the analysis is the trade-off, not exhaustive retrieval.
    for ($page = 1; $page -le 4; $page++) {
        $filter = $DateFilter + [uri]::EscapeDataString("title_and_abstract.search:$query")
        $uri = "https://api.openalex.org/works" +
               "?per-page=200&page=$page&mailto=$MailTo&select=doi,display_name&filter=$filter"
        try { $body = (Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 120).Content }
        catch { Write-Warning "Query failed on page $page for '$label'"; break }

        if ($yield -lt 0 -and $body -match '"count"\s*:\s*(\d+)') { $yield = [int]$Matches[1] }

        $json = $body | ConvertFrom-Json
        foreach ($r in $json.results) {
            $k = Test-IsKnown -Doi $r.doi -Title $r.display_name
            if ($k -and $found -notcontains $k) { $found += $k }
        }
        if ($json.results.Count -lt 200) { break }
    }

    $totalYield += $yield
    foreach ($f in $found) { if ($allBroadHits -notcontains $f) { $allBroadHits += $f } }
    '{0,-52}{1,7}  {2,3}' -f "  $label", $yield, $found.Count | Write-Host
}

Write-Host ("{0,-52}{1,7}  {2,3} of {3}" -f '  Broader strings, total', $totalYield, $allBroadHits.Count, $known.Count)
Write-Host "`nPaper reports: protocol 233 / 2 of 34; broader 5,816 / 15 of 34 (17 September 2026)." -ForegroundColor DarkGray
