<#
.SYNOPSIS
    Derives every screening number reported in Figure 1 from the committed
    search log and screening decisions.

.DESCRIPTION
    Recomputes the PRISMA-style flow of the scoped systematic literature review
    from searchlog_raw.csv, searchlog_dedup.csv and the three screening batch
    files, and checks the result against the counts printed in the paper.

    Screening itself was a judgement task carried out against the inclusion and
    exclusion criteria in Appendix A; it is not reproducible by script. The
    decisions are recorded per record in screening_batch1-3.csv, and this script
    only aggregates them.

    Exclusion reason codes used during screening:
      E1  not about AI, machine learning or data-driven methods
      E2  AI/ML study with no software-project or project-management link
      E3  project-management study in a clearly non-IT domain
      E4  not a research contribution (editorial, front matter, erratum)
      E5  not in English
      E6  duplicate title of another record (a second deduplication stage)

.OUTPUTS
    Console report. Exits non-zero if any figure disagrees with the paper.
#>

[CmdletBinding()]
param(
    [string]$DataDirectory = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

# Counts as printed in the paper, for verification.
$Expected = @{
    Identified = 233
    Screened   = 194
    Excluded   = 37
    Retained   = 157
}

$raw    = Import-Csv (Join-Path $DataDirectory 'searchlog_raw.csv')
$dedup  = Import-Csv (Join-Path $DataDirectory 'searchlog_dedup.csv')

$screen = @()
1..3 | ForEach-Object {
    $screen += Import-Csv (Join-Path $DataDirectory "screening_batch$_.csv")
}

# Reason codes were sometimes annotated, e.g. "E6 (duplicate of W123)".
# Normalise to the bare code.
function Get-ReasonCode {
    param([string]$Reason)
    if ($Reason -match '^(E\d)') { return $Matches[1] }
    return $null
}

$identified   = $raw.Count
$idDuplicates = $raw.Count - $dedup.Count

$excluded     = $screen | Where-Object { $_.decision -eq 'EXCLUDE' }
$codes        = $excluded | ForEach-Object { Get-ReasonCode $_.reason }

$titleDuplicates = ($codes | Where-Object { $_ -eq 'E6' }).Count
$topicExcluded   = ($codes | Where-Object { $_ -ne 'E6' }).Count
$retained        = ($screen | Where-Object { $_.decision -eq 'INCLUDE' }).Count

$totalDuplicates = $idDuplicates + $titleDuplicates
$screened        = $identified - $totalDuplicates

Write-Host "PRISMA flow, recomputed from the committed data" -ForegroundColor Cyan
Write-Host "-----------------------------------------------"
'{0,-46}{1,6}' -f 'Records identified by database search',      $identified
'{0,-46}{1,6}' -f '  duplicate OpenAlex identifiers removed',   $idDuplicates
'{0,-46}{1,6}' -f '  duplicate titles removed (code E6)',       $titleDuplicates
'{0,-46}{1,6}' -f 'Records screened on title',                  $screened
'{0,-46}{1,6}' -f 'Records excluded at screening',              $topicExcluded

foreach ($c in ($codes | Where-Object { $_ -ne 'E6' } | Group-Object | Sort-Object Name)) {
    '{0,-46}{1,6}' -f "    $($c.Name)", $c.Count
}

'{0,-46}{1,6}' -f 'Records retained after title screening',     $retained

Write-Host "`nVerification against the figures printed in the paper" -ForegroundColor Cyan
Write-Host "-----------------------------------------------------"

$checks = @(
    @{ Label = 'Identified'; Actual = $identified; Expected = $Expected.Identified }
    @{ Label = 'Screened';   Actual = $screened;   Expected = $Expected.Screened   }
    @{ Label = 'Excluded';   Actual = $topicExcluded; Expected = $Expected.Excluded }
    @{ Label = 'Retained';   Actual = $retained;   Expected = $Expected.Retained   }
)

$failed = $false
foreach ($c in $checks) {
    $ok = $c.Actual -eq $c.Expected
    if (-not $ok) { $failed = $true }
    '{0,-14} computed {1,5}   paper {2,5}   {3}' -f `
        $c.Label, $c.Actual, $c.Expected, $(if ($ok) { 'OK' } else { 'MISMATCH' }) |
        Write-Host -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
}

# Arithmetic closure: the flow must balance.
$balances = ($identified - $totalDuplicates - $topicExcluded) -eq $retained
Write-Host ("`nFlow balances ({0} - {1} - {2} = {3}): {4}" -f `
    $identified, $totalDuplicates, $topicExcluded, $retained, $balances) `
    -ForegroundColor $(if ($balances) { 'Green' } else { 'Red' })

if ($failed -or -not $balances) { exit 1 }
Write-Host "`nAll figures reconcile." -ForegroundColor Green
